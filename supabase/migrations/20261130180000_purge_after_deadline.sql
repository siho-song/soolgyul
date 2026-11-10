-- An account past its deletion day is purged whether or not its social link
-- is still marked revoked. A login during the 30 days resets that mark, and
-- a member who then left the app without choosing was never purged, against
-- the promised date. The link is still revoked at the request and again
-- when the member keeps the deletion after a new login.

create or replace function public.soolgyul_finalize_withdrawn_account_data(target_user_id uuid) returns integer
    language plpgsql security definer
    set search_path to ''
    as $$
declare account_row public.users%rowtype; retained_count integer;
begin
  select * into account_row from public.users where id=target_user_id for update;
  if not found then return 0; end if;
  if account_row.purged_at is not null then return 0; end if;
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
