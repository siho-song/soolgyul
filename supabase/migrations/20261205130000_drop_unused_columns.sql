-- Columns that nothing fills or nothing reads go away.
--   * drink_records.deleted_at: a record the member deletes is removed
--     outright and kept without its owner, so no row ever carried the mark,
--     yet nine functions and four policies still tested it.
--   * users.email: a copy of the address Auth holds, read nowhere.
--   * users.provider_user_id: always the account id; its unique rule and the
--     conflict check on it could never fire.
--   * users.profile_created_at: filled when the row was made, the same
--     moment as created_at.
--   * drink_record_answers.free_text: the server refuses an answer that
--     carries typed text, so it was always null.
-- The owner policy on taste_cards takes the table's name on the way.
set local lock_timeout = '5s';

alter policy drink_records_owner_select on public.drink_records using (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
);

alter policy drink_result_summaries_owner_select on public.taste_cards
  rename to taste_cards_owner_select;
alter policy taste_cards_owner_select on public.taste_cards using (
  (select public.soolgyul_account_active((select auth.uid())))
  and exists (
    select 1
    from public.drink_records r
    where r.id = taste_cards.drink_record_id
      and r.user_id = (select auth.uid())
  )
);

alter policy user_liked_drink_cards_owner_select on public.user_liked_drink_cards using (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
  and exists (
    select 1
    from public.drink_records record_row
    where record_row.id = user_liked_drink_cards.drink_record_id
      and record_row.user_id = user_liked_drink_cards.user_id
  )
);

alter policy user_liked_drink_cards_owner_insert on public.user_liked_drink_cards with check (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
  and exists (
    select 1
    from public.drink_records record_row
    where record_row.id = user_liked_drink_cards.drink_record_id
      and record_row.user_id = user_liked_drink_cards.user_id
  )
);

create or replace function public.soolgyul_build_taste_card_result(target_result_summary_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'wire_schema_version', 'taste-card-result-wire-v3',
    'result_id', summary_row.id::text,
    'record_id', record_row.id::text,
    'snapshot_ref', summary_row.snapshot_ref,
    'ownership_state', case
      when record_row.user_id is null then 'anonymous'
      else 'saved'
    end,
    'alcohol_identification', jsonb_build_object(
      'mode', 'catalog_match',
      'alcohol_item_id', record_row.alcohol_item_id,
      'alcohol_name_snapshot', item_row.name_ko,
      'category', category_row.category_key
    ),
    'rendered_snapshot', summary_row.rendered_snapshot,
    'created_at', summary_row.snapshot_created_at
  )
  from public.taste_cards summary_row
  join public.drink_records record_row
    on record_row.id = summary_row.drink_record_id
  join public.alcohol_items item_row
    on item_row.id = record_row.alcohol_item_id
  left join public.alcohol_categories category_row
    on category_row.id = item_row.alcohol_category_id
  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id;
$function$;

