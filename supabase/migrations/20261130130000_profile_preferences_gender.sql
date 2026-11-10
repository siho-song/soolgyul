-- The app picks the 자주 찾는 술 list by the member's gender, so reading
-- one's own profile preferences now returns the stored gender too.

create or replace function public.soolgyul_get_my_profile_preferences() returns jsonb
language plpgsql stable security definer
set search_path to ''
as $$
declare
  target_user_id uuid;
  current_display_name text;
  current_gender text;
  current_interest_keys text[];
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  if not public.soolgyul_account_active(target_user_id) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  select profile.display_name, profile.gender
  into current_display_name, current_gender
  from public.users profile
  where profile.id = target_user_id;

  select coalesce(
    array_agg(
      selection.interest_key
      order by interest.sort_order, selection.interest_key
    ),
    array[]::text[]
  )
  into current_interest_keys
  from public.user_drink_interests selection
  left join lateral (
    select min(category.sort_order) as sort_order
    from public.alcohol_categories category
    where category.interest_key = selection.interest_key
  ) interest on true
  where selection.user_id = target_user_id;

  return jsonb_build_object(
    'display_name', current_display_name,
    'gender', current_gender,
    'interest_group_keys', to_jsonb(current_interest_keys)
  );
end
$$;
