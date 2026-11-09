-- Objects left behind by removed workflows: the v1 provider-revocation marker
-- (the edge function calls v2), catalog text validators no constraint uses,
-- the sensory batch helpers whose only callers were dropped on 2026-10-12, the
-- account deletion ledger replaced by users deletion columns, client policies
-- on user_drink_interests that have no matching grant, and uuid-ossp.

drop function if exists public.soolgyul_mark_deletion_provider_revoked(uuid, timestamptz);
drop function if exists public.soolgyul_catalog_http_url_is_valid(text);
drop function if exists public.soolgyul_catalog_timestamp_text_is_valid(text);
drop function if exists public.encode_sensory_note_evidence(jsonb, text, text[]);
drop function if exists public.sensory_item_assignment_snapshot(jsonb);
drop function if exists public.sensory_semantic_phase_matches(jsonb, jsonb);
drop function if exists public.sensory_note_phase_matches(text, text, text);

drop table if exists public.user_account_deletions;

drop policy if exists user_drink_interests_owner_insert on public.user_drink_interests;
drop policy if exists user_drink_interests_owner_delete on public.user_drink_interests;

drop extension if exists "uuid-ossp";
