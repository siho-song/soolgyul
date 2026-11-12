-- Fixes from a review of the schema:
--   * search picks count the bottle a reader chose from a label's candidates
--     (label_pick), not the first candidate the app reports on its own
--     (label_match);
--   * sign-up checks age and birth date against today's date in Korea; the
--     database runs in UTC, so from 00:00 to 09:00 KST it was still yesterday
--     and on 1 January a reader turning 19 that year was refused;
--   * a post is published only with at least one photo;
--   * a catalog term that a product or tasting profile still uses cannot be
--     deleted (the seed deletes terms that left the dictionary, and the term
--     checks ran only on insert and update); the identity trigger's delete
--     branch never fired and said terms are never deleted, so it goes;
--   * removing a record also removes an attempt that names its card by
--     snapshot (claim_snapshot_id holds taste_cards.snapshot_id, not id);
--   * the visitor-card cleanup takes batches until none are left (a run took
--     500 while up to 1000 visitor cards an hour may start);
--   * the remaining storage and admin policies ask who is signed in once per
--     query, not once per row;
--   * a member's events and records are found by account and time with one
--     index; the answers' record index repeats the unique index's lead.
set local lock_timeout = '5s';

create or replace function public.soolgyul_refresh_catalog_search_picks()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with counted as (
    select picked.alcohol_item_id, count(distinct picked.user_id)::integer as picks
    from (
      select event.alcohol_item_id, event.user_id
      from public.drink_discovery_events as event
      where event.occurred_at > now() - interval '90 days'
        and event.user_id is not null
        and event.alcohol_item_id is not null
        and event.kind in ('search_pick', 'label_pick', 'fit_view')
      union all
      select record.alcohol_item_id, record.user_id
      from public.drink_records as record
      where record.created_at > now() - interval '90 days'
        and record.user_id is not null
    ) as picked
    group by picked.alcohol_item_id
  ),
  forgotten as (
    update public.catalog_search_signals as signal
    set picks = 0, updated_at = now()
    where signal.picks > 0
      and not exists (
        select 1 from counted where counted.alcohol_item_id = signal.alcohol_item_id
      )
  )
  insert into public.catalog_search_signals (alcohol_item_id, picks)
  select counted.alcohol_item_id, counted.picks
  from counted
  join public.alcohol_items as item on item.id = counted.alcohol_item_id
  on conflict (alcohol_item_id) do update
    set picks = excluded.picks, updated_at = now()
    where public.catalog_search_signals.picks is distinct from excluded.picks;
$function$;

