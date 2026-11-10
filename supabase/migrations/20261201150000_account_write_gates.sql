-- An account that signed in with a social login but never confirmed its age
-- or accepted the terms could still send an inquiry, upload pictures, save
-- articles and leave search events tied to it. Those writes now need the
-- finished sign-up that making a card already needs.
-- Pictures went anywhere under the member's own folder, without a count.
-- They now go only where an inquiry keeps them, sixty a day at most.
-- Scheduling a withdrawal was open to any signed-in session, so a direct
-- call skipped the check with Kakao, Google or Apple. Only the server
-- function, after that check, can schedule one now.
-- The withdrawal worker took the five oldest due accounts every time, so
-- five that kept failing held back every other one. It now notes when it
-- last tried an account and takes the ones it has waited on longest.
-- Statements slower than a second are logged; their values are no longer
-- logged with them, since those can be an inquiry, an email or a note.
set local lock_timeout = '5s';

create function public.soolgyul_my_account_ready() returns boolean
language sql stable security definer
set search_path to ''
as $$
  select coalesce(
    public.soolgyul_account_active(auth.uid())
      and public.soolgyul_adult_profile_complete(auth.uid()),
    false
  );
$$;
revoke all on function public.soolgyul_my_account_ready() from public, anon;
grant execute on function public.soolgyul_my_account_ready() to authenticated, service_role;

create function public.soolgyul_private_upload_allowed(object_name text) returns boolean
language sql stable security definer
set search_path to ''
as $$
  select public.soolgyul_my_account_ready()
    and object_name ~ (
      '^' || auth.uid()::text
      || '/inquiries/[0-9a-f-]{36}/[0-4]-[0-9a-f]{64}[.](jpg|png|webp)$'
    )
    and (
      select count(*)
      from storage.objects stored
      where stored.bucket_id = 'soolgyul-private'
        and stored.name like auth.uid()::text || '/%'
        and stored.name <> object_name
        and stored.created_at > now() - interval '24 hours'
    ) < 60;
$$;
revoke all on function public.soolgyul_private_upload_allowed(text) from public, anon;
grant execute on function public.soolgyul_private_upload_allowed(text) to authenticated, service_role;

alter policy soolgyul_private_owner_insert on storage.objects with check (
  bucket_id = 'soolgyul-private'
  and public.soolgyul_private_upload_allowed(name)
);
-- Sending the same picture again replaces it in place.
alter policy soolgyul_private_owner_update on storage.objects
  using (
    bucket_id = 'soolgyul-private'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.soolgyul_my_account_ready())
  )
  with check (
    bucket_id = 'soolgyul-private'
    and public.soolgyul_private_upload_allowed(name)
  );

alter policy user_saved_articles_owner_insert on public.user_saved_articles with check (
  user_id = (select auth.uid())
  and (select public.soolgyul_my_account_ready())
  and exists (
    select 1
    from public.editorial_articles article
    where article.id = user_saved_articles.article_id
      and article.status = 'published'
      and article.published_at is not null
      and article.published_at <= now()
  )
);

create or replace function public.soolgyul_record_discovery_event(event_kind text, event_surface text, target_alcohol_item_id uuid DEFAULT NULL::uuid, event_query text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  actor uuid := auth.uid();
  member uuid;
  cleaned text := nullif(left(btrim(regexp_replace(
    coalesce(event_query, ''), '\s+', ' ', 'g')), 120), '');
begin
  if actor is not null then
    -- A reader on the way out is no longer counted.
    -- Nor is an account that has not finished signing up.
    if not public.soolgyul_account_active(actor)
      or not public.soolgyul_adult_profile_complete(actor) then
      return;
    end if;
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

create or replace function public.soolgyul_submit_support_inquiry(p_id uuid, p_inquiry_type text, p_reply_email text, p_content text, p_attachment_paths text[] DEFAULT '{}'::text[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  owner_id uuid := auth.uid();
  existing public.support_inquiries%rowtype;
  attachment text;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  -- Serialize submissions for this user, including retries and rate checks.
  perform 1 from public.users where id = owner_id for update;
  if not found
    or not coalesce(public.soolgyul_account_active(owner_id), false)
    or not coalesce(public.soolgyul_adult_profile_complete(owner_id), false) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;
  select * into existing from public.support_inquiries where id = p_id;
  if found then
    if existing.user_id = owner_id
      and existing.inquiry_type = p_inquiry_type
      and existing.reply_email = btrim(p_reply_email)
      and existing.content = btrim(p_content)
      and existing.attachment_paths = p_attachment_paths then
      return existing.id;
    end if;
    raise exception 'inquiry_request_conflict' using errcode = '22023';
  end if;
  if p_id is null or p_attachment_paths is null
    or cardinality(p_attachment_paths) > 5
    or array_position(p_attachment_paths, null) is not null then
    raise exception 'invalid_inquiry_attachments' using errcode = '22023';
  end if;
  if (select count(*) from public.support_inquiries
      where user_id = owner_id and created_at >= now() - interval '1 hour') >= 10 then
    raise exception 'inquiry_rate_limited' using errcode = 'P0001';
  end if;
  foreach attachment in array p_attachment_paths loop
    if attachment !~ ('^' || owner_id::text || '/inquiries/' || p_id::text ||
        '/[0-4]-[0-9a-f]{64}[.](jpg|png|webp)$')
      or not exists (
        select 1 from storage.objects o
        where o.bucket_id = 'soolgyul-private' and o.name = attachment
          and o.metadata->>'mimetype' in ('image/jpeg', 'image/png', 'image/webp')
          and (o.metadata->>'size')::bigint between 1 and 10485760
      ) then
      raise exception 'invalid_inquiry_attachment' using errcode = '22023';
    end if;
  end loop;
  insert into public.support_inquiries
    (id, user_id, inquiry_type, reply_email, content, attachment_paths)
  values (p_id, owner_id, p_inquiry_type, btrim(p_reply_email), btrim(p_content), p_attachment_paths);
  return p_id;
end;
$_$;

drop function public.soolgyul_request_my_account_deletion();

create function public.soolgyul_request_account_deletion(target_user_id uuid) returns jsonb
language plpgsql security definer
set search_path to ''
as $$
declare u public.users%rowtype;
begin
  select * into u from public.users where id = target_user_id for update;
  if not found or u.disabled_at is not null or u.purged_at is not null then
    raise exception 'active_account_required';
  end if;
  if u.deletion_requested_at is null then
    update public.users
      set deletion_requested_at = statement_timestamp(),
          deletion_provider_revoked_at = null
      where id = u.id
      returning * into u;
  end if;
  return jsonb_build_object(
    'deletion_state', 'scheduled',
    'requested_at', u.deletion_requested_at,
    'scheduled_deletion_at', public.soolgyul_deletion_due_at(u.deletion_requested_at),
    'restore_available',
      public.soolgyul_deletion_due_at(u.deletion_requested_at) > statement_timestamp(),
    'provider_revoked', u.deletion_provider_revoked_at is not null
  );
end;
$$;
revoke all on function public.soolgyul_request_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.soolgyul_request_account_deletion(uuid) to service_role;

alter table public.users add column purge_attempted_at timestamptz;

-- The setting exists from Postgres 13 and the roles on a Supabase project only.
do $$
declare
  role_name text;
begin
  foreach role_name in array array['authenticator', 'postgres'] loop
    if exists (select 1 from pg_catalog.pg_roles where rolname = role_name) then
      execute format(
        'alter role %I set log_parameter_max_length = %L', role_name, '0'
      );
    end if;
  end loop;
end
$$;
