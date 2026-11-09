-- The 취향 tab's calendar and card list show the owner's saved records of one
-- month, and a tap opens the card. Card bodies are not client-readable, so
-- this owner RPC hands out the card id and the 핵심 요약 tag labels only.

create or replace function public.soolgyul_my_drink_history(
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
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
        'note', r.one_line_note,
        'tags', coalesce((
          select jsonb_agg(tag ->> 'label')
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
    where r.user_id = auth.uid()
      and r.deleted_at is null
      and public.soolgyul_account_active(auth.uid())
      and r.created_at >= p_from
      and r.created_at < p_to
      and p_to - p_from <= interval '45 days'
  ) t;
$$;

revoke execute on function public.soolgyul_my_drink_history(timestamptz, timestamptz) from public;
grant execute on function public.soolgyul_my_drink_history(timestamptz, timestamptz) to authenticated;
