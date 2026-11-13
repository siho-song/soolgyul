-- 구입 가격: a member notes what a bottle or a glass cost on a record, from
-- its card, after the record exists. Unlike the memo it is not the reader's
-- own words, so a record kept without its owner keeps the price with it.
set local lock_timeout = '5s';

alter table public.drink_records
  add column purchase_price_won integer,
  add column purchase_price_unit text,
  add constraint drink_records_purchase_price_won_range
    check (purchase_price_won between 1 and 10000000),
  add constraint drink_records_purchase_price_unit_valid
    check (purchase_price_unit in ('bottle', 'glass')),
  add constraint drink_records_purchase_price_pair
    check ((purchase_price_won is null) = (purchase_price_unit is null));

alter table public.retained_drink_records
  add column purchase_price_won integer,
  add column purchase_price_unit text,
  add constraint retained_drink_records_purchase_price_won_range
    check (purchase_price_won between 1 and 10000000),
  add constraint retained_drink_records_purchase_price_unit_valid
    check (purchase_price_unit in ('bottle', 'glass')),
  add constraint retained_drink_records_purchase_price_pair
    check ((purchase_price_won is null) = (purchase_price_unit is null));

comment on table public.retained_drink_records is
  'A record kept without its owner once a member deletes a card or an account is deleted: five-year birth band, consented gender, product, chosen answers, card text and purchase price. No memo, no account or record id; no client reads.';

create or replace function public.soolgyul_update_my_drink_record_price(p_record_id uuid, p_amount integer, p_unit text)
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

  if p_amount is not null and (p_amount < 1 or p_amount > 10000000) then
    raise exception using errcode = '22023', message = 'price_amount_invalid';
  end if;
  if p_amount is not null and (p_unit is null or p_unit not in ('bottle', 'glass')) then
    raise exception using errcode = '22023', message = 'price_unit_invalid';
  end if;

  -- No amount clears the price, unit and all.
  update public.drink_records
    set purchase_price_won = p_amount,
        purchase_price_unit = case when p_amount is null then null else p_unit end,
        updated_at = now()
    where id = p_record_id and user_id = target_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'record_not_found';
  end if;
end
$function$;

revoke all on function public.soolgyul_update_my_drink_record_price(uuid, integer, text) from public, anon;
grant execute on function public.soolgyul_update_my_drink_record_price(uuid, integer, text) to authenticated, service_role;

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
        'note', r.one_line_note,
        'price_won', r.purchase_price_won,
        'price_unit', r.purchase_price_unit,
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
    r.purchase_price_won,
    r.purchase_price_unit
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
