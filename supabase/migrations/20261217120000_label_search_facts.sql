-- A label shows more than the drink's name: its region, its strength, its
-- year. The label search answered only what the result list draws, so the
-- app could weigh a candidate by its name alone and could not tell a
-- brand's bottles apart by the place the label names. Each row now also
-- carries `label_facts`, what the catalog knows of the bottle that a label
-- can show. One json column, so a fact added later changes no signature.

-- What the catalog knows of one bottle that its label can show. Keys with
-- nothing to say are left out.
--   vintage  the year
--   age      the age statement, in years
--   grapes   the grape keys ("cabernet_sauvignon")
--   regions  the bottle's place first, then each place it lies in; every
--            place is the list of names it goes by
--   producer the names the producer goes by
--   known    a bottle picked by hand as one people know
--   staple   the producer's everyday bottle among those
create function public.soolgyul_catalog_label_facts(target_item_id uuid)
returns jsonb
language sql stable security definer
set search_path to 'pg_catalog', 'public'
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'vintage', item.vintage_year,
    'age', item.age_statement_years,
    'grapes', nullif(to_jsonb(item.grape_variety_keys), '[]'::jsonb),
    'regions', (
      with recursive place as (
        select term.label_ko, term.label_en, term.synonyms, term.parent_term_key, 1 as depth
        from public.catalog_taxonomy as term
        where term.term_type = 'region' and term.term_key = item.region_key
        union all
        select parent.label_ko, parent.label_en, parent.synonyms, parent.parent_term_key, place.depth + 1
        from place
        join public.catalog_taxonomy as parent
          on parent.term_type = 'region' and parent.term_key = place.parent_term_key
        where place.depth < 8
      )
      select jsonb_agg(
        to_jsonb(array_remove(array[place.label_ko, place.label_en] || place.synonyms, null))
        order by place.depth
      )
      from place
    ),
    'producer', (
      select nullif(
        to_jsonb(array_remove(array[producer.name_ko, producer.name_en, producer.name_native], null)),
        '[]'::jsonb
      )
      from public.producers as producer
      where producer.id = item.producer_id
    ),
    'known', nullif(coalesce(signal.known, false), false),
    'staple', nullif(coalesce(signal.staple, false), false)
  ))
  from public.alcohol_items as item
  left join public.catalog_search_signals as signal on signal.alcohol_item_id = item.id
  where item.id = target_item_id
$$;
revoke all on function public.soolgyul_catalog_label_facts(uuid) from public, anon, authenticated;

-- The same search in the same order; a function's answer cannot gain a
-- column in place, so it is dropped and made again.
drop function public.soolgyul_search_alcohol_catalog_by_label(text[], integer);
create function public.soolgyul_search_alcohol_catalog_by_label(
  target_queries text[],
  target_limit integer default 10
) returns table(
  query_index integer, id uuid, name_ko text, name_en text, category_key text,
  style_key text, style_label text, abv_percent numeric, media_path text,
  country_code text, region text, label_facts jsonb
)
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public'
as $$
#variable_conflict use_column
declare
  asked record;
begin
  for asked in
    select line.words, line.place::integer as place
    from unnest(target_queries[1:8]) with ordinality as line(words, place)
    order by line.place
  loop
    return query
      select asked.place, found.id, found.name_ko, found.name_en, found.category_key,
        found.style_key, found.style_label, found.abv_percent, found.media_path,
        found.country_code, found.region,
        public.soolgyul_catalog_label_facts(found.id)
      from public.soolgyul_catalog_exact_matches(asked.words, target_limit, 0)
        with ordinality as found(
          id, name_ko, name_en, category_key, style_key, style_label, abv_percent,
          media_path, country_code, region, spelled, place
        )
      order by found.place;
    continue when found;
    -- Both kinds of near match answer together, the whole-name ones first:
    -- either can be the one that reads the label right.
    return query
      select asked.place, near.id, near.name_ko, near.name_en, near.category_key,
        near.style_key, near.style_label, near.abv_percent, near.media_path,
        near.country_code, near.region,
        public.soolgyul_catalog_label_facts(near.id)
      from (
        select distinct on (both_kinds.id) both_kinds.*
        from (
          select found.*, 1 as kind
          from public.soolgyul_catalog_name_near_matches(asked.words, target_limit)
            with ordinality as found(
              id, name_ko, name_en, category_key, style_key, style_label, abv_percent,
              media_path, country_code, region, place
            )
          union all
          select found.*, 2 as kind
          from public.soolgyul_catalog_near_matches(asked.words, target_limit, 0)
            with ordinality as found(
              id, name_ko, name_en, category_key, style_key, style_label, abv_percent,
              media_path, country_code, region, place
            )
        ) as both_kinds
        order by both_kinds.id, both_kinds.kind, both_kinds.place
      ) as near
      order by near.kind, near.place
      limit greatest(1, least(coalesce(target_limit, 10), 20));
  end loop;
end
$$;
revoke all on function public.soolgyul_search_alcohol_catalog_by_label(text[], integer) from public;
grant execute on function public.soolgyul_search_alcohol_catalog_by_label(text[], integer) to service_role, anon, authenticated;
