-- The grape varieties a wine is made from, main grape first, as the local
-- catalog already records them (grape_variety_keys in the import rows). The
-- card reads them to pick the 종류 표 grape line (까베르네 소비뇽의 떫음) and
-- to name a blend's grapes; without the column the remote catalog can only
-- offer the base style line.
alter table public.alcohol_items
  add column grape_variety_keys text[] default array[]::text[] not null;

alter table public.alcohol_items
  add constraint alcohol_items_grape_variety_keys_check
  check (public.soolgyul_catalog_text_array_is_valid(grape_variety_keys, 64, '^[a-z][a-z0-9_]*$'));

comment on column public.alcohol_items.grape_variety_keys is
  'Grape variety keys of a wine, main grape first (style-profiles.json wine_grapes keys). Empty for other kinds or when unknown.';
