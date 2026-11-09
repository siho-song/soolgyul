-- A reader can no longer record a drink by typing its name: every record
-- points at one catalog item. The entered name column, its pair constraint
-- and the direct_input branches of the record functions go. The result
-- builder now names the wire the card engine writes (v3; it still said v2,
-- which the server refuses).

drop trigger drink_records_guard_final_identity on public.drink_records;
-- The only rows without a catalog item are the seed records of the synthetic
-- test account; their cards were already removed and the dependent tables
-- cascade.
delete from public.drink_records where alcohol_item_id is null;
alter table public.drink_records
  drop constraint drink_records_identity_check,
  drop column entered_alcohol_name,
  alter column alcohol_item_id set not null;
create trigger drink_records_guard_final_identity
  before update of questionnaire_version, alcohol_item_id
  on public.drink_records
  for each row
  when (old.questionnaire_version is distinct from new.questionnaire_version
    or old.alcohol_item_id is distinct from new.alcohol_item_id)
  execute function public.soolgyul_guard_final_drink_record_identity();

create or replace function public.soolgyul_build_taste_card_result(target_result_summary_id uuid)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select jsonb_build_object(
    'wire_schema_version', 'taste-card-result-wire-v3',
    'result_id', summary_row.id::text,
    'record_id', record_row.id::text,
    'snapshot_ref', summary_row.snapshot_ref,
    'ownership_state', case
      when record_row.user_id is null then 'anonymous'
      else 'saved'
    end,
    'alcohol_identification', jsonb_build_object(
      'mode', 'catalog_match',
      'alcohol_item_id', record_row.alcohol_item_id,
      'alcohol_name_snapshot', item_row.name_ko,
      'category', category_row.category_key
    ),
    'rendered_snapshot', summary_row.rendered_snapshot,
    'created_at', summary_row.snapshot_created_at
  )
  from public.taste_cards summary_row
  join public.drink_records record_row
    on record_row.id = summary_row.drink_record_id
  join public.alcohol_items item_row
    on item_row.id = record_row.alcohol_item_id
  left join public.alcohol_categories category_row
    on category_row.id = item_row.alcohol_category_id
  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id
    and record_row.deleted_at is null;
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

  if identification_row->>'mode' is distinct from 'catalog_match' then
    raise exception using errcode = '22023', message = 'identification mode is invalid';
  end if;

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

  insert into public.drink_records (
    id,
    user_id,
    anonymous_session_id,
    questionnaire_version,
    alcohol_item_id,
    one_line_note,
    idempotency_key
  )
  values (
    attempt_row.reserved_record_id,
    case when principal_kind = 'authenticated' then attempt_row.owner_user_id else null end,
    case when principal_kind = 'anonymous' then request_row->>'anonymous_session_id' else null end,
    request_row->>'questionnaire_version',
    resolved_alcohol_item_id,
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
