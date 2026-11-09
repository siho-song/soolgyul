-- A card made on the web now follows the visitor into the app: the result's
-- conversion ticket travels in the store link and is claimed after the app's
-- sign-in. Installing and signing in can take days, so unclaimed anonymous
-- records, answers, cards and attempts are kept 30 days instead of 24 hours.
-- The ten-generations-per-24-hours limit on an anonymous session is unchanged.

create or replace function public.soolgyul_purge_expired_anonymous_taste_cards(batch_limit integer default 500)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  cutoff timestamptz := now() - interval '30 days';
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
