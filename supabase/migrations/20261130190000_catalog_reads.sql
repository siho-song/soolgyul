-- Catalog reads were slow in three places. The name search joined every
-- match to the product tables before keeping one page, which spilled to
-- disk on a common word, and a query nothing matched checked thousands of
-- products word by word; it is rewritten below. The record and liked-card
-- lists asked for photos through a function that built the whole catalog's
-- photo list each time; the lists now carry the photo path themselves.
-- Screens that searched once per name (자주 찾는 술, a photographed label)
-- get one call for all names. Indexes that no query reads are dropped.
set local lock_timeout = '5s';

-- The search in two steps. Products that hold every word come first; only
-- when there is none are products looked up whose names nearly hold every
-- word (a typo, a label read off a photo). The matches carry what a result
-- shows of the product itself, so a page is cut from them without reading
-- the product table again; only the page's rows look up labels and photo.

-- Products that hold every word of the query, best match first.
create function public.soolgyul_catalog_exact_matches(
  target_query text,
  target_limit integer,
  target_offset integer
) returns table(
  id uuid, name_ko text, name_en text, category_key text, style_key text,
  style_label text, abv_percent numeric, media_path text, country_code text,
  region text
)
language plpgsql stable
set search_path to 'pg_catalog', 'public'
as $$
#variable_conflict use_column
begin
  return query
  with search_input as (
    select
      public.soolgyul_fold_korean_sound(target_query) as folded,
      array_remove(array(
        select public.soolgyul_fold_korean_sound(word)
        from regexp_split_to_table(coalesce(target_query, ''), '\s+') as word
      ), '') as words,
      char_length(trim(coalesce(target_query, ''))) as raw_length,
      greatest(1, least(coalesce(target_limit, 20), 20)) as result_limit,
      greatest(0, least(coalesce(target_offset, 0), 1000)) as result_offset
  ),
  usable_input as (
    select
      folded,
      words,
      (select word from unnest(words) as word order by char_length(word) desc, word limit 1) as index_word
    from search_input
    where raw_length between 1 and 100 and cardinality(words) > 0
  ),
  active_categories as (
    select array_agg(category.id) as ids
    from public.alcohol_categories as category
    where category.is_active
  ),
  index_word_producers as (
    select array_agg(producer.id) as ids
    from public.producers as producer
    where producer.search_fold_text like '%' || (select index_word from usable_input) || '%'
  ),
  matches as (
    -- search_fold_text starts with fold(name_ko) ' ' fold(name_en); folds
    -- hold no spaces, so the first two words are the two folded names and
    -- every later word is one name word.
    select
      item.id,
      item.name_ko,
      item.name_en,
      item.alcohol_category_id,
      item.style_key,
      item.region_key,
      item.abv_percent,
      item.country_code,
      case
        when split_part(item.search_fold_text, ' ', 1) = (select folded from usable_input)
          or split_part(item.search_fold_text, ' ', 2) = (select folded from usable_input) then 0
        when ' ' || item.search_fold_text || ' ' like '% ' || (select folded from usable_input) || ' %' then 1
        when split_part(item.search_fold_text, ' ', 1) like (select folded from usable_input) || '%'
          or split_part(item.search_fold_text, ' ', 2) like (select folded from usable_input) || '%' then 2
        when item.search_fold_text like '%' || (select folded from usable_input) || '%' then 3
        when coalesce(producer.search_fold_text, '') like '%' || (select folded from usable_input) || '%' then 4
        else 5
      end as match_rank
    from public.alcohol_items as item
    left join public.producers as producer
      on producer.id = item.producer_id
    where (select char_length(index_word) >= 3 from usable_input)
      and item.publish_status = 'published'
      and item.alcohol_category_id = any(coalesce((select ids from active_categories), '{}'::uuid[]))
      and (
        item.search_fold_text like '%' || (select index_word from usable_input) || '%'
        or item.producer_id = any(coalesce((select ids from index_word_producers), '{}'::uuid[]))
      )
      and (
        select bool_and(
          item.search_fold_text like '%' || word || '%'
          or coalesce(producer.search_fold_text, '') like '%' || word || '%'
        )
        from unnest((select words from usable_input)) as word
      )
    union all
    select
      item.id,
      item.name_ko,
      item.name_en,
      item.alcohol_category_id,
      item.style_key,
      item.region_key,
      item.abv_percent,
      item.country_code,
      case
        when split_part(item.search_fold_text, ' ', 1) = (select folded from usable_input)
          or split_part(item.search_fold_text, ' ', 2) = (select folded from usable_input) then 0
        when ' ' || item.search_fold_text || ' ' like '% ' || (select folded from usable_input) || ' %' then 1
        when split_part(item.search_fold_text, ' ', 1) like (select folded from usable_input) || '%'
          or split_part(item.search_fold_text, ' ', 2) like (select folded from usable_input) || '%' then 2
        when item.search_fold_text like '%' || (select folded from usable_input) || '%' then 3
        when coalesce(producer.search_fold_text, '') like '%' || (select folded from usable_input) || '%' then 4
        else 5
      end as match_rank
    from public.alcohol_items as item
    left join public.producers as producer
      on producer.id = item.producer_id
    where (select char_length(index_word) < 3 from usable_input)
      and item.publish_status = 'published'
      and item.alcohol_category_id = any(coalesce((select ids from active_categories), '{}'::uuid[]))
      and (
        select bool_and(
          item.search_fold_text like '%' || word || '%'
          or coalesce(producer.search_fold_text, '') like '%' || word || '%'
        )
        from unnest((select words from usable_input)) as word
      )
  ),
  page as (
    select matches.*
    from matches
    order by
      matches.match_rank,
      char_length(matches.name_ko),
      matches.name_ko,
      matches.id
    limit (select result_limit from search_input)
    offset (select result_offset from search_input)
  )
  select
    page.id,
    page.name_ko,
    page.name_en,
    category.category_key,
    page.style_key,
    coalesce(style_term.label_ko, category.name_ko) as style_label,
    page.abv_percent,
    (
      select media.media_path
      from public.catalog_media_assets as media
      where media.alcohol_item_id = page.id
        and media.publish_status = 'published'
        and media.published_at is not null
    ) as media_path,
    page.country_code,
    region_term.label_ko as region
  from page
  join public.alcohol_categories as category
    on category.id = page.alcohol_category_id
  left join public.catalog_taxonomy as style_term
    on style_term.term_type = 'style'
   and style_term.term_key = page.style_key
   and style_term.is_active
  left join public.catalog_taxonomy as region_term
    on region_term.term_type = 'region'
   and region_term.term_key = page.region_key
  order by
    page.match_rank,
    char_length(page.name_ko),
    page.name_ko,
    page.id;
