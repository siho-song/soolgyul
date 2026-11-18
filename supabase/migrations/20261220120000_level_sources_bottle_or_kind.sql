-- A level's grade now says only whether it was read for the bottle (1) or
-- copied from its kind (4). The maker / outside rating / user votes split
-- (1, 2, 3) is dropped: every sensory level is someone's description turned
-- into a step, so no one of them is more exact than another, and the card
-- and the next quality pass only ask whether the number is the bottle's.
-- 4 keeps its number so functions that test for 4 read old and new rows alike.

update public.alcohol_tasting_profiles p
set level_sources = (
  select jsonb_object_agg(
    e.key,
    case when e.value = '4'::jsonb then '4'::jsonb else '1'::jsonb end
  )
  from jsonb_each(p.level_sources) e
)
where exists (
  select 1 from jsonb_each(p.level_sources) e
  where e.value in ('2'::jsonb, '3'::jsonb)
);

create or replace function public.soolgyul_level_sources_are_valid(sources jsonb)
returns boolean
language sql immutable parallel safe
set search_path to ''
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
        or (entry.grade #>> '{}') not in ('1', '4')
    );
$$;

comment on column public.alcohol_tasting_profiles.level_sources is
  'Per-level origin: 1 read for this bottle, 4 copied from its kind (kind table, style or category median, sibling product, fill). A level column without an entry is unknown. Source names are not kept.';
