-- taste_cards kept old-engine columns, version and evidence copies that already
-- live inside semantic_snapshot/rendered_snapshot, and withdraw/supersede
-- columns no feature ever filled. Nothing read them, so they go; a card is
-- written whole in one insert and never changes afterwards.

alter table public.taste_cards
  drop constraint taste_cards_digest_check,
  drop constraint taste_cards_json_check,
  drop constraint taste_cards_legacy_envelope_check,
  drop constraint taste_cards_lifecycle_check,
  drop constraint taste_cards_snapshot_complete,
  drop constraint taste_cards_versions_check,
  drop constraint taste_cards_supersedes_check,
  drop constraint taste_cards_supersedes_snapshot_id_fkey;

alter table public.taste_cards
  drop column result_type_key,
  drop column taste_axis_scores,
  drop column preference_cues,
  drop column next_drink_directions,
  drop column burdensome_directions,
  drop column summary_paragraphs,
  drop column share_card_text,
  drop column catalog_evidence,
  drop column result_snapshot,
  drop column rule_version,
  drop column created_at,
  drop column canonical_input_digest,
  drop column questionnaire_version,
  drop column catalog_taxonomy_version,
  drop column catalog_evidence_version,
  drop column adapter_compatibility_version,
  drop column memo_rule_version,
  drop column claim_registry_version,
  drop column claim_rule_versions,
  drop column copy_template_version,
  drop column presentation_version,
  drop column source_statuses,
  drop column supersedes_snapshot_id,
  drop column withdrawal_reason_code,
  drop column withdrawn_at;

delete from public.taste_cards where snapshot_id is null;

alter table public.taste_cards
  alter column snapshot_id set not null,
  alter column snapshot_ref set not null,
  alter column lifecycle set not null,
  alter column canonical_schema_version set not null,
  alter column semantic_snapshot set not null,
  alter column rendered_snapshot set not null,
  alter column snapshot_created_at set not null,
  alter column snapshot_created_at set default now(),
  add constraint taste_cards_lifecycle_check check (lifecycle = 'final'),
  add constraint taste_cards_version_check
    check (char_length(btrim(canonical_schema_version)) between 1 and 128),
  add constraint taste_cards_json_check check (
    jsonb_typeof(semantic_snapshot) = 'object'
    and jsonb_typeof(rendered_snapshot) = 'object'
    and pg_column_size(semantic_snapshot) <= 524288
    and pg_column_size(rendered_snapshot) <= 131072);

create or replace function public.soolgyul_guard_taste_card_content()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  if new is not distinct from old then return new; end if;
  raise exception using errcode = '55000', message = 'Final taste card content is immutable';
end;
$$;

