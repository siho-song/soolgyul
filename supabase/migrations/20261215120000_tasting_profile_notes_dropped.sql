-- A bottle's tasting profile kept four note texts (aroma, palate, finish,
-- texture) beside its tags, and the card read aroma names out of two of them
-- each time it was written. A bottle's aromas are its tags alone now: the
-- names the notes state are added to the tag columns by a catalog job
-- (tools/catalog/note_aromas_to_tags.ts) before this runs, and the note texts
-- are kept outside the database. Nothing reads them after that, so the
-- columns go.
set local lock_timeout = '5s';

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
      old.finish_cleanliness) > 0
    or cardinality(old.aroma_tags || old.palate_tags || old.finish_tags) > 0
  then
    raise exception 'reviewed or populated tasting profile target is immutable; create a replacement profile'
      using errcode = '23514';
  end if;
  return new;
end
$$;

-- A profile that held nothing but notes holds nothing now.
delete from public.alcohol_tasting_profiles
where num_nonnulls(
    sweetness, acidity, bitterness, astringency, body, carbonation,
    aroma_intensity, finish_length, finish_cleanliness) = 0
  and cardinality(aroma_tags || palate_tags || finish_tags) = 0;

alter table public.alcohol_tasting_profiles
  drop constraint alcohol_tasting_profiles_direct_content_check,
  drop column aroma_note,
  drop column palate_note,
  drop column finish_note,
  drop column texture_note;

alter table public.alcohol_tasting_profiles
  add constraint alcohol_tasting_profiles_direct_content_check check (
    num_nonnulls(
      sweetness, acidity, bitterness, astringency, body, carbonation,
      aroma_intensity, finish_length, finish_cleanliness) > 0
    or cardinality(aroma_tags || palate_tags || finish_tags) > 0);
