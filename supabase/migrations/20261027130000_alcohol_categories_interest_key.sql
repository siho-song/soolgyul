-- The sixteen drink interests a user can pick were a second taxonomy
-- (alcohol_interest_groups) mapped onto alcohol_categories through a third
-- table. Every interest is one category, except 'other', which covers the two
-- 'other_*' categories; decided 2026-10-27 to fold the interest into
-- alcohol_categories.interest_key (null = the category is not offered as an
-- interest) and to store interests by key wherever they are referenced.

alter table public.alcohol_categories
  add column interest_key text
    constraint alcohol_categories_interest_key_check
    check (interest_key ~ '^[a-z][a-z0-9_]*$');

comment on column public.alcohol_categories.interest_key is
  'Drink-interest key this category is offered under (user interests, editorial links). Null when the category is not an interest choice; the two other_* categories share ''other''.';

update public.alcohol_categories category
set interest_key = interest_group.interest_group_key
from public.alcohol_interest_group_categories link
join public.alcohol_interest_groups interest_group
  on interest_group.id = link.alcohol_interest_group_id
where link.alcohol_category_id = category.id;

-- user_drink_interests: key instead of group id. The group table's
-- "selected" read policy looked at the group id column, so it goes first.

drop policy alcohol_interest_groups_selected_read on public.alcohol_interest_groups;

alter table public.user_drink_interests add column interest_key text;

update public.user_drink_interests selection
set interest_key = interest_group.interest_group_key
from public.alcohol_interest_groups interest_group
where interest_group.id = selection.alcohol_interest_group_id;

alter table public.user_drink_interests
  alter column interest_key set not null,
  drop constraint user_drink_interests_pkey,
  drop column alcohol_interest_group_id,
  add constraint user_drink_interests_pkey primary key (user_id, interest_key),
  add constraint user_drink_interests_interest_key_check
    check (interest_key ~ '^[a-z][a-z0-9_]*$');

comment on table public.user_drink_interests is
  'Owner interest selections by alcohol_categories.interest_key, at most five per user. Mutations go through soolgyul_replace_my_drink_interests.';

create or replace function public.soolgyul_enforce_drink_interest_limit() returns trigger
language plpgsql security definer
set search_path to ''
as $$
begin
  if exists (
    select 1
    from public.user_drink_interests current_selection
    where current_selection.user_id = new.user_id
      and current_selection.interest_key = new.interest_key
  ) then
    return new;
  end if;

  perform 1
  from public.users product_user
  where product_user.id = new.user_id
  for update;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'interest_owner_not_found';
  end if;

  if (
    select count(*)
    from public.user_drink_interests current_selection
    where current_selection.user_id = new.user_id
  ) >= 5 then
    raise exception using
      errcode = '23514',
      message = 'drink_interest_limit_exceeded';
  end if;

  return new;
end
$$;

create or replace function public.soolgyul_get_my_profile_preferences() returns jsonb
language plpgsql stable security definer
set search_path to ''
as $$
declare
  target_user_id uuid;
  current_display_name text;
  current_interest_keys text[];
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  if not public.soolgyul_account_active(target_user_id) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  select profile.display_name
  into current_display_name
  from public.users profile
  where profile.id = target_user_id;

  select coalesce(
    array_agg(
      selection.interest_key
      order by interest.sort_order, selection.interest_key
    ),
    array[]::text[]
  )
  into current_interest_keys
  from public.user_drink_interests selection
  left join lateral (
    select min(category.sort_order) as sort_order
    from public.alcohol_categories category
    where category.interest_key = selection.interest_key
  ) interest on true
  where selection.user_id = target_user_id;

  return jsonb_build_object(
    'display_name', current_display_name,
    'interest_group_keys', to_jsonb(current_interest_keys)
  );
end
$$;