create or replace function public.soolgyul_complete_my_profile(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text DEFAULT NULL::text, p_gender_consent_accepted boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  target_user_id uuid;
  trusted_auth_provider text;
  normalized_display_name text;
  accepted_timestamp timestamptz := clock_timestamp();
  today_in_korea date := (now() at time zone 'Asia/Seoul')::date;
  response_payload jsonb;
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_birth_date is null or not isfinite(p_birth_date)
    or p_birth_date < date '1900-01-01' or p_birth_date > today_in_korea then
    raise exception using errcode = '22023', message = 'birth_date_invalid';
  end if;
  if (p_gender is not null and p_gender not in ('male', 'female', 'other'))
    or (p_gender is not null and not coalesce(p_gender_consent_accepted, false))
    or (p_gender is null and coalesce(p_gender_consent_accepted, false)) then
    raise exception using errcode = '22023', message = 'gender_consent_invalid';
  end if;
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'idempotency_key_required';
  end if;

  normalized_display_name := btrim(coalesce(p_display_name, ''));
  if char_length(normalized_display_name) < 2
    or char_length(normalized_display_name) > 12
    or normalized_display_name !~ '^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ]+$'
  then
    raise exception using errcode = '22023', message = 'display_name_invalid';
  end if;

  if not coalesce(p_age_19_or_over_confirmed, false)
    or extract(year from today_in_korea)::integer
      - extract(year from p_birth_date)::integer < 19
  then
    raise exception using errcode = '22023', message = 'age_gate_required';
  end if;
  if not coalesce(p_terms_accepted, false)
    or not coalesce(p_privacy_accepted, false)
  then
    raise exception using errcode = '22023', message = 'terms_and_privacy_required';
  end if;
  if p_terms_version is distinct from 'soolgyul-terms-v1'
    or p_privacy_version is distinct from 'soolgyul-privacy-v1'
    or p_marketing_version is distinct from 'soolgyul-marketing-v1'
  then
    raise exception using errcode = '22023', message = 'policy_version_invalid';
  end if;

  select product_user.auth_provider
  into trusted_auth_provider
  from public.users product_user
  where product_user.id = target_user_id
    and product_user.disabled_at is null
    and product_user.deletion_requested_at is null
    and product_user.purged_at is null
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;
  if trusted_auth_provider not in ('kakao', 'apple', 'google') then
    raise exception using errcode = '42501', message = 'unsupported_auth_provider';
  end if;

  -- Signup completion is one-shot, not a consent or nickname editing endpoint.
  -- A retry must not undo later nickname changes or revive withdrawn consents.
  if exists (
    select 1 from public.users p
    where p.id = target_user_id and p.age_confirmed_at is not null
  ) and exists (
    select 1 from public.user_consents c
    where c.user_id = target_user_id and c.consent_type = 'terms'
  ) and exists (
    select 1 from public.user_consents c
    where c.user_id = target_user_id and c.consent_type = 'privacy'
  ) then
    return public.soolgyul_get_my_profile_status();
  end if;

  update public.users profile
  set display_name = normalized_display_name,
      age_confirmed_at = coalesce(profile.age_confirmed_at, accepted_timestamp),
      birth_date = p_birth_date,
      gender = p_gender,
      gender_consent_accepted_at = case when p_gender is null then null else accepted_timestamp end,
      gender_consent_version = case when p_gender is null then null else 'soolgyul-gender-v1' end,
      updated_at = accepted_timestamp
  where profile.id = target_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'profile_not_found';
  end if;

  if not exists (
    select 1 from public.user_consents consent
    where consent.user_id = target_user_id
      and consent.consent_type = 'age_19'
      and consent.document_version = 'self-attestation-v1'
      and consent.withdrawn_at is null
  ) then
    insert into public.user_consents (
      user_id, consent_type, document_version, accepted_at
    ) values (
      target_user_id, 'age_19', 'self-attestation-v1', accepted_timestamp
    );
  end if;

  if not exists (
    select 1 from public.user_consents consent
    where consent.user_id = target_user_id
      and consent.consent_type = 'terms'
      and consent.document_version = p_terms_version
      and consent.withdrawn_at is null
  ) then
    insert into public.user_consents (
      user_id, consent_type, document_version, accepted_at
    ) values (
      target_user_id, 'terms', p_terms_version, accepted_timestamp
    );
  end if;

  if not exists (
    select 1 from public.user_consents consent
    where consent.user_id = target_user_id
      and consent.consent_type = 'privacy'
      and consent.document_version = p_privacy_version
      and consent.withdrawn_at is null
  ) then
    insert into public.user_consents (
      user_id, consent_type, document_version, accepted_at
    ) values (
      target_user_id, 'privacy', p_privacy_version, accepted_timestamp
    );
  end if;

  if coalesce(p_marketing_opt_in, false) then
    if not exists (
      select 1 from public.user_consents consent
      where consent.user_id = target_user_id
        and consent.consent_type = 'marketing'
        and consent.document_version = p_marketing_version
        and consent.withdrawn_at is null
    ) then
      insert into public.user_consents (
        user_id, consent_type, document_version, accepted_at
      ) values (
        target_user_id, 'marketing', p_marketing_version, accepted_timestamp
      );
    end if;
  else
    update public.user_consents consent
    set withdrawn_at = accepted_timestamp
    where consent.user_id = target_user_id
      and consent.consent_type = 'marketing'
      and consent.withdrawn_at is null;
  end if;

  response_payload := jsonb_build_object(
    'profile_complete', true,
    'display_name', normalized_display_name,
    'age_19_or_over_confirmed', true,
    'terms_version', p_terms_version,
    'privacy_version', p_privacy_version,
    'marketing_opt_in', coalesce(p_marketing_opt_in, false),
    'deletion_state', 'active'
  );

  return response_payload;
end
$_$;

create or replace function public.soolgyul_admin_change_editorial_status(article_id uuid, next_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not public.soolgyul_admin_has_role(array['admin']::text[]) then
    raise exception 'admin role required' using errcode = '42501';
  end if;
  if next_status not in ('published', 'withdrawn') then
    raise exception 'unsupported editorial status' using errcode = '22023';
  end if;

  update public.editorial_articles
  set status = next_status
  where id = article_id;

  if not found then
    raise exception 'article not found' using errcode = 'P0002';
  end if;

  if next_status = 'published' and not exists (
    select 1 from public.editorial_article_media_assets media
    where media.article_id = soolgyul_admin_change_editorial_status.article_id
  ) then
    raise exception using errcode = 'P0001', message = 'article_photo_required';
  end if;
end
$function$;

create or replace function public.soolgyul_protect_catalog_term_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.term_type is distinct from old.term_type
    or new.term_key is distinct from old.term_key
  then
    raise exception
      'catalog term identity is immutable; add the new key and delete the old one'
      using errcode = '23514';
  end if;

  return new;
end
$function$;

-- Checked at commit, so a seed may add a new key, move products to it and
-- delete the old one in any order within one transaction.
create function public.soolgyul_catalog_term_delete_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  same_types text[] := case when old.term_type in ('process', 'maturation')
    then array['process', 'maturation'] else array[old.term_type] end;
  used boolean := false;
begin
  if exists (
    select 1 from public.catalog_taxonomy term
    where term.term_type = any(same_types) and term.term_key = old.term_key
  ) then
    return null;
  end if;

  if old.term_type = 'style' then
    used := exists (select 1 from public.alcohol_items item
      where item.style_key = old.term_key);
  elsif old.term_type = 'region' then
    used := exists (select 1 from public.alcohol_items item
      where item.region_key = old.term_key);
  elsif old.term_type = 'ingredient' then
    used := exists (select 1 from public.alcohol_items item
      where old.term_key = any(item.ingredient_keys));
  elsif old.term_type in ('process', 'maturation') then
    used := exists (select 1 from public.alcohol_items item
      where old.term_key = any(item.production_process_keys));
  elsif old.term_type = 'sensory_descriptor' then
    used := exists (select 1 from public.alcohol_tasting_profiles profile
      where old.term_key = any(profile.aroma_tags)
        or old.term_key = any(profile.palate_tags)
        or old.term_key = any(profile.finish_tags));
  end if;

  if used then
    raise exception using
      errcode = '23503',
      message = format('catalog term %s:%s is still used by the catalog',
        old.term_type, old.term_key);
  end if;
  return null;
end
$function$;

revoke all on function public.soolgyul_catalog_term_delete_guard()
  from public, anon, authenticated;
grant all on function public.soolgyul_catalog_term_delete_guard() to service_role;

create constraint trigger catalog_taxonomy_delete_guard
  after delete on public.catalog_taxonomy
  deferrable initially deferred
  for each row execute function public.soolgyul_catalog_term_delete_guard();

create or replace function public.soolgyul_retain_drink_records(target_user_id uuid, only_record_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare account_row public.users%rowtype; retained_count integer; birth integer;
begin
  select * into account_row from public.users where id=target_user_id;
  if not found then return 0; end if;

  -- Keep only what cannot point back to the reader: no memo,
  -- no names, account metadata or raw snapshots.
  birth := extract(year from account_row.birth_date)::integer;
  insert into public.retained_drink_records(birth_year_band,gender,record_data)
  select birth - birth % 5,
    case when account_row.gender_consent_accepted_at is not null then account_row.gender end,
    jsonb_build_object(
      'alcohol_item_id',r.alcohol_item_id,
      'questionnaire_version',r.questionnaire_version,
      'answers',coalesce((select jsonb_agg(jsonb_build_object(
        'question_key',a.question_key,
        'selected_option_keys',a.selected_option_keys) order by a.question_key,a.id)
        from public.drink_record_answers a where a.drink_record_id=r.id),'[]'::jsonb),
      'card',(select public.soolgyul_strip_retained_card_links(jsonb_build_object('rendered_snapshot',c.rendered_snapshot))
        from public.taste_cards c where c.drink_record_id=r.id)
    )
  from public.drink_records r
  where r.user_id=target_user_id
    and (only_record_id is null or r.id=only_record_id);
  get diagnostics retained_count = row_count;

  -- Converted anonymous attempts can still carry an anonymous proof. Remove
  -- them by record linkage too, not just by owner_user_id.
  delete from public.taste_card_generation_attempts a
  where (only_record_id is null and a.owner_user_id=target_user_id) or exists (
    select 1 from public.drink_records r where r.user_id=target_user_id
      and (only_record_id is null or r.id=only_record_id)
      and (r.id=a.reserved_record_id or exists (
        select 1 from public.taste_cards c where c.drink_record_id=r.id
          and (c.id=a.result_summary_id or c.snapshot_id=a.claim_snapshot_id))));
  delete from public.drink_records r
  where r.user_id=target_user_id
    and (only_record_id is null or r.id=only_record_id);
  return retained_count;
end;
$function$;

create or replace function public.soolgyul_purge_expired_anonymous_taste_cards(batch_limit integer DEFAULT 500)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cutoff timestamptz := now() - interval '30 days';
  batch_size integer := greatest(batch_limit, 1);
  batch_count integer;
  deleted_records integer := 0;
begin
  -- Attempts first: an attempt still referencing the card snapshot would block
  -- the cascading card delete below.
  delete from public.taste_card_generation_attempts attempt_row
  where attempt_row.anonymous_session_digest is not null
    and attempt_row.created_at < cutoff;

  -- Up to 1000 visitor cards may start in an hour; take batches until the
  -- expired ones run out, at most twenty a run.
  for batch_number in 1..20 loop
    with expired as (
      select record_row.id
      from public.drink_records record_row
      where record_row.user_id is null
        and record_row.anonymous_session_id is not null
        and record_row.created_at < cutoff
      order by record_row.created_at
      limit batch_size
    )
    delete from public.drink_records record_row
    using expired
    where record_row.id = expired.id;
    get diagnostics batch_count = row_count;
    deleted_records := deleted_records + batch_count;
    exit when batch_count < batch_size;
  end loop;
  return deleted_records;
end;
$function$;

alter policy soolgyul_private_owner_read on storage.objects using (
  bucket_id = 'soolgyul-private'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (select public.soolgyul_account_active((select auth.uid())))
);

alter policy soolgyul_private_owner_delete on storage.objects using (
  bucket_id = 'soolgyul-private'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (select public.soolgyul_account_active((select auth.uid())))
);

alter policy soolgyul_private_admin_inquiry_read on storage.objects using (
  bucket_id = 'soolgyul-private'
  and (storage.foldername(name))[2] = 'inquiries'
  and (select public.soolgyul_admin_has_role(array['admin']))
);

alter policy soolgyul_editorial_media_admin_insert on storage.objects with check (
  bucket_id = 'soolgyul-editorial'
  and (select public.soolgyul_admin_has_role())
);

alter policy editorial_articles_authenticated_select on public.editorial_articles using (
  (status = 'published' and published_at is not null and published_at <= now())
  or (select public.soolgyul_admin_has_role())
);

alter policy editorial_articles_admin_insert on public.editorial_articles with check (
  (select public.soolgyul_admin_has_role(array['admin']))
  or ((select public.soolgyul_admin_has_role(array['editor']))
    and status = 'draft' and published_at is null)
);

alter policy editorial_articles_admin_update on public.editorial_articles
  using (
    (select public.soolgyul_admin_has_role(array['admin']))
    or ((select public.soolgyul_admin_has_role(array['editor']))
      and status = 'draft' and published_at is null)
  )
  with check (
    (select public.soolgyul_admin_has_role(array['admin']))
    or ((select public.soolgyul_admin_has_role(array['editor']))
      and status = 'draft' and published_at is null)
  );

alter policy editorial_articles_admin_delete_draft on public.editorial_articles using (
  (select public.soolgyul_admin_has_role(array['admin']))
  and status = 'draft' and published_at is null
);

alter policy editorial_article_media_authenticated_select
  on public.editorial_article_media_assets using (
  exists (
    select 1 from public.editorial_articles article
    where article.id = editorial_article_media_assets.article_id
      and article.status = 'published'
      and article.published_at is not null
      and article.published_at <= now()
  )
  or (select public.soolgyul_admin_has_role())
);

alter policy editorial_article_media_admin_insert
  on public.editorial_article_media_assets with check (
  (select public.soolgyul_admin_has_role(array['admin']))
  or ((select public.soolgyul_admin_has_role(array['editor'])) and exists (
    select 1 from public.editorial_articles article
    where article.id = editorial_article_media_assets.article_id
      and article.status = 'draft' and article.published_at is null
  ))
);

alter policy editorial_article_media_admin_update
  on public.editorial_article_media_assets
  using (
    (select public.soolgyul_admin_has_role(array['admin']))
    or ((select public.soolgyul_admin_has_role(array['editor'])) and exists (
      select 1 from public.editorial_articles article
      where article.id = editorial_article_media_assets.article_id
        and article.status = 'draft' and article.published_at is null
    ))
  )
  with check (
    (select public.soolgyul_admin_has_role(array['admin']))
    or ((select public.soolgyul_admin_has_role(array['editor'])) and exists (
      select 1 from public.editorial_articles article
      where article.id = editorial_article_media_assets.article_id
        and article.status = 'draft' and article.published_at is null
    ))
  );

alter policy editorial_article_media_admin_delete
  on public.editorial_article_media_assets using (
  (select public.soolgyul_admin_has_role(array['admin']))
  or ((select public.soolgyul_admin_has_role(array['editor'])) and exists (
    select 1 from public.editorial_articles article
    where article.id = editorial_article_media_assets.article_id
      and article.status = 'draft' and article.published_at is null
  ))
);

alter policy editorial_article_interests_authenticated_select
  on public.editorial_article_interests using (
  exists (
    select 1 from public.editorial_articles article
    where article.id = editorial_article_interests.article_id
      and article.status = 'published'
      and article.published_at is not null
      and article.published_at <= now()
  )
  or (select public.soolgyul_admin_has_role())
);

alter policy editorial_article_interests_admin_insert
  on public.editorial_article_interests with check (
  (select public.soolgyul_admin_has_role(array['admin']))
  or ((select public.soolgyul_admin_has_role(array['editor'])) and exists (
    select 1 from public.editorial_articles article
    where article.id = editorial_article_interests.article_id
      and article.status = 'draft' and article.published_at is null
  ))
);

alter policy editorial_article_interests_admin_delete
  on public.editorial_article_interests using (
  (select public.soolgyul_admin_has_role(array['admin']))
  or ((select public.soolgyul_admin_has_role(array['editor'])) and exists (
    select 1 from public.editorial_articles article
    where article.id = editorial_article_interests.article_id
      and article.status = 'draft' and article.published_at is null
  ))
);

alter policy site_posts_authenticated_select on public.site_posts using (
  status = 'published' or (select public.soolgyul_admin_has_role())
);

alter policy site_posts_admin_insert on public.site_posts with check (
  (select public.soolgyul_admin_has_role(array['admin']))
  or ((select public.soolgyul_admin_has_role(array['editor'])) and status = 'draft')
);

alter policy site_posts_admin_update on public.site_posts
  using (
    (select public.soolgyul_admin_has_role(array['admin']))
    or ((select public.soolgyul_admin_has_role(array['editor'])) and status = 'draft')
  )
  with check (
    (select public.soolgyul_admin_has_role(array['admin']))
    or ((select public.soolgyul_admin_has_role(array['editor'])) and status = 'draft')
  );

alter policy site_posts_admin_delete on public.site_posts using (
  (select public.soolgyul_admin_has_role(array['admin']))
);

create index drink_discovery_events_user_occurred_idx
  on public.drink_discovery_events (user_id, occurred_at)
  where user_id is not null;
drop index public.drink_discovery_events_user_idx;
create index drink_records_user_created_idx
  on public.drink_records (user_id, created_at);
drop index public.drink_records_user_id_idx;
drop index public.drink_record_answers_record_id_idx;
