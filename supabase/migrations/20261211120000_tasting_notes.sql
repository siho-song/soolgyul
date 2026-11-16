-- 테이스팅 노트: what a member writes on a record beyond the questionnaire,
-- from the card's 테이스팅 노트 tab: the memo, what the drink cost and where
-- it was bought, how it looked, how it was served, a line on the aroma. One
-- row per record, and only for a record that has something written. The memo
-- and the purchase price move here from drink_records, so a record's own row
-- is its answers and everything the member writes about it sits in one place.
-- An app built before this reads the memo on the record: it must be updated
-- before this runs where such apps are in use.
set local lock_timeout = '5s';

create table public.tasting_notes (
  drink_record_id uuid not null
    references public.drink_records (id) on delete cascade,
  purchase_price_won integer,
  purchase_price_unit text,
  purchase_place text,
  -- The option the member chose among those the card offered for its kind of
  -- drink (a red wine's 석류석빛, a 탁주's 탁도, a whisky's 니트): the options are
  -- the card's. One glass may be drunk several ways, so serving holds each.
  appearance text,
  appearance_texture text,
  serving text[],
  aroma_memo text,
  palate_memo text,
  finish_memo text,
  one_line_note text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint tasting_notes_pkey primary key (drink_record_id),
  constraint tasting_notes_purchase_price_won_range
    check (purchase_price_won between 1 and 10000000),
  constraint tasting_notes_purchase_price_unit_valid
    check (purchase_price_unit in ('bottle', 'glass')),
  constraint tasting_notes_purchase_price_pair
    check ((purchase_price_won is null) = (purchase_price_unit is null)),
  constraint tasting_notes_purchase_place_valid
    check (purchase_place in (
      'convenience_mart', 'smart_order_shop', 'restaurant_pub', 'bar',
      'duty_free_abroad')),
  constraint tasting_notes_option_keys_check
    check (
      coalesce(appearance, 'a') ~ '^[a-z][a-z0-9_]{0,39}$'
      and coalesce(appearance_texture, 'a') ~ '^[a-z][a-z0-9_]{0,39}$'
      and (serving is null or (
        cardinality(serving) between 1 and 8
        and array_to_string(serving, ',', '')
          ~ '^[a-z][a-z0-9_]{0,39}(,[a-z][a-z0-9_]{0,39}){0,7}$'))),
  constraint tasting_notes_aroma_memo_check
    check (aroma_memo = btrim(aroma_memo) and length(aroma_memo) between 1 and 200),
  constraint tasting_notes_palate_memo_check
    check (palate_memo = btrim(palate_memo) and length(palate_memo) between 1 and 200),
  constraint tasting_notes_finish_memo_check
    check (finish_memo = btrim(finish_memo) and length(finish_memo) between 1 and 200),
  constraint tasting_notes_one_line_note_check
    check (btrim(one_line_note) <> '' and char_length(one_line_note) <= 2000),
  constraint tasting_notes_not_empty
    check (num_nonnulls(purchase_price_won, purchase_place, appearance,
      appearance_texture, serving, aroma_memo, palate_memo, finish_memo,
      one_line_note) > 0)
);

comment on table public.tasting_notes is
  'What a member writes on a drink record: the memo, purchase price and place, appearance, serving, a line on the aroma. One row per record; owner reads, writes through one RPC.';

alter table public.tasting_notes enable row level security;

revoke all on table public.tasting_notes from public, anon, authenticated;
grant select on table public.tasting_notes to authenticated;
grant all on table public.tasting_notes to service_role;

create policy tasting_notes_owner_select on public.tasting_notes
  for select to authenticated using (
    exists (
      select 1 from public.drink_records r
      where r.id = drink_record_id
        and r.user_id = (select auth.uid())
    )
    and (select public.soolgyul_account_active((select auth.uid())))
  );

insert into public.tasting_notes (
  drink_record_id, purchase_price_won, purchase_price_unit, one_line_note,
  created_at, updated_at)
select id, purchase_price_won, purchase_price_unit,
  case when btrim(one_line_note) <> '' then one_line_note end,
  updated_at, updated_at
from public.drink_records
where purchase_price_won is not null or btrim(one_line_note) <> '';

drop function public.soolgyul_update_my_drink_record_price(uuid, integer, text);
drop function public.soolgyul_update_my_drink_record_note(uuid, text);

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
    idempotency_key
  )
  values (
    attempt_row.reserved_record_id,
    case when principal_kind = 'authenticated' then attempt_row.owner_user_id else null end,
    case when principal_kind = 'anonymous' then request_row->>'anonymous_session_id' else null end,
    request_row->>'questionnaire_version',
    resolved_alcohol_item_id,
    request_row->>'idempotency_key'
  );

  -- The memo written with the answers is the record's first note.
  insert into public.tasting_notes (drink_record_id, one_line_note)
  select attempt_row.reserved_record_id, request_row->>'q7_free_text'
  where btrim(coalesce(request_row->>'q7_free_text', '')) <> '';

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

alter table public.drink_records
  drop column purchase_price_won,
  drop column purchase_price_unit,
  drop column one_line_note;

