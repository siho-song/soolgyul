-- The catalog search put names in order of their length alone, so the
-- bottles people look for sat behind rare editions, a wine that only shares a
-- word stood among a brand's whiskies, and a like-sounding name counted as
-- much as the right spelling. When nothing matched, loosely similar names
-- were answered as if they were matches, also for drinks the catalog does
-- not carry at all.
-- Matches are now ordered by: the right spelling, the full name, the bottles
-- people know or pick, where the words sit in the name, and for a wine with
-- many years the recent ones first. A word has to sit inside a word of the
-- name or run on from the start of one. A word naming a kind of drink or a
-- country narrows the search, one naming a style is met by the bottle's
-- style. Words that find nothing are tried said another way. A look-alike
-- has to be close word by word and is marked as a guess, and a drink the
-- catalog does not carry is said to be so.
set local lock_timeout = '5s';

-- What makes a bottle come first among equal matches: it is one of the
-- bottles people know (set by hand), and how often members picked or
-- recorded it lately (counted by a nightly job). Among matches that weigh
-- and sit the same, a brand's everyday bottle (`staple`, set by hand) comes
-- first; a list by kind or country starts with those.
create table public.catalog_search_signals (
  alcohol_item_id uuid primary key references public.alcohol_items(id) on delete cascade,
  known boolean not null default false,
  staple boolean not null default false,
  picks integer not null default 0 check (picks >= 0),
  updated_at timestamptz not null default now()
);
alter table public.catalog_search_signals enable row level security;
revoke all on table public.catalog_search_signals from public, anon, authenticated;
grant all on table public.catalog_search_signals to service_role;

-- A name as typed, without spaces, marks, case or accents: the right spelling
-- is told apart from a like-sounding one by this, not by the sound fold.
create function public.soolgyul_catalog_compact_text(input_value text) returns text
language sql immutable parallel safe
set search_path to ''
as $$
  select translate(
    lower(regexp_replace(normalize(coalesce(input_value, ''), NFC), '[[:space:][:punct:]]+', '', 'g')),
    'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ',
    'aaaaaaceeeeiiiinooooouuuuyy'
  );
$$;

revoke all on function public.soolgyul_catalog_compact_text(text) from public, anon, authenticated;
grant execute on function public.soolgyul_catalog_compact_text(text) to service_role;

-- The kind of drink a word names, or null: "위스키" said along with a name
-- narrows the search to that kind instead of being looked for in the name.
create function public.soolgyul_catalog_kind_of_word(word text) returns text
language sql immutable parallel safe
set search_path to ''
as $$
  select case public.soolgyul_catalog_compact_text(word)
    when '위스키' then 'whisky' when 'whisky' then 'whisky' when 'whiskey' then 'whisky'
    when '와인' then 'wine' when 'wine' then 'wine'
    when '사케' then 'sake' when 'sake' then 'sake' when '니혼슈' then 'sake'
    when '전통주' then 'korean_traditional'
  end;
$$;

revoke all on function public.soolgyul_catalog_kind_of_word(text) from public, anon, authenticated;
grant execute on function public.soolgyul_catalog_kind_of_word(text) to service_role;

-- Both names as typed, kept with the row so a search does not work them out
-- for every candidate.
alter table public.alcohol_items
  add column search_typed_text text generated always as (
    public.soolgyul_catalog_compact_text(name_ko) || ' ' || public.soolgyul_catalog_compact_text(name_en)
  ) stored;

-- The styles a word names, or null. Said with other words, such a word is
-- also met by a bottle of that style whose name does not hold it: "지평
-- 막걸리" finds 지평탁주, "맥캘란 싱글몰트" the 맥캘란 bottles.
create function public.soolgyul_catalog_styles_of_word(word text) returns text[]
language sql immutable parallel safe
set search_path to ''
as $$
  select case public.soolgyul_catalog_compact_text(word)
    when '막걸리' then array['takju'] when '탁주' then array['takju']
    when '약주' then array['yakju'] when '청주' then array['korean_cheongju']
    when '소주' then array['distilled_soju'] when '증류주' then array['distilled_soju']
    when '과실주' then array['korean_fruit_wine']
    when '레드' then array['red_wine'] when '화이트' then array['white_wine']
    when '로제' then array['rose_wine'] when '스파클링' then array['sparkling_wine']
    when '싱글몰트' then array['single_malt_whisky']
    when '블렌디드' then array['blended_whisky', 'blended_malt_whisky']
    when '버번' then array['bourbon']
  end;
$$;
revoke all on function public.soolgyul_catalog_styles_of_word(text) from public, anon, authenticated;

