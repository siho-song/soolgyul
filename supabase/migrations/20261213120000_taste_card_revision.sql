-- A member may correct the answers of a saved record on its tasting note.
-- The card written from them is then written again in place: the record,
-- the card's id and its date stay, so lists, likes and links keep pointing
-- at it. Refused when the card changed since the revision was read from it.

-- A final card's content was never to change. It still does not, except
-- within a revision: the row's identity and its date stay even then.
create or replace function public.soolgyul_guard_taste_card_content()
 returns trigger
 language plpgsql
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if new is not distinct from old then return new; end if;
  if current_setting('soolgyul.taste_card_revision', true) = 'on'
    and new.id = old.id
    and new.drink_record_id = old.drink_record_id
    and new.snapshot_id = old.snapshot_id
    and new.lifecycle = old.lifecycle
    and new.snapshot_created_at = old.snapshot_created_at
  then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'Final taste card content is immutable';
end;
$function$;

create function public.soolgyul_revise_taste_card(input_bundle jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  target_user_id uuid := nullif(input_bundle->>'user_id', '')::uuid;
  target_result_id uuid := nullif(input_bundle->>'result_id', '')::uuid;
  rendered_row jsonb := input_bundle->'rendered_view';
  snapshot_row jsonb := input_bundle->'semantic_snapshot';
  answer_rows jsonb := input_bundle->'answers';
  target_record_id uuid;
  held_snapshot_ref text;
begin
  if target_user_id is null
    or target_result_id is null
    or jsonb_typeof(rendered_row) is distinct from 'object'
    or jsonb_typeof(snapshot_row) is distinct from 'object'
    or jsonb_typeof(answer_rows) is distinct from 'array'
    or jsonb_array_length(answer_rows) = 0
    or input_bundle->>'wire_schema_version'
      is distinct from 'taste-card-result-wire-v3'
    or rendered_row #>> '{metadata,schema_version}' is distinct from '3'
    or rendered_row #>> '{metadata,snapshot_ref}'
      is distinct from input_bundle->>'snapshot_ref'
    or nullif(btrim(coalesce(input_bundle->>'engine_version', '')), '') is null
    or pg_column_size(rendered_row) > 131072
    or pg_column_size(snapshot_row) > 524288
  then
    raise exception using
      errcode = '22023',
      message = 'taste card revision bundle is invalid';
  end if;

  -- The same user-then-record lock order as account and profile writes.
  perform 1 from public.users u where u.id = target_user_id for update;
  if not found or not public.soolgyul_account_active(target_user_id) then
    raise exception using errcode = '42501', message = 'active account required';
  end if;

  select card_row.drink_record_id, card_row.snapshot_ref
  into target_record_id, held_snapshot_ref
  from public.taste_cards card_row
  join public.drink_records record_row
    on record_row.id = card_row.drink_record_id
  where card_row.id = target_result_id
    and record_row.user_id = target_user_id
  for update of record_row, card_row;

  if not found then
    raise exception using errcode = 'P0002', message = 'owned result not found';
  end if;
  if held_snapshot_ref is distinct from input_bundle->>'base_snapshot_ref' then
    raise exception using errcode = 'P0001', message = 'revision_conflict';
  end if;

  delete from public.drink_record_answers
  where drink_record_id = target_record_id;

  insert into public.drink_record_answers (
    drink_record_id,
    question_key,
    selected_option_keys
  )
  select
    target_record_id,
    answer_row->>'question_key',
    array(
      select jsonb_array_elements_text(
        coalesce(answer_row->'selected_option_keys', '[]'::jsonb)
      )
    )
  from jsonb_array_elements(answer_rows) answer_row;

  -- Opens the content guard for this transaction's one update.
  perform set_config('soolgyul.taste_card_revision', 'on', true);
  update public.taste_cards
  set snapshot_ref = input_bundle->>'snapshot_ref',
      canonical_schema_version = input_bundle->>'engine_version',
      semantic_snapshot = snapshot_row,
      rendered_snapshot = rendered_row
  where id = target_result_id;
  perform set_config('soolgyul.taste_card_revision', 'off', true);

  update public.drink_records
  set updated_at = now()
  where id = target_record_id;

  return public.soolgyul_build_taste_card_result(target_result_id);
end;
$function$;

revoke all on function public.soolgyul_revise_taste_card(jsonb) from public;
revoke all on function public.soolgyul_revise_taste_card(jsonb) from anon, authenticated;
grant execute on function public.soolgyul_revise_taste_card(jsonb) to service_role;

comment on table public.taste_cards is
  'One taste card per drink record: the rendered content and the internal interpretation. Written again in place when the member corrects the record''s answers.';
