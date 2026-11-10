-- A visitor tries the product with a few cards; the rest are made in the
-- app. One address now starts five a day instead of forty.
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
    ) >= 5 then
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
