-- A card the reader deletes is kept the way a withdrawn member's cards are:
-- at once it moves to withdrawn_drink_records with no owner, memo or free
-- text, and the original record is removed. Before, a deleted record stayed
-- on the account, hidden, and was dropped without a trace at withdrawal.
-- One function now does the move for both the single delete and the
-- withdrawal, and records already marked deleted are moved here.

create function public.soolgyul_retain_drink_records(
  target_user_id uuid,
  only_record_id uuid default null
) returns integer
    language plpgsql security definer
    set search_path to ''
    as $$
declare account_row public.users%rowtype; retained_count integer; birth integer;
begin
  select * into account_row from public.users where id=target_user_id;
  if not found then return 0; end if;

  -- Keep only what cannot point back to the reader: no memo, no free text,
  -- no names, account metadata or raw snapshots.
  birth := extract(year from account_row.birth_date)::integer;
  insert into public.withdrawn_drink_records(birth_year_band,gender,record_data)
  select birth - birth % 5,
    case when account_row.gender_consent_accepted_at is not null then account_row.gender end,
    jsonb_build_object(
      'alcohol_item_id',r.alcohol_item_id,
      'questionnaire_version',r.questionnaire_version,
      'answers',coalesce((select jsonb_agg(jsonb_build_object(
        'question_key',a.question_key,
        'selected_option_keys',a.selected_option_keys) order by a.question_key,a.id)
        from public.drink_record_answers a where a.drink_record_id=r.id),'[]'::jsonb),
      'card',(select public.soolgyul_strip_retained_card_links(jsonb_build_object('rendered_snapshot',c.rendered_snapshot))
        from public.taste_cards c where c.drink_record_id=r.id)
    )
  from public.drink_records r
  where r.user_id=target_user_id
    and (only_record_id is null or r.id=only_record_id);
  get diagnostics retained_count = row_count;

  -- Converted anonymous attempts can still carry an anonymous proof. Remove
  -- them by record linkage too, not just by owner_user_id.
  delete from public.taste_card_generation_attempts a
  where (only_record_id is null and a.owner_user_id=target_user_id) or exists (
    select 1 from public.drink_records r where r.user_id=target_user_id
      and (only_record_id is null or r.id=only_record_id)
      and (r.id=a.reserved_record_id or exists (
        select 1 from public.taste_cards c where c.drink_record_id=r.id
          and c.id in (a.result_summary_id, a.claim_snapshot_id))));
  delete from public.drink_records r
  where r.user_id=target_user_id
    and (only_record_id is null or r.id=only_record_id);
  return retained_count;
end;
$$;

revoke all on function public.soolgyul_retain_drink_records(uuid, uuid)
  from public, anon, authenticated;
grant all on function public.soolgyul_retain_drink_records(uuid, uuid) to service_role;

create or replace function public.soolgyul_delete_owned_drink_record(target_result_summary_id uuid, target_user_id uuid) returns uuid
    language plpgsql security definer
    set search_path to 'public', 'pg_temp'
    as $$
declare
  deleted_record_id uuid;
begin
  if not public.soolgyul_account_active(target_user_id) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  select record_row.id into deleted_record_id
    from public.drink_records record_row
    join public.taste_cards summary_row on summary_row.drink_record_id = record_row.id
    where summary_row.id = target_result_summary_id
      and record_row.user_id = target_user_id
    for update of record_row;

  if deleted_record_id is null then
    raise exception using errcode = 'P0002', message = 'owned result not found';
  end if;
  perform public.soolgyul_retain_drink_records(target_user_id, deleted_record_id);
  return deleted_record_id;
end;
$$;

create or replace function public.soolgyul_finalize_withdrawn_account_data(target_user_id uuid) returns integer
    language plpgsql security definer
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

  retained_count := public.soolgyul_retain_drink_records(target_user_id);
  perform public.soolgyul_anonymize_discovery_events(target_user_id);
  update public.users set birth_date=null,gender=null,
    gender_consent_accepted_at=null,gender_consent_version=null,
    display_name=null,email=null,provider_user_id=gen_random_uuid()::text,
    age_confirmed_at=null,profile_created_at=null,last_sign_in_at=null,
    purged_at=statement_timestamp(),updated_at=statement_timestamp()
  where id=target_user_id;
  return retained_count;
end;
$$;

comment on table public.withdrawn_drink_records is
  'Records kept without their owner: a card its reader deleted, and every card of a withdrawn member.';

-- Records marked deleted under the old rule.
select public.soolgyul_retain_drink_records(r.user_id, r.id)
from public.drink_records r
where r.deleted_at is not null and r.user_id is not null;
