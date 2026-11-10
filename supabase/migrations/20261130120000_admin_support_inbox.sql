-- The admin console reads the support inbox: an admin (not an editor) lists
-- the inquiries, opens their photos and marks one answered once the reply
-- mail is out. Reading members' mail and words makes the admin a personal
-- data handler, so every list and every answer mark is logged with who, when
-- and which inquiries; the log is kept at least a year and no client reads
-- or changes it.

alter table public.support_inquiries add column answered_at timestamptz;

create table public.admin_access_logs (
  id bigint generated always as identity primary key,
  accessed_at timestamptz not null default statement_timestamp(),
  -- No foreign key: the record outlives the admin account.
  admin_user_id uuid not null,
  action text not null check (action in
    ('list_support_inquiries', 'answer_support_inquiry', 'reopen_support_inquiry')),
  inquiry_ids uuid[] not null default '{}'
);

create index admin_access_logs_accessed_at_idx
  on public.admin_access_logs (accessed_at);

alter table public.admin_access_logs enable row level security;
revoke all on public.admin_access_logs from anon, authenticated;

comment on table public.admin_access_logs is
  'Who among the admins read or changed which support inquiries, and when. Kept at least a year; written only by the admin inbox functions, no client reads.';

-- The newest 200 inquiries, open ones first.
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
      insert into public.admin_access_logs (admin_user_id, action, inquiry_ids)
      select (select auth.uid()), 'list_support_inquiries',
        coalesce(array_agg(inbox.id), '{}')
      from inbox
    )
    select inbox.id, inbox.inquiry_type, inbox.reply_email, inbox.content,
      inbox.attachment_paths, inbox.created_at, inbox.answered_at
    from inbox
    order by inbox.answered_at is not null, inbox.created_at desc;
end;
$$;

revoke execute on function public.soolgyul_admin_list_support_inquiries() from public, anon;
grant execute on function public.soolgyul_admin_list_support_inquiries() to authenticated;

-- Marks an inquiry answered (now) or open again.
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
  insert into public.admin_access_logs (admin_user_id, action, inquiry_ids)
  values ((select auth.uid()),
    case when answered then 'answer_support_inquiry' else 'reopen_support_inquiry' end,
    array[inquiry_id]);
end;
$$;

revoke execute on function public.soolgyul_admin_set_support_inquiry_answered(uuid, boolean) from public, anon;
grant execute on function public.soolgyul_admin_set_support_inquiry_answered(uuid, boolean) to authenticated;

-- An admin may sign links to inquiry photos (<owner>/inquiries/<id>/...).
create policy soolgyul_private_admin_inquiry_read on storage.objects
  for select to authenticated
  using (bucket_id = 'soolgyul-private'
    and (storage.foldername(name))[2] = 'inquiries'
    and public.soolgyul_admin_has_role(array['admin']));
