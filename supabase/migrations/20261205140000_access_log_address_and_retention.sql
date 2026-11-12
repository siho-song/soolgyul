-- The record of an administrator reading the inquiries said who, when and
-- which inquiries, but not from where. It now keeps the address the request
-- came from, and a row is deleted two years after it was written (the rule
-- asks for one year, two for a service with many members).
-- A card generation attempt only answers a repeated request with the same
-- card. A visitor's went after thirty days while a member's stayed for
-- good; now every attempt goes after thirty days.
set local lock_timeout = '5s';

alter table public.admin_access_logs add column ip inet;

comment on table public.admin_access_logs is
  'Who among the admins read or changed which support inquiries, when and from which address. Kept two years; written only by the admin inbox functions, no client reads.';

-- The address the API request came from: the first one the gateway lists.
-- Null outside an API request or when the header is not an address.
create function public.soolgyul_request_ip()
returns inet
language plpgsql stable
set search_path to ''
as $$
begin
  return nullif(btrim(split_part(
    nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-forwarded-for',
    ',', 1)), '')::inet;
exception when others then
  return null;
end;
$$;

revoke execute on function public.soolgyul_request_ip() from public, anon, authenticated;

create or replace function public.soolgyul_admin_list_support_inquiries()
returns table (
  id uuid,
  inquiry_type text,
  reply_email text,
  content text,
  attachment_paths text[],
  created_at timestamptz,
  answered_at timestamptz
)
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.soolgyul_admin_has_role(array['admin']) then
    raise exception 'admin_role_required' using errcode = '42501';
  end if;
  return query
    with inbox as (
      select i.id, i.inquiry_type, i.reply_email, i.content,
        i.attachment_paths, i.created_at, i.answered_at
      from public.support_inquiries i
      order by i.answered_at is not null, i.created_at desc
      limit 200
    ), logged as (
      insert into public.admin_access_logs (admin_user_id, action, inquiry_ids, ip)
      select (select auth.uid()), 'list_support_inquiries',
        coalesce(array_agg(inbox.id), '{}'), public.soolgyul_request_ip()
      from inbox
    )
    select inbox.id, inbox.inquiry_type, inbox.reply_email, inbox.content,
      inbox.attachment_paths, inbox.created_at, inbox.answered_at
    from inbox
    order by inbox.answered_at is not null, inbox.created_at desc;
end;
$$;

create or replace function public.soolgyul_admin_set_support_inquiry_answered(
  inquiry_id uuid,
  answered boolean
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.soolgyul_admin_has_role(array['admin']) then
    raise exception 'admin_role_required' using errcode = '42501';
  end if;
  update public.support_inquiries
  set answered_at = case when answered then statement_timestamp() end
  where id = inquiry_id;
  if not found then
    raise exception 'support_inquiry_not_found' using errcode = 'P0002';
  end if;
  insert into public.admin_access_logs (admin_user_id, action, inquiry_ids, ip)
  values ((select auth.uid()),
    case when answered then 'answer_support_inquiry' else 'reopen_support_inquiry' end,
    array[inquiry_id], public.soolgyul_request_ip());
end;
$$;

select cron.schedule('soolgyul-admin-access-log-retention', '0 19 * * *',
  $job$delete from public.admin_access_logs where accessed_at < now() - interval '2 years'$job$);
select cron.schedule('soolgyul-generation-attempt-retention', '20 19 * * *',
  $job$delete from public.taste_card_generation_attempts where created_at < now() - interval '30 days'$job$);
