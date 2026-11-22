-- A label photo reads words, often a few letters off ("GLENGRANT",
-- "CAYMU5"), and the label search's line queries find the drink only when
-- a line holds most of its name. The app now ranks the drinks itself from
-- everything the label shows of each, and asks the catalog only for the
-- drinks one of whose name words looks like a word read: each read word
-- finds the name words that share enough three-letter pieces with it, the
-- rarer a word the more it counts, and the drinks holding the most come
-- back with what the app weighs them by (their facts, and how rare each
-- word of their names is).

-- A text as the label match compares it: lower case, accents and voicing
-- marks off, apostrophes dropped ("d'arche" is "darche"), anything but
-- letters and digits a space. The app folds read words the same way.
create function public.soolgyul_label_fold(input_text text)
returns text
language sql immutable parallel safe
set search_path to ''
as $$
  select pg_catalog.btrim(pg_catalog.regexp_replace(
    pg_catalog.replace(pg_catalog.replace(pg_catalog.lower(pg_catalog.normalize(
      pg_catalog.regexp_replace(
        pg_catalog.normalize(coalesce(input_text, ''), 'NFKD'),
        '[̀-ͯ᪰-᫿᷀-᷿⃐-⃿︠-゙゚︯]', '', 'g'
      ), 'NFC')), U&'\2019', ''), '''', ''),
    '[^0-9a-z぀-ヿ㐀-鿿가-힣]+', ' ', 'g'
  ))
$$;
revoke all on function public.soolgyul_label_fold(text) from public, anon, authenticated;

-- The words of a name, its year left off ("... 2019" is the same drink).
create function public.soolgyul_label_name_words(input_name text)
returns text[]
language sql immutable parallel safe
set search_path to ''
as $$
  select coalesce(pg_catalog.array_remove(pg_catalog.string_to_array(
    public.soolgyul_label_fold(pg_catalog.regexp_replace(coalesce(input_name, ''), '\s+(?:19|20)\d\d$', '')), ' '
  ), ''), '{}')
$$;
revoke all on function public.soolgyul_label_name_words(text) from public, anon, authenticated;

-- Each word of each listed drink's Korean and Latin name, and each two
-- neighbouring words written as one ("glen grant" as "glengrant"), with
-- the drinks that hold it and how much reading it says: ln(listed drinks /
-- drinks whose name holds it as a word), the most a word can say for a
-- joined pair no name holds as one word.
create materialized view public.catalog_label_words as
with listed as (
  select item.id,
    public.soolgyul_label_name_words(item.name_en) as en,
    public.soolgyul_label_name_words(item.name_ko) as ko
  from public.alcohol_items as item
  join public.alcohol_categories as category
    on category.id = item.alcohol_category_id and category.is_active
  where item.publish_status = 'published'
),
side as (
  select id, en as words from listed
  union all
  select id, ko from listed
),
posting as (
  select distinct word.value as word, side.id, word.single
  from side
  cross join lateral (
    select side.words[place] as value, true as single
    from pg_catalog.generate_subscripts(side.words, 1) as place
    union all
    select side.words[place] || side.words[place + 1], false
    from pg_catalog.generate_subscripts(side.words, 1) as place
    where place < pg_catalog.cardinality(side.words)
  ) as word
),
total as (
  select count(*)::double precision as drinks from listed
)
select posting.word,
  pg_catalog.ln(total.drinks / greatest(1, count(*) filter (where posting.single))) as rarity,
  pg_catalog.array_agg(distinct posting.id) as drinks
from posting
cross join total
group by posting.word, total.drinks;
create unique index catalog_label_words_word_idx on public.catalog_label_words (word);
-- Only a word fewer than one drink in about 25 holds picks candidates:
-- "chateau" or "cabernet" would bring in thousands that say nothing.
create index catalog_label_words_trgm_idx on public.catalog_label_words
  using gin (word extensions.gin_trgm_ops) where rarity >= 3.2;
revoke all on public.catalog_label_words from public, anon, authenticated;

-- The words change with the catalog's names: made again every night.
create function public.soolgyul_refresh_label_words()
returns void
language plpgsql security definer
set search_path to ''
as $$
begin
  refresh materialized view public.catalog_label_words;
end
$$;
revoke all on function public.soolgyul_refresh_label_words() from public, anon, authenticated;

select cron.schedule('soolgyul_refresh_label_words', '30 18 * * *', 'select public.soolgyul_refresh_label_words()');

-- The drinks whose name words look most like [target_words] (words a
-- label read, folded or not), at most [target_limit], and the drinks of
-- [also_ids] (those the line search found) whatever their words: each
-- with its facts, the rarity of each word of its names, and how much the
-- words read found of it (`found`).
create function public.soolgyul_search_alcohol_catalog_by_label_words(
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
      (
        select jsonb_object_agg(word.value, vocabulary.rarity)
        from unnest(public.soolgyul_label_name_words(item.name_en) || public.soolgyul_label_name_words(item.name_ko)) as word(value)
        left join public.catalog_label_words as vocabulary on vocabulary.word = word.value
      ),
      picked.found
    from picked
    join public.alcohol_items as item on item.id = picked.id and item.publish_status = 'published'
    join public.alcohol_categories as category on category.id = item.alcohol_category_id and category.is_active
    left join public.catalog_taxonomy as style_term
      on style_term.term_type = 'style' and style_term.term_key = item.style_key and style_term.is_active
    left join public.catalog_taxonomy as region_term
      on region_term.term_type = 'region' and region_term.term_key = item.region_key
    order by picked.found desc, item.id;
end
$$;
revoke all on function public.soolgyul_search_alcohol_catalog_by_label_words(text[], uuid[], integer) from public;
grant execute on function public.soolgyul_search_alcohol_catalog_by_label_words(text[], uuid[], integer) to service_role, anon, authenticated;