end
$$;

-- Producers whose name nearly holds the word. The planner underrates what
-- comparing a word with every name costs and would read the whole table;
-- the trigram index is several times faster whatever the word, so this
-- lookup is planned without sequential scans.
create function public.soolgyul_producers_near_word(target_word text)
returns uuid[]
language sql stable
set search_path to 'pg_catalog', 'public'
set enable_seqscan to off
as $$
  select array_agg(producer.id)
  from public.producers as producer
  where target_word operator(extensions.<%) producer.search_fold_text
$$;

-- Products whose names nearly hold every word long enough to judge (word
-- similarity at the threshold set below), most similar first. The words
-- are known when this query is planned, so it starts from the rarest one:
-- a common word like "domaine" no longer has every product of every
-- "Domaine ..." producer checked word by word.
create function public.soolgyul_catalog_near_matches(
  target_query text,
  target_limit integer,
  target_offset integer
) returns table(
  id uuid, name_ko text, name_en text, category_key text, style_key text,
  style_label text, abv_percent numeric, media_path text, country_code text,
  region text
)
language plpgsql stable
set search_path to 'pg_catalog', 'public'
as $$
declare
  near_words text[];
  first_word text;
  second_word text;
  first_producers uuid[];
  second_producers uuid[];
begin
  if char_length(trim(coalesce(target_query, ''))) not between 1 and 100 then
    return;
  end if;
  near_words := array(
    select folded.word
    from (
      select public.soolgyul_fold_korean_sound(raw_word) as word
      from regexp_split_to_table(coalesce(target_query, ''), '\s+') as raw_word
    ) as folded
    where char_length(folded.word) >= 3
    order by char_length(folded.word) desc, folded.word
  );
  if cardinality(near_words) = 0 then
    return;
  end if;
  -- Calling any pg_trgm function loads the extension so its parameter is
  -- known in this session; set_config then applies to this transaction.
  perform extensions.show_trgm('');
  perform set_config('pg_trgm.word_similarity_threshold', '0.45', true);

  -- The two longest words each narrow the search through the indexes; a
  -- single word stands in for the second.
  first_word := near_words[1];
  second_word := coalesce(near_words[2], first_word);
  first_producers := public.soolgyul_producers_near_word(first_word);
  second_producers := case
    when second_word = first_word then first_producers
    else public.soolgyul_producers_near_word(second_word)
  end;

  return query execute $query$
    with active_categories as (
      select array_agg(category.id) as ids
      from public.alcohol_categories as category
      where category.is_active
    ),
    matches as (
      select
        item.id,
        item.name_ko,
        item.name_en,
        item.alcohol_category_id,
        item.style_key,
        item.region_key,
        item.abv_percent,
        item.country_code,
        (
          select sum(greatest(
            extensions.word_similarity(word, item.search_fold_text),
            extensions.word_similarity(word, coalesce(producer.search_fold_text, ''))
          ))
          from unnest($1) as word
        )::real as near_score
      from public.alcohol_items as item
      left join public.producers as producer
        on producer.id = item.producer_id
      where item.publish_status = 'published'
        and item.alcohol_category_id = any(coalesce((select ids from active_categories), '{}'::uuid[]))
        and (
          $2 operator(extensions.<%) item.search_fold_text
          or item.producer_id = any($3)
        )
        and (
          $4 operator(extensions.<%) item.search_fold_text
          or item.producer_id = any($5)
        )
        and (
          select bool_and(
            word operator(extensions.<%) item.search_fold_text
            or word operator(extensions.<%) coalesce(producer.search_fold_text, '')
          )
          from unnest($1) as word
        )
    ),
    page as (
      select matches.*
      from matches
      order by
        matches.near_score desc,
        char_length(matches.name_ko),
        matches.name_ko,
        matches.id
      limit $6
      offset $7
    )
  select
    page.id,
    page.name_ko,
    page.name_en,
    category.category_key,
    page.style_key,
    coalesce(style_term.label_ko, category.name_ko) as style_label,
    page.abv_percent,
    (
      select media.media_path
      from public.catalog_media_assets as media
      where media.alcohol_item_id = page.id
        and media.publish_status = 'published'
        and media.published_at is not null
    ) as media_path,
    page.country_code,
    region_term.label_ko as region
  from page
  join public.alcohol_categories as category
    on category.id = page.alcohol_category_id
  left join public.catalog_taxonomy as style_term
    on style_term.term_type = 'style'
   and style_term.term_key = page.style_key
   and style_term.is_active
  left join public.catalog_taxonomy as region_term
    on region_term.term_type = 'region'
   and region_term.term_key = page.region_key
    order by
      page.near_score desc,
      char_length(page.name_ko),
      page.name_ko,
      page.id
  $query$ using
    near_words,
    first_word, coalesce(first_producers, '{}'::uuid[]),
    second_word, coalesce(second_producers, '{}'::uuid[]),
    greatest(1, least(coalesce(target_limit, 20), 20)),
    greatest(0, least(coalesce(target_offset, 0), 1000));
