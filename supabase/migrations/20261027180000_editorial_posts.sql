-- Posts are written like social-network posts: photos swiped through in a
-- gallery plus plain text with line breaks, no markdown. The category becomes
-- a fixed three-value column instead of a table; slug, tags, read time, the
-- recommended flag and the actor columns were read by nothing. Interest keys
-- become a real link to alcohol_categories.interest_key, which is unique now
-- that the two 기타 categories carry none: a post about no particular kind
-- simply has no interest rows.

-- 1. Interest keys are 1:1 with categories and enforced by foreign keys.
update public.alcohol_categories
set interest_key = null
where interest_key = 'other';

-- The update queues deferred catalog validation triggers; Postgres refuses to
-- alter the table while they are pending, so run them now.
set constraints all immediate;

alter table public.alcohol_categories
  add constraint alcohol_categories_interest_key_key unique (interest_key);

delete from public.editorial_article_interests where interest_key = 'other';
delete from public.user_drink_interests where interest_key = 'other';

alter table public.editorial_article_interests
  add constraint editorial_article_interests_interest_key_fkey
  foreign key (interest_key) references public.alcohol_categories (interest_key)
  on update cascade;

alter table public.user_drink_interests
  add constraint user_drink_interests_interest_key_fkey
  foreign key (interest_key) references public.alcohol_categories (interest_key)
  on update cascade;

-- 2. The category is a column with a fixed set of values.
alter table public.editorial_articles add column category text;

update public.editorial_articles article
set category = category_row.category_key
from public.editorial_categories category_row
where category_row.id = article.category_id;

alter table public.editorial_articles
  alter column category set not null,
  add constraint editorial_articles_category_check
    check (category in ('beginner', 'drink_story', 'trend')),
  drop column category_id;

drop table public.editorial_categories;

-- 3. Plain-text body. Existing posts lose their heading and bold markers.
alter table public.editorial_articles rename column body_markdown to body;
alter table public.editorial_articles
  rename constraint editorial_articles_body_markdown_check to editorial_articles_body_check;

update public.editorial_articles
set body = regexp_replace(
  regexp_replace(body, '(^|\n)#{1,6}[ \t]+', '\1', 'g'),
  '\*\*([^*]+)\*\*', '\1', 'g'
);

-- 4. Columns nothing reads.
alter table public.editorial_articles
  drop column slug,
  drop column tags,
  drop column estimated_read_minutes,
  drop column is_recommended,
  drop column created_by,
  drop column updated_by,
  drop column published_by;

-- 5. The write trigger only stamps published_at now.
create or replace function public.soolgyul_prepare_admin_editorial_article()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.status = 'published'
     and (
       tg_op = 'INSERT'
       or old.status is distinct from 'published'
       or new.published_at is null
     ) then
    if tg_op = 'UPDATE' and old.status is distinct from 'published' then
      new.published_at := now();
    else
      new.published_at := coalesce(new.published_at, now());
    end if;
  end if;
  return new;
end
$$;

-- 6. Admin save RPC with the new columns.
drop function public.soolgyul_admin_save_editorial_article(
  uuid, uuid, text, text, text, text, text[], integer, boolean, integer, text, text[]
);

create function public.soolgyul_admin_save_editorial_article(
  article_id uuid,
  article_category text,
  article_title text,
  article_summary text,
  article_body text,
  feature_rank integer,
  article_status text,
  interest_keys text[]
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  saved_id uuid;
  is_admin boolean := public.soolgyul_admin_has_role(array['admin']::text[]);
  is_editor boolean := public.soolgyul_admin_has_role(array['editor']::text[]);
begin
  if not is_admin and not is_editor then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if not is_admin and (article_status <> 'draft') then
    raise exception 'editors may save drafts only' using errcode = '42501';
  end if;
  if exists (
    select 1
    from unnest(coalesce(interest_keys, array[]::text[])) as input(interest_key)
    where not exists (
      select 1
      from public.alcohol_categories category
      where category.is_active
        and category.interest_key = input.interest_key
    )
  ) then
    raise exception 'unknown interest key' using errcode = '22023';
  end if;

  if article_id is null then
    insert into public.editorial_articles (
      category, title, summary, body, featured_rank, status
    )
    values (
      article_category,
      btrim(article_title),
      btrim(article_summary),
      article_body,
      feature_rank,
      article_status
    )
    returning id into saved_id;
  else
    update public.editorial_articles
    set category = article_category,
        title = btrim(article_title),
        summary = btrim(article_summary),
        body = article_body,
        featured_rank = feature_rank,
        status = article_status
    where id = article_id
      and (is_admin or (status = 'draft' and published_at is null))
    returning id into saved_id;

    if saved_id is null then
      raise exception 'article is not editable' using errcode = '42501';
    end if;
  end if;

  delete from public.editorial_article_interests
  where editorial_article_interests.article_id = saved_id;

  insert into public.editorial_article_interests (article_id, interest_key)
  select distinct saved_id, input.interest_key
  from unnest(coalesce(interest_keys, array[]::text[])) as input(interest_key);

  return saved_id;
end
$$;

revoke all on function public.soolgyul_admin_save_editorial_article(
  uuid, text, text, text, text, integer, text, text[]
) from public;
grant execute on function public.soolgyul_admin_save_editorial_article(
  uuid, text, text, text, text, integer, text, text[]
) to authenticated, service_role;

-- 7. Related posts compare the category column.
create or replace function public.soolgyul_related_editorial_articles(p_article_id uuid, p_result_limit integer default 10)
returns table(article_id uuid, relevance_score integer)
language sql
stable security definer
set search_path to ''
as $$
  with source_article as (
    select article.id, article.category
    from public.editorial_articles article
    where article.id = p_article_id
      and article.status = 'published'
  ),
  source_interests as (
    select link.interest_key
    from public.editorial_article_interests link
    join source_article source on source.id = link.article_id
  ),
  viewer_interests as (
    select selection.interest_key
    from public.user_drink_interests selection
    where auth.uid() is not null
      and selection.user_id = auth.uid()
  ),
  scored_candidates as (
    select
      candidate.id as article_id,
      (
        case when candidate.category = source.category then 10 else 0 end
        + 5 * (
          select count(*)::integer
          from public.editorial_article_interests candidate_link
          join source_interests source_interest
            on source_interest.interest_key = candidate_link.interest_key
          where candidate_link.article_id = candidate.id
        )
        + 2 * (
          select count(*)::integer
          from public.editorial_article_interests candidate_link
          join viewer_interests viewer_interest
            on viewer_interest.interest_key = candidate_link.interest_key
          where candidate_link.article_id = candidate.id
        )
      )::integer as relevance_score
    from public.editorial_articles candidate
    cross join source_article source
    where candidate.status = 'published'
      and candidate.id <> source.id
  )
  select candidate.article_id, candidate.relevance_score
  from scored_candidates candidate
  order by
    candidate.relevance_score desc,
    md5(p_article_id::text || ':' || candidate.article_id::text)
  limit least(greatest(coalesce(p_result_limit, 10), 1), 10)
$$;
