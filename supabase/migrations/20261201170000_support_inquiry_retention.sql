-- The privacy policy keeps an answered inquiry's reply address, photos and
-- owner for six months and removes photos uploaded for an inquiry that was
-- never sent after a day, but nothing did either: inquiries stayed whole for
-- as long as the account lived. Six months after the answer an inquiry now
-- moves to closed_support_inquiries as its type and words only, and the
-- original row is removed. Photos are files, which only the Storage API
-- deletes, so the scheduled purge function (account-retention-purge) asks
-- these functions what is due, deletes the files and then closes the row.
set local lock_timeout = '5s';

create table public.closed_support_inquiries (
  id uuid primary key default gen_random_uuid(),
  inquiry_type text not null,
  content text not null
);

alter table public.closed_support_inquiries enable row level security;
revoke all on public.closed_support_inquiries from anon, authenticated;

comment on table public.closed_support_inquiries is
  'What members asked, kept six months after the answer as the type and the words only: no owner, reply address, photo or date. No client reads.';

create function public.soolgyul_due_support_inquiries(batch_limit integer default 20)
returns table (id uuid, attachment_paths text[])
language sql stable security definer
set search_path to ''
as $$
  select i.id, i.attachment_paths
  from public.support_inquiries i
  where i.answered_at <= statement_timestamp() - interval '6 months'
  order by i.answered_at
  limit greatest(batch_limit, 1)
$$;

-- Refuses while a photo is still stored, so a failed file deletion is tried
-- again instead of leaving a file nobody points to.
create function public.soolgyul_close_support_inquiry(target_inquiry_id uuid)
returns boolean
language plpgsql security definer
set search_path to ''
as $$
declare inquiry public.support_inquiries%rowtype;
begin
  select * into inquiry from public.support_inquiries
  where id = target_inquiry_id for update;
  if not found then return false; end if;
  if inquiry.answered_at is null
    or inquiry.answered_at > statement_timestamp() - interval '6 months' then
    raise exception 'inquiry_not_due';
  end if;
  if exists (select 1 from storage.objects o
      where o.bucket_id = 'soolgyul-private'
        and o.name = any(inquiry.attachment_paths)) then
    raise exception 'inquiry_storage_cleanup_required';
  end if;
  insert into public.closed_support_inquiries (inquiry_type, content)
  values (inquiry.inquiry_type, inquiry.content);
  delete from public.support_inquiries where id = target_inquiry_id;
  return true;
end;
$$;

-- Photos under a member's inquiries folder that no inquiry lists, a day
-- after the upload: the form was left, or the submission never arrived.
create function public.soolgyul_stale_inquiry_uploads(batch_limit integer default 100)
returns setof text
language sql stable security definer
set search_path to ''
as $$
  select o.name
  from storage.objects o
  where o.bucket_id = 'soolgyul-private'
    and o.name ~ '^[0-9a-f-]{36}/inquiries/[0-9a-f-]{36}/[^/]+$'
    and o.created_at < statement_timestamp() - interval '24 hours'
    and not exists (
      select 1 from public.support_inquiries i
      where o.name = any(i.attachment_paths))
  order by o.created_at
  limit greatest(batch_limit, 1)
$$;

revoke execute on function public.soolgyul_due_support_inquiries(integer)
  from public, anon, authenticated;
revoke execute on function public.soolgyul_close_support_inquiry(uuid)
  from public, anon, authenticated;
revoke execute on function public.soolgyul_stale_inquiry_uploads(integer)
  from public, anon, authenticated;
grant execute on function public.soolgyul_due_support_inquiries(integer) to service_role;
grant execute on function public.soolgyul_close_support_inquiry(uuid) to service_role;
grant execute on function public.soolgyul_stale_inquiry_uploads(integer) to service_role;