create or replace function public.soolgyul_finalize_taste_card_generation(input_bundle jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  attempt_row public.taste_card_generation_attempts%rowtype;
  request_row jsonb := input_bundle->'request';
  identification_row jsonb := input_bundle->'alcohol_identification';
  version_row jsonb := input_bundle->'version_vector';
  rendered_row jsonb := input_bundle->'rendered_view';
  answer_row jsonb;
  generated_snapshot_id uuid := gen_random_uuid();
  principal_kind text := input_bundle #>> '{principal,kind}';
  wire_schema_version text := input_bundle->>'wire_schema_version';
  selected_catalog_id uuid;
  resolved_alcohol_item_id uuid;
  semantic_snapshot_row jsonb;
begin
  if jsonb_typeof(input_bundle) is distinct from 'object'
    or jsonb_typeof(request_row) is distinct from 'object'
    or jsonb_typeof(identification_row) is distinct from 'object'
    or jsonb_typeof(version_row) is distinct from 'object'
    or jsonb_typeof(rendered_row) is distinct from 'object'
  then
    raise exception using
      errcode = '22023',
      message = 'taste card finalization bundle is invalid';
  end if;

  if wire_schema_version is distinct from 'taste-card-result-wire-v2' then
    raise exception using
      errcode = '22023',
      message = 'taste card wire schema version is invalid';
  end if;

  if (
    rendered_row #>> '{metadata,schema_version}' is distinct from '2'
    or rendered_row #>> '{metadata,snapshot_ref}'
      is distinct from input_bundle->>'semantic_snapshot_id'
    or jsonb_typeof(input_bundle->'evidence_context_v2') is distinct from 'object'
    or jsonb_typeof(input_bundle->'insight_plan_v2') is distinct from 'object'
    or jsonb_typeof(input_bundle->'style_recommendation_plan_v2') is distinct from 'object'
    or pg_column_size(input_bundle->'evidence_context_v2') > 262144
    or pg_column_size(input_bundle->'insight_plan_v2') > 65536
    or pg_column_size(input_bundle->'style_recommendation_plan_v2') > 65536
  ) then
    raise exception using
      errcode = '22023',
      message = 'taste card V2 private or public snapshot is invalid';
  end if;

  select existing_attempt.*
  into attempt_row
  from public.taste_card_generation_attempts existing_attempt
  where existing_attempt.attempt_ref = input_bundle->>'attempt_ref'
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'generation attempt not found';
  end if;
  if attempt_row.request_digest is distinct from input_bundle->>'request_digest' then
    raise exception using errcode = '22023', message = 'idempotency_conflict';
  end if;
  if attempt_row.idempotency_key is distinct from
    (request_row->>'idempotency_key')::uuid
  then
    raise exception using errcode = '22023', message = 'idempotency key mismatch';
  end if;

  if principal_kind = 'authenticated' then
    if attempt_row.owner_user_id is distinct from
      (input_bundle #>> '{principal,user_id}')::uuid
    then
      raise exception using errcode = '42501', message = 'generation principal mismatch';
    end if;
    if not public.soolgyul_account_active(attempt_row.owner_user_id)
      or not public.soolgyul_adult_profile_complete(attempt_row.owner_user_id)
    then
      raise exception using errcode = '42501', message = 'completed adult profile required';
    end if;
  elsif principal_kind = 'anonymous' then
    if attempt_row.anonymous_session_digest is distinct from
      input_bundle #>> '{principal,anonymous_session_digest}'
    then
      raise exception using errcode = '42501', message = 'generation principal mismatch';
    end if;
    if encode(
      extensions.digest(request_row->>'anonymous_session_id', 'sha256'),
      'hex'
    ) is distinct from attempt_row.anonymous_session_digest
    then
      raise exception using errcode = '42501', message = 'anonymous session mismatch';
    end if;
  else
    raise exception using errcode = '22023', message = 'generation principal invalid';
  end if;

  if attempt_row.state = 'final' then
    return public.soolgyul_build_taste_card_result(attempt_row.result_summary_id);
  end if;

  if identification_row->>'mode' = 'catalog_match' then
    selected_catalog_id := nullif(
      identification_row->>'alcohol_item_id',
      ''
    )::uuid;
    if selected_catalog_id is null then
      raise exception using errcode = '22023', message = 'catalog identifier required';
    end if;

    select item_row.id
    into resolved_alcohol_item_id
    from public.alcohol_items item_row
    where item_row.id = selected_catalog_id
      and item_row.publish_status = 'published';

    if resolved_alcohol_item_id is null then
      raise exception using errcode = '22023', message = 'catalog identifier is not publishable';
    end if;
  elsif identification_row->>'mode' = 'direct_input' then
    if identification_row->'alcohol_item_id' is distinct from 'null'::jsonb then
      raise exception using errcode = '22023', message = 'direct input cannot use a catalog identifier';
    end if;
  else
    raise exception using errcode = '22023', message = 'identification mode is invalid';
  end if;

  insert into public.drink_records (
    id,
    user_id,
    anonymous_session_id,
    questionnaire_version,
    alcohol_item_id,
    entered_alcohol_name,
    one_line_note,
    idempotency_key
  )
  values (
    attempt_row.reserved_record_id,
    case when principal_kind = 'authenticated' then attempt_row.owner_user_id else null end,
    case when principal_kind = 'anonymous' then request_row->>'anonymous_session_id' else null end,
    request_row->>'questionnaire_version',
    resolved_alcohol_item_id,
    nullif(identification_row->>'entered_alcohol_name', ''),
    nullif(request_row->>'q7_free_text', ''),
    request_row->>'idempotency_key'
  );

  for answer_row in
    select value
    from jsonb_array_elements(coalesce(request_row->'answers', '[]'::jsonb))
  loop
    insert into public.drink_record_answers (
      drink_record_id,
      question_key,
      selected_option_keys,
      free_text
    )
    values (
      attempt_row.reserved_record_id,
      answer_row->>'question_key',
      array(
        select jsonb_array_elements_text(
          coalesce(answer_row->'selected_option_keys', '[]'::jsonb)
        )
      ),
      nullif(answer_row->>'free_text', '')
    );
  end loop;

  semantic_snapshot_row := jsonb_build_object(
    'snapshot_id', input_bundle->>'semantic_snapshot_id',
    'snapshot_status', 'final',
    'subject_record_ref', input_bundle #>> '{canonical_input,subject_record_ref}',
    'canonical_input_digest', input_bundle->>'canonical_input_digest',
    'version_vector', version_row,
    'source_statuses', input_bundle #> '{canonical_input,source_statuses}',
    'observations', input_bundle #> '{canonical_input,observations}',
    'evidence_refs', input_bundle #> '{canonical_input,evidence_refs}',
    'claim_decisions', input_bundle->'decisions',
    'semantic_projection', input_bundle->'semantic_projection',
    'rendered_projection', null,
    'supersedes_snapshot_id', 'none',
    'withdrawal_reason_code', 'none',
    'created_at', input_bundle->>'generated_at',
    'evidence_context_v2', input_bundle->'evidence_context_v2',
    'insight_plan_v2', input_bundle->'insight_plan_v2',
    'style_recommendation_plan_v2', input_bundle->'style_recommendation_plan_v2'
  );

  if pg_column_size(semantic_snapshot_row) > 524288 then
    raise exception using
      errcode = '22023',
      message = 'taste card semantic snapshot exceeds the persistence limit';
  end if;

  insert into public.taste_cards (
    id,
    drink_record_id,
    snapshot_id,
    snapshot_ref,
    lifecycle,
    canonical_schema_version,
    semantic_snapshot,
    rendered_snapshot,
    snapshot_created_at
  )
  values (
    attempt_row.reserved_result_summary_id,
    attempt_row.reserved_record_id,
    generated_snapshot_id,
    input_bundle->>'semantic_snapshot_id',
    'final',
    version_row->>'canonical_schema_version',
    semantic_snapshot_row,
    rendered_row,
    now()
  );

  update public.taste_card_generation_attempts
  set state = 'final',
      error_code = null,
      retry_after = null,
      result_summary_id = attempt_row.reserved_result_summary_id,
      claim_snapshot_id = generated_snapshot_id,
      conversion_key_version = input_bundle->>'conversion_key_version',
      conversion_expires_at = nullif(
        input_bundle->>'conversion_expires_at',
        ''
      )::timestamptz,
      completed_at = now(),
      updated_at = now()
  where id = attempt_row.id;

  return public.soolgyul_build_taste_card_result(
    attempt_row.reserved_result_summary_id
  );
end;
$$;

create or replace function public.soolgyul_finalize_withdrawn_account_data(target_user_id uuid)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare account_row public.users%rowtype; retained_count integer;
begin
  select * into account_row from public.users where id=target_user_id for update;
  if not found then return 0; end if;
  if account_row.purged_at is not null then return 0; end if;
  if account_row.deletion_provider_revoked_at is null then raise exception 'provider_revocation_required'; end if;
  if account_row.account_status <> 'scheduled_deletion'
    or account_row.deletion_requested_at is null
    or public.soolgyul_deletion_due_at(account_row.deletion_requested_at) > statement_timestamp() then
    raise exception 'account_purge_not_due';
  end if;
  if exists(select 1 from storage.objects where bucket_id='soolgyul-private'
    and starts_with(name,target_user_id::text || '/')) then
    raise exception 'private_storage_cleanup_required';
  end if;

  -- Preserve memo and questionnaire free text verbatim; never archive support
  -- inquiries, names, account metadata, consent history, or raw engine snapshots.
  insert into public.withdrawn_drink_records(birth_year,gender,record_data)
  select extract(year from account_row.birth_date)::integer,
    case when account_row.gender_consent_accepted_at is not null then account_row.gender end,
    jsonb_build_object(
      'alcohol_item_id',r.alcohol_item_id,
      'entered_alcohol_name',r.entered_alcohol_name,
      'one_line_note',r.one_line_note,
      'questionnaire_version',r.questionnaire_version,
      'answers',coalesce((select jsonb_agg(jsonb_build_object(
        'question_key',a.question_key,
        'selected_option_keys',a.selected_option_keys,
        'free_text',a.free_text) order by a.question_key,a.id)
        from public.drink_record_answers a where a.drink_record_id=r.id),'[]'::jsonb),
      'card',(select public.soolgyul_strip_retained_card_links(jsonb_build_object('rendered_snapshot',c.rendered_snapshot))
        from public.taste_cards c where c.drink_record_id=r.id)
    )
  from public.drink_records r
  where r.user_id=target_user_id and r.deleted_at is null;
  get diagnostics retained_count = row_count;

  -- Converted anonymous attempts can still carry an anonymous proof. Remove
  -- them by record linkage too, not just by owner_user_id.
  delete from public.taste_card_generation_attempts a
  where a.owner_user_id=target_user_id or exists (
    select 1 from public.drink_records r where r.user_id=target_user_id
      and (r.id=a.reserved_record_id or exists (
        select 1 from public.taste_cards c where c.drink_record_id=r.id
          and c.id=a.result_summary_id)));
  delete from public.drink_records where user_id=target_user_id;
  update public.users set birth_date=null,gender=null,
    gender_consent_accepted_at=null,gender_consent_version=null,
    display_name=null,email=null,provider_user_id=gen_random_uuid()::text,
    age_confirmed_at=null,profile_created_at=null,last_sign_in_at=null,
    purged_at=statement_timestamp(),updated_at=statement_timestamp()
  where id=target_user_id;
  return retained_count;
end;
$$;
