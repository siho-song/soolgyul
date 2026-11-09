-- A whole word that folds to the query ranks right after the exact name,
-- above a name prefix or substring that crosses words: 샤도네이 lists the
-- 샤르도네 wines before 샤또 네넹 (fold 샤도네넹). The stored fold text gains
-- the per-word folds of name_ko as extra tokens, so the rank stays a cheap
-- pattern on that column; aliases and keywords already are whole tokens.

drop index if exists public.alcohol_items_published_search_fold_trgm_idx;
alter table public.alcohol_items drop column search_fold_text;
alter table public.alcohol_items
  add column search_fold_text text generated always as (
    public.soolgyul_fold_korean_sound(name_ko)
    || ' ' || public.soolgyul_fold_korean_sound(coalesce(name_en, ''))
    || ' ' || public.soolgyul_fold_korean_sound_array(aliases)
    || ' ' || public.soolgyul_fold_korean_sound_array(search_keywords)
    || ' ' || public.soolgyul_fold_korean_sound_array(regexp_split_to_array(name_ko, '\s+'))
  ) stored;

create index alcohol_items_published_search_fold_trgm_idx
  on public.alcohol_items using gin (search_fold_text extensions.gin_trgm_ops)
  where publish_status = 'published';

create or replace function public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer default 20)
returns table(id uuid, name_ko text, name_en text, category_key text, style_key text, abv_percent numeric)
language sql stable security definer
set search_path to 'pg_catalog', 'public'
as $$
  with search_input as (
    select
      public.soolgyul_fold_korean_sound(target_query) as folded,
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
      item.abv_percent,
      -- search_fold_text starts with fold(name_ko) ' ' fold(name_en); folds
      -- hold no spaces, so the first two words are the two folded names and
      -- every later word is one alias, keyword or name word.
      case
        when split_part(item.search_fold_text, ' ', 1) = input.folded
          or split_part(item.search_fold_text, ' ', 2) = input.folded then 0
        when ' ' || item.search_fold_text || ' ' like '% ' || input.folded || ' %' then 1
        when split_part(item.search_fold_text, ' ', 1) like input.folded || '%'
          or split_part(item.search_fold_text, ' ', 2) like input.folded || '%' then 2
        when split_part(item.search_fold_text, ' ', 1) like '%' || input.folded || '%'
          or split_part(item.search_fold_text, ' ', 2) like '%' || input.folded || '%' then 3
        else 4
      end as match_rank,
      input.result_limit
    from public.alcohol_items as item
    join public.alcohol_categories as category
      on category.id = item.alcohol_category_id
     and category.is_active
    cross join search_input as input
    where item.publish_status = 'published'
      and input.raw_length between 1 and 100
      and input.folded <> ''
      and item.search_fold_text like '%' || input.folded || '%'
  )
  select
    matches.id,
    matches.name_ko,
    matches.name_en,
    matches.category_key,
    matches.style_key,
    matches.abv_percent
  from matches
  order by
    matches.match_rank,
    char_length(matches.name_ko),
    matches.name_ko,
    matches.id
  limit (select result_limit from search_input);
$$;