end
$$;

revoke all on function public.soolgyul_producers_near_word(text) from public, anon, authenticated;
revoke all on function public.soolgyul_catalog_exact_matches(text, integer, integer) from public, anon, authenticated;
revoke all on function public.soolgyul_catalog_near_matches(text, integer, integer) from public, anon, authenticated;

create or replace function public.soolgyul_search_alcohol_catalog(
  target_query text,
  target_limit integer default 20,
  target_offset integer default 0
) returns table(
  id uuid, name_ko text, name_en text, category_key text, style_key text,
  style_label text, abv_percent numeric, media_path text, country_code text,
  region text
)
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  return query
    select * from public.soolgyul_catalog_exact_matches(target_query, target_limit, target_offset);
  if found then
    return;
  end if;
  -- An empty page past the first may still follow exact matches, and near
  -- matches never mix with those.
  if coalesce(target_offset, 0) > 0 and exists (
    select 1 from public.soolgyul_catalog_exact_matches(target_query, 1, 0)
  ) then
    return;
  end if;
  return query
    select * from public.soolgyul_catalog_near_matches(target_query, target_limit, target_offset);
end
$$;

-- Several searches in one call, each answered as the single search answers
-- it: `query_index` is the query's place in the array, and the rows of one
-- query keep their rank order.
create function public.soolgyul_search_alcohol_catalog_batch(
  target_queries text[],
  target_limit integer default 10
) returns table(
  query_index integer, id uuid, name_ko text, name_en text, category_key text,
  style_key text, style_label text, abv_percent numeric, media_path text,
  country_code text, region text
)
language sql stable security definer
set search_path to ''
as $$
  select
    asked.place::integer,
    found.id, found.name_ko, found.name_en, found.category_key,
    found.style_key, found.style_label, found.abv_percent, found.media_path,
    found.country_code, found.region
  from unnest(target_queries[1:8]) with ordinality as asked(words, place)
  cross join lateral public.soolgyul_search_alcohol_catalog(
    asked.words, target_limit, 0
  ) with ordinality as found(
    id, name_ko, name_en, category_key, style_key, style_label, abv_percent,
    media_path, country_code, region, place
  )
  order by asked.place, found.place
