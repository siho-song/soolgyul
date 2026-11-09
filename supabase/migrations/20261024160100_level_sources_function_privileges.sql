-- The level-source validator runs inside a check constraint as the table
-- owner; no client role calls it. New functions receive EXECUTE for PUBLIC by
-- default, so take it away explicitly like the other service-only functions.
revoke all on function public.soolgyul_level_sources_are_valid(jsonb)
  from public, anon, authenticated;
