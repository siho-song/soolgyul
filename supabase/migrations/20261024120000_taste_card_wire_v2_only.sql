-- Taste cards are wire-v2 only.
--
-- The edge functions build only wire-v2 results and the app reads only
-- wire-v2, so the finalizer now rejects any other wire version instead of
-- defaulting to wire-v1, and stores every card as schema_version 2. The
-- result builder returns only schema_version 2 cards; an older final card is
-- treated as missing, the same as a card of an unknown version was before.

CREATE OR REPLACE FUNCTION public.soolgyul_build_taste_card_result(target_result_summary_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select jsonb_build_object(
    'wire_schema_version', 'taste-card-result-wire-v2',
    'result_id', summary_row.id::text,
    'record_id', record_row.id::text,
    'snapshot_ref', summary_row.snapshot_ref,
    'ownership_state', case
      when record_row.user_id is null then 'anonymous'
      else 'saved'
    end,
    'alcohol_identification', jsonb_build_object(
      'mode', record_row.identification_mode,
      'alcohol_item_id', record_row.alcohol_item_id,
      'entered_alcohol_name', record_row.entered_alcohol_name,
      'alcohol_name_snapshot', record_row.alcohol_name_snapshot,
      'category', record_row.category
    ),
    'rendered_snapshot', summary_row.rendered_snapshot,
    'created_at', summary_row.snapshot_created_at
  )
  from public.taste_cards summary_row
  join public.drink_records record_row
    on record_row.id = summary_row.drink_record_id
  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id
    and summary_row.schema_version = 2
    and record_row.deleted_at is null;
$$;

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
    'taste_card_v2',
    '{}'::jsonb,
    coalesce(rendered_row->'core_summary'->'blocks', '[]'::jsonb),
    coalesce(rendered_row->'next_drink'->'candidates', '[]'::jsonb),
    jsonb_build_array(rendered_row #>> '{next_drink,defer_formula}'),
    coalesce(rendered_row->'discovery'->'blocks', '[]'::jsonb),
    coalesce(
      rendered_row #>> '{core_summary,blocks,0,text}',
      identification_row->>'alcohol_name_snapshot'
    ),
    jsonb_build_object(
      'selected_catalog_id', identification_row->'alcohol_item_id',
      'resolved_alcohol_item_id', resolved_alcohol_item_id,
      'entered_alcohol_name', identification_row->'entered_alcohol_name',
      'alcohol_name_snapshot', identification_row->'alcohol_name_snapshot'
    ),
    2,
    rendered_row #>> '{metadata,rule_version}',
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
