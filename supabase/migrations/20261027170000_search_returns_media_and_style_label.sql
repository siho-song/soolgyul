-- The onboarding search list shows a bottle photo and a style line under each
-- product name (레드 와인 · 13.5%), and the chosen product is confirmed with
-- its country and region. The photo path comes from the media table,
-- so the app derives no storage path itself; the label comes from the term
-- dictionary so the app keeps no copy of it, and a product whose style has no
-- active term shows its category name. The return type changes, so the
-- function is recreated.
drop function public.soolgyul_search_alcohol_catalog(text, integer);

create function public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer default 20)
returns table(id uuid, name_ko text, name_en text, category_key text, style_key text, style_label text, abv_percent numeric, media_path text, country_code text, region text)
language sql stable security definer
set search_path to 'pg_catalog', 'public'
as $$
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
  matches as (
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
      item.region,
      -- search_fold_text starts with fold(name_ko) ' ' fold(name_en); folds
      -- hold no spaces, so the first two words are the two folded names and
      -- every later word is one name word.
      case
        when split_part(item.search_fold_text, ' ', 1) = input.folded
          or split_part(item.search_fold_text, ' ', 2) = input.folded then 0
        when ' ' || item.search_fold_text || ' ' like '% ' || input.folded || ' %' then 1
        when split_part(item.search_fold_text, ' ', 1) like input.folded || '%'
          or split_part(item.search_fold_text, ' ', 2) like input.folded || '%' then 2
        when item.search_fold_text like '%' || input.folded || '%' then 3
        when coalesce(producer.search_fold_text, '') like '%' || input.folded || '%' then 4
        else 5
      end as match_rank,
      input.result_limit
    from public.alcohol_items as item
    join public.alcohol_categories as category
      on category.id = item.alcohol_category_id
     and category.is_active
    left join public.producers as producer
      on producer.id = item.producer_id
    left join public.catalog_terms as style_term
      on style_term.term_type = 'style'
     and style_term.term_key = item.style_key
     and style_term.is_active
    left join public.catalog_media_assets as media
      on media.alcohol_item_id = item.id
     and media.publish_status = 'published'
     and media.published_at is not null
    cross join search_input as input
    where item.publish_status = 'published'
      and input.raw_length between 1 and 100
      and cardinality(input.words) > 0
      and (
        select bool_and(
          item.search_fold_text like '%' || word || '%'
          or coalesce(producer.search_fold_text, '') like '%' || word || '%'
        )
        from unnest(input.words) as word
      )
  )
  select
    matches.id,
    matches.name_ko,
    matches.name_en,
    matches.category_key,
    matches.style_key,
    matches.style_label,
    matches.abv_percent,
    matches.media_path,
    matches.country_code,
    matches.region
  from matches
  order by
    matches.match_rank,
    char_length(matches.name_ko),
    matches.name_ko,
    matches.id
  limit (select result_limit from search_input);
$$;

comment on function public.soolgyul_search_alcohol_catalog(text, integer) is
  'Searches active published alcohol products: every word of the query, sound-folded (soolgyul_fold_korean_sound), must appear in the product''s names or its producer''s names. style_label is the style term''s Korean label, or the category name; media_path is the published photo in bucket alcohol-product-images.';

revoke all on function public.soolgyul_search_alcohol_catalog(text, integer) from public;
grant execute on function public.soolgyul_search_alcohol_catalog(text, integer)
  to anon, authenticated, service_role;
