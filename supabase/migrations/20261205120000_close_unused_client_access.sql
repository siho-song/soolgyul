-- A visitor or a member reaches the database only through what the app
-- uses. These were open and nothing in the app, the site or the server
-- functions used them:
--   * a function that handed any signed-in account every product photo's
--     path, and the unused search view that was its only caller;
--   * the producers and categories tables, readable whole without a login;
--   * the inner search function, called directly instead of through its
--     wrappers;
--   * a member's own rows in five tables the app reads through functions;
--   * the list of files in the post pictures' bucket;
--   * two text helpers of the catalog's check constraints.
-- A member could also ask whether any other account id was active.
set local lock_timeout = '5s';

drop view public.catalog_search_projection;
drop function public.soolgyul_catalog_search_projection_rows();
drop function public.soolgyul_catalog_primary_media_rows();

drop policy producers_read on public.producers;
revoke all on public.producers from anon, authenticated;
drop policy alcohol_categories_public_read_active on public.alcohol_categories;
revoke all on public.alcohol_categories from anon, authenticated;

-- soolgyul_search_catalog and the batch search run it as their owner.
revoke execute on function public.soolgyul_search_alcohol_catalog(text, integer, integer)
  from anon, authenticated;

revoke execute on function public.soolgyul_catalog_text_array_is_valid(text[], integer, text)
  from authenticated;
revoke execute on function public.soolgyul_normalize_catalog_text(text)
  from authenticated;

drop policy users_owner_select on public.users;
revoke all on public.users from authenticated;
drop policy user_consents_owner_select on public.user_consents;
revoke all on public.user_consents from authenticated;
drop policy user_drink_interests_owner_select on public.user_drink_interests;
revoke all on public.user_drink_interests from authenticated;
drop policy support_inquiries_owner_read on public.support_inquiries;
revoke all on public.support_inquiries from authenticated;
drop policy drink_record_answers_owner_select on public.drink_record_answers;
revoke all on public.drink_record_answers from authenticated;

-- The row policies ask this about the member reading; a member asking
-- about someone else is told no. The server, which has no member of its
-- own, still asks about any account.
create or replace function public.soolgyul_account_active(target_user_id uuid)
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select exists (
    select 1
    from public.users u
    where u.id = target_user_id
      and u.disabled_at is null
      and u.deletion_requested_at is null
      and u.purged_at is null
      and ((select auth.uid()) is null or (select auth.uid()) = target_user_id)
  );
$$;

-- A post's picture is public by its address. Only the administrator web,
-- which replaces and removes pictures, sees the bucket's rows.
drop policy soolgyul_editorial_media_public_select on storage.objects;
create policy soolgyul_editorial_media_admin_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'soolgyul-editorial'
    and (select public.soolgyul_admin_has_role())
  );
