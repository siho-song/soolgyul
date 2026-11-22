-- A bottle or a maker goes by names its catalog name is not spelled with: a
-- sake label prints 真澄 銀撰 for 마스미 긴센, a brewery also sells under
-- 上善如水. A label photo never met them: the only other names were the
-- typed search's nicknames ("와턱"), which reword a query before it is
-- searched and stay so, since a nickname of two letters searched as a
-- name finds every name that holds it ("버트" in 로버트 몬다비). Each
-- bottle and each producer now carries the names it goes by, folded into
-- the search text every search already looks in, and the label search also
-- finds a bottle whose other name stands inside a line of kanji or kana,
-- which a label runs together ("銀撰真澄").

create function public.soolgyul_catalog_compact_text_array(input_values text[])
returns text
language sql immutable parallel safe
set search_path to ''
as $$
  select coalesce(string_agg(public.soolgyul_catalog_compact_text(value), ' ' order by ordinality), '')
  from unnest(coalesce(input_values, array[]::text[])) with ordinality as source(value, ordinality);
$$;
revoke all on function public.soolgyul_catalog_compact_text_array(text[]) from public, anon, authenticated;

alter table public.alcohol_items
  add column other_names text[] not null default '{}'
    check (array_position(other_names, null) is null and not ('' = any(other_names)));
alter table public.producers
  add column other_names text[] not null default '{}'
    check (array_position(other_names, null) is null and not ('' = any(other_names)));
comment on column public.alcohol_items.other_names is
  'Names the bottle goes by that name_ko and name_en do not spell, as its label prints them in its own script (真澄 銀撰). Searched with the names.';
comment on column public.producers.other_names is
  'Names the producer goes by besides name_ko, name_en and name_native, such as its other brands (上善如水). Searched with the names.';

-- A generated column's expression cannot change in place: each search text
-- is made again with the other names after the rest, so the parts the
-- searches cut by position stay where they were.
drop index public.alcohol_items_published_search_fold_trgm_idx;
alter table public.alcohol_items drop column search_fold_text;
alter table public.alcohol_items add column search_fold_text text generated always as (
  public.soolgyul_fold_korean_sound(name_ko) || ' '
  || public.soolgyul_fold_korean_sound(coalesce(name_en, '')) || ' '
  || public.soolgyul_fold_korean_sound_array(regexp_split_to_array(name_ko, '\s+')) || ' '
  || public.soolgyul_fold_korean_sound_array(other_names)
) stored;
create index alcohol_items_published_search_fold_trgm_idx on public.alcohol_items
  using gin (search_fold_text extensions.gin_trgm_ops) where publish_status = 'published';

alter table public.alcohol_items drop column search_typed_text;
alter table public.alcohol_items add column search_typed_text text generated always as (
  public.soolgyul_catalog_compact_text(name_ko) || ' '
  || public.soolgyul_catalog_compact_text(name_en) || ' '
  || public.soolgyul_catalog_compact_text_array(other_names)
) stored;

drop index public.producers_search_fold_trgm_idx;
alter table public.producers drop column search_fold_text;
alter table public.producers add column search_fold_text text generated always as (
  public.soolgyul_fold_korean_sound(coalesce(name_ko, '')) || ' '
  || public.soolgyul_fold_korean_sound(coalesce(name_en, '')) || ' '
  || public.soolgyul_fold_korean_sound(coalesce(name_native, '')) || ' '
  || public.soolgyul_fold_korean_sound_array(other_names)
) stored;
create index producers_search_fold_trgm_idx on public.producers
  using gin (search_fold_text extensions.gin_trgm_ops);

-- The label's facts also give the bottle's other names, and its producer's,
-- so the app weighs a label that shows one of them as it weighs its name.
create or replace function public.soolgyul_catalog_label_facts(target_item_id uuid)
returns jsonb
language sql stable security definer
set search_path to 'pg_catalog', 'public'
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'vintage', item.vintage_year,
    'age', item.age_statement_years,
    'grapes', nullif(to_jsonb(item.grape_variety_keys), '[]'::jsonb),
    'names', nullif(to_jsonb(item.other_names), '[]'::jsonb),
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
        to_jsonb(
          array_remove(array[producer.name_ko, producer.name_en, producer.name_native], null)
            || producer.other_names
        ),
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

