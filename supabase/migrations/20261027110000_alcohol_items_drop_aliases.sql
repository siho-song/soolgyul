-- alcohol_items.aliases goes. It duplicated search_keywords (both fed the
-- same search fold) and held 50,645 leftover packaging and old-spelling
-- strings nobody curated; decided 2026-10-27 to keep search_keywords only.
-- The search fold column is generated from the dropped column, so it is
-- rebuilt without it; the catalog search projection keeps its column shape
-- and now lists search_keywords alone.

drop index if exists public.alcohol_items_aliases_idx;
drop index if exists public.alcohol_items_published_aliases_lower_idx;
drop index if exists public.alcohol_items_published_search_fold_trgm_idx;

alter table public.alcohol_items drop column search_fold_text;
alter table public.alcohol_items drop column aliases;

alter table public.alcohol_items
  add column search_fold_text text generated always as (
    public.soolgyul_fold_korean_sound(name_ko)
    || ' ' || public.soolgyul_fold_korean_sound(coalesce(name_en, ''))
    || ' ' || public.soolgyul_fold_korean_sound_array(search_keywords)
    || ' ' || public.soolgyul_fold_korean_sound_array(regexp_split_to_array(name_ko, '\s+'))
  ) stored;

create index alcohol_items_published_search_fold_trgm_idx
  on public.alcohol_items using gin (search_fold_text extensions.gin_trgm_ops)
  where publish_status = 'published';

comment on function public.soolgyul_search_alcohol_catalog(text, integer) is
  'Searches active published alcohol products on a sound-folded form of names and search keywords (soolgyul_fold_korean_sound), so Korean transliteration variants match.';

create or replace function public.soolgyul_catalog_search_projection_rows_v1()
returns table(alcohol_item_id uuid, alcohol_release_id uuid, display_name text, secondary_name text, producer_or_brand_display text, category_key text, subcategory_key text, style_key text, country_code text, region_display text, abv_percent numeric, search_aliases text[], descriptor_keys text[], is_active boolean, published_at timestamp with time zone, updated_at timestamp with time zone)
language sql stable security definer
set search_path to ''
as $$
 select i.id,null::uuid,i.name_ko,i.name_en,null::text,c.category_key,null::text,i.style_key,
 i.country_code,i.region,i.abv_percent,
 coalesce(a.search_aliases,array[]::text[]),coalesce(t.descriptor_keys,array[]::text[]),
 true,i.published_at,i.updated_at
 from public.alcohol_items i join public.alcohol_categories c on c.id=i.alcohol_category_id and c.is_active
 left join lateral (
  select array_agg(distinct public.soolgyul_normalize_catalog_text(v) order by public.soolgyul_normalize_catalog_text(v)) search_aliases
  from unnest(i.search_keywords) v where nullif(btrim(v),'') is not null
 ) a on true
 left join lateral (
  select array_agg(distinct v order by v) descriptor_keys
  from public.alcohol_tasting_profiles p
  cross join lateral unnest(p.aroma_tags||p.palate_tags||p.finish_tags) v
  where p.alcohol_item_id=i.id
 ) t on true
 where i.publish_status='published'
$$;
