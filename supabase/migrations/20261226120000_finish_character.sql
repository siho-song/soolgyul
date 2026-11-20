-- 끝맛의 인상 is asked from clean (1) to rich (5). The catalog held it the
-- other way round, as how clean the finish is (5 the cleanest), and so did
-- the dictionary, so the card engine turned every answer over before it
-- compared the two. The column now holds what the question asks: it takes the
-- question's name (finish_character) and its direction. Every stored value is
-- turned (n → 6 − n); its level_sources entry is renamed and keeps its grade.
-- The functions that read the column by its old name ship with this file.
set local lock_timeout = '5s';

alter table public.alcohol_tasting_profiles
  rename column finish_cleanliness to finish_character;

comment on column public.alcohol_tasting_profiles.finish_character is
  '끝맛의 인상, on the scale it is asked on: 1 clean … 5 rich.';

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
          'finish_character')
        or jsonb_typeof(entry.grade) <> 'number'
        or (entry.grade #>> '{}') not in ('1', '4')
    );
$$;

update public.alcohol_tasting_profiles
set
  finish_character = 6 - finish_character,
  level_sources = case
    when level_sources ? 'finish_cleanliness' then
      (level_sources - 'finish_cleanliness')
        || jsonb_build_object(
          'finish_character', level_sources -> 'finish_cleanliness')
    else level_sources
  end
where finish_character is not null
  or level_sources ? 'finish_cleanliness';

create or replace function public.soolgyul_prevent_populated_tasting_profile_retargeting() returns trigger
    language plpgsql security definer
    set search_path to ''
    as $$
begin
  if new.alcohol_item_id is not distinct from old.alcohol_item_id then
    return new;
  end if;
  if num_nonnulls(
      old.sweetness, old.acidity, old.bitterness, old.astringency, old.body,
      old.carbonation, old.aroma_intensity, old.finish_length,
      old.finish_character) > 0
    or cardinality(old.aroma_tags || old.palate_tags || old.finish_tags) > 0
  then
    raise exception 'reviewed or populated tasting profile target is immutable; create a replacement profile'
      using errcode = '23514';
  end if;
  return new;
end
$$;
