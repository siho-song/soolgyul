-- The fit check gains a fifth verdict, 낯설 수 있음 ('unfamiliar'): a bottle
-- far from what the member liked but on no side they called a burden. A
-- saved bottle keeps the badge shown when it was saved, so the column and
-- the save function accept the new value. The function is otherwise the one
-- from 20261207120000_saved_drinks.sql.
set local lock_timeout = '5s';

alter table public.user_saved_drinks
  drop constraint user_saved_drinks_fit_badge_check,
  add constraint user_saved_drinks_fit_badge_check
    check (fit_badge in ('star', 'neutral', 'unfamiliar', 'caution', 'no_info'));

create or replace function public.soolgyul_save_my_drink(
  p_alcohol_item_id uuid,
  p_fit_badge text default null
) returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_user_id uuid := auth.uid();
begin
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if not public.soolgyul_my_account_ready() then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;
  if p_fit_badge is not null
     and p_fit_badge not in ('star', 'neutral', 'unfamiliar', 'caution', 'no_info') then
    raise exception using errcode = '22023', message = 'fit_badge_invalid';
  end if;
  if not exists (
    select 1
    from public.alcohol_items item
    where item.id = p_alcohol_item_id
      and item.publish_status = 'published'
  ) then
    raise exception using errcode = 'P0002', message = 'drink_not_found';
  end if;

  -- Saving again keeps the first day and the badge shown then.
  insert into public.user_saved_drinks (user_id, alcohol_item_id, fit_badge)
  values (target_user_id, p_alcohol_item_id, p_fit_badge)
  on conflict (user_id, alcohol_item_id) do nothing;
end
$function$;
