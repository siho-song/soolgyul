-- alcohol_tasting_profiles carried columns nothing fills or nothing reads.
-- Audited 2026-10-27 against the live data and every reader (card engine,
-- question context RPC, search projection, triggers):
--   body_note, viscosity, flavour_clarity  empty in every row
--   texture_tags                           47 rows, two values, read by nothing
--                                          the card shows
--   sensory_scale                          5 in every row; a gate, never a value
--   locale                                 'ko-KR' in every row, no reader
--   overall_note                           912 rows of leftover text (food
--                                          pairings, generated filler); the
--                                          taste in it already lives in the
--                                          level columns
--   structured_semantics                   derived from the coded notes that
--                                          were dropped; only the old engine's
--                                          candidate selection read it
-- The publish columns went in 20261026120000. The row keeps the nine level
-- columns, level_sources, the four section notes, three section tags and
-- structured_sensory until the new card engine replaces the old one.

-- 1. The content gate no longer counts the dropped columns.
alter table public.alcohol_tasting_profiles
  drop constraint if exists alcohol_tasting_profiles_direct_content_check;
alter table public.alcohol_tasting_profiles
  add constraint alcohol_tasting_profiles_direct_content_check check (
    num_nonnulls(
      nullif(btrim(aroma_note), ''), nullif(btrim(palate_note), ''),
      nullif(btrim(finish_note), ''), nullif(btrim(texture_note), ''),
      sweetness, acidity, bitterness, astringency, body, carbonation,
      aroma_intensity, finish_length, finish_cleanliness) > 0
    or cardinality(aroma_tags || palate_tags || finish_tags) > 0
  );

-- 2. The source snapshot that decides when structured_sensory is stale.
create or replace function public.sensory_source_snapshot(p jsonb)
returns jsonb
language sql
immutable
set search_path to ''
as $$
  select jsonb_build_object(
    'sweetness', p->'sweetness', 'acidity', p->'acidity',
    'bitterness', p->'bitterness', 'astringency', p->'astringency',
    'body', p->'body', 'carbonation', p->'carbonation',
    'aroma_intensity', p->'aroma_intensity',
    'finish_length', p->'finish_length',
    'finish_cleanliness', p->'finish_cleanliness',
    'aroma_note', p->'aroma_note', 'palate_note', p->'palate_note',
    'texture_note', p->'texture_note', 'finish_note', p->'finish_note',
    'aroma_tags', p->'aroma_tags', 'palate_tags', p->'palate_tags',
    'finish_tags', p->'finish_tags');
$$;

create or replace function public.invalidate_product_sensory_facts()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.alcohol_item_id is distinct from old.alcohol_item_id
    or public.sensory_source_snapshot(to_jsonb(new))
      is distinct from public.sensory_source_snapshot(to_jsonb(old))
  then
    new.structured_sensory = null;
  end if;
  return new;
end;
$$;

-- 3. A populated row keeps its product. (This also stops reading the publish
--    columns that 20261026120000 removed.)
create or replace function public.soolgyul_prevent_populated_tasting_profile_retargeting()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.alcohol_item_id is not distinct from old.alcohol_item_id then
    return new;
  end if;
  if num_nonnulls(
      nullif(btrim(old.aroma_note), ''), nullif(btrim(old.palate_note), ''),
      nullif(btrim(old.finish_note), ''), nullif(btrim(old.texture_note), ''),
      old.sweetness, old.acidity, old.bitterness, old.astringency, old.body,
      old.carbonation, old.aroma_intensity, old.finish_length,
      old.finish_cleanliness) > 0
    or cardinality(old.aroma_tags || old.palate_tags || old.finish_tags) > 0
  then
    raise exception 'reviewed or populated tasting profile target is immutable; create a replacement profile'
      using errcode = '23514';
  end if;
  return new;
end
$$;

