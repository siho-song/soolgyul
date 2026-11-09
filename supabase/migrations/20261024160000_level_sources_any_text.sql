-- A level's source names where the number was read: a retailer scale, a
-- tasting note, a critic or importer page, the reader's own answer. New sources
-- keep appearing as collection widens, so the column accepts any short text per
-- dimension. Only the estimate words stay fixed by convention (table,
-- style_median, category_median, abv, style, same_line, fill): the card treats
-- those as the kind's value, everything else as evidence about the bottle.
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
          'sweetness', 'acidity', 'bitterness', 'umami', 'saltiness',
          'astringency', 'body', 'viscosity', 'carbonation', 'alcohol_presence',
          'aroma_intensity', 'flavour_clarity', 'finish_length', 'finish_cleanliness'
        )
        or jsonb_typeof(entry.source) <> 'string'
        or length(entry.source #>> '{}') not between 1 and 120
        or (entry.source #>> '{}') <> btrim(entry.source #>> '{}')
        or (entry.source #>> '{}') ~ '[[:cntrl:]]'
    );
$$;

alter table public.alcohol_tasting_profiles
  drop constraint alcohol_tasting_profiles_level_sources_check;

alter table public.alcohol_tasting_profiles
  add constraint alcohol_tasting_profiles_level_sources_check
  check (public.soolgyul_level_sources_are_valid(level_sources));

comment on column public.alcohol_tasting_profiles.level_sources is
  'Per-level provenance: short text naming where the number was read (wine21_scale, note, dailyshot, a retailer or critic site, the reader''s answer). Estimates are the fixed words table, style_median, category_median, abv, style, same_line, fill; the catalog stores none of them for bitterness, umami, saltiness, carbonation, alcohol_presence, aroma_intensity, finish_length, finish_cleanliness since 2026-10-24 (the card reads the style table instead). A level column without a source key is unknown.';
