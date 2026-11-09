-- User tables slimmed after the 2026-10-27 review. Dropped: columns that
-- repeat another column (identification_mode, alcohol_name_snapshot, category,
-- deletion_scheduled_at = requested + 30 days), columns nothing wrote or read
-- (photo_storage_path, saved_at, the three schema_version), copies of
-- questionnaire text (question_label_snapshot, selected_option_labels_snapshot;
-- the questionnaire version keeps the text) and the per-question "no matching
-- expression" feedback (option_gap_reported, feedback_text), which the app no
-- longer offers. Liked cards are keyed by the drink record, dropping the old
-- drink_result_summaries name.

-- 1. users: the deletion deadline is derived from the request time.
create or replace function public.soolgyul_deletion_due_at(requested_at timestamptz)
returns timestamptz
language sql
stable
set search_path to ''
as $$
  select requested_at + interval '30 days';
$$;
revoke execute on function public.soolgyul_deletion_due_at(timestamptz) from public;

alter table public.users drop column account_status;
alter table public.users drop column deletion_scheduled_at;
alter table public.users add column account_status text generated always as (
  case
    when purged_at is not null then 'purged'
    when deletion_requested_at is not null then 'scheduled_deletion'
    when disabled_at is not null then 'disabled'
    else 'active'
  end
) stored;

create or replace function public.soolgyul_account_active(target_user_id uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from public.users u
    where u.id = target_user_id
      and u.disabled_at is null
      and u.deletion_requested_at is null
      and u.purged_at is null
  );
$$;

create or replace function public.soolgyul_admin_has_role(required_roles text[] default array['editor'::text, 'admin'::text])
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select exists (
    select 1
    from public.admin_user_roles access_grant
    join public.users account on account.id = access_grant.user_id
    where access_grant.user_id = (select auth.uid())
      and access_grant.role = any(required_roles)
      and account.disabled_at is null
      and account.deletion_requested_at is null
      and account.purged_at is null
  );
$$;

create or replace function public.soolgyul_get_my_deletion_state()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare u public.users%rowtype;
begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 select * into u from public.users where id=auth.uid();
 if not found then raise exception 'account_not_found'; end if;
 return jsonb_build_object('deletion_state',case when u.purged_at is not null then 'purged'
   when u.deletion_requested_at is not null then 'scheduled' else 'active' end,
  'requested_at',u.deletion_requested_at,
  'scheduled_deletion_at',public.soolgyul_deletion_due_at(u.deletion_requested_at),
  'restore_available',u.purged_at is null and u.disabled_at is null
    and public.soolgyul_deletion_due_at(u.deletion_requested_at)>statement_timestamp(),
  'provider_revoked',u.deletion_provider_revoked_at is not null);
end; $$;

create or replace function public.soolgyul_request_my_account_deletion()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare u public.users%rowtype;
begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 select * into u from public.users where id=auth.uid() for update;
 if not found or u.disabled_at is not null or u.purged_at is not null then
  raise exception 'active_account_required'; end if;
 if u.deletion_requested_at is null then
  update public.users set deletion_requested_at=statement_timestamp(),
   deletion_provider_revoked_at=null where id=u.id;
 end if;
 return public.soolgyul_get_my_deletion_state();
end; $$;

create or replace function public.soolgyul_restore_my_account()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare u public.users%rowtype;
begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 select * into u from public.users where id=auth.uid() for update;
 if not found or u.disabled_at is not null or u.purged_at is not null then
  raise exception 'account_restore_unavailable'; end if;
 if u.deletion_requested_at is not null
   and public.soolgyul_deletion_due_at(u.deletion_requested_at)<=statement_timestamp() then
  raise exception 'restore_window_closed'; end if;
 update public.users set deletion_requested_at=null,
  deletion_provider_revoked_at=null where id=u.id;
 -- Never alter record.deleted_at or other user content.
 return public.soolgyul_get_my_deletion_state();
end; $$;

