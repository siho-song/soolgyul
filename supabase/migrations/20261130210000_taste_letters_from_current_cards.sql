-- The 네 글자 are computed outside the database from the cards read a moment
-- earlier. When a save and a delete overlapped, the slower one could store
-- letters computed from a card list that had already changed. The save now
-- names the records it was computed from and is refused when they are no
-- longer the account's cards, so the caller reads again and recomputes.
-- The ten-a-day limit for cards made without an account counted and then
-- inserted; two requests at once could both pass. They now take turns.
set local lock_timeout = '5s';

drop function public.soolgyul_save_taste_letters(uuid, jsonb, jsonb);

create function public.soolgyul_save_taste_letters(
  target_user_id uuid,
  state jsonb,
  changes jsonb,
  -- The records the letters were computed from. Null skips the check, for
  -- a caller deployed before the check existed.
  source_record_ids uuid[] default null
) returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if jsonb_typeof(state) is distinct from 'object'
    or jsonb_typeof(state->'axes') is distinct from 'object'
    or jsonb_typeof(changes) is distinct from 'array'
  then
    raise exception using errcode = '22023', message = 'taste letters payload is invalid';
  end if;

  -- One save at a time per account; the card list is read after the wait.
  perform 1 from public.users u where u.id = target_user_id for update;

  if source_record_ids is not null and (
    select coalesce(array_agg(distinct card.drink_record_id order by card.drink_record_id), '{}'::uuid[])
    from public.taste_cards card
    join public.drink_records record_row on record_row.id = card.drink_record_id
    where record_row.user_id = target_user_id
      and record_row.deleted_at is null
      and card.lifecycle = 'final'
  ) is distinct from (
    select coalesce(array_agg(distinct id order by id), '{}'::uuid[])
    from unnest(source_record_ids) as id
  ) then
    -- Not a serialization-failure code (40001): the API layer would run the
    -- call again on its own, without end, and the answer would never change.
    raise exception using errcode = 'P0001', message = 'taste_letters_stale';
  end if;

  insert into public.taste_letters (user_id, rule_version, record_count, axes, updated_at)
  values (
    target_user_id,
    state->>'rule_version',
    (state->>'record_count')::integer,
    state->'axes',
    now()
  )
  on conflict (user_id) do update
    set rule_version = excluded.rule_version,
        record_count = excluded.record_count,
        axes = excluded.axes,
        updated_at = excluded.updated_at;

  delete from public.taste_letter_changes where user_id = target_user_id;
  insert into public.taste_letter_changes (
    user_id, drink_record_id, axis, from_letter, to_letter,
    left_share, right_share, product_name, changed_at, rule_version
  )
  select
    target_user_id,
    (change->>'record_id')::uuid,
    change->>'axis',
    change->>'from_letter',
    change->>'to_letter',
    (change->>'left_share')::integer,
    (change->>'right_share')::integer,
    change->>'product_name',
    (change->>'changed_at')::timestamptz,
    state->>'rule_version'
  from jsonb_array_elements(changes) as change;
end;
$$;

revoke all on function public.soolgyul_save_taste_letters(uuid, jsonb, jsonb, uuid[]) from public, anon, authenticated;
grant all on function public.soolgyul_save_taste_letters(uuid, jsonb, jsonb, uuid[]) to service_role;

create or replace function public.soolgyul_limit_anonymous_taste_card_attempts() returns trigger
language plpgsql security definer
set search_path to ''
as $$
begin
  if new.anonymous_session_digest is null then
    return new;
  end if;
  -- Requests of one session wait for each other, so the count below sees
  -- every earlier one.
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
  return new;
end;
$$;
