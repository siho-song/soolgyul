-- Producers become a table. alcohol_items.search_keywords held the producer's
-- Korean and English names (plus a few product-name variants) per product so
-- that "프레이 브라더스" found the producer's wines; decided 2026-10-27 that the
-- producer is a row of its own, items point at it, and search looks at the
-- producer's names through that link. search_keywords goes.
--
-- The sound fold also drops the y-glide and rounds the remaining vowel pairs
-- (쇼비뇽/소비뇽, 뮤지니/무지니, 셰리/쉐리/세리, 쉬라/시라), and the search
-- matches every word of the query somewhere in the product or producer names
-- instead of the whole query as one substring ("프레이 소비뇽" finds the
-- Frei Brothers Cabernet Sauvignon). The Python fold
-- (tools/catalog/field_rules/check.py) and the fixture stay identical.

create or replace function public.soolgyul_fold_korean_sound(input_value text)
returns text
language plpgsql immutable parallel safe
set search_path to ''
as $$
declare
  base text;
  ch text;
  code integer;
  cho integer;
  jung integer;
  jong integer;
  cho_j text;
  jung_j text;
  jong_j text;
  out_text text := '';
  -- compatibility jamo tables (index = decomposition index + 1)
  chos text[] := array['ㄱ','ㄲ','ㄴ','ㄷ','ㄸ','ㄹ','ㅁ','ㅂ','ㅃ','ㅅ','ㅆ','ㅇ','ㅈ','ㅉ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'];
  jungs text[] := array['ㅏ','ㅐ','ㅑ','ㅒ','ㅓ','ㅔ','ㅕ','ㅖ','ㅗ','ㅘ','ㅙ','ㅚ','ㅛ','ㅜ','ㅝ','ㅞ','ㅟ','ㅠ','ㅡ','ㅢ','ㅣ'];
  jongs text[] := array['','ㄱ','ㄲ','ㄳ','ㄴ','ㄵ','ㄶ','ㄷ','ㄹ','ㄺ','ㄻ','ㄼ','ㄽ','ㄾ','ㄿ','ㅀ','ㅁ','ㅂ','ㅄ','ㅅ','ㅆ','ㅇ','ㅈ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'];
begin
  base := lower(normalize(coalesce(input_value, ''), NFC));
  base := translate(base, 'àáâäãåçèéêëìíîïñòóôöõøùúûüýÿ', 'aaaaaaceeeeiiiinoooooouuuuyy');
  base := regexp_replace(base, '[^0-9a-z가-힣]+', '', 'g');
  foreach ch in array regexp_split_to_array(base, '')
  loop
    code := ascii(ch) - 44032;  -- U+AC00
    if code < 0 or code >= 11172 then
      out_text := out_text || ch;
      continue;
    end if;
    cho := code / 588;
    jung := (code % 588) / 28;
    jong := code % 28;
    cho_j := chos[cho + 1];
    jung_j := jungs[jung + 1];
    jong_j := jongs[jong + 1];
    cho_j := case cho_j
      when 'ㄲ' then 'ㄱ' when 'ㅋ' then 'ㄱ'
      when 'ㄸ' then 'ㄷ' when 'ㅌ' then 'ㄷ'
      when 'ㅃ' then 'ㅂ' when 'ㅍ' then 'ㅂ'
      when 'ㅆ' then 'ㅅ'
      when 'ㅉ' then 'ㅈ' when 'ㅊ' then 'ㅈ'
      else cho_j end;
    jung_j := case jung_j
      when 'ㅐ' then 'ㅔ' when 'ㅒ' then 'ㅔ' when 'ㅖ' then 'ㅔ'
      when 'ㅙ' then 'ㅔ' when 'ㅚ' then 'ㅔ' when 'ㅞ' then 'ㅔ'
      when 'ㅝ' then 'ㅓ' when 'ㅕ' then 'ㅓ'
      when 'ㅢ' then 'ㅣ' when 'ㅟ' then 'ㅣ'
      when 'ㅛ' then 'ㅗ' when 'ㅠ' then 'ㅜ'
      else jung_j end;
    -- 까베르네/까베네: an inserted 르 is dropped.
    if cho_j = 'ㄹ' and jung_j = 'ㅡ' and jong_j = '' then
      continue;
    end if;
    -- 도멘/도메인: a trailing 이 after something is dropped.
    if cho_j = 'ㅇ' and jung_j = 'ㅣ' and jong_j = '' and out_text <> '' then
      continue;
    end if;
    if jong_j in ('ㅅ', 'ㅆ', 'ㅌ', 'ㅍ', 'ㅋ') then
      jong_j := '';
    end if;
    out_text := out_text || cho_j || jung_j || jong_j;
  end loop;
  return out_text;
