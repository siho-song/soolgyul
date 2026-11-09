-- 2026-11-14: the fuzzy search set pg_trgm.word_similarity_threshold on the
-- function, which the database role may not do (applying it live failed
-- with "permission denied to set parameter"), and writing the threshold
-- into each comparison lost the trigram index and timed out on the full
-- catalog. The function now loads pg_trgm and sets the threshold for its
-- own transaction, then runs the same query with the indexed <% operator.
create or replace function public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer default 20)
returns table(id uuid, name_ko text, name_en text, category_key text, style_key text, style_label text, abv_percent numeric, media_path text, country_code text, region text)
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public'
as $$
#variable_conflict use_column
begin
  -- Calling any pg_trgm function loads the extension so its parameter is
  -- known in this session; set_config then applies to this transaction.
  perform extensions.show_trgm('');
  perform set_config('pg_trgm.word_similarity_threshold', '0.45', true);
  return query
  with search_input as (
    select
      public.soolgyul_fold_korean_sound(target_query) as folded,
      array_remove(array(
        select public.soolgyul_fold_korean_sound(word)
        from regexp_split_to_table(coalesce(target_query, ''), '\s+') as word
      ), '') as words,
      char_length(trim(coalesce(target_query, ''))) as raw_length,
      greatest(1, least(coalesce(target_limit, 20), 20)) as result_limit
  ),
  usable_input as (
    select
      folded,
      words,
      (select word from unnest(words) as word order by char_length(word) desc, word limit 1) as index_word,
      array(select word from unnest(words) as word where char_length(word) >= 3 order by char_length(word) desc, word) as fuzzy_words
    from search_input
    where raw_length between 1 and 100 and cardinality(words) > 0
  ),
  index_word_producers as (
    select array_agg(producer.id) as ids
    from public.producers as producer
    where producer.search_fold_text like '%' || (select index_word from usable_input) || '%'
  ),
  strict_matches as (
    -- search_fold_text starts with fold(name_ko) ' ' fold(name_en); folds
    -- hold no spaces, so the first two words are the two folded names and
    -- every later word is one name word.
    select
      item.id,
      case
        when split_part(item.search_fold_text, ' ', 1) = (select folded from usable_input)
          or split_part(item.search_fold_text, ' ', 2) = (select folded from usable_input) then 0
        when ' ' || item.search_fold_text || ' ' like '% ' || (select folded from usable_input) || ' %' then 1
        when split_part(item.search_fold_text, ' ', 1) like (select folded from usable_input) || '%'
          or split_part(item.search_fold_text, ' ', 2) like (select folded from usable_input) || '%' then 2
        when item.search_fold_text like '%' || (select folded from usable_input) || '%' then 3
        when coalesce(producer.search_fold_text, '') like '%' || (select folded from usable_input) || '%' then 4
        else 5
      end as match_rank,
      0::real as fuzzy_score
    from public.alcohol_items as item
    left join public.producers as producer
      on producer.id = item.producer_id
    where (select char_length(index_word) >= 3 from usable_input)
      and item.publish_status = 'published'
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
      case
        when split_part(item.search_fold_text, ' ', 1) = (select folded from usable_input)
          or split_part(item.search_fold_text, ' ', 2) = (select folded from usable_input) then 0
        when ' ' || item.search_fold_text || ' ' like '% ' || (select folded from usable_input) || ' %' then 1
        when split_part(item.search_fold_text, ' ', 1) like (select folded from usable_input) || '%'
          or split_part(item.search_fold_text, ' ', 2) like (select folded from usable_input) || '%' then 2
        when item.search_fold_text like '%' || (select folded from usable_input) || '%' then 3
        when coalesce(producer.search_fold_text, '') like '%' || (select folded from usable_input) || '%' then 4
        else 5
      end as match_rank,
      0::real as fuzzy_score
    from public.alcohol_items as item
    left join public.producers as producer
      on producer.id = item.producer_id
    where (select char_length(index_word) < 3 from usable_input)
      and item.publish_status = 'published'
      and (
        select bool_and(
          item.search_fold_text like '%' || word || '%'
          or coalesce(producer.search_fold_text, '') like '%' || word || '%'
        )
        from unnest((select words from usable_input)) as word
      )
  ),
  -- Only when no product holds every word: every word long enough to judge
  -- must then be nearly in the names (word similarity at the threshold
  -- above), and the rows rank by the summed similarity.
  fuzzy_word_producers as (
    select array_agg(producer.id) as ids
    from public.producers as producer
    where (select fuzzy_words[1] from usable_input) operator(extensions.<%) producer.search_fold_text
  ),
  fuzzy_matches as (
    select
      item.id,
      6 as match_rank,
      (
        select sum(greatest(
          extensions.word_similarity(word, item.search_fold_text),
          extensions.word_similarity(word, coalesce(producer.search_fold_text, ''))
        ))
        from unnest((select fuzzy_words from usable_input)) as word
      )::real as fuzzy_score
    from public.alcohol_items as item
    left join public.producers as producer
      on producer.id = item.producer_id
    where not exists (select 1 from strict_matches)
      and (select cardinality(fuzzy_words) > 0 from usable_input)
      and item.publish_status = 'published'
      and (
        (select fuzzy_words[1] from usable_input) operator(extensions.<%) item.search_fold_text
        or item.producer_id = any(coalesce((select ids from fuzzy_word_producers), '{}'::uuid[]))
      )
      and (
        select bool_and(
          word operator(extensions.<%) item.search_fold_text
          or word operator(extensions.<%) coalesce(producer.search_fold_text, '')
        )
        from unnest((select fuzzy_words from usable_input)) as word
      )
  ),
  matches as (
    select * from strict_matches
    union all
    select * from fuzzy_matches
  )
  select
    item.id,
    item.name_ko,
    item.name_en,
    category.category_key,
    item.style_key,
    coalesce(style_term.label_ko, category.name_ko) as style_label,
    item.abv_percent,
    media.media_path,
    item.country_code,
    region_term.label_ko as region
  from matches
  join public.alcohol_items as item
    on item.id = matches.id
  join public.alcohol_categories as category
    on category.id = item.alcohol_category_id
   and category.is_active
  left join public.catalog_terms as style_term
    on style_term.term_type = 'style'
   and style_term.term_key = item.style_key
   and style_term.is_active
  left join public.catalog_terms as region_term
    on region_term.term_type = 'region'
   and region_term.term_key = item.region_key
  left join public.catalog_media_assets as media
    on media.alcohol_item_id = item.id
   and media.publish_status = 'published'
   and media.published_at is not null
  order by
    matches.match_rank,
    matches.fuzzy_score desc,
    char_length(item.name_ko),
    item.name_ko,
    item.id
  limit (select result_limit from search_input);
end
$$;
