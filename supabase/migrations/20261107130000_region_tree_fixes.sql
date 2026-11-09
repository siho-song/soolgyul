-- Region tree fixes found while writing region explanations (2026-11-06): regions
-- filed under the wrong country, a winery used as a region, and products pointing at
-- them. Products move to the right row first, then the wrong rows go.

begin;

update public.catalog_terms set parent_term_key = 'ca' where term_type = 'region' and term_key = 'ca_ontario';
update public.catalog_terms set parent_term_key = 'ca_ontario' where term_type = 'region' and term_key = 'ca_niagara_peninsula';
update public.alcohol_items set region_key = 'fr', country_code = 'FR' where id = 'c0786a33-a18f-56b0-b928-1be1818d13b6';
update public.alcohol_items set region_key = 'ca_niagara_peninsula', country_code = 'CA' where id = 'e79ac3c8-0fde-59f8-bf81-dea5d36cca9d';
update public.alcohol_items set region_key = 'us_napa_valley_ava', country_code = 'US' where id = '77ba4513-709d-5733-b3b7-ccc99288a320';
update public.alcohol_items set region_key = null, country_code = 'FR' where id = '2cf94dc2-3d54-5fa2-acfb-b569b41fd78a';
update public.alcohol_items set region_key = null, country_code = 'CN' where id = '864ecc42-5700-565c-8041-8329c9ddc519';
update public.alcohol_items set region_key = 'ar_mendoza', country_code = 'AR' where id = '779b07fd-9c48-57d5-86e6-429f642ee183';
update public.alcohol_items set region_key = 'ar_mendoza', country_code = 'AR' where id = '066e9c3e-aeda-5090-9cfd-e8d0d5c92eab';
delete from public.catalog_terms where term_type = 'region' and term_key in ('fr_cholchagua_valley', 'fr_rapel_valley', 'fr_central_valley', 'it_napa_valley_ava', 'it_napa_county', 'it_california', 'cn_piemonte', 'ca_bear_river', 'ar_central_valley');

commit;