end;
$$;

create table public.producers (
  id uuid primary key default gen_random_uuid(),
  producer_key text not null unique
    constraint producers_producer_key_check check (producer_key ~ '^[a-z0-9][a-z0-9_]*$'),
  name_ko text
    constraint producers_name_ko_check check (name_ko is null or btrim(name_ko) <> ''),
  name_en text
    constraint producers_name_en_check check (name_en is null or btrim(name_en) <> ''),
  search_fold_text text generated always as (
    public.soolgyul_fold_korean_sound(coalesce(name_ko, ''))
    || ' ' || public.soolgyul_fold_korean_sound(coalesce(name_en, ''))
  ) stored,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint producers_name_check check (coalesce(name_ko, name_en) is not null)
);

comment on table public.producers is
  'Who makes the product: winery, distillery, brewery or brand. One row per producer_key; items link through alcohol_items.producer_id.';

create index producers_search_fold_trgm_idx
  on public.producers using gin (search_fold_text extensions.gin_trgm_ops);

alter table public.producers enable row level security;
create policy producers_read on public.producers for select to anon, authenticated using (true);
grant select on table public.producers to anon, authenticated;
grant all on table public.producers to service_role;

alter table public.alcohol_items
  add column producer_id uuid references public.producers(id) on delete restrict;
create index alcohol_items_producer_idx on public.alcohol_items (producer_id);

comment on column public.alcohol_items.producer_id is 'The producer row; search also matches the producer''s names through it.';

drop index if exists public.alcohol_items_published_search_fold_trgm_idx;
alter table public.alcohol_items drop column search_fold_text;
alter table public.alcohol_items drop column search_keywords;

alter table public.alcohol_items
  add column search_fold_text text generated always as (
    public.soolgyul_fold_korean_sound(name_ko)
    || ' ' || public.soolgyul_fold_korean_sound(coalesce(name_en, ''))
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
      item.abv_percent,
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
    matches.abv_percent
  from matches
  order by
    matches.match_rank,
    char_length(matches.name_ko),
    matches.name_ko,
    matches.id
  limit (select result_limit from search_input);
$$;

comment on function public.soolgyul_search_alcohol_catalog(text, integer) is
  'Searches active published alcohol products: every word of the query, sound-folded (soolgyul_fold_korean_sound), must appear in the product''s names or its producer''s names.';

create or replace function public.soolgyul_catalog_search_projection_rows_v1()
returns table(alcohol_item_id uuid, alcohol_release_id uuid, display_name text, secondary_name text, producer_or_brand_display text, category_key text, subcategory_key text, style_key text, country_code text, region_display text, abv_percent numeric, search_aliases text[], descriptor_keys text[], is_active boolean, published_at timestamp with time zone, updated_at timestamp with time zone)
language sql stable security definer
set search_path to ''
as $$
 select i.id,null::uuid,i.name_ko,i.name_en,coalesce(producer.name_ko,producer.name_en),c.category_key,null::text,i.style_key,
 i.country_code,i.region,i.abv_percent,
 coalesce(a.search_aliases,array[]::text[]),coalesce(t.descriptor_keys,array[]::text[]),
 true,i.published_at,i.updated_at
 from public.alcohol_items i join public.alcohol_categories c on c.id=i.alcohol_category_id and c.is_active
 left join public.producers producer on producer.id=i.producer_id
 left join lateral (
  select array_agg(distinct public.soolgyul_normalize_catalog_text(v) order by public.soolgyul_normalize_catalog_text(v)) search_aliases
  from unnest(array[producer.name_ko,producer.name_en]) v where nullif(btrim(v),'') is not null
 ) a on true
 left join lateral (
  select array_agg(distinct v order by v) descriptor_keys
  from public.alcohol_tasting_profiles p
  cross join lateral unnest(p.aroma_tags||p.palate_tags||p.finish_tags) v
  where p.alcohol_item_id=i.id
 ) t on true
 where i.publish_status='published'
$$;
