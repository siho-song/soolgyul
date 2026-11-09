-- The service keeps only wine, whisky, sake and korean_traditional. Every
-- other category leaves the service DB: its products (with tasting profiles
-- and media rows), saved interests, post tags and category rows. Catalog
-- terms are append-only, so rules that applied only to removed categories
-- are switched off and the rest drop those keys. The removed data is archived
-- outside the service (manual-import/archive/2026-10-29_excluded_categories).
create temporary table removed_category on commit drop as
select id, category_key, interest_key
from public.alcohol_categories
where category_key not in ('wine', 'whisky', 'sake', 'korean_traditional');

delete from public.user_drink_interests
where interest_key in (select interest_key from removed_category);

delete from public.editorial_article_interests
where interest_key in (select interest_key from removed_category);

delete from public.catalog_media_assets media
using public.alcohol_items item
where item.id = media.alcohol_item_id
  and item.alcohol_category_id in (select id from removed_category);

delete from public.alcohol_tasting_profiles profile
using public.alcohol_items item
where item.id = profile.alcohol_item_id
  and item.alcohol_category_id in (select id from removed_category);

delete from public.alcohol_items
where alcohol_category_id in (select id from removed_category);

update public.catalog_terms term
set is_active = false
where term.is_active
  and jsonb_typeof(term.metadata -> 'applies_to_categories') = 'array'
  and not exists (
    select 1
    from jsonb_array_elements_text(term.metadata -> 'applies_to_categories') category_key
    where category_key not in (select category_key from removed_category)
  );

update public.catalog_terms term
set metadata = jsonb_set(
  term.metadata,
  '{applies_to_categories}',
  (
    select jsonb_agg(category_key)
    from jsonb_array_elements_text(term.metadata -> 'applies_to_categories') category_key
    where category_key not in (select category_key from removed_category)
  )
)
where term.is_active
  and jsonb_typeof(term.metadata -> 'applies_to_categories') = 'array'
  and term.metadata -> 'applies_to_categories' ?| array(select category_key from removed_category);

delete from public.alcohol_categories
where id in (select id from removed_category);