-- The country a word names, or null: "칠레 와인" and "일본 위스키" narrow the
-- search to that country instead of looking for the word in the names.
create function public.soolgyul_catalog_country_of_word(word text) returns text
language sql immutable parallel safe
set search_path to ''
as $$
  select case public.soolgyul_catalog_compact_text(word)
    when '프랑스' then 'FR' when 'france' then 'FR'
    when '이탈리아' then 'IT' when '이태리' then 'IT' when 'italy' then 'IT'
    when '미국' then 'US' when 'usa' then 'US'
    when '스페인' then 'ES' when 'spain' then 'ES'
    when '호주' then 'AU' when '오스트레일리아' then 'AU' when 'australia' then 'AU'
    when '칠레' then 'CL' when 'chile' then 'CL'
    when '일본' then 'JP' when 'japan' then 'JP'
    when '영국' then 'GB' when '스코틀랜드' then 'GB' when 'scotland' then 'GB'
    when '한국' then 'KR' when '국산' then 'KR' when 'korea' then 'KR'
    when '포르투갈' then 'PT' when 'portugal' then 'PT'
    when '아르헨티나' then 'AR' when 'argentina' then 'AR'
    when '뉴질랜드' then 'NZ'
    when '독일' then 'DE' when 'germany' then 'DE'
    when '남아공' then 'ZA' when '남아프리카' then 'ZA'
    when '조지아' then 'GE'
    when '오스트리아' then 'AT' when 'austria' then 'AT'
    when '아일랜드' then 'IE' when 'ireland' then 'IE'
    when '헝가리' then 'HU' when '그리스' then 'GR' when '캐나다' then 'CA'
    when '대만' then 'TW' when '타이완' then 'TW' when 'taiwan' then 'TW'
    when '인도' then 'IN' when '중국' then 'CN'
  end;
$$;
revoke all on function public.soolgyul_catalog_country_of_word(text) from public, anon, authenticated;

-- Whether the name's words, run together from the start of one of them, go
-- on as said: "블랙라벨" in "조니워커 블랙 라벨". A word found in the run
-- any other way is pieced from the end of one word and the start of the
-- next ("주스" in "원소주 스피릿") and is no match.
create function public.soolgyul_catalog_runs_from_word(name_words text, said text) returns boolean
language sql immutable parallel safe
set search_path to ''
as $$
  select exists (
    select 1
    from (select string_to_array(name_words, ' ') as list) as words,
      generate_subscripts(words.list, 1) as start
    where array_to_string(words.list[start:], '') like said || '%'
  );
$$;
revoke all on function public.soolgyul_catalog_runs_from_word(text, text) from public, anon, authenticated;

-- The words said another way, tried when nothing is spelled as typed: a
-- number without what people add to it ("41도", "21년산", "12y"), a letter
-- parted from the number after it ("맥12"), and a letter said by its Korean
-- name ("엠" for M; "엑스오" for XO).
create function public.soolgyul_catalog_reworded_query(target_query text) returns text
language sql immutable parallel safe
set search_path to ''
as $$
  select string_agg(
    case
      when word ~ '^[0-9]+(년산|도)$' then substring(word from '^[0-9]+') || case when word like '%년산' then '년' else '' end
      when word ~* '^[0-9]+(y|yo|yr|yrs|year|years)$' then substring(word from '^[0-9]+')
      when word = '엑스오' then 'xo'
      when word = '브이에스오피' then 'vsop'
      when word = '브이에스' then 'vs'
      when word in ('에이', '비', '씨', '디', '에프', '지', '에이치', '아이', '제이', '케이', '엘', '엠', '엔',
                    '피', '큐', '알', '에스', '티', '유', '브이', '더블유', '엑스', '와이', '제트') then
        case word
          when '에이' then 'a' when '비' then 'b' when '씨' then 'c' when '디' then 'd' when '에프' then 'f'
          when '지' then 'g' when '에이치' then 'h' when '아이' then 'i' when '제이' then 'j' when '케이' then 'k'
          when '엘' then 'l' when '엠' then 'm' when '엔' then 'n' when '피' then 'p' when '큐' then 'q'
          when '알' then 'r' when '에스' then 's' when '티' then 't' when '유' then 'u' when '브이' then 'v'
          when '더블유' then 'w' when '엑스' then 'x' when '와이' then 'y' when '제트' then 'z'
        end
      else word
    end,
    ' ' order by place
  )
  from regexp_split_to_table(
    regexp_replace(trim(coalesce(target_query, '')), '([가-힣A-Za-z])([0-9])', '\1 \2', 'g'),
    '\s+'
  ) with ordinality as said(word, place)
  where word <> '';
$$;
revoke all on function public.soolgyul_catalog_reworded_query(text) from public, anon, authenticated;

drop function public.soolgyul_search_alcohol_catalog_batch(text[], integer);
drop function public.soolgyul_search_alcohol_catalog(text, integer, integer);
drop function public.soolgyul_catalog_exact_matches(text, integer, integer);

