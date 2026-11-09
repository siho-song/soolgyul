-- alcohol_tasting_profiles.structured_sensory repeated the nine level
-- columns, the three tag arrays and the four notes as one JSON document for
-- the old card engine. Checked live on 2026-10-29: no row disagrees with its
-- scalar columns and nothing reads it any more (the card engine reads the
-- columns). The column goes together with its check constraint, the trigger
-- that blanked it when a source column changed, and the two helper functions
-- only those used.

alter table public.alcohol_tasting_profiles
  drop constraint if exists alcohol_tasting_profiles_structured_sensory_valid;

drop trigger if exists invalidate_product_sensory_facts
  on public.alcohol_tasting_profiles;
drop function if exists public.invalidate_product_sensory_facts();
drop function if exists public.sensory_source_snapshot(jsonb);

alter table public.alcohol_tasting_profiles
  drop column if exists structured_sensory;

drop function if exists public.valid_product_sensory_facts(jsonb, uuid);