$$;

revoke all on function public.soolgyul_search_alcohol_catalog_batch(text[], integer) from public;
grant execute on function public.soolgyul_search_alcohol_catalog_batch(text[], integer) to service_role, anon, authenticated;

create or replace function public.soolgyul_my_drink_history(
  p_from timestamp with time zone,
  p_to timestamp with time zone
) returns jsonb
language sql stable security definer
set search_path to ''
as $$
  select coalesce(jsonb_agg(t.row_json order by t.created_at, t.id), '[]'::jsonb)
  from (
    select c.id, r.created_at,
      jsonb_build_object(
        'result_id', c.id::text,
        'recorded_at', r.created_at,
        'alcohol_item_id', r.alcohol_item_id::text,
        'name', item_row.name_ko,
        'category_key', category_row.category_key,
        'category_label', category_row.name_ko,
        'media_path', media_row.media_path,
        'note', r.one_line_note,
        'summary', c.rendered_snapshot #>> '{bite,summary}',
        'brief', c.rendered_snapshot #>> '{bite,brief}',
        'tags', coalesce((
          select jsonb_agg(jsonb_build_object(
            'label', tag ->> 'label',
            'kind', tag ->> 'kind'
          ))
          from jsonb_array_elements(
            case jsonb_typeof(c.rendered_snapshot #> '{bite,tags}')
              when 'array' then c.rendered_snapshot #> '{bite,tags}'
              else '[]'::jsonb
            end
          ) as tag
          where tag ->> 'label' <> ''
        ), '[]'::jsonb)
      ) as row_json
    from public.drink_records r
    join public.taste_cards c
      on c.drink_record_id = r.id and c.lifecycle = 'final'
    join public.alcohol_items item_row on item_row.id = r.alcohol_item_id
    left join public.alcohol_categories category_row
      on category_row.id = item_row.alcohol_category_id
    left join public.catalog_media_assets media_row
      on media_row.alcohol_item_id = item_row.id
      and item_row.publish_status = 'published'
      and media_row.publish_status = 'published'
      and media_row.published_at is not null
    where r.user_id = auth.uid()
      and r.deleted_at is null
      and public.soolgyul_account_active(auth.uid())
      and r.created_at >= p_from
      and r.created_at < p_to
      and p_to - p_from <= interval '45 days'
  ) t;
$$;

create or replace function public.soolgyul_my_liked_cards(
  p_category text default null,
  p_latest_first boolean default true,
  p_offset integer default 0,
  p_limit integer default 30
) returns jsonb
language sql stable security definer
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
      case when item_row.publish_status = 'published' then item_row.id end as shown_item_id,
      c.id as result_id,
      c.rendered_snapshot #>> '{bite,brief}' as brief,
      c.rendered_snapshot #>> '{bite,summary}' as summary,
      category_row.interest_key
    from public.user_liked_drink_cards l
    join public.drink_records r
      on r.id = l.drink_record_id
      and r.user_id = l.user_id
      and r.deleted_at is null
    join public.alcohol_items item_row on item_row.id = r.alcohol_item_id
    left join public.taste_cards c
      on c.drink_record_id = r.id and c.lifecycle = 'final'
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
          'media_path', media_row.media_path,
          'result_id', page.result_id::text,
          'brief', page.brief,
          'summary', page.summary,
          'interest_key', page.interest_key
        )
        order by page.position
      )
      from page
      left join public.catalog_media_assets media_row
        on media_row.alcohol_item_id = page.shown_item_id
        and media_row.publish_status = 'published'
        and media_row.published_at is not null
    ), '[]'::jsonb)
  );
$$;

-- No query reads these: the search uses search_fold_text, and the key and
-- tag arrays are only ever checked row by row.
drop index public.alcohol_items_name_en_trgm_idx;
drop index public.alcohol_items_name_ko_trgm_idx;
drop index public.alcohol_items_published_name_en_trgm_idx;
drop index public.alcohol_items_published_name_ko_trgm_idx;
drop index public.alcohol_items_category_name_en_idx;
drop index public.alcohol_items_ingredient_keys_idx;
drop index public.alcohol_items_production_process_keys_idx;
drop index public.alcohol_tasting_profiles_aroma_tags_idx;
drop index public.alcohol_tasting_profiles_palate_tags_idx;
drop index public.alcohol_tasting_profiles_finish_tags_idx;
