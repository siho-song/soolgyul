-- Region rows the 2026-11-09 catalog field check needed: products whose real
-- appellation (Roero, Ballard Canyon, Hemel-en-Aarde, Chiroubles and others)
-- had no row sat on a broader one. Three keys spelled wrong since the region
-- tree was built (Yorville, Cholchagua, Extremandura) get their right key and
-- English name: the new row goes in, children and products move, the old row
-- goes. The rows come from the dictionary (catalog/dictionary/terms.json);
-- products move to the new rows in the catalog sync.

begin;

insert into public.catalog_taxonomy (
  term_type, term_key, label_ko, label_en, synonyms, parent_term_key,
  applicable_sections, metadata, taxonomy_version, sort_order, is_active
)
values
  ('region', 'cl_colchagua_valley', '콜차구아 밸리', 'Colchagua Valley', array[]::text[], 'cl_rapel_valley', array['region']::text[], '{}'::jsonb, '2.0.0', 1390, true),
  ('region', 'es_extremadura', '에스트레마두라', 'Extremadura', array[]::text[], 'es', array['region']::text[], '{}'::jsonb, '2.0.0', 1950, true),
  ('region', 'us_yorkville_highlands', '요크빌 하이랜즈', 'Yorkville Highlands', array[]::text[], 'us_mendocino_county', array['region']::text[], '{}'::jsonb, '2.0.0', 9230, true),
  ('region', 'ar_neuquen', '네우켄', 'Neuquen', array[]::text[], 'ar_patagonia', array['region']::text[], '{}'::jsonb, '2.0.0', 9500, true),
  ('region', 'it_colli_orientali_del_friuli', '콜리 오리엔탈리 델 프리울리', 'Colli Orientali del Friuli', array[]::text[], 'it_friuli_venezia_giulia', array['region']::text[], '{}'::jsonb, '2.0.0', 9510, true),
  ('region', 'fr_massif_de_saint_thierry', '마시프 드 생티에리', 'Massif de Saint-Thierry', array[]::text[], 'fr_champagne', array['region']::text[], '{}'::jsonb, '2.0.0', 9520, true),
  ('region', 'it_roero', '로에로', 'Roero', array[]::text[], 'it_piemonte', array['region']::text[], '{}'::jsonb, '2.0.0', 9530, true),
  ('region', 'us_ballard_canyon', '발라드 캐니언', 'Ballard Canyon', array[]::text[], 'us_santa_ynez_valley', array['region']::text[], '{}'::jsonb, '2.0.0', 9540, true),
  ('region', 'fr_minervois_la_liviniere', '미네르부아 라 리비니에르', 'Minervois-La Livinière', array[]::text[], 'fr_minervois', array['region']::text[], '{}'::jsonb, '2.0.0', 9550, true),
  ('region', 'us_petaluma_gap', '페탈루마 갭', 'Petaluma Gap', array[]::text[], 'us_sonoma_coast', array['region']::text[], '{}'::jsonb, '2.0.0', 9560, true),
  ('region', 'za_hemel_en_aarde', '헤멜 엔 아르데', 'Hemel-en-Aarde', array[]::text[], 'za_walker_bay', array['region']::text[], '{}'::jsonb, '2.0.0', 9570, true),
  ('region', 'fr_chiroubles', '시루블', 'Chiroubles', array[]::text[], 'fr_beaujolais', array['region']::text[], '{}'::jsonb, '2.0.0', 9580, true),
  ('region', 'fr_coteaux_du_lyonnais', '꼬또 뒤 리오네', 'Coteaux du Lyonnais', array[]::text[], 'fr_beaujolais', array['region']::text[], '{}'::jsonb, '2.0.0', 9590, true),
  ('region', 'us_fort_ross_seaview', '포트 로스 시뷰', 'Fort Ross-Seaview', array[]::text[], 'us_sonoma_coast', array['region']::text[], '{}'::jsonb, '2.0.0', 9600, true),
  ('region', 'fr_collines_rhodaniennes', '콜린 로다니엔', 'Collines Rhodaniennes', array[]::text[], 'fr_rhone', array['region']::text[], '{}'::jsonb, '2.0.0', 9610, true),
  ('region', 'nz_waitaki_valley', '와이타키 밸리', 'Waitaki Valley', array[]::text[], 'nz_south_island', array['region']::text[], '{}'::jsonb, '2.0.0', 9620, true)
on conflict (term_type, term_key) do nothing;

update public.catalog_taxonomy set parent_term_key = 'cl_colchagua_valley'
  where term_type = 'region' and parent_term_key = 'cl_cholchagua_valley';
update public.alcohol_items set region_key = 'cl_colchagua_valley' where region_key = 'cl_cholchagua_valley';
update public.alcohol_items set region_key = 'es_extremadura' where region_key = 'es_extremandura';
update public.alcohol_items set region_key = 'us_yorkville_highlands' where region_key = 'us_yorville_highlands';
delete from public.catalog_taxonomy
  where term_type = 'region' and term_key in ('cl_cholchagua_valley', 'es_extremandura', 'us_yorville_highlands');

commit;
