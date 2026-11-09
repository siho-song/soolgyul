-- 20261025120000 dropped alcohol_tasting_profiles.alcohol_presence but left
-- soolgyul_get_sensory_question_context reading it, so every questionnaire
-- load failed with "column profile.alcohol_presence does not exist". The
-- questionnaire context now carries the five remaining levels; the heat of a
-- drink comes from abv_percent, which the item row already states.

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
    'texture_keys', coalesce(to_jsonb(profile.texture_tags), '[]'::jsonb),
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
