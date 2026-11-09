-- Name search folds Korean transliteration variants.
--
-- Users type foreign names in Korean the way they hear them (퀴숑/뀌숑,
-- 샤도네이/샤르도네, 피노누아/피노 누아). The search now compares a folded
-- form of the query with a folded form of the name, aliases and keywords:
-- tense consonants become plain (ㄲㅋ→ㄱ …), ㅐ=ㅔ, an inserted 르/이 is
-- dropped, weak final consonants are dropped, spaces and punctuation go,
-- Latin accents are folded. The Python side (tools/catalog/field_rules/
-- check.py search_fold) must stay identical; the fixture
-- supabase/functions/_tests/fixtures/korean_sound_fold.json pins both.

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
      when 'ㅐ' then 'ㅔ' when 'ㅒ' then 'ㅖ'
      when 'ㅙ' then 'ㅞ' when 'ㅚ' then 'ㅞ'
      when 'ㅝ' then 'ㅓ' when 'ㅢ' then 'ㅣ'
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

create or replace function public.soolgyul_fold_korean_sound_array(input_values text[])
returns text
language sql immutable parallel safe
set search_path to ''
as $$
  select coalesce(string_agg(public.soolgyul_fold_korean_sound(value), ' ' order by ordinality), '')
  from unnest(coalesce(input_values, array[]::text[])) with ordinality as source(value, ordinality);
$$;

revoke all on function public.soolgyul_fold_korean_sound(text) from public;
revoke all on function public.soolgyul_fold_korean_sound_array(text[]) from public;

-- Folded name, aliases and keywords in one indexed text per product.
alter table public.alcohol_items
  add column search_fold_text text generated always as (
    public.soolgyul_fold_korean_sound(name_ko)
    || ' ' || public.soolgyul_fold_korean_sound(coalesce(name_en, ''))
    || ' ' || public.soolgyul_fold_korean_sound_array(aliases)
    || ' ' || public.soolgyul_fold_korean_sound_array(search_keywords)
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
      -- hold no spaces, so the first two words are the two folded names.
      case
        when split_part(item.search_fold_text, ' ', 1) = input.folded
          or split_part(item.search_fold_text, ' ', 2) = input.folded then 0
        when split_part(item.search_fold_text, ' ', 1) like input.folded || '%'
          or split_part(item.search_fold_text, ' ', 2) like input.folded || '%' then 1
        when split_part(item.search_fold_text, ' ', 1) like '%' || input.folded || '%'
          or split_part(item.search_fold_text, ' ', 2) like '%' || input.folded || '%' then 2
        else 3
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

comment on function public.soolgyul_search_alcohol_catalog(text, integer) is
  'Searches active published alcohol products on a sound-folded form of names, aliases and keywords (soolgyul_fold_korean_sound), so Korean transliteration variants match.';
