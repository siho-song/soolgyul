-- ADR-150 anonymous retention with the ADR-186 scope: an anonymous session may
-- start at most ten generations per 24 hours, and unclaimed anonymous records,
-- answers, cards and attempts are deleted 24 hours after the server first
-- received them. Anonymous records never carry a photo path, so there is no
-- storage object to remove.

create function public.soolgyul_limit_anonymous_taste_card_attempts()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.anonymous_session_digest is null then
    return new;
  end if;
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
  return new;
end;
$$;

create trigger taste_card_generation_attempts_anonymous_limit
  before insert on public.taste_card_generation_attempts
  for each row execute function public.soolgyul_limit_anonymous_taste_card_attempts();

create function public.soolgyul_purge_expired_anonymous_taste_cards(batch_limit integer default 500)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  cutoff timestamptz := now() - interval '24 hours';
  deleted_records integer;
begin
  -- Attempts first: an attempt still referencing the card snapshot would block
  -- the cascading card delete below.
  delete from public.taste_card_generation_attempts attempt_row
  where attempt_row.anonymous_session_digest is not null
    and attempt_row.created_at < cutoff;

  with expired as (
    select record_row.id
    from public.drink_records record_row
    where record_row.user_id is null
      and record_row.anonymous_session_id is not null
      and record_row.photo_storage_path is null
      and record_row.created_at < cutoff
    order by record_row.created_at
    limit greatest(batch_limit, 1)
  )
  delete from public.drink_records record_row
  using expired
  where record_row.id = expired.id;
  get diagnostics deleted_records = row_count;
  return deleted_records;
end;
$$;

revoke execute on function public.soolgyul_limit_anonymous_taste_card_attempts()
  from public, anon, authenticated;
revoke execute on function public.soolgyul_purge_expired_anonymous_taste_cards(integer)
  from public, anon, authenticated;
grant execute on function public.soolgyul_purge_expired_anonymous_taste_cards(integer)
  to service_role;

select cron.schedule(
  'soolgyul-anonymous-retention',
  '*/5 * * * *',
  'select public.soolgyul_purge_expired_anonymous_taste_cards();'
);
