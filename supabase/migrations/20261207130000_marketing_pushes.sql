-- An admin sends a marketing notification from the administrator web. It
-- goes to the phones of active members who agreed to marketing and turned
-- notifications on, and every send is kept: who sent what, when, to how many
-- phones.
-- The send's id is chosen by the page that sends it, so the same send asked
-- twice (a second press, a retry) is refused the second time.
-- No client reads or writes the table. The admin starts a send and reads the
-- history through two functions; the server function that talks to the
-- notification service reads the phones and closes the send.
set local lock_timeout = '5s';

create table public.marketing_pushes (
  id uuid primary key,
  admin_user_id uuid not null,
  title text not null,
  body text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  device_count integer,
  sent_count integer,
  constraint marketing_pushes_title_check
    check (char_length(btrim(title)) between 1 and 30),
  constraint marketing_pushes_body_check
    check (char_length(btrim(body)) between 1 and 100),
  constraint marketing_pushes_counts_check
    check (sent_count between 0 and device_count)
);
comment on table public.marketing_pushes is
  'Marketing notifications an admin sent: the words as typed, who, when, to how many phones and how many the notification service took. Without finished_at the send was cut short. Service-only.';
alter table public.marketing_pushes enable row level security;
revoke all on table public.marketing_pushes from public, anon, authenticated;
grant all on table public.marketing_pushes to service_role;

-- The phones a marketing notification goes to: of members whose account is
-- in use and whose marketing consent stands.
create function public.soolgyul_marketing_push_devices()
returns table (token text)
language sql stable security definer
set search_path to ''
as $$
  select device.token
  from public.user_push_devices device
  join public.users account on account.id = device.user_id
  where account.disabled_at is null
    and account.deletion_requested_at is null
    and account.purged_at is null
    and exists (
      select 1
      from public.user_consents consent
      where consent.user_id = device.user_id
        and consent.consent_type = 'marketing'
        and consent.document_version = 'soolgyul-marketing-v1'
        and consent.withdrawn_at is null
    )
  order by device.token;
$$;
revoke all on function public.soolgyul_marketing_push_devices() from public, anon, authenticated;
grant execute on function public.soolgyul_marketing_push_devices() to service_role;

create function public.soolgyul_admin_start_marketing_push(
  p_id uuid,
  p_title text,
  p_body text
)
returns void
language plpgsql security definer
set search_path to ''
as $$
begin
  if not public.soolgyul_admin_has_role(array['admin']) then
    raise exception 'admin_role_required' using errcode = '42501';
  end if;
  if p_id is null
    or p_title is null or char_length(btrim(p_title)) not between 1 and 30
    or p_body is null or char_length(btrim(p_body)) not between 1 and 100
  then
    raise exception 'marketing_push_invalid' using errcode = '22023';
  end if;
  insert into public.marketing_pushes (id, admin_user_id, title, body)
  values (p_id, (select auth.uid()), btrim(p_title), btrim(p_body));
end;
$$;
revoke all on function public.soolgyul_admin_start_marketing_push(uuid, text, text) from public, anon;
grant execute on function public.soolgyul_admin_start_marketing_push(uuid, text, text) to authenticated, service_role;

-- Closes a send with what the notification service answered, and forgets
-- the phones it no longer knows.
create function public.soolgyul_finish_marketing_push(
  p_id uuid,
  p_device_count integer,
  p_sent_count integer,
  p_gone_tokens text[]
)
returns void
language plpgsql security definer
set search_path to ''
as $$
begin
  update public.marketing_pushes
  set finished_at = clock_timestamp(),
      device_count = p_device_count,
      sent_count = p_sent_count
  where id = p_id and finished_at is null;
  if not found then
    raise exception 'marketing_push_not_open' using errcode = 'P0002';
  end if;
  delete from public.user_push_devices
  where token = any(coalesce(p_gone_tokens, '{}'));
end;
$$;
revoke all on function public.soolgyul_finish_marketing_push(uuid, integer, integer, text[]) from public, anon, authenticated;
grant execute on function public.soolgyul_finish_marketing_push(uuid, integer, integer, text[]) to service_role;

-- What the admin page shows before a send: how many members and phones it
-- would reach now, and the last sends.
create function public.soolgyul_admin_marketing_push_overview()
returns jsonb
language plpgsql stable security definer
set search_path to ''
as $$
begin
  if not public.soolgyul_admin_has_role(array['admin']) then
    raise exception 'admin_role_required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'member_count', (
      select count(distinct device.user_id)
      from public.soolgyul_marketing_push_devices() audience
      join public.user_push_devices device on device.token = audience.token
    ),
    'device_count', (select count(*) from public.soolgyul_marketing_push_devices()),
    'pushes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', recent.id,
        'title', recent.title,
        'body', recent.body,
        'started_at', recent.started_at,
        'finished_at', recent.finished_at,
        'device_count', recent.device_count,
        'sent_count', recent.sent_count
      ) order by recent.started_at desc)
      from (
        select push.*
        from public.marketing_pushes push
        order by push.started_at desc
        limit 30
      ) recent
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.soolgyul_admin_marketing_push_overview() from public, anon;
grant execute on function public.soolgyul_admin_marketing_push_overview() to authenticated, service_role;
