alter table public.alcohol_tasting_profiles
  add column level_sources jsonb not null default '{}'::jsonb;

alter table public.alcohol_tasting_profiles
  add constraint alcohol_tasting_profiles_level_sources_check check (
    jsonb_typeof(level_sources) = 'object'
    and not jsonb_path_exists(
      level_sources,
      '$.* ? (!(@ == "catalog" || @ == "note" || @ == "note_modifier" || @ == "name" || @ == "style" || @ == "abv"))'
    )
  );

comment on column public.alcohol_tasting_profiles.level_sources is
  'Per-level provenance: catalog (imported, unverified), note, note_modifier, name, style, abv. A level column without a source key is unknown.';
