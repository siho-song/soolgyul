-- 2026-11-07: the photo and the one-line note are added to a record from its
-- card, after the record exists, so the owner needs a write for exactly those
-- two fields. Records stay otherwise service-written. The photo path column
-- returns; it left with the user-table slimming while the app sent no photo.

alter table public.drink_records add column photo_storage_path text;
comment on column public.drink_records.photo_storage_path is
  'Object path in the private soolgyul-private bucket, under the owner''s folder; null without a photo.';

create or replace function public.soolgyul_update_my_drink_record_note(
  p_record_id uuid, p_note text
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  target_user_id uuid := auth.uid();
begin
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_record_id is null then
    raise exception using errcode = '22023', message = 'record_id_required';
  end if;
  if not public.soolgyul_account_active(target_user_id) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  -- The note has no length limit; blank clears it.
  update public.drink_records
    set one_line_note = nullif(btrim(coalesce(p_note, '')), ''),
        updated_at = now()
    where id = p_record_id and user_id = target_user_id and deleted_at is null;
  if not found then
    raise exception using errcode = 'P0002', message = 'record_not_found';
  end if;
end
$$;

-- Returns the path the new photo replaced (null for a first photo) so the
-- client can remove that object; the path must already be uploaded under
-- <owner>/drink-records/<record>/.
create or replace function public.soolgyul_set_my_drink_record_photo(
  p_record_id uuid, p_storage_path text
)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  target_user_id uuid := auth.uid();
  expected_prefix text;
  previous_path text;
begin
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_record_id is null then
    raise exception using errcode = '22023', message = 'record_id_required';
  end if;
  if not public.soolgyul_account_active(target_user_id) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  expected_prefix := target_user_id::text || '/drink-records/' || p_record_id::text || '/';
  if p_storage_path is null
    or not starts_with(p_storage_path, expected_prefix)
    or length(p_storage_path) <= length(expected_prefix)
    or position('/' in substr(p_storage_path, length(expected_prefix) + 1)) > 0
  then
    raise exception using errcode = '22023', message = 'photo_path_invalid';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'soolgyul-private' and o.name = p_storage_path
  ) then
    raise exception using errcode = '22023', message = 'photo_object_missing';
  end if;

  select r.photo_storage_path into previous_path
  from public.drink_records r
  where r.id = p_record_id and r.user_id = target_user_id and r.deleted_at is null
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'record_not_found';
  end if;

  update public.drink_records
    set photo_storage_path = p_storage_path, updated_at = now()
    where id = p_record_id;
  return previous_path;
end
$$;

revoke execute on function public.soolgyul_update_my_drink_record_note(uuid, text) from public;
revoke execute on function public.soolgyul_set_my_drink_record_photo(uuid, text) from public;
grant execute on function public.soolgyul_update_my_drink_record_note(uuid, text) to authenticated;
grant execute on function public.soolgyul_set_my_drink_record_photo(uuid, text) to authenticated;
