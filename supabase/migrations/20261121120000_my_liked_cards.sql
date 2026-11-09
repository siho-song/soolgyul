-- The 저장한 술결 카드 screen lists the owner's liked cards with the catalog
-- name and interest key. Clients cannot read alcohol_items directly, so this
-- owner RPC joins the catalog for them: one page at a time plus the total.

create or replace function public.soolgyul_my_liked_cards(
  p_category text default null,
  p_latest_first boolean default true,
  p_offset integer default 0,
  p_limit integer default 30
)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  with liked as (
    select
      l.drink_record_id,
      l.created_at as liked_at,
      r.created_at as recorded_at,
      r.one_line_note,
      r.alcohol_item_id,
      item_row.name_ko,
      category_row.interest_key
    from public.user_liked_drink_cards l
    join public.drink_records r
      on r.id = l.drink_record_id
      and r.user_id = l.user_id
      and r.deleted_at is null
    join public.alcohol_items item_row on item_row.id = r.alcohol_item_id
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
          'interest_key', page.interest_key
        )
        order by page.position
      )
      from page
    ), '[]'::jsonb)
  );
$$;

revoke execute on function public.soolgyul_my_liked_cards(text, boolean, integer, integer) from public;
grant execute on function public.soolgyul_my_liked_cards(text, boolean, integer, integer) to authenticated;
