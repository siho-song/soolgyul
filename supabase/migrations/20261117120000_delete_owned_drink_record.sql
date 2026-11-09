-- A reader deletes one of their saved records from its card. The record is
-- marked deleted (every reader already skips such rows) and the card server
-- recomputes the account's 네 글자 right after, so the delete runs through the
-- service role from the card function, never from the client directly.

create or replace function public.soolgyul_delete_owned_drink_record(
  target_result_summary_id uuid,
  target_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  deleted_record_id uuid;
begin
  if not public.soolgyul_account_active(target_user_id) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  update public.drink_records record_row
    set deleted_at = now(),
        updated_at = now()
    from public.taste_cards summary_row
    where summary_row.id = target_result_summary_id
      and record_row.id = summary_row.drink_record_id
      and record_row.user_id = target_user_id
      and record_row.deleted_at is null
    returning record_row.id into deleted_record_id;

  if deleted_record_id is null then
    raise exception using errcode = 'P0002', message = 'owned result not found';
  end if;
  return deleted_record_id;
end;
$$;
revoke execute on function public.soolgyul_delete_owned_drink_record(uuid, uuid) from public;
revoke execute on function public.soolgyul_delete_owned_drink_record(uuid, uuid) from anon, authenticated;
grant execute on function public.soolgyul_delete_owned_drink_record(uuid, uuid) to service_role;
