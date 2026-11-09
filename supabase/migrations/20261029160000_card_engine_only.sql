-- The old claim engine is gone: a card is now written whole by the card-facts
-- engine, so the finalizer takes one rendered view and one private snapshot
-- (the record and the facts read from it) instead of the claim plans and
-- version vector it used to validate column by column.

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
  rendered_row jsonb := input_bundle->'rendered_view';
  snapshot_row jsonb := input_bundle->'semantic_snapshot';
  answer_row jsonb;
  generated_snapshot_id uuid := gen_random_uuid();
  principal_kind text := input_bundle #>> '{principal,kind}';
  selected_catalog_id uuid;
  resolved_alcohol_item_id uuid;
begin
  if jsonb_typeof(input_bundle) is distinct from 'object'
    or jsonb_typeof(request_row) is distinct from 'object'
    or jsonb_typeof(identification_row) is distinct from 'object'
    or jsonb_typeof(rendered_row) is distinct from 'object'
    or jsonb_typeof(snapshot_row) is distinct from 'object'
  then
    raise exception using
      errcode = '22023',
      message = 'taste card finalization bundle is invalid';
  end if;

  if input_bundle->>'wire_schema_version' is distinct from 'taste-card-result-wire-v3' then
    raise exception using
      errcode = '22023',
      message = 'taste card wire schema version is invalid';
  end if;

  if (
    rendered_row #>> '{metadata,schema_version}' is distinct from '3'
    or rendered_row #>> '{metadata,snapshot_ref}'
      is distinct from input_bundle->>'snapshot_ref'
    or nullif(btrim(coalesce(input_bundle->>'engine_version', '')), '') is null
    or pg_column_size(rendered_row) > 131072
    or pg_column_size(snapshot_row) > 524288
  ) then
    raise exception using
      errcode = '22023',
      message = 'taste card snapshot is invalid';
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
    input_bundle->>'snapshot_ref',
    'final',
    input_bundle->>'engine_version',
    snapshot_row,
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
