-- A label read off a photo is the drink's whole name with a letter or two
-- wrong ("사또 몽페라 루즈" for 샤또, "CLOUDY BAl"), spaced differently
-- ("트리플우드") or with a word the catalog leaves out ("… 디오씨지"). The
-- search for typed names goes word by word and drops the short ones, so it
-- misses these or answers with an unrelated product. A label gets its own
-- search: every word first, as typed names do; when no product holds them
-- all, the products whose name holds most of the label's text as one
-- string, followed by the word-by-word near matches.
set local lock_timeout = '5s';

-- Products whose folded name, as one string, holds most of the folded
-- text: its trigrams against the best run of the name's (word similarity
-- 0.55 or more). Nearest first; among equals the name closest to the text
-- as a whole, then the shorter name. Text under six folded letters says
-- too little to compare this way.
create function public.soolgyul_catalog_name_near_matches(
  target_name text,
  target_limit integer
) returns table(
  id uuid, name_ko text, name_en text, category_key text, style_key text,
  style_label text, abv_percent numeric, media_path text, country_code text,
  region text
)
language plpgsql stable
set search_path to 'pg_catalog', 'public'
-- The planner underrates what comparing the text with every name costs;
-- the trigram index is faster whatever the text.
set enable_seqscan to off
as $$
#variable_conflict use_column
declare
  folded text := public.soolgyul_fold_korean_sound(target_name);
begin
  if char_length(folded) not between 6 and 120 then
    return;
  end if;
  -- Calling any pg_trgm function loads the extension so its parameter is
  -- known in this session; set_config then applies to this transaction.
  perform extensions.show_trgm('');
  perform set_config('pg_trgm.word_similarity_threshold', '0.55', true);

  return query
  with near as (
    select
      item.id,
      item.name_ko,
      item.name_en,
      item.alcohol_category_id,
      item.style_key,
      item.region_key,
      item.abv_percent,
      item.country_code,
      extensions.word_similarity(folded, item.search_fold_text) as nearness,
      greatest(
        extensions.similarity(folded, split_part(item.search_fold_text, ' ', 1)),
        extensions.similarity(folded, split_part(item.search_fold_text, ' ', 2))
      ) as wholeness
    from public.alcohol_items as item
    where item.publish_status = 'published'
      and item.alcohol_category_id in (
        select category.id from public.alcohol_categories as category where category.is_active
      )
      and folded operator(extensions.<%) item.search_fold_text
    order by nearness desc, wholeness desc, char_length(item.name_ko), item.name_ko, item.id
    limit greatest(1, least(coalesce(target_limit, 20), 20))
  )
  select
    near.id,
    near.name_ko,
    near.name_en,
    category.category_key,
    near.style_key,
    coalesce(style_term.label_ko, category.name_ko) as style_label,
    near.abv_percent,
    (
      select media.media_path
      from public.catalog_media_assets as media
      where media.alcohol_item_id = near.id
        and media.publish_status = 'published'
        and media.published_at is not null
    ) as media_path,
    near.country_code,
    region_term.label_ko as region
  from near
  join public.alcohol_categories as category
    on category.id = near.alcohol_category_id
  left join public.catalog_taxonomy as style_term
    on style_term.term_type = 'style'
   and style_term.term_key = near.style_key
   and style_term.is_active
  left join public.catalog_taxonomy as region_term
    on region_term.term_type = 'region'
   and region_term.term_key = near.region_key
  order by near.nearness desc, near.wholeness desc, char_length(near.name_ko), near.name_ko, near.id;
end
$$;

revoke all on function public.soolgyul_catalog_name_near_matches(text, integer) from public, anon, authenticated;

-- What a photographed label's lines find, one answer per line in order and
-- at most eight lines, as soolgyul_search_alcohol_catalog_batch answers
-- typed names.
create function public.soolgyul_search_alcohol_catalog_by_label(
  target_queries text[],
  target_limit integer default 10
) returns table(
  query_index integer, id uuid, name_ko text, name_en text, category_key text,
  style_key text, style_label text, abv_percent numeric, media_path text,
  country_code text, region text
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
        found.country_code, found.region
      from public.soolgyul_catalog_exact_matches(asked.words, target_limit, 0)
        with ordinality as found(
          id, name_ko, name_en, category_key, style_key, style_label, abv_percent,
          media_path, country_code, region, place
        )
      order by found.place;
    continue when found;
    -- Both kinds of near match answer together, the whole-name ones first:
    -- either can be the one that reads the label right.
    return query
      select asked.place, near.id, near.name_ko, near.name_en, near.category_key,
        near.style_key, near.style_label, near.abv_percent, near.media_path,
        near.country_code, near.region
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
