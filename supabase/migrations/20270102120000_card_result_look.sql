-- A visitor's card carries the colour and texture chosen with the answers on
-- its record's note, but only a member can read a note, and only their own:
-- the visitor's own result screen, and the screen of a card just claimed,
-- had nothing to draw 색 · 점성 from. The card's result, which the server
-- functions read for every card they send, now gives the note's look beside
-- the stored card, and the functions mark it on the note they send. The
-- stored card itself is unchanged, and no grant changes: the function stays
-- service-only.
set local lock_timeout = '5s';

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
    -- Beside the card, not in it: the note is written apart from the card.
    'look', jsonb_strip_nulls(jsonb_build_object(
      'appearance', note_row.appearance,
      'appearance_texture', note_row.appearance_texture
    )),
    'created_at', summary_row.snapshot_created_at
  )
  from public.taste_cards summary_row
  join public.drink_records record_row
    on record_row.id = summary_row.drink_record_id
  join public.alcohol_items item_row
    on item_row.id = record_row.alcohol_item_id
  left join public.alcohol_categories category_row
    on category_row.id = item_row.alcohol_category_id
  left join public.tasting_notes note_row
    on note_row.drink_record_id = record_row.id
  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id;
$function$;