create or replace function public.soolgyul_convert_anonymous_taste_card(target_user_id uuid, target_result_summary_id uuid, target_anonymous_session_digest text, target_idempotency_key uuid)
 RETURNS TABLE(drink_record_id uuid, result_summary_id uuid, claim_snapshot_id uuid, converted boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  if not found then
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
$function$;

create or replace function public.soolgyul_finalize_taste_card_generation(input_bundle jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  attempt_row public.taste_card_generation_attempts%rowtype;
  request_row jsonb := input_bundle->'request';
  identification_row jsonb := input_bundle->'alcohol_identification';
  rendered_row jsonb := input_bundle->'rendered_view';
  snapshot_row jsonb := input_bundle->'semantic_snapshot';
  answer_row jsonb;
  generated_snapshot_id uuid := gen_random_uuid();
  principal_kind text := input_bundle #>> '{principal,kind}';
  selected_catalog_id uuid;
  resolved_alcohol_item_id uuid;
begin
  if jsonb_typeof(input_bundle) is distinct from 'object'
    or jsonb_typeof(request_row) is distinct from 'object'
    or jsonb_typeof(identification_row) is distinct from 'object'
    or jsonb_typeof(rendered_row) is distinct from 'object'
    or jsonb_typeof(snapshot_row) is distinct from 'object'
  then
    raise exception using
      errcode = '22023',
      message = 'taste card finalization bundle is invalid';
  end if;

  if input_bundle->>'wire_schema_version' is distinct from 'taste-card-result-wire-v3' then
    raise exception using
      errcode = '22023',
      message = 'taste card wire schema version is invalid';
  end if;

  if (
    rendered_row #>> '{metadata,schema_version}' is distinct from '3'
    or rendered_row #>> '{metadata,snapshot_ref}'
      is distinct from input_bundle->>'snapshot_ref'
    or nullif(btrim(coalesce(input_bundle->>'engine_version', '')), '') is null
    or pg_column_size(rendered_row) > 131072
    or pg_column_size(snapshot_row) > 524288
  ) then
    raise exception using
      errcode = '22023',
      message = 'taste card snapshot is invalid';
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

  if identification_row->>'mode' is distinct from 'catalog_match' then
    raise exception using errcode = '22023', message = 'identification mode is invalid';
  end if;

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

  insert into public.drink_records (
    id,
    user_id,
    anonymous_session_id,
    questionnaire_version,
    alcohol_item_id,
    one_line_note,
    idempotency_key
  )
  values (
    attempt_row.reserved_record_id,
    case when principal_kind = 'authenticated' then attempt_row.owner_user_id else null end,
    case when principal_kind = 'anonymous' then request_row->>'anonymous_session_id' else null end,
    request_row->>'questionnaire_version',
    resolved_alcohol_item_id,
    nullif(request_row->>'q7_free_text', ''),
    request_row->>'idempotency_key'
  );

  for answer_row in
    select value
    from jsonb_array_elements(coalesce(request_row->'answers', '[]'::jsonb))
  loop
    insert into public.drink_record_answers (
      drink_record_id,
      question_key,
      selected_option_keys
    )
    values (
      attempt_row.reserved_record_id,
      answer_row->>'question_key',
      array(
        select jsonb_array_elements_text(
          coalesce(answer_row->'selected_option_keys', '[]'::jsonb)
        )
      )
    );
  end loop;

  insert into public.taste_cards (
    id,
    drink_record_id,
    snapshot_id,
    snapshot_ref,
    lifecycle,
    canonical_schema_version,
    semantic_snapshot,
    rendered_snapshot,
    snapshot_created_at
  )
  values (
    attempt_row.reserved_result_summary_id,
    attempt_row.reserved_record_id,
    generated_snapshot_id,
    input_bundle->>'snapshot_ref',
    'final',
    input_bundle->>'engine_version',
    snapshot_row,
    rendered_row,
    now()
  );

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
$function$;

create or replace function public.soolgyul_finalize_withdrawn_account_data(target_user_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare account_row public.users%rowtype; retained_count integer;
begin
  select * into account_row from public.users where id=target_user_id for update;
  if not found then return 0; end if;
  if account_row.purged_at is not null then return 0; end if;
  if account_row.account_status <> 'scheduled_deletion'
    or account_row.deletion_requested_at is null
    or public.soolgyul_deletion_due_at(account_row.deletion_requested_at) > statement_timestamp() then
    raise exception 'account_purge_not_due';
  end if;
  if exists(select 1 from storage.objects where bucket_id='soolgyul-private'
    and starts_with(name,target_user_id::text || '/')) then
    raise exception 'private_storage_cleanup_required';
  end if;

  retained_count := public.soolgyul_retain_drink_records(target_user_id);
  perform public.soolgyul_anonymize_discovery_events(target_user_id);
  update public.users set birth_date=null,gender=null,
    gender_consent_accepted_at=null,gender_consent_version=null,
    display_name=null,age_confirmed_at=null,last_sign_in_at=null,
    purged_at=statement_timestamp(),updated_at=statement_timestamp()
  where id=target_user_id;
  return retained_count;
end;
$function$;

create or replace function public.soolgyul_get_owned_taste_card_result(target_result_summary_id uuid, target_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not public.soolgyul_account_active(target_user_id)
    or not exists (
      select 1
      from public.taste_cards summary_row
      join public.drink_records record_row
        on record_row.id = summary_row.drink_record_id
      where summary_row.id = target_result_summary_id
        and record_row.user_id = target_user_id
    )
  then
    raise exception using errcode = 'P0002', message = 'owned result not found';
  end if;
  return public.soolgyul_build_taste_card_result(target_result_summary_id);
end;
$function$;

create or replace function public.soolgyul_my_drink_history(p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(t.row_json order by t.created_at, t.id), '[]'::jsonb)
  from (
    select c.id, r.created_at,
      jsonb_build_object(
        'result_id', c.id::text,
        'recorded_at', r.created_at,
        'alcohol_item_id', r.alcohol_item_id::text,
        'name', item_row.name_ko,
        'category_key', category_row.category_key,
        'category_label', category_row.name_ko,
        'media_path', media_row.media_path,
        'note', r.one_line_note,
        'summary', c.rendered_snapshot #>> '{bite,summary}',
        'brief', c.rendered_snapshot #>> '{bite,brief}',
        'tags', coalesce((
          select jsonb_agg(jsonb_build_object(
            'label', tag ->> 'label',
            'kind', tag ->> 'kind'
          ))
          from jsonb_array_elements(
            case jsonb_typeof(c.rendered_snapshot #> '{bite,tags}')
              when 'array' then c.rendered_snapshot #> '{bite,tags}'
              else '[]'::jsonb
            end
          ) as tag
          where tag ->> 'label' <> ''
        ), '[]'::jsonb)
      ) as row_json
    from public.drink_records r
    join public.taste_cards c
      on c.drink_record_id = r.id and c.lifecycle = 'final'
    join public.alcohol_items item_row on item_row.id = r.alcohol_item_id
    left join public.alcohol_categories category_row
      on category_row.id = item_row.alcohol_category_id
    left join public.catalog_media_assets media_row
      on media_row.alcohol_item_id = item_row.id
      and item_row.publish_status = 'published'
      and media_row.publish_status = 'published'
      and media_row.published_at is not null
    where r.user_id = auth.uid()
      and public.soolgyul_account_active(auth.uid())
      and r.created_at >= p_from
      and r.created_at < p_to
      and p_to - p_from <= interval '45 days'
  ) t;
$function$;

create or replace function public.soolgyul_my_liked_cards(p_category text DEFAULT NULL::text, p_latest_first boolean DEFAULT true, p_offset integer DEFAULT 0, p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with liked as (
    select
      l.drink_record_id,
      l.created_at as liked_at,
      r.created_at as recorded_at,
      r.one_line_note,
      r.alcohol_item_id,
      item_row.name_ko,
      case when item_row.publish_status = 'published' then item_row.id end as shown_item_id,
      c.id as result_id,
      c.rendered_snapshot #>> '{bite,brief}' as brief,
      c.rendered_snapshot #>> '{bite,summary}' as summary,
      category_row.interest_key
    from public.user_liked_drink_cards l
    join public.drink_records r
      on r.id = l.drink_record_id
      and r.user_id = l.user_id
    join public.alcohol_items item_row on item_row.id = r.alcohol_item_id
    left join public.taste_cards c
      on c.drink_record_id = r.id and c.lifecycle = 'final'
    left join public.alcohol_categories category_row
      on category_row.id = item_row.alcohol_category_id
    where l.user_id = auth.uid()
      and public.soolgyul_account_active(auth.uid())
      and (p_category is null or category_row.interest_key = p_category)
  ),
  page as (
    select liked.*, row_number() over (
      order by
        case when p_latest_first then liked_at end desc,
        case when p_latest_first then drink_record_id end desc,
        liked_at asc,
        drink_record_id asc
    ) as position
    from liked
    order by position
    offset greatest(coalesce(p_offset, 0), 0)
    limit least(greatest(coalesce(p_limit, 30), 0), 50)
  )
  select jsonb_build_object(
    'total', (select count(*) from liked),
    'cards', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'drink_record_id', page.drink_record_id::text,
          'liked_at', page.liked_at,
          'recorded_at', page.recorded_at,
          'note', page.one_line_note,
          'alcohol_item_id', page.alcohol_item_id::text,
          'name', page.name_ko,
          'media_path', media_row.media_path,
          'result_id', page.result_id::text,
          'brief', page.brief,
          'summary', page.summary,
          'interest_key', page.interest_key
        )
        order by page.position
      )
      from page
      left join public.catalog_media_assets media_row
        on media_row.alcohol_item_id = page.shown_item_id
        and media_row.publish_status = 'published'
        and media_row.published_at is not null
    ), '[]'::jsonb)
  );
$function$;

create or replace function public.soolgyul_my_recent_card_guides(p_limit integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(t.row_json order by t.created_at desc, t.id desc), '[]'::jsonb)
  from (
    select c.id, r.created_at,
      jsonb_build_object(
        'result_id', c.id::text,
        'kind_label', coalesce(style_term.label_ko, category_row.name_ko),
        'category_label', category_row.name_ko,
        'guide', c.rendered_snapshot #> '{bite,guide}'
      ) as row_json
    from public.drink_records r
    join public.taste_cards c
      on c.drink_record_id = r.id and c.lifecycle = 'final'
    join public.alcohol_items item_row on item_row.id = r.alcohol_item_id
    left join public.alcohol_categories category_row
      on category_row.id = item_row.alcohol_category_id
    left join public.catalog_taxonomy style_term
      on style_term.term_type = 'style' and style_term.term_key = item_row.style_key
    where r.user_id = auth.uid()
      and public.soolgyul_account_active(auth.uid())
      and jsonb_typeof(c.rendered_snapshot #> '{bite,guide}') = 'object'
    order by r.created_at desc, c.id desc
    limit greatest(1, least(coalesce(p_limit, 3), 10))
  ) t;
$function$;

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
        and event.kind in ('search_pick', 'label_match', 'fit_view')
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

create or replace function public.soolgyul_restore_my_account()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 -- The records and everything else the member made stay as they are.
 return public.soolgyul_get_my_deletion_state();
end; $function$;

create or replace function public.soolgyul_save_taste_letters(target_user_id uuid, state jsonb, changes jsonb, source_record_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if jsonb_typeof(state) is distinct from 'object'
    or jsonb_typeof(state->'axes') is distinct from 'object'
    or jsonb_typeof(changes) is distinct from 'array'
  then
    raise exception using errcode = '22023', message = 'taste letters payload is invalid';
  end if;

  -- One save at a time per account; the card list is read after the wait.
  perform 1 from public.users u where u.id = target_user_id for update;

  if source_record_ids is not null and (
    select coalesce(array_agg(distinct card.drink_record_id order by card.drink_record_id), '{}'::uuid[])
    from public.taste_cards card
    join public.drink_records record_row on record_row.id = card.drink_record_id
    where record_row.user_id = target_user_id
      and card.lifecycle = 'final'
  ) is distinct from (
    select coalesce(array_agg(distinct id order by id), '{}'::uuid[])
    from unnest(source_record_ids) as id
  ) then
    -- Not a serialization-failure code (40001): the API layer would run the
    -- call again on its own, without end, and the answer would never change.
    raise exception using errcode = 'P0001', message = 'taste_letters_stale';
  end if;

  insert into public.taste_letters (user_id, rule_version, record_count, axes, updated_at)
  values (
    target_user_id,
    state->>'rule_version',
    (state->>'record_count')::integer,
    state->'axes',
    now()
  )
  on conflict (user_id) do update
    set rule_version = excluded.rule_version,
        record_count = excluded.record_count,
        axes = excluded.axes,
        updated_at = excluded.updated_at;

  delete from public.taste_letter_changes where user_id = target_user_id;
  insert into public.taste_letter_changes (
    user_id, drink_record_id, axis, from_letter, to_letter,
    left_share, right_share, product_name, changed_at, rule_version
  )
  select
    target_user_id,
    (change->>'record_id')::uuid,
    change->>'axis',
    change->>'from_letter',
    change->>'to_letter',
    (change->>'left_share')::integer,
    (change->>'right_share')::integer,
    change->>'product_name',
    (change->>'changed_at')::timestamptz,
    state->>'rule_version'
  from jsonb_array_elements(changes) as change;
end;
$function$;

create or replace function public.soolgyul_update_my_drink_record_note(p_record_id uuid, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  if char_length(p_note) > 2000 then
    raise exception using errcode = '22023', message = 'note_too_long';
  end if;

  -- Blank clears the note.
  update public.drink_records
    set one_line_note = nullif(btrim(coalesce(p_note, '')), ''),
        updated_at = now()
    where id = p_record_id and user_id = target_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'record_not_found';
  end if;
end
$function$;

create or replace function public.soolgyul_provision_auth_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  resolved_provider text;
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

  -- Members come from Kakao, Apple or Google. An email account becomes one
  -- only when the service marked it as staff: app metadata is written with
  -- the service key alone, never by the person signing up.
  if resolved_provider = 'email'
     and lower(coalesce(new.raw_app_meta_data ->> 'soolgyul_staff', '')) <> 'true'
  then
    return new;
  end if;
  if resolved_provider not in ('kakao', 'apple', 'google', 'test', 'email') then
    return new;
  end if;

  insert into public.users (id, auth_provider, created_at, last_sign_in_at)
  values (
    new.id,
    resolved_provider,
    coalesce(new.created_at, now()),
    new.last_sign_in_at
  )
  on conflict (id) do update
  set auth_provider = excluded.auth_provider,
      last_sign_in_at = excluded.last_sign_in_at;

  return new;
end
$function$;

alter table public.drink_records drop column deleted_at;
alter table public.users
  drop column email,
  drop column provider_user_id,
  drop column profile_created_at;
alter table public.drink_record_answers drop column free_text;