-- A word said is in a name when it sits inside one of the name's words or
-- runs on from the start of one; a word of one or two letters, or a single
-- syllable said alone, has to begin a word. With `target_word_starts` every
-- word said has to begin a word of the name.
create function public.soolgyul_catalog_exact_matches(
  target_query text,
  target_limit integer,
  target_offset integer,
  target_category_keys text[] default null,
  target_country_codes text[] default null,
  target_word_starts boolean default false
) returns table(
  id uuid, name_ko text, name_en text, category_key text, style_key text,
  style_label text, abv_percent numeric, media_path text, country_code text,
  region text, spelled boolean
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
      char_length(trim(coalesce(target_query, ''))) as raw_length,
      greatest(1, least(coalesce(target_limit, 20), 20)) as result_limit,
      greatest(0, least(coalesce(target_offset, 0), 1000)) as result_offset
  ),
  said_words as materialized (
    select
      row_number() over (order by raw.place) as place,
      public.soolgyul_fold_korean_sound(raw.word) as folded,
      public.soolgyul_catalog_compact_text(raw.word) as typed,
      public.soolgyul_catalog_styles_of_word(raw.word) as styles
    from regexp_split_to_table(coalesce(target_query, ''), '\s+') with ordinality as raw(word, place)
    where public.soolgyul_fold_korean_sound(raw.word) <> ''
  ),
  said as materialized (
    select
      said_words.*,
      (select count(*) from said_words) as word_count,
      -- Such a word has to begin a word of the name.
      (
        target_word_starts
        or char_length(said_words.folded) <= 2
        or (char_length(said_words.folded) = 3 and (select count(*) from said_words) = 1)
      ) as begins_only
    from said_words
  ),
  usable_input as (
    select
      search_input.folded,
      (select count(*) from said) as word_count,
      (select said.folded from said order by said.place limit 1) as first_word,
      -- The word the index looks for: the longest, and not one a bottle's
      -- style alone can meet while another word is said.
      (
        select said.folded
        from said
        order by (said.styles is not null and said.word_count > 1), char_length(said.folded) desc, said.folded
        limit 1
      ) as index_word,
      (
        select said.begins_only
        from said
        order by (said.styles is not null and said.word_count > 1), char_length(said.folded) desc, said.folded
        limit 1
      ) as index_begins_only
    from search_input
    where search_input.raw_length between 1 and 100 and exists (select 1 from said)
  ),
  wanted_categories as (
    select array_agg(category.id) as ids
    from public.alcohol_categories as category
    where category.is_active
      and (target_category_keys is null or category.category_key = any(target_category_keys))
  ),
  index_word_producers as (
    select array_agg(producer.id) as ids
    from public.producers as producer, usable_input
    where case
      when usable_input.index_begins_only
        then ' ' || producer.search_fold_text like '% ' || usable_input.index_word || '%'
      else producer.search_fold_text like '%' || usable_input.index_word || '%'
    end
  ),
  candidates as (
    select item.id, item.name_ko, item.name_en, item.alcohol_category_id, item.style_key,
           item.region_key, item.abv_percent, item.country_code, item.vintage_year,
           item.search_fold_text, item.search_typed_text, coalesce(producer.search_fold_text, '') as producer_fold
    from public.alcohol_items as item
    left join public.producers as producer on producer.id = item.producer_id
    where (select char_length(index_word) >= 3 from usable_input)
      and item.publish_status = 'published'
      and item.alcohol_category_id = any(coalesce((select ids from wanted_categories), '{}'::uuid[]))
      and (target_country_codes is null or item.country_code = any(target_country_codes))
      and (
        item.search_fold_text like '%' || (select index_word from usable_input) || '%'
        or item.producer_id = any(coalesce((select ids from index_word_producers), '{}'::uuid[]))
      )
    union all
    -- One or two letters: no index helps, so only the rows where a word
    -- begins with them go on to be weighed.
    select item.id, item.name_ko, item.name_en, item.alcohol_category_id, item.style_key,
           item.region_key, item.abv_percent, item.country_code, item.vintage_year,
           item.search_fold_text, item.search_typed_text, coalesce(producer.search_fold_text, '') as producer_fold
    from public.alcohol_items as item
    left join public.producers as producer on producer.id = item.producer_id
    where (select char_length(index_word) < 3 from usable_input)
      and item.publish_status = 'published'
      and item.alcohol_category_id = any(coalesce((select ids from wanted_categories), '{}'::uuid[]))
      and (target_country_codes is null or item.country_code = any(target_country_codes))
      and (
        ' ' || item.search_fold_text like '% ' || (select index_word from usable_input) || '%'
        or item.producer_id = any(coalesce((select ids from index_word_producers), '{}'::uuid[]))
        or (
          (select word_count > 1 and index_word ~ '^[a-z]+$' from usable_input)
          and item.search_fold_text like '%' || (select index_word from usable_input) || '%'
        )
        or (
          (select word_count > 1 from usable_input)
          and item.search_fold_text like '%' || (select folded from usable_input) || '%'
        )
      )
  ),
  matches as (
    -- search_fold_text is fold(name_ko) ' ' fold(name_en) ' ' and then the
    -- words of name_ko folded one by one; folds hold no spaces.
    select
      candidate.*,
      -- Every word as it was typed is in the name: the right spelling.
      not exists (
        select 1
        from said
        where not (
          candidate.search_typed_text like '%' || said.typed || '%'
          or case
            when said.styles is not null and candidate.style_key = any(said.styles) then
              exists (select 1 from said as other where other.styles is null)
              and not exists (
                select 1 from said as other
                where other.styles is null
                  and ' ' || candidate.search_fold_text not like '% ' || other.folded || '%'
              )
            else false
          end
        )
      ) as spelled,
      case
        when parts.name_run = (select folded from usable_input)
          or parts.latin_run = (select folded from usable_input) then 0
        -- The name begins with what was said: its first word begins with the
        -- first word said, and the name run together goes on as said. The
        -- run alone would also take "샤도네" from "샤또 네넹".
        when (
            split_part(parts.name_words, ' ', 1) like (select first_word from usable_input) || '%'
            and parts.name_run like (select folded from usable_input) || '%'
          )
          or parts.latin_run like (select folded from usable_input) || '%' then 1
        when ' ' || candidate.search_fold_text || ' ' like '% ' || (select folded from usable_input) || ' %' then 2
        when ' ' || candidate.search_fold_text like '% ' || (select folded from usable_input) || '%' then 3
        when candidate.search_fold_text like '%' || (select folded from usable_input) || '%' then 4
        when not exists (
          select 1 from said where candidate.search_fold_text not like '%' || said.folded || '%'
        ) then 5
        else 6
      end as place,
      -- Every word said is a whole word of the name, not the start of one.
      not exists (
        select 1 from said
        where ' ' || candidate.search_fold_text || ' ' not like '% ' || said.folded || ' %'
      ) as whole_words,
      -- A wine's name without its year: the years of one wine stay together.
      case
        when candidate.vintage_year is not null
          and right(candidate.name_ko, 4) = candidate.vintage_year::text
        then rtrim(left(candidate.name_ko, char_length(candidate.name_ko) - 4))
        else candidate.name_ko
      end as base_name
    from candidates as candidate
    cross join lateral (
      select
        split_part(candidate.search_fold_text, ' ', 1) as name_run,
        split_part(candidate.search_fold_text, ' ', 2) as latin_run,
        substr(
          candidate.search_fold_text,
          char_length(split_part(candidate.search_fold_text, ' ', 1))
            + char_length(split_part(candidate.search_fold_text, ' ', 2)) + 3
        ) as name_words
    ) as parts
    where not exists (
      select 1
      from said
      where not (
        case
          when said.begins_only then
            ' ' || candidate.search_fold_text like '% ' || said.folded || '%'
            or ' ' || candidate.producer_fold like '% ' || said.folded || '%'
            -- A short Latin word among others ("opus one", "moet et chandon").
            or (
              not target_word_starts and said.word_count > 1 and said.folded ~ '^[a-z]+$'
              and parts.latin_run like '%' || said.folded || '%'
            )
          else
            parts.name_words like '%' || said.folded || '%'
            or parts.latin_run like '%' || said.folded || '%'
            or (
              parts.name_run like '%' || said.folded || '%'
              and public.soolgyul_catalog_runs_from_word(parts.name_words, said.folded)
            )
            or candidate.producer_fold like '%' || said.folded || '%'
        end
        -- A word naming a style is met by the bottle's style, but only
        -- beside words that begin words of its name: "화이트 호스" is not
        -- a white wine that holds "호스" somewhere.
        or case
          when said.styles is not null and candidate.style_key = any(said.styles) then
            exists (select 1 from said as other where other.styles is null)
            and not exists (
              select 1 from said as other
              where other.styles is null
                and ' ' || candidate.search_fold_text not like '% ' || other.folded || '%'
            )
          else false
        end
      )
    )
    -- Or the words said, run together, are in the name as one word would
    -- be: a name parted where it is not ("닷 사이", "no 7" for "No.7").
    or (
      (select word_count > 1 from usable_input)
      and (
        parts.name_words like '%' || (select folded from usable_input) || '%'
        or parts.latin_run like '%' || (select folded from usable_input) || '%'
        or (
          parts.name_run like '%' || (select folded from usable_input) || '%'
          and public.soolgyul_catalog_runs_from_word(parts.name_words, (select folded from usable_input))
        )
      )
    )
  ),
  weighed as (
    select
      matches.*,
      case when signal.known then 3 else 0 end + ln(1 + coalesce(signal.picks, 0)) as weight,
      coalesce(signal.staple, false) as staple,
      bool_or(matches.spelled and matches.place <= 1) over () as some_name_begins_as_typed
    from matches
    left join public.catalog_search_signals as signal on signal.alcohol_item_id = matches.id
  ),
  page as (
    select
      weighed.*,
      -- The right spelling comes first. When no name begins as typed, a
      -- bottle people know whose name begins as the words sound stands with
      -- the spelled ones: "니카" is 닛카 before a wine that holds "니카시아".
      (
        weighed.spelled
        or (weighed.weight > 0 and weighed.place <= 1 and not weighed.some_name_begins_as_typed)
      ) as stands_first
    from weighed
    order by
      stands_first desc,
      (weighed.place = 0) desc,
      (weighed.place = 6),
      weighed.weight desc,
      weighed.spelled desc,
      weighed.place,
      weighed.staple desc,
      weighed.whole_words desc,
      char_length(weighed.base_name),
      weighed.base_name,
      weighed.vintage_year desc nulls last,
      weighed.name_ko,
      weighed.id
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
    region_term.label_ko as region,
    page.spelled
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
    page.stands_first desc,
    (page.place = 0) desc,
    (page.place = 6),
    page.weight desc,
    page.spelled desc,
    page.place,
    page.staple desc,
    page.whole_words desc,
    char_length(page.base_name),
    page.base_name,
    page.vintage_year desc nulls last,
    page.name_ko,
    page.id;
end
$$;
revoke all on function public.soolgyul_catalog_exact_matches(text, integer, integer, text[], text[], boolean) from public, anon, authenticated;


-- Two words that differ by one letter put in, left out or swapped for
-- another. Trigram closeness alone is too harsh on short words: "파쿠" and
-- "파크" share too few to pass, so a slip in a short word of a longer name
-- ("하이랜드 파쿠 18년") lost the whole search.
create function public.soolgyul_catalog_one_slip_apart(first_word text, second_word text)
returns boolean
language plpgsql immutable parallel safe
set search_path to ''
as $$
declare
  first_length integer := char_length(first_word);
  second_length integer := char_length(second_word);
  shorter integer := least(first_length, second_length);
  same_start integer := 0;
  same_end integer := 0;
begin
  if abs(first_length - second_length) > 1 then
    return false;
  end if;
  while same_start < shorter
    and substr(first_word, same_start + 1, 1) = substr(second_word, same_start + 1, 1) loop
    same_start := same_start + 1;
  end loop;
  while same_end < shorter - same_start
    and substr(first_word, first_length - same_end, 1) = substr(second_word, second_length - same_end, 1) loop
    same_end := same_end + 1;
  end loop;
  return same_start + same_end >= greatest(first_length, second_length) - 1;
end
$$;
revoke all on function public.soolgyul_catalog_one_slip_apart(text, text) from public, anon, authenticated;

-- A near match was scored against the whole name run together, so a word
-- could be pieced from the ends of two others ("맥칼란" from "알칼라 맥라렌").
-- Each word said is now compared with the single words of the name and of
-- the producer, every one of them has to be close (by its trigrams, or one
-- slip apart), and the known bottles come first among equally close ones.
create or replace function public.soolgyul_catalog_near_matches(
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
  perform extensions.show_trgm('');
  perform set_config('pg_trgm.word_similarity_threshold', '0.45', true);

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
    candidates as (
      select
        item.id, item.name_ko, item.name_en, item.alcohol_category_id, item.style_key,
        item.region_key, item.abv_percent, item.country_code,
        -- The fold keeps a Latin name as one run; its words are compared one
        -- by one too ("macalan" with "macallan", not with "macallanterra").
        string_to_array(item.search_fold_text || ' ' || coalesce(producer.search_fold_text, ''), ' ')
          || regexp_split_to_array(
            lower(
              coalesce(item.name_en, '') || ' ' || coalesce(producer.name_en, '')
              || ' ' || coalesce(producer.name_native, '')
            ),
            '[^[:alnum:]]+'
          ) as tokens
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
    ),
    scored as (
      select
        candidate.*,
        (
          select min(best.closeness)
          from unnest($1) as word
          cross join lateral (
            select max(greatest(
              extensions.similarity(word, token),
              -- One slip is close enough in a word of three syllables or so,
              -- and in a shorter one when other words are said with it: alone,
              -- "김치" would be answered with "끼지".
              case
                when char_length(word) >= case when cardinality($1) > 1 then 4 else 6 end
                  and public.soolgyul_catalog_one_slip_apart(word, token)
                then 0.5
                else 0
              end
            )) as closeness
            from unnest(candidate.tokens) as token
            -- A slip rarely falls on the first letter, and without this
            -- "헤네시" would be close to "테네시".
            where left(token, 1) = left(word, 1)
          ) as best
        )::real as weakest,
        (
          select sum(best.closeness)
          from unnest($1) as word
          cross join lateral (
            select max(greatest(
              extensions.similarity(word, token),
              -- One slip is close enough in a word of three syllables or so,
              -- and in a shorter one when other words are said with it: alone,
              -- "김치" would be answered with "끼지".
              case
                when char_length(word) >= case when cardinality($1) > 1 then 4 else 6 end
                  and public.soolgyul_catalog_one_slip_apart(word, token)
                then 0.5
                else 0
              end
            )) as closeness
            from unnest(candidate.tokens) as token
            -- A slip rarely falls on the first letter, and without this
            -- "헤네시" would be close to "테네시".
            where left(token, 1) = left(word, 1)
          ) as best
        )::real as near_score
      from candidates as candidate
    ),
    page as (
      select
        scored.*,
        case when signal.known then 3 else 0 end + ln(1 + coalesce(signal.picks, 0)) as weight,
        coalesce(signal.staple, false) as staple
      from scored
      left join public.catalog_search_signals as signal on signal.alcohol_item_id = scored.id
      where scored.weakest >= $8
      order by
        round(scored.near_score::numeric, 1) desc,
        case when signal.known then 3 else 0 end + ln(1 + coalesce(signal.picks, 0)) desc,
        coalesce(signal.staple, false) desc,
        scored.near_score desc,
        char_length(scored.name_ko),
        scored.name_ko,
        scored.id
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
      round(page.near_score::numeric, 1) desc,
      page.weight desc,
      page.staple desc,
      page.near_score desc,
      char_length(page.name_ko),
      page.name_ko,
      page.id
  $query$ using
    near_words,
    first_word, coalesce(first_producers, '{}'::uuid[]),
    second_word, coalesce(second_producers, '{}'::uuid[]),
    greatest(1, least(coalesce(target_limit, 20), 20)),
    greatest(0, least(coalesce(target_offset, 0), 1000)),
    0.45::real;
end
$$;

-- `match_kind` says how a row matched: the words as typed ('exact'), words
-- that sound the same ('sound'), or only something that looks like them
-- ('near'), so a screen can show the last as a guess.
create function public.soolgyul_search_alcohol_catalog(
  target_query text,
  target_limit integer default 20,
  target_offset integer default 0
) returns table(
  id uuid, name_ko text, name_en text, category_key text, style_key text,
  style_label text, abv_percent numeric, media_path text, country_code text,
  region text, match_kind text
)
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  plain_query text;
  kinds text[];
  countries text[];
  name_query text;
  reworded_query text;
  split_query text;
  page_limit integer := greatest(1, least(coalesce(target_limit, 20), 20));
  page_offset integer := greatest(0, least(coalesce(target_offset, 0), 1000));
begin
  -- "더" or "the" before a name is not looked for: people say "더 맥캘란"
  -- for bottles named "맥캘란 …", and "더 글렌리벳 …" is found without it.
  plain_query := regexp_replace(trim(coalesce(target_query, '')), '^(더|the)\s+', '', 'i');

  -- A name people use that no bottle is spelled with is looked for as what
  -- it means: all the words together, or one word among them.
  select coalesce(
    (
      select other.means
      from public.catalog_search_other_names as other
      where other.said = public.soolgyul_catalog_compact_text(plain_query)
    ),
    (
      select string_agg(coalesce(other.means, said.word), ' ' order by said.place)
      from regexp_split_to_table(plain_query, '\s+') with ordinality as said(word, place)
      left join public.catalog_search_other_names as other
        on other.said = public.soolgyul_catalog_compact_text(said.word)
      where said.word <> ''
    ),
    ''
  ) into plain_query;

  -- Words that name a kind of drink or a country narrow the search when a
  -- name is said too; alone they list the bottles people know and pick.
  -- When the narrowed search finds nothing, every word is looked for in the
  -- names as before.
  select
    array_agg(distinct public.soolgyul_catalog_kind_of_word(word))
      filter (where public.soolgyul_catalog_kind_of_word(word) is not null),
    array_agg(distinct public.soolgyul_catalog_country_of_word(word))
      filter (where public.soolgyul_catalog_country_of_word(word) is not null),
    string_agg(word, ' ' order by place)
      filter (where public.soolgyul_catalog_kind_of_word(word) is null
        and public.soolgyul_catalog_country_of_word(word) is null)
  into kinds, countries, name_query
  from regexp_split_to_table(plain_query, '\s+') with ordinality as said(word, place)
  where word <> '';

  if (kinds is not null or countries is not null) and name_query is null then
    return query
      select
        item.id, item.name_ko, item.name_en, category.category_key, item.style_key,
        coalesce(style_term.label_ko, category.name_ko), item.abv_percent,
        (
          select media.media_path
          from public.catalog_media_assets as media
          where media.alcohol_item_id = item.id
            and media.publish_status = 'published'
            and media.published_at is not null
        ),
        item.country_code, region_term.label_ko, 'exact'::text
      from public.catalog_search_signals as signal
      join public.alcohol_items as item on item.id = signal.alcohol_item_id
      join public.alcohol_categories as category on category.id = item.alcohol_category_id
      left join public.catalog_taxonomy as style_term
        on style_term.term_type = 'style' and style_term.term_key = item.style_key and style_term.is_active
      left join public.catalog_taxonomy as region_term
        on region_term.term_type = 'region' and region_term.term_key = item.region_key
      where item.publish_status = 'published'
        and category.is_active
        and (kinds is null or category.category_key = any(kinds))
        and (countries is null or item.country_code = any(countries))
        and (signal.known or signal.picks > 0)
      -- One maker's bottles do not fill the list: each maker's first
      -- bottle comes before anyone's second.
      order by
        row_number() over (
          partition by item.producer_id
          order by
            case when signal.known then 3 else 0 end + case when signal.staple then 1 else 0 end + ln(1 + signal.picks) desc,
            item.name_ko
        ),
        case when signal.known then 3 else 0 end + case when signal.staple then 1 else 0 end + ln(1 + signal.picks) desc,
        item.name_ko,
        item.id
      limit page_limit
      offset page_offset;
    if found or page_offset > 0 then
      return;
    end if;
  end if;

  -- A bottle named exactly as said is what is asked for, whatever kind or
  -- country its words name ("오미로제 스파클링 와인").
  if (kinds is not null or countries is not null) and name_query is not null and not exists (
    select 1
    from public.alcohol_items as item
    where item.publish_status = 'published'
      and (
        item.search_fold_text like public.soolgyul_fold_korean_sound(plain_query) || ' %'
        or item.search_fold_text like '% ' || public.soolgyul_fold_korean_sound(plain_query) || ' %'
      )
  ) and exists (
    select 1 from public.soolgyul_catalog_exact_matches(name_query, 1, 0, kinds, countries)
  ) then
    return query
      select found.id, found.name_ko, found.name_en, found.category_key, found.style_key,
             found.style_label, found.abv_percent, found.media_path, found.country_code,
             found.region, case when found.spelled then 'exact' else 'sound' end
      from public.soolgyul_catalog_exact_matches(name_query, page_limit, page_offset, kinds, countries) as found;
    return;
  end if;

  return query
    select found.id, found.name_ko, found.name_en, found.category_key, found.style_key,
           found.style_label, found.abv_percent, found.media_path, found.country_code,
           found.region, case when found.spelled then 'exact' else 'sound' end
    from public.soolgyul_catalog_exact_matches(plain_query, page_limit, page_offset) as found;
  if found then
    return;
  end if;
  -- An empty page past the first may still follow matches of this kind;
  -- the kinds below never mix with them.
  if page_offset > 0 and exists (
    select 1 from public.soolgyul_catalog_exact_matches(plain_query, 1, 0)
  ) then
    return;
  end if;

  -- Nothing is named as typed: the same words said another way.
  reworded_query := public.soolgyul_catalog_reworded_query(plain_query);
  if reworded_query is distinct from plain_query and exists (
    select 1 from public.soolgyul_catalog_exact_matches(reworded_query, 1, 0)
  ) then
    return query
      select found.id, found.name_ko, found.name_en, found.category_key, found.style_key,
             found.style_label, found.abv_percent, found.media_path, found.country_code,
             found.region, case when found.spelled then 'exact' else 'sound' end
      from public.soolgyul_catalog_exact_matches(reworded_query, page_limit, page_offset) as found;
    return;
  end if;

  return query
    select found.*, 'near'::text
    from public.soolgyul_catalog_near_matches(plain_query, page_limit, page_offset) as found;
  if found then
    return;
  end if;
  if page_offset > 0 and exists (
    select 1 from public.soolgyul_catalog_near_matches(plain_query, 1, 0)
  ) then
    return;
  end if;

  -- Two names shortened and run together ("조니블랙"): parted in two, each
  -- part has to begin a word of the name. Answered as a guess, and only
  -- when nothing looks like the word as a whole.
  if plain_query ~ '^[가-힣]{4,8}$' then
    for cut in 2 .. char_length(plain_query) - 2 loop
      split_query := left(plain_query, cut) || ' ' || substr(plain_query, cut + 1);
      if exists (
        select 1 from public.soolgyul_catalog_exact_matches(split_query, 1, 0, null, null, true)
      ) then
        return query
          select found.id, found.name_ko, found.name_en, found.category_key, found.style_key,
                 found.style_label, found.abv_percent, found.media_path, found.country_code,
                 found.region, 'near'::text
          from public.soolgyul_catalog_exact_matches(split_query, page_limit, page_offset, null, null, true) as found;
        return;
      end if;
    end loop;
  end if;
end
$$;
revoke all on function public.soolgyul_search_alcohol_catalog(text, integer, integer) from public;
grant execute on function public.soolgyul_search_alcohol_catalog(text, integer, integer) to service_role, anon, authenticated;

create function public.soolgyul_search_alcohol_catalog_batch(
  target_queries text[],
  target_limit integer default 10
) returns table(
  query_index integer, id uuid, name_ko text, name_en text, category_key text,
  style_key text, style_label text, abv_percent numeric, media_path text,
  country_code text, region text, match_kind text
)
language sql stable security definer
set search_path to ''
as $$
  select
    asked.place::integer,
    found.id, found.name_ko, found.name_en, found.category_key,
    found.style_key, found.style_label, found.abv_percent, found.media_path,
    found.country_code, found.region, found.match_kind
  from unnest(target_queries[1:8]) with ordinality as asked(words, place)
  cross join lateral public.soolgyul_search_alcohol_catalog(
    asked.words, target_limit, 0
  ) with ordinality as found(
    id, name_ko, name_en, category_key, style_key, style_label, abv_percent,
    media_path, country_code, region, match_kind, place
  )
  order by asked.place, found.place
$$;
revoke all on function public.soolgyul_search_alcohol_catalog_batch(text[], integer) from public;
grant execute on function public.soolgyul_search_alcohol_catalog_batch(text[], integer) to service_role, anon, authenticated;

-- Drinks the catalog does not carry, by the words people type for them. A
-- search for one says so instead of answering with a bottle whose name only
-- sounds alike.
create table public.catalog_unlisted_terms (
  term text primary key check (term = public.soolgyul_catalog_compact_text(term) and term <> ''),
  kind text not null check (kind in (
    'beer', 'soju', 'liqueur', 'gin', 'vodka', 'rum', 'tequila', 'brandy', 'baijiu',
    -- A well-known bottle of a kind the catalog carries that is not in it yet.
    'not_listed'
  ))
);
alter table public.catalog_unlisted_terms enable row level security;
revoke all on table public.catalog_unlisted_terms from public, anon, authenticated;
grant all on table public.catalog_unlisted_terms to service_role;

insert into public.catalog_unlisted_terms (term, kind)
select public.soolgyul_catalog_compact_text(word), kind
from (values
  ('beer', '맥주 비어 beer 라거 생맥주 수제맥주 카스 테라 하이트 켈리 클라우드 크러시 필라이트 필굿 기네스 하이네켄 아사히 삿포로 기린 칭따오 버드와이저 버드와이져 코로나 호가든 스텔라 스텔라아르투아 블랑 필스너우르켈 코젤 에델바이스 파울라너 에딩거 칼스버그 산미구엘 타이거 곰표 제주맥주 블루문 듀벨 레페'),
  ('soju', '참이슬 처음처럼 진로이즈백 새로 좋은데이 한라산 대선 잎새주 참소주 맛있는참 이제우린 자몽에이슬'),
  ('liqueur', '리큐르 리큐어 깔루아 베일리스 예거마이스터 말리부 아페롤 캄파리 디사론노 코인트로 그랑마니에르 샤르트뢰즈 미도리 피치트리 베네딕틴 드람뷔 볼스 트리플섹 압생트'),
  ('gin', '봄베이 봄베이사파이어 탱커레이 헨드릭스 고든스 비피터 몽키47 로쿠 더보타니스트 시타델 플리머스'),
  ('vodka', '보드카 앱솔루트 스미노프 그레이구스 벨베디어 스톨리치나야 케틀원 스카이보드카 벨루가'),
  ('rum', '럼주 바카디 캡틴모건 하바나클럽 디플로마티코 자카파 플랜테이션 마운트게이 말리부럼'),
  ('tequila', '데킬라 테킬라 메즈칼 호세쿠엘보 쿠엘보 돈훌리오 패트론 클라세아줄 에스폴론 카사미고스 올메카 사우자'),
  ('brandy', '브랜디 코냑 꼬냑 헤네시 레미마틴 까뮤 마르텔 꾸브와제 칼바도스 아르마냑 메타사'),
  ('baijiu', '고량주 백주 바이주 연태고량주 연태 마오타이 공부가주 우량예 수정방 이과두주 노주노교 양하대곡 죽엽청주 소흥주'),
  ('not_listed', '청하 백화수복 설중매 이강주 금정산성 문경바람 담솔 고운달 표문 백걸리 팔팔')
) as listed(kind, words)
cross join lateral regexp_split_to_table(listed.words, '\s+') as word
on conflict (term) do nothing;

-- Names people use for a bottle or a maker that no name in the catalog is
-- spelled with: a nickname ("와턱"), a name read another way ("겟케이칸" for
-- 월계관), a spelling the market uses ("빌라엠"). A search for one looks for
-- what it means.
create table public.catalog_search_other_names (
  said text primary key check (said = public.soolgyul_catalog_compact_text(said) and said <> ''),
  means text not null check (btrim(means) <> '')
);
alter table public.catalog_search_other_names enable row level security;
revoke all on table public.catalog_search_other_names from public, anon, authenticated;
grant all on table public.catalog_search_other_names to service_role;

insert into public.catalog_search_other_names (said, means) values
  ('빌라엠', '빌라 M'),
  ('겟케이칸', '월계관'),
  ('죠젠미즈노고토시', '상선여수'),
  ('조젠미즈노고토시', '상선여수'),
  ('와턱', '와일드 터키'),
  ('메막', '메이커스 마크'),
  ('버트', '버팔로 트레이스')
on conflict (said) do nothing;

-- What a search screen asks: the matches and, when the words name a drink
-- the catalog does not carry, its kind. The words name one when all of them
-- together, or the first of them, is on the list ("호세 쿠엘보", "헤네시 xo");
-- a listed word further on ("미오 후레쉬") does not, and neither does a word
-- that leads the name of a bottle the catalog carries ("테라", "기린"). Such
-- a drink said alone ("카스") is answered with no bottle at all, since a name
-- that merely holds the word ("카스텔로 …") is not what was asked for; with
-- more words after it, only bottles spelled that way are answered, never the
-- like-sounding or the look-alike.
create function public.soolgyul_search_catalog(
  target_query text,
  target_limit integer default 20,
  target_offset integer default 0
) returns jsonb
language sql stable security definer
set search_path to ''
as $$
  with said as (
    select
      public.soolgyul_catalog_compact_text(target_query) as whole,
      public.soolgyul_catalog_compact_text(
        split_part(trim(coalesce(target_query, '')), ' ', 1)
      ) as first_word
  ),
  not_carried as (
    select unlisted.kind, unlisted.term = said.whole as said_alone
    from public.catalog_unlisted_terms as unlisted, said
    where (unlisted.term = said.whole or unlisted.term = said.first_word)
      and not exists (
        select 1
        from public.alcohol_items as item
        where item.publish_status = 'published'
          and public.soolgyul_catalog_compact_text(split_part(item.name_ko, ' ', 1)) = unlisted.term
      )
    order by char_length(unlisted.term) desc, unlisted.term
    limit 1
  ),
  found as (
    select row_number() over () as place, match.*
    from public.soolgyul_search_alcohol_catalog(target_query, target_limit, target_offset) as match
  )
  select jsonb_build_object(
    'not_carried', (select kind from not_carried),
    'results', coalesce((
      select jsonb_agg(to_jsonb(found) - 'place' order by found.place)
      from found
      where not exists (select 1 from not_carried)
        or (found.match_kind = 'exact' and not (select said_alone from not_carried))
    ), '[]'::jsonb)
  );
$$;
revoke all on function public.soolgyul_search_catalog(text, integer, integer) from public;
grant execute on function public.soolgyul_search_catalog(text, integer, integer) to service_role, anon, authenticated;

-- How many members picked, opened the fit of, or recorded each bottle in the
-- last ninety days. A member counts once per bottle; visitors do not count,
-- so nobody raises a bottle by asking again and again.
create function public.soolgyul_refresh_catalog_search_picks() returns void
language sql security definer
set search_path to ''
as $$
  with counted as (
    select picked.alcohol_item_id, count(distinct picked.user_id)::integer as picks
    from (
      select event.alcohol_item_id, event.user_id
      from public.drink_discovery_events as event
      where event.occurred_at > now() - interval '90 days'
        and event.user_id is not null
        and event.alcohol_item_id is not null
        and event.kind in ('search_pick', 'label_match', 'fit_view')
      union all
      select record.alcohol_item_id, record.user_id
      from public.drink_records as record
      where record.created_at > now() - interval '90 days'
        and record.user_id is not null
        and record.deleted_at is null
    ) as picked
    group by picked.alcohol_item_id
  ),
  forgotten as (
    update public.catalog_search_signals as signal
    set picks = 0, updated_at = now()
    where signal.picks > 0
      and not exists (
        select 1 from counted where counted.alcohol_item_id = signal.alcohol_item_id
      )
  )
  insert into public.catalog_search_signals (alcohol_item_id, picks)
  select counted.alcohol_item_id, counted.picks
  from counted
  join public.alcohol_items as item on item.id = counted.alcohol_item_id
  on conflict (alcohol_item_id) do update
    set picks = excluded.picks, updated_at = now()
    where public.catalog_search_signals.picks is distinct from excluded.picks;
$$;
revoke all on function public.soolgyul_refresh_catalog_search_picks() from public, anon, authenticated;
grant execute on function public.soolgyul_refresh_catalog_search_picks() to service_role;

select cron.schedule('soolgyul-search-picks', '10 19 * * *',
  'select public.soolgyul_refresh_catalog_search_picks();');
