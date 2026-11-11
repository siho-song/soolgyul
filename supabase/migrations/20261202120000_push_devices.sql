-- A phone that allows the app's notifications hands over its address at the
-- notification service, and the server keeps it to reach that phone. The
-- address is forgotten when the member turns notifications off or signs out,
-- and with the account when it is removed.
-- A phone has one address and one account at a time: registering the address
-- again under another account moves it. A member keeps ten phones at most,
-- the ones registered last.
-- No client reads or writes the table; the two functions are the only way in.
set local lock_timeout = '5s';

create table public.user_push_devices (
  token text primary key,
  user_id uuid not null references public.users(id) on delete cascade,
  platform text not null,
  registered_at timestamptz not null default now(),
  constraint user_push_devices_platform_check
    check (platform in ('android', 'ios')),
  constraint user_push_devices_token_check
    check (char_length(token) between 32 and 4096)
);
comment on table public.user_push_devices is
  'Notification addresses of the phones a member turned notifications on for; service-only.';
create index user_push_devices_user_idx
  on public.user_push_devices (user_id, registered_at desc);
alter table public.user_push_devices enable row level security;
revoke all on table public.user_push_devices from public, anon, authenticated;
grant all on table public.user_push_devices to service_role;

create function public.soolgyul_register_push_device(p_token text, p_platform text)
returns void
language plpgsql security definer
set search_path to ''
as $$
declare target uuid := auth.uid();
begin
  if target is null or not public.soolgyul_my_account_ready() then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;
  if p_token is null or char_length(p_token) not between 32 and 4096 then
    raise exception using errcode = '22023', message = 'push_token_invalid';
  end if;
  if p_platform is null or p_platform not in ('android', 'ios') then
    raise exception using errcode = '22023', message = 'push_platform_invalid';
  end if;
  insert into public.user_push_devices (token, user_id, platform)
  values (p_token, target, p_platform)
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        registered_at = now();
  delete from public.user_push_devices device
  where device.user_id = target
    and device.token in (
      select older.token
      from public.user_push_devices older
      where older.user_id = target
      order by older.registered_at desc, older.token
      offset 10
    );
end;
$$;
revoke all on function public.soolgyul_register_push_device(text, text) from public, anon;
grant execute on function public.soolgyul_register_push_device(text, text) to authenticated, service_role;

-- Open to an account that is leaving too: forgetting is never refused.
create function public.soolgyul_unregister_push_device(p_token text)
returns void
language sql security definer
set search_path to ''
as $$
  delete from public.user_push_devices
  where token = p_token and user_id = auth.uid();
$$;
revoke all on function public.soolgyul_unregister_push_device(text) from public, anon;
grant execute on function public.soolgyul_unregister_push_device(text) to authenticated, service_role;
