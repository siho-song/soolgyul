-- One adult-profile rule and one signup RPC.
--
-- soolgyul_adult_profile_complete is the single definition of a completed
-- adult profile: adult confirmation recorded plus active age, terms and privacy
-- consents. The status RPC, the anonymous card conversion, the generation
-- finalizer and the edge profile gate all use it; the conversion previously
-- skipped the age consent. soolgyul_complete_my_profile_v3 now validates and
-- stores everything itself, so the v1 and v2 wrappers it delegated to are
-- dropped. Behaviour, error codes and the one-shot retry rule are unchanged.

create or replace function public.soolgyul_adult_profile_complete(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1 from public.users profile_row
    where profile_row.id = target_user_id
      and profile_row.age_confirmed_at is not null
  )
  and (
    select count(distinct consent.consent_type) = 3
    from public.user_consents consent
    where consent.user_id = target_user_id
      and consent.withdrawn_at is null
      and (consent.consent_type, consent.document_version) in (
        ('age_19', 'self-attestation-v1'),
        ('terms', 'soolgyul-terms-v1'),
        ('privacy', 'soolgyul-privacy-v1')
      )
  );
$$;

revoke execute on function public.soolgyul_adult_profile_complete(uuid) from public, anon, authenticated;
grant execute on function public.soolgyul_adult_profile_complete(uuid) to service_role;

CREATE OR REPLACE FUNCTION public.soolgyul_get_my_profile_status_v1() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  target_user_id uuid;
  current_display_name text;
  current_account_status text;
  has_adult_confirmation boolean;
  has_terms_acceptance boolean;
  has_privacy_acceptance boolean;
  has_marketing_acceptance boolean;
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  select product_user.display_name, product_user.account_status
  into current_display_name, current_account_status
  from public.users product_user
  
  where product_user.id = target_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'profile_not_found';
  end if;
  if current_account_status in ('disabled', 'purged') then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  select
    exists (
      select 1
      from public.user_consents consent
      where consent.user_id = target_user_id
        and consent.consent_type = 'age_19'
        and consent.document_version = 'self-attestation-v1'
        and consent.withdrawn_at is null
    ),
    exists (
      select 1
      from public.user_consents consent
      where consent.user_id = target_user_id
        and consent.consent_type = 'terms'
        and consent.document_version = 'soolgyul-terms-v1'
        and consent.withdrawn_at is null
    ),
    exists (
      select 1
      from public.user_consents consent
      where consent.user_id = target_user_id
        and consent.consent_type = 'privacy'
        and consent.document_version = 'soolgyul-privacy-v1'
        and consent.withdrawn_at is null
    ),
    exists (
      select 1
      from public.user_consents consent
      where consent.user_id = target_user_id
        and consent.consent_type = 'marketing'
        and consent.document_version = 'soolgyul-marketing-v1'
        and consent.withdrawn_at is null
    )
  into
    has_adult_confirmation,
    has_terms_acceptance,
    has_privacy_acceptance,
    has_marketing_acceptance;

  return jsonb_build_object(
    'profile_complete',
      current_display_name is not null
      and public.soolgyul_adult_profile_complete(target_user_id),
    'display_name', current_display_name,
    'age_19_or_over_confirmed', has_adult_confirmation,
    'terms_version', case
      when has_terms_acceptance then 'soolgyul-terms-v1'
      else null
    end,
    'privacy_version', case
      when has_privacy_acceptance then 'soolgyul-privacy-v1'
      else null
    end,
    'marketing_opt_in', has_marketing_acceptance,
    'deletion_state', case
      when current_account_status = 'scheduled_deletion' then 'scheduled'
      else 'active'
    end
  );
end
$$;

