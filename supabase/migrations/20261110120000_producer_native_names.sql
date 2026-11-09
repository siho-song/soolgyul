-- 2026-11-10: a sake label shows its brand in Japanese (風の森, 獺祭), and
-- the label photo search reads it, but the catalog held Korean and romaji
-- names only. Producers get the name as printed on the label, name_native,
-- and it joins the producer's folded search text, so a Japanese word in a
-- query matches through the producer like any other word. The fold used to
-- strip every character outside digits, Latin letters and Hangul; it now
-- keeps Japanese script (kana, kanji, 々 〆 ー) unchanged. alcohol_items keeps
-- its stored fold as is: no published name holds Japanese script that the
-- old fold removed except a single item, and a product matches through its
-- producer's native name.

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
  -- Japanese kana and kanji (and the marks 々 〆 ー) are kept so a label's
  -- native brand name can be searched; they pass through unchanged. The
  -- middle dot ・ and other kana punctuation are dropped like any symbol.
  base := regexp_replace(base, '[^0-9a-z가-힣぀-ゟァ-ヺー一-鿿々〆]+', '', 'g');
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

alter table public.producers
  add column name_native text
    constraint producers_name_native_check check (name_native is null or btrim(name_native) <> '');

comment on column public.producers.name_native is
  'The producer''s name in its own script as printed on the label (Japanese for sake: brand 銘柄 or brewery 蔵元, whichever name_en names); null when not collected.';

-- The generated column cannot be altered in place: rebuild it with the native name.
drop index if exists public.producers_search_fold_trgm_idx;
alter table public.producers drop column search_fold_text;
alter table public.producers
  add column search_fold_text text generated always as (
    public.soolgyul_fold_korean_sound(coalesce(name_ko, ''))
    || ' ' || public.soolgyul_fold_korean_sound(coalesce(name_en, ''))
    || ' ' || public.soolgyul_fold_korean_sound(coalesce(name_native, ''))
  ) stored;

create index producers_search_fold_trgm_idx
  on public.producers using gin (search_fold_text extensions.gin_trgm_ops);