-- 4. Tag validation covers the three remaining sections.
create or replace function public.soolgyul_validate_tasting_profile_catalog_terms()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'INSERT' or new.aroma_tags is distinct from old.aroma_tags then
    if not public.soolgyul_catalog_term_keys_are_active(
      new.aroma_tags, array['sensory_descriptor'], array['aroma']
    ) then
      raise exception 'aroma_tags require active aroma sensory terms'
        using errcode = '23514';
    end if;
  end if;
  if tg_op = 'INSERT' or new.palate_tags is distinct from old.palate_tags then
    if not public.soolgyul_catalog_term_keys_are_active(
      new.palate_tags, array['sensory_descriptor'], array['palate']
    ) then
      raise exception 'palate_tags require active palate sensory terms'
        using errcode = '23514';
    end if;
  end if;
  if tg_op = 'INSERT' or new.finish_tags is distinct from old.finish_tags then
    if not public.soolgyul_catalog_term_keys_are_active(
      new.finish_tags, array['sensory_descriptor'], array['finish']
    ) then
      raise exception 'finish_tags require active finish sensory terms'
        using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists alcohol_tasting_profiles_catalog_terms_validate
  on public.alcohol_tasting_profiles;
create trigger alcohol_tasting_profiles_catalog_terms_validate
  before insert or update of aroma_tags, palate_tags, finish_tags
  on public.alcohol_tasting_profiles
  for each row execute function public.soolgyul_validate_tasting_profile_catalog_terms();

-- 5. Readers: the questionnaire context keeps its shape for the app that is
--    already installed (texture_keys stays an empty list, sensory_scale stays
--    5); the search projection folds the three remaining tag arrays.
create or replace function public.soolgyul_get_sensory_question_context(target_catalog_id uuid)
returns jsonb
language sql stable security definer
set search_path to 'pg_catalog', 'public'
as $$
  select jsonb_build_object(
    'id', item.id,
    'name', item.name_ko,
    'name_en', item.name_en,
    'category', category.category_key,
    'style_key', item.style_key,
    'target', 'product',
    'facets', to_jsonb(item.classification_keys),
    'ingredient_keys', item.ingredient_keys,
    'production_process_keys', item.production_process_keys,
    'abv_percent', item.abv_percent,
    'aroma_keys', coalesce(to_jsonb(profile.aroma_tags), '[]'::jsonb),
    'texture_keys', '[]'::jsonb,
    'sensory_scale', 5,
    'levels', jsonb_strip_nulls(jsonb_build_object(
      'sweetness', profile.sweetness,
      'acidity', profile.acidity,
      'bitterness', profile.bitterness,
      'astringency', profile.astringency,
      'body', profile.body)))
  from public.alcohol_items item
  join public.alcohol_categories category on category.id = item.alcohol_category_id
  left join public.alcohol_tasting_profiles profile on profile.alcohol_item_id = item.id
  where item.id = target_catalog_id and item.publish_status = 'published';
$$;

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

-- 6. level_sources may only name the nine remaining levels.
create or replace function public.soolgyul_level_sources_are_valid(sources jsonb)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select jsonb_typeof(sources) = 'object'
    and not exists (
      select 1
      from jsonb_each(sources) as entry(dimension, source)
      where entry.dimension not in (
          'sweetness', 'acidity', 'bitterness', 'astringency', 'body',
          'carbonation', 'aroma_intensity', 'finish_length',
          'finish_cleanliness')
        or jsonb_typeof(entry.source) <> 'string'
        or length(entry.source #>> '{}') not between 1 and 120
        or (entry.source #>> '{}') <> btrim(entry.source #>> '{}')
        or (entry.source #>> '{}') ~ '[[:cntrl:]]'
    );
$$;

-- 7. The columns themselves.
alter table public.alcohol_tasting_profiles
  drop column if exists overall_note,
  drop column if exists body_note,
  drop column if exists viscosity,
  drop column if exists flavour_clarity,
  drop column if exists texture_tags,
  drop column if exists sensory_scale,
  drop column if exists locale,
  drop column if exists structured_semantics;

drop function if exists public.valid_product_sensory_semantics(jsonb, uuid);
