-- Sign-in records of our own. The Auth audit log stores the time of a login
-- but leaves the IP address empty, so it cannot say where a member connected
-- from. Auth does write the address on the session row; a trigger copies it
-- here when a session starts and whenever its address changes. Rows are kept
-- three months (Protection of Communications Secrets Act) and then deleted,
-- also for a withdrawn member. No client reads them.

create table public.sign_in_records (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default statement_timestamp(),
  -- No foreign key: the record outlives the account for its three months.
  user_id uuid not null,
  ip inet not null,
  user_agent text
);

create index sign_in_records_occurred_at_idx on public.sign_in_records (occurred_at);
create index sign_in_records_user_idx on public.sign_in_records (user_id, occurred_at);

alter table public.sign_in_records enable row level security;
revoke all on public.sign_in_records from anon, authenticated;

comment on table public.sign_in_records is
  'When and from which IP address an account signed in or moved to a new address. Written by a trigger on auth.sessions, deleted after three months; no client reads.';

create or replace function public.soolgyul_record_sign_in()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.ip is not null
     and (tg_op = 'INSERT' or new.ip is distinct from old.ip) then
    insert into public.sign_in_records (user_id, ip, user_agent)
    values (new.user_id, new.ip, left(new.user_agent, 400));
  end if;
  return null;
exception when others then
  -- A sign-in never fails because its record could not be written.
  return null;
end;
$$;

revoke execute on function public.soolgyul_record_sign_in() from public, anon, authenticated;

create trigger soolgyul_sign_in_record
  after insert or update of ip on auth.sessions
  for each row execute function public.soolgyul_record_sign_in();

-- The audit log job gives way to this table's.
select cron.unschedule('soolgyul-sign-in-records-retention');
select cron.schedule('soolgyul-sign-in-records-retention', '10 18 * * *',
  $$delete from public.sign_in_records where occurred_at < now() - interval '3 months'$$);
