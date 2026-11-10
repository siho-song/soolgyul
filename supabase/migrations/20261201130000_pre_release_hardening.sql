-- Closes what a caller without an account, or with one they made
-- themselves, could do before release: sign up by email and become a member,
-- make cards without end by sending a new session id each time, and store
-- text of any length. Searches by visitors were never removed; they now go
-- after thirteen months, the same horizon as a member's.
set local lock_timeout = '5s';

create or replace function public.soolgyul_provision_auth_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  resolved_provider text;
  trusted_provider_user_id text;
begin
  if lower(coalesce(new.raw_app_meta_data ->> 'provider', '')) = 'email'
     and lower(coalesce(new.raw_app_meta_data ->> 'soolgyul_test_user', '')) = 'true'
  then
    resolved_provider := 'test';
  else
    resolved_provider := lower(
      coalesce(new.raw_app_meta_data ->> 'provider', '')
    );
  end if;

  -- Members come from Kakao, Apple or Google. An email account becomes one
  -- only when the service marked it as staff: app metadata is written with
  -- the service key alone, never by the person signing up.
  if resolved_provider = 'email'
     and lower(coalesce(new.raw_app_meta_data ->> 'soolgyul_staff', '')) <> 'true'
  then
    return new;
  end if;
  if resolved_provider not in ('kakao', 'apple', 'google', 'test', 'email') then
    return new;
  end if;

  trusted_provider_user_id := new.id::text;
  if exists (
    select 1
    from public.users product_user
    where product_user.auth_provider = resolved_provider
      and product_user.provider_user_id = trusted_provider_user_id
      and product_user.id <> new.id
  ) then
    raise exception using
      errcode = '23505',
      message = 'trusted_auth_identity_conflict';
  end if;

  begin
    insert into public.users (
      id,
      auth_provider,
      provider_user_id,
      email,
      created_at,
      last_sign_in_at
    ) values (
      new.id,
      resolved_provider,
      trusted_provider_user_id,
      new.email,
      coalesce(new.created_at, now()),
      new.last_sign_in_at
    )
    on conflict (id) do update
    set auth_provider = excluded.auth_provider,
        provider_user_id = excluded.provider_user_id,
        email = excluded.email,
        last_sign_in_at = excluded.last_sign_in_at;
  exception
    when unique_violation then
      raise exception using
        errcode = '23505',
        message = 'trusted_auth_identity_conflict';
  end;

  return new;
end
$$;

-- The admin API inserts the account first and writes its app metadata right
-- after, so the staff mark arrives as an update.
create trigger soolgyul_auth_user_provision_staff
  after update of raw_app_meta_data on auth.users
  for each row
  when (
    lower(coalesce(new.raw_app_meta_data ->> 'soolgyul_staff', '')) = 'true'
    and lower(coalesce(old.raw_app_meta_data ->> 'soolgyul_staff', '')) <> 'true'
  )
  execute function public.soolgyul_provision_auth_user();

alter table public.drink_records
  add constraint drink_records_one_line_note_length
  check (char_length(one_line_note) <= 2000);

create or replace function public.soolgyul_update_my_drink_record_note(p_record_id uuid, p_note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  target_user_id uuid := auth.uid();
begin
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_record_id is null then
    raise exception using errcode = '22023', message = 'record_id_required';
  end if;
  if not public.soolgyul_account_active(target_user_id) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  if char_length(p_note) > 2000 then
    raise exception using errcode = '22023', message = 'note_too_long';
  end if;

  -- Blank clears the note.
  update public.drink_records
    set one_line_note = nullif(btrim(coalesce(p_note, '')), ''),
        updated_at = now()
    where id = p_record_id and user_id = target_user_id and deleted_at is null;
  if not found then
    raise exception using errcode = 'P0002', message = 'record_not_found';
  end if;
end
$$;

-- The session id is the caller's own text, so the per-session limit alone
-- stops nobody. The function now also passes a keyed digest of the address
-- the request came from, and one address or all visitors together can only
-- make so many cards.
alter table public.taste_card_generation_attempts
  add column client_address_digest text;
create index taste_card_generation_attempts_client_address_idx
  on public.taste_card_generation_attempts (client_address_digest, created_at)
  where client_address_digest is not null;

create or replace function public.soolgyul_limit_anonymous_taste_card_attempts() returns trigger
language plpgsql security definer
set search_path to ''
as $$
begin
  if new.anonymous_session_digest is null then
    return new;
  end if;
  -- Requests of one session, and of one address, wait for each other, so
  -- the counts below see every earlier one.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.anonymous_session_digest, 0)
  );
  if (
    select count(*)
    from public.taste_card_generation_attempts attempt_row
    where attempt_row.anonymous_session_digest = new.anonymous_session_digest
      and attempt_row.created_at > now() - interval '24 hours'
  ) >= 10 then
    raise exception using
      errcode = 'P0001',
      message = 'anonymous_generation_limit_reached';
  end if;
  if new.client_address_digest is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(new.client_address_digest, 1)
    );
    if (
      select count(*)
      from public.taste_card_generation_attempts attempt_row
      where attempt_row.client_address_digest = new.client_address_digest
        and attempt_row.created_at > now() - interval '24 hours'
    ) >= 40 then
      raise exception using
        errcode = 'P0001',
        message = 'anonymous_generation_limit_reached';
    end if;
  end if;
  if (
    select count(*)
    from public.taste_card_generation_attempts attempt_row
    where attempt_row.anonymous_session_digest is not null
      and attempt_row.created_at > now() - interval '1 hour'
  ) >= 1000 then
    raise exception using
      errcode = 'P0001',
      message = 'anonymous_generation_limit_reached';
  end if;
  return new;
end;
$$;

-- A visitor's row never had a member behind it: no account, no age band, no
-- gender. A member's row keeps its band after the account is cut off.
select cron.schedule('soolgyul-discovery-visitor-retention', '50 18 * * *',
  $job$delete from public.drink_discovery_events where user_id is null and birth_year_band is null and gender is null and occurred_at < now() - interval '13 months'$job$);
