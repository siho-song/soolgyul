-- Client roles execute only the RPCs the app and the admin web call. Every
-- other public function (service RPCs, trigger and validation helpers) stays
-- with service_role, and new objects no longer inherit anon/authenticated
-- access from the project defaults.

alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;

-- RLS policy helpers evaluated as the signed-in user.
grant execute on function public.soolgyul_account_active(uuid) to authenticated;
grant execute on function public.soolgyul_admin_has_role(text[]) to authenticated;

-- Public onboarding and catalog reads.
grant execute on function public.soolgyul_get_sensory_question_context(uuid)
  to anon, authenticated;
grant execute on function public.soolgyul_search_alcohol_catalog(text, integer)
  to anon, authenticated;

-- Signed-in account, profile, consent, record and support RPCs.
grant execute on function public.soolgyul_catalog_primary_media_rows_v1() to authenticated;
grant execute on function public.soolgyul_complete_my_profile_v3(
  uuid, text, date, boolean, text, text, text, boolean, boolean, boolean, text, boolean
) to authenticated;
grant execute on function public.soolgyul_get_marketing_consent() to authenticated;
grant execute on function public.soolgyul_get_my_deletion_state() to authenticated;
grant execute on function public.soolgyul_get_my_profile_preferences() to authenticated;
grant execute on function public.soolgyul_get_my_profile_status_v1() to authenticated;
grant execute on function public.soolgyul_replace_my_drink_interests(text[], uuid) to authenticated;
grant execute on function public.soolgyul_request_my_account_deletion() to authenticated;
grant execute on function public.soolgyul_restore_my_account() to authenticated;
grant execute on function public.soolgyul_set_marketing_consent(boolean) to authenticated;
grant execute on function public.soolgyul_submit_support_inquiry(uuid, text, text, text, text[])
  to authenticated;
grant execute on function public.soolgyul_update_my_display_name(text, uuid) to authenticated;

-- Admin web editorial RPCs; each function checks the admin role itself. The
-- tag validator and the normaliser it calls run inside the editorial_articles
-- CHECK constraint, so they execute as the editor who writes the row.
grant execute on function public.soolgyul_catalog_text_array_is_valid(text[], integer, text)
  to authenticated;
grant execute on function public.soolgyul_normalize_catalog_text(text) to authenticated;
grant execute on function public.soolgyul_admin_change_editorial_status(uuid, text) to authenticated;
grant execute on function public.soolgyul_admin_delete_editorial_draft(uuid) to authenticated;
grant execute on function public.soolgyul_admin_save_editorial_article(
  uuid, uuid, text, text, text, text, text[], integer, boolean, integer, text, uuid[]
) to authenticated;

-- Records are written only by the service generation RPC.
revoke insert, update on table public.drink_records from authenticated;
drop policy if exists drink_records_owner_insert on public.drink_records;
drop policy if exists drink_records_owner_update on public.drink_records;

-- Editors may change only unpublished articles, their media rows and their
-- storage objects. The USING clauses let an editor target published rows.
alter policy editorial_articles_admin_update on public.editorial_articles
  using (
    public.soolgyul_admin_has_role(array['admin'])
    or (
      public.soolgyul_admin_has_role(array['editor'])
      and status = 'draft'
      and published_at is null
    )
  );

alter policy editorial_article_media_admin_update on public.editorial_article_media_assets
  using (
    public.soolgyul_admin_has_role(array['admin'])
    or (
      public.soolgyul_admin_has_role(array['editor'])
      and exists (
        select 1
        from public.editorial_articles article
        where article.id = editorial_article_media_assets.article_id
          and article.status = 'draft'
          and article.published_at is null
      )
    )
  );

create function public.soolgyul_editorial_object_editable(object_path text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.soolgyul_admin_has_role(array['admin'])
    or (
      public.soolgyul_admin_has_role(array['editor'])
      and not exists (
        select 1
        from public.editorial_article_media_assets media
        join public.editorial_articles article on article.id = media.article_id
        where media.storage_bucket = 'soolgyul-editorial'
          and media.storage_object_path = object_path
          and article.status = 'published'
      )
    );
$$;

revoke execute on function public.soolgyul_editorial_object_editable(text) from public, anon;
grant execute on function public.soolgyul_editorial_object_editable(text) to authenticated, service_role;

alter policy soolgyul_editorial_media_admin_update on storage.objects
  using (
    bucket_id = 'soolgyul-editorial'
    and public.soolgyul_editorial_object_editable(name)
  )
  with check (
    bucket_id = 'soolgyul-editorial'
    and public.soolgyul_editorial_object_editable(name)
  );

alter policy soolgyul_editorial_media_admin_delete on storage.objects
  using (
    bucket_id = 'soolgyul-editorial'
    and public.soolgyul_editorial_object_editable(name)
  );
