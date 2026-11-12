-- The table that keeps a record without its owner was named for withdrawal,
-- but a card a member deletes goes there too. It takes the name of what it
-- holds: retained records.
set local lock_timeout = '5s';

alter table public.withdrawn_drink_records rename to retained_drink_records;
alter table public.retained_drink_records
  rename constraint withdrawn_drink_records_pkey to retained_drink_records_pkey;
alter table public.retained_drink_records
  rename constraint withdrawn_drink_records_birth_year_band_check
  to retained_drink_records_birth_year_band_check;
alter table public.retained_drink_records
  rename constraint withdrawn_drink_records_gender_check
  to retained_drink_records_gender_check;
alter table public.retained_drink_records
  rename constraint withdrawn_drink_records_record_data_check
  to retained_drink_records_record_data_check;

comment on table public.retained_drink_records is
  'A record kept without its owner once a member deletes a card or an account is deleted: five-year birth band, consented gender, product, chosen answers and card text. No memo, no account or record id; no client reads.';

create or replace function public.soolgyul_retain_drink_records(target_user_id uuid, only_record_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare account_row public.users%rowtype; retained_count integer; birth integer;
begin
  select * into account_row from public.users where id=target_user_id;
  if not found then return 0; end if;

  -- Keep only what cannot point back to the reader: no memo,
  -- no names, account metadata or raw snapshots.
  birth := extract(year from account_row.birth_date)::integer;
  insert into public.retained_drink_records(birth_year_band,gender,record_data)
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
$function$;
