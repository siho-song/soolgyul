-- A post is its photos and one text, like a post on a social network. The
-- title and summary were shown to no reader once the feed became covers
-- only; the recommended order went unused as the feed is newest first; the
-- cover is simply the first photo, so the cover role and the "cover in the
-- gallery" switch go; and a photo's alt text, caption, size and type had no
-- input in the admin.

-- 1. The cover becomes the first photo of the gallery.
update public.editorial_article_media_assets
set sort_order = case when asset_role = 'cover' then 0 else sort_order + 1 end;

drop index if exists public.editorial_article_one_cover_idx;
drop index if exists public.editorial_article_media_order_idx;

alter table public.editorial_article_media_assets
  drop column asset_role,
  drop column alt_text,
  drop column caption,
  drop column width,
  drop column height,
  drop column media_type;

create index editorial_article_media_order_idx
  on public.editorial_article_media_assets (article_id, sort_order);

comment on table public.editorial_article_media_assets is
  'A post''s photos in gallery order; the first one is the cover. flutter-assets is allowed only for bundled fixtures.';

-- 2. A post keeps its text, status, interests and Instagram address.
alter table public.editorial_articles
  drop column title,
  drop column summary,
  drop column featured_rank,
  drop column cover_in_gallery;

comment on table public.editorial_articles is
  'Administrator-authored posts: photos swiped through in order plus a plain text with line breaks.';

-- 3. The admin save RPC takes what is left.
drop function public.soolgyul_admin_save_editorial_article(
  uuid, text, text, text, integer, text, text[], boolean, text
);

create function public.soolgyul_admin_save_editorial_article(
  article_id uuid,
  article_body text,
  article_status text,
  interest_keys text[],
  instagram_link text default null
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
    insert into public.editorial_articles (body, status, instagram_url)
    values (
      coalesce(article_body, ''),
      article_status,
      nullif(btrim(instagram_link), '')
    )
    returning id into saved_id;
  else
    update public.editorial_articles
    set body = coalesce(article_body, ''),
        status = article_status,
        instagram_url = nullif(btrim(instagram_link), '')
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
  uuid, text, text, text[], text
) from public;
grant execute on function public.soolgyul_admin_save_editorial_article(
  uuid, text, text, text[], text
) to authenticated, service_role;
