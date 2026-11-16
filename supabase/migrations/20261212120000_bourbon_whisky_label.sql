-- 버번 was the one whisky style named without 위스키 (싱글 몰트 위스키, 라이
-- 위스키, ...), so a card said only 버번. The short name stays a synonym.

update public.catalog_taxonomy
   set label_ko = '버번 위스키',
       synonyms = array['bourbon whisky', '버번']::text[]
 where term_type = 'style'
   and term_key = 'bourbon';
