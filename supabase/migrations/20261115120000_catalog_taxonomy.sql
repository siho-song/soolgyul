-- catalog_terms becomes catalog_taxonomy. The dictionary file
-- catalog/dictionary/terms.json is the single source of prose: sensory
-- descriptions and trait keys leave the table (the card function reads its
-- bundled copy of the file), the sensory_dimension rows and card_label_ko go
-- with them, and the table keeps only the classification skeleton the
-- database searches and validates with: the region tree, style, ingredient,
-- process and maturation keys, and sensory_descriptor keys for tag checks.
-- The style, ingredient, process and maturation rows were originally seeded
-- by a file outside the migrations, so a database built from migrations alone
-- lacked them; they are inserted here from the dictionary projection
-- (tools/catalog/enrichment/materialize_catalog_terms.py), which also adds the
-- twelve fruit ingredients the dictionary gained after that seed. Existing
-- rows are left untouched (on conflict do nothing).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

-- (1) prose and its guards leave the table. Row changes run with the
-- deferred assignment check paused: a pending deferred event would block the
-- DDL below (Postgres refuses ALTER TABLE with pending trigger events), and
-- the check needs active alcohol_categories rows, which a database built from
-- migrations alone does not have. The live database does, and already holds
-- every classification row but the twelve fruit ingredients; those rows are
-- the assignment contract the check enforces
-- (supabase/functions/_shared/catalog/assignment_contract.json).
alter table public.catalog_terms
  drop constraint catalog_terms_sensory_knowledge_check,
  drop constraint catalog_terms_dimension_knowledge_check,
  drop constraint catalog_terms_card_label_check,
  drop column card_label_ko,
  disable trigger catalog_terms_assignment_validate;
drop function public.soolgyul_sensory_knowledge_is_valid(jsonb);

delete from public.catalog_terms where term_type = 'sensory_dimension';

alter table public.catalog_terms
  drop constraint catalog_terms_term_type_check,
  add constraint catalog_terms_term_type_check check (
    term_type = any (array['classification', 'style', 'ingredient', 'process', 'maturation',
                           'sensory_descriptor', 'region'])
  );

update public.catalog_terms
set metadata = metadata - 'sensory_description' - 'sensory_trait_keys'
where metadata ?| array['sensory_description', 'sensory_trait_keys'];

-- (2) the classification rows the migrations never carried; parents come
-- first in the list, and the deferred parent check is settled right away so
-- the rename below sees no pending events.
insert into public.catalog_terms (
  term_type, term_key, label_ko, label_en, synonyms, parent_term_key,
  applicable_sections, metadata, taxonomy_version, sort_order, is_active
)
select term_type, term_key, label_ko, label_en, synonyms, parent_term_key,
       applicable_sections, metadata, taxonomy_version, sort_order, is_active
