-- A withdrawn reader's records are kept without a period, so they must be
-- anonymous information: the memo and free-text answers (which can name a
-- person) go, and the exact birth year is folded to its five-year band. The
-- purge also cuts the account link of the reader's discovery events.

alter table public.withdrawn_drink_records
  add column birth_year_band integer
  constraint withdrawn_drink_records_birth_year_band_check
  check (birth_year_band between 1900 and 2095 and birth_year_band % 5 = 0);

update public.withdrawn_drink_records w
set birth_year_band = w.birth_year - w.birth_year % 5,
  record_data = (w.record_data - 'one_line_note') || jsonb_build_object(
    'answers', coalesce((
      select jsonb_agg(a.value - 'free_text' order by a.ordinality)
      from jsonb_array_elements(coalesce(w.record_data->'answers', '[]'::jsonb))
        with ordinality a
    ), '[]'::jsonb));

alter table public.withdrawn_drink_records drop column birth_year;

comment on table public.withdrawn_drink_records is
  'Anonymous post-withdrawal analysis records: five-year birth band, consented gender, product, chosen answers and card text. No memo, free text, ids or account links. No public or owner access.';

create or replace function public.soolgyul_finalize_withdrawn_account_data(target_user_id uuid)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare account_row public.users%rowtype; retained_count integer; birth integer;
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

  -- Keep only what cannot point back to the reader: no memo, no free text,
  -- no inquiries, names, account metadata, consent history or raw snapshots.
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
