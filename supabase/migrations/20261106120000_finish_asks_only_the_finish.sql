-- 2026-11-06: the finish question asks only what the drinking pages cannot:
-- how long the finish ran, whether the mouth cleared, and what came up the
-- nose. The eleven finish options that re-asked a taste or mouthfeel after
-- swallowing (finish:sweet … finish:rich) left the questionnaire, so stored
-- answers and card facts drop them here and the registry can forget them.
-- The card facts stay valid for the reader: the reactions those answers made
-- go, with the findings built on them and the summary entries only they held.

-- 1. Answers: the finish options go, every other answer stays.
update public.drink_record_answers
  set selected_option_keys = (
    select coalesce(array_agg(k order by ord), '{}'::text[])
    from unnest(selected_option_keys) with ordinality as u(k, ord)
    where k not in (
      'finish:sweet', 'finish:cloying', 'finish:fresh', 'finish:sour',
      'finish:bittersweet', 'finish:bitter', 'finish:warm', 'finish:hot',
      'finish:grip', 'finish:drying', 'finish:rich'))
  where selected_option_keys && array[
    'finish:sweet', 'finish:cloying', 'finish:fresh', 'finish:sour',
    'finish:bittersweet', 'finish:bitter', 'finish:warm', 'finish:hot',
    'finish:grip', 'finish:drying', 'finish:rich']::text[];

-- 2. Cards: final cards are immutable by trigger; this is the one edit.
alter table public.taste_cards disable trigger taste_cards_content_immutable;
do $$
declare
  card record;
  facts jsonb;
  gone_refs constant text[] := array[
    'finish:sweet', 'finish:cloying', 'finish:fresh', 'finish:sour',
    'finish:bittersweet', 'finish:bitter', 'finish:warm', 'finish:hot',
    'finish:grip', 'finish:drying', 'finish:rich'];
  gone_rows constant text[] := array[
    'persistence_sweetness', 'persistence_acidity', 'persistence_bitterness',
    'persistence_warmth', 'persistence_drying'];
  gone_ids text[];
  reactions jsonb;
  findings jsonb;
  finding_ids text[];
  kept_subjects jsonb;
  burden_subjects jsonb;
  lingering_subjects jsonb;
  weak_subjects jsonb;
