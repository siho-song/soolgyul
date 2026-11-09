-- Level provenance now includes the retailer notes and scales, the note term map and
-- the two estimate kinds collected for the local catalog.
alter table public.alcohol_tasting_profiles
  drop constraint alcohol_tasting_profiles_level_sources_check;

alter table public.alcohol_tasting_profiles
  add constraint alcohol_tasting_profiles_level_sources_check check (
    jsonb_typeof(level_sources) = 'object'
    and not jsonb_path_exists(
      level_sources,
      '$.* ? (!(@ == "catalog" || @ == "note" || @ == "note_modifier" || @ == "name" || @ == "term_map"
               || @ == "wine21_scale" || @ == "wine21_note" || @ == "dailyshot" || @ == "sdh_note"
               || @ == "shop_note" || @ == "tippsy_note" || @ == "sbsaq_note" || @ == "review"
               || @ == "style" || @ == "abv" || @ == "same_line" || @ == "fill"
               || @ == "table" || @ == "style_median" || @ == "category_median"))'
    )
  );

comment on column public.alcohol_tasting_profiles.level_sources is
  'Per-level provenance. Product evidence: note, note_modifier, name, term_map, wine21_scale, wine21_note, dailyshot, sdh_note, shop_note, tippsy_note, sbsaq_note, review. Estimates: table, style_median, category_median, abv, style, same_line, fill. catalog = imported, unverified. A level column without a source key is unknown.';