from jsonb_to_recordset('[{"term_type":"style","term_key":"red_wine","label_ko":"레드 와인","label_en":"Red wine","synonyms":["red","레드"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["wine"],"category_key":"wine","definition":"Wine whose reviewed primary presentation is red wine."},"taxonomy_version":"2.0.0","sort_order":10,"is_active":true},{"term_type":"style","term_key":"white_wine","label_ko":"화이트 와인","label_en":"White wine","synonyms":["white","화이트"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["wine"],"category_key":"wine","definition":"Wine whose reviewed primary presentation is white wine."},"taxonomy_version":"2.0.0","sort_order":20,"is_active":true},{"term_type":"style","term_key":"rose_wine","label_ko":"로제 와인","label_en":"Rosé wine","synonyms":["rose","rosé","로제"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["wine"],"category_key":"wine","definition":"Wine whose reviewed primary presentation is rosé wine."},"taxonomy_version":"2.0.0","sort_order":30,"is_active":true},{"term_type":"style","term_key":"sparkling_wine","label_ko":"스파클링 와인","label_en":"Sparkling wine","synonyms":["발포성 와인","스파클링"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["wine"],"category_key":"wine","definition":"Wine supported as sparkling by product evidence; production method remains a separate facet.","definition_source":"OIV International Code of Oenological Practices, special wines","source_standard_url":"https://www.oiv.int/standards/international-code-of-oenological-practices/part-i-definitions/special-wines"},"taxonomy_version":"2.0.0","sort_order":40,"is_active":true},{"term_type":"style","term_key":"fortified_wine","label_ko":"주정강화 와인","label_en":"Fortified wine","synonyms":["주정 강화","포티파이드 와인"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["wine"],"category_key":"wine","definition":"Wine supported as fortified or liqueur wine by product evidence.","definition_source":"OIV International Code of Oenological Practices, liqueur wine and fortification","source_standard_url":"https://www.oiv.int/standards/international-code-of-oenological-practices/part-i-definitions/special-wines"},"taxonomy_version":"2.0.0","sort_order":50,"is_active":true},{"term_type":"style","term_key":"orange_wine","label_ko":"오렌지 와인","label_en":"Orange wine","synonyms":["스킨 콘택트 화이트","앰버 와인"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["wine"],"category_key":"wine","definition":"White-grape wine supported as made with extended pomace contact; color alone is insufficient.","definition_source":"OIV definition of white wine with maceration","source_standard_url":"https://www.oiv.int/standards/international-code-of-oenological-practices/part-i-definitions/special-wines"},"taxonomy_version":"2.0.0","sort_order":60,"is_active":true},{"term_type":"style","term_key":"single_malt_whisky","label_ko":"싱글 몰트 위스키","label_en":"Single malt whisky","synonyms":["american single malt","American single malt whisky","single malt","싱글몰트","아메리칸 싱글 몰트 위스키","아메리칸 싱글몰트"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["whisky"],"category_key":"whisky","definition":"Whisky explicitly identified as single malt under its applicable jurisdiction or producer claim."},"taxonomy_version":"2.0.0","sort_order":70,"is_active":true},{"term_type":"style","term_key":"grain_whisky","label_ko":"그레인 위스키","label_en":"Grain whisky","synonyms":["blended grain","Blended grain whisky","single grain","Single grain whisky","블렌디드 그레인","블렌디드 그레인 위스키","싱글 그레인 위스키","싱글그레인"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["whisky"],"category_key":"whisky","definition":"싱글 그레인과 블렌디드 그레인의 서비스 대표 계열. 버번·라이·위트·콘은 곡물 원료라는 이유로 이 계열에 합치지 않는다."},"taxonomy_version":"2.0.0","sort_order":80,"is_active":true},{"term_type":"style","term_key":"blended_whisky","label_ko":"블렌디드 위스키","label_en":"Blended whisky","synonyms":["blended","블렌디드"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["whisky"],"category_key":"whisky","definition":"Whisky explicitly identified as a blend; component types are separate facets when known."},"taxonomy_version":"2.0.0","sort_order":90,"is_active":true},{"term_type":"style","term_key":"bourbon","label_ko":"버번","label_en":"Bourbon","synonyms":["bourbon whisky","버번 위스키"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["whisky"],"category_key":"whisky","definition":"Whisky explicitly designated bourbon under applicable labeling rules."},"taxonomy_version":"2.0.0","sort_order":100,"is_active":true},{"term_type":"style","term_key":"blended_malt_whisky","label_ko":"블렌디드 몰트 위스키","label_en":"Blended malt whisky","synonyms":["blended malt","블렌디드 몰트"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["whisky"],"category_key":"whisky","definition":"A blend explicitly identified as composed of malt whiskies from more than one distillery."},"taxonomy_version":"2.0.0","sort_order":110,"is_active":true},{"term_type":"style","term_key":"rye_whisky","label_ko":"라이 위스키","label_en":"Rye whisky","synonyms":["rye whiskey","라이"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["whisky"],"category_key":"whisky","definition":"Whisky explicitly identified as rye whisky under applicable labeling rules."},"taxonomy_version":"2.0.0","sort_order":120,"is_active":true},{"term_type":"style","term_key":"wheat_whisky","label_ko":"위트 위스키","label_en":"Wheat whisky","synonyms":["wheat whiskey","밀 위스키"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["whisky"],"category_key":"whisky","definition":"Whisky explicitly identified as wheat whisky under applicable labeling rules."},"taxonomy_version":"2.0.0","sort_order":130,"is_active":true},{"term_type":"style","term_key":"corn_whisky","label_ko":"콘 위스키","label_en":"Corn whisky","synonyms":["corn whiskey","옥수수 위스키"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["whisky"],"category_key":"whisky","definition":"Whisky explicitly identified as corn whisky under applicable labeling rules."},"taxonomy_version":"2.0.0","sort_order":140,"is_active":true},{"term_type":"style","term_key":"junmai","label_ko":"준마이","label_en":"Junmai","synonyms":["junmai-shu","Tokubetsu junmai","tokubetsu junmai-shu","도쿠베츠 준마이","준마이슈","특별 준마이"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["sake"],"category_key":"sake","definition":"Sake explicitly labeled junmai under the applicable Japanese labeling standard.","definition_source":"Japan National Tax Agency specific designation sake overview","source_standard_url":"https://www.nta.go.jp/about/organization/sapporo/release/r7/kanpyokai/03.htm"},"taxonomy_version":"2.0.0","sort_order":150,"is_active":true},{"term_type":"style","term_key":"ginjo","label_ko":"긴조","label_en":"Ginjo","synonyms":["ginjo-shu","긴죠"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["sake"],"category_key":"sake","definition":"Sake explicitly labeled ginjo under the applicable Japanese labeling standard.","definition_source":"Japan National Tax Agency specific designation sake overview","source_standard_url":"https://www.nta.go.jp/about/organization/sapporo/release/r7/kanpyokai/03.htm"},"taxonomy_version":"2.0.0","sort_order":160,"is_active":true},{"term_type":"style","term_key":"daiginjo","label_ko":"다이긴조","label_en":"Daiginjo","synonyms":["daiginjo-shu","다이긴죠"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["sake"],"category_key":"sake","definition":"Sake explicitly labeled daiginjo under the applicable Japanese labeling standard.","definition_source":"Japan National Tax Agency specific designation sake overview","source_standard_url":"https://www.nta.go.jp/about/organization/sapporo/release/r7/kanpyokai/03.htm"},"taxonomy_version":"2.0.0","sort_order":170,"is_active":true},{"term_type":"style","term_key":"junmai_ginjo","label_ko":"준마이 긴조","label_en":"Junmai ginjo","synonyms":["junmai ginjo-shu","준마이긴조"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["sake"],"category_key":"sake","definition":"Sake explicitly labeled junmai ginjo.","definition_source":"Japan National Tax Agency specific designation sake overview","source_standard_url":"https://www.nta.go.jp/about/organization/sapporo/release/r7/kanpyokai/03.htm"},"taxonomy_version":"2.0.0","sort_order":180,"is_active":true},{"term_type":"style","term_key":"junmai_daiginjo","label_ko":"준마이 다이긴조","label_en":"Junmai daiginjo","synonyms":["junmai daiginjo-shu","준마이다이긴조"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["sake"],"category_key":"sake","definition":"Sake explicitly labeled junmai daiginjo.","definition_source":"Japan National Tax Agency specific designation sake overview","source_standard_url":"https://www.nta.go.jp/about/organization/sapporo/release/r7/kanpyokai/03.htm"},"taxonomy_version":"2.0.0","sort_order":190,"is_active":true},{"term_type":"style","term_key":"honjozo","label_ko":"혼조조","label_en":"Honjozo","synonyms":["honjozo-shu","Tokubetsu honjozo","tokubetsu honjozo-shu","도쿠베츠 혼조조","특별 혼조조","혼죠조"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["sake"],"category_key":"sake","definition":"Sake explicitly labeled honjozo.","definition_source":"Japan National Tax Agency specific designation sake overview","source_standard_url":"https://www.nta.go.jp/about/organization/sapporo/release/r7/kanpyokai/03.htm"},"taxonomy_version":"2.0.0","sort_order":200,"is_active":true},{"term_type":"style","term_key":"futsushu","label_ko":"후쓰슈","label_en":"Futsushu","synonyms":["ordinary sake","보통주"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["sake"],"category_key":"sake","definition":"Sake explicitly identified as ordinary sake rather than a specific-designation sake."},"taxonomy_version":"2.0.0","sort_order":210,"is_active":true},{"term_type":"style","term_key":"takju","label_ko":"탁주","label_en":"Takju","synonyms":["막걸리"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["korean_traditional"],"category_key":"korean_traditional","definition":"Korean traditional alcohol explicitly classified as takju."},"taxonomy_version":"2.0.0","sort_order":220,"is_active":true},{"term_type":"style","term_key":"yakju","label_ko":"약주","label_en":"Yakju","synonyms":["한국 약주"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["korean_traditional"],"category_key":"korean_traditional","definition":"Korean traditional alcohol explicitly classified as yakju."},"taxonomy_version":"2.0.0","sort_order":230,"is_active":true},{"term_type":"style","term_key":"korean_cheongju","label_ko":"청주","label_en":"Korean cheongju","synonyms":["한국 청주"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["korean_traditional"],"category_key":"korean_traditional","definition":"Korean traditional alcohol explicitly classified as cheongju."},"taxonomy_version":"2.0.0","sort_order":240,"is_active":true},{"term_type":"style","term_key":"korean_fruit_wine","label_ko":"과실주","label_en":"Korean fruit wine","synonyms":["한국 과실주"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["korean_traditional"],"category_key":"korean_traditional","definition":"Korean traditional product explicitly classified as fruit wine."},"taxonomy_version":"2.0.0","sort_order":250,"is_active":true},{"term_type":"style","term_key":"distilled_soju","label_ko":"증류식 소주","label_en":"Distilled soju","synonyms":["전통 소주"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["korean_traditional"],"category_key":"korean_traditional","definition":"Korean soju explicitly classified as distilled soju."},"taxonomy_version":"2.0.0","sort_order":260,"is_active":true},{"term_type":"style","term_key":"diluted_soju","label_ko":"희석식 소주","label_en":"Diluted soju","synonyms":["희석 소주"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["korean_traditional"],"category_key":"korean_traditional","definition":"Korean soju explicitly classified as diluted soju."},"taxonomy_version":"2.0.0","sort_order":270,"is_active":true},{"term_type":"style","term_key":"port_wine","label_ko":"포트 와인","label_en":"Port wine","synonyms":["Porto wine","포르투 와인"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["wine"],"category_key":"wine","definition":"포르투갈 도루의 포트로 제품별 출처에서 확인된 주정강화 와인. 루비·토니·화이트 등의 차이와 당도는 별도이며 포트통 숙성 상품은 포함하지 않는다.","definition_source":"IVDP Port wine introduction","source_standard_url":"https://www.ivdp.pt/en/wines/port-wines/introduction/"},"taxonomy_version":"2.0.0","sort_order":280,"is_active":true},{"term_type":"style","term_key":"sherry_wine","label_ko":"셰리 와인","label_en":"Sherry wine","synonyms":["Jerez wine","쉐리 와인"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["wine"],"category_key":"wine","definition":"헤레스의 셰리로 제품별 출처에서 확인된 주정강화 와인. 피노·올로로소·PX 등의 차이는 별도이며 셰리통 숙성 증류주는 제외한다.","definition_source":"Consejo Regulador Jerez, Sherry wine families","source_standard_url":"https://www.sherry.wine/sherry-wine/dry-sherry-wines/fino"},"taxonomy_version":"2.0.0","sort_order":290,"is_active":true},{"term_type":"style","term_key":"madeira_wine","label_ko":"마데이라 와인","label_en":"Madeira wine","synonyms":["마데라 와인"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["wine"],"category_key":"wine","definition":"마데이라의 주정강화 와인으로 확인된 제품군. 당도·품종·숙성 연수는 별도이며 마데이라통 숙성 상품은 포함하지 않는다.","definition_source":"Blandy''s Madeira wine portfolio","source_standard_url":"https://blandys.com/en/wines-portfolio/"},"taxonomy_version":"2.0.0","sort_order":300,"is_active":true},{"term_type":"style","term_key":"tennessee_whisky","label_ko":"테네시 위스키","label_en":"Tennessee whiskey","synonyms":["테네시 위스키 계열"],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["whisky"],"category_key":"whisky","definition":"제품별 제조사 설명에서 테네시 위스키로 확인된 제품군. 브랜드나 생산지만으로 분류하지 않고 명시된 라이·싱글몰트·블렌드는 각 제품 정체성을 따른다.","definition_source":"Jack Daniel''s producer product definitions","source_standard_url":"https://pressroom.jackdaniels.com/products/"},"taxonomy_version":"2.0.0","sort_order":310,"is_active":true},{"term_type":"style","term_key":"gwahaju","label_ko":"과하주","label_en":"Gwahaju","synonyms":[],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["korean_traditional"],"category_key":"korean_traditional","definition":"발효주에 증류주를 더하는 혼양 방식의 한국 과하주. 약주나 증류식 소주 단독 유형과 구분한다."},"taxonomy_version":"2.0.0","sort_order":320,"is_active":true},{"term_type":"style","term_key":"single_pot_still_whisky","label_ko":"싱글 팟 스틸 위스키","label_en":"Single pot still whiskey","synonyms":[],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["whisky"],"category_key":"whisky","definition":"Single Pot Still로 식별된 단일 증류소의 몰트·비몰트 곡물 팟스틸 위스키. 싱글몰트로 바꾸지 않는다."},"taxonomy_version":"2.0.0","sort_order":330,"is_active":true},{"term_type":"style","term_key":"american_whisky","label_ko":"아메리칸 위스키","label_en":"American whiskey","synonyms":[],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["whisky"],"category_key":"whisky","definition":"미국 위스키 중 버번·라이·테네시·특정 곡물 등 기존 계열로 설명되지 않는 제품. 원산지 확인을 요구하며 버번 요건을 추정하지 않는다."},"taxonomy_version":"2.0.0","sort_order":340,"is_active":true},{"term_type":"style","term_key":"vermouth","label_ko":"베르무트","label_en":"Vermouth","synonyms":[],"parent_term_key":null,"applicable_sections":["style"],"metadata":{"applies_to_categories":["wine"],"category_key":"wine","definition":"제품별 자료에서 베르무트로 식별된 방향성 와인. 일반 화이트·레드·순수 증류주와 구별한다."},"taxonomy_version":"2.0.0","sort_order":350,"is_active":true},{"term_type":"ingredient","term_key":"barley","label_ko":"보리","label_en":"Barley","synonyms":["대맥"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","whisky"],"definition":"Barley material without a supported malt status.","ingredient_type_key":"grain"},"taxonomy_version":"2.0.0","sort_order":10,"is_active":true},{"term_type":"ingredient","term_key":"rice","label_ko":"쌀","label_en":"Rice","synonyms":["미곡"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","sake"],"definition":"Rice material without a narrower supported form or variety.","ingredient_type_key":"grain"},"taxonomy_version":"2.0.0","sort_order":30,"is_active":true},{"term_type":"ingredient","term_key":"wheat","label_ko":"밀","label_en":"Wheat","synonyms":["소맥"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","whisky"],"definition":"Wheat material.","ingredient_type_key":"grain"},"taxonomy_version":"2.0.0","sort_order":60,"is_active":true},{"term_type":"ingredient","term_key":"corn","label_ko":"옥수수","label_en":"Corn","synonyms":["메이즈"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","whisky"],"definition":"Corn or maize material.","ingredient_type_key":"grain"},"taxonomy_version":"2.0.0","sort_order":70,"is_active":true},{"term_type":"ingredient","term_key":"rye","label_ko":"호밀","label_en":"Rye","synonyms":["라이"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["whisky"],"definition":"Rye grain material.","ingredient_type_key":"grain"},"taxonomy_version":"2.0.0","sort_order":80,"is_active":true},{"term_type":"ingredient","term_key":"sorghum","label_ko":"수수","label_en":"Sorghum","synonyms":["고량"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Sorghum grain material.","ingredient_type_key":"grain"},"taxonomy_version":"2.0.0","sort_order":90,"is_active":true},{"term_type":"ingredient","term_key":"buckwheat","label_ko":"메밀","label_en":"Buckwheat","synonyms":["소바"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Buckwheat material.","ingredient_type_key":"grain"},"taxonomy_version":"2.0.0","sort_order":100,"is_active":true},{"term_type":"ingredient","term_key":"millet","label_ko":"조·기장","label_en":"Millet","synonyms":["잡곡"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Millet-family grain where a narrower species is not established.","ingredient_type_key":"grain"},"taxonomy_version":"2.0.0","sort_order":110,"is_active":true},{"term_type":"ingredient","term_key":"oat","label_ko":"귀리","label_en":"Oat","synonyms":["오트"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","whisky"],"definition":"Oat grain material.","ingredient_type_key":"grain"},"taxonomy_version":"2.0.0","sort_order":120,"is_active":true},{"term_type":"ingredient","term_key":"grape","label_ko":"포도","label_en":"Grape","synonyms":["양조용 포도"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","wine"],"definition":"Grape material without a supported variety.","ingredient_type_key":"grape"},"taxonomy_version":"2.0.0","sort_order":130,"is_active":true},{"term_type":"ingredient","term_key":"apple_fruit","label_ko":"사과","label_en":"Apple","synonyms":["애플"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Apple fruit material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":140,"is_active":true},{"term_type":"ingredient","term_key":"pear_fruit","label_ko":"배","label_en":"Pear","synonyms":["페어"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Pear fruit material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":150,"is_active":true},{"term_type":"ingredient","term_key":"cherry_fruit","label_ko":"체리","label_en":"Cherry","synonyms":["버찌"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Cherry fruit explicitly used as a fermentable or flavouring material, including cherry spirit identified as Kirsch.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":160,"is_active":true},{"term_type":"ingredient","term_key":"plum_fruit","label_ko":"자두·매실","label_en":"Plum","synonyms":["매실","플럼"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","sake"],"definition":"Plum-family fruit material; exact species and source wording should be retained.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":170,"is_active":true},{"term_type":"ingredient","term_key":"peach_fruit","label_ko":"복숭아","label_en":"Peach","synonyms":["피치"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","wine"],"definition":"Peach fruit material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":180,"is_active":true},{"term_type":"ingredient","term_key":"citrus_fruit","label_ko":"감귤류","label_en":"Citrus fruit","synonyms":["시트러스"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","sake","wine"],"definition":"Citrus-family fruit without a narrower supported species.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":190,"is_active":true},{"term_type":"ingredient","term_key":"berry_fruit","label_ko":"베리류","label_en":"Berry fruit","synonyms":["베리"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","wine"],"definition":"Berry-family fruit without a narrower supported species.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":200,"is_active":true},{"term_type":"ingredient","term_key":"tropical_fruit_material","label_ko":"열대과일","label_en":"Tropical fruit","synonyms":["트로피컬 프루트"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Tropical fruit without a narrower supported species.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":210,"is_active":true},{"term_type":"ingredient","term_key":"honey","label_ko":"꿀","label_en":"Honey","synonyms":["벌꿀"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Honey material.","ingredient_type_key":"other"},"taxonomy_version":"2.0.0","sort_order":220,"is_active":true},{"term_type":"ingredient","term_key":"sweet_potato","label_ko":"고구마","label_en":"Sweet potato","synonyms":["감저"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Sweet-potato material.","ingredient_type_key":"other"},"taxonomy_version":"2.0.0","sort_order":230,"is_active":true},{"term_type":"ingredient","term_key":"herb_botanical","label_ko":"허브","label_en":"Herb","synonyms":["허브류"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Herbal botanical without a narrower supported species.","ingredient_type_key":"botanical"},"taxonomy_version":"2.0.0","sort_order":240,"is_active":true},{"term_type":"ingredient","term_key":"hop_material","label_ko":"홉","label_en":"Hop","synonyms":["호프"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["whisky"],"definition":"Hop without a supported variety.","ingredient_type_key":"botanical"},"taxonomy_version":"2.0.0","sort_order":250,"is_active":true},{"term_type":"ingredient","term_key":"yeast","label_ko":"효모","label_en":"Yeast","synonyms":["이스트"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky","wine"],"definition":"Yeast culture without a supported strain.","ingredient_type_key":"other"},"taxonomy_version":"2.0.0","sort_order":260,"is_active":true},{"term_type":"ingredient","term_key":"lactic_bacteria","label_ko":"유산균","label_en":"Lactic acid bacteria","synonyms":["젖산균"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","sake","wine"],"definition":"Lactic-acid bacteria culture without a supported strain.","ingredient_type_key":"other"},"taxonomy_version":"2.0.0","sort_order":270,"is_active":true},{"term_type":"ingredient","term_key":"koji_starter","label_ko":"코지","label_en":"Koji","synonyms":["누룩곰팡이","쌀 누룩","쌀국","쌀누룩","입국"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["sake"],"definition":"Koji starter without a supported type.","ingredient_type_key":"other"},"taxonomy_version":"2.0.0","sort_order":280,"is_active":true},{"term_type":"ingredient","term_key":"nuruk_starter","label_ko":"누룩","label_en":"Nuruk","synonyms":["전통 누룩"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Nuruk starter without a supported subtype.","ingredient_type_key":"other"},"taxonomy_version":"2.0.0","sort_order":310,"is_active":true},{"term_type":"ingredient","term_key":"water_material","label_ko":"물","label_en":"Water","synonyms":["양조용수","용수","정제수","희석수"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky","wine"],"definition":"Water explicitly documented as an ingredient, brewing water or dilution water.","ingredient_type_key":"water"},"taxonomy_version":"2.0.0","sort_order":320,"is_active":true},{"term_type":"ingredient","term_key":"caramel_colour","label_ko":"캐러멜 색소","label_en":"Caramel colour","synonyms":["카라멜 색소"],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["whisky"],"definition":"Caramel colouring explicitly declared; caramel sensory notes are separate.","ingredient_type_key":"additive"},"taxonomy_version":"2.0.0","sort_order":330,"is_active":true},{"term_type":"ingredient","term_key":"apricot_fruit","label_ko":"살구","label_en":"Apricot","synonyms":[],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Apricot fruit material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":340,"is_active":true},{"term_type":"ingredient","term_key":"aronia_fruit","label_ko":"아로니아","label_en":"Aronia","synonyms":[],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Aronia (chokeberry) fruit material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":350,"is_active":true},{"term_type":"ingredient","term_key":"blueberry_fruit","label_ko":"블루베리","label_en":"Blueberry","synonyms":[],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Blueberry fruit material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":360,"is_active":true},{"term_type":"ingredient","term_key":"bokbunja_fruit","label_ko":"복분자","label_en":"Bokbunja (Korean black raspberry)","synonyms":[],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Rubus coreanus fruit (복분자) material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":370,"is_active":true},{"term_type":"ingredient","term_key":"hardy_kiwi_fruit","label_ko":"다래","label_en":"Hardy kiwi","synonyms":[],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Hardy kiwi (다래, 참다래) fruit material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":380,"is_active":true},{"term_type":"ingredient","term_key":"meoru_fruit","label_ko":"머루","label_en":"Meoru (Korean wild grape)","synonyms":[],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Vitis coignetiae wild grape (머루) material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":390,"is_active":true},{"term_type":"ingredient","term_key":"mulberry_fruit","label_ko":"오디","label_en":"Mulberry","synonyms":[],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Mulberry fruit (오디, 뽕) material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":400,"is_active":true},{"term_type":"ingredient","term_key":"omija_fruit","label_ko":"오미자","label_en":"Omija (schisandra berry)","synonyms":[],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Schisandra chinensis berry (오미자) fruit material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":410,"is_active":true},{"term_type":"ingredient","term_key":"persimmon_fruit","label_ko":"감","label_en":"Persimmon","synonyms":[],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Persimmon (단감, 홍시) fruit material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":420,"is_active":true},{"term_type":"ingredient","term_key":"pomegranate_fruit","label_ko":"석류","label_en":"Pomegranate","synonyms":[],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Pomegranate fruit material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":430,"is_active":true},{"term_type":"ingredient","term_key":"quince_fruit","label_ko":"모과","label_en":"Chinese quince","synonyms":[],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Chinese quince (모과) fruit material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":440,"is_active":true},{"term_type":"ingredient","term_key":"strawberry_fruit","label_ko":"딸기","label_en":"Strawberry","synonyms":[],"parent_term_key":null,"applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Strawberry fruit material.","ingredient_type_key":"fruit"},"taxonomy_version":"2.0.0","sort_order":450,"is_active":true},{"term_type":"process","term_key":"cultured_fermentation","label_ko":"배양 효모 발효","label_en":"Cultured fermentation","synonyms":["선별 효모"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky","wine"],"definition":"A selected or cultured fermentation organism is explicitly documented.","kind_key":"fermentation","process_stage":"fermentation"},"taxonomy_version":"2.0.0","sort_order":10,"is_active":true},{"term_type":"process","term_key":"spontaneous_fermentation","label_ko":"자연발효","label_en":"Spontaneous fermentation","synonyms":["야생 발효"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["wine"],"definition":"The producer explicitly documents spontaneous fermentation.","kind_key":"fermentation","process_stage":"fermentation"},"taxonomy_version":"2.0.0","sort_order":20,"is_active":true},{"term_type":"process","term_key":"mixed_culture_fermentation","label_ko":"혼합 배양 발효","label_en":"Mixed-culture fermentation","synonyms":["믹스드 컬처"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["wine"],"definition":"More than one documented microorganism or culture participates in fermentation.","kind_key":"fermentation","process_stage":"fermentation"},"taxonomy_version":"2.0.0","sort_order":30,"is_active":true},{"term_type":"process","term_key":"malolactic_fermentation","label_ko":"말로락틱 발효","label_en":"Malolactic fermentation","synonyms":["MLF","유산 발효"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["wine"],"definition":"Malolactic conversion is explicitly documented.","kind_key":"fermentation","process_stage":"fermentation"},"taxonomy_version":"2.0.0","sort_order":40,"is_active":true},{"term_type":"process","term_key":"parallel_multiple_fermentation","label_ko":"병행복발효","label_en":"Parallel multiple fermentation","synonyms":["병행 복발효"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","sake"],"definition":"Saccharification and alcoholic fermentation are explicitly documented as proceeding in parallel.","kind_key":"fermentation","process_stage":"fermentation"},"taxonomy_version":"2.0.0","sort_order":50,"is_active":true},{"term_type":"process","term_key":"pot_distillation","label_ko":"단식 증류","label_en":"Pot distillation","synonyms":["단식증류기","팟 스틸"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","whisky"],"definition":"Pot-still or batch distillation is explicitly documented.","kind_key":"distillation","process_stage":"distillation"},"taxonomy_version":"2.0.0","sort_order":60,"is_active":true},{"term_type":"process","term_key":"column_distillation","label_ko":"연속식 증류","label_en":"Column distillation","synonyms":["연속증류기","컬럼 스틸"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","whisky"],"definition":"Column or continuous distillation is explicitly documented.","kind_key":"distillation","process_stage":"distillation"},"taxonomy_version":"2.0.0","sort_order":70,"is_active":true},{"term_type":"process","term_key":"single_distillation","label_ko":"1회 증류","label_en":"Single distillation","synonyms":["한 번 증류"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","whisky"],"definition":"A single distillation pass is explicitly documented.","kind_key":"distillation","process_stage":"distillation"},"taxonomy_version":"2.0.0","sort_order":80,"is_active":true},{"term_type":"process","term_key":"double_distillation","label_ko":"2회 증류","label_en":"Double distillation","synonyms":["이중 증류"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","whisky"],"definition":"Two distillation passes are explicitly documented.","kind_key":"distillation","process_stage":"distillation"},"taxonomy_version":"2.0.0","sort_order":90,"is_active":true},{"term_type":"process","term_key":"triple_distillation","label_ko":"3회 증류","label_en":"Triple distillation","synonyms":["삼중 증류"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["whisky"],"definition":"Three distillation passes are explicitly documented.","kind_key":"distillation","process_stage":"distillation"},"taxonomy_version":"2.0.0","sort_order":100,"is_active":true},{"term_type":"process","term_key":"atmospheric_distillation","label_ko":"상압 증류","label_en":"Atmospheric distillation","synonyms":["常圧蒸留"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Distillation at normal atmospheric pressure is explicitly documented (常圧蒸留); it carries heavier aroma compounds over than reduced-pressure distillation.","kind_key":"distillation","process_stage":"distillation"},"taxonomy_version":"2.0.0","sort_order":110,"is_active":true},{"term_type":"process","term_key":"vacuum_distillation","label_ko":"감압 증류","label_en":"Vacuum distillation","synonyms":["저온 감압 증류"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","whisky"],"definition":"Reduced-pressure distillation is explicitly documented.","kind_key":"distillation","process_stage":"distillation"},"taxonomy_version":"2.0.0","sort_order":120,"is_active":true},{"term_type":"process","term_key":"chill_filtration","label_ko":"냉각여과","label_en":"Chill filtration","synonyms":["칠 필터링"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["whisky"],"definition":"Chill filtration is explicitly documented.","excludes_term_keys":["non_chill_filtered"],"kind_key":"filtration","process_stage":"filtration"},"taxonomy_version":"2.0.0","sort_order":130,"is_active":true},{"term_type":"process","term_key":"non_chill_filtered","label_ko":"비냉각여과","label_en":"Non-chill filtered","synonyms":["논칠필터드"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["whisky"],"definition":"A non-chill-filtered claim is explicitly documented.","excludes_term_keys":["chill_filtration"],"kind_key":"filtration","process_stage":"filtration"},"taxonomy_version":"2.0.0","sort_order":140,"is_active":true},{"term_type":"process","term_key":"charcoal_filtration","label_ko":"활성탄 여과","label_en":"Charcoal filtration","synonyms":["숯 여과"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky"],"definition":"Charcoal or activated-carbon filtration is explicitly documented.","kind_key":"filtration","process_stage":"filtration"},"taxonomy_version":"2.0.0","sort_order":150,"is_active":true},{"term_type":"process","term_key":"unfiltered_claim","label_ko":"무여과 표방","label_en":"Unfiltered claim","synonyms":["논필터드"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky","wine"],"definition":"An unfiltered claim is explicit; visible haze alone is insufficient.","kind_key":"filtration","process_stage":"filtration"},"taxonomy_version":"2.0.0","sort_order":160,"is_active":true},{"term_type":"process","term_key":"rice_water_only_claim","label_ko":"쌀과 물만 사용 표방","label_en":"Rice and water only claim","synonyms":["쌀과 물로만 양조 표방"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["sake"],"definition":"Explicit wording claims rice and water only. Preserve the stated scope without inferring absent yeast, junmai grade, additive absence or removing existing ingredient facts.","kind_key":"other","process_stage":"other"},"taxonomy_version":"2.0.0","sort_order":170,"is_active":true},{"term_type":"process","term_key":"pasteurised","label_ko":"살균","label_en":"Pasteurised","synonyms":["가열 살균"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","sake","wine"],"definition":"Pasteurisation is explicitly documented.","excludes_term_keys":["unpasteurised"],"kind_key":"stabilization","process_stage":"stabilization"},"taxonomy_version":"2.0.0","sort_order":180,"is_active":true},{"term_type":"process","term_key":"unpasteurised","label_ko":"비살균","label_en":"Unpasteurised","synonyms":["나마","생"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","sake","wine"],"definition":"An unpasteurised or raw claim is explicitly documented.","excludes_term_keys":["pasteurised"],"kind_key":"stabilization","process_stage":"stabilization"},"taxonomy_version":"2.0.0","sort_order":190,"is_active":true},{"term_type":"process","term_key":"cold_stabilised","label_ko":"저온 안정화","label_en":"Cold stabilised","synonyms":["콜드 스태빌라이즈드"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["wine"],"definition":"Cold stabilisation is explicitly documented.","kind_key":"stabilization","process_stage":"stabilization"},"taxonomy_version":"2.0.0","sort_order":200,"is_active":true},{"term_type":"process","term_key":"maceration","label_ko":"침용","label_en":"Maceration","synonyms":["마세레이션"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","wine"],"definition":"Maceration of a documented material is explicitly described.","kind_key":"preparation","process_stage":"preparation"},"taxonomy_version":"2.0.0","sort_order":210,"is_active":true},{"term_type":"process","term_key":"peated_malt","label_ko":"피트 처리 맥아","label_en":"Peated malt","synonyms":["peated","피티드"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["whisky"],"definition":"Malt dried over peat smoke is explicitly documented for the product or its distillery.","kind_key":"preparation","process_stage":"preparation"},"taxonomy_version":"2.0.0","sort_order":220,"is_active":true},{"term_type":"process","term_key":"bottle_secondary_fermentation","label_ko":"병내 2차 발효","label_en":"Bottle secondary fermentation","synonyms":["병 발효","전통 방식"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["sake","wine"],"definition":"Secondary fermentation in bottle is explicitly documented.","kind_key":"carbonation","process_stage":"carbonation"},"taxonomy_version":"2.0.0","sort_order":230,"is_active":true},{"term_type":"process","term_key":"tank_secondary_fermentation","label_ko":"탱크 2차 발효","label_en":"Tank secondary fermentation","synonyms":["샤르마 방식"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["sake","wine"],"definition":"Secondary fermentation in a closed tank is explicitly documented.","kind_key":"carbonation","process_stage":"carbonation"},"taxonomy_version":"2.0.0","sort_order":240,"is_active":true},{"term_type":"process","term_key":"forced_carbonation","label_ko":"탄산 주입","label_en":"Forced carbonation","synonyms":["강제 탄산"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","sake","wine"],"definition":"Exogenous carbonation is explicitly documented.","kind_key":"carbonation","process_stage":"carbonation"},"taxonomy_version":"2.0.0","sort_order":250,"is_active":true},{"term_type":"process","term_key":"multi_vintage_blend","label_ko":"다빈티지 블렌드","label_en":"Multi-vintage blend","synonyms":["논빈티지 블렌딩"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["sake","wine"],"definition":"Components from more than one vintage are explicitly documented.","kind_key":"blending","process_stage":"blending"},"taxonomy_version":"2.0.0","sort_order":260,"is_active":true},{"term_type":"process","term_key":"multi_cask_blend","label_ko":"다중 캐스크 블렌드","label_en":"Multi-cask blend","synonyms":["배럴 블렌딩"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["whisky"],"definition":"Components from more than one cask are explicitly documented.","kind_key":"blending","process_stage":"blending"},"taxonomy_version":"2.0.0","sort_order":270,"is_active":true},{"term_type":"process","term_key":"solera_blending","label_ko":"솔레라 블렌딩","label_en":"Solera blending","synonyms":["분획 블렌딩"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["wine"],"definition":"A solera or fractional-blending system is explicitly documented.","kind_key":"blending","process_stage":"blending"},"taxonomy_version":"2.0.0","sort_order":280,"is_active":true},{"term_type":"process","term_key":"spirit_fortification","label_ko":"증류주 첨가 강화","label_en":"Spirit fortification","synonyms":["주정 첨가"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","wine"],"definition":"Addition of a documented spirit or alcohol for fortification is explicitly supported.","kind_key":"other","process_stage":"other"},"taxonomy_version":"2.0.0","sort_order":290,"is_active":true},{"term_type":"process","term_key":"cask_strength","label_ko":"캐스크 스트렝스","label_en":"Cask strength","synonyms":["배럴 프루프","캐스크 스트렝쓰"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","whisky"],"definition":"Bottled at the strength it left the cask, without dilution to a standard ABV.","kind_key":"bottling","process_stage":"bottling"},"taxonomy_version":"2.0.0","sort_order":300,"is_active":true},{"term_type":"process","term_key":"small_batch","label_ko":"스몰 배치","label_en":"Small batch","synonyms":["소량 배치"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","whisky"],"definition":"Release blended from a small, named number of casks or a single small run.","kind_key":"blending","process_stage":"blending"},"taxonomy_version":"2.0.0","sort_order":310,"is_active":true},{"term_type":"process","term_key":"organic_certified","label_ko":"유기 인증","label_en":"Certified organic","synonyms":["오가닉 인증","유기농 인증"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky","wine"],"definition":"Certified organic farming or production is explicitly documented.","kind_key":"preparation","process_stage":"preparation"},"taxonomy_version":"2.0.0","sort_order":320,"is_active":true},{"term_type":"process","term_key":"biodynamic_certified","label_ko":"바이오다이내믹 인증","label_en":"Certified biodynamic","synonyms":["생명역동농법 인증"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["wine"],"definition":"Certified biodynamic farming is explicitly documented.","kind_key":"preparation","process_stage":"preparation"},"taxonomy_version":"2.0.0","sort_order":330,"is_active":true},{"term_type":"process","term_key":"natural_wine_claim","label_ko":"내추럴 와인 표방","label_en":"Natural wine claim","synonyms":["자연주의 와인"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["wine"],"definition":"The producer presents the wine as natural wine; a claim, not a certification.","kind_key":"preparation","process_stage":"preparation"},"taxonomy_version":"2.0.0","sort_order":340,"is_active":true},{"term_type":"process","term_key":"undiluted","label_ko":"겐슈","label_en":"Genshu (undiluted)","synonyms":["무가수","원주"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["sake"],"definition":"Bottled without adding water after pressing or distillation.","kind_key":"bottling","process_stage":"bottling"},"taxonomy_version":"2.0.0","sort_order":350,"is_active":true},{"term_type":"process","term_key":"coarse_filtered","label_ko":"니고리","label_en":"Nigori (coarse filtered)","synonyms":["니고리자케","탁한 사케"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["sake"],"definition":"Pressed through a coarse mesh so lees remain and the drink is cloudy.","kind_key":"filtration","process_stage":"filtration"},"taxonomy_version":"2.0.0","sort_order":360,"is_active":true},{"term_type":"process","term_key":"kimoto_starter","label_ko":"기모토","label_en":"Kimoto starter","synonyms":["생모토"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["sake"],"definition":"Yeast starter made by the traditional kimoto method with natural lactic bacteria.","kind_key":"fermentation","process_stage":"fermentation"},"taxonomy_version":"2.0.0","sort_order":370,"is_active":true},{"term_type":"process","term_key":"yamahai_starter","label_ko":"야마하이","label_en":"Yamahai starter","synonyms":["산폐"],"parent_term_key":null,"applicable_sections":["production"],"metadata":{"applies_to_categories":["sake"],"definition":"Yeast starter made by the yamahai method, kimoto without the mashing step.","kind_key":"fermentation","process_stage":"fermentation"},"taxonomy_version":"2.0.0","sort_order":380,"is_active":true},{"term_type":"maturation","term_key":"wooden_cask","label_ko":"목재 캐스크","label_en":"Wooden cask","synonyms":["나무통"],"parent_term_key":null,"applicable_sections":["maturation"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky","wine"],"definition":"Maturation in a wooden cask is explicitly documented, without a supported wood species.","kind_key":"maturation_vessel","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":10,"is_active":true},{"term_type":"maturation","term_key":"stainless_steel_vessel","label_ko":"스테인리스 용기","label_en":"Stainless-steel vessel","synonyms":["스테인리스 탱크"],"parent_term_key":null,"applicable_sections":["maturation"],"metadata":{"applies_to_categories":["korean_traditional","sake","wine"],"definition":"Holding or maturation in stainless steel is explicitly documented.","kind_key":"maturation_vessel","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":20,"is_active":true},{"term_type":"maturation","term_key":"amphora_vessel","label_ko":"암포라","label_en":"Amphora","synonyms":["점토 항아리"],"parent_term_key":null,"applicable_sections":["maturation"],"metadata":{"applies_to_categories":["korean_traditional","wine"],"definition":"Fermentation, holding or maturation in amphora or a documented clay vessel.","kind_key":"maturation_vessel","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":30,"is_active":true},{"term_type":"maturation","term_key":"concrete_vessel","label_ko":"콘크리트 용기","label_en":"Concrete vessel","synonyms":["콘크리트 탱크"],"parent_term_key":null,"applicable_sections":["maturation"],"metadata":{"applies_to_categories":["wine"],"definition":"Holding or maturation in a concrete vessel is explicitly documented.","kind_key":"maturation_vessel","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":40,"is_active":true},{"term_type":"maturation","term_key":"bottle_ageing","label_ko":"병 숙성","label_en":"Bottle ageing","synonyms":["병입 숙성"],"parent_term_key":null,"applicable_sections":["maturation"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky","wine"],"definition":"A documented period of bottle ageing precedes release.","kind_key":"maturation_vessel","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":50,"is_active":true},{"term_type":"maturation","term_key":"cask_finishing","label_ko":"캐스크 피니시","label_en":"Cask finishing","synonyms":["피니시 숙성"],"parent_term_key":null,"applicable_sections":["maturation"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky","wine"],"definition":"A distinct finishing maturation stage is explicitly documented; finishing vessel is linked separately.","kind_key":"maturation_regime","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":210,"is_active":true},{"term_type":"maturation","term_key":"fractional_ageing","label_ko":"분획 숙성","label_en":"Fractional ageing","synonyms":["솔레라 숙성"],"parent_term_key":null,"applicable_sections":["maturation"],"metadata":{"applies_to_categories":["wine"],"definition":"A solera or other fractional-aging regime is explicitly documented.","kind_key":"maturation_regime","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":220,"is_active":true},{"term_type":"maturation","term_key":"single_cask_maturation","label_ko":"단일 캐스크 숙성","label_en":"Single-cask maturation","synonyms":["싱글 배럴 숙성"],"parent_term_key":null,"applicable_sections":["maturation"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky"],"definition":"The release is explicitly matured and released from one cask.","kind_key":"maturation_regime","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":230,"is_active":true},{"term_type":"maturation","term_key":"extended_maturation","label_ko":"장기 숙성","label_en":"Extended maturation","synonyms":["Koshu","고슈","숙성 사케"],"parent_term_key":null,"applicable_sections":["maturation"],"metadata":{"applies_to_categories":["korean_traditional","sake"],"definition":"Matured for years beyond the usual release age; for sake, koshu.","kind_key":"maturation_regime","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":240,"is_active":true},{"term_type":"ingredient","term_key":"malted_barley","label_ko":"맥아","label_en":"Malted barley","synonyms":["몰트","보리 맥아"],"parent_term_key":"barley","applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["whisky"],"definition":"Barley explicitly supported as malted.","ingredient_type_key":"grain"},"taxonomy_version":"2.0.0","sort_order":20,"is_active":true},{"term_type":"ingredient","term_key":"rice_omachi","label_ko":"오마치 쌀","label_en":"Omachi rice","synonyms":["Omachi","오마치"],"parent_term_key":"rice","applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["sake"],"definition":"Rice explicitly identified as the Omachi variety.","ingredient_type_key":"grain"},"taxonomy_version":"2.0.0","sort_order":40,"is_active":true},{"term_type":"ingredient","term_key":"glutinous_rice","label_ko":"찹쌀","label_en":"Glutinous rice","synonyms":["sticky rice"],"parent_term_key":"rice","applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["korean_traditional"],"definition":"Rice explicitly identified as glutinous rice.","ingredient_type_key":"grain"},"taxonomy_version":"2.0.0","sort_order":50,"is_active":true},{"term_type":"ingredient","term_key":"white_koji","label_ko":"백국","label_en":"White koji","synonyms":["시로 코지"],"parent_term_key":"koji_starter","applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["sake"],"definition":"Koji explicitly identified as white koji.","ingredient_type_key":"other"},"taxonomy_version":"2.0.0","sort_order":290,"is_active":true},{"term_type":"ingredient","term_key":"yellow_koji","label_ko":"황국","label_en":"Yellow koji","synonyms":["키 코지"],"parent_term_key":"koji_starter","applicable_sections":["ingredient"],"metadata":{"applies_to_categories":["sake"],"definition":"Koji explicitly identified as yellow koji.","ingredient_type_key":"other"},"taxonomy_version":"2.0.0","sort_order":300,"is_active":true},{"term_type":"maturation","term_key":"oak_wood","label_ko":"오크","label_en":"Oak","synonyms":["참나무"],"parent_term_key":"wooden_cask","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky","wine"],"definition":"Oak is documented without a narrower species or origin.","kind_key":"wood_species","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":60,"is_active":true},{"term_type":"maturation","term_key":"american_oak","label_ko":"아메리칸 오크","label_en":"American oak","synonyms":["미국산 오크"],"parent_term_key":"oak_wood","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["sake","whisky","wine"],"definition":"American oak is explicitly documented; exact species may remain in source text.","kind_key":"wood_species","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":70,"is_active":true},{"term_type":"maturation","term_key":"european_oak","label_ko":"유러피언 오크","label_en":"European oak","synonyms":["유럽산 오크"],"parent_term_key":"oak_wood","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["sake","whisky","wine"],"definition":"European oak is explicitly documented; exact species and origin may remain in source text.","kind_key":"wood_species","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":80,"is_active":true},{"term_type":"maturation","term_key":"mizunara_oak","label_ko":"미즈나라 오크","label_en":"Mizunara oak","synonyms":["물참나무"],"parent_term_key":"oak_wood","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["sake","whisky"],"definition":"Mizunara oak is explicitly documented.","kind_key":"wood_species","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":90,"is_active":true},{"term_type":"maturation","term_key":"new_oak_cask","label_ko":"새 오크통","label_en":"New oak cask","synonyms":["버진 오크"],"parent_term_key":"wooden_cask","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["whisky","wine"],"definition":"A new or first-fill unused oak cask is explicitly documented.","kind_key":"prior_fill","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":100,"is_active":true},{"term_type":"maturation","term_key":"ex_bourbon_cask","label_ko":"버번 캐스크","label_en":"Ex-bourbon cask","synonyms":["버번 배럴"],"parent_term_key":"wooden_cask","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["sake","whisky","wine"],"definition":"A cask previously holding bourbon is explicitly documented.","kind_key":"prior_fill","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":110,"is_active":true},{"term_type":"maturation","term_key":"ex_sherry_cask","label_ko":"셰리 캐스크","label_en":"Ex-sherry cask","synonyms":["쉐리 캐스크"],"parent_term_key":"wooden_cask","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["sake","whisky","wine"],"definition":"A sherry-seasoned or former sherry cask is explicitly documented; the exact wording is retained.","kind_key":"prior_fill","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":120,"is_active":true},{"term_type":"maturation","term_key":"ex_wine_cask","label_ko":"와인 캐스크","label_en":"Ex-wine cask","synonyms":["와인 배럴"],"parent_term_key":"wooden_cask","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky"],"definition":"A cask previously holding wine is explicitly documented; wine type is stored separately when known.","kind_key":"prior_fill","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":130,"is_active":true},{"term_type":"maturation","term_key":"ex_port_cask","label_ko":"포트 캐스크","label_en":"Ex-port cask","synonyms":["포트 와인 캐스크"],"parent_term_key":"ex_wine_cask","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["korean_traditional","sake","whisky"],"definition":"A cask previously holding port is explicitly documented.","kind_key":"prior_fill","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":140,"is_active":true},{"term_type":"maturation","term_key":"ex_rum_cask","label_ko":"럼 캐스크","label_en":"Ex-rum cask","synonyms":["럼 배럴"],"parent_term_key":"wooden_cask","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["sake","whisky"],"definition":"A cask previously holding rum is explicitly documented.","kind_key":"prior_fill","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":150,"is_active":true},{"term_type":"maturation","term_key":"ex_rye_cask","label_ko":"라이 캐스크","label_en":"Ex-rye whiskey cask","synonyms":["rye barrel","라이 위스키 캐스크"],"parent_term_key":"wooden_cask","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["whisky"],"definition":"A cask previously holding rye whiskey is explicitly documented.","kind_key":"prior_fill","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":160,"is_active":true},{"term_type":"maturation","term_key":"ex_beer_cask","label_ko":"맥주 캐스크","label_en":"Ex-beer cask","synonyms":["IPA 캐스크","스타우트 캐스크"],"parent_term_key":"wooden_cask","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["whisky"],"definition":"A cask previously holding beer (IPA, stout, ale) is explicitly documented.","kind_key":"prior_fill","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":170,"is_active":true},{"term_type":"maturation","term_key":"ex_brandy_cask","label_ko":"브랜디 캐스크","label_en":"Ex-brandy cask","synonyms":["코냑 캐스크"],"parent_term_key":"wooden_cask","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["sake","whisky"],"definition":"A cask previously holding brandy is explicitly documented.","kind_key":"prior_fill","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":180,"is_active":true},{"term_type":"maturation","term_key":"toasted_cask","label_ko":"토스팅 캐스크","label_en":"Toasted cask","synonyms":["토스트 오크"],"parent_term_key":"wooden_cask","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["whisky","wine"],"definition":"Cask toasting is explicitly documented; toast level is stored separately if available.","kind_key":"vessel_treatment","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":190,"is_active":true},{"term_type":"maturation","term_key":"charred_cask","label_ko":"차링 캐스크","label_en":"Charred cask","synonyms":["그을린 오크통"],"parent_term_key":"wooden_cask","applicable_sections":["maturation"],"metadata":{"applies_to_categories":["whisky"],"definition":"Cask charring is explicitly documented; char level is stored separately if available.","kind_key":"vessel_treatment","process_stage":"maturation"},"taxonomy_version":"2.0.0","sort_order":200,"is_active":true}]'::jsonb) as row_in(
  term_type text, term_key text, label_ko text, label_en text, synonyms text[],
  parent_term_key text, applicable_sections text[], metadata jsonb,
  taxonomy_version text, sort_order integer, is_active boolean
)
on conflict (term_type, term_key) do nothing;

