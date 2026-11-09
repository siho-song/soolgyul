-- level_sources now stores the grade of each level's evidence instead of the
-- source name: 1 제조사 공식, 2 외부 평가, 3 사용자 평가 모음, 4 종류 추정
-- (docs/specs/SENSORY_LEVEL_SOURCE_GRADES.md). Source names stay in the local
-- working copy. A level whose source was no evidence (a single word read as a
-- level, one blog post) is dropped with its source. The rule rows below are
-- printed by `python3 -m tools.catalog.sensory.level_source_grades --sql`.

alter table public.alcohol_tasting_profiles
  drop constraint alcohol_tasting_profiles_level_sources_check;

create temporary table level_source_grade_rules (prefix text primary key, grade smallint)
  on commit drop;

insert into level_source_grade_rules (prefix, grade) values
('producer', 1),
('producer (quoting Vivino)', 1),
('producer via retailer', 1),
('brewery_site', 1),
('sakenomy_spec', 1),
('name', 1),
('label', 1),
('label_term', 1),
('datagokr', 1),
('prtimes', 1),
('brand', 1),
('wine21_scale', 2),
('wine21_note', 2),
('wine21', 2),
('dailyshot', 2),
('dailyshot_words', 2),
('note', 2),
('note_modifier', 2),
('retailer', 2),
('critic', 2),
('vinmonopolet', 2),
('alko', 2),
('systembolaget', 2),
('saq', 2),
('lcbo', 2),
('importer', 2),
('sdh_note', 2),
('thesool_note', 2),
('thesool', 2),
('thesool_column', 2),
('urbansake', 2),
('tippsy', 2),
('tippsy_note', 2),
('shop_note', 2),
('sbsaq_note', 2),
('beercartel', 2),
('beerhunter', 2),
('twe', 2),
('press', 2),
('trade', 2),
('jetro', 2),
('meininger', 2),
('sieum', 2),
('review', 2),
('brewers_assoc', 2),
('research', 2),
('mottox', 2),
('sakenomy', 3),
('user', 3),
('table', 4),
('style_median', 4),
('category_median', 4),
('same_line', 4),
('fill', 4),
('abv', 4),
('style', 4),
('catalog', 4),
('thesool_ai', 4),
('fashionstore-rule', 4),
('1887', 4),
('3000', 4),
('term_map', null),
('blog', null),
('sakeblog', null);

with graded as (
  select p.id,
    jsonb_object_agg(e.key, coalesce(r.grade, 2)) filter (where r.prefix is null or r.grade is not null) as sources,
    array_agg(e.key) filter (where r.prefix is not null and r.grade is null) as dropped
  from public.alcohol_tasting_profiles p
  cross join lateral jsonb_each_text(p.level_sources) as e(key, value)
  left join level_source_grade_rules r
    on r.prefix = case when e.value like 'user\_%' then 'user' else split_part(e.value, ':', 1) end
  where jsonb_typeof(p.level_sources) = 'object'
  group by p.id
)
update public.alcohol_tasting_profiles p
set level_sources = coalesce(g.sources, '{}'::jsonb),
  sweetness = case when 'sweetness' = any(coalesce(g.dropped, '{}')) then null else p.sweetness end,
  acidity = case when 'acidity' = any(coalesce(g.dropped, '{}')) then null else p.acidity end,
  bitterness = case when 'bitterness' = any(coalesce(g.dropped, '{}')) then null else p.bitterness end,
  astringency = case when 'astringency' = any(coalesce(g.dropped, '{}')) then null else p.astringency end,
  body = case when 'body' = any(coalesce(g.dropped, '{}')) then null else p.body end,
  carbonation = case when 'carbonation' = any(coalesce(g.dropped, '{}')) then null else p.carbonation end,
  aroma_intensity = case when 'aroma_intensity' = any(coalesce(g.dropped, '{}')) then null else p.aroma_intensity end,
  finish_length = case when 'finish_length' = any(coalesce(g.dropped, '{}')) then null else p.finish_length end,
  finish_cleanliness = case when 'finish_cleanliness' = any(coalesce(g.dropped, '{}')) then null else p.finish_cleanliness end
from graded g
where g.id = p.id;

create or replace function public.soolgyul_level_sources_are_valid(sources jsonb)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select jsonb_typeof(sources) = 'object'
    and not exists (
      select 1
      from jsonb_each(sources) as entry(dimension, grade)
      where entry.dimension not in (
          'sweetness', 'acidity', 'bitterness', 'astringency', 'body',
          'carbonation', 'aroma_intensity', 'finish_length',
          'finish_cleanliness')
        or jsonb_typeof(entry.grade) <> 'number'
        or (entry.grade #>> '{}') not in ('1', '2', '3', '4')
    );
$$;

alter table public.alcohol_tasting_profiles
  add constraint alcohol_tasting_profiles_level_sources_check
  check (public.soolgyul_level_sources_are_valid(level_sources));

comment on column public.alcohol_tasting_profiles.level_sources is
  'Per-level evidence grade: 1 the maker''s own statement, 2 an outside rating of this bottle, 3 aggregated user votes or reader answers, 4 a kind-level estimate (table, style or category median, sibling product, fill). A level column without a grade is unknown. Source names are kept only in the local working copy.';