-- Only the fields named in p_note change; a null clears one. A note left
-- with nothing is no row.
create function public.soolgyul_save_my_tasting_note(p_record_id uuid, p_note jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  target_user_id uuid := auth.uid();
  fields constant text[] := array[
    'price_won', 'price_unit', 'purchase_place', 'appearance',
    'appearance_texture', 'serving', 'aroma_memo', 'palate_memo', 'finish_memo',
    'memo'];
  note_row public.tasting_notes%rowtype;
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
  if p_note is null or jsonb_typeof(p_note) <> 'object' or exists (
    select 1 from jsonb_each(p_note) field
    where field.key <> all (fields)
      or jsonb_typeof(field.value) not in (
        'null', case field.key
          when 'price_won' then 'number'
          when 'serving' then 'array'
          else 'string' end)
  ) then
    raise exception using errcode = '22023', message = 'note_invalid';
  end if;

  perform 1 from public.drink_records
    where id = p_record_id and user_id = target_user_id
    for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'record_not_found';
  end if;

  select * into note_row from public.tasting_notes
    where drink_record_id = p_record_id;
  begin
    if p_note ? 'price_won' then
      note_row.purchase_price_won := (p_note ->> 'price_won')::integer;
    end if;
    if p_note ? 'price_unit' then
      note_row.purchase_price_unit := p_note ->> 'price_unit';
    end if;
    if p_note ? 'purchase_place' then
      note_row.purchase_place := p_note ->> 'purchase_place';
    end if;
    if p_note ? 'appearance' then
      note_row.appearance := p_note ->> 'appearance';
    end if;
    if p_note ? 'appearance_texture' then
      note_row.appearance_texture := p_note ->> 'appearance_texture';
    end if;
    if p_note ? 'serving' then
      -- Each way once, in the order sent; none clears the field.
      note_row.serving := (
        select array_agg(way.key order by way.first_at)
        from (
          select way.key, min(way.at) as first_at
          from jsonb_array_elements_text(
            case jsonb_typeof(p_note -> 'serving')
              when 'array' then p_note -> 'serving' else '[]'::jsonb end
          ) with ordinality as way(key, at)
          group by way.key
        ) way);
    end if;
    if p_note ? 'aroma_memo' then
      note_row.aroma_memo := nullif(btrim(p_note ->> 'aroma_memo'), '');
    end if;
    if p_note ? 'palate_memo' then
      note_row.palate_memo := nullif(btrim(p_note ->> 'palate_memo'), '');
    end if;
    if p_note ? 'finish_memo' then
      note_row.finish_memo := nullif(btrim(p_note ->> 'finish_memo'), '');
    end if;
    if p_note ? 'memo' then
      note_row.one_line_note := nullif(btrim(p_note ->> 'memo'), '');
    end if;

    if num_nonnulls(note_row.purchase_price_won, note_row.purchase_price_unit,
        note_row.purchase_place, note_row.appearance, note_row.appearance_texture,
        note_row.serving, note_row.aroma_memo, note_row.palate_memo,
        note_row.finish_memo, note_row.one_line_note) = 0 then
      delete from public.tasting_notes where drink_record_id = p_record_id;
      return;
    end if;

    insert into public.tasting_notes as note (
      drink_record_id, purchase_price_won, purchase_price_unit, purchase_place,
      appearance, appearance_texture, serving, aroma_memo, palate_memo,
      finish_memo, one_line_note)
    values (
      p_record_id, note_row.purchase_price_won, note_row.purchase_price_unit,
      note_row.purchase_place, note_row.appearance, note_row.appearance_texture,
      note_row.serving, note_row.aroma_memo, note_row.palate_memo,
      note_row.finish_memo, note_row.one_line_note)
    on conflict (drink_record_id) do update set
      purchase_price_won = excluded.purchase_price_won,
      purchase_price_unit = excluded.purchase_price_unit,
      purchase_place = excluded.purchase_place,
      appearance = excluded.appearance,
      appearance_texture = excluded.appearance_texture,
      serving = excluded.serving,
      aroma_memo = excluded.aroma_memo,
      palate_memo = excluded.palate_memo,
      finish_memo = excluded.finish_memo,
      one_line_note = excluded.one_line_note,
      updated_at = now();
  exception
    when check_violation or invalid_text_representation
        or numeric_value_out_of_range then
      raise exception using errcode = '22023', message = 'note_invalid';
  end;
end
$function$;

revoke all on function public.soolgyul_save_my_tasting_note(uuid, jsonb) from public, anon;
grant execute on function public.soolgyul_save_my_tasting_note(uuid, jsonb) to authenticated, service_role;

-- The 취향 tab's record card shows the price under the date.
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
        'note', note_row.one_line_note,
        'price_won', note_row.purchase_price_won,
        'price_unit', note_row.purchase_price_unit,
        'purchase_place', note_row.purchase_place,
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
    left join public.tasting_notes note_row on note_row.drink_record_id = r.id
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

-- 좋아요한 카드: the memo is read from the note.
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
      note_row.one_line_note,
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
    left join public.tasting_notes note_row on note_row.drink_record_id = r.id
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

-- A record kept without its owner keeps the price, as before; nothing else
-- of the note goes with it.
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
  -- no names, account metadata or raw snapshots. The price goes with it.
  birth := extract(year from account_row.birth_date)::integer;
  insert into public.retained_drink_records(
    birth_year_band,gender,record_data,purchase_price_won,purchase_price_unit)
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
    ),
    n.purchase_price_won,
    n.purchase_price_unit
  from public.drink_records r
  left join public.tasting_notes n on n.drink_record_id=r.id
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
