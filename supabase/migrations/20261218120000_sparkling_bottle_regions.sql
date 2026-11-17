-- Sparkling bottles recorded at the province where their wine is an appellation of its own.
-- 프란치아코르타, 트렌토독 and 프로세코 are read from the bottle's region, so a bottle that states only
-- 롬바르디아 or 트렌티노 알토 아디제 lost its style when those styles moved to their own places.
-- Two Gancia bottles were recorded in 롬바르디아; the house is in 피에몬테.
-- A bottle is moved only while it still holds the region it was checked with.
begin;

create temporary table bottle_region (id uuid primary key, old_key text not null, new_key text not null) on commit drop;
insert into bottle_region (id, old_key, new_key) values
  -- 프란치아코르타
  ('73fc6bcf-97fd-5539-bf63-73b8a75a270c', 'it_lombardia', 'it_franciacorta'),  -- 까델 보스코 빈티지 컬렉션 도자쥬 제로
  ('c957e728-aff9-55c5-96d5-ad7db824481c', 'it_lombardia', 'it_franciacorta'),  -- 까델 보스코 빈티지 컬렉션 브뤼
  ('50f48d55-5216-5aa5-b175-fc36319c3065', 'it_lombardia', 'it_franciacorta'),  -- 까델 보스코 프란치아코르타 뀌베 프레스티지 로제
  ('9a976ee1-63ae-50dd-ab30-6613394a7efd', 'it_lombardia', 'it_franciacorta'),  -- 까델 보스코 프란치아코르타 빈티지 컬렉션 도자쥬 제로 2002
  ('7505047e-5668-5111-8be1-e02862493f21', 'it_lombardia', 'it_franciacorta'),  -- 까델 보스코 프란치아코르타 빈티지 컬렉션 도자쥬 제로 2008
  ('6c6f61a9-0b26-5ac5-b894-4d047888b0c2', 'it_lombardia', 'it_franciacorta'),  -- 까델 보스코 프란치아코르타 빈티지 컬렉션 엑스트라 브뤼
  ('ababb8db-82bc-5601-99b9-1e0d7a50b340', 'it_lombardia', 'it_franciacorta'),  -- 벨라비스타 넥타
  ('7a079da4-5826-592b-b313-f365422c514e', 'it_lombardia', 'it_franciacorta'),  -- 벨라비스타 라 스칼라 2008
  ('8a7fcc16-383c-598f-bf74-5e1a39cdaba3', 'it_lombardia', 'it_franciacorta'),  -- 벨라비스타 라 스칼라 2012
  ('4a5db2e1-6063-5318-a1ea-57d0a5e95859', 'it_lombardia', 'it_franciacorta'),  -- 벨라비스타 라 스칼라 2015
  ('53a7c21f-a597-5316-9f5a-11f83a10dcae', 'it_lombardia', 'it_franciacorta'),  -- 벨라비스타 로제 2008
  ('f2aa23f9-a0c8-56e8-a9de-3d95438c8540', 'it_lombardia', 'it_franciacorta'),  -- 벨라비스타 로제 2014
  ('87a0c42d-448a-5ce9-8456-9552527fe81a', 'it_lombardia', 'it_franciacorta'),  -- 벨라비스타 사텐 2009
  ('9d26b9ae-63ac-53cc-ac12-2c4d7d926737', 'it_lombardia', 'it_franciacorta'),  -- 벨라비스타 사텐 2013
  ('b2925630-951f-5094-990d-257122b2397b', 'it_lombardia', 'it_franciacorta'),  -- 벨라비스타 알마 그랑 뀌베
  ('edeb6e72-f0a5-525c-8746-913aa16d824b', 'it_lombardia', 'it_franciacorta'),  -- 벨라비스타 알마 아상블라주 1
  ('18114e1c-8804-5a27-b1c7-4a0226936d77', 'it_lombardia', 'it_franciacorta'),  -- 안티노리 몬테니자 디제로
  ('cb026ca4-3133-5d23-881a-8e5a00ab1caf', 'it_lombardia', 'it_franciacorta'),  -- 안티노리 몬테니자 리제르바 콘테사 마지
  ('840aba2a-7f19-56fd-b27e-c27a80d57b6b', 'it_lombardia', 'it_franciacorta'),  -- 안티노리 몬테니자 브뤼
  ('c784522a-39ed-5a4f-9b41-e11ea33d84f4', 'it_lombardia', 'it_franciacorta'),  -- 안티노리 몬테니자 사텐 밀레지마토
  -- 트렌토
  ('0785f1b9-4f90-5fee-a545-af7113104906', 'it_trentino_alto_adige', 'it_trento'),  -- 로타리 브뤼 리제르바
  ('0f587257-34a0-51c2-a6dc-9d8aaecd5fc2', 'it_trentino_alto_adige', 'it_trento'),  -- 로타리 탈렌토 뀌베 28
  ('a391b9c4-c320-5bbb-82dc-f67f76f63482', 'it_trentino_alto_adige', 'it_trento'),  -- 지울리오 페라리 리제르바 2006
  ('ee34f353-a49f-5183-bed9-6d30ca01aa42', 'it_trentino_alto_adige', 'it_trento'),  -- 지울리오 페라리 리제르바 2008
  ('2d3bd9b0-8934-51e2-9921-acfd6f5eac2a', 'it_trentino_alto_adige', 'it_trento'),  -- 페라리 로제
  ('c13172e0-1c6e-5d32-adbe-9436f258b62f', 'it_trentino_alto_adige', 'it_trento'),  -- 페라리 브뤼
  ('3263ad0a-99fa-5d4c-9679-b115678b443b', 'it_trentino_alto_adige', 'it_trento'),  -- 페라리 페를
  -- 프로세코
  ('bcc2f68f-473d-57fa-ab23-2c273790ae01', 'it_veneto', 'it_prosecco'),  -- 마소트 마르나 블루
  ('56630112-0bcf-5925-9e2e-26216e771058', 'it_veneto', 'it_prosecco'),  -- 발리에띠 스푸만테 엑스트라 드라이
  ('431eae8f-3f18-5d16-8ab0-1017f4b595a5', 'it_treviso', 'it_prosecco'),  -- 안드레올라 P. 디 트레비소 베르브 엑스트라 드라이
  -- 피에몬테
  ('94d8b9b3-5e35-5c10-8880-7f3a79bff5ec', 'it_lombardia', 'it_piemonte'),  -- 간치아 플래티늄 카를로 간치아
  ('5f353586-c6dc-53ca-b86f-1845a9298275', 'it_lombardia', 'it_piemonte');  -- 간치아 피닌파리나 로제

update public.alcohol_items as item
   set region_key = moved.new_key
  from bottle_region as moved
 where item.id = moved.id
   and item.region_key = moved.old_key;

commit;
