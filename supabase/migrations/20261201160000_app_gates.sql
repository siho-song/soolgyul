-- An app on a phone stays at the version it was installed with, while the
-- server it talks to moves on. Nothing could tell an old version that it no
-- longer works with the server, or tell anyone that the service is paused
-- for maintenance. This table holds, per platform, the oldest version still
-- allowed in and an optional maintenance notice; the app reads it when it
-- starts and when it comes back to the front. It is changed by hand (SQL)
-- and read by everyone, signed in or not.
set local lock_timeout = '5s';

create table public.app_gates (
  platform text primary key
    check (platform in ('ios', 'android', 'web')),
  -- Versions below this are asked to update. 0.0.0 lets every version in.
  minimum_version text not null default '0.0.0'
    check (minimum_version ~ '^[0-9]{1,4}[.][0-9]{1,4}[.][0-9]{1,4}$'),
  -- Shown while set; null means the service is open.
  maintenance_message text
    check (char_length(maintenance_message) between 1 and 300),
  updated_at timestamptz not null default now()
);

alter table public.app_gates enable row level security;

create policy app_gates_public_read on public.app_gates
  for select to anon, authenticated using (true);

revoke all on table public.app_gates from public, anon, authenticated;
grant select on table public.app_gates to anon, authenticated;
grant all on table public.app_gates to service_role;

insert into public.app_gates (platform) values ('ios'), ('android'), ('web');