create or replace function public.soolgyul_replace_my_drink_interests(p_interest_group_keys text[], p_idempotency_key uuid) returns jsonb
language plpgsql security definer
set search_path to ''
as $$
declare
  target_user_id uuid;
  normalized_interest_keys text[];
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'idempotency_key_required';
  end if;
  if p_interest_group_keys is null
    or cardinality(p_interest_group_keys) < 1
    or cardinality(p_interest_group_keys) > 5
  then
    raise exception using errcode = '22023', message = 'drink_interest_count_invalid';
  end if;
  if array_position(p_interest_group_keys, null) is not null
    or (
      select count(distinct interest_key)
      from unnest(p_interest_group_keys) interest_key
    ) <> cardinality(p_interest_group_keys)
  then
    raise exception using errcode = '22023', message = 'drink_interest_keys_invalid';
  end if;

  select array_agg(interest.interest_key order by interest.sort_order, interest.interest_key)
  into normalized_interest_keys
  from (
    select category.interest_key, min(category.sort_order) as sort_order
    from public.alcohol_categories category
    where category.is_active
      and category.interest_key = any(p_interest_group_keys)
    group by category.interest_key
  ) interest;

  if cardinality(coalesce(normalized_interest_keys, array[]::text[]))
    <> cardinality(p_interest_group_keys)
  then
    raise exception using errcode = '22023', message = 'drink_interest_keys_invalid';
  end if;

  perform 1
  from public.users product_user
  where product_user.id = target_user_id
    and product_user.disabled_at is null
    and product_user.deletion_requested_at is null
    and product_user.deletion_scheduled_at is null
    and product_user.purged_at is null
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  delete from public.user_drink_interests selection
  where selection.user_id = target_user_id
    and selection.interest_key <> all(normalized_interest_keys);

  insert into public.user_drink_interests (user_id, interest_key)
  select target_user_id, chosen.interest_key
  from unnest(normalized_interest_keys) with ordinality as chosen(interest_key, position)
  where not exists (
    select 1
    from public.user_drink_interests current_selection
    where current_selection.user_id = target_user_id
      and current_selection.interest_key = chosen.interest_key
  )
  order by chosen.position;

  return jsonb_build_object('interest_group_keys', to_jsonb(normalized_interest_keys));
end
$$;

-- editorial_article_interest_groups: renamed, keyed by interest_key.

alter table public.editorial_article_interest_groups rename to editorial_article_interests;
alter table public.editorial_article_interests
  rename constraint editorial_article_interest_groups_article_id_fkey
  to editorial_article_interests_article_id_fkey;

alter table public.editorial_article_interests add column interest_key text;

update public.editorial_article_interests link
set interest_key = interest_group.interest_group_key
from public.alcohol_interest_groups interest_group
where interest_group.id = link.alcohol_interest_group_id;

alter table public.editorial_article_interests
  alter column interest_key set not null,
  drop constraint editorial_article_interest_groups_pkey,
  drop column alcohol_interest_group_id,
  add constraint editorial_article_interests_pkey primary key (article_id, interest_key),
  add constraint editorial_article_interests_interest_key_check
    check (interest_key ~ '^[a-z][a-z0-9_]*$');

create index editorial_article_interests_interest_key_idx
  on public.editorial_article_interests (interest_key, article_id);

comment on table public.editorial_article_interests is
  'Drink interests (alcohol_categories.interest_key) an editorial article is about.';

create or replace function public.soolgyul_related_editorial_articles(p_article_id uuid, p_result_limit integer default 10)
returns table(article_id uuid, relevance_score integer)
language sql stable security definer
set search_path to ''
as $$
  with source_article as (
    select article.id, article.category_id
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
        case when candidate.category_id = source.category_id then 10 else 0 end
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

drop function public.soolgyul_admin_save_editorial_article(uuid, uuid, text, text, text, text, text[], integer, boolean, integer, text, uuid[]);

create function public.soolgyul_admin_save_editorial_article(article_id uuid, category_id uuid, article_slug text, article_title text, article_summary text, article_body_markdown text, article_tags text[], read_minutes integer, recommended boolean, feature_rank integer, article_status text, interest_keys text[])
returns uuid
language plpgsql security definer
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
      category_id,
      slug,
      title,
      summary,
      body_markdown,
      tags,
      estimated_read_minutes,
      is_recommended,
      featured_rank,
      status
    )
    values (
      category_id,
      btrim(article_slug),
      btrim(article_title),
      btrim(article_summary),
      article_body_markdown,
      coalesce(article_tags, array[]::text[]),
      read_minutes,
      recommended,
      feature_rank,
      article_status
    )
    returning id into saved_id;
  else
    update public.editorial_articles
    set category_id = soolgyul_admin_save_editorial_article.category_id,
        slug = btrim(article_slug),
        title = btrim(article_title),
        summary = btrim(article_summary),
        body_markdown = article_body_markdown,
        tags = coalesce(article_tags, array[]::text[]),
        estimated_read_minutes = read_minutes,
        is_recommended = recommended,
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

revoke all on function public.soolgyul_admin_save_editorial_article(uuid, uuid, text, text, text, text, text[], integer, boolean, integer, text, text[]) from public;
grant execute on function public.soolgyul_admin_save_editorial_article(uuid, uuid, text, text, text, text, text[], integer, boolean, integer, text, text[]) to service_role, authenticated;

drop table public.alcohol_interest_group_categories;
drop table public.alcohol_interest_groups;
