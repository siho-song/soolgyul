-- 2026-11-08: the home's 다음 한 잔 가이드 slide draws the card's guide body,
-- whose picks section is titled by the bottle's category (추천 품종 & 산지 for
-- 와인, 추천 캐스크 & 제조 방식 for 위스키). The RPC now hands out the
-- category name beside the kind name.

create or replace function public.soolgyul_my_recent_card_guides(p_limit integer default 3)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
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
    left join public.catalog_terms style_term
      on style_term.term_type = 'style' and style_term.term_key = item_row.style_key
    where r.user_id = auth.uid()
      and r.deleted_at is null
      and public.soolgyul_account_active(auth.uid())
      and jsonb_typeof(c.rendered_snapshot #> '{bite,guide}') = 'object'
    order by r.created_at desc, c.id desc
    limit greatest(1, least(coalesce(p_limit, 3), 10))
  ) t;
$$;