set constraints all immediate;

-- (3) the rename, with every constraint, trigger and index following
alter table public.catalog_terms rename to catalog_taxonomy;

do $$
declare
  name text;
begin
  for name in
    select conname from pg_constraint
    where conrelid = 'public.catalog_taxonomy'::regclass
      and contype <> 't' and starts_with(conname, 'catalog_terms_')
  loop
    execute format('alter table public.catalog_taxonomy rename constraint %I to %I',
                   name, 'catalog_taxonomy_' || substr(name, length('catalog_terms_') + 1));
  end loop;
  for name in
    select tgname from pg_trigger
    where tgrelid = 'public.catalog_taxonomy'::regclass
      and not tgisinternal and tgconstraint = 0 and starts_with(tgname, 'catalog_terms_')
  loop
    execute format('alter trigger %I on public.catalog_taxonomy rename to %I',
                   name, 'catalog_taxonomy_' || substr(name, length('catalog_terms_') + 1));
  end loop;
  for name in
    select indexname from pg_indexes
    where schemaname = 'public' and tablename = 'catalog_taxonomy'
      and starts_with(indexname, 'catalog_terms_')
  loop
    execute format('alter index public.%I rename to %I',
                   name, 'catalog_taxonomy_' || substr(name, length('catalog_terms_') + 1));
  end loop;
