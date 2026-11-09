-- raw_user_meta_data is writable by the signing-up client. Only the Auth admin
-- API can set raw_app_meta_data, so synthetic test accounts are recognised
-- there instead.
create or replace function public.soolgyul_provision_auth_user()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  resolved_provider text;
  trusted_provider_user_id text;
begin
  if lower(coalesce(new.raw_app_meta_data ->> 'provider', '')) = 'email'
     and lower(coalesce(new.raw_app_meta_data ->> 'soolgyul_test_user', '')) = 'true'
  then
    resolved_provider := 'test';
  else
    resolved_provider := lower(
      coalesce(new.raw_app_meta_data ->> 'provider', '')
    );
  end if;

  if resolved_provider not in ('kakao', 'apple', 'google', 'test') then
    return new;
  end if;

  trusted_provider_user_id := new.id::text;
  if exists (
    select 1
    from public.users product_user
    where product_user.auth_provider = resolved_provider
      and product_user.provider_user_id = trusted_provider_user_id
      and product_user.id <> new.id
  ) then
    raise exception using
      errcode = '23505',
      message = 'trusted_auth_identity_conflict';
  end if;

  begin
    insert into public.users (
      id,
      auth_provider,
      provider_user_id,
      email,
      created_at,
      last_sign_in_at
    ) values (
      new.id,
      resolved_provider,
      trusted_provider_user_id,
      new.email,
      coalesce(new.created_at, now()),
      new.last_sign_in_at
    )
    on conflict (id) do update
    set auth_provider = excluded.auth_provider,
        provider_user_id = excluded.provider_user_id,
        email = excluded.email,
        last_sign_in_at = excluded.last_sign_in_at;
  exception
    when unique_violation then
      raise exception using
        errcode = '23505',
        message = 'trusted_auth_identity_conflict';
  end;

  return new;
end
$$;
