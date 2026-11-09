-- Posts are no longer sorted into beginner / drink_story / trend. Until the
-- content has a clearer direction, the only grouping readers get is the
-- drink interest tags; a category axis can come back once it is earned.
-- The related-posts function goes with it: the app ranks related posts
-- itself and nothing called it.

alter table public.editorial_articles
  drop constraint editorial_articles_category_check,
  drop column category;

drop function public.soolgyul_related_editorial_articles(uuid, integer);

drop function public.soolgyul_admin_save_editorial_article(
  uuid, text, text, text, text, integer, text, text[], boolean
);

create function public.soolgyul_admin_save_editorial_article(
  article_id uuid,
  article_title text,
  article_summary text,
  article_body text,
  feature_rank integer,
  article_status text,
  interest_keys text[],
  show_cover boolean default true
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
      title, summary, body, featured_rank, status, cover_in_gallery
    )
    values (
      btrim(article_title),
      btrim(article_summary),
      article_body,
      feature_rank,
      article_status,
      coalesce(show_cover, true)
    )
    returning id into saved_id;
  else
    update public.editorial_articles
    set title = btrim(article_title),
        summary = btrim(article_summary),
        body = article_body,
        featured_rank = feature_rank,
        status = article_status,
        cover_in_gallery = coalesce(show_cover, true)
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
  uuid, text, text, text, integer, text, text[], boolean
) from public;
grant execute on function public.soolgyul_admin_save_editorial_article(
  uuid, text, text, text, integer, text, text[], boolean
) to authenticated, service_role;