end
$$;

-- A constraint trigger keeps its constraint's old name under ALTER TRIGGER
-- RENAME, so the paused assignment check is recreated instead, which also
-- re-enables it.
drop trigger catalog_terms_assignment_validate on public.catalog_taxonomy;
create constraint trigger catalog_taxonomy_assignment_validate
  after insert or update on public.catalog_taxonomy
  deferrable initially deferred
  for each row execute function public.soolgyul_catalog_assignment_term_validate();

comment on table public.catalog_taxonomy is
  'Classification skeleton the database searches and validates with: region tree, style/ingredient/process/maturation keys, sensory tag keys. Prose lives in catalog/dictionary/terms.json.';

-- (4) the functions that read the table, otherwise unchanged
CREATE OR REPLACE FUNCTION public.soolgyul_catalog_assignment_category_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare category public.alcohol_categories%rowtype; related record;
begin
  if tg_op='UPDATE' and row(new.category_key,new.is_active) is not distinct from row(old.category_key,old.is_active) then return null; end if;
  if not exists(select 1 from public.alcohol_categories c where c.category_key=old.category_key and c.is_active) and exists(
    select 1 from public.catalog_taxonomy t where t.is_active and t.term_type in ('style','classification','ingredient','process','maturation')
    and t.metadata->'applies_to_categories' ? old.category_key) then
    raise exception using errcode='23514',message='category is still referenced by active catalog rules';
  end if;
  select * into category from public.alcohol_categories c where c.id=old.id;
  if not found then return null; end if;
  for related in select i.id from public.alcohol_items i where i.alcohol_category_id=category.id loop
    perform public.soolgyul_catalog_assert_item_assignment(related.id);
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.soolgyul_catalog_assignment_issues(category text, style text, target text, ingredients text[] DEFAULT '{}'::text[], processes text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  errors jsonb := '[]'; term public.catalog_taxonomy%rowtype;
  field text; keys text[]; key text; seen text[];
  types text[]; effective_target text := target;
begin
  if target is null or target not in ('product','release') then
    errors := errors || public.soolgyul_catalog_assignment_issue('invalid_target','target');
    effective_target := 'product';
  end if;
  if not exists(select 1 from public.alcohol_categories c where c.category_key=category and c.is_active) then
    errors := errors || public.soolgyul_catalog_assignment_issue('unknown_category','category_key');
  end if;
  if style is not null then
    select * into term from public.catalog_taxonomy t where t.term_type='style' and t.term_key=style and t.is_active;
    if not found then
      errors := errors || public.soolgyul_catalog_assignment_issue('unknown_term','style_key',style);
    elsif not coalesce(term.metadata->'applies_to_categories' ? category,false) then
      errors := errors || public.soolgyul_catalog_assignment_issue('wrong_category','style_key',style);
    end if;
  end if;
  foreach field in array array['ingredient_keys','production_process_keys'] loop
    keys := case field when 'ingredient_keys' then ingredients else processes end;
    types := case field when 'ingredient_keys' then array['ingredient'] else array['process','maturation'] end;
    seen := '{}';
    if keys is null or coalesce(array_ndims(keys),1) <> 1 then
      errors := errors || public.soolgyul_catalog_assignment_issue('invalid_array',field);
      continue;
    end if;
    if cardinality(keys)>64 then errors := errors || public.soolgyul_catalog_assignment_issue('too_many_terms',field); end if;
    foreach key in array keys loop
      if key is null or key !~ '^[a-z][a-z0-9_]*$' then
        errors := errors || public.soolgyul_catalog_assignment_issue('invalid_key',field);
        continue;
      end if;
      if key=any(seen) then errors := errors || public.soolgyul_catalog_assignment_issue('duplicate_term',field,key); end if;
      seen := array_append(seen,key);
      if (select count(*) from public.catalog_taxonomy t where t.term_type=any(types) and t.term_key=key and t.is_active) <> 1 then
        errors := errors || public.soolgyul_catalog_assignment_issue(
          case when exists(select 1 from public.catalog_taxonomy t where t.term_type=any(types) and t.term_key=key and t.is_active)
          then 'ambiguous_term' else 'unknown_term' end,field,key);
        continue;
      end if;
      select * into term from public.catalog_taxonomy t where t.term_type=any(types) and t.term_key=key and t.is_active;
      if not coalesce(term.metadata->'applies_to_categories' ? category,false) then
        errors := errors || public.soolgyul_catalog_assignment_issue('wrong_category',field,key);
      end if;
      if coalesce(jsonb_array_length(term.metadata->'applies_to_styles'),0)>0
         and not coalesce(term.metadata->'applies_to_styles' ? style,false) then
        errors := errors || public.soolgyul_catalog_assignment_issue('wrong_style',field,key);
      end if;
      if coalesce(term.metadata->>'allowed_target','both') not in (effective_target,'both') then
        errors := errors || public.soolgyul_catalog_assignment_issue('wrong_target',field,key);
      end if;
    end loop;
    for term in select t.* from public.catalog_taxonomy t where t.term_type=any(types) and t.term_key=any(seen) and t.is_active loop
      if exists(select 1 from jsonb_array_elements_text(coalesce(term.metadata->'excludes_term_keys','[]')) e where e.value=any(seen)) then
        errors := errors || public.soolgyul_catalog_assignment_issue('excluded_combination',field,term.term_key);
      end if;
    end loop;
  end loop;
  return (select coalesce(jsonb_agg(x order by x.code,x.field,x.key),'[]') from
    (select distinct e.code,e.field,e.key from jsonb_to_recordset(errors) as e(code text,field text,key text)) x);
end;
$function$;

CREATE OR REPLACE FUNCTION public.soolgyul_catalog_assignment_term_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare term public.catalog_taxonomy%rowtype; m jsonb; related record; key text;
begin
  if tg_op='UPDATE' and row(new.metadata,new.is_active,new.applicable_sections) is not distinct from row(old.metadata,old.is_active,old.applicable_sections) then return null; end if;
  select * into term from public.catalog_taxonomy t where t.term_type=new.term_type and t.term_key=new.term_key;
  if not found or term.term_type not in ('style','ingredient','process','maturation') then return null; end if;
  m := term.metadata;
  -- Reverse references also matter: an otherwise unused style may still be
  -- required by active production rules. Check final transaction state.
  if term.term_type='style' and exists(select 1 from public.catalog_taxonomy t
    where t.is_active and t.metadata->'applies_to_styles' ? term.term_key
    and (not term.is_active or not coalesce((m->'applies_to_categories') <@ (t.metadata->'applies_to_categories'),false))) then
    raise exception using errcode='23514',message='style is still referenced by active catalog rules';
  end if;
  if term.is_active then
    if jsonb_typeof(m->'applies_to_categories') is distinct from 'array' then
      raise exception using errcode='23514',message='invalid catalog rule categories';
    end if;
    if jsonb_array_length(m->'applies_to_categories')=0 or exists(
      select 1 from jsonb_array_elements(m->'applies_to_categories') v
      where jsonb_typeof(v) <> 'string' or not exists(select 1 from public.alcohol_categories c where c.category_key=v#>>'{}' and c.is_active)) then
      raise exception using errcode='23514',message='invalid catalog rule categories';
    end if;
    if term.term_type='style' and (jsonb_array_length(m->'applies_to_categories')<>1
      or (m ? 'category_key' and m->>'category_key' is distinct from m->'applies_to_categories'->>0)) then
      raise exception using errcode='23514',message='inconsistent style category';
    end if;
    foreach key in array array['applies_to_styles','excludes_term_keys'] loop
      if m ? key and jsonb_typeof(m->key) is distinct from 'array' then
        raise exception using errcode='23514',message='invalid catalog rule key array';
      end if;
      if exists(select 1 from jsonb_array_elements(coalesce(m->key,'[]')) v where jsonb_typeof(v)<>'string') then
        raise exception using errcode='23514',message='invalid catalog rule key array';
      end if;
    end loop;
    if exists(select 1 from jsonb_array_elements_text(coalesce(m->'applies_to_styles','[]')) v where not exists(
      select 1 from public.catalog_taxonomy s where s.term_type='style' and s.term_key=v.value and s.is_active
      and (s.metadata->'applies_to_categories') <@ (m->'applies_to_categories'))) then
      raise exception using errcode='23514',message='invalid catalog applicable style';
    end if;
    if exists(select 1 from jsonb_array_elements_text(coalesce(m->'excludes_term_keys','[]')) v where v.value=term.term_key or not exists(
      select 1 from public.catalog_taxonomy t where t.term_type=term.term_type and t.term_key=v.value)) then
      raise exception using errcode='23514',message='invalid catalog exclusion reference';
    end if;
  end if;
  -- Affect only assignments which reference the edited term.
  for related in select distinct i.id from public.alcohol_items i where
    (term.term_type='style' and i.style_key=term.term_key) or
    (term.term_type='ingredient' and term.term_key=any(i.ingredient_keys)) or
    (term.term_type in ('process','maturation') and term.term_key=any(i.production_process_keys)) loop
    perform public.soolgyul_catalog_assert_item_assignment(related.id);
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.soolgyul_catalog_search_projection_rows_v1()
 RETURNS TABLE(alcohol_item_id uuid, alcohol_release_id uuid, display_name text, secondary_name text, producer_or_brand_display text, category_key text, subcategory_key text, style_key text, country_code text, region_display text, abv_percent numeric, search_aliases text[], descriptor_keys text[], is_active boolean, published_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select i.id,null::uuid,i.name_ko,i.name_en,coalesce(producer.name_ko,producer.name_en),c.category_key,null::text,i.style_key,
 i.country_code,region_term.label_ko,i.abv_percent,
 coalesce(a.search_aliases,array[]::text[]),coalesce(t.descriptor_keys,array[]::text[]),
 true,i.published_at,i.updated_at
 from public.alcohol_items i join public.alcohol_categories c on c.id=i.alcohol_category_id and c.is_active
 left join public.producers producer on producer.id=i.producer_id
 left join public.catalog_taxonomy region_term on region_term.term_type='region' and region_term.term_key=i.region_key
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
$function$;

CREATE OR REPLACE FUNCTION public.soolgyul_catalog_term_keys_are_active(input_keys text[], allowed_term_types text[], required_sections text[] DEFAULT NULL::text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    input_keys is not null
    and public.soolgyul_catalog_text_array_is_valid(input_keys,64,'^[a-z][a-z0-9_]*(:[a-z][a-z0-9_]*)?$')
    and allowed_term_types is not null and cardinality(allowed_term_types)>0
    and allowed_term_types <@ array[
      'classification','style','ingredient','process','maturation','sensory_descriptor'
    ]::text[]
    and (required_sections is null or (
      cardinality(required_sections)>0 and required_sections <@ array[
        'classification','style','ingredient','production','maturation','aroma','palate','finish','texture'
      ]::text[]
    ))
    and not exists (
      select 1 from unnest(input_keys) assigned(term_key)
      where not exists (
        select 1 from public.catalog_taxonomy term
        where term.term_key=assigned.term_key and term.term_type=any(allowed_term_types)
          and term.is_active
          and (required_sections is null or term.applicable_sections && required_sections)
      )
    ),false
  )
$function$;

CREATE OR REPLACE FUNCTION public.soolgyul_my_recent_card_guides(p_limit integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(t.row_json order by t.created_at desc, t.id desc), '[]'::jsonb)
  from (
    select c.id, r.created_at,
      jsonb_build_object(
        'result_id', c.id::text,
        'kind_label', coalesce(style_term.label_ko, category_row.name_ko),
        'category_label', category_row.name_ko,
        'guide', c.rendered_snapshot #> '{bite,guide}'
      ) as row_json
    from public.drink_records r
    join public.taste_cards c
      on c.drink_record_id = r.id and c.lifecycle = 'final'
    join public.alcohol_items item_row on item_row.id = r.alcohol_item_id
    left join public.alcohol_categories category_row
      on category_row.id = item_row.alcohol_category_id
    left join public.catalog_taxonomy style_term
      on style_term.term_type = 'style' and style_term.term_key = item_row.style_key
    where r.user_id = auth.uid()
      and r.deleted_at is null
      and public.soolgyul_account_active(auth.uid())
      and jsonb_typeof(c.rendered_snapshot #> '{bite,guide}') = 'object'
    order by r.created_at desc, c.id desc
    limit greatest(1, least(coalesce(p_limit, 3), 10))
  ) t;
$function$;

CREATE OR REPLACE FUNCTION public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer DEFAULT 20)
 RETURNS TABLE(id uuid, name_ko text, name_en text, category_key text, style_key text, style_label text, abv_percent numeric, media_path text, country_code text, region text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
  left join public.catalog_taxonomy as style_term
    on style_term.term_type = 'style'
   and style_term.term_key = item.style_key
   and style_term.is_active
  left join public.catalog_taxonomy as region_term
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
$function$;

CREATE OR REPLACE FUNCTION public.soolgyul_validate_alcohol_item_catalog_terms()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT'
    or new.ingredient_keys is distinct from old.ingredient_keys
  then
    if not public.soolgyul_catalog_term_keys_are_active(
      new.ingredient_keys,
      array['ingredient'],
      array['ingredient']
    ) then
      raise exception 'ingredient_keys require active ingredient terms'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT'
    or new.production_process_keys is distinct from old.production_process_keys
  then
    if not public.soolgyul_catalog_term_keys_are_active(
      new.production_process_keys,
      array['process', 'maturation'],
      array['production', 'maturation']
    ) then
      raise exception
        'production_process_keys require active process or maturation terms'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT' or new.style_key is distinct from old.style_key then
    if new.style_key is not null
      and not public.soolgyul_catalog_term_keys_are_active(
        array[new.style_key], array['style'], array['style']
      )
    then
      raise exception 'style_key requires an active style term'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT' or new.region_key is distinct from old.region_key then
    if new.region_key is not null and not exists (
      select 1 from public.catalog_taxonomy term
      where term.term_type = 'region' and term.term_key = new.region_key and term.is_active
    ) then
      raise exception 'region_key requires an active region term'
        using errcode = '23514';
    end if;
  end if;

  return new;
end
$function$;

-- (5) nothing in the schema still names catalog_terms
do $$
declare
  offenders text;
begin
  select string_agg(p.proname, ', ' order by p.proname) into offenders
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosrc like '%catalog\_terms%';
  if offenders is not null then
    raise exception 'functions still read catalog_terms: %', offenders;
  end if;
  select string_agg(viewname, ', ' order by viewname) into offenders
  from pg_views where schemaname = 'public' and definition like '%catalog\_terms%';
  if offenders is not null then
    raise exception 'views still read catalog_terms: %', offenders;
  end if;
  select string_agg(name, ', ' order by name) into offenders
  from (
    select conname as name from pg_constraint where conrelid = 'public.catalog_taxonomy'::regclass
    union all
    select tgname from pg_trigger where tgrelid = 'public.catalog_taxonomy'::regclass and not tgisinternal
    union all
    select indexname from pg_indexes where schemaname = 'public' and tablename = 'catalog_taxonomy'
  ) named
  where starts_with(name, 'catalog_terms_');
  if offenders is not null then
    raise exception 'objects still named catalog_terms_*: %', offenders;
  end if;
end
$$;

commit;
