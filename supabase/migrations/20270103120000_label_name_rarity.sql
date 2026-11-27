-- The word search hands back, with each drink, how rare every word of its
-- names is. Working that out again for the three hundred drinks of every
-- answer took most of the search's time, and it changes only when a name or
-- the word list does: it is now kept beside the word list and made again
-- with it every night. The search answers with the same rows as before.

-- How rare each word of a drink's two names is; a word the list does not
-- hold has no rarity.
create function public.soolgyul_label_name_rarity(name_en text, name_ko text)
returns jsonb
language sql stable
set search_path to ''
as $$
  select pg_catalog.jsonb_object_agg(word.value, vocabulary.rarity)
  from pg_catalog.unnest(
    public.soolgyul_label_name_words(name_en) || public.soolgyul_label_name_words(name_ko)
  ) as word(value)
  left join public.catalog_label_words as vocabulary on vocabulary.word = word.value
$$;
revoke all on function public.soolgyul_label_name_rarity(text, text) from public, anon, authenticated;

create materialized view public.catalog_label_name_rarity as
select item.id as alcohol_item_id,
  public.soolgyul_label_name_rarity(item.name_en, item.name_ko) as name_rarity
from public.alcohol_items as item
where item.publish_status = 'published';
create unique index catalog_label_name_rarity_item_idx
  on public.catalog_label_name_rarity (alcohol_item_id);
revoke all on public.catalog_label_name_rarity from public, anon, authenticated;

-- The word list first: the rarities are read from it.
create or replace function public.soolgyul_refresh_label_words()
returns void
language plpgsql security definer
set search_path to ''
as $$
begin
  refresh materialized view public.catalog_label_words;
  refresh materialized view public.catalog_label_name_rarity;
end
$$;

create or replace function public.soolgyul_search_alcohol_catalog_by_label_words(
  target_words text[],
  also_ids uuid[] default '{}',
  target_limit integer default 300
) returns table(
  id uuid, name_ko text, name_en text, category_key text,
  style_key text, style_label text, abv_percent numeric, media_path text,
  country_code text, region text, label_facts jsonb, name_rarity jsonb, found double precision
)
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public'
as $$
#variable_conflict use_column
begin
  perform set_config('pg_trgm.similarity_threshold', '0.4', true);
  return query
    with read as (
      select distinct folded.word
      from unnest(target_words[1:120]) as asked(value)
      cross join lateral unnest(string_to_array(public.soolgyul_label_fold(asked.value), ' ')) as folded(word)
      where char_length(folded.word) >= 3 and folded.word !~ '^\d+$'
    ),
    word_found as (
      select vocabulary.word, vocabulary.rarity, vocabulary.drinks,
        max(extensions.similarity(vocabulary.word, read.word)) as likeness
      from read
      join public.catalog_label_words as vocabulary
        on vocabulary.rarity >= 3.2 and vocabulary.word operator(extensions.%) read.word
      group by vocabulary.word, vocabulary.rarity, vocabulary.drinks
    ),
    drink_found as (
      select drink.id, sum(word_found.rarity * word_found.likeness) as found
      from word_found
      cross join lateral unnest(word_found.drinks) as drink(id)
      group by drink.id
    ),
    picked as (
      (
        select drink_found.id, drink_found.found from drink_found
        order by drink_found.found desc, drink_found.id
        limit greatest(1, least(coalesce(target_limit, 300), 300))
      )
      union
      select also.id, coalesce(drink_found.found, 0)
      from unnest(also_ids[1:40]) as also(id)
      left join drink_found on drink_found.id = also.id
    )
    select item.id, item.name_ko, item.name_en, category.category_key,
      item.style_key, coalesce(style_term.label_ko, category.name_ko), item.abv_percent,
      (
        select media.media_path
        from public.catalog_media_assets as media
        where media.alcohol_item_id = item.id
          and media.publish_status = 'published'
          and media.published_at is not null
      ),
      item.country_code, region_term.label_ko,
      public.soolgyul_catalog_label_facts(item.id),
      -- A drink listed since the night's making is worked out here.
      coalesce(kept.name_rarity, public.soolgyul_label_name_rarity(item.name_en, item.name_ko)),
      picked.found
    from picked
    join public.alcohol_items as item on item.id = picked.id and item.publish_status = 'published'
    join public.alcohol_categories as category on category.id = item.alcohol_category_id and category.is_active
    left join public.catalog_label_name_rarity as kept on kept.alcohol_item_id = item.id
    left join public.catalog_taxonomy as style_term
      on style_term.term_type = 'style' and style_term.term_key = item.style_key and style_term.is_active
    left join public.catalog_taxonomy as region_term
      on region_term.term_type = 'region' and region_term.term_key = item.region_key
    order by picked.found desc, item.id;
end
$$;
