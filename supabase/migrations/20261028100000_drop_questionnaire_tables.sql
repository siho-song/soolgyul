-- The questionnaire's questions and options live in the versioned server
-- registry (sensory_questionnaire_v1.ts); the DB copies were never read for the
-- live version. Records keep the version name as text, so the three
-- questionnaire tables go.

alter table public.drink_records add column questionnaire_version text;

update public.drink_records r
set questionnaire_version = v.version_key
from public.questionnaire_versions v
where v.id = r.questionnaire_version_id;

alter table public.drink_records
  alter column questionnaire_version set not null,
  add constraint drink_records_questionnaire_version_valid
    check (char_length(questionnaire_version) between 1 and 64);

drop trigger drink_records_guard_final_identity on public.drink_records;
alter table public.drink_records drop column questionnaire_version_id;
create trigger drink_records_guard_final_identity
  before update of questionnaire_version, alcohol_item_id, entered_alcohol_name
  on public.drink_records
  for each row
  when (old.questionnaire_version is distinct from new.questionnaire_version
    or old.alcohol_item_id is distinct from new.alcohol_item_id
    or old.entered_alcohol_name is distinct from new.entered_alcohol_name)
  execute function public.soolgyul_guard_final_drink_record_identity();

alter table public.drink_record_answers
  drop column questionnaire_question_id,
  drop column questionnaire_version_id;

drop table public.questionnaire_options;
drop table public.questionnaire_questions;
drop table public.questionnaire_versions;
drop function public.soolgyul_guard_questionnaire_content();
drop function public.soolgyul_guard_questionnaire_version();

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
      'card',(select public.soolgyul_strip_retained_card_links(jsonb_build_object(
        'result_type_key',c.result_type_key,'taste_axis_scores',c.taste_axis_scores,
        'preference_cues',c.preference_cues,'next_drink_directions',c.next_drink_directions,
        'burdensome_directions',c.burdensome_directions,
        'summary_paragraphs',c.summary_paragraphs,'share_card_text',c.share_card_text,
        'rendered_snapshot',c.rendered_snapshot))
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