CREATE OR REPLACE FUNCTION public.soolgyul_convert_anonymous_taste_card(target_user_id uuid, target_result_summary_id uuid, target_anonymous_session_digest text, target_idempotency_key uuid) RETURNS TABLE(drink_record_id uuid, result_summary_id uuid, claim_snapshot_id uuid, converted boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
declare
  target_record public.drink_records%rowtype;
  target_snapshot_id uuid;
  did_convert boolean := false;
begin
  if target_user_id is null
    or target_result_summary_id is null
    or target_idempotency_key is null
    or target_anonymous_session_digest is null
    or target_anonymous_session_digest !~ '^[0-9a-f]{64}$'
  then
    raise exception using
      errcode = '22023',
      message = 'invalid anonymous taste card conversion request';
  end if;

  -- Use the same user-then-record lock order as account/profile writes.
  perform 1 from public.users u where u.id = target_user_id for update;
  if not found or not public.soolgyul_account_active(target_user_id) then
    raise exception using
      errcode = '42501',
      message = 'active account required';
  end if;

  if not public.soolgyul_adult_profile_complete(target_user_id) then
    raise exception using
      errcode = '42501',
      message = 'completed adult profile required';
  end if;

  select record_row.*
  into target_record
  from public.taste_cards summary_row
  join public.drink_records record_row
    on record_row.id = summary_row.drink_record_id
  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id
  for update of record_row;

  if not found or target_record.deleted_at is not null then
    raise exception using
      errcode = 'P0002',
      message = 'taste card result not found';
  end if;

  select summary_row.snapshot_id
  into target_snapshot_id
  from public.taste_cards summary_row
  
  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id;

  if target_snapshot_id is null then
    raise exception using
      errcode = '55000',
      message = 'final taste card snapshot required';
  end if;

  if not exists (
    select 1
    from public.taste_card_generation_attempts attempt_row
    where attempt_row.anonymous_session_digest = target_anonymous_session_digest
      and attempt_row.result_summary_id = target_result_summary_id
      and attempt_row.claim_snapshot_id = target_snapshot_id
      and attempt_row.state = 'final'
      and (target_record.user_id = target_user_id
        or attempt_row.conversion_expires_at > now())
  ) then
    raise exception using
      errcode = '42501',
      message = 'anonymous taste card proof is invalid or expired';
  end if;

  if target_record.user_id is null then
    update public.drink_records
    set user_id = target_user_id,
        anonymous_session_id = null,
        saved_at = coalesce(saved_at, now()),
        updated_at = now()
    where id = target_record.id;
    did_convert := true;
  elsif target_record.user_id <> target_user_id then
    raise exception using
      errcode = '42501',
      message = 'taste card is owned by another account';
  end if;

  return query
  select
    target_record.id,
    target_result_summary_id,
    target_snapshot_id,
    did_convert;
end;
$_$;

CREATE OR REPLACE FUNCTION public.soolgyul_finalize_taste_card_generation(input_bundle jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  attempt_row public.taste_card_generation_attempts%rowtype;
  request_row jsonb := input_bundle->'request';
  identification_row jsonb := input_bundle->'alcohol_identification';
  version_row jsonb := input_bundle->'version_vector';
  rendered_row jsonb := input_bundle->'rendered_view';
  answer_row jsonb;
  question_id uuid;
  generated_snapshot_id uuid := gen_random_uuid();
  principal_kind text := input_bundle #>> '{principal,kind}';
  wire_schema_version text := coalesce(
    input_bundle->>'wire_schema_version',
    'taste-card-result-wire-v1'
  );
  selected_catalog_id uuid;
  resolved_alcohol_item_id uuid;
  result_schema_version integer;
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

  if wire_schema_version not in (
    'taste-card-result-wire-v1',
    'taste-card-result-wire-v2'
  ) then
    raise exception using
      errcode = '22023',
      message = 'taste card wire schema version is invalid';
  end if;

  result_schema_version := case
    when wire_schema_version = 'taste-card-result-wire-v2' then 2
    else 1
  end;

  if result_schema_version = 2 and (
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
    questionnaire_version_id,
    alcohol_item_id,
    entered_alcohol_name,
    alcohol_name_snapshot,
    category,
    identification_mode,
    photo_storage_path,
    one_line_note,
    saved_at,
    idempotency_key
  )
  values (
    attempt_row.reserved_record_id,
    case when principal_kind = 'authenticated' then attempt_row.owner_user_id else null end,
    case when principal_kind = 'anonymous' then request_row->>'anonymous_session_id' else null end,
    (request_row->>'questionnaire_version_id')::uuid,
    resolved_alcohol_item_id,
    nullif(identification_row->>'entered_alcohol_name', ''),
    identification_row->>'alcohol_name_snapshot',
    nullif(identification_row->>'category', ''),
    identification_row->>'mode',
    null,
    nullif(request_row->>'q7_free_text', ''),
    case when principal_kind = 'authenticated' then now() else null end,
    request_row->>'idempotency_key'
  );

  for answer_row in
    select value
    from jsonb_array_elements(coalesce(request_row->'answers', '[]'::jsonb))
  loop
    select question_row.id
    into question_id
    from public.questionnaire_questions question_row
    where question_row.questionnaire_version_id =
      (request_row->>'questionnaire_version_id')::uuid
      and question_row.question_key = answer_row->>'question_key';

    if (answer_row ? 'option_gap_reported' and jsonb_typeof(answer_row->'option_gap_reported') not in ('boolean', 'null'))
      or (answer_row ? 'feedback_text' and jsonb_typeof(answer_row->'feedback_text') not in ('string', 'null')) then
      raise exception 'invalid_question_feedback' using errcode = '22023';
    end if;

    insert into public.drink_record_answers (
      drink_record_id,
      questionnaire_version_id,
      questionnaire_question_id,
      question_key,
      question_label_snapshot,
      selected_option_keys,
      selected_option_labels_snapshot,
      free_text,
      option_gap_reported,
      feedback_text
    )
    values (
      attempt_row.reserved_record_id,
      (request_row->>'questionnaire_version_id')::uuid,
      question_id,
      answer_row->>'question_key',
      answer_row->>'question_label_snapshot',
      array(
        select jsonb_array_elements_text(
          coalesce(answer_row->'selected_option_keys', '[]'::jsonb)
        )
      ),
      array(
        select jsonb_array_elements_text(
          coalesce(answer_row->'selected_option_labels_snapshot', '[]'::jsonb)
        )
      ),
      nullif(answer_row->>'free_text', ''),
      (answer_row->>'option_gap_reported')::boolean,
      nullif(btrim(answer_row->>'feedback_text'), '')
    );
  end loop;

  insert into public.taste_cards (
    id,
    drink_record_id,
    result_type_key,
    taste_axis_scores,
    preference_cues,
    next_drink_directions,
    burdensome_directions,
    summary_paragraphs,
    share_card_text,
    catalog_evidence,
    schema_version,
    rule_version,
    result_snapshot
  )
  values (
    attempt_row.reserved_result_summary_id,
    attempt_row.reserved_record_id,
    case when result_schema_version = 2 then 'taste_card_v2' else 'taste_card_v1' end,
    '{}'::jsonb,
    case
      when result_schema_version = 2
        then coalesce(rendered_row->'core_summary'->'blocks', '[]'::jsonb)
      else jsonb_build_array(rendered_row #>> '{summary,discovery,body}')
    end,
    case
      when result_schema_version = 2
        then coalesce(rendered_row->'next_drink'->'candidates', '[]'::jsonb)
      else jsonb_build_array(rendered_row #>> '{summary,next_choice,body}')
    end,
    case
      when result_schema_version = 2
        then jsonb_build_array(rendered_row #>> '{next_drink,defer_formula}')
      else '[]'::jsonb
    end,
    case
      when result_schema_version = 2
        then coalesce(rendered_row->'discovery'->'blocks', '[]'::jsonb)
      else jsonb_build_array(rendered_row #>> '{discovery,lead}')
    end,
    case
      when result_schema_version = 2 then coalesce(
        rendered_row #>> '{core_summary,blocks,0,text}',
        identification_row->>'alcohol_name_snapshot'
      )
      else rendered_row #>> '{closing,body}'
    end,
    case
      when result_schema_version = 2 then jsonb_build_object(
        'selected_catalog_id', identification_row->'alcohol_item_id',
        'resolved_alcohol_item_id', resolved_alcohol_item_id,
        'entered_alcohol_name', identification_row->'entered_alcohol_name',
        'alcohol_name_snapshot', identification_row->'alcohol_name_snapshot'
      )
      else jsonb_build_object(
        'matched_catalog_item_id', identification_row->'alcohol_item_id',
        'entered_alcohol_name', identification_row->'entered_alcohol_name',
        'alcohol_name_snapshot', identification_row->'alcohol_name_snapshot'
      )
    end,
    result_schema_version,
    case
      when result_schema_version = 2
        then rendered_row #>> '{metadata,rule_version}'
      else version_row->>'claim_registry_version'
    end,
    rendered_row
  );

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
    'created_at', input_bundle->>'generated_at'
  );

  if result_schema_version = 2 then
    semantic_snapshot_row := semantic_snapshot_row || jsonb_build_object(
      'evidence_context_v2', input_bundle->'evidence_context_v2',
      'insight_plan_v2', input_bundle->'insight_plan_v2',
      'style_recommendation_plan_v2', input_bundle->'style_recommendation_plan_v2'
    );
  end if;

  if pg_column_size(semantic_snapshot_row) > 524288 then
    raise exception using
      errcode = '22023',
      message = 'taste card semantic snapshot exceeds the persistence limit';
  end if;

  update public.taste_cards set (
    snapshot_id,
    snapshot_ref,
    canonical_input_digest,
    questionnaire_version,
    catalog_taxonomy_version,
    catalog_evidence_version,
    adapter_compatibility_version,
    canonical_schema_version,
    memo_rule_version,
    claim_registry_version,
    claim_rule_versions,
    copy_template_version,
    presentation_version,
    source_statuses,
    semantic_snapshot,
    rendered_snapshot
  ) = (
    generated_snapshot_id,
    input_bundle->>'semantic_snapshot_id',
    input_bundle->>'canonical_input_digest',
    version_row->>'questionnaire_version',
    version_row->>'catalog_taxonomy_version',
    version_row->>'catalog_evidence_version',
    version_row->>'adapter_compatibility_version',
    version_row->>'canonical_schema_version',
    version_row->>'memo_rule_version',
    version_row->>'claim_registry_version',
    version_row->'claim_rule_versions',
    version_row->>'copy_template_version',
    version_row->>'presentation_version',
    input_bundle #> '{canonical_input,source_statuses}',
    semantic_snapshot_row,
    rendered_row
  ), lifecycle = 'final', snapshot_created_at = now()
  where id = attempt_row.reserved_result_summary_id;

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

CREATE OR REPLACE FUNCTION public.soolgyul_complete_my_profile_v3(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text DEFAULT NULL::text, p_gender_consent_accepted boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  target_user_id uuid;
  trusted_auth_provider text;
  normalized_display_name text;
  accepted_timestamp timestamptz := clock_timestamp();
  response_payload jsonb;
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_birth_date is null or not isfinite(p_birth_date)
    or p_birth_date < date '1900-01-01' or p_birth_date > current_date then
    raise exception using errcode = '22023', message = 'birth_date_invalid';
  end if;
  if (p_gender is not null and p_gender not in ('male', 'female', 'other'))
    or (p_gender is not null and not coalesce(p_gender_consent_accepted, false))
    or (p_gender is null and coalesce(p_gender_consent_accepted, false)) then
    raise exception using errcode = '22023', message = 'gender_consent_invalid';
  end if;
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'idempotency_key_required';
  end if;

  normalized_display_name := btrim(coalesce(p_display_name, ''));
  if char_length(normalized_display_name) < 2
    or char_length(normalized_display_name) > 12
    or normalized_display_name !~ '^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ]+$'
  then
    raise exception using errcode = '22023', message = 'display_name_invalid';
  end if;

  if not coalesce(p_age_19_or_over_confirmed, false)
    or extract(year from current_date)::integer
      - extract(year from p_birth_date)::integer < 19
  then
    raise exception using errcode = '22023', message = 'age_gate_required';
  end if;
  if not coalesce(p_terms_accepted, false)
    or not coalesce(p_privacy_accepted, false)
  then
    raise exception using errcode = '22023', message = 'terms_and_privacy_required';
  end if;
  if p_terms_version is distinct from 'soolgyul-terms-v1'
    or p_privacy_version is distinct from 'soolgyul-privacy-v1'
    or p_marketing_version is distinct from 'soolgyul-marketing-v1'
  then
    raise exception using errcode = '22023', message = 'policy_version_invalid';
  end if;

  select product_user.auth_provider
  into trusted_auth_provider
  from public.users product_user
  where product_user.id = target_user_id
    and product_user.disabled_at is null
    and product_user.deletion_requested_at is null
    and product_user.deletion_scheduled_at is null
    and product_user.purged_at is null
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;
  if trusted_auth_provider not in ('kakao', 'apple', 'google') then
    raise exception using errcode = '42501', message = 'unsupported_auth_provider';
  end if;

  -- Signup completion is one-shot, not a consent or nickname editing endpoint.
  -- A retry must not undo later nickname changes or revive withdrawn consents.
  if exists (
    select 1 from public.users p
    where p.id = target_user_id and p.age_confirmed_at is not null
  ) and exists (
    select 1 from public.user_consents c
    where c.user_id = target_user_id and c.consent_type = 'terms'
  ) and exists (
    select 1 from public.user_consents c
    where c.user_id = target_user_id and c.consent_type = 'privacy'
  ) then
    return public.soolgyul_get_my_profile_status_v1();
  end if;

  update public.users profile
  set display_name = normalized_display_name,
      age_confirmed_at = coalesce(profile.age_confirmed_at, accepted_timestamp),
      birth_date = p_birth_date,
      gender = p_gender,
      gender_consent_accepted_at = case when p_gender is null then null else accepted_timestamp end,
      gender_consent_version = case when p_gender is null then null else 'soolgyul-gender-v1' end,
      updated_at = accepted_timestamp
  where profile.id = target_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'profile_not_found';
  end if;

  if not exists (
    select 1 from public.user_consents consent
    where consent.user_id = target_user_id
      and consent.consent_type = 'age_19'
      and consent.document_version = 'self-attestation-v1'
      and consent.withdrawn_at is null
  ) then
    insert into public.user_consents (
      user_id, consent_type, document_version, accepted_at
    ) values (
      target_user_id, 'age_19', 'self-attestation-v1', accepted_timestamp
    );
  end if;

  if not exists (
    select 1 from public.user_consents consent
    where consent.user_id = target_user_id
      and consent.consent_type = 'terms'
      and consent.document_version = p_terms_version
      and consent.withdrawn_at is null
  ) then
    insert into public.user_consents (
      user_id, consent_type, document_version, accepted_at
    ) values (
      target_user_id, 'terms', p_terms_version, accepted_timestamp
    );
  end if;

  if not exists (
    select 1 from public.user_consents consent
    where consent.user_id = target_user_id
      and consent.consent_type = 'privacy'
      and consent.document_version = p_privacy_version
      and consent.withdrawn_at is null
  ) then
    insert into public.user_consents (
      user_id, consent_type, document_version, accepted_at
    ) values (
      target_user_id, 'privacy', p_privacy_version, accepted_timestamp
    );
  end if;

  if coalesce(p_marketing_opt_in, false) then
    if not exists (
      select 1 from public.user_consents consent
      where consent.user_id = target_user_id
        and consent.consent_type = 'marketing'
        and consent.document_version = p_marketing_version
        and consent.withdrawn_at is null
    ) then
      insert into public.user_consents (
        user_id, consent_type, document_version, accepted_at
      ) values (
        target_user_id, 'marketing', p_marketing_version, accepted_timestamp
      );
    end if;
  else
    update public.user_consents consent
    set withdrawn_at = accepted_timestamp
    where consent.user_id = target_user_id
      and consent.consent_type = 'marketing'
      and consent.withdrawn_at is null;
  end if;

  response_payload := jsonb_build_object(
    'profile_complete', true,
    'display_name', normalized_display_name,
    'age_19_or_over_confirmed', true,
    'terms_version', p_terms_version,
    'privacy_version', p_privacy_version,
    'marketing_opt_in', coalesce(p_marketing_opt_in, false),
    'deletion_state', 'active'
  );

  return response_payload;
end
$_$;

drop function public.soolgyul_complete_my_profile_v2(
  uuid, text, integer, boolean, text, text, text, boolean, boolean, boolean, text, boolean
);
drop function public.soolgyul_complete_my_profile_v1(
  uuid, text, integer, boolean, text, text, text, boolean, boolean, boolean
);
