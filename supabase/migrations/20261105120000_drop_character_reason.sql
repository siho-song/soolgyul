-- 2026-11-05: the "character" reason (맛 자체가 좋았어요 · 취향이 아니었어요) left
-- every aroma and taste question. The card never read it beyond what the bare
-- reaction already says, and chosen together with another reason it hid that
-- one. Stored answers and card facts drop it here so the questionnaire
-- registry can forget the option too; the reaction it explained stays.

-- 1. Answers: the reason options go, the reaction they explained stays.
update public.drink_record_answers
  set selected_option_keys = (
    select coalesce(array_agg(k order by ord), '{}'::text[])
    from unnest(selected_option_keys) with ordinality as u(k, ord)
    where k not like 'reason:%:character')
  where exists (
    select 1 from unnest(selected_option_keys) k
    where k like 'reason:%:character');

-- 2. Cards: the reaction fact loses the qualifier, the explained flag and the
--    answer ref. Final cards are immutable by trigger; this is the one edit.
alter table public.taste_cards disable trigger taste_cards_content_immutable;
update public.taste_cards
  set semantic_snapshot = jsonb_set(semantic_snapshot, '{facts,reactions}', coalesce((
    select jsonb_agg(
      case
        when r->>'qualifier' = 'character' or exists (
          select 1 from jsonb_array_elements_text(r->'answer_refs') a
          where a like 'reason:%:character')
        then r
          || jsonb_build_object('answer_refs', coalesce((
               select jsonb_agg(a)
               from jsonb_array_elements_text(r->'answer_refs') with ordinality as s(a, o)
               where a not like 'reason:%:character'), '[]'::jsonb))
          -- The qualifier the engine now derives: the first remaining reason in
          -- card_reading.ts order (pronounced, gentle, harmonious, excessive,
          -- too_weak, masking); none when no reason remains.
          || jsonb_build_object('qualifier',
               case when r->>'qualifier' <> 'character' then r->'qualifier' else (
                 select to_jsonb(q.qualifier)
                 from (values
                   ('pronounced', 'pronounced', 1), ('gentle', 'gentle', 2),
                   ('harmony', 'harmonious', 3), ('too_strong', 'excessive', 4),
                   ('too_weak', 'too_weak', 5), ('disharmony', 'masking', 6)
                 ) as q(code, qualifier, rank)
                 where exists (
                   select 1 from jsonb_array_elements_text(r->'answer_refs') a
                   where a like 'reason:%:' || q.code)
                 order by q.rank limit 1) end)
          || jsonb_build_object('focus', exists (
               select 1 from jsonb_array_elements_text(r->'answer_refs') a
               where a like 'reason:%' and a not like 'reason:%:character'))
        else r
      end
      order by ord)
    from jsonb_array_elements(semantic_snapshot #> '{facts,reactions}')
      with ordinality as t(r, ord)), '[]'::jsonb))
  where jsonb_typeof(semantic_snapshot #> '{facts,reactions}') = 'array'
    and (semantic_snapshot #> '{facts,reactions}')::text like '%character%';
alter table public.taste_cards enable trigger taste_cards_content_immutable;

-- 3. Retained records of withdrawn accounts keep their answers as JSON.
update public.withdrawn_drink_records
  set record_data = jsonb_set(record_data, '{answers}', coalesce((
    select jsonb_agg(
      case
        when exists (
          select 1 from jsonb_array_elements_text(a->'selected_option_keys') k
          where k like 'reason:%:character')
        then a || jsonb_build_object('selected_option_keys', coalesce((
          select jsonb_agg(k)
          from jsonb_array_elements_text(a->'selected_option_keys') with ordinality as s(k, o)
          where k not like 'reason:%:character'), '[]'::jsonb))
        else a
      end
      order by ord)
    from jsonb_array_elements(record_data->'answers') with ordinality as t(a, ord)), '[]'::jsonb))
  where jsonb_typeof(record_data->'answers') = 'array'
    and (record_data->'answers')::text like '%:character"%';
