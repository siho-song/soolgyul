-- 기본 정보 of the 테이스팅 노트 becomes a form the member fills in: when the
-- bottle was bought, with whom and where it was drunk (one line), what was
-- eaten with it, the price and where it was bought. When it was drunk is
-- the record's own date. The member may also rate the drink, half a star
-- to five. The occasion gets columns of its
-- own; a note holding only one of them is still something written. 구입처
-- is now the member's own words rather than one of five places, so its
-- choice check goes (an old key still reads, as the app names it), and the
-- price no longer needs a unit: the form asks only the amount, so the
-- amount-and-unit pair check goes and the unit is left to old rows.
set local lock_timeout = '5s';

alter table public.tasting_notes
  add column companion_place text,
  add column rating numeric(2, 1),
  add column pairing text,
  add column purchased_on date,
  drop constraint tasting_notes_purchase_place_valid,
  drop constraint tasting_notes_purchase_price_pair,
  add constraint tasting_notes_purchase_place_check
    check (purchase_place = btrim(purchase_place)
      and char_length(purchase_place) between 1 and 100),
  add constraint tasting_notes_companion_place_check
    check (companion_place = btrim(companion_place)
      and char_length(companion_place) between 1 and 100),
  -- Half stars: 0.5 to 5 in steps of a half.
  add constraint tasting_notes_rating_check
    check (rating between 0.5 and 5.0 and rating * 2 = floor(rating * 2)),
  add constraint tasting_notes_pairing_check
    check (pairing = btrim(pairing) and char_length(pairing) between 1 and 100),
  drop constraint tasting_notes_not_empty,
  add constraint tasting_notes_not_empty
    check (num_nonnulls(purchase_price_won, purchase_place, appearance,
      appearance_texture, serving, aroma_memo, palate_memo, finish_memo,
      one_line_note, companion_place, pairing, purchased_on, rating) > 0);

-- A record kept without its owner keeps the price as written, unit or not.
alter table public.retained_drink_records
  drop constraint retained_drink_records_purchase_price_pair;

create or replace function public.soolgyul_save_my_tasting_note(p_record_id uuid, p_note jsonb)
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
    'memo', 'pairing', 'companion_place', 'purchased_on', 'rating'];
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
          when 'rating' then 'number'
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
      note_row.purchase_place := nullif(btrim(p_note ->> 'purchase_place'), '');
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
    if p_note ? 'rating' then
      note_row.rating := (p_note ->> 'rating')::numeric;
    end if;
    if p_note ? 'pairing' then
      note_row.pairing := nullif(btrim(p_note ->> 'pairing'), '');
    end if;
    if p_note ? 'companion_place' then
      note_row.companion_place := nullif(btrim(p_note ->> 'companion_place'), '');
    end if;
    if p_note ? 'purchased_on' then
      note_row.purchased_on := (p_note ->> 'purchased_on')::date;
    end if;
    if p_note ? 'memo' then
      note_row.one_line_note := nullif(btrim(p_note ->> 'memo'), '');
    end if;

    if num_nonnulls(note_row.purchase_price_won, note_row.purchase_price_unit,
        note_row.purchase_place, note_row.appearance, note_row.appearance_texture,
        note_row.serving, note_row.aroma_memo, note_row.palate_memo,
        note_row.finish_memo, note_row.one_line_note, note_row.pairing,
        note_row.companion_place, note_row.purchased_on, note_row.rating) = 0 then
      delete from public.tasting_notes where drink_record_id = p_record_id;
      return;
    end if;

    insert into public.tasting_notes as note (
      drink_record_id, purchase_price_won, purchase_price_unit, purchase_place,
      appearance, appearance_texture, serving, aroma_memo, palate_memo,
      finish_memo, one_line_note, pairing, companion_place, purchased_on,
      rating)
    values (
      p_record_id, note_row.purchase_price_won, note_row.purchase_price_unit,
      note_row.purchase_place, note_row.appearance, note_row.appearance_texture,
      note_row.serving, note_row.aroma_memo, note_row.palate_memo,
      note_row.finish_memo, note_row.one_line_note, note_row.pairing,
      note_row.companion_place, note_row.purchased_on, note_row.rating)
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
      pairing = excluded.pairing,
      companion_place = excluded.companion_place,
      purchased_on = excluded.purchased_on,
      rating = excluded.rating,
      updated_at = now();
  exception
    when check_violation or invalid_text_representation
        or numeric_value_out_of_range
        or invalid_datetime_format or datetime_field_overflow then
      raise exception using errcode = '22023', message = 'note_invalid';
  end;
end
$function$;

revoke all on function public.soolgyul_save_my_tasting_note(uuid, jsonb) from public, anon;
grant execute on function public.soolgyul_save_my_tasting_note(uuid, jsonb) to authenticated, service_role;