-- The bottles one of whose other names, or one of whose producer's names in
-- kanji or kana, stands inside [target_line]: a label printed in Japanese
-- runs its words together, so "銀撰真澄" holds no word a name is spelled
-- with. The bottle's own names count before its producer's, a longer name
-- before a shorter.
create function public.soolgyul_catalog_names_inside(target_line text, target_limit integer)
returns table(id uuid, place bigint)
language sql stable
set search_path to 'pg_catalog', 'public'
as $$
  with line as (
    select public.soolgyul_catalog_compact_text(target_line) as compact
  ),
  producer_hits as (
    select producer.id, max(char_length(piece.compact)) as longest
    from public.producers as producer
    cross join lateral unnest(array[producer.name_native] || producer.other_names) as name(value)
    cross join lateral (select public.soolgyul_catalog_compact_text(name.value) as compact) as piece
    cross join line
    where (producer.name_native is not null or producer.other_names <> '{}')
      and name.value ~ '[぀-ヿ㐀-鿿]'
      and char_length(piece.compact) >= 2
      and strpos(line.compact, piece.compact) > 0
    group by producer.id
  ),
  item_hits as (
    select item.id, max(char_length(piece.compact)) as longest
    from public.alcohol_items as item
    cross join lateral unnest(item.other_names) as name(value)
    cross join lateral (select public.soolgyul_catalog_compact_text(name.value) as compact) as piece
    cross join line
    where item.other_names <> '{}'
      and item.publish_status = 'published'
      and name.value ~ '[぀-ヿ㐀-鿿]'
      and char_length(piece.compact) >= 2
      and strpos(line.compact, piece.compact) > 0
    group by item.id
  )
  select item.id, row_number() over (
    order by
      coalesce(own.longest, 0) desc,
      coalesce(maker.longest, 0) desc,
      case when signal.known then 3 else 0 end + ln(1 + coalesce(signal.picks, 0)) desc,
      coalesce(signal.staple, false) desc,
      item.name_ko,
      item.id
  )
  from public.alcohol_items as item
  join public.alcohol_categories as category
    on category.id = item.alcohol_category_id and category.is_active
  left join item_hits as own on own.id = item.id
  left join producer_hits as maker on maker.id = item.producer_id
  left join public.catalog_search_signals as signal on signal.alcohol_item_id = item.id
  where item.publish_status = 'published'
    and (own.id is not null or maker.id is not null)
  order by 2
  limit greatest(1, least(coalesce(target_limit, 10), 20))
$$;
revoke all on function public.soolgyul_catalog_names_inside(text, integer) from public, anon, authenticated;

-- The label search asks for the names inside a line of kanji or kana when
-- nothing else answers it.
create or replace function public.soolgyul_search_alcohol_catalog_by_label(
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
    continue when found or asked.words !~ '[぀-ヿ㐀-鿿]';
    return query
      select asked.place, item.id, item.name_ko, item.name_en, category.category_key,
        item.style_key, coalesce(style_term.label_ko, category.name_ko), item.abv_percent,
        (
          select media.media_path
          from public.catalog_media_assets as media
          where media.alcohol_item_id = item.id
            and media.publish_status = 'published'
            and media.published_at is not null
        ),
        item.country_code, region_term.label_ko,
        public.soolgyul_catalog_label_facts(item.id)
      from public.soolgyul_catalog_names_inside(asked.words, target_limit) as inside
      join public.alcohol_items as item on item.id = inside.id
      join public.alcohol_categories as category on category.id = item.alcohol_category_id
      left join public.catalog_taxonomy as style_term
        on style_term.term_type = 'style' and style_term.term_key = item.style_key and style_term.is_active
      left join public.catalog_taxonomy as region_term
        on region_term.term_type = 'region' and region_term.term_key = item.region_key
      order by inside.place;
  end loop;
end
$$;