create or replace function public.soolgyul_invalidate_deletion_revocation_on_login()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
 if new.last_sign_in_at is distinct from old.last_sign_in_at then
  update public.users set deletion_provider_revoked_at=null
   where id=new.id and deletion_requested_at is not null and purged_at is null;
 end if;
 return new;
end; $$;

create or replace function public.soolgyul_mark_deletion_provider_revoked_v2(target_user_id uuid, requested_at timestamp with time zone, authenticated_at timestamp with time zone)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
begin
 -- Same lock order as the Auth login trigger: Auth row, then product row.
 perform 1 from auth.users where id=target_user_id and last_sign_in_at=authenticated_at for share;
 if not found then return false; end if;
 update public.users set deletion_provider_revoked_at=statement_timestamp()
 where id=target_user_id and deletion_requested_at=requested_at and purged_at is null;
 return found;
end; $$;

create or replace function public.soolgyul_update_my_display_name(p_display_name text, p_idempotency_key uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  target_user_id uuid;
  normalized_display_name text;
  response_payload jsonb;
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
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

  perform 1
  from public.users product_user
  where product_user.id = target_user_id
    and product_user.disabled_at is null
    and product_user.deletion_requested_at is null
    and product_user.purged_at is null
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  update public.users profile
  set display_name = normalized_display_name,
      updated_at = now()
  where profile.id = target_user_id
    and profile.display_name is distinct from normalized_display_name;

  response_payload := jsonb_build_object('display_name', normalized_display_name);

  return response_payload;
end
$$;

create or replace function public.soolgyul_replace_my_drink_interests(p_interest_group_keys text[], p_idempotency_key uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  target_user_id uuid;
  normalized_interest_keys text[];
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'idempotency_key_required';
  end if;
  if p_interest_group_keys is null
    or cardinality(p_interest_group_keys) < 1
    or cardinality(p_interest_group_keys) > 5
  then
    raise exception using errcode = '22023', message = 'drink_interest_count_invalid';
  end if;
  if array_position(p_interest_group_keys, null) is not null
    or (
      select count(distinct interest_key)
      from unnest(p_interest_group_keys) interest_key
    ) <> cardinality(p_interest_group_keys)
  then
    raise exception using errcode = '22023', message = 'drink_interest_keys_invalid';
  end if;

  select array_agg(interest.interest_key order by interest.sort_order, interest.interest_key)
  into normalized_interest_keys
  from (
    select category.interest_key, min(category.sort_order) as sort_order
    from public.alcohol_categories category
    where category.is_active
      and category.interest_key = any(p_interest_group_keys)
    group by category.interest_key
  ) interest;

  if cardinality(coalesce(normalized_interest_keys, array[]::text[]))
    <> cardinality(p_interest_group_keys)
  then
    raise exception using errcode = '22023', message = 'drink_interest_keys_invalid';
  end if;

  perform 1
  from public.users product_user
  where product_user.id = target_user_id
    and product_user.disabled_at is null
    and product_user.deletion_requested_at is null
    and product_user.purged_at is null
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  delete from public.user_drink_interests selection
  where selection.user_id = target_user_id
    and selection.interest_key <> all(normalized_interest_keys);

  insert into public.user_drink_interests (user_id, interest_key)
  select target_user_id, chosen.interest_key
  from unnest(normalized_interest_keys) with ordinality as chosen(interest_key, position)
  where not exists (
    select 1
    from public.user_drink_interests current_selection
    where current_selection.user_id = target_user_id
      and current_selection.interest_key = chosen.interest_key
  )
  order by chosen.position;

  return jsonb_build_object('interest_group_keys', to_jsonb(normalized_interest_keys));
end
$$;

create or replace function public.soolgyul_complete_my_profile_v3(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text default null::text, p_gender_consent_accepted boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  target_user_id uuid;
  trusted_auth_provider text;
  normalized_display_name text;
  accepted_timestamp timestamptz := clock_timestamp();
  response_payload jsonb;
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_birth_date is null or not isfinite(p_birth_date)
    or p_birth_date < date '1900-01-01' or p_birth_date > current_date then
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
    or extract(year from current_date)::integer
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
    return public.soolgyul_get_my_profile_status_v1();
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
$$;

-- 2. drink_records: the identity is the pair of columns itself.
drop trigger drink_records_guard_final_identity on public.drink_records;
alter table public.drink_records
  drop column identification_mode,
  drop column alcohol_name_snapshot,
  drop column category,
  drop column photo_storage_path,
  drop column saved_at,
  drop column schema_version;
alter table public.drink_records add constraint drink_records_identity_check check (
  (alcohol_item_id is not null and entered_alcohol_name is null)
  or (alcohol_item_id is null and nullif(btrim(entered_alcohol_name), '') is not null)
);
create trigger drink_records_guard_final_identity
  before update of questionnaire_version_id, alcohol_item_id, entered_alcohol_name
  on public.drink_records
  for each row
  when (old.questionnaire_version_id is distinct from new.questionnaire_version_id
    or old.alcohol_item_id is distinct from new.alcohol_item_id
    or old.entered_alcohol_name is distinct from new.entered_alcohol_name)
  execute function public.soolgyul_guard_final_drink_record_identity();

-- 3. drink_record_answers keep the keys; the questionnaire version keeps the text.
alter table public.drink_record_answers
  drop column question_label_snapshot,
  drop column selected_option_labels_snapshot,
  drop column schema_version,
  drop column option_gap_reported,
  drop column feedback_text;

-- 4. taste_cards: every card is the v2 wire; the old-engine columns stay for now.
alter table public.taste_cards drop column schema_version;
alter table public.taste_cards add constraint taste_cards_legacy_envelope_check check (
  btrim(rule_version) <> '' and jsonb_typeof(result_snapshot) = 'object'
);
alter table public.taste_cards rename constraint drink_result_summaries_pkey to taste_cards_pkey;
alter table public.taste_cards rename constraint drink_result_summaries_drink_record_id_fkey to taste_cards_drink_record_id_fkey;

-- 5. Liked cards are keyed by the drink record (one card per record).
drop policy user_liked_drink_cards_owner_select on public.user_liked_drink_cards;
drop policy user_liked_drink_cards_owner_insert on public.user_liked_drink_cards;
alter table public.user_liked_drink_cards
  drop constraint user_liked_drink_cards_drink_result_summary_id_fkey;
update public.user_liked_drink_cards liked
set drink_result_summary_id = card.drink_record_id
from public.taste_cards card
where card.id = liked.drink_result_summary_id;
alter table public.user_liked_drink_cards
  rename column drink_result_summary_id to drink_record_id;
alter table public.user_liked_drink_cards
  add constraint user_liked_drink_cards_drink_record_id_fkey
  foreign key (drink_record_id) references public.drink_records(id) on delete cascade;
alter index public.user_liked_drink_cards_result_idx rename to user_liked_drink_cards_record_idx;
comment on column public.user_liked_drink_cards.drink_record_id is
  'The owner''s drink record whose card is liked.';
create policy user_liked_drink_cards_owner_select on public.user_liked_drink_cards
  for select to authenticated
  using (
    user_id = auth.uid()
    and public.soolgyul_account_active(user_id)
    and exists (
      select 1
      from public.drink_records record_row
      where record_row.id = user_liked_drink_cards.drink_record_id
        and record_row.user_id = user_liked_drink_cards.user_id
        and record_row.deleted_at is null
    )
  );
create policy user_liked_drink_cards_owner_insert on public.user_liked_drink_cards
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.soolgyul_account_active(user_id)
    and exists (
      select 1
      from public.drink_records record_row
      where record_row.id = user_liked_drink_cards.drink_record_id
        and record_row.user_id = user_liked_drink_cards.user_id
        and record_row.deleted_at is null
    )
  );

-- 6. Card functions read the identity from the record and the catalog.
create or replace function public.soolgyul_build_taste_card_result(target_result_summary_id uuid)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select jsonb_build_object(
    'wire_schema_version', 'taste-card-result-wire-v2',
    'result_id', summary_row.id::text,
    'record_id', record_row.id::text,
    'snapshot_ref', summary_row.snapshot_ref,
    'ownership_state', case
      when record_row.user_id is null then 'anonymous'
      else 'saved'
    end,
    'alcohol_identification', jsonb_build_object(
      'mode', case
        when record_row.alcohol_item_id is null then 'direct_input'
        else 'catalog_match'
      end,
      'alcohol_item_id', record_row.alcohol_item_id,
      'entered_alcohol_name', record_row.entered_alcohol_name,
      'alcohol_name_snapshot', coalesce(item_row.name_ko, record_row.entered_alcohol_name),
      'category', category_row.category_key
    ),
    'rendered_snapshot', summary_row.rendered_snapshot,
    'created_at', summary_row.snapshot_created_at
  )
  from public.taste_cards summary_row
  join public.drink_records record_row
    on record_row.id = summary_row.drink_record_id
  left join public.alcohol_items item_row
    on item_row.id = record_row.alcohol_item_id
  left join public.alcohol_categories category_row
    on category_row.id = item_row.alcohol_category_id
  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id
    and record_row.deleted_at is null;
$$;

create or replace function public.soolgyul_convert_anonymous_taste_card(target_user_id uuid, target_result_summary_id uuid, target_anonymous_session_digest text, target_idempotency_key uuid)
returns table(drink_record_id uuid, result_summary_id uuid, claim_snapshot_id uuid, converted boolean)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  target_record public.drink_records%rowtype;
  target_snapshot_id uuid;
  did_convert boolean := false;
begin
  if target_user_id is null
    or target_result_summary_id is null
    or target_idempotency_key is null
    or target_anonymous_session_digest is null
    or target_anonymous_session_digest !~ '^[0-9a-f]{64}$'
  then
    raise exception using
      errcode = '22023',
      message = 'invalid anonymous taste card conversion request';
  end if;

  -- Use the same user-then-record lock order as account/profile writes.
  perform 1 from public.users u where u.id = target_user_id for update;
  if not found or not public.soolgyul_account_active(target_user_id) then
    raise exception using
      errcode = '42501',
      message = 'active account required';
  end if;

  if not public.soolgyul_adult_profile_complete(target_user_id) then
    raise exception using
      errcode = '42501',
      message = 'completed adult profile required';
  end if;

  select record_row.*
  into target_record
  from public.taste_cards summary_row
  join public.drink_records record_row
    on record_row.id = summary_row.drink_record_id
  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id
  for update of record_row;

  if not found or target_record.deleted_at is not null then
    raise exception using
      errcode = 'P0002',
      message = 'taste card result not found';
  end if;

  select summary_row.snapshot_id
  into target_snapshot_id
  from public.taste_cards summary_row
  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id;

  if target_snapshot_id is null then
    raise exception using
      errcode = '55000',
      message = 'final taste card snapshot required';
  end if;

  if not exists (
    select 1
    from public.taste_card_generation_attempts attempt_row
    where attempt_row.anonymous_session_digest = target_anonymous_session_digest
      and attempt_row.result_summary_id = target_result_summary_id
      and attempt_row.claim_snapshot_id = target_snapshot_id
      and attempt_row.state = 'final'
      and (target_record.user_id = target_user_id
        or attempt_row.conversion_expires_at > now())
  ) then
    raise exception using
      errcode = '42501',
      message = 'anonymous taste card proof is invalid or expired';
  end if;

  if target_record.user_id is null then
    update public.drink_records
    set user_id = target_user_id,
        anonymous_session_id = null,
        updated_at = now()
    where id = target_record.id;
    did_convert := true;
  elsif target_record.user_id <> target_user_id then
    raise exception using
      errcode = '42501',
      message = 'taste card is owned by another account';
  end if;

  return query
  select
    target_record.id,
    target_result_summary_id,
    target_snapshot_id,
    did_convert;
end;
$$;

create or replace function public.soolgyul_purge_expired_anonymous_taste_cards(batch_limit integer default 500)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  cutoff timestamptz := now() - interval '24 hours';
  deleted_records integer;
begin
  -- Attempts first: an attempt still referencing the card snapshot would block
  -- the cascading card delete below.
  delete from public.taste_card_generation_attempts attempt_row
  where attempt_row.anonymous_session_digest is not null
    and attempt_row.created_at < cutoff;

  with expired as (
    select record_row.id
    from public.drink_records record_row
    where record_row.user_id is null
      and record_row.anonymous_session_id is not null
      and record_row.created_at < cutoff
    order by record_row.created_at
    limit greatest(batch_limit, 1)
  )
  delete from public.drink_records record_row
  using expired
  where record_row.id = expired.id;
  get diagnostics deleted_records = row_count;
  return deleted_records;
end;
$$;

create or replace function public.soolgyul_finalize_taste_card_generation(input_bundle jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  attempt_row public.taste_card_generation_attempts%rowtype;
  request_row jsonb := input_bundle->'request';
  identification_row jsonb := input_bundle->'alcohol_identification';
  version_row jsonb := input_bundle->'version_vector';
  rendered_row jsonb := input_bundle->'rendered_view';
  answer_row jsonb;
  question_id uuid;
  generated_snapshot_id uuid := gen_random_uuid();
  principal_kind text := input_bundle #>> '{principal,kind}';
  wire_schema_version text := input_bundle->>'wire_schema_version';
  selected_catalog_id uuid;
  resolved_alcohol_item_id uuid;
  semantic_snapshot_row jsonb;
begin
  if jsonb_typeof(input_bundle) is distinct from 'object'
    or jsonb_typeof(request_row) is distinct from 'object'
    or jsonb_typeof(identification_row) is distinct from 'object'
    or jsonb_typeof(version_row) is distinct from 'object'
    or jsonb_typeof(rendered_row) is distinct from 'object'
  then
    raise exception using
      errcode = '22023',
      message = 'taste card finalization bundle is invalid';
  end if;

  if wire_schema_version is distinct from 'taste-card-result-wire-v2' then
    raise exception using
      errcode = '22023',
      message = 'taste card wire schema version is invalid';
  end if;

  if (
    rendered_row #>> '{metadata,schema_version}' is distinct from '2'
    or rendered_row #>> '{metadata,snapshot_ref}'
      is distinct from input_bundle->>'semantic_snapshot_id'
    or jsonb_typeof(input_bundle->'evidence_context_v2') is distinct from 'object'
    or jsonb_typeof(input_bundle->'insight_plan_v2') is distinct from 'object'
    or jsonb_typeof(input_bundle->'style_recommendation_plan_v2') is distinct from 'object'
    or pg_column_size(input_bundle->'evidence_context_v2') > 262144
    or pg_column_size(input_bundle->'insight_plan_v2') > 65536
    or pg_column_size(input_bundle->'style_recommendation_plan_v2') > 65536
  ) then
    raise exception using
      errcode = '22023',
      message = 'taste card V2 private or public snapshot is invalid';
  end if;

  select existing_attempt.*
  into attempt_row
  from public.taste_card_generation_attempts existing_attempt
  where existing_attempt.attempt_ref = input_bundle->>'attempt_ref'
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'generation attempt not found';
  end if;
  if attempt_row.request_digest is distinct from input_bundle->>'request_digest' then
    raise exception using errcode = '22023', message = 'idempotency_conflict';
  end if;
  if attempt_row.idempotency_key is distinct from
    (request_row->>'idempotency_key')::uuid
  then
    raise exception using errcode = '22023', message = 'idempotency key mismatch';
  end if;

  if principal_kind = 'authenticated' then
    if attempt_row.owner_user_id is distinct from
      (input_bundle #>> '{principal,user_id}')::uuid
    then
      raise exception using errcode = '42501', message = 'generation principal mismatch';
    end if;
    if not public.soolgyul_account_active(attempt_row.owner_user_id)
      or not public.soolgyul_adult_profile_complete(attempt_row.owner_user_id)
    then
      raise exception using errcode = '42501', message = 'completed adult profile required';
    end if;
  elsif principal_kind = 'anonymous' then
    if attempt_row.anonymous_session_digest is distinct from
      input_bundle #>> '{principal,anonymous_session_digest}'
    then
      raise exception using errcode = '42501', message = 'generation principal mismatch';
    end if;
    if encode(
      extensions.digest(request_row->>'anonymous_session_id', 'sha256'),
      'hex'
    ) is distinct from attempt_row.anonymous_session_digest
    then
      raise exception using errcode = '42501', message = 'anonymous session mismatch';
    end if;
  else
    raise exception using errcode = '22023', message = 'generation principal invalid';
  end if;

  if attempt_row.state = 'final' then
    return public.soolgyul_build_taste_card_result(attempt_row.result_summary_id);
  end if;

  if identification_row->>'mode' = 'catalog_match' then
    selected_catalog_id := nullif(
      identification_row->>'alcohol_item_id',
      ''
    )::uuid;
    if selected_catalog_id is null then
      raise exception using errcode = '22023', message = 'catalog identifier required';
    end if;

    select item_row.id
    into resolved_alcohol_item_id
    from public.alcohol_items item_row
    where item_row.id = selected_catalog_id
      and item_row.publish_status = 'published';

    if resolved_alcohol_item_id is null then
      raise exception using errcode = '22023', message = 'catalog identifier is not publishable';
    end if;
  elsif identification_row->>'mode' = 'direct_input' then
    if identification_row->'alcohol_item_id' is distinct from 'null'::jsonb then
      raise exception using errcode = '22023', message = 'direct input cannot use a catalog identifier';
    end if;
  else
    raise exception using errcode = '22023', message = 'identification mode is invalid';
  end if;

  insert into public.drink_records (
    id,
    user_id,
    anonymous_session_id,
    questionnaire_version_id,
    alcohol_item_id,
    entered_alcohol_name,
    one_line_note,
    idempotency_key
  )
  values (
    attempt_row.reserved_record_id,
    case when principal_kind = 'authenticated' then attempt_row.owner_user_id else null end,
    case when principal_kind = 'anonymous' then request_row->>'anonymous_session_id' else null end,
    (request_row->>'questionnaire_version_id')::uuid,
    resolved_alcohol_item_id,
    nullif(identification_row->>'entered_alcohol_name', ''),
    nullif(request_row->>'q7_free_text', ''),
    request_row->>'idempotency_key'
  );

  for answer_row in
    select value
    from jsonb_array_elements(coalesce(request_row->'answers', '[]'::jsonb))
  loop
    select question_row.id
    into question_id
    from public.questionnaire_questions question_row
    where question_row.questionnaire_version_id =
      (request_row->>'questionnaire_version_id')::uuid
      and question_row.question_key = answer_row->>'question_key';

    insert into public.drink_record_answers (
      drink_record_id,
      questionnaire_version_id,
      questionnaire_question_id,
      question_key,
      selected_option_keys,
      free_text
    )
    values (
      attempt_row.reserved_record_id,
      (request_row->>'questionnaire_version_id')::uuid,
      question_id,
      answer_row->>'question_key',
      array(
        select jsonb_array_elements_text(
          coalesce(answer_row->'selected_option_keys', '[]'::jsonb)
        )
      ),
      nullif(answer_row->>'free_text', '')
    );
  end loop;

  insert into public.taste_cards (
    id,
    drink_record_id,
    result_type_key,
    taste_axis_scores,
    preference_cues,
    next_drink_directions,
    burdensome_directions,
    summary_paragraphs,
    share_card_text,
    catalog_evidence,
    rule_version,
    result_snapshot
  )
  values (
    attempt_row.reserved_result_summary_id,
    attempt_row.reserved_record_id,
    'taste_card_v2',
    '{}'::jsonb,
    coalesce(rendered_row->'core_summary'->'blocks', '[]'::jsonb),
    coalesce(rendered_row->'next_drink'->'candidates', '[]'::jsonb),
    jsonb_build_array(rendered_row #>> '{next_drink,defer_formula}'),
    coalesce(rendered_row->'discovery'->'blocks', '[]'::jsonb),
    coalesce(
      rendered_row #>> '{core_summary,blocks,0,text}',
      identification_row->>'alcohol_name_snapshot'
    ),
    jsonb_build_object(
      'selected_catalog_id', identification_row->'alcohol_item_id',
      'resolved_alcohol_item_id', resolved_alcohol_item_id,
      'entered_alcohol_name', identification_row->'entered_alcohol_name',
      'alcohol_name_snapshot', identification_row->'alcohol_name_snapshot'
    ),
    rendered_row #>> '{metadata,rule_version}',
    rendered_row
  );

  semantic_snapshot_row := jsonb_build_object(
    'snapshot_id', input_bundle->>'semantic_snapshot_id',
    'snapshot_status', 'final',
    'subject_record_ref', input_bundle #>> '{canonical_input,subject_record_ref}',
    'canonical_input_digest', input_bundle->>'canonical_input_digest',
    'version_vector', version_row,
    'source_statuses', input_bundle #> '{canonical_input,source_statuses}',
    'observations', input_bundle #> '{canonical_input,observations}',
    'evidence_refs', input_bundle #> '{canonical_input,evidence_refs}',
    'claim_decisions', input_bundle->'decisions',
    'semantic_projection', input_bundle->'semantic_projection',
    'rendered_projection', null,
    'supersedes_snapshot_id', 'none',
    'withdrawal_reason_code', 'none',
    'created_at', input_bundle->>'generated_at',
    'evidence_context_v2', input_bundle->'evidence_context_v2',
    'insight_plan_v2', input_bundle->'insight_plan_v2',
    'style_recommendation_plan_v2', input_bundle->'style_recommendation_plan_v2'
  );

  if pg_column_size(semantic_snapshot_row) > 524288 then
    raise exception using
      errcode = '22023',
      message = 'taste card semantic snapshot exceeds the persistence limit';
  end if;

  update public.taste_cards set (
    snapshot_id,
    snapshot_ref,
    canonical_input_digest,
    questionnaire_version,
    catalog_taxonomy_version,
    catalog_evidence_version,
    adapter_compatibility_version,
    canonical_schema_version,
    memo_rule_version,
    claim_registry_version,
    claim_rule_versions,
    copy_template_version,
    presentation_version,
    source_statuses,
    semantic_snapshot,
    rendered_snapshot
  ) = (
    generated_snapshot_id,
    input_bundle->>'semantic_snapshot_id',
    input_bundle->>'canonical_input_digest',
    version_row->>'questionnaire_version',
    version_row->>'catalog_taxonomy_version',
    version_row->>'catalog_evidence_version',
    version_row->>'adapter_compatibility_version',
    version_row->>'canonical_schema_version',
    version_row->>'memo_rule_version',
    version_row->>'claim_registry_version',
    version_row->'claim_rule_versions',
    version_row->>'copy_template_version',
    version_row->>'presentation_version',
    input_bundle #> '{canonical_input,source_statuses}',
    semantic_snapshot_row,
    rendered_row
  ), lifecycle = 'final', snapshot_created_at = now()
  where id = attempt_row.reserved_result_summary_id;

  update public.taste_card_generation_attempts
  set state = 'final',
      error_code = null,
      retry_after = null,
      result_summary_id = attempt_row.reserved_result_summary_id,
      claim_snapshot_id = generated_snapshot_id,
      conversion_key_version = input_bundle->>'conversion_key_version',
      conversion_expires_at = nullif(
        input_bundle->>'conversion_expires_at',
        ''
      )::timestamptz,
      completed_at = now(),
      updated_at = now()
  where id = attempt_row.id;

  return public.soolgyul_build_taste_card_result(
    attempt_row.reserved_result_summary_id
  );
end;
$$;

-- 7. Withdrawal keeps the record keys; names and labels are looked up by key.
create or replace function public.soolgyul_finalize_withdrawn_account_data(target_user_id uuid)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare account_row public.users%rowtype; retained_count integer;
begin
  select * into account_row from public.users where id=target_user_id for update;
  if not found then return 0; end if;
  if account_row.purged_at is not null then return 0; end if;
  if account_row.deletion_provider_revoked_at is null then raise exception 'provider_revocation_required'; end if;
  if account_row.account_status <> 'scheduled_deletion'
    or account_row.deletion_requested_at is null
    or public.soolgyul_deletion_due_at(account_row.deletion_requested_at) > statement_timestamp() then
    raise exception 'account_purge_not_due';
  end if;
  if exists(select 1 from storage.objects where bucket_id='soolgyul-private'
    and starts_with(name,target_user_id::text || '/')) then
    raise exception 'private_storage_cleanup_required';
  end if;

  -- Preserve memo and questionnaire free text verbatim; never archive support
  -- inquiries, names, account metadata, consent history, or raw engine snapshots.
  insert into public.withdrawn_drink_records(birth_year,gender,record_data)
  select extract(year from account_row.birth_date)::integer,
    case when account_row.gender_consent_accepted_at is not null then account_row.gender end,
    jsonb_build_object(
      'alcohol_item_id',r.alcohol_item_id,
      'entered_alcohol_name',r.entered_alcohol_name,
      'one_line_note',r.one_line_note,
      'questionnaire_version_id',r.questionnaire_version_id,
      'answers',coalesce((select jsonb_agg(jsonb_build_object(
        'question_key',a.question_key,
        'selected_option_keys',a.selected_option_keys,
        'free_text',a.free_text) order by a.question_key,a.id)
        from public.drink_record_answers a where a.drink_record_id=r.id),'[]'::jsonb),
      'card',(select public.soolgyul_strip_retained_card_links(jsonb_build_object(
        'result_type_key',c.result_type_key,'taste_axis_scores',c.taste_axis_scores,
        'preference_cues',c.preference_cues,'next_drink_directions',c.next_drink_directions,
        'burdensome_directions',c.burdensome_directions,
        'summary_paragraphs',c.summary_paragraphs,'share_card_text',c.share_card_text,
        'rendered_snapshot',c.rendered_snapshot))
        from public.taste_cards c where c.drink_record_id=r.id)
    )
  from public.drink_records r
  where r.user_id=target_user_id and r.deleted_at is null;
  get diagnostics retained_count = row_count;

  -- Converted anonymous attempts can still carry an anonymous proof. Remove
  -- them by record linkage too, not just by owner_user_id.
  delete from public.taste_card_generation_attempts a
  where a.owner_user_id=target_user_id or exists (
    select 1 from public.drink_records r where r.user_id=target_user_id
      and (r.id=a.reserved_record_id or exists (
        select 1 from public.taste_cards c where c.drink_record_id=r.id
          and c.id=a.result_summary_id)));
  delete from public.drink_records where user_id=target_user_id;
  update public.users set birth_date=null,gender=null,
    gender_consent_accepted_at=null,gender_consent_version=null,
    display_name=null,email=null,provider_user_id=gen_random_uuid()::text,
    age_confirmed_at=null,profile_created_at=null,last_sign_in_at=null,
    purged_at=statement_timestamp(),updated_at=statement_timestamp()
  where id=target_user_id;
  return retained_count;
end;
$$;
