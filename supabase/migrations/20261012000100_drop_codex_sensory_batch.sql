-- Remove the one-off sensory batch writers and the coded_sensory column; no runtime path uses them.

alter table public.alcohol_tasting_profiles
  drop constraint if exists alcohol_tasting_profiles_coded_valid,
  drop column if exists coded_sensory;

drop function if exists public.refresh_product_sensory_grades_batch(jsonb);
drop function if exists public.set_product_sensory_facts_batch(jsonb);
drop function if exists public.set_product_sensory_catalog_batch(jsonb);
drop function if exists public.compact_product_sensory_notes_batch(jsonb);
drop function if exists public.assert_product_sensory_catalog_sources(jsonb, public.alcohol_tasting_profiles);
drop function if exists public.apply_sensory_product_claims(uuid, jsonb, jsonb);
drop function if exists public.extract_coded_sensory(jsonb, text);
drop function if exists public.coded_sensory_evidence_matches(jsonb, jsonb, jsonb, boolean);
drop function if exists public.valid_coded_sensory(jsonb, uuid);
drop function if exists public.sensory_oak_long_aroma_clause(text);
drop function if exists public.sensory_literal_balanced_acid_mouthfeel(text);
drop function if exists public.sensory_literal_cold_sake_oak(text);
drop function if exists public.sensory_literal_fruit_aroma_through_finish(text);
drop function if exists public.sensory_literal_gold_fruit_opening(text);
drop function if exists public.sensory_literal_lively_smooth_fruit_finish(text);
drop function if exists public.sensory_literal_oak_named_long_aroma(text);
drop function if exists public.sensory_literal_oak_vanilla_aroma(text);
drop function if exists public.sensory_literal_omachi_rice(text);
drop function if exists public.sensory_literal_rice_water_sake(text);
