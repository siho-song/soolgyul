-- What readers look for: a pick from search, a search that found nothing, a
-- label read with or without a match, and a drink whose fit was opened. The
-- misses tell the catalog what to add; all of it counts interest by drink.
-- A member's events stay linked to the account for 13 months. After that, or
-- when the account is purged, the link goes and only the day, a five-year
-- birth band and the consented gender remain: anonymous, kept without a
-- period. A guest's events never carry an identity.

create table public.drink_discovery_events (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default statement_timestamp(),
  kind text not null check (kind in
    ('search_pick', 'search_empty', 'label_match', 'label_miss', 'fit_view')),
  surface text not null check (surface in ('record', 'taste_fit')),
  alcohol_item_id uuid references public.alcohol_items(id) on delete set null,
  query_text text check (char_length(query_text) between 1 and 120),
  user_id uuid references public.users(id) on delete set null,
  birth_year_band integer
    check (birth_year_band between 1900 and 2095 and birth_year_band % 5 = 0),
  gender text check (gender in ('male', 'female', 'other')),
  -- A miss is only its words; a match or a view is only its drink.
  constraint drink_discovery_events_query_shape check (
    case kind
      when 'search_empty' then query_text is not null
      when 'label_miss' then query_text is not null
      when 'search_pick' then true
      else query_text is null
    end),
  constraint drink_discovery_events_identity_or_profile check (
    user_id is null or (birth_year_band is null and gender is null))
);

create index drink_discovery_events_occurred_at_idx
  on public.drink_discovery_events (occurred_at);
create index drink_discovery_events_user_idx
  on public.drink_discovery_events (user_id) where user_id is not null;
create index drink_discovery_events_item_idx
  on public.drink_discovery_events (alcohol_item_id)
  where alcohol_item_id is not null;

alter table public.drink_discovery_events enable row level security;
revoke all on public.drink_discovery_events from anon, authenticated;

comment on table public.drink_discovery_events is
  'What readers look for. Linked to an active member for at most 13 months, then anonymous (day, five-year birth band, consented gender). Written only through soolgyul_record_discovery_event; no client reads.';

-- The app's one write. A member over 300 events an hour, or guests together
-- over 600 a minute, are dropped silently: the events are a signal, not a
-- record the reader relies on.
create or replace function public.soolgyul_record_discovery_event(
  event_kind text,
  event_surface text,
  target_alcohol_item_id uuid default null,
  event_query text default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  actor uuid := auth.uid();
  member uuid;
  cleaned text := nullif(left(btrim(regexp_replace(
    coalesce(event_query, ''), '\s+', ' ', 'g')), 120), '');
begin
  if actor is not null then
    -- A reader on the way out is no longer counted.
    if not public.soolgyul_account_active(actor) then return; end if;
    member := actor;
    if (select count(*) from public.drink_discovery_events
        where user_id = member
          and occurred_at > statement_timestamp() - interval '1 hour') >= 300 then
      return;
    end if;
  elsif (select count(*) from public.drink_discovery_events
         where user_id is null
           and occurred_at > statement_timestamp() - interval '1 minute') >= 600 then
    return;
  end if;
  insert into public.drink_discovery_events
    (kind, surface, alcohol_item_id, query_text, user_id)
  values (event_kind, event_surface, target_alcohol_item_id, cleaned, member);
exception
  when check_violation or foreign_key_violation then
    raise exception 'discovery_event_invalid' using errcode = '22023';
end;
$$;

revoke execute on function public.soolgyul_record_discovery_event(text, text, uuid, text) from public;
grant execute on function public.soolgyul_record_discovery_event(text, text, uuid, text) to anon, authenticated;

-- Cuts the account link: every event of target_user_id, or with no target
-- every member event older than 13 months. The day is kept in Korean time.
create or replace function public.soolgyul_anonymize_discovery_events(target_user_id uuid default null)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare changed integer;
begin
  update public.drink_discovery_events e
  set user_id = null,
    occurred_at = date_trunc('day', e.occurred_at, 'Asia/Seoul'),
    birth_year_band = extract(year from u.birth_date)::integer
      - extract(year from u.birth_date)::integer % 5,
    gender = case when u.gender_consent_accepted_at is not null then u.gender end
  from public.users u
  where e.user_id = u.id
    and (case when target_user_id is null
      then e.occurred_at < statement_timestamp() - interval '13 months'
      else e.user_id = target_user_id end);
  get diagnostics changed = row_count;
  return changed;
end;
$$;

revoke execute on function public.soolgyul_anonymize_discovery_events(uuid) from public, anon, authenticated;

select cron.schedule('soolgyul-discovery-anonymize', '30 18 * * *',
  'select public.soolgyul_anonymize_discovery_events()');