begin
  for card in
    select id, semantic_snapshot from public.taste_cards
    where jsonb_typeof(semantic_snapshot #> '{facts,reactions}') = 'array'
      and exists (
        select 1
        from jsonb_array_elements(semantic_snapshot #> '{facts,reactions}') r,
          jsonb_array_elements_text(r->'answer_refs') a
        where a = any(gone_refs))
  loop
    facts := card.semantic_snapshot->'facts';

    -- The reactions those answers made.
    select coalesce(array_agg(r->>'id'), '{}'::text[]) into gone_ids
    from jsonb_array_elements(facts->'reactions') r
    where exists (
      select 1 from jsonb_array_elements_text(r->'answer_refs') a
      where a = any(gone_refs));
    select coalesce(jsonb_agg(r order by ord), '[]'::jsonb) into reactions
    from jsonb_array_elements(facts->'reactions') with ordinality as t(r, ord)
    where not (r->>'id' = any(gone_ids));

    -- Findings built on them, or on rows the engine no longer has.
    select coalesce(jsonb_agg(f order by ord), '[]'::jsonb) into findings
    from jsonb_array_elements(facts->'findings') with ordinality as t(f, ord)
    where not (f->>'row' = any(gone_rows))
      and not exists (
        select 1 from jsonb_array_elements_text(f->'reactions') x
        where x = any(gone_ids));
    select coalesce(array_agg(f->>'id'), '{}'::text[]) into finding_ids
    from jsonb_array_elements(findings) f;

    -- Subjects the remaining reactions still speak for.
    select coalesce(jsonb_agg(r->'subject'), '[]'::jsonb) into kept_subjects
    from jsonb_array_elements(reactions) r
    where r->>'reaction' in ('liked', 'fine');
    select coalesce(jsonb_agg(r->'subject'), '[]'::jsonb) into burden_subjects
    from jsonb_array_elements(reactions) r where r->>'reaction' = 'burden';
    select coalesce(jsonb_agg(r->'subject'), '[]'::jsonb) into lingering_subjects
    from jsonb_array_elements(reactions) r where r->>'qualifier' = 'lingering';
    select coalesce(jsonb_agg(r->'subject'), '[]'::jsonb) into weak_subjects
    from jsonb_array_elements(reactions) r
    where r->>'reaction' = 'burden'
      and r->>'qualifier' in ('too_weak', 'too_brief');

    facts := jsonb_set(facts, '{reactions}', reactions);
    facts := jsonb_set(facts, '{findings}', findings);
    facts := jsonb_set(facts, '{sections,positive}', coalesce((
      select jsonb_agg(x order by ord)
      from jsonb_array_elements_text(facts #> '{sections,positive}')
        with ordinality as t(x, ord)
      where x = any(finding_ids)), '[]'::jsonb));
    facts := jsonb_set(facts, '{sections,burden}', coalesce((
      select jsonb_agg(x order by ord)
      from jsonb_array_elements_text(facts #> '{sections,burden}')
        with ordinality as t(x, ord)
      where x = any(finding_ids)), '[]'::jsonb));
    facts := jsonb_set(facts, '{summary,preference}', coalesce((
      select jsonb_agg(x order by ord)
      from jsonb_array_elements_text(facts #> '{summary,preference}')
        with ordinality as t(x, ord)
      where x = any(finding_ids)), '[]'::jsonb));
    facts := jsonb_set(facts, '{summary,next_choice,keep}', coalesce((
      select jsonb_agg(s order by ord)
      from jsonb_array_elements(facts #> '{summary,next_choice,keep}')
        with ordinality as t(s, ord)
      where kept_subjects @> jsonb_build_array(s)), '[]'::jsonb));
    -- An adjustment stays while a burden of its subject remains; "shorter"
    -- came from the lingering answer, so without one the direction is the
    -- engine's other rule: higher for 너무 약했어요, softer for bubbles and
    -- warmth, lower otherwise (card_conclusions.ts).
    facts := jsonb_set(facts, '{summary,next_choice,adjust}', coalesce((
      select jsonb_agg(
        case
          when a->>'direction' = 'shorter'
            and not lingering_subjects @> jsonb_build_array(a->'subject')
          then a || jsonb_build_object('direction',
            case
              when weak_subjects @> jsonb_build_array(a->'subject') then 'higher'
              when a #>> '{subject,key}' in ('bubbles', 'warmth') then 'softer'
              else 'lower'
            end)
          else a
        end order by ord)
      from jsonb_array_elements(facts #> '{summary,next_choice,adjust}')
        with ordinality as t(a, ord)
      where burden_subjects @> jsonb_build_array(a->'subject')), '[]'::jsonb));
    -- A finish-only nickname named one of the finishes that left; without a
    -- liked answer the selector falls back on the burden or neutral name.
    if facts->>'nickname' in (
      '스위티 피니쉬 러버', '시트러스 피니쉬 러버', '쌉쌀한 피니쉬 러버',
      '웜 피니쉬 러버', '드라이 피니쉬 러버', '리치 피니쉬 러버')
    then
      facts := jsonb_set(facts, '{nickname}', to_jsonb(
        case when jsonb_array_length(burden_subjects) > 0
          then '취향 유랑자' else '취향 탐색자' end));
    end if;

    update public.taste_cards
      set semantic_snapshot = jsonb_set(semantic_snapshot, '{facts}', facts)
      where id = card.id;
  end loop;
end $$;
alter table public.taste_cards enable trigger taste_cards_content_immutable;

-- 3. Retained records of withdrawn accounts keep their answers as JSON.
update public.withdrawn_drink_records
  set record_data = jsonb_set(record_data, '{answers}', coalesce((
    select jsonb_agg(
      case
        when exists (
          select 1 from jsonb_array_elements_text(a->'selected_option_keys') k
          where k in (
            'finish:sweet', 'finish:cloying', 'finish:fresh', 'finish:sour',
            'finish:bittersweet', 'finish:bitter', 'finish:warm', 'finish:hot',
            'finish:grip', 'finish:drying', 'finish:rich'))
        then a || jsonb_build_object('selected_option_keys', coalesce((
          select jsonb_agg(k order by o)
          from jsonb_array_elements_text(a->'selected_option_keys') with ordinality as s(k, o)
          where k not in (
            'finish:sweet', 'finish:cloying', 'finish:fresh', 'finish:sour',
            'finish:bittersweet', 'finish:bitter', 'finish:warm', 'finish:hot',
            'finish:grip', 'finish:drying', 'finish:rich')), '[]'::jsonb))
        else a
      end
      order by ord)
    from jsonb_array_elements(record_data->'answers') with ordinality as t(a, ord)), '[]'::jsonb))
  where jsonb_typeof(record_data->'answers') = 'array'
    and (record_data->'answers')::text ~ '"finish:(sweet|cloying|fresh|sour|bittersweet|bitter|warm|hot|grip|drying|rich)"';
