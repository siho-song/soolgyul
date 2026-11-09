-- catalog_media_assets carried storage metadata that never varies: live on
-- 2026-10-27 all 58,234 rows sit in bucket alcohol-product-images as
-- image/webp at 512x640, and every path is a unique
-- '{category_key}/{item uuid}.webp'. The bucket name is now a code constant, so
-- the table keeps only the serving path and its publish state.
-- catalog_media_fallbacks held 2,775 borrowed line photos of which only 42
-- served; decided 2026-10-27 that borrowed photos are no longer allowed, so the
-- table goes and those products fall back to the app's category default image.

drop view if exists public.catalog_search_projection_v1;
drop function if exists public.soolgyul_catalog_primary_media_rows_v1();

alter table public.catalog_media_assets
  drop constraint if exists catalog_media_assets_public_storage_check,
  drop constraint if exists catalog_media_assets_storage_bucket_check,
  drop constraint if exists catalog_media_assets_media_type_check,
  drop constraint if exists catalog_media_assets_width_check,
  drop constraint if exists catalog_media_assets_height_check,
  drop constraint if exists catalog_media_assets_storage_bucket_storage_object_path_key,
  drop constraint if exists catalog_media_assets_storage_object_path_check;

alter table public.catalog_media_assets
  drop column if exists storage_bucket,
  drop column if exists media_type,
  drop column if exists width,
  drop column if exists height,
  drop column if exists alt_text,
  drop column if exists attribution_text;

alter table public.catalog_media_assets
  rename column storage_object_path to media_path;

alter table public.catalog_media_assets
  add constraint catalog_media_assets_media_path_key unique (media_path),
  add constraint catalog_media_assets_media_path_check
    check (btrim(media_path) <> ''),
  add constraint catalog_media_assets_media_path_format_check
    check (media_path ~ '^[a-z_]+/[0-9a-f-]{36}\.webp$'),
  add constraint catalog_media_assets_publish_check
    check (publish_status <> 'published' or published_at is not null);

comment on table public.catalog_media_assets is
  'One serving image path per product in the public alcohol-product-images bucket, with publish state.';

drop table if exists public.catalog_media_fallbacks;

create function public.soolgyul_catalog_primary_media_rows_v1()
returns table(catalog_media_asset_id uuid, alcohol_item_id uuid, media_path text)
language sql
stable
security definer
set search_path = ''
as $$
  select media.id, item.id, media.media_path
  from public.alcohol_items item
  join public.catalog_media_assets media on media.alcohol_item_id = item.id
  where item.publish_status = 'published'
    and media.publish_status = 'published'
    and media.published_at is not null
$$;

create view public.catalog_search_projection_v1
with (security_invoker = 'true', security_barrier = 'true') as
select
  search_row.alcohol_item_id,
  search_row.alcohol_release_id,
  search_row.display_name,
  search_row.secondary_name,
  search_row.producer_or_brand_display,
  search_row.category_key,
  search_row.subcategory_key,
  search_row.style_key,
  search_row.country_code,
  search_row.region_display,
  search_row.abv_percent,
  search_row.search_aliases,
  search_row.descriptor_keys,
  search_row.is_active,
  search_row.published_at,
  search_row.updated_at,
  media.catalog_media_asset_id as primary_image_asset_id,
  media.media_path as primary_image_media_path
from public.soolgyul_catalog_search_projection_rows_v1() search_row
left join public.soolgyul_catalog_primary_media_rows_v1() media
  on media.alcohol_item_id = search_row.alcohol_item_id;

-- Recreated objects lose their grants; reissue the net state of the baseline
-- plus 20261013100000_restrict_client_privileges.
revoke all on function public.soolgyul_catalog_primary_media_rows_v1() from public, anon;
grant execute on function public.soolgyul_catalog_primary_media_rows_v1()
  to authenticated, service_role;

grant all on table public.catalog_search_projection_v1 to anon, authenticated, service_role;
