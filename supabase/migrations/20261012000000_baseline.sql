-- Baseline: the live Supabase schema as of 2026-10-12, replacing all earlier migrations.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- A fresh Supabase project grants anon/authenticated on every new public
-- object through default privileges, while this dump only records the explicit
-- grants live carries. Switch the defaults off first so a replay ends with the
-- same privileges as live.
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated;
--
-- PostgreSQL database dump
--

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.9 (Ubuntu 17.9-1.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

--
-- Name: sensory_level_5; Type: DOMAIN; Schema: public; Owner: -
--

CREATE DOMAIN public.sensory_level_5 AS numeric
	CONSTRAINT sensory_level_5_integer_check CHECK ((((VALUE >= (1)::numeric) AND (VALUE <= (5)::numeric)) AND (VALUE = trunc(VALUE))));

--
-- Name: DOMAIN sensory_level_5; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON DOMAIN public.sensory_level_5 IS 'Sensory integer level: 1 lowest, 2 low, 3 medium, 4 medium-high, 5 high; NULL unknown. Fractional inputs are rejected.';

--
-- Name: apply_sensory_product_claims(uuid, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_sensory_product_claims(item_id uuid, source jsonb, entry jsonb) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare item public.alcohol_items%rowtype; claim jsonb;
 process_additions text[]:='{}'; classification_additions text[]:='{}'; ingredient_additions text[]:='{}'; processes text[]; classifications text[]; ingredients text[];
begin
 if jsonb_typeof(entry->'productionClaims') is distinct from 'array' or jsonb_array_length(entry->'productionClaims')>64 then raise exception 'invalid production claims';end if;
 select * into item from public.alcohol_items i where i.id=item_id and i.publish_status in ('published','staging') for update;
 if not found then return false;end if;
 if item.updated_at is distinct from (entry->>'itemUpdatedAt')::timestamptz or md5(public.sensory_item_assignment_snapshot(to_jsonb(item))::text) is distinct from entry->>'itemSourceFingerprint' then return false;end if;
 for claim in select value from jsonb_array_elements(entry->'productionClaims') loop
  if jsonb_typeof(claim) is distinct from 'object' or (select count(*) from jsonb_object_keys(claim))<>4
   or exists(select 1 from jsonb_object_keys(claim) k where k not in ('sourceField','excerpt','field','key'))
   or length(coalesce(claim->>'excerpt',''))=0 or position(claim->>'excerpt' in coalesce(source->>(claim->>'sourceField'),''))=0
   or not coalesce((claim->>'sourceField'='palate_note' and claim->>'field'='ingredient_keys' and claim->>'key'='rice_omachi' and public.sensory_literal_omachi_rice(claim->>'excerpt')) or (claim->>'sourceField'='aroma_note' and claim->>'field'='production_process_keys' and claim->>'key'='oak_wood' and public.sensory_literal_oak_vanilla_aroma(claim->>'excerpt'))
    or (claim->>'sourceField'='finish_note' and claim->>'field'='production_process_keys' and claim->>'key'='oak_wood' and public.sensory_literal_oak_named_long_aroma(claim->>'excerpt')) or (claim->>'sourceField'='palate_note' and public.sensory_literal_cold_sake_oak(claim->>'excerpt') and (
      (claim->>'field'='production_process_keys' and claim->>'key'='oak_wood') or (claim->>'field'='classification_keys' and claim->>'key' in ('sake_treatment:sake_genshu','sake_treatment:sake_nama')))) or (claim->>'sourceField'='palate_note' and public.sensory_literal_rice_water_sake(claim->>'excerpt') and ((claim->>'field'='classification_keys' and claim->>'key' in ('sake_treatment:sake_nama','sake_treatment:sake_muroka')) or (claim->>'field'='production_process_keys' and claim->>'key' in ('unpasteurised','unfiltered_claim','rice_water_only_claim')) or (claim->>'field'='ingredient_keys' and claim->>'key' in ('rice','water_material')))),false)
   then raise exception 'unsupported literal production assignment';end if;
  if claim->>'field'='production_process_keys' then process_additions=array_append(process_additions,claim->>'key');elsif claim->>'field'='classification_keys' then classification_additions=array_append(classification_additions,claim->>'key');else ingredient_additions=array_append(ingredient_additions,claim->>'key');end if;
 end loop;
 select coalesce(array_agg(key order by first_seen),'{}') into processes from (
  select key,min(ordinal) first_seen from unnest(coalesce(item.production_process_keys,'{}')||process_additions) with ordinality t(key,ordinal) group by key
 ) keys;
 select coalesce(array_agg(key order by first_seen),'{}') into classifications from (
  select key,min(ordinal) first_seen from unnest(coalesce(item.classification_keys,'{}')||classification_additions) with ordinality t(key,ordinal) group by key
 ) keys;
 select coalesce(array_agg(key order by first_seen),'{}') into ingredients from (
  select key,min(ordinal) first_seen from unnest(coalesce(item.ingredient_keys,'{}')||ingredient_additions) with ordinality t(key,ordinal) group by key
 ) keys;
 if 'unpasteurised'=any(processes) and 'pasteurised'=any(processes) then raise exception 'conflicting pasteurisation assignments';end if;
 if processes is distinct from item.production_process_keys or classifications is distinct from item.classification_keys or ingredients is distinct from item.ingredient_keys then
  update public.alcohol_items set production_process_keys=processes,classification_keys=classifications,ingredient_keys=ingredients,updated_at=clock_timestamp() where id=item.id;
 end if;
 perform public.soolgyul_catalog_assert_item_assignment(item.id);
 select * into item from public.alcohol_items i where i.id=item_id;
 if md5(public.sensory_item_assignment_snapshot(to_jsonb(item))::text) is distinct from entry->>'expectedItemFingerprint' then raise exception 'production assignment verification failed';end if;
 return true;
end;
$$;

--
-- Name: soolgyul_catalog_text_array_is_valid(text[], integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_text_array_is_valid(input_values text[], max_items integer, key_pattern text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO ''
    AS $$
  select coalesce(
    input_values is not null
    and max_items >= 0
    and cardinality(input_values) <= max_items
    and not exists (
      select 1
      from unnest(input_values) value
      where value is null
         or nullif(btrim(value), '') is null
         or value <> btrim(value)
         or value <> normalize(value, NFC)
         or (key_pattern is not null and value !~ key_pattern)
    )
    and cardinality(input_values) = (
      select count(distinct public.soolgyul_normalize_catalog_text(value))
      from unnest(input_values) value
    ),
    false
  )
$$;

--
-- Name: valid_coded_sensory(jsonb, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.valid_coded_sensory(p jsonb, item_id uuid) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
declare entry jsonb; proof jsonb;
begin
 if p is null then return true;end if;
 if jsonb_typeof(p) is distinct from 'object' or p->'profile' is null or p->'profile'='null'::jsonb or p->'semantics' is null or p->'semantics'='null'::jsonb
 or not public.valid_product_sensory_facts(p->'profile',item_id) or not public.valid_product_sensory_semantics(p->'semantics',item_id) then return false;end if;
 if exists(select 1 from jsonb_object_keys(p) k where k not in ('profile','semantics')) then return false;end if;
 if exists(select 1 from jsonb_object_keys(p->'profile') k where k not in ('schemaVersion','scaleVersion','itemId','facts')) or exists(select 1 from jsonb_object_keys(p->'semantics') k where k not in ('schemaVersion','itemId','entries')) then return false;end if;
 for entry in select value from jsonb_array_elements((p#>'{profile,facts}')||(p#>'{semantics,entries}')) loop
  if entry->>'state'='unknown' or exists(select 1 from jsonb_object_keys(entry) k where k not in ('target','attribute','identity','state','value','evidence')) then return false;end if;
  if entry ? 'target' and entry ? 'identity' then return false;end if;
  if entry ? 'identity' and entry ? 'attribute' then return false;end if;
  if entry ? 'target' and exists(select 1 from jsonb_object_keys(entry->'target') k where k not in ('kind','key','section')) then return false;end if;
  if entry ? 'identity' and exists(select 1 from jsonb_object_keys(entry->'identity') k where k not in ('kind','target','from','to','section','textureKey','sourceKey','colourKey','minimum','maximum','conditionKey','comparisonKey','originKey')) then return false;end if;
  if entry ? 'identity' then
   if exists(select 1 from jsonb_each(entry->'identity') pair cross join lateral jsonb_object_keys(case when pair.key in ('target','from','to') then pair.value else '{}'::jsonb end) k where k not in ('kind','key','section')) then return false;end if;
   if exists(select 1 from jsonb_object_keys(entry->'identity') k where not k=any(case entry#>>'{identity,kind}'
     when 'intensity_ceiling' then array['kind','target'] when 'duration_ceiling' then array['kind','target'] when 'prominence' then array['kind','target'] when 'target_harmony' then array['kind','target'] when 'target_masking' then array['kind','target']
     when 'conditional_character' then array['kind','target','sourceKey','conditionKey','comparisonKey','originKey'] when 'character_source' then array['kind','target','sourceKey'] when 'character_intensity' then array['kind','target','sourceKey'] when 'contrast' then array['kind','from','to'] when 'harmony' then array['kind','from','to'] when 'masking' then array['kind','from','to']
     when 'appearance_colour' then array['kind','section','colourKey'] when 'tannin_prominence' then array['kind','section'] when 'sequence' then array['kind','from','to'] when 'tannin_harmony' then array['kind','target'] when 'stronger_than' then array['kind','from','to'] when 'body_range' then array['kind','section','minimum','maximum'] when 'tannin_balance' then array['kind','section'] when 'support' then array['kind','from','to'] when 'layer_under' then array['kind','from','to'] when 'balance' then array['kind','section'] when 'tannin_texture' then array['kind','section','textureKey'] else array['kind'] end)) then return false;end if;
  end if;
  for proof in select value from jsonb_array_elements(entry->'evidence') loop
   if proof ? 'interpretation' and (proof->>'interpretation' is distinct from 'finish_weight_to_cleanliness' or entry->'target' is distinct from '{"kind":"axis","key":"finish_cleanliness","section":"finish"}'::jsonb or entry->>'attribute' is distinct from 'intensity') then return false;end if;
   if exists(select 1 from jsonb_object_keys(proof) k where k not in ('sourceRef','sourceField','excerpt','value','interpretation')) or proof->>'sourceField' not in ('coded_aroma_note','coded_palate_note','coded_texture_note','coded_finish_note','coded_overall_note','coded_body_note')
    or proof->>'sourceRef' is distinct from 'catalog:product:'||item_id::text||':'||(proof->>'sourceField')
    or proof->>'excerpt' is distinct from proof->>'value' then return false;end if;
  end loop;
 end loop;
 return true;
exception when others then return false;
end;
$$;

--
-- Name: valid_product_sensory_facts(jsonb, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.valid_product_sensory_facts(p jsonb, item_id uuid) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
declare f jsonb; e jsonb; k text; seen text[] := '{}'; vals jsonb[]; expected_kind text;
 descriptor_sections constant jsonb := '{"hay": ["aroma", "finish", "palate"], "hop": ["aroma", "finish", "palate"], "oak": ["aroma", "finish", "palate"], "oat": ["aroma", "palate", "finish"], "pea": ["aroma"], "pie": ["aroma", "palate", "finish"], "rye": ["aroma", "palate", "finish"], "tar": ["aroma", "finish", "palate"], "tea": ["aroma", "finish", "palate"], "ume": ["aroma", "finish", "palate"], "wax": ["aroma", "palate", "finish"], "cake": ["aroma", "palate", "finish"], "char": ["aroma", "finish", "palate"], "corn": ["aroma", "palate", "finish"], "date": ["aroma", "finish", "palate"], "dill": ["aroma", "finish", "palate"], "iris": ["aroma", "palate", "finish"], "iron": ["aroma", "palate", "finish"], "kiwi": ["aroma", "finish", "palate"], "koji": ["aroma", "finish", "palate"], "leaf": ["aroma", "palate"], "lily": ["aroma", "finish", "palate"], "lime": ["aroma", "finish", "palate"], "malt": ["aroma", "finish", "palate"], "milk": ["aroma", "palate", "finish"], "mint": ["aroma", "finish", "palate"], "musk": ["aroma", "finish", "palate"], "pear": ["aroma", "finish", "palate"], "peat": ["aroma", "finish", "palate"], "pine": ["aroma", "finish", "palate"], "plum": ["aroma", "finish", "palate"], "rice": ["aroma", "finish", "palate"], "rose": ["aroma", "finish", "palate"], "sage": ["aroma", "finish", "palate"], "talc": ["aroma", "palate", "finish"], "tart": ["aroma", "palate", "finish"], "wood": ["aroma", "finish", "palate"], "yuzu": ["aroma", "finish", "palate"], "agave": ["aroma", "finish", "palate"], "anise": ["aroma", "finish", "palate"], "apple": ["aroma", "finish", "palate"], "bacon": ["aroma", "palate", "finish"], "basil": ["aroma", "finish", "palate"], "berry": ["aroma", "finish", "palate"], "bread": ["aroma", "finish", "palate"], "brett": ["aroma", "finish"], "broth": ["aroma", "finish", "palate"], "candy": ["aroma", "palate", "finish"], "cedar": ["aroma", "finish", "palate"], "chalk": ["aroma", "palate", "finish"], "clove": ["aroma", "finish", "palate"], "cocoa": ["aroma", "finish", "palate"], "cream": ["aroma", "finish", "palate"], "dairy": ["aroma", "finish", "palate"], "earth": ["aroma", "finish", "palate"], "ester": ["aroma"], "flint": ["aroma", "finish", "palate"], "fudge": ["aroma", "palate", "finish"], "grape": ["aroma", "finish", "palate"], "grass": ["aroma", "finish", "palate"], "guava": ["aroma", "finish", "palate"], "honey": ["aroma", "finish", "palate"], "jammy": ["aroma", "finish", "palate"], "jelly": ["aroma", "palate", "finish"], "lemon": ["aroma", "finish", "palate"], "lilac": ["aroma", "finish", "palate"], "mango": ["aroma", "finish", "palate"], "meaty": ["aroma", "palate", "finish"], "melon": ["aroma", "finish", "palate"], "mocha": ["aroma", "finish", "palate"], "nuruk": ["aroma", "finish", "palate"], "nutty": ["aroma", "finish", "palate"], "olive": ["aroma", "palate", "finish"], "omija": ["aroma", "finish", "palate"], "peach": ["aroma", "finish", "palate"], "pecan": ["aroma", "finish", "palate"], "prune": ["aroma", "finish", "palate"], "shiso": ["aroma", "palate"], "slate": ["aroma", "finish", "palate"], "smoke": ["aroma", "finish", "palate"], "spice": ["aroma", "finish", "palate"], "syrup": ["aroma", "palate", "finish"], "thyme": ["aroma", "finish", "palate"], "toast": ["aroma", "finish", "palate"], "wafer": ["aroma", "palate", "finish"], "wheat": ["aroma", "palate", "finish"], "yeast": ["aroma", "finish", "palate"], "acacia": ["aroma", "finish", "palate"], "almond": ["aroma", "finish", "palate"], "azalea": ["aroma"], "bakery": ["aroma", "finish", "palate"], "banana": ["aroma", "finish", "palate"], "barley": ["aroma", "finish", "palate"], "butter": ["aroma", "finish", "palate"], "cashew": ["aroma", "finish", "palate"], "celery": ["aroma"], "cereal": ["aroma", "finish", "palate"], "cheese": ["aroma", "finish", "palate"], "cherry": ["aroma", "finish", "palate"], "chilli": ["aroma", "palate", "finish"], "citrus": ["aroma", "finish", "palate"], "coffee": ["aroma", "finish", "palate"], "cognac": ["finish"], "cookie": ["aroma", "palate", "finish"], "fennel": ["aroma", "palate", "finish"], "floral": ["aroma", "finish", "palate"], "ginger": ["aroma", "finish", "palate"], "herbal": ["aroma", "finish", "palate"], "iodine": ["aroma", "finish", "palate"], "jujube": ["aroma", "palate", "finish"], "kabosu": ["aroma", "finish", "palate"], "kirsch": ["aroma", "palate", "finish"], "lactic": ["aroma", "finish", "palate"], "lychee": ["aroma", "finish", "palate"], "matcha": ["aroma", "finish", "palate"], "muscat": ["aroma", "palate", "finish"], "myrtle": ["aroma", "palate", "finish"], "nougat": ["aroma", "finish", "palate"], "nutmeg": ["aroma", "finish", "palate"], "orange": ["aroma", "finish", "palate"], "papaya": ["aroma", "finish", "palate"], "pastry": ["aroma", "finish", "palate"], "peanut": ["aroma", "palate", "finish"], "pepper": ["aroma", "finish", "palate"], "petrol": ["aroma", "finish", "palate"], "pomelo": ["aroma", "finish", "palate"], "potato": ["aroma", "finish", "palate"], "quince": ["aroma", "finish", "palate"], "raisin": ["aroma", "finish", "palate"], "ramune": ["aroma", "finish", "palate"], "rancio": ["aroma", "palate", "finish"], "saline": ["aroma", "finish", "palate"], "sansho": ["aroma", "palate", "finish"], "savory": ["aroma", "finish", "palate"], "sesame": ["aroma", "finish", "palate"], "sherry": ["aroma", "finish", "palate"], "tannin": ["palate", "texture", "finish"], "toffee": ["aroma", "finish", "palate"], "tomato": ["aroma", "finish", "palate"], "violet": ["aroma", "finish", "palate"], "walnut": ["aroma", "finish", "palate"], "apricot": ["aroma", "finish", "palate"], "asphalt": ["aroma", "palate", "finish"], "beeswax": ["aroma", "palate"], "biscuit": ["aroma", "finish", "palate"], "bonfire": ["aroma", "finish", "palate"], "bramble": ["aroma", "finish", "palate"], "brioche": ["aroma", "finish", "palate"], "caramel": ["aroma", "finish", "palate"], "coconut": ["aroma", "finish", "palate"], "compote": ["aroma", "palate", "finish"], "currant": ["aroma", "finish", "palate"], "custard": ["aroma", "finish", "palate"], "freesia": ["aroma", "palate", "finish"], "ginseng": ["aroma", "finish", "palate"], "guarana": ["aroma", "finish", "palate"], "heather": ["aroma", "palate", "finish"], "incense": ["aroma", "palate", "finish"], "jasmine": ["aroma", "finish", "palate"], "juniper": ["aroma", "finish", "palate"], "kumquat": ["aroma", "palate", "finish"], "leather": ["aroma", "finish", "palate"], "madeira": ["finish"], "menthol": ["aroma", "palate", "finish"], "mineral": ["aroma", "finish", "palate"], "mugwort": ["aroma", "palate", "finish"], "oregano": ["aroma", "palate", "finish"], "pancake": ["aroma", "palate", "finish"], "paprika": ["aroma", "palate", "finish"], "popcorn": ["aroma", "palate", "finish"], "praline": ["aroma", "palate", "finish"], "pudding": ["aroma", "palate", "finish"], "rhubarb": ["aroma", "palate", "finish"], "roasted": ["aroma", "finish", "palate"], "saffron": ["aroma", "palate", "finish"], "seaweed": ["aroma", "finish", "palate"], "solvent": ["aroma", "finish"], "sorghum": ["aroma", "palate", "finish"], "sudachi": ["aroma"], "tobacco": ["aroma", "finish", "palate"], "truffle": ["aroma", "finish", "palate"], "vanilla": ["aroma", "finish", "palate"], "vegetal": ["aroma", "finish", "palate"], "vinegar": ["aroma", "palate", "finish"], "allspice": ["aroma", "palate", "finish"], "amaretto": ["finish"], "animalic": ["aroma", "finish", "palate"], "balsamic": ["aroma", "palate", "finish"], "barbecue": ["aroma", "palate", "finish"], "bay_leaf": ["aroma", "finish", "palate"], "bergamot": ["aroma", "palate"], "bilberry": ["aroma", "finish", "palate"], "bokbunja": ["aroma", "palate", "finish"], "cardamom": ["aroma", "palate", "finish"], "chestnut": ["aroma", "palate", "finish"], "cilantro": ["aroma", "palate", "finish"], "cinnamon": ["aroma", "finish", "palate"], "cucumber": ["aroma", "finish", "palate"], "dark_rum": ["palate"], "espresso": ["aroma", "palate", "finish"], "firewood": ["aroma", "palate", "finish"], "garrigue": ["aroma", "palate", "finish"], "geranium": ["aroma", "palate", "finish"], "graphite": ["aroma", "finish", "palate"], "hawthorn": ["aroma", "palate"], "hazelnut": ["aroma", "finish", "palate"], "hibiscus": ["aroma", "palate", "finish"], "honeydew": ["aroma", "palate", "finish"], "jalapeno": ["aroma"], "kola_nut": ["aroma"], "lavender": ["aroma", "finish", "palate"], "mandarin": ["aroma", "finish", "palate"], "marzipan": ["aroma", "finish", "palate"], "meringue": ["aroma", "palate", "finish"], "metallic": ["aroma", "palate", "finish"], "mulberry": ["aroma", "palate", "finish"], "mushroom": ["aroma", "finish", "palate"], "phenolic": ["palate"], "red_bean": ["aroma", "finish", "palate"], "rosemary": ["aroma", "finish", "palate"], "tamarind": ["palate", "finish"], "tiramisu": ["aroma", "palate", "finish"], "wet_leaf": ["aroma", "finish", "palate"], "wisteria": ["aroma", "palate", "finish"], "asparagus": ["aroma", "palate", "finish"], "black_tea": ["aroma", "finish", "palate"], "blueberry": ["aroma", "finish", "palate"], "bubblegum": ["aroma", "finish", "palate"], "buckwheat": ["aroma", "finish"], "chamomile": ["aroma", "finish", "palate"], "chocolate": ["aroma", "finish", "palate"], "cola_note": ["aroma", "palate", "finish"], "cranberry": ["aroma", "finish", "palate"], "dried_fig": ["aroma", "finish", "palate"], "dry_earth": ["aroma", "finish", "palate"], "earl_grey": ["aroma", "finish"], "fig_syrup": ["aroma", "palate", "finish"], "fresh_fig": ["aroma", "finish", "palate"], "green_tea": ["aroma", "palate", "finish"], "honeybush": ["aroma"], "honeycomb": ["aroma", "palate", "finish"], "jackfruit": ["aroma", "palate", "finish"], "lime_peel": ["aroma", "finish", "palate"], "limestone": ["aroma", "palate", "finish"], "liquorice": ["aroma", "finish", "palate"], "macadamia": ["aroma", "finish", "palate"], "marmalade": ["aroma", "finish", "palate"], "medicinal": ["aroma", "finish", "palate"], "nectarine": ["aroma", "finish", "palate"], "osmanthus": ["aroma"], "pineapple": ["aroma", "finish", "palate"], "raspberry": ["aroma", "finish", "palate"], "red_apple": ["aroma", "palate", "finish"], "red_berry": ["aroma", "palate", "finish"], "red_fruit": ["aroma", "finish", "palate"], "rice_bran": ["aroma"], "ripe_pear": ["aroma", "palate", "finish"], "ripe_plum": ["aroma", "finish", "palate"], "root_beer": ["aroma", "palate", "finish"], "shikuwasa": ["aroma", "palate"], "soy_sauce": ["aroma", "finish", "palate"], "spearmint": ["aroma", "palate", "finish"], "sugarcane": ["aroma", "palate", "finish"], "sulfurous": ["aroma", "finish", "palate"], "tangerine": ["aroma", "palate", "finish"], "tree_moss": ["aroma", "palate", "finish"], "wet_chalk": ["aroma", "palate", "finish"], "wet_earth": ["aroma", "finish", "palate"], "wet_stone": ["aroma", "finish", "palate"], "wine_note": ["aroma", "palate", "finish"], "yuzu_peel": ["aroma", "palate", "finish"], "apple_mint": ["aroma", "palate", "finish"], "apple_peel": ["aroma", "finish", "palate"], "black_plum": ["aroma", "palate", "finish"], "blackberry": ["aroma", "finish", "palate"], "brazil_nut": ["aroma", "palate", "finish"], "cherry_pie": ["aroma", "palate", "finish"], "cherry_pit": ["finish"], "citrus_oil": ["aroma", "palate", "finish"], "clementine": ["aroma", "palate", "finish"], "cocoa_nibs": ["aroma", "palate", "finish"], "corn_syrup": ["palate"], "dark_berry": ["aroma", "palate", "finish"], "dried_herb": ["aroma", "finish", "palate"], "elderberry": ["aroma", "palate", "finish"], "eucalyptus": ["aroma", "finish", "palate"], "frangipani": ["aroma"], "fresh_herb": ["aroma", "finish", "palate"], "fresh_pear": ["aroma", "finish", "palate"], "fresh_plum": ["aroma", "finish", "palate"], "fruit_cake": ["aroma", "palate", "finish"], "gooseberry": ["aroma", "finish", "palate"], "grape_skin": ["aroma", "palate", "finish"], "grapefruit": ["aroma", "finish", "palate"], "green_pear": ["aroma", "palate", "finish"], "guava_peel": ["aroma", "palate", "finish"], "lemon_balm": ["aroma", "palate", "finish"], "lemon_curd": ["aroma", "palate", "finish"], "lemon_lime": ["aroma", "finish", "palate"], "lemon_peel": ["aroma", "finish", "palate"], "lemon_tart": ["aroma", "palate", "finish"], "lemongrass": ["aroma", "finish", "palate"], "lotus_leaf": ["aroma", "palate", "finish"], "maple_note": ["aroma", "palate", "finish"], "melon_peel": ["palate"], "mid_palate": ["palate"], "musk_melon": ["aroma", "palate", "finish"], "oolong_tea": ["aroma", "palate", "finish"], "peppercorn": ["aroma", "palate", "finish"], "peppermint": ["aroma", "palate", "finish"], "pine_resin": ["aroma", "finish", "palate"], "plant_note": ["palate"], "red_cherry": ["aroma", "palate", "finish"], "red_chilli": ["aroma", "palate", "finish"], "red_flower": ["aroma", "finish", "palate"], "redcurrant": ["aroma", "finish", "palate"], "ripe_apple": ["aroma", "finish", "palate"], "ripe_peach": ["aroma", "finish", "palate"], "rose_apple": ["palate"], "rose_water": ["aroma", "palate", "finish"], "rum_raisin": ["aroma", "palate", "finish"], "sandalwood": ["aroma", "palate", "finish"], "shell_note": ["aroma", "palate", "finish"], "shortbread": ["aroma", "palate", "finish"], "star_anise": ["aroma", "palate", "finish"], "strawberry": ["aroma", "finish", "palate"], "sweet_pear": ["aroma", "finish", "palate"], "sweet_plum": ["aroma", "finish", "palate"], "tart_scent": ["aroma"], "toffee_nut": ["aroma", "palate", "finish"], "watermelon": ["aroma", "palate", "finish"], "wheatgrass": ["aroma"], "wild_berry": ["aroma", "palate", "finish"], "wild_fruit": ["aroma", "palate", "finish"], "wood_smoke": ["aroma", "palate", "finish"], "yeast_lees": ["aroma", "palate", "finish"], "apple_cider": ["aroma", "finish", "palate"], "apple_honey": ["aroma", "palate", "finish"], "apple_juice": ["aroma", "palate", "finish"], "baked_apple": ["aroma", "palate", "finish"], "bamboo_leaf": ["aroma", "finish"], "banana_chip": ["aroma", "palate", "finish"], "bell_pepper": ["aroma", "finish", "palate"], "bing_cherry": ["aroma", "palate", "finish"], "black_fruit": ["aroma", "finish", "palate"], "black_olive": ["aroma", "palate", "finish"], "borisu_note": ["aroma", "palate", "finish"], "boysenberry": ["aroma", "palate", "finish"], "brandy_note": ["aroma", "palate", "finish"], "broad_aroma": ["aroma"], "brown_sugar": ["aroma", "finish", "palate"], "cherry_tart": ["aroma", "palate", "finish"], "cherry_wood": ["aroma", "palate"], "citrus_peel": ["aroma", "palate", "finish"], "dried_fruit": ["aroma", "finish", "palate"], "elderflower": ["aroma", "finish", "palate"], "fresh_apple": ["aroma", "finish", "palate"], "fresh_fruit": ["aroma", "finish", "palate"], "fresh_peach": ["aroma", "finish", "palate"], "fruit_candy": ["aroma", "palate", "finish"], "fruit_syrup": ["aroma", "palate", "finish"], "ginjo_aroma": ["aroma", "finish", "palate"], "golden_kiwi": ["aroma", "palate", "finish"], "grape_juice": ["aroma", "palate", "finish"], "green_apple": ["aroma", "finish", "palate"], "green_grape": ["aroma", "finish", "palate"], "green_olive": ["aroma", "palate", "finish"], "honeysuckle": ["aroma", "finish", "palate"], "kaffir_lime": ["aroma", "palate", "finish"], "kyoho_grape": ["aroma"], "lemon_candy": ["aroma", "palate"], "lemon_juice": ["aroma", "palate", "finish"], "lingonberry": ["aroma"], "maple_syrup": ["aroma", "palate", "finish"], "marshmallow": ["aroma", "palate", "finish"], "meyer_lemon": ["aroma", "palate", "finish"], "orange_peel": ["aroma", "finish", "palate"], "pine_needle": ["aroma", "palate", "finish"], "pink_pepper": ["aroma", "palate", "finish"], "pomegranate": ["aroma", "finish", "palate"], "ripe_cherry": ["aroma", "finish", "palate"], "rose_petals": ["aroma", "palate", "finish"], "sour_cherry": ["aroma", "palate", "finish"], "stone_fruit": ["aroma", "finish", "palate"], "sugar_aroma": ["aroma", "palate", "finish"], "sweet_apple": ["aroma", "finish", "palate"], "sweet_peach": ["aroma", "finish", "palate"], "tomato_leaf": ["aroma", "palate", "finish"], "white_fruit": ["aroma", "palate", "finish"], "white_lilac": ["aroma", "palate", "finish"], "white_melon": ["aroma", "palate", "finish"], "white_peach": ["aroma", "palate", "finish"], "wine_barrel": ["aroma", "palate", "finish"], "apple_butter": ["aroma", "palate", "finish"], "baking_spice": ["aroma", "palate", "finish"], "barrel_toast": ["aroma", "finish", "palate"], "black_cherry": ["aroma", "finish", "palate"], "black_pepper": ["aroma", "finish", "palate"], "blackcurrant": ["aroma", "finish", "palate"], "blood_orange": ["aroma", "finish", "palate"], "bourbon_note": ["aroma", "palate", "finish"], "butterscotch": ["aroma", "finish", "palate"], "cocoa_butter": ["aroma", "palate"], "cookie_dough": ["palate"], "cotton_candy": ["aroma", "palate", "finish"], "cream_cheese": ["aroma", "palate", "finish"], "creme_brulee": ["aroma", "palate", "finish"], "dark_caramel": ["aroma", "palate", "finish"], "dragon_fruit": ["aroma", "palate", "finish"], "dried_flower": ["aroma", "finish", "palate"], "fermentation": ["aroma", "finish", "palate"], "fine_bubbles": ["finish", "palate", "texture"], "firm_texture": ["finish", "palate", "texture"], "floral_honey": ["aroma", "palate", "finish"], "forest_floor": ["aroma", "palate", "finish"], "fresh_cherry": ["aroma", "palate", "finish"], "ginger_candy": ["aroma", "palate", "finish"], "golden_apple": ["aroma", "palate", "finish"], "honeyed_pear": ["aroma", "palate", "finish"], "juniper_wood": ["aroma", "palate", "finish"], "korean_melon": ["aroma", "palate"], "kumquat_peel": ["finish"], "lemon_sorbet": ["aroma", "palate", "finish"], "lotus_flower": ["aroma", "palate", "finish"], "manuka_honey": ["aroma", "palate", "finish"], "oily_texture": ["finish", "palate", "texture"], "orange_juice": ["aroma", "palate", "finish"], "oyster_shell": ["aroma", "palate", "finish"], "pear_blossom": ["aroma", "palate", "finish"], "plum_blossom": ["aroma", "palate", "finish"], "rich_texture": ["finish", "palate", "texture"], "sakura_mochi": ["palate"], "slim_texture": ["texture"], "smoked_bacon": ["aroma", "palate"], "soft_bubbles": ["finish", "palate", "texture"], "soft_texture": ["finish", "palate", "texture"], "stewed_apple": ["aroma", "palate", "finish"], "sweet_cherry": ["aroma", "finish", "palate"], "sweet_potato": ["aroma", "finish", "palate"], "taut_texture": ["palate", "texture", "finish"], "tomato_paste": ["aroma", "palate", "finish"], "tteokgal_oak": ["aroma", "palate", "finish"], "unripe_fruit": ["aroma", "palate", "finish"], "waxy_texture": ["finish", "palate", "texture"], "white_flower": ["aroma", "finish", "palate"], "white_pepper": ["aroma", "finish", "palate"], "yellow_apple": ["aroma", "palate", "finish"], "yellow_fruit": ["aroma", "palate", "finish"], "aged_aromatic": ["aroma", "palate", "finish"], "alcohol_aroma": ["aroma"], "annurca_apple": ["aroma", "palate", "finish"], "apple_blossom": ["aroma", "palate", "finish"], "bitter_orange": ["aroma", "palate", "finish"], "bread_pudding": ["aroma", "palate", "finish"], "candied_fruit": ["aroma", "palate", "finish"], "chewy_texture": ["finish", "palate", "texture"], "chrysanthemum": ["aroma", "palate", "finish"], "creme_caramel": ["aroma", "palate", "finish"], "crisp_acidity": ["palate", "finish"], "dense_bubbles": ["palate", "texture", "finish"], "dried_apricot": ["aroma", "finish", "palate"], "dry_character": ["finish", "palate"], "essential_oil": ["palate"], "foamy_texture": ["finish", "palate", "texture"], "fresh_acidity": ["finish", "palate"], "heavy_texture": ["finish", "palate", "texture"], "juicy_texture": ["finish", "palate", "texture"], "korean_cherry": ["aroma", "palate"], "light_texture": ["finish", "palate", "texture"], "moist_texture": ["palate", "texture", "finish"], "molasses_note": ["aroma", "finish", "palate"], "orchard_fruit": ["aroma", "finish", "palate"], "passion_fruit": ["aroma", "finish", "palate"], "peach_blossom": ["aroma", "palate"], "peanut_butter": ["aroma", "palate", "finish"], "poached_fruit": ["aroma", "palate", "finish"], "powdered_sage": ["aroma", "palate", "finish"], "red_liquorice": ["aroma", "palate", "finish"], "rough_texture": ["finish", "palate", "texture"], "satin_texture": ["palate", "texture", "finish"], "scorched_rice": ["aroma", "palate", "finish"], "silky_texture": ["finish", "palate", "texture"], "stone_mineral": ["aroma", "palate", "finish"], "thick_texture": ["finish", "palate", "texture"], "vodka_flavour": ["aroma", "palate", "finish"], "water_parsley": ["aroma", "palate", "finish"], "yellow_pomelo": ["aroma", "finish", "palate"], "apricot_kernel": ["aroma", "palate"], "black_mulberry": ["aroma"], "candied_cherry": ["aroma", "palate", "finish"], "chalky_texture": ["finish", "palate", "texture"], "cherry_blossom": ["aroma", "palate"], "christmas_cake": ["aroma", "palate", "finish"], "citrus_blossom": ["aroma", "palate", "finish"], "cooked_vegetal": ["aroma", "palate", "finish"], "cool_character": ["aroma", "palate", "finish"], "coriander_seed": ["aroma", "finish", "palate"], "creamy_caramel": ["aroma", "palate", "finish"], "creamy_texture": ["finish", "palate", "texture"], "dark_chocolate": ["aroma", "finish", "palate"], "deep_character": ["aroma", "palate", "finish"], "demerara_sugar": ["aroma", "palate", "finish"], "drying_texture": ["finish", "palate", "texture"], "firm_character": ["palate", "finish"], "firm_structure": ["finish", "palate", "texture"], "glossy_texture": ["texture"], "honeyed_walnut": ["aroma", "palate", "finish"], "linden_blossom": ["aroma", "palate", "finish"], "linear_texture": ["texture"], "lively_acidity": ["palate", "finish"], "longan_blossom": ["aroma"], "marasca_cherry": ["aroma", "palate", "finish"], "medicinal_herb": ["aroma", "finish", "palate"], "milk_chocolate": ["aroma", "palate", "finish"], "morello_cherry": ["aroma", "palate", "finish"], "oily_character": ["aroma", "palate", "finish"], "orange_blossom": ["aroma", "palate", "finish"], "red_apple_skin": ["aroma", "palate", "finish"], "red_grapefruit": ["aroma", "palate", "finish"], "rich_character": ["aroma", "palate", "finish"], "ripe_blueberry": ["aroma", "finish", "palate"], "ripe_fresh_fig": ["aroma", "finish", "palate"], "ripe_raspberry": ["aroma", "finish", "palate"], "root_vegetable": ["aroma", "palate", "finish"], "smooth_texture": ["finish", "palate", "texture"], "sticky_texture": ["finish", "palate", "texture"], "supple_texture": ["finish", "palate", "texture"], "sweet_aromatic": ["aroma", "finish", "palate"], "syrupy_texture": ["finish", "palate", "texture"], "technical_note": ["aroma", "finish", "palate"], "tropical_fruit": ["aroma", "finish", "palate"], "warm_character": ["aroma", "palate", "finish"], "watery_texture": ["finish", "palate", "texture"], "wild_character": ["aroma", "palate", "finish"], "apricot_blossom": ["aroma", "palate", "finish"], "black_liquorice": ["aroma", "palate", "finish"], "black_raspberry": ["aroma", "palate", "finish"], "blueberry_paste": ["aroma", "palate", "finish"], "bubbles_texture": ["finish", "palate", "texture"], "clean_character": ["aroma", "palate", "texture"], "clear_character": ["aroma", "palate", "finish"], "coating_texture": ["finish", "palate", "texture"], "creme_de_cassis": ["aroma", "palate", "finish"], "crisp_character": ["aroma", "palate", "texture", "finish"], "dried_character": ["aroma", "palate", "finish"], "dried_cranberry": ["aroma", "palate", "finish"], "dried_persimmon": ["aroma", "finish"], "dried_pineapple": ["aroma", "palate", "finish"], "dusty_character": ["aroma", "finish", "palate"], "flowing_texture": ["finish", "palate", "texture"], "fresh_blueberry": ["aroma", "finish", "palate"], "fresh_raspberry": ["aroma", "finish", "palate"], "green_vegetable": ["aroma", "palate", "finish"], "immediate_onset": ["palate", "texture", "finish"], "juicy_character": ["palate", "finish"], "neungi_mushroom": ["aroma"], "nutty_character": ["aroma", "palate", "finish"], "overall_flavour": ["palate", "finish"], "overall_texture": ["texture", "palate", "finish"], "pickled_apricot": ["aroma", "palate", "finish"], "pillowy_texture": ["palate", "texture", "finish"], "pink_grapefruit": ["aroma", "palate", "finish"], "plain_character": ["palate", "finish"], "powdered_ginger": ["aroma", "palate", "finish"], "powdery_texture": ["finish", "palate", "texture"], "preserved_lemon": ["aroma", "palate", "finish"], "prickly_bubbles": ["finish", "palate", "texture"], "refined_texture": ["finish", "palate", "texture"], "ripe_blackberry": ["aroma", "finish", "palate"], "ripe_strawberry": ["aroma", "finish", "palate"], "rounded_texture": ["finish", "palate", "texture"], "silky_character": ["aroma", "palate", "finish"], "spicy_sensation": ["finish", "palate", "texture"], "sweet_blueberry": ["aroma", "finish", "palate"], "sweet_fresh_fig": ["aroma", "finish", "palate"], "sweet_raspberry": ["aroma", "finish", "palate"], "tactile_prickle": ["finish", "palate", "texture"], "turkish_delight": ["palate", "finish"], "velvety_texture": ["finish", "palate", "texture"], "viscous_texture": ["finish", "palate", "texture"], "white_asparagus": ["aroma", "palate", "finish"], "white_chocolate": ["aroma", "palate", "finish"], "wild_strawberry": ["aroma", "palate", "finish"], "bright_character": ["aroma", "palate", "finish"], "dessert_aromatic": ["aroma", "finish", "palate"], "dried_lemon_peel": ["aroma", "palate", "finish"], "exotic_character": ["aroma", "palate", "finish"], "first_impression": ["palate", "texture", "finish"], "forest_character": ["aroma", "palate", "finish"], "fresh_blackberry": ["aroma", "finish", "palate"], "fresh_strawberry": ["aroma", "palate", "finish"], "gentle_character": ["aroma", "palate", "finish"], "gripping_texture": ["finish", "palate", "texture"], "limoncella_apple": ["aroma", "palate", "finish"], "lively_character": ["aroma", "finish", "palate"], "luscious_texture": ["palate", "texture", "finish"], "orange_tangerine": ["aroma", "finish", "palate"], "ripe_fresh_fruit": ["aroma", "finish", "palate"], "sweet_blackberry": ["aroma", "finish", "palate"], "sweet_strawberry": ["aroma", "finish", "palate"], "unctuous_texture": ["finish", "palate", "texture"], "wilted_character": ["aroma", "finish", "palate"], "angular_character": ["palate", "texture", "finish"], "apple_concentrate": ["aroma", "palate", "finish"], "black_forest_cake": ["aroma", "palate"], "blackcurrant_leaf": ["aroma", "palate", "finish"], "burning_sensation": ["finish", "palate", "texture"], "candied_character": ["aroma", "palate", "finish"], "christmas_pudding": ["aroma", "palate"], "complex_character": ["aroma", "finish", "palate"], "crushed_character": ["aroma", "palate", "finish"], "digestive_biscuit": ["aroma", "palate", "finish"], "fresh_fresh_fruit": ["aroma", "finish", "palate"], "gradual_emergence": ["aroma", "palate", "texture", "finish"], "layered_character": ["aroma", "palate", "finish"], "maraschino_cherry": ["aroma", "palate", "finish"], "natural_character": ["aroma", "palate", "finish"], "orchard_character": ["aroma", "palate", "finish"], "overall_structure": ["finish", "palate", "texture"], "puckering_texture": ["finish", "palate", "texture"], "refined_character": ["aroma", "palate", "finish"], "refined_structure": ["finish", "palate", "texture"], "ripe_black_cherry": ["aroma", "finish", "palate"], "sweet_fresh_fruit": ["aroma", "finish", "palate"], "toasted_character": ["aroma", "palate", "finish"], "warming_sensation": ["finish", "palate", "texture"], "wild_fermentation": ["aroma", "palate", "finish"], "astringent_texture": ["finish", "palate", "texture"], "balanced_character": ["aroma", "finish", "palate"], "balloonflower_root": ["aroma", "palate", "finish"], "cherry_blossom_tea": ["aroma"], "concentrated_umami": ["palate", "finish"], "deepened_character": ["palate", "finish"], "fragrant_character": ["aroma", "palate", "finish"], "fresh_black_cherry": ["aroma", "finish", "palate"], "mediterranean_herb": ["aroma", "palate", "finish"], "persistent_bubbles": ["texture"], "powerful_character": ["aroma", "palate", "finish"], "restrained_texture": ["palate", "texture", "finish"], "sweet_black_cherry": ["aroma", "finish", "palate"], "dissipating_bubbles": ["palate", "texture", "finish"], "green_orchard_fruit": ["aroma", "palate", "finish"], "intensity_character": ["palate", "texture", "finish"], "mediterranean_spice": ["aroma", "palate", "finish"], "semisweet_chocolate": ["aroma", "palate", "finish"], "structuring_acidity": ["palate", "finish"], "sugar_coated_almond": ["aroma", "palate", "finish"], "sweetness_character": ["palate", "finish"], "tactile_stimulation": ["palate", "texture", "finish"], "concentrated_texture": ["finish", "palate", "texture"], "effervescent_texture": ["palate", "texture", "finish"], "fully_ripe_character": ["aroma", "palate", "finish"], "in_glass_development": ["aroma", "palate", "finish"], "integrated_character": ["aroma", "palate", "texture", "finish"], "medium_dry_character": ["palate", "finish"], "mouth_edge_roughness": ["texture"], "mouthfilling_texture": ["finish", "palate", "texture"], "persistent_character": ["aroma", "palate", "texture", "finish"], "refreshing_character": ["aroma", "finish", "palate"], "restrained_character": ["palate", "texture", "finish"], "sherry_soaked_raisin": ["aroma", "palate", "finish"], "sweet_tart_character": ["aroma", "palate", "finish"], "mouthwatering_acidity": ["palate", "finish"], "tongue_tip_bitterness": ["palate", "finish"], "wide_spread_character": ["aroma", "palate", "texture", "finish"], "concentrated_character": ["aroma", "palate", "finish"], "cooked_preserved_fruit": ["aroma", "finish", "palate"], "fine_grained_character": ["finish", "palate", "texture"], "freshly_baked_character": ["aroma", "palate", "finish"], "gentle_spread_character": ["palate", "texture", "finish"], "mouthwatering_character": ["palate", "finish"], "toasty_savory_character": ["aroma", "palate", "finish"], "toward_finish_emergence": ["aroma", "palate", "texture", "finish"], "relative_intensity_increase": ["aroma", "palate", "finish"], "naturally_fermented_carbonation": ["palate", "texture", "finish"]}'::jsonb;
 axis_sections constant jsonb := '{"sweetness": ["palate", "finish"], "acidity": ["palate", "finish"], "bitterness": ["palate", "finish"], "umami": ["palate", "finish"], "saltiness": ["palate", "finish"], "body": ["texture", "finish"], "viscosity": ["texture", "finish"], "astringency": ["texture", "finish"], "alcohol_presence": ["texture", "finish"], "smoothness": ["texture", "finish"], "carbonation": ["texture"], "aroma_intensity": ["aroma"], "flavour_clarity": ["palate"], "finish_length": ["finish"], "finish_cleanliness": ["finish"]}'::jsonb;
begin
 if p is null then return true; end if;
 if jsonb_typeof(p) <> 'object' or p->'schemaVersion' is distinct from '1'::jsonb
 or p->>'scaleVersion' is distinct from 'sensory-grades-v1' or p->>'itemId' is distinct from item_id::text
 or jsonb_typeof(p->'facts') is distinct from 'array' or jsonb_array_length(p->'facts')>512 then return false; end if;
 for f in select value from jsonb_array_elements(p->'facts') loop
  if jsonb_typeof(f) is distinct from 'object' or jsonb_typeof(f->'target') is distinct from 'object'
  or f->>'attribute' is null or f->>'attribute' not in ('presence','intensity','duration','acidity','sweetness','bitterness') then return false; end if;
  if f#>>'{target,kind}' = 'descriptor' then
   if not coalesce((descriptor_sections->(f#>>'{target,key}')) ? (f#>>'{target,section}'),false) then return false; end if;
  elsif f#>>'{target,kind}' = 'axis' then
   if not coalesce((axis_sections->(f#>>'{target,key}')) ? (f#>>'{target,section}'),false) then return false; end if;
  else return false; end if;
  if f->>'attribute' in ('acidity','sweetness','bitterness') and (f#>>'{target,kind}' is distinct from 'descriptor' or coalesce(f#>>'{target,section}','') not in ('palate','finish')) then return false; end if;
  if f->>'attribute'='duration' and f#>>'{target,section}'<>'finish' and not(f#>>'{target,kind}'='descriptor' and f#>>'{target,section}' in ('texture','aroma')) and not(f#>>'{target,kind}'='axis' and f#>>'{target,key}'='sweetness' and f#>>'{target,section}'='palate') then return false; end if;
  if f#>>'{target,kind}'='axis' and f#>>'{target,key}'='finish_length' and f->>'attribute'<>'duration' then return false; end if;
  k=jsonb_build_array(f#>>'{target,kind}',f#>>'{target,key}',f#>>'{target,section}',f->>'attribute')::text;
  if k=any(seen) then return false; end if; seen=array_append(seen,k);
  if jsonb_typeof(f->'evidence') is distinct from 'array' then return false; end if;
  vals='{}';
  for e in select value from jsonb_array_elements(f->'evidence') loop
   if jsonb_typeof(e) is distinct from 'object' or exists(select 1 from unnest(array['sourceRef','sourceField','excerpt']) n where jsonb_typeof(e->n) is distinct from 'string' or length(trim(e->>n))=0) then return false; end if;
   if e ? 'interpretation' and (e->>'interpretation' is distinct from 'finish_weight_to_cleanliness' or f->'target' is distinct from '{"kind":"axis","key":"finish_cleanliness","section":"finish"}'::jsonb or f->>'attribute' is distinct from 'intensity' or e->>'sourceField' not in ('finish_note','overall_note','coded_finish_note','coded_overall_note')) then return false;end if;
   if f->>'attribute'='presence' then
    if e->'value' not in ('"present"'::jsonb,'"absent"'::jsonb) or e->'value' is null then return false; end if;
   elsif jsonb_typeof(e->'value') is distinct from 'number' or (e->>'value')::numeric not in (1,2,3,4,5) then return false;
   end if;
   vals=array_append(vals,e->'value');
  end loop;
  if f->>'state'='known' then
   if cardinality(vals)=0 or f->'value' is null or f->'value'='null'::jsonb or exists(select 1 from unnest(vals) v where v is distinct from f->'value') then return false; end if;
  elsif f->>'state'='unknown' then
   if f->'value' is distinct from 'null'::jsonb or cardinality(vals)<>0 then return false; end if;
  elsif f->>'state'='conflicting' then
   if f->'value' is distinct from 'null'::jsonb or (select count(distinct v) from unnest(vals) v)<2 then return false; end if;
  else return false; end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p->'facts') a, jsonb_array_elements(p->'facts') b where a#>>'{target,kind}'=b#>>'{target,kind}' and a#>>'{target,key}'=b#>>'{target,key}' and a#>>'{target,section}'=b#>>'{target,section}' and a->>'attribute'='presence' and a->>'state'='known' and a->>'value'='absent' and b->>'attribute'<>'presence' and b->>'state'<>'unknown') then return false; end if;
 return true;
exception when others then return false;
end;
$$;

--
-- Name: valid_product_sensory_semantics(jsonb, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.valid_product_sensory_semantics(p jsonb, item_id uuid) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$
declare e jsonb; identity jsonb; target jsonb; targets jsonb; evidence jsonb; kind text; k text; a text; b text;
 seen text[]:='{}'; vals text[];
 source_keys constant jsonb := '["acacia", "agave", "alcohol_aroma", "almond", "amaretto", "animalic", "anise", "apple", "apple_blossom", "apricot", "apricot_kernel", "azalea", "bacon", "bakery", "balanced_character", "balsamic", "bamboo_leaf", "banana", "barley", "basil", "bay_leaf", "beeswax", "bell_pepper", "bergamot", "berry", "bilberry", "biscuit", "black_cherry", "black_forest_cake", "black_fruit", "black_mulberry", "black_pepper", "black_tea", "blackberry", "blackcurrant", "blood_orange", "blueberry", "bokbunja", "bonfire", "boysenberry", "bramble", "bread", "brett", "brioche", "broth", "brown_sugar", "bubblegum", "buckwheat", "butter", "butterscotch", "candy", "caramel", "cardamom", "cashew", "cedar", "celery", "cereal", "chamomile", "char", "cheese", "cherry", "cherry_blossom", "cherry_blossom_tea", "cherry_pit", "cherry_wood", "chocolate", "christmas_cake", "christmas_pudding", "chrysanthemum", "cilantro", "cinnamon", "citrus", "citrus_peel", "clementine", "clove", "cocoa", "cocoa_butter", "coconut", "coffee", "cognac", "complex_character", "cooked_preserved_fruit", "cookie_dough", "coriander_seed", "corn", "corn_syrup", "cranberry", "cream", "creme_brulee", "cucumber", "custard", "dairy", "dark_chocolate", "dark_rum", "date", "dill", "dried_apricot", "dried_fig", "dried_flower", "dried_fruit", "dried_herb", "dried_persimmon", "dried_pineapple", "dry_earth", "earl_grey", "earth", "elderflower", "essential_oil", "ester", "eucalyptus", "fennel", "fermentation", "fig_syrup", "flint", "floral", "floral_honey", "frangipani", "fresh_fig", "fresh_fruit", "fresh_herb", "fruit_cake", "fruit_candy", "fruit_syrup", "fudge", "ginger", "ginjo_aroma", "ginseng", "gooseberry", "grape", "grape_skin", "grapefruit", "graphite", "grass", "green_apple", "green_grape", "green_tea", "guarana", "guava", "hawthorn", "hay", "hazelnut", "heather", "herbal", "hibiscus", "honey", "honeybush", "honeycomb", "honeysuckle", "hop", "incense", "iris", "jalapeno", "jammy", "jasmine", "jujube", "juniper", "juniper_wood", "kabosu", "kiwi", "koji", "kola_nut", "korean_cherry", "korean_melon", "kumquat", "kumquat_peel", "kyoho_grape", "lactic", "lavender", "leaf", "leather", "lemon", "lemon_candy", "lemon_curd", "lemon_peel", "lemongrass", "lilac", "lily", "lime", "lime_peel", "lingonberry", "liquorice", "longan_blossom", "lychee", "macadamia", "madeira", "malt", "mandarin", "mango", "maple_syrup", "marmalade", "marshmallow", "marzipan", "matcha", "meaty", "medicinal", "medicinal_herb", "melon", "melon_peel", "milk_chocolate", "mineral", "mint", "mocha", "molasses_note", "muscat", "mushroom", "musk", "nectarine", "neungi_mushroom", "nougat", "nuruk", "nutmeg", "nutty", "oak", "oat", "olive", "omija", "orange", "orange_blossom", "orange_peel", "orchard_fruit", "osmanthus", "papaya", "passion_fruit", "pastry", "pea", "peach", "peach_blossom", "pear", "pear_blossom", "peat", "pecan", "pepper", "petrol", "phenolic", "pine", "pine_resin", "pineapple", "plant_note", "plum", "pomegranate", "pomelo", "potato", "prune", "quince", "raisin", "ramune", "rancio", "raspberry", "red_bean", "red_flower", "red_fruit", "redcurrant", "refreshing_character", "rhubarb", "rice", "rice_bran", "roasted", "rose", "rose_apple", "rosemary", "rye", "sage", "sakura_mochi", "saline", "sandalwood", "sansho", "savory", "seaweed", "sesame", "sherry", "shikuwasa", "shiso", "slate", "smoke", "smoked_bacon", "solvent", "sorghum", "soy_sauce", "spice", "stewed_apple", "stone_fruit", "strawberry", "sudachi", "sugarcane", "sulfurous", "sweet_aromatic", "sweet_potato", "tamarind", "tangerine", "tar", "tea", "technical_note", "thyme", "tiramisu", "toast", "tobacco", "toffee", "tomato", "tropical_fruit", "truffle", "turkish_delight", "ume", "vanilla", "vegetal", "violet", "walnut", "watermelon", "wet_earth", "wet_leaf", "wet_stone", "wheat", "wheatgrass", "white_chocolate", "white_flower", "white_fruit", "white_pepper", "wood", "yeast", "yellow_fruit", "yuzu", "yuzu_peel", "fresh_strawberry", "sour_cherry", "cherry_tart", "red_apple_skin", "broad_aroma", "fresh_cherry", "candied_cherry", "ripe_pear", "baked_apple", "lively_acidity", "yellow_pomelo", "lively_character", "fresh_acidity", "ripe_fresh_fruit", "fresh_fresh_fruit", "sweet_fresh_fruit", "ripe_cherry", "sweet_cherry", "ripe_black_cherry", "fresh_black_cherry", "sweet_black_cherry", "ripe_apple", "fresh_apple", "sweet_apple", "ripe_plum", "fresh_plum", "sweet_plum", "ripe_peach", "fresh_peach", "sweet_peach", "fresh_pear", "sweet_pear", "ripe_strawberry", "sweet_strawberry", "ripe_raspberry", "fresh_raspberry", "sweet_raspberry", "ripe_blueberry", "fresh_blueberry", "sweet_blueberry", "ripe_blackberry", "fresh_blackberry", "sweet_blackberry", "ripe_fresh_fig", "sweet_fresh_fig", "dry_character", "rich_character", "fragrant_character", "refined_character", "gentle_character", "bright_character", "clear_character", "clean_character", "medium_dry_character", "nutty_character", "toasty_savory_character", "overall_flavour", "concentrated_character", "mediterranean_herb", "red_berry", "dark_berry", "wood_smoke", "ginger_candy", "creme_de_cassis", "vodka_flavour", "allspice", "yeast_lees", "white_asparagus", "powdered_ginger", "structuring_acidity", "deep_character", "stone_mineral", "freesia", "white_lilac", "apricot_blossom", "musk_melon", "golden_kiwi", "apple_honey", "tongue_tip_bitterness", "dried_cranberry", "forest_floor", "citrus_oil", "wild_berry", "kirsch", "black_plum", "black_liquorice", "espresso", "baking_spice", "spearmint", "chilli", "firewood", "peppermint", "chalk", "black_olive", "mouthwatering_acidity", "menthol", "meyer_lemon", "luscious_texture", "green_olive", "bing_cherry", "rose_petals", "oyster_shell", "immediate_onset", "powerful_character", "marasca_cherry", "juicy_character", "forest_character", "firm_character", "iron", "deepened_character", "exotic_character", "dark_caramel", "tannin", "mid_palate", "black_raspberry", "crushed_character", "tart_scent", "natural_character", "guava_peel", "first_impression", "limoncella_apple", "annurca_apple", "candied_fruit", "morello_cherry", "apple_juice", "lemon_juice", "apple_concentrate", "metallic", "slim_texture", "crisp_acidity", "mouthwatering_character", "elderberry", "warm_character", "wine_barrel", "semisweet_chocolate", "wild_fruit", "plain_character", "concentrated_umami", "gradual_emergence", "green_vegetable", "saffron", "red_cherry", "red_liquorice", "integrated_character", "glossy_texture", "iodine", "barrel_toast", "wild_character", "dried_character", "candied_character", "effervescent_texture", "apple_peel", "currant", "apple_cider", "dusty_character", "wilted_character", "fine_grained_character", "sweetness_character", "cool_character", "white_peach", "linden_blossom", "preserved_lemon", "creme_caramel", "restrained_character", "rose_water", "compote", "green_orchard_fruit", "freshly_baked_character", "unripe_fruit", "gentle_spread_character", "sweet_tart_character", "oily_character", "intensity_character", "red_chilli", "mediterranean_spice", "myrtle", "star_anise", "meringue", "oolong_tea", "tree_moss", "sugar_aroma", "chestnut", "mulberry", "pie", "banana_chip", "fully_ripe_character", "silky_character", "toasted_character", "wide_spread_character", "crisp_character", "borisu_note", "maple_note", "cake", "scorched_rice", "pine_needle", "apple_mint", "plum_blossom", "shell_note", "honeydew", "jackfruit", "milk", "praline", "pudding", "syrup", "yellow_apple", "brandy_note", "bourbon_note", "wine_note", "cola_note", "poached_fruit", "orchard_character", "aged_aromatic", "candy", "citrus_peel", "in_glass_development", "wild_strawberry", "root_vegetable", "root_beer", "toward_finish_emergence", "green_pear", "citrus_blossom", "wet_chalk", "layered_character", "asparagus", "peanut", "brazil_nut", "dragon_fruit", "lemon_balm", "shortbread", "geranium", "demerara_sugar", "pink_grapefruit", "red_grapefruit", "manuka_honey", "tart", "cherry_pie", "paprika", "cocoa_nibs", "oregano", "lemon_tart", "peanut_butter", "digestive_biscuit", "mugwort", "water_parsley", "balloonflower_root", "tteokgal_oak", "creamy_caramel", "pink_pepper", "pancake", "lemon_sorbet", "rum_raisin", "sugar_coated_almond", "dried_lemon_peel", "vinegar", "wild_fermentation", "red_apple", "white_melon", "blackcurrant_leaf", "tomato_leaf", "grape_juice", "orange_juice", "garrigue", "powdered_sage", "cotton_candy", "pickled_apricot", "barbecue", "toffee_nut", "wax", "relative_intensity_increase", "peppercorn", "cookie", "popcorn", "honeyed_pear", "honeyed_walnut", "sherry_soaked_raisin", "bitter_orange", "maraschino_cherry", "blueberry_paste", "tomato_paste", "lotus_flower", "lotus_leaf", "wafer", "jelly", "chalky_texture", "angular_character", "persistent_character", "cooked_vegetal", "golden_apple", "kaffir_lime", "wisteria", "limestone", "talc", "cream_cheese", "apple_butter", "bread_pudding", "asphalt"]'::jsonb;
begin
 if p is null then return true; end if;
 if jsonb_typeof(p) is distinct from 'object' or p->'schemaVersion' is distinct from '1'::jsonb or p->>'itemId' is distinct from item_id::text
 or jsonb_typeof(p->'entries') is distinct from 'array' or jsonb_array_length(p->'entries')>512 then return false; end if;
 for e in select value from jsonb_array_elements(p->'entries') loop
  identity=e->'identity';kind=identity->>'kind';targets='[]'::jsonb;

  if kind='conditional_character' then
   if jsonb_typeof(identity) is distinct from 'object' or (select count(*) from jsonb_object_keys(identity))<>6
    or exists(select 1 from jsonb_object_keys(identity) x where x not in ('kind','target','sourceKey','conditionKey','comparisonKey','originKey'))
    or identity->'target' is distinct from '{"kind":"descriptor","key":"overall_flavour","section":"palate"}'::jsonb
    or identity->>'conditionKey' is distinct from 'colder_serving' or identity->>'comparisonKey' is distinct from 'most_apparent'
    or not coalesce((identity->>'sourceKey'='lively_character' and identity->>'originKey'='sake_genshu') or (identity->>'sourceKey'='complex_character' and identity->>'originKey'='oak_wood'),false)
    or (e->>'state'='known' and e->>'value' is distinct from 'present')
    or jsonb_typeof(e->'evidence') is distinct from 'array'
    or exists(select 1 from jsonb_array_elements(e->'evidence') proof where proof->>'value' is distinct from 'present') then return false; end if;
   targets=jsonb_build_array(identity->'target');
   k=jsonb_build_array(kind,identity->'target',identity->>'sourceKey',identity->>'conditionKey',identity->>'comparisonKey',identity->>'originKey')::text;
  elsif kind in ('prominence','target_harmony','target_masking','character_source','tannin_harmony','character_intensity','intensity_ceiling','duration_ceiling') then
   if kind='duration_ceiling' and identity->'target' is distinct from '{"kind":"axis","key":"finish_length","section":"finish"}'::jsonb then return false;end if;
   if kind='tannin_harmony' and identity#>>'{target,section}' not in ('palate','texture','finish') then return false; end if;
   targets=jsonb_build_array(identity->'target');k=jsonb_build_array(kind,identity#>>'{target,kind}',identity#>>'{target,key}',identity#>>'{target,section}')::text;
   if kind in ('character_source','character_intensity') then
    if identity->>'sourceKey'='concentrated_character' and (identity#>>'{target,kind}' is distinct from 'descriptor' or coalesce(identity#>>'{target,section}','') not in ('aroma','palate','finish')) then return false; end if;
    if not coalesce(source_keys ? (identity->>'sourceKey'),false) and not coalesce(
      kind='character_source' and identity->>'sourceKey'='creamy_texture' and identity#>>'{target,section}'='texture' and
      ((identity#>>'{target,kind}'='axis' and identity#>>'{target,key}'='carbonation') or (identity#>>'{target,kind}'='descriptor' and identity#>>'{target,key}'='foamy_texture')),false) then return false; end if;
    k=jsonb_build_array(k,identity->>'sourceKey')::text;
   end if;
  elsif kind in ('harmony','contrast','masking','sequence','stronger_than','support','layer_under') then
   if identity->'from' is not distinct from identity->'to' or (identity#>>'{from,section}' is distinct from identity#>>'{to,section}' and not((kind in ('harmony','support') and identity#>>'{from,section}' in ('palate','texture') and identity#>>'{to,section}' in ('palate','texture')) or (kind='sequence' and identity#>>'{from,section}' in ('palate','texture') and identity#>>'{to,section}'='finish') or (kind='sequence' and identity->'from'='{"kind":"descriptor","key":"fresh_fruit","section":"aroma"}'::jsonb and identity->'to'='{"kind":"descriptor","key":"fresh_fruit","section":"finish"}'::jsonb) or (kind='support' and identity->'from'='{"kind":"axis","key":"acidity","section":"palate"}'::jsonb and identity->'to'='{"kind":"descriptor","key":"overall_flavour","section":"finish"}'::jsonb) or (kind='stronger_than' and identity#>>'{from,kind}'='descriptor' and identity#>>'{from,key}'='alcohol_aroma' and identity#>>'{from,section}'='aroma' and identity#>>'{to,kind}'='axis' and identity#>>'{to,key}'='alcohol_presence' and identity#>>'{to,section}'='texture'))) then return false; end if;
   targets=jsonb_build_array(identity->'from',identity->'to');
   a=jsonb_build_array(identity#>>'{from,kind}',identity#>>'{from,key}',identity#>>'{from,section}')::text;
   b=jsonb_build_array(identity#>>'{to,kind}',identity#>>'{to,key}',identity#>>'{to,section}')::text;
   if a=b then return false; end if;
   k=jsonb_build_array(kind,case when kind in ('harmony','contrast') then least(a,b) else a end,case when kind in ('harmony','contrast') then greatest(a,b) else b end)::text;
  elsif kind='appearance_colour' then
   if identity->>'section' is null or identity->>'section' not in ('aroma','palate','texture','finish') or identity->>'colourKey' is null or identity->>'colourKey' not in ('vivid_ruby','bright_gold','rose','dark_ruby','dark_purple','purple','dark_brown','brown','amber','gold','ruby','red','clear') then return false; end if;
   k=jsonb_build_array(kind,identity->>'section',identity->>'colourKey')::text;
  elsif kind='tannin_prominence' then
   if identity->>'section' is null or identity->>'section' not in ('palate','texture','finish') then return false; end if;
   k=jsonb_build_array(kind,identity->>'section')::text;
  elsif kind='body_range' then
   if identity->>'section' is distinct from 'texture' or jsonb_typeof(identity->'minimum') is distinct from 'number' or jsonb_typeof(identity->'maximum') is distinct from 'number' or identity->>'minimum' !~ '^[1-5]$' or identity->>'maximum' !~ '^[1-5]$' then return false; end if;
   if (identity->>'minimum')::integer >= (identity->>'maximum')::integer then return false; end if;
   k=jsonb_build_array(kind,identity->>'section',(identity->>'minimum')::integer,(identity->>'maximum')::integer)::text;
  elsif kind='tannin_balance' then
   if identity->>'section' is null or identity->>'section' not in ('palate','texture','finish') then return false; end if;
   k=jsonb_build_array(kind,identity->>'section')::text;
  elsif kind='balance' then
   if identity->>'section' is null or identity->>'section' not in ('aroma','palate','texture','finish') then return false; end if;
   k=jsonb_build_array(kind,identity->>'section')::text;
  elsif kind='tannin_texture' then
   if identity->>'section' is null or identity->>'section' not in ('palate','texture','finish')
    or identity->>'textureKey' is null or identity->>'textureKey' not in ('young_tannin','chalky_texture','creamy_texture','smooth_texture','silky_texture','velvety_texture','refined_texture','firm_structure','supple_texture','mature_tannin','rounded_texture','rich_texture','concentrated_texture','rough_texture','sticky_texture','gripping_texture','chewy_texture','coating_texture','powdery_texture') then return false; end if;
   k=jsonb_build_array(kind,identity->>'section',identity->>'textureKey')::text;
  else return false; end if;
  for target in select value from jsonb_array_elements(targets) loop
   if not public.valid_product_sensory_facts(jsonb_build_object('schemaVersion',1,'scaleVersion','sensory-grades-v1','itemId',item_id,
    'facts',jsonb_build_array(jsonb_build_object('target',target,'attribute',case when target->>'kind'='axis' and target->>'key'='finish_length' then 'duration' else 'presence' end,
      'state','unknown','value',null,'evidence','[]'::jsonb))),item_id) then return false; end if;
  end loop;
  if k=any(seen) or jsonb_typeof(e->'evidence') is distinct from 'array' then return false; end if;
  seen=array_append(seen,k);vals='{}';
  for evidence in select value from jsonb_array_elements(e->'evidence') loop
   if exists(select 1 from unnest(array['sourceRef','sourceField','excerpt']) n where jsonb_typeof(evidence->n) is distinct from 'string' or length(trim(evidence->>n))=0) then return false; end if;
   if evidence->>'value' is null or ((kind='prominence' and evidence->>'value' not in ('noticeable','dominant','not_noticeable')) or (kind='tannin_prominence' and evidence->>'value' not in ('noticeable','dominant','subdued')))
    or (kind in ('character_intensity','intensity_ceiling','duration_ceiling') and (jsonb_typeof(evidence->'value') is distinct from 'number' or evidence->>'value' !~ '^[1-5]$')) or (kind not in ('prominence','tannin_prominence','character_intensity','intensity_ceiling','duration_ceiling') and evidence->>'value' not in ('present','absent')) then return false; end if;
   vals=array_append(vals,evidence->>'value');
  end loop;
  if e->>'state'='known' then
   if kind in ('character_intensity','intensity_ceiling','duration_ceiling') and (jsonb_typeof(e->'value') is distinct from 'number' or e->>'value' !~ '^[1-5]$') then return false; end if;
   if cardinality(vals)=0 or e->>'value' is null or exists(select 1 from unnest(vals) x where x is distinct from e->>'value') then return false; end if;
  elsif e->>'state'='unknown' then
   if cardinality(vals)<>0 or e->'value' is distinct from 'null'::jsonb then return false; end if;
  elsif e->>'state'='conflicting' then
   if (select count(distinct x) from unnest(vals) x)<2 or e->'value' is distinct from 'null'::jsonb then return false; end if;
  else return false; end if;
 end loop;
 return true;
exception when others then return false;
end;
$_$;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: alcohol_tasting_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alcohol_tasting_profiles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    alcohol_item_id uuid NOT NULL,
    locale text NOT NULL,
    publish_status text DEFAULT 'staging'::text NOT NULL,
    published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    overall_note text,
    aroma_note text,
    palate_note text,
    finish_note text,
    texture_note text,
    body_note text,
    sweetness public.sensory_level_5,
    acidity public.sensory_level_5,
    bitterness public.sensory_level_5,
    umami public.sensory_level_5,
    saltiness public.sensory_level_5,
    astringency public.sensory_level_5,
    body public.sensory_level_5,
    viscosity public.sensory_level_5,
    carbonation public.sensory_level_5,
    alcohol_presence public.sensory_level_5,
    aroma_intensity public.sensory_level_5,
    flavour_clarity public.sensory_level_5,
    finish_length public.sensory_level_5,
    finish_cleanliness public.sensory_level_5,
    aroma_tags text[] DEFAULT ARRAY[]::text[] NOT NULL,
    palate_tags text[] DEFAULT ARRAY[]::text[] NOT NULL,
    finish_tags text[] DEFAULT ARRAY[]::text[] NOT NULL,
    texture_tags text[] DEFAULT ARRAY[]::text[] NOT NULL,
    sensory_scale smallint DEFAULT 5 NOT NULL,
    structured_sensory jsonb,
    structured_semantics jsonb,
    coded_sensory jsonb,
    CONSTRAINT alcohol_tasting_profiles_aroma_tags_check CHECK (public.soolgyul_catalog_text_array_is_valid(aroma_tags, 64, '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_tasting_profiles_coded_valid CHECK (public.valid_coded_sensory(coded_sensory, alcohol_item_id)),
    CONSTRAINT alcohol_tasting_profiles_direct_content_check CHECK (((num_nonnulls(NULLIF(btrim(overall_note), ''::text), NULLIF(btrim(aroma_note), ''::text), NULLIF(btrim(palate_note), ''::text), NULLIF(btrim(finish_note), ''::text), NULLIF(btrim(texture_note), ''::text), NULLIF(btrim(body_note), ''::text), sweetness, acidity, bitterness, umami, saltiness, astringency, body, viscosity, carbonation, alcohol_presence, aroma_intensity, flavour_clarity, finish_length, finish_cleanliness) > 0) OR (cardinality((((aroma_tags || palate_tags) || texture_tags) || finish_tags)) > 0))),
    CONSTRAINT alcohol_tasting_profiles_finish_tags_check CHECK (public.soolgyul_catalog_text_array_is_valid(finish_tags, 64, '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_tasting_profiles_palate_tags_check CHECK (public.soolgyul_catalog_text_array_is_valid(palate_tags, 64, '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_tasting_profiles_publish_gate_check CHECK (((publish_status <> 'published'::text) OR (published_at IS NOT NULL))),
    CONSTRAINT alcohol_tasting_profiles_publish_status_check CHECK ((publish_status = ANY (ARRAY['staging'::text, 'published'::text, 'withdrawn'::text]))),
    CONSTRAINT alcohol_tasting_profiles_semantics_valid CHECK (public.valid_product_sensory_semantics(structured_semantics, alcohol_item_id)),
    CONSTRAINT alcohol_tasting_profiles_sensory_scale_check CHECK ((sensory_scale = 5)),
    CONSTRAINT alcohol_tasting_profiles_structured_sensory_valid CHECK (public.valid_product_sensory_facts(structured_sensory, alcohol_item_id)),
    CONSTRAINT alcohol_tasting_profiles_texture_tags_check CHECK (public.soolgyul_catalog_text_array_is_valid(texture_tags, 64, '^[a-z][a-z0-9_]*$'::text))
);

--
-- Name: TABLE alcohol_tasting_profiles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.alcohol_tasting_profiles IS 'One exact-product operational profile. A sole normalized variant may materialize its product-group profile; multi-variant groups require exact-product evidence.';

--
-- Name: COLUMN alcohol_tasting_profiles.aroma_tags; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_tasting_profiles.aroma_tags IS 'Ordered-independent controlled sensory descriptors perceived in aroma.';

--
-- Name: COLUMN alcohol_tasting_profiles.palate_tags; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_tasting_profiles.palate_tags IS 'Ordered-independent controlled sensory descriptors perceived on the palate.';

--
-- Name: COLUMN alcohol_tasting_profiles.finish_tags; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_tasting_profiles.finish_tags IS 'Ordered-independent controlled sensory descriptors perceived in the finish.';

--
-- Name: COLUMN alcohol_tasting_profiles.texture_tags; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_tasting_profiles.texture_tags IS 'Controlled texture descriptors; empty until texture-applicable terms are seeded.';

--
-- Name: COLUMN alcohol_tasting_profiles.sensory_scale; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_tasting_profiles.sensory_scale IS 'Explicit 1–5 storage scale; legacy engine adapters normalize as (level-1)/4.';

--
-- Name: COLUMN alcohol_tasting_profiles.structured_sensory; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_tasting_profiles.structured_sensory IS 'Versioned exact-product sensory facts. Source edits invalidate facts; ingestion grade corrections synchronize scalar columns and facts atomically without scalar recovery history.';

--
-- Name: COLUMN alcohol_tasting_profiles.structured_semantics; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_tasting_profiles.structured_semantics IS 'Exact-product, scoped harmony, masking, balance, prominence and tannin texture with literal note evidence. Ingested before recommendation.';

--
-- Name: COLUMN alcohol_tasting_profiles.coded_sensory; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_tasting_profiles.coded_sensory IS 'Canonical claims from consumed note expressions; no original excerpts or recovery history. Survives residual-note edits.';

--
-- Name: assert_product_sensory_catalog_sources(jsonb, public.alcohol_tasting_profiles); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_product_sensory_catalog_sources(entry jsonb, p public.alcohol_tasting_profiles) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$
declare source jsonb; f jsonb; e jsonb; field text; proof jsonb; section text;
begin
 if entry->'grades' is distinct from '{}'::jsonb then raise exception 'zero-grade validation required';end if;
 source=public.sensory_source_snapshot(to_jsonb(p));
  if entry->'profile' is null or entry->'profile'='null'::jsonb or not public.valid_product_sensory_facts(entry->'profile',p.alcohol_item_id) then raise exception 'invalid sensory profile'; end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p.coded_sensory#>'{profile,facts}','[]'::jsonb)) c where not exists(
   select 1 from jsonb_array_elements(entry#>'{profile,facts}') n where n->'target'=c->'target' and n->'attribute'=c->'attribute' and not exists(select 1 from jsonb_array_elements(c->'evidence') oldproof where not (n->'evidence') @> jsonb_build_array(oldproof)
    and not (c->'target'='{"kind":"axis","key":"finish_cleanliness","section":"finish"}'::jsonb and c->>'attribute'='intensity'
     and oldproof->>'interpretation' is not distinct from 'finish_weight_to_cleanliness'
     and exists(select 1 from jsonb_array_elements(n->'evidence') direct where not direct ? 'interpretation' and direct->>'sourceField' in ('finish_note','overall_note','coded_finish_note','coded_overall_note')))))) then raise exception 'coded facts omitted';end if;
  -- Verify source identity and literal provenance against the locked current row.
  for f in select value from jsonb_array_elements(entry#>'{profile,facts}') loop
   for e in select value from jsonb_array_elements(f->'evidence') loop
    field=e->>'sourceField';
    if field like 'coded\_%' escape '\' then
     if not public.coded_sensory_evidence_matches(p.coded_sensory,f,e,false) then raise exception 'invalid coded sensory evidence';end if;
     continue;
    end if;
    if e->>'sourceRef' is distinct from 'catalog:product:'||p.alcohol_item_id::text||':'||field or not source ? field then raise exception 'invalid sensory source'; end if;
    if jsonb_typeof(source->field)='array' then
     if not (source->field) ? (e->>'excerpt') then raise exception 'stale sensory evidence'; end if;
    elsif jsonb_typeof(source->field)='number' then
     if e->>'excerpt' is distinct from source->>field or e->'value' is distinct from source->field then raise exception 'invalid numeric sensory evidence'; end if;
    elsif jsonb_typeof(source->field)='string' then
     if position(e->>'excerpt' in source->>field)=0 then raise exception 'stale note evidence'; end if;
    else raise exception 'missing sensory evidence'; end if;
   end loop;
  end loop;

  if entry->'semantics' is null or entry->'semantics'='null'::jsonb or not public.valid_product_sensory_semantics(entry->'semantics',p.alcohol_item_id) then raise exception 'invalid semantic profile'; end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p.coded_sensory#>'{semantics,entries}','[]'::jsonb)) c where not exists(
   select 1 from jsonb_array_elements(entry#>'{semantics,entries}') n where n->'identity'=c->'identity' and (n->'evidence') @> (c->'evidence'))) then raise exception 'coded semantics omitted';end if;
  for e in select value from jsonb_array_elements(entry#>'{semantics,entries}') loop
   section=coalesce(e#>>'{identity,target,section}',e#>>'{identity,from,section}',e#>>'{identity,section}');
   for proof in select value from jsonb_array_elements(e->'evidence') loop
    if proof->>'sourceField' like 'coded\_%' escape '\' then
     if not public.coded_sensory_evidence_matches(p.coded_sensory,e,proof,true) then raise exception 'invalid coded semantic evidence';end if;
     continue;
    end if;
    if not public.sensory_semantic_phase_matches(e->'identity',proof) then raise exception 'semantic phase mismatch';end if;
  if e->'identity'='{"kind":"sequence","from":{"kind":"descriptor","key":"fresh_fruit","section":"aroma"},"to":{"kind":"descriptor","key":"fresh_fruit","section":"finish"}}'::jsonb
   and not coalesce(proof->>'sourceField'='aroma_note' and proof->>'value'='present' and public.sensory_literal_fruit_aroma_through_finish(proof->>'excerpt'),false)
   and not(proof->>'sourceField'='finish_note' and proof->>'value'='present' and public.sensory_literal_oak_named_long_aroma(proof->>'excerpt') and e#>>'{identity,kind}'='character_source' and e#>>'{identity,target,kind}'='descriptor' and e#>>'{identity,target,section}'='aroma' and e#>>'{identity,target,key}' in ('vanilla','liquorice','tobacco') and e#>>'{identity,sourceKey}'='oak') and not(proof->>'sourceField'='aroma_note' and proof->>'value'='present'
   and trim(regexp_replace(trim(proof->>'excerpt'),'[.!。]+$','')) ~ '^실키하고\s*(?:우아한\s*)?(?:타닌|탄닌)과\s*입안에서\s*퍼지는\s*풍부한\s*과실향이\s*인상적인\s*와인이다$'
   and e->'identity' in (
    '{"kind":"tannin_texture","section":"texture","textureKey":"silky_texture"}'::jsonb,
    '{"kind":"character_source","target":{"kind":"descriptor","key":"fresh_fruit","section":"palate"},"sourceKey":"rich_character"}'::jsonb,
    '{"kind":"character_source","target":{"kind":"descriptor","key":"fresh_fruit","section":"palate"},"sourceKey":"wide_spread_character"}'::jsonb
   )) and not(proof->>'sourceField' in ('palate_note','texture_note') and proof->>'value'='present'
   and trim(regexp_replace(trim(proof->>'excerpt'),'[.!。]+$','')) ~ '^농축된\s*꽃과\s*풍부한\s*과일\s*향을\s*느낄\s*수\s*있고,\s*입에서는\s*온화한\s*맛과\s*조화롭고\s*풍부한\s*바디감을\s*가지고\s*있다$'
   and e->'identity' in (
    '{"kind":"character_source","target":{"kind":"descriptor","key":"floral","section":"aroma"},"sourceKey":"concentrated_character"}'::jsonb,
    '{"kind":"character_source","target":{"kind":"descriptor","key":"fresh_fruit","section":"aroma"},"sourceKey":"rich_character"}'::jsonb
   )) then raise exception 'semantic phase mismatch';end if;
    if proof->>'sourceRef' is distinct from 'catalog:product:'||p.alcohol_item_id::text||':'||(proof->>'sourceField')
     or jsonb_typeof(source->(proof->>'sourceField')) is distinct from 'string'
     or position(proof->>'excerpt' in source->>(proof->>'sourceField'))=0 then raise exception 'stale semantic evidence';end if;
   end loop;
  end loop;

end;
$_$;

--
-- Name: coded_sensory_evidence_matches(jsonb, jsonb, jsonb, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.coded_sensory_evidence_matches(coded jsonb, entry jsonb, proof jsonb, semantic boolean) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
 select exists(select 1 from jsonb_array_elements(coalesce(case when semantic then coded#>'{semantics,entries}' else coded#>'{profile,facts}' end,'[]'::jsonb)) c
 where case when semantic then c->'identity'=entry->'identity' else c->'target'=entry->'target' and c->'attribute'=entry->'attribute' end
 and (c->'evidence') @> jsonb_build_array(proof));
$$;

--
-- Name: compact_product_sensory_notes_batch(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compact_product_sensory_notes_batch(entries jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare entry jsonb;p public.alcohol_tasting_profiles; source jsonb;r jsonb; fields text[];k text;v jsonb;
 profile jsonb;semantics jsonb;coded jsonb;applied int:=0;stale int:=0;unchanged int:=0;
begin
 if jsonb_typeof(entries) is distinct from 'array' or jsonb_array_length(entries)>100 then raise exception 'invalid compaction batch';end if;

 -- Match the existing catalog lock order before either profile or item row locks.
 if exists(select 1 from jsonb_array_elements(entries) e where jsonb_array_length(coalesce(e->'productionClaims','[]'::jsonb))>0) then perform pg_advisory_xact_lock(20260911,135); end if;
 for entry in select value from jsonb_array_elements(entries) loop
  select t.* into p from public.alcohol_tasting_profiles t join public.alcohol_items i on i.id=t.alcohol_item_id
   where t.id=(entry->>'profileId')::uuid and t.alcohol_item_id=(entry->>'itemId')::uuid and i.publish_status in ('published','staging') for update of t;
  if not found then stale=stale+1;continue;end if;
  source=public.sensory_source_snapshot(to_jsonb(p));
  if md5(source::text) is distinct from entry->>'sourceFingerprint'
   or md5(coalesce(p.structured_sensory::text,'null')) is distinct from entry->>'structuredFingerprint'
   or md5(coalesce(p.structured_semantics::text,'null')) is distinct from entry->>'semanticsFingerprint' then stale=stale+1;continue;end if;

  if entry->'notes'?'aroma_note' and entry#>'{notes,aroma_note}' is distinct from source->'aroma_note'
   and public.sensory_literal_oak_vanilla_aroma(source->>'aroma_note') and jsonb_array_length(coalesce(entry->'productionClaims','[]'::jsonb))=0 then raise exception 'consumed production claim requires catalog assignment'; end if;

  if entry->'notes'?'palate_note' and exists(
   select 1 from regexp_split_to_table(coalesce(source->>'palate_note',''),'[.!。]+') sentence
   where public.sensory_literal_cold_sake_oak(sentence) and position(trim(sentence) in coalesce(entry#>>'{notes,palate_note}',''))=0
   and exists(select 1 from (values ('production_process_keys','oak_wood'),('classification_keys','sake_treatment:sake_genshu'),('classification_keys','sake_treatment:sake_nama')) required(field,key)
    where not exists(select 1 from jsonb_array_elements(coalesce(entry->'productionClaims','[]'::jsonb)) c where c->>'sourceField'='palate_note' and c->>'field'=required.field and c->>'key'=required.key and c->>'excerpt'=trim(sentence)))
  ) then raise exception 'consumed conditional description requires literal catalog assignments';end if;

  if entry->'notes'?'palate_note' and exists(
   select 1 from regexp_split_to_table(coalesce(source->>'palate_note',''),'[.!。]+') sentence
   where public.sensory_literal_rice_water_sake(sentence) and position(trim(sentence) in coalesce(entry#>>'{notes,palate_note}',''))=0
   and exists(select 1 from (values ('classification_keys','sake_treatment:sake_nama'),('classification_keys','sake_treatment:sake_muroka'),('production_process_keys','unpasteurised'),('production_process_keys','unfiltered_claim'),('production_process_keys','rice_water_only_claim'),('ingredient_keys','rice'),('ingredient_keys','water_material')) required(field,key)
    where not exists(select 1 from jsonb_array_elements(coalesce(entry->'productionClaims','[]'::jsonb)) c where c->>'sourceField'='palate_note' and c->>'field'=required.field and c->>'key'=required.key and c->>'excerpt'=trim(sentence)))
  ) then raise exception 'consumed production description requires literal catalog assignments';end if;

  if entry->'notes'?'finish_note' and public.sensory_oak_long_aroma_clause(source->>'finish_note') is not null
   and position(public.sensory_oak_long_aroma_clause(source->>'finish_note') in coalesce(entry#>>'{notes,finish_note}',''))=0 then
   if not exists(select 1 from jsonb_array_elements(coalesce(entry->'productionClaims','[]'::jsonb)) c where c->>'sourceField'='finish_note' and c->>'field'='production_process_keys' and c->>'key'='oak_wood' and c->>'excerpt'=public.sensory_oak_long_aroma_clause(source->>'finish_note')) then raise exception 'oak aroma requires production assignment';end if;
   if exists(select 1 from (values ('vanilla'),('liquorice'),('tobacco')) required(key) where
    not exists(select 1 from jsonb_array_elements(entry#>'{profile,facts}') f where f#>>'{target,key}'=required.key and f#>>'{target,section}'='aroma' and f->>'attribute'='duration' and f->>'state'='known' and f->>'value'='4')
    or not exists(select 1 from jsonb_array_elements(entry#>'{profile,facts}') f where f#>>'{target,key}'=required.key and f#>>'{target,section}'='aroma' and f->>'attribute'='presence' and f->>'value'='present')
    or not exists(select 1 from jsonb_array_elements(entry#>'{semantics,entries}') e where e#>>'{identity,target,key}'=required.key and e#>>'{identity,target,section}'='aroma' and e#>>'{identity,kind}'='character_source' and e#>>'{identity,sourceKey}'='oak')
   ) then raise exception 'oak aroma requires all named durations and origins';end if;
  end if;

  if exists(select 1 from jsonb_array_elements(entry#>'{semantics,entries}') c
   where c#>>'{identity,kind}'='duration_ceiling' and c->>'state'='known' and (
    coalesce((entry#>>'{grades,finish_length}')::numeric,p.finish_length)>(c->>'value')::numeric
    or exists(select 1 from jsonb_array_elements(entry#>'{profile,facts}') f where f#>>'{target,kind}'='axis' and f#>>'{target,key}'='finish_length' and f->>'attribute'='duration' and f->>'state'='known' and (f->>'value')::numeric>(c->>'value')::numeric)
   )) then raise exception 'sensory duration ceiling conflict';end if;
  if jsonb_array_length(coalesce(entry->'productionClaims','[]'::jsonb))>0 and not public.apply_sensory_product_claims(p.alcohol_item_id,source,entry) then stale=stale+1;continue;end if;

  if entry->'notes'?'palate_note' and entry#>'{notes,palate_note}' is distinct from source->'palate_note'
   and exists(select 1 from regexp_split_to_table(coalesce(source->>'palate_note',''),'[.!。]') s where public.sensory_literal_omachi_rice(trim(s)))
   and not exists(select 1 from jsonb_array_elements(coalesce(entry->'productionClaims','[]'::jsonb)) c where c->>'field'='ingredient_keys' and c->>'key'='rice_omachi')
   then raise exception 'consumed cultivar requires ingredient assignment';end if;
  if jsonb_typeof(entry->'notes') is distinct from 'object' then raise exception 'missing residual notes';end if;
  fields='{}';
  for k,v in select key,value from jsonb_each(entry->'notes') loop
   if k not in ('aroma_note','palate_note','texture_note','finish_note','body_note','overall_note') or (v<>'null'::jsonb and jsonb_typeof(v)<>'string') then raise exception 'invalid residual field';end if;
   if length(coalesce(v#>>'{}',''))>length(coalesce(source->>k,'')) then raise exception 'residual expanded';end if;
   if v is distinct from source->k then fields=array_append(fields,k);end if;
  end loop;
  -- The ordinary RPC checks the full original source and all claim evidence first.
  if entry->'grades'='{}'::jsonb then
   perform public.assert_product_sensory_catalog_sources(entry,p);
   if p.structured_sensory is not distinct from entry->'profile' and p.structured_semantics is not distinct from entry->'semantics' then
    r=jsonb_build_object('applied',0,'unchanged',1,'stale',0);
   else r=jsonb_build_object('applied',1,'unchanged',0,'stale',0);end if;
  else
   r=public.set_product_sensory_catalog_batch(jsonb_build_array(entry));
   if (r->>'stale')::int<>0 then raise exception 'source changed';end if;
  end if;
  profile=public.encode_sensory_note_evidence(entry->'profile','facts',fields);
  semantics=public.encode_sensory_note_evidence(entry->'semantics','entries',fields);
  coded=jsonb_build_object('profile',public.extract_coded_sensory(profile,'facts'),'semantics',public.extract_coded_sensory(semantics,'entries'));
  if not public.valid_coded_sensory(coded,p.alcohol_item_id) then raise exception 'invalid coded claims';end if;
  if cardinality(fields)=0 and coded is not distinct from p.coded_sensory and (entry->'grades'<>'{}'::jsonb or (p.structured_sensory is not distinct from entry->'profile' and p.structured_semantics is not distinct from entry->'semantics')) then
   applied=applied+(r->>'applied')::int;unchanged=unchanged+(r->>'unchanged')::int;continue;
  end if;
  update public.alcohol_tasting_profiles set
   aroma_note=case when entry->'notes'?'aroma_note' then entry#>>'{notes,aroma_note}' else aroma_note end,
   palate_note=case when entry->'notes'?'palate_note' then entry#>>'{notes,palate_note}' else palate_note end,
   texture_note=case when entry->'notes'?'texture_note' then entry#>>'{notes,texture_note}' else texture_note end,
   finish_note=case when entry->'notes'?'finish_note' then entry#>>'{notes,finish_note}' else finish_note end,
   body_note=case when entry->'notes'?'body_note' then entry#>>'{notes,body_note}' else body_note end,
   overall_note=case when entry->'notes'?'overall_note' then entry#>>'{notes,overall_note}' else overall_note end,
   coded_sensory=coded,updated_at=clock_timestamp() where id=p.id;
  -- Source-change invalidation intentionally runs first; then restore verified caches.
  update public.alcohol_tasting_profiles set structured_sensory=profile,structured_semantics=semantics where id=p.id;
  applied=applied+1;
 end loop;
 return jsonb_build_object('applied',applied,'unchanged',unchanged,'stale',stale);
end;
$$;

--
-- Name: encode_sensory_note_evidence(jsonb, text, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.encode_sensory_note_evidence(profile jsonb, collection text, fields text[]) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
declare entries jsonb:='[]'; e jsonb; proof jsonb; evidence jsonb; f text;
begin
 for e in select value from jsonb_array_elements(profile->collection) loop
  evidence='[]';
  for proof in select value from jsonb_array_elements(e->'evidence') loop
   f=proof->>'sourceField';
   if f=any(fields) then
    proof=jsonb_build_object('sourceField','coded_'||f,'sourceRef','catalog:product:'||(profile->>'itemId')||':coded_'||f,'excerpt',proof->>'value','value',proof->'value') || case when proof ? 'interpretation' then jsonb_build_object('interpretation',proof->'interpretation') else '{}'::jsonb end;
   end if;
   if not evidence @> jsonb_build_array(proof) then evidence=evidence||jsonb_build_array(proof);end if;
  end loop;
  entries=entries||jsonb_build_array(jsonb_set(e,'{evidence}',evidence));
 end loop;
 return jsonb_set(profile,array[collection],entries);
end;
$$;

--
-- Name: extract_coded_sensory(jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.extract_coded_sensory(profile jsonb, collection text) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
declare entries jsonb:='[]';e jsonb;evidence jsonb;v jsonb;n int;
begin
 for e in select value from jsonb_array_elements(profile->collection) loop
  select coalesce(jsonb_agg(x),'[]') into evidence from jsonb_array_elements(e->'evidence') x where x->>'sourceField' like 'coded\_%' escape '\';
  if evidence='[]'::jsonb then continue;end if;
  select count(distinct x->'value') into n from jsonb_array_elements(evidence) x;
  v=evidence->0->'value';
  entries=entries||jsonb_build_array(e||jsonb_build_object('evidence',evidence,'state',case when n=1 then 'known' else 'conflicting' end,'value',case when n=1 then v else 'null'::jsonb end));
 end loop;
 return jsonb_set(profile,array[collection],entries);
end;
$$;

--
-- Name: invalidate_product_sensory_facts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.invalidate_product_sensory_facts() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
 if new.alcohol_item_id is distinct from old.alcohol_item_id or public.sensory_source_snapshot(to_jsonb(new)) is distinct from public.sensory_source_snapshot(to_jsonb(old)) then
  new.structured_sensory=null;new.structured_semantics=null;
 end if;
 return new;
end;
$$;

--
-- Name: refresh_product_sensory_grades_batch(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_product_sensory_grades_batch(entries jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare entry jsonb; p public.alcohol_tasting_profiles; next_row public.alcohol_tasting_profiles;
 patch jsonb; field text; grade jsonb; f jsonb; result jsonb;
 applied int := 0; stale int := 0;
 axes constant text[] := array['sweetness','acidity','bitterness','umami','saltiness','astringency','body','viscosity','carbonation','alcohol_presence','aroma_intensity','flavour_clarity','finish_length','finish_cleanliness'];
 section text;
begin
 if jsonb_typeof(entries) is distinct from 'array' or jsonb_array_length(entries)>100 then raise exception 'invalid grade batch'; end if;
 for entry in select value from jsonb_array_elements(entries) loop
  select t.* into p from public.alcohol_tasting_profiles t join public.alcohol_items i on i.id=t.alcohol_item_id
   where t.id=(entry->>'profileId')::uuid and t.alcohol_item_id=(entry->>'itemId')::uuid and i.publish_status in ('published','staging') for update of t;
  if not found then stale=stale+1; continue; end if;
  if md5(public.sensory_source_snapshot(to_jsonb(p))::text) is distinct from entry->>'sourceFingerprint'
   or md5(coalesce(p.structured_sensory::text,'null')) is distinct from entry->>'structuredFingerprint'
   then stale=stale+1; continue; end if;
  if p.sensory_scale is distinct from 5 then raise exception 'integer scale required'; end if;
  patch=entry->'grades';
  if jsonb_typeof(patch) is distinct from 'object' or patch='{}'::jsonb then raise exception 'empty grade correction'; end if;
  if entry->'profile' is null or entry->'profile'='null'::jsonb or not public.valid_product_sensory_facts(entry->'profile',p.alcohol_item_id) then raise exception 'invalid refreshed profile'; end if;
  for field,grade in select key,value from jsonb_each(patch) loop
   if not field=any(axes) or jsonb_typeof(grade) is distinct from 'number' or grade::text not in ('1','2','3','4','5') then raise exception 'invalid grade correction'; end if;
   section=case when field like 'finish_%' then 'finish' when field='aroma_intensity' then 'aroma'
     when field=any(array['body','viscosity','astringency','carbonation','alcohol_presence']) then 'texture' else 'palate' end;
   if not exists (
    select 1 from jsonb_array_elements(entry#>'{profile,facts}') fact
    where fact#>>'{target,kind}'='axis' and fact#>>'{target,key}'=field and fact#>>'{target,section}'=section
     and fact->>'attribute'=case when field='finish_length' then 'duration' else 'intensity' end
     and fact->>'state'='known' and fact->'value'=grade
     and exists(select 1 from jsonb_array_elements(fact->'evidence') e where public.sensory_note_phase_matches(section,e->>'sourceField',e->>'excerpt') and e->'value'=grade)
     and exists(select 1 from jsonb_array_elements(fact->'evidence') e where e->>'sourceField'=field and e->'value'=grade)
   ) then raise exception 'correction missing matching note and scalar evidence'; end if;
  end loop;
  next_row=jsonb_populate_record(p,patch);
  update public.alcohol_tasting_profiles set
   sweetness=next_row.sweetness,acidity=next_row.acidity,bitterness=next_row.bitterness,
   umami=next_row.umami,saltiness=next_row.saltiness,astringency=next_row.astringency,
   body=next_row.body,viscosity=next_row.viscosity,carbonation=next_row.carbonation,
   alcohol_presence=next_row.alcohol_presence,aroma_intensity=next_row.aroma_intensity,
   flavour_clarity=next_row.flavour_clarity,finish_length=next_row.finish_length,
   finish_cleanliness=next_row.finish_cleanliness,updated_at=clock_timestamp()
   where id=p.id;
  -- The existing source invalidation trigger runs above. Restore facts in the
  -- same transaction through the existing literal-evidence validation boundary.
  result=public.set_product_sensory_facts_batch(jsonb_build_array(jsonb_build_object(
   'itemId',p.alcohol_item_id,'source',public.sensory_source_snapshot(to_jsonb(next_row)),'profile',entry->'profile')));
  if (result->>'stale')::int<>0 or (result->>'applied')::int+(result->>'unchanged')::int<>1 then raise exception 'grade refresh did not complete'; end if;
  applied=applied+1;
 end loop;
 return jsonb_build_object('applied',applied,'stale',stale);
end;
$$;

--
-- Name: sensory_item_assignment_snapshot(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_item_assignment_snapshot(i jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
 select jsonb_build_object('id',i->'id','alcohol_category_id',i->'alcohol_category_id',
  'style_key',i->'style_key',
  'classification_keys',i->'classification_keys','ingredient_keys',i->'ingredient_keys',
  'production_process_keys',i->'production_process_keys');
$$;

--
-- Name: sensory_literal_balanced_acid_mouthfeel(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_literal_balanced_acid_mouthfeel(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $_$
 select coalesce(trim(regexp_replace(trim(p),'[.!。]+$','')) ~ $pattern$^균형\s*잡힌\s*산도와\s*입안\s*느낌을\s*지(?:닌다|닙니다)$$pattern$,false);
$_$;

--
-- Name: sensory_literal_cold_sake_oak(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_literal_cold_sake_oak(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $_$
 select coalesce(trim(regexp_replace(trim(p),'[.!。]+$','')) ~ $pattern$^차갑게\s*즐길수록\s*생원주의\s*생동감과\s*오크\s*숙성의\s*복합미가\s*가장\s*선명하게\s*드러나며,\s*구운\s*육류나\s*치즈처럼\s*풍미\s*있는\s*요리와\s*잘\s*어울리는\s*식중주\s*입니다$$pattern$,false);
$_$;

--
-- Name: sensory_literal_fruit_aroma_through_finish(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_literal_fruit_aroma_through_finish(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $_$
 select coalesce(trim(regexp_replace(trim(p),'[.!。]+$','')) ~ $pattern$^과실\s*향이\s*마지막\s*피니시까지\s*가득\s*찬\s*채로\s*지속되어\s*신선함과\s*만족감을\s*느낄\s*수\s*있는\s*와인(?:이다|입니다)$$pattern$,false);
$_$;

--
-- Name: sensory_literal_gold_fruit_opening(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_literal_gold_fruit_opening(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $_$
 select coalesce(trim(regexp_replace(trim(p),'[.!。]+$','')) ~ $pattern$^밝은\s*금빛을\s*띠며,\s*(.+?)의\s*풍미로\s*시작되며,\s*(풍부한|풍성한)\s*아로마\s*속에\s*(산뜻한|상쾌한)\s*신선함이\s*어우러진\s*향미를\s*선사(?:한다|합니다)$$pattern$,false);
$_$;

--
-- Name: sensory_literal_lively_smooth_fruit_finish(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_literal_lively_smooth_fruit_finish(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $_$
 select coalesce(trim(regexp_replace(trim(p),'[.!。]+$','')) ~ $pattern$^입\s*안에서는\s*생동감과\s*부드러움이\s*조화롭게\s*어우러져\s*과일\s*풍미를\s*한층\s*살려주며,\s*긴\s*여운으로\s*마무리되는\s*와인(?:이다|입니다)$$pattern$,false);
$_$;

--
-- Name: sensory_literal_oak_named_long_aroma(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_literal_oak_named_long_aroma(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $_$
 select coalesce(trim(regexp_replace(trim(p),'[.!。]+$','')) ~ $pattern$^오크\s*숙성(?:으로\s*부터|에서)\s*느껴지는\s*바닐라,\s*감초,\s*담배의\s*향이\s*길게\s*느껴짐과\s*동시에\s*인상적인\s*피니시를\s*주는\s*와인(?:이다|입니다)$$pattern$,false);
$_$;

--
-- Name: sensory_literal_oak_vanilla_aroma(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_literal_oak_vanilla_aroma(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $_$
 select coalesce(trim(regexp_replace(trim(p),'[.!。]+$','')) ~ $pattern$^잔에\s*따르면\s*딸기와\s*백도,\s*바나나칩을\s*닮은\s*달콤하고\s*화사한\s*향이\s*먼저\s*올라오고,\s*오크\s*숙성에서\s*비롯된\s*바닐라의\s*농후한\s*향이\s*부드럽게\s*이어집니다$$pattern$,false);
$_$;

--
-- Name: sensory_literal_omachi_rice(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_literal_omachi_rice(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $_$
 select coalesce(p ~ $pattern$^오마치\s*쌀의\s*특징을\s*살린\s+.+$$pattern$
  and p !~ '않|아니|없|다면|라면|지만',false);
$_$;

--
-- Name: sensory_literal_rice_water_sake(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_literal_rice_water_sake(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $_$
 select coalesce(trim(regexp_replace(trim(p),'[.!。]+$','')) ~ $pattern$^열처리와\s*여과\s*없이\s*오직\s*쌀과\s*물로만\s*술을\s*빚는\s*고집스러운\s*방식은\s*순수한\s*맛을\s*지키려는\s*카제노모리의\s*철학을\s*잘\s*보여줍니다$$pattern$,false);
$_$;

--
-- Name: sensory_note_phase_matches(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_note_phase_matches(section text, source_field text, excerpt text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
 select coalesce(
  source_field in ('aroma_note','palate_note','texture_note','finish_note','overall_note','body_note',
                   'coded_aroma_note','coded_palate_note','coded_texture_note','coded_finish_note','coded_overall_note','coded_body_note')
  and (
   source_field in (section||'_note','overall_note')
   -- Canonical evidence is checked against the existing coded claim by the caller.
   or source_field like 'coded\_%' escape '\'
   or (section='texture' and source_field='body_note')
   or (section in ('palate','texture') and source_field in ('palate_note','texture_note'))
   or case section
    when 'aroma' then excerpt ~ '(향|아로마|노트|피어오)'
    when 'palate' then excerpt ~ '(입\s*안|입에서|입에서는|맛|풍미|산미|산도)'
    when 'texture' then excerpt ~ '(바디|질감|감촉|촉감|입\s*안|목\s*넘김|점성|탄산|기포|탄닌|타닌|알코올\s*열감)'
    when 'finish' then excerpt ~ '(여운|피니시|피니쉬|마무리|뒷\s*맛|끝\s*맛|목\s*넘김)'
    else false end
  ),false);
$$;

--
-- Name: sensory_oak_long_aroma_clause(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_oak_long_aroma_clause(p text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$
declare cleaned text:=trim(regexp_replace(trim(p),'[.!。]+$','')); tail text; prefix text;
begin
 tail:=substring(cleaned from $pattern$오크\s*숙성(?:으로\s*부터|에서)\s*느껴지는.*$$pattern$);
 if not coalesce(public.sensory_literal_oak_named_long_aroma(tail),false) then return null;end if;
 prefix:=trim(left(cleaned,length(cleaned)-length(tail)));
 if prefix<>'' and prefix !~ $pattern$향기가\s*지배적으로\s*느껴지며$$pattern$ then return null;end if;
 return tail;
end;
$_$;

--
-- Name: sensory_semantic_phase_matches(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_semantic_phase_matches(identity jsonb, proof jsonb) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
 with claim as (select coalesce(identity#>>'{target,section}',identity#>>'{from,section}',identity->>'section') section)
 select (
   public.sensory_note_phase_matches(section,proof->>'sourceField',null)
   or (identity->>'kind'='sequence' and identity#>>'{from,section}' in ('palate','texture')
       and identity#>>'{to,section}'='finish' and proof->>'sourceField'='finish_note')
   or (public.sensory_note_phase_matches(section,proof->>'sourceField',proof->>'excerpt')
       and (not identity ? 'from' or coalesce(proof->>'excerpt' ~
        '(조화|균형|어우러|어울|가리|묻히|대비|비해|보다|받쳐|살려|이어|지속|남|여운|피니시|피니쉬|마무리|시작|끝|바탕|더해|채워|감싸|돋보|지탱|길|짧|함께|동시|동반)',false)))
  ) from claim;
$$;

--
-- Name: sensory_source_snapshot(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensory_source_snapshot(p jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
 select jsonb_build_object('overall_note',p->'overall_note','body_note',p->'body_note','sweetness',p->'sweetness','acidity',p->'acidity','bitterness',p->'bitterness','umami',p->'umami','saltiness',p->'saltiness','astringency',p->'astringency','body',p->'body','viscosity',p->'viscosity','carbonation',p->'carbonation','alcohol_presence',p->'alcohol_presence','aroma_intensity',p->'aroma_intensity','flavour_clarity',p->'flavour_clarity','finish_length',p->'finish_length','finish_cleanliness',p->'finish_cleanliness','sensory_scale',p->'sensory_scale','aroma_note',p->'aroma_note','palate_note',p->'palate_note','texture_note',p->'texture_note','finish_note',p->'finish_note','aroma_tags',p->'aroma_tags','palate_tags',p->'palate_tags','texture_tags',p->'texture_tags','finish_tags',p->'finish_tags','coded_sensory',p->'coded_sensory');
$$;

--
-- Name: set_product_sensory_catalog_batch(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_product_sensory_catalog_batch(entries jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$
declare entry jsonb; p public.alcohol_tasting_profiles; r jsonb; source jsonb; e jsonb; proof jsonb; section text;
 applied int:=0;unchanged int:=0;stale int:=0;
begin
 if jsonb_typeof(entries) is distinct from 'array' or jsonb_array_length(entries)>100 then raise exception 'invalid catalog sensory batch'; end if;
 for entry in select value from jsonb_array_elements(entries) loop
  select t.* into p from public.alcohol_tasting_profiles t join public.alcohol_items i on i.id=t.alcohol_item_id
   where t.id=(entry->>'profileId')::uuid and t.alcohol_item_id=(entry->>'itemId')::uuid and i.publish_status in ('published','staging') for update of t;
  if not found then stale=stale+1;continue;end if;
  source=public.sensory_source_snapshot(to_jsonb(p));
  if md5(source::text) is distinct from entry->>'sourceFingerprint'
   or md5(coalesce(p.structured_sensory::text,'null')) is distinct from entry->>'structuredFingerprint'
   or md5(coalesce(p.structured_semantics::text,'null')) is distinct from entry->>'semanticsFingerprint' then stale=stale+1;continue;end if;
  if entry->'semantics' is null or entry->'semantics'='null'::jsonb or not public.valid_product_sensory_semantics(entry->'semantics',p.alcohol_item_id) then raise exception 'invalid semantic profile'; end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p.coded_sensory#>'{semantics,entries}','[]'::jsonb)) c where not exists(
   select 1 from jsonb_array_elements(entry#>'{semantics,entries}') n where n->'identity'=c->'identity' and (n->'evidence') @> (c->'evidence'))) then raise exception 'coded semantics omitted';end if;
  for e in select value from jsonb_array_elements(entry#>'{semantics,entries}') loop
   section=coalesce(e#>>'{identity,target,section}',e#>>'{identity,from,section}',e#>>'{identity,section}');
   for proof in select value from jsonb_array_elements(e->'evidence') loop
    if proof->>'sourceField' like 'coded\_%' escape '\' then
     if not public.coded_sensory_evidence_matches(p.coded_sensory,e,proof,true) then raise exception 'invalid coded semantic evidence';end if;
     continue;
    end if;
    if not public.sensory_semantic_phase_matches(e->'identity',proof) then raise exception 'semantic phase mismatch';end if;
  if e->'identity'='{"kind":"sequence","from":{"kind":"descriptor","key":"fresh_fruit","section":"aroma"},"to":{"kind":"descriptor","key":"fresh_fruit","section":"finish"}}'::jsonb
   and not coalesce(proof->>'sourceField'='aroma_note' and proof->>'value'='present' and public.sensory_literal_fruit_aroma_through_finish(proof->>'excerpt'),false)
   and not(proof->>'sourceField'='finish_note' and proof->>'value'='present' and public.sensory_literal_oak_named_long_aroma(proof->>'excerpt') and e#>>'{identity,kind}'='character_source' and e#>>'{identity,target,kind}'='descriptor' and e#>>'{identity,target,section}'='aroma' and e#>>'{identity,target,key}' in ('vanilla','liquorice','tobacco') and e#>>'{identity,sourceKey}'='oak') and not(proof->>'sourceField'='aroma_note' and proof->>'value'='present'
   and trim(regexp_replace(trim(proof->>'excerpt'),'[.!。]+$','')) ~ '^실키하고\s*(?:우아한\s*)?(?:타닌|탄닌)과\s*입안에서\s*퍼지는\s*풍부한\s*과실향이\s*인상적인\s*와인이다$'
   and e->'identity' in (
    '{"kind":"tannin_texture","section":"texture","textureKey":"silky_texture"}'::jsonb,
    '{"kind":"character_source","target":{"kind":"descriptor","key":"fresh_fruit","section":"palate"},"sourceKey":"rich_character"}'::jsonb,
    '{"kind":"character_source","target":{"kind":"descriptor","key":"fresh_fruit","section":"palate"},"sourceKey":"wide_spread_character"}'::jsonb
   )) and not(proof->>'sourceField' in ('palate_note','texture_note') and proof->>'value'='present'
   and trim(regexp_replace(trim(proof->>'excerpt'),'[.!。]+$','')) ~ '^농축된\s*꽃과\s*풍부한\s*과일\s*향을\s*느낄\s*수\s*있고,\s*입에서는\s*온화한\s*맛과\s*조화롭고\s*풍부한\s*바디감을\s*가지고\s*있다$'
   and e->'identity' in (
    '{"kind":"character_source","target":{"kind":"descriptor","key":"floral","section":"aroma"},"sourceKey":"concentrated_character"}'::jsonb,
    '{"kind":"character_source","target":{"kind":"descriptor","key":"fresh_fruit","section":"aroma"},"sourceKey":"rich_character"}'::jsonb
   )) then raise exception 'semantic phase mismatch';end if;
    if proof->>'sourceRef' is distinct from 'catalog:product:'||p.alcohol_item_id::text||':'||(proof->>'sourceField')
     or jsonb_typeof(source->(proof->>'sourceField')) is distinct from 'string'
     or position(proof->>'excerpt' in source->>(proof->>'sourceField'))=0 then raise exception 'stale semantic evidence';end if;
   end loop;
  end loop;
  if jsonb_typeof(entry->'grades') is distinct from 'object' then raise exception 'missing grade patch';end if;
  if entry->'grades'<>'{}'::jsonb then
   r=public.refresh_product_sensory_grades_batch(jsonb_build_array(entry));
   if (r->>'applied')::int<>1 then raise exception 'grade refresh failed';end if;
  else
   r=public.set_product_sensory_facts_batch(jsonb_build_array(jsonb_build_object('itemId',p.alcohol_item_id,'source',source,'profile',entry->'profile')));
   if (r->>'stale')::int<>0 then raise exception 'source changed';end if;
  end if;
  if entry->'grades'='{}'::jsonb and p.structured_sensory is not distinct from entry->'profile' and p.structured_semantics is not distinct from entry->'semantics' then
   unchanged=unchanged+1;
  else
   update public.alcohol_tasting_profiles set structured_semantics=entry->'semantics',updated_at=clock_timestamp() where id=p.id;
   applied=applied+1;
  end if;
 end loop;
 return jsonb_build_object('applied',applied,'unchanged',unchanged,'stale',stale);
end;
$_$;

--
-- Name: set_product_sensory_facts_batch(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_product_sensory_facts_batch(entries jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare entry jsonb; p public.alcohol_tasting_profiles; f jsonb; e jsonb; source jsonb; field text;
 applied int := 0; unchanged int := 0; stale int := 0;
begin
 if jsonb_typeof(entries) is distinct from 'array' or jsonb_array_length(entries)>100 then raise exception 'invalid sensory batch'; end if;
 for entry in select value from jsonb_array_elements(entries) loop
  select t.* into p from public.alcohol_tasting_profiles t join public.alcohol_items i on i.id=t.alcohol_item_id
   where t.alcohol_item_id=(entry->>'itemId')::uuid and i.publish_status in ('published','staging') for update of t;
  if not found then stale=stale+1; continue; end if;
  source=public.sensory_source_snapshot(to_jsonb(p));
  if source is distinct from entry->'source' then stale=stale+1; continue; end if;
  if entry->'profile' is null or entry->'profile'='null'::jsonb or not public.valid_product_sensory_facts(entry->'profile',p.alcohol_item_id) then raise exception 'invalid sensory profile'; end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p.coded_sensory#>'{profile,facts}','[]'::jsonb)) c where not exists(
   select 1 from jsonb_array_elements(entry#>'{profile,facts}') n where n->'target'=c->'target' and n->'attribute'=c->'attribute' and not exists(select 1 from jsonb_array_elements(c->'evidence') oldproof where not (n->'evidence') @> jsonb_build_array(oldproof)
    and not (c->'target'='{"kind":"axis","key":"finish_cleanliness","section":"finish"}'::jsonb and c->>'attribute'='intensity'
     and oldproof->>'interpretation' is not distinct from 'finish_weight_to_cleanliness'
     and exists(select 1 from jsonb_array_elements(n->'evidence') direct where not direct ? 'interpretation' and direct->>'sourceField' in ('finish_note','overall_note','coded_finish_note','coded_overall_note')))))) then raise exception 'coded facts omitted';end if;
  -- Verify source identity and literal provenance against the locked current row.
  for f in select value from jsonb_array_elements(entry#>'{profile,facts}') loop
   for e in select value from jsonb_array_elements(f->'evidence') loop
    field=e->>'sourceField';
    if field like 'coded\_%' escape '\' then
     if not public.coded_sensory_evidence_matches(p.coded_sensory,f,e,false) then raise exception 'invalid coded sensory evidence';end if;
     continue;
    end if;
    if e->>'sourceRef' is distinct from 'catalog:product:'||p.alcohol_item_id::text||':'||field or not source ? field then raise exception 'invalid sensory source'; end if;
    if jsonb_typeof(source->field)='array' then
     if not (source->field) ? (e->>'excerpt') then raise exception 'stale sensory evidence'; end if;
    elsif jsonb_typeof(source->field)='number' then
     if e->>'excerpt' is distinct from source->>field or e->'value' is distinct from source->field then raise exception 'invalid numeric sensory evidence'; end if;
    elsif jsonb_typeof(source->field)='string' then
     if position(e->>'excerpt' in source->>field)=0 then raise exception 'stale note evidence'; end if;
    else raise exception 'missing sensory evidence'; end if;
   end loop;
  end loop;
  if p.structured_sensory is not distinct from entry->'profile' then unchanged=unchanged+1; continue; end if;
  update public.alcohol_tasting_profiles set structured_sensory=entry->'profile' where id=p.id;
  applied=applied+1;
 end loop;
 return jsonb_build_object('applied',applied,'unchanged',unchanged,'stale',stale);
end;
$$;

--
-- Name: soolgyul_account_active(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_account_active(target_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1
    from public.users u
    where u.id = target_user_id
      and u.disabled_at is null
      and u.deletion_requested_at is null
      and u.deletion_scheduled_at is null
      and u.purged_at is null
  );
$$;

--
-- Name: soolgyul_admin_change_editorial_status(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_admin_change_editorial_status(article_id uuid, next_status text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.soolgyul_admin_has_role(array['admin']::text[]) then
    raise exception 'admin role required' using errcode = '42501';
  end if;
  if next_status not in ('published', 'withdrawn') then
    raise exception 'unsupported editorial status' using errcode = '22023';
  end if;

  update public.editorial_articles
  set status = next_status
  where id = article_id;

  if not found then
    raise exception 'article not found' using errcode = 'P0002';
  end if;
end
$$;

--
-- Name: soolgyul_admin_delete_editorial_draft(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_admin_delete_editorial_draft(article_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.soolgyul_admin_has_role(array['admin']::text[]) then
    raise exception 'admin role required' using errcode = '42501';
  end if;

  delete from public.editorial_articles
  where id = article_id
    and status = 'draft'
    and published_at is null;

  if not found then
    raise exception 'only an unissued draft can be deleted' using errcode = '42501';
  end if;
end
$$;

--
-- Name: soolgyul_admin_has_role(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_admin_has_role(required_roles text[] DEFAULT ARRAY['editor'::text, 'admin'::text]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1
    from public.admin_user_roles access_grant
    join public.users account on account.id = access_grant.user_id
    where access_grant.user_id = (select auth.uid())
      and access_grant.role = any(required_roles)
      and account.disabled_at is null
      and account.deletion_requested_at is null
      and account.deletion_scheduled_at is null
      and account.purged_at is null
  );
$$;

--
-- Name: FUNCTION soolgyul_admin_has_role(required_roles text[]); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_admin_has_role(required_roles text[]) IS 'Authoritative RLS helper for active editor/admin access. Role grants cannot be changed by an authenticated client.';

--
-- Name: soolgyul_admin_save_editorial_article(uuid, uuid, text, text, text, text, text[], integer, boolean, integer, text, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_admin_save_editorial_article(article_id uuid, category_id uuid, article_slug text, article_title text, article_summary text, article_body_markdown text, article_tags text[], read_minutes integer, recommended boolean, feature_rank integer, article_status text, interest_group_ids uuid[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  saved_id uuid;
  is_admin boolean := public.soolgyul_admin_has_role(array['admin']::text[]);
  is_editor boolean := public.soolgyul_admin_has_role(array['editor']::text[]);
begin
  if not is_admin and not is_editor then
    raise exception 'administrator role required' using errcode = '42501';
  end if;
  if not is_admin and (article_status <> 'draft') then
    raise exception 'editors may save drafts only' using errcode = '42501';
  end if;

  if article_id is null then
    insert into public.editorial_articles (
      category_id,
      slug,
      title,
      summary,
      body_markdown,
      tags,
      estimated_read_minutes,
      is_recommended,
      featured_rank,
      status
    )
    values (
      category_id,
      btrim(article_slug),
      btrim(article_title),
      btrim(article_summary),
      article_body_markdown,
      coalesce(article_tags, array[]::text[]),
      read_minutes,
      recommended,
      feature_rank,
      article_status
    )
    returning id into saved_id;
  else
    update public.editorial_articles
    set category_id = soolgyul_admin_save_editorial_article.category_id,
        slug = btrim(article_slug),
        title = btrim(article_title),
        summary = btrim(article_summary),
        body_markdown = article_body_markdown,
        tags = coalesce(article_tags, array[]::text[]),
        estimated_read_minutes = read_minutes,
        is_recommended = recommended,
        featured_rank = feature_rank,
        status = article_status
    where id = article_id
      and (is_admin or (status = 'draft' and published_at is null))
    returning id into saved_id;

    if saved_id is null then
      raise exception 'article is not editable' using errcode = '42501';
    end if;
  end if;

  delete from public.editorial_article_interest_groups
  where editorial_article_interest_groups.article_id = saved_id;

  insert into public.editorial_article_interest_groups (
    article_id,
    alcohol_interest_group_id
  )
  select saved_id, interest_group_id
  from unnest(coalesce(interest_group_ids, array[]::uuid[]))
    as input(interest_group_id)
  on conflict do nothing;

  return saved_id;
end
$$;

--
-- Name: soolgyul_build_taste_card_result(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_build_taste_card_result(target_result_summary_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select jsonb_build_object(
    'wire_schema_version', case
      when summary_row.schema_version = 2
        then 'taste-card-result-wire-v2'
      else 'taste-card-result-wire-v1'
    end,
    'result_id', summary_row.id::text,
    'record_id', record_row.id::text,
    'snapshot_ref', summary_row.snapshot_ref,
    'ownership_state', case
      when record_row.user_id is null then 'anonymous'
      else 'saved'
    end,
    'alcohol_identification', jsonb_build_object(
      'mode', record_row.identification_mode,
      'alcohol_item_id', record_row.alcohol_item_id,
      'entered_alcohol_name', record_row.entered_alcohol_name,
      'alcohol_name_snapshot', record_row.alcohol_name_snapshot,
      'category', record_row.category
    ),
    'rendered_snapshot', summary_row.rendered_snapshot,
    'created_at', summary_row.snapshot_created_at
  )
  from public.taste_cards summary_row
  join public.drink_records record_row
    on record_row.id = summary_row.drink_record_id

  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id
    and summary_row.schema_version in (1, 2)
    and record_row.deleted_at is null;
$$;

--
-- Name: soolgyul_catalog_assert_item_assignment(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_assert_item_assignment(item_id uuid) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare item public.alcohol_items%rowtype;
  category text; errors jsonb;
begin
  select * into item from public.alcohol_items i where i.id=item_id;
  if not found then return; end if;
  select c.category_key into category from public.alcohol_categories c where c.id=item.alcohol_category_id;
  errors := public.soolgyul_catalog_assignment_issues(category,item.style_key,'product',item.classification_keys,item.ingredient_keys,item.production_process_keys);
  if errors<>'[]'::jsonb then
    raise exception using errcode='23514',message='invalid catalog assignment',detail=jsonb_build_object('target','product','id',item.id,'issues',errors)::text;
  end if;
end;
$$;

--
-- Name: soolgyul_catalog_assignment_category_validate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_assignment_category_validate() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare category public.alcohol_categories%rowtype; related record;
begin
  if tg_op='UPDATE' and row(new.category_key,new.is_active) is not distinct from row(old.category_key,old.is_active) then return null; end if;
  if not exists(select 1 from public.alcohol_categories c where c.category_key=old.category_key and c.is_active) and exists(
    select 1 from public.catalog_terms t where t.is_active and t.term_type in ('style','classification','ingredient','process','maturation')
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
$$;

--
-- Name: soolgyul_catalog_assignment_issue(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_assignment_issue(code text, field text, key text DEFAULT ''::text) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'pg_catalog'
    AS $$
  select jsonb_build_array(jsonb_build_object('code',code,'field',field,'key',key));
$$;

--
-- Name: soolgyul_catalog_assignment_issues(text, text, text, text[], text[], text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_assignment_issues(category text, style text, target text, classifications text[] DEFAULT '{}'::text[], ingredients text[] DEFAULT '{}'::text[], processes text[] DEFAULT '{}'::text[]) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $_$
declare
  errors jsonb := '[]'; term public.catalog_terms%rowtype;
  field text; keys text[]; key text; selected jsonb; seen text[];
  types text[]; pattern text; scheme text; effective_target text := target;
begin
  if target is null or target not in ('product','release') then
    errors := errors || public.soolgyul_catalog_assignment_issue('invalid_target','target');
    effective_target := 'product';
  end if;
  if not exists(select 1 from public.alcohol_categories c where c.category_key=category and c.is_active) then
    errors := errors || public.soolgyul_catalog_assignment_issue('unknown_category','category_key');
  end if;
  if style is not null then
    select * into term from public.catalog_terms t where t.term_type='style' and t.term_key=style and t.is_active;
    if not found then
      errors := errors || public.soolgyul_catalog_assignment_issue('unknown_term','style_key',style);
    elsif not coalesce(term.metadata->'applies_to_categories' ? category,false) then
      errors := errors || public.soolgyul_catalog_assignment_issue('wrong_category','style_key',style);
    end if;
  end if;
  foreach field in array array['classification_keys','ingredient_keys','production_process_keys'] loop
    keys := case field when 'classification_keys' then classifications when 'ingredient_keys' then ingredients else processes end;
    types := case field when 'classification_keys' then array['classification'] when 'ingredient_keys' then array['ingredient'] else array['process','maturation'] end;
    pattern := case field when 'classification_keys' then '^[a-z][a-z0-9_]*:[a-z][a-z0-9_]*$' else '^[a-z][a-z0-9_]*$' end;
    seen := '{}'; selected := '[]';
    if keys is null or coalesce(array_ndims(keys),1) <> 1 then
      errors := errors || public.soolgyul_catalog_assignment_issue('invalid_array',field);
      continue;
    end if;
    if cardinality(keys)>64 then errors := errors || public.soolgyul_catalog_assignment_issue('too_many_terms',field); end if;
    foreach key in array keys loop
      if key is null or key !~ pattern or key ~ '[[:space:]]' then
        errors := errors || public.soolgyul_catalog_assignment_issue('invalid_key',field);
        continue;
      end if;
      if key=any(seen) then errors := errors || public.soolgyul_catalog_assignment_issue('duplicate_term',field,key); end if;
      seen := array_append(seen,key);
      if (select count(*) from public.catalog_terms t where t.term_type=any(types) and t.term_key=key and t.is_active) <> 1 then
        errors := errors || public.soolgyul_catalog_assignment_issue(
          case when exists(select 1 from public.catalog_terms t where t.term_type=any(types) and t.term_key=key and t.is_active)
          then 'ambiguous_term' else 'unknown_term' end,field,key);
        continue;
      end if;
      select * into term from public.catalog_terms t where t.term_type=any(types) and t.term_key=key and t.is_active;
      selected := selected || jsonb_build_array(jsonb_build_object('key',key,'metadata',term.metadata));
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
    for term in select t.* from public.catalog_terms t where t.term_type=any(types) and t.term_key=any(seen) and t.is_active loop
      if exists(select 1 from jsonb_array_elements_text(coalesce(term.metadata->'excludes_term_keys','[]')) e where e.value=any(seen)) then
        errors := errors || public.soolgyul_catalog_assignment_issue('excluded_combination',field,term.term_key);
      end if;
    end loop;
    for scheme in select s->'metadata'->>'scheme_key' from jsonb_array_elements(selected) s
      where s->'metadata'->>'selection_cardinality'='single'
      group by s->'metadata'->>'scheme_key' having count(distinct s->>'key')>1 loop
      errors := errors || public.soolgyul_catalog_assignment_issue('single_cardinality_conflict',field,scheme);
    end loop;
  end loop;
  return (select coalesce(jsonb_agg(x order by x.code,x.field,x.key),'[]') from
    (select distinct e.code,e.field,e.key from jsonb_to_recordset(errors) as e(code text,field text,key text)) x);
end;
$_$;

--
-- Name: FUNCTION soolgyul_catalog_assignment_issues(category text, style text, target text, classifications text[], ingredients text[], processes text[]); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_catalog_assignment_issues(category text, style text, target text, classifications text[], ingredients text[], processes text[]) IS 'ADR-135: read-only assignment audit; dictionary rules are repository-owned. Empty arrays mean unknown, not absence.';

--
-- Name: soolgyul_catalog_assignment_row_validate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_assignment_row_validate() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
begin
 if tg_op='UPDATE' and row(new.alcohol_category_id,new.style_key,new.classification_keys,new.ingredient_keys,new.production_process_keys)
 is not distinct from row(old.alcohol_category_id,old.style_key,old.classification_keys,old.ingredient_keys,old.production_process_keys) then return null; end if;
 perform public.soolgyul_catalog_assert_item_assignment(new.id);
 return null;
end $$;

--
-- Name: soolgyul_catalog_assignment_term_validate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_assignment_term_validate() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare term public.catalog_terms%rowtype; m jsonb; related record; key text;
begin
  if tg_op='UPDATE' and row(new.metadata,new.is_active,new.applicable_sections) is not distinct from row(old.metadata,old.is_active,old.applicable_sections) then return null; end if;
  select * into term from public.catalog_terms t where t.term_type=new.term_type and t.term_key=new.term_key;
  if not found or term.term_type not in ('style','classification','ingredient','process','maturation') then return null; end if;
  m := term.metadata;
  -- Reverse references also matter: an otherwise unused style may still be
  -- required by active classification rules. Check final transaction state.
  if term.term_type='style' and exists(select 1 from public.catalog_terms t
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
    if term.term_type='classification' and (
      m->>'scheme_key' is distinct from split_part(term.term_key,':',1)
      or coalesce(m->>'allowed_target','') not in ('product','release','both')
      or coalesce(m->>'selection_cardinality','') not in ('single','multiple')
    ) then raise exception using errcode='23514',message='invalid catalog classification rule'; end if;
    if term.term_type='style' and (jsonb_array_length(m->'applies_to_categories')<>1
      or (m ? 'category_key' and m->>'category_key' is distinct from m->'applies_to_categories'->>0)) then
      raise exception using errcode='23514',message='inconsistent style category';
    end if;
    if term.term_type='classification' and exists(select 1 from public.catalog_terms t where
      t.term_type='classification' and t.is_active and t.term_key<>term.term_key and t.metadata->>'scheme_key'=m->>'scheme_key'
      and row(t.metadata->>'allowed_target',t.metadata->>'selection_cardinality') is distinct from row(m->>'allowed_target',m->>'selection_cardinality')) then
      raise exception using errcode='23514',message='inconsistent classification scheme rules';
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
      select 1 from public.catalog_terms s where s.term_type='style' and s.term_key=v.value and s.is_active
      and (s.metadata->'applies_to_categories') <@ (m->'applies_to_categories'))) then
      raise exception using errcode='23514',message='invalid catalog applicable style';
    end if;
    if exists(select 1 from jsonb_array_elements_text(coalesce(m->'excludes_term_keys','[]')) v where v.value=term.term_key or not exists(
      select 1 from public.catalog_terms t where t.term_type=term.term_type and t.term_key=v.value)) then
      raise exception using errcode='23514',message='invalid catalog exclusion reference';
    end if;
  end if;
  -- Affect only assignments which reference the edited term. No historical
  -- answer/snapshot rewriting, no table-wide validation on unrelated label edits.
  for related in select distinct i.id from public.alcohol_items i where
    (term.term_type='style' and i.style_key=term.term_key) or
    (term.term_type='classification' and term.term_key=any(i.classification_keys)) or
    (term.term_type='ingredient' and term.term_key=any(i.ingredient_keys)) or
    (term.term_type in ('process','maturation') and term.term_key=any(i.production_process_keys)) loop
    perform public.soolgyul_catalog_assert_item_assignment(related.id);
  end loop;
  return null;
end;
$$;

--
-- Name: soolgyul_catalog_assignment_write_lock(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_assignment_write_lock() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
begin
  if current_setting('transaction_isolation')='repeatable read' then
    raise exception using errcode='23514', message='catalog assignments require read committed or serializable maintenance';
  end if;
  perform pg_advisory_xact_lock(20260911,135);
  return null;
end;
$$;

--
-- Name: soolgyul_catalog_http_url_is_valid(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_http_url_is_valid(input_value text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
    SET search_path TO ''
    AS $_$
declare
  normalized_value text;
  port_text text;
begin
  if input_value is null
    or nullif(btrim(input_value), '') is null
    or length(input_value) > 2048
    or input_value <> btrim(input_value)
    or input_value <> normalize(input_value, NFC)
    or lower(input_value) like 'repository://%'
    or input_value ~ '[[:space:]]'
  then
    return false;
  end if;

  normalized_value := lower(input_value);
  if normalized_value !~
    '^https?://(\[[0-9a-f:.]+\]|[^/?#@[:space:]:]+)(:[0-9]+)?([/?#]|$)'
  then
    return false;
  end if;

  port_text := coalesce(
    substring(
      normalized_value from
      '^https?://\[[0-9a-f:.]+\]:([0-9]+)([/?#]|$)'
    ),
    substring(
      normalized_value from
      '^https?://[^/?#@[:space:]:]+:([0-9]+)([/?#]|$)'
    )
  );
  if port_text is null then
    return true;
  end if;
  if length(port_text) > 5 then
    return false;
  end if;
  return port_text::integer between 1 and 65535;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end
$_$;

--
-- Name: soolgyul_catalog_primary_media_rows_v1(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_primary_media_rows_v1() RETURNS TABLE(catalog_media_asset_id uuid, alcohol_item_id uuid, alcohol_release_id uuid, storage_object_path text, alt_text text, width integer, height integer, sort_order integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select selected.id,target.id,null::uuid,selected.storage_object_path,
    case when selected.is_fallback then target.name_ko || ' 대표 라인 이미지'
      else selected.alt_text end,
    selected.width,selected.height,0
  from public.alcohol_items target
  join lateral (
    select candidate.* from (
      select media.id,media.storage_object_path,media.alt_text,media.width,media.height,
        false as is_fallback,0 as source_priority
      from public.catalog_media_assets media
      where media.alcohol_item_id=target.id and media.publish_status='published'
        and media.storage_bucket='alcohol-product-images' and media.published_at is not null
      union all
      select media.id,media.storage_object_path,media.alt_text,media.width,media.height,true,1
      from public.catalog_media_fallbacks fallback
      join public.catalog_media_assets media on media.id=fallback.source_catalog_media_asset_id
        and media.publish_status='published' and media.storage_bucket='alcohol-product-images'
        and media.published_at is not null
      where fallback.alcohol_item_id=target.id
    ) candidate
    order by candidate.source_priority
    limit 1
  ) selected on true
  where target.publish_status='published'
$$;

--
-- Name: soolgyul_catalog_search_projection_rows_v1(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_search_projection_rows_v1() RETURNS TABLE(alcohol_item_id uuid, alcohol_release_id uuid, display_name text, secondary_name text, producer_or_brand_display text, category_key text, subcategory_key text, style_key text, country_code text, region_display text, abv_percent numeric, search_aliases text[], descriptor_keys text[], is_active boolean, published_at timestamp with time zone, updated_at timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
 select i.id,null::uuid,i.name_ko,i.name_en,null::text,c.category_key,null::text,i.style_key,
 i.country_code,i.region,i.abv_percent,
 coalesce(a.search_aliases,array[]::text[]),coalesce(t.descriptor_keys,array[]::text[]),
 true,i.published_at,i.updated_at
 from public.alcohol_items i join public.alcohol_categories c on c.id=i.alcohol_category_id and c.is_active
 left join lateral (
  select array_agg(distinct public.soolgyul_normalize_catalog_text(v) order by public.soolgyul_normalize_catalog_text(v)) search_aliases
  from unnest(i.aliases||i.search_keywords) v where nullif(btrim(v),'') is not null
 ) a on true
 left join lateral (
  select array_agg(distinct v order by v) descriptor_keys
  from public.alcohol_tasting_profiles p
  cross join lateral unnest(p.aroma_tags||p.palate_tags||p.texture_tags||p.finish_tags) v
  where p.alcohol_item_id=i.id
 ) t on true
 where i.publish_status='published'
$$;

--
-- Name: FUNCTION soolgyul_catalog_search_projection_rows_v1(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_catalog_search_projection_rows_v1() IS 'Reviewed public catalog rows. Exact release sensory overrides product fallback when available.';

--
-- Name: soolgyul_catalog_term_keys_are_active(text[], text[], text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_term_keys_are_active(input_keys text[], allowed_term_types text[], required_sections text[] DEFAULT NULL::text[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$
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
        select 1 from public.catalog_terms term
        where term.term_key=assigned.term_key and term.term_type=any(allowed_term_types)
          and term.is_active
          and (required_sections is null or term.applicable_sections && required_sections)
      )
    ),false
  )
$_$;

--
-- Name: soolgyul_catalog_timestamp_text_is_valid(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_timestamp_text_is_valid(input_value text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
    SET search_path TO ''
    AS $_$
begin
  if input_value is null
    or input_value <> btrim(input_value)
    or input_value <> normalize(input_value, NFC)
    or input_value !~
      '^[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]{1,6})?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$'
  then
    return false;
  end if;

  perform input_value::timestamptz;
  return true;
exception
  when invalid_datetime_format or datetime_field_overflow then
    return false;
end
$_$;

--
-- Name: soolgyul_complete_my_profile_v1(uuid, text, integer, boolean, text, text, text, boolean, boolean, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_complete_my_profile_v1(p_idempotency_key uuid, p_display_name text, p_birth_year integer, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  target_user_id uuid;
  trusted_auth_provider text;
  normalized_display_name text;
  accepted_timestamp timestamptz := clock_timestamp();
  response_payload jsonb;
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'idempotency_key_required';
  end if;

  normalized_display_name := btrim(coalesce(p_display_name, ''));
  if char_length(normalized_display_name) < 2
    or char_length(normalized_display_name) > 12
    or normalized_display_name !~ '^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ]+$'
  then
    raise exception using errcode = '22023', message = 'display_name_invalid';
  end if;

  if p_birth_year is null
    or p_birth_year < 1900
    or p_birth_year > extract(year from current_date)::integer
  then
    raise exception using errcode = '22023', message = 'birth_year_invalid';
  end if;
  if not coalesce(p_age_19_or_over_confirmed, false)
    or extract(year from current_date)::integer - p_birth_year < 19
  then
    raise exception using errcode = '22023', message = 'age_gate_required';
  end if;
  if not coalesce(p_terms_accepted, false)
    or not coalesce(p_privacy_accepted, false)
  then
    raise exception using errcode = '22023', message = 'terms_and_privacy_required';
  end if;
  if p_terms_version is distinct from 'soolgyul-terms-v1'
    or p_privacy_version is distinct from 'soolgyul-privacy-v1'
    or p_marketing_version is distinct from 'soolgyul-marketing-v1'
  then
    raise exception using errcode = '22023', message = 'policy_version_invalid';
  end if;

  select product_user.auth_provider
  into trusted_auth_provider
  from public.users product_user
  where product_user.id = target_user_id
    and product_user.disabled_at is null
    and product_user.deletion_requested_at is null
    and product_user.deletion_scheduled_at is null
    and product_user.purged_at is null
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;
  if trusted_auth_provider not in ('kakao', 'apple', 'google') then
    raise exception using errcode = '42501', message = 'unsupported_auth_provider';
  end if;

  -- Signup completion is one-shot, not a consent or nickname editing endpoint.
  -- A retry must not undo later nickname changes or revive withdrawn consents.
  if exists (
    select 1 from public.users p
    where p.id = target_user_id and p.age_confirmed_at is not null
  ) and exists (
    select 1 from public.user_consents c
    where c.user_id = target_user_id and c.consent_type = 'terms'
  ) and exists (
    select 1 from public.user_consents c
    where c.user_id = target_user_id and c.consent_type = 'privacy'
  ) then
    return public.soolgyul_get_my_profile_status_v1();
  end if;

  update public.users profile
  set display_name = normalized_display_name,
      age_confirmed_at = coalesce(profile.age_confirmed_at, accepted_timestamp),
      updated_at = accepted_timestamp
  where profile.id = target_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'profile_not_found';
  end if;

  if not exists (
    select 1 from public.user_consents consent
    where consent.user_id = target_user_id
      and consent.consent_type = 'age_19'
      and consent.document_version = 'self-attestation-v1'
      and consent.withdrawn_at is null
  ) then
    insert into public.user_consents (
      user_id, consent_type, document_version, accepted_at
    ) values (
      target_user_id, 'age_19', 'self-attestation-v1', accepted_timestamp
    );
  end if;

  if not exists (
    select 1 from public.user_consents consent
    where consent.user_id = target_user_id
      and consent.consent_type = 'terms'
      and consent.document_version = p_terms_version
      and consent.withdrawn_at is null
  ) then
    insert into public.user_consents (
      user_id, consent_type, document_version, accepted_at
    ) values (
      target_user_id, 'terms', p_terms_version, accepted_timestamp
    );
  end if;

  if not exists (
    select 1 from public.user_consents consent
    where consent.user_id = target_user_id
      and consent.consent_type = 'privacy'
      and consent.document_version = p_privacy_version
      and consent.withdrawn_at is null
  ) then
    insert into public.user_consents (
      user_id, consent_type, document_version, accepted_at
    ) values (
      target_user_id, 'privacy', p_privacy_version, accepted_timestamp
    );
  end if;

  if coalesce(p_marketing_opt_in, false) then
    if not exists (
      select 1 from public.user_consents consent
      where consent.user_id = target_user_id
        and consent.consent_type = 'marketing'
        and consent.document_version = p_marketing_version
        and consent.withdrawn_at is null
    ) then
      insert into public.user_consents (
        user_id, consent_type, document_version, accepted_at
      ) values (
        target_user_id, 'marketing', p_marketing_version, accepted_timestamp
      );
    end if;
  else
    update public.user_consents consent
    set withdrawn_at = accepted_timestamp
    where consent.user_id = target_user_id
      and consent.consent_type = 'marketing'
      and consent.withdrawn_at is null;
  end if;

  response_payload := jsonb_build_object(
    'profile_complete', true,
    'display_name', normalized_display_name,
    'age_19_or_over_confirmed', true,
    'terms_version', p_terms_version,
    'privacy_version', p_privacy_version,
    'marketing_opt_in', coalesce(p_marketing_opt_in, false),
    'deletion_state', 'active'
  );

  return response_payload;
end
$_$;

--
-- Name: FUNCTION soolgyul_complete_my_profile_v1(p_idempotency_key uuid, p_display_name text, p_birth_year integer, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_complete_my_profile_v1(p_idempotency_key uuid, p_display_name text, p_birth_year integer, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean) IS 'One-time signup completion; repeats return current state without rewriting later preferences or consents.';

--
-- Name: soolgyul_complete_my_profile_v2(uuid, text, integer, boolean, text, text, text, boolean, boolean, boolean, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_complete_my_profile_v2(p_idempotency_key uuid, p_display_name text, p_birth_year integer, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text DEFAULT NULL::text, p_gender_consent_accepted boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  target uuid := auth.uid();
  already_complete boolean;
  result jsonb;
begin
  if target is null then
    raise exception using errcode='28000', message='authentication_required';
  end if;
  if (p_gender is not null and p_gender not in ('male','female','other'))
    or (p_gender is not null and not coalesce(p_gender_consent_accepted,false))
    or (p_gender is null and coalesce(p_gender_consent_accepted,false)) then
    raise exception using errcode='22023', message='gender_consent_invalid';
  end if;
  -- Serialize with v1 and account deletion. Never use signup retries as profile edits.
  select u.age_confirmed_at is not null
    and exists(select 1 from public.user_consents c where c.user_id=target and c.consent_type='terms')
    and exists(select 1 from public.user_consents c where c.user_id=target and c.consent_type='privacy')
  into already_complete from public.users u where u.id=target for update;
  result := public.soolgyul_complete_my_profile_v1(
    p_idempotency_key,p_display_name,p_birth_year,p_age_19_or_over_confirmed,
    p_terms_version,p_privacy_version,p_marketing_version,p_terms_accepted,
    p_privacy_accepted,p_marketing_opt_in);
  if not coalesce(already_complete,false) and p_gender is not null then
    update public.users set gender=p_gender,
      gender_consent_accepted_at=clock_timestamp(),
      gender_consent_version='soolgyul-gender-v1' where id=target;
  end if;
  return result;
end $$;

--
-- Name: soolgyul_complete_my_profile_v3(uuid, text, date, boolean, text, text, text, boolean, boolean, boolean, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_complete_my_profile_v3(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text DEFAULT NULL::text, p_gender_consent_accepted boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  target uuid := auth.uid();
  already_complete boolean;
  result jsonb;
begin
  if target is null then
    raise exception using errcode='28000', message='authentication_required';
  end if;
  if p_birth_date is null or not isfinite(p_birth_date)
    or p_birth_date < date '1900-01-01' or p_birth_date > current_date then
    raise exception using errcode='22023', message='birth_date_invalid';
  end if;
  select u.age_confirmed_at is not null
    and exists(select 1 from public.user_consents c where c.user_id=target and c.consent_type='terms')
    and exists(select 1 from public.user_consents c where c.user_id=target and c.consent_type='privacy')
  into already_complete from public.users u where u.id=target for update;
  result := public.soolgyul_complete_my_profile_v2(
    p_idempotency_key,p_display_name,extract(year from p_birth_date)::integer,
    p_age_19_or_over_confirmed,p_terms_version,p_privacy_version,p_marketing_version,
    p_terms_accepted,p_privacy_accepted,p_marketing_opt_in,p_gender,p_gender_consent_accepted);
  if not coalesce(already_complete,false) then
    update public.users set birth_date=p_birth_date where id=target;
  end if;
  return result;
end $$;

--
-- Name: soolgyul_convert_anonymous_taste_card(uuid, uuid, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_convert_anonymous_taste_card(target_user_id uuid, target_result_summary_id uuid, target_anonymous_session_digest text, target_idempotency_key uuid) RETURNS TABLE(drink_record_id uuid, result_summary_id uuid, claim_snapshot_id uuid, converted boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
declare
  target_record public.drink_records%rowtype;
  target_snapshot_id uuid;
  did_convert boolean := false;
begin
  if target_user_id is null
    or target_result_summary_id is null
    or target_idempotency_key is null
    or target_anonymous_session_digest is null
    or target_anonymous_session_digest !~ '^[0-9a-f]{64}$'
  then
    raise exception using
      errcode = '22023',
      message = 'invalid anonymous taste card conversion request';
  end if;

  -- Use the same user-then-record lock order as account/profile writes.
  perform 1 from public.users u where u.id = target_user_id for update;
  if not found or not public.soolgyul_account_active(target_user_id) then
    raise exception using
      errcode = '42501',
      message = 'active account required';
  end if;

  if not exists (
    select 1
    from public.users profile_row
    where profile_row.id = target_user_id
      and profile_row.age_confirmed_at is not null
      and exists (
        select 1 from public.user_consents c
        where c.user_id = target_user_id and c.consent_type = 'terms'
          and c.document_version = 'soolgyul-terms-v1' and c.withdrawn_at is null
      )
      and exists (
        select 1 from public.user_consents c
        where c.user_id = target_user_id and c.consent_type = 'privacy'
          and c.document_version = 'soolgyul-privacy-v1' and c.withdrawn_at is null
      )
  ) then
    raise exception using
      errcode = '42501',
      message = 'completed adult profile required';
  end if;

  select record_row.*
  into target_record
  from public.taste_cards summary_row
  join public.drink_records record_row
    on record_row.id = summary_row.drink_record_id
  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id
  for update of record_row;

  if not found or target_record.deleted_at is not null then
    raise exception using
      errcode = 'P0002',
      message = 'taste card result not found';
  end if;

  select summary_row.snapshot_id
  into target_snapshot_id
  from public.taste_cards summary_row
  
  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id;

  if target_snapshot_id is null then
    raise exception using
      errcode = '55000',
      message = 'final taste card snapshot required';
  end if;

  if not exists (
    select 1
    from public.taste_card_generation_attempts attempt_row
    where attempt_row.anonymous_session_digest = target_anonymous_session_digest
      and attempt_row.result_summary_id = target_result_summary_id
      and attempt_row.claim_snapshot_id = target_snapshot_id
      and attempt_row.state = 'final'
      and (target_record.user_id = target_user_id
        or attempt_row.conversion_expires_at > now())
  ) then
    raise exception using
      errcode = '42501',
      message = 'anonymous taste card proof is invalid or expired';
  end if;

  if target_record.user_id is null then
    update public.drink_records
    set user_id = target_user_id,
        anonymous_session_id = null,
        saved_at = coalesce(saved_at, now()),
        updated_at = now()
    where id = target_record.id;
    did_convert := true;
  elsif target_record.user_id <> target_user_id then
    raise exception using
      errcode = '42501',
      message = 'taste card is owned by another account';
  end if;

  return query
  select
    target_record.id,
    target_result_summary_id,
    target_snapshot_id,
    did_convert;
end;
$_$;

--
-- Name: FUNCTION soolgyul_convert_anonymous_taste_card(target_user_id uuid, target_result_summary_id uuid, target_anonymous_session_digest text, target_idempotency_key uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_convert_anonymous_taste_card(target_user_id uuid, target_result_summary_id uuid, target_anonymous_session_digest text, target_idempotency_key uuid) IS 'Service-only proof-checked ownership transition, serialized on the record; same-owner retries are no-ops.';

--
-- Name: soolgyul_enforce_drink_interest_limit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_enforce_drink_interest_limit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if exists (
    select 1
    from public.user_drink_interests current_selection
    where current_selection.user_id = new.user_id
      and current_selection.alcohol_interest_group_id = new.alcohol_interest_group_id
  ) then
    return new;
  end if;

  perform 1
  from public.users product_user
  where product_user.id = new.user_id
  for update;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'interest_owner_not_found';
  end if;

  if (
    select count(*)
    from public.user_drink_interests current_selection
    where current_selection.user_id = new.user_id
  ) >= 5 then
    raise exception using
      errcode = '23514',
      message = 'drink_interest_limit_exceeded';
  end if;

  return new;
end
$$;

--
-- Name: soolgyul_finalize_taste_card_generation(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_finalize_taste_card_generation(input_bundle jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  attempt_row public.taste_card_generation_attempts%rowtype;
  request_row jsonb := input_bundle->'request';
  identification_row jsonb := input_bundle->'alcohol_identification';
  version_row jsonb := input_bundle->'version_vector';
  rendered_row jsonb := input_bundle->'rendered_view';
  answer_row jsonb;
  question_id uuid;
  generated_snapshot_id uuid := gen_random_uuid();
  principal_kind text := input_bundle #>> '{principal,kind}';
  wire_schema_version text := coalesce(
    input_bundle->>'wire_schema_version',
    'taste-card-result-wire-v1'
  );
  selected_catalog_id uuid;
  resolved_alcohol_item_id uuid;
  result_schema_version integer;
  semantic_snapshot_row jsonb;
begin
  if jsonb_typeof(input_bundle) is distinct from 'object'
    or jsonb_typeof(request_row) is distinct from 'object'
    or jsonb_typeof(identification_row) is distinct from 'object'
    or jsonb_typeof(version_row) is distinct from 'object'
    or jsonb_typeof(rendered_row) is distinct from 'object'
  then
    raise exception using
      errcode = '22023',
      message = 'taste card finalization bundle is invalid';
  end if;

  if wire_schema_version not in (
    'taste-card-result-wire-v1',
    'taste-card-result-wire-v2'
  ) then
    raise exception using
      errcode = '22023',
      message = 'taste card wire schema version is invalid';
  end if;

  result_schema_version := case
    when wire_schema_version = 'taste-card-result-wire-v2' then 2
    else 1
  end;

  if result_schema_version = 2 and (
    rendered_row #>> '{metadata,schema_version}' is distinct from '2'
    or rendered_row #>> '{metadata,snapshot_ref}'
      is distinct from input_bundle->>'semantic_snapshot_id'
    or jsonb_typeof(input_bundle->'evidence_context_v2') is distinct from 'object'
    or jsonb_typeof(input_bundle->'insight_plan_v2') is distinct from 'object'
    or jsonb_typeof(input_bundle->'style_recommendation_plan_v2') is distinct from 'object'
    or pg_column_size(input_bundle->'evidence_context_v2') > 262144
    or pg_column_size(input_bundle->'insight_plan_v2') > 65536
    or pg_column_size(input_bundle->'style_recommendation_plan_v2') > 65536
  ) then
    raise exception using
      errcode = '22023',
      message = 'taste card V2 private or public snapshot is invalid';
  end if;

  select existing_attempt.*
  into attempt_row
  from public.taste_card_generation_attempts existing_attempt
  where existing_attempt.attempt_ref = input_bundle->>'attempt_ref'
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'generation attempt not found';
  end if;
  if attempt_row.request_digest is distinct from input_bundle->>'request_digest' then
    raise exception using errcode = '22023', message = 'idempotency_conflict';
  end if;
  if attempt_row.idempotency_key is distinct from
    (request_row->>'idempotency_key')::uuid
  then
    raise exception using errcode = '22023', message = 'idempotency key mismatch';
  end if;

  if principal_kind = 'authenticated' then
    if attempt_row.owner_user_id is distinct from
      (input_bundle #>> '{principal,user_id}')::uuid
    then
      raise exception using errcode = '42501', message = 'generation principal mismatch';
    end if;
    if not public.soolgyul_account_active(attempt_row.owner_user_id)
      or not exists (
        select 1
        from public.users profile_row
        where profile_row.id = attempt_row.owner_user_id
          and profile_row.age_confirmed_at is not null
      )
      or not exists (
        select 1
        from public.user_consents consent_row
        where consent_row.user_id = attempt_row.owner_user_id
          and consent_row.consent_type = 'age_19'
          and consent_row.document_version = 'self-attestation-v1'
          and consent_row.withdrawn_at is null
      )
      or not exists (
        select 1
        from public.user_consents consent_row
        where consent_row.user_id = attempt_row.owner_user_id
          and consent_row.consent_type = 'terms'
          and consent_row.document_version = 'soolgyul-terms-v1'
          and consent_row.withdrawn_at is null
      )
      or not exists (
        select 1
        from public.user_consents consent_row
        where consent_row.user_id = attempt_row.owner_user_id
          and consent_row.consent_type = 'privacy'
          and consent_row.document_version = 'soolgyul-privacy-v1'
          and consent_row.withdrawn_at is null
      )
    then
      raise exception using errcode = '42501', message = 'completed adult profile required';
    end if;
  elsif principal_kind = 'anonymous' then
    if attempt_row.anonymous_session_digest is distinct from
      input_bundle #>> '{principal,anonymous_session_digest}'
    then
      raise exception using errcode = '42501', message = 'generation principal mismatch';
    end if;
    if encode(
      extensions.digest(request_row->>'anonymous_session_id', 'sha256'),
      'hex'
    ) is distinct from attempt_row.anonymous_session_digest
    then
      raise exception using errcode = '42501', message = 'anonymous session mismatch';
    end if;
  else
    raise exception using errcode = '22023', message = 'generation principal invalid';
  end if;

  if attempt_row.state = 'final' then
    return public.soolgyul_build_taste_card_result(attempt_row.result_summary_id);
  end if;

  if identification_row->>'mode' = 'catalog_match' then
    selected_catalog_id := nullif(
      identification_row->>'alcohol_item_id',
      ''
    )::uuid;
    if selected_catalog_id is null then
      raise exception using errcode = '22023', message = 'catalog identifier required';
    end if;

    select item_row.id
    into resolved_alcohol_item_id
    from public.alcohol_items item_row
    where item_row.id = selected_catalog_id
      and item_row.publish_status = 'published';

    if resolved_alcohol_item_id is null then
      raise exception using errcode = '22023', message = 'catalog identifier is not publishable';
    end if;
  elsif identification_row->>'mode' = 'direct_input' then
    if identification_row->'alcohol_item_id' is distinct from 'null'::jsonb then
      raise exception using errcode = '22023', message = 'direct input cannot use a catalog identifier';
    end if;
  else
    raise exception using errcode = '22023', message = 'identification mode is invalid';
  end if;

  insert into public.drink_records (
    id,
    user_id,
    anonymous_session_id,
    questionnaire_version_id,
    alcohol_item_id,
    entered_alcohol_name,
    alcohol_name_snapshot,
    category,
    identification_mode,
    photo_storage_path,
    one_line_note,
    saved_at,
    idempotency_key
  )
  values (
    attempt_row.reserved_record_id,
    case when principal_kind = 'authenticated' then attempt_row.owner_user_id else null end,
    case when principal_kind = 'anonymous' then request_row->>'anonymous_session_id' else null end,
    (request_row->>'questionnaire_version_id')::uuid,
    resolved_alcohol_item_id,
    nullif(identification_row->>'entered_alcohol_name', ''),
    identification_row->>'alcohol_name_snapshot',
    nullif(identification_row->>'category', ''),
    identification_row->>'mode',
    null,
    nullif(request_row->>'q7_free_text', ''),
    case when principal_kind = 'authenticated' then now() else null end,
    request_row->>'idempotency_key'
  );

  for answer_row in
    select value
    from jsonb_array_elements(coalesce(request_row->'answers', '[]'::jsonb))
  loop
    select question_row.id
    into question_id
    from public.questionnaire_questions question_row
    where question_row.questionnaire_version_id =
      (request_row->>'questionnaire_version_id')::uuid
      and question_row.question_key = answer_row->>'question_key';

    if (answer_row ? 'option_gap_reported' and jsonb_typeof(answer_row->'option_gap_reported') not in ('boolean', 'null'))
      or (answer_row ? 'feedback_text' and jsonb_typeof(answer_row->'feedback_text') not in ('string', 'null')) then
      raise exception 'invalid_question_feedback' using errcode = '22023';
    end if;

    insert into public.drink_record_answers (
      drink_record_id,
      questionnaire_version_id,
      questionnaire_question_id,
      question_key,
      question_label_snapshot,
      selected_option_keys,
      selected_option_labels_snapshot,
      free_text,
      option_gap_reported,
      feedback_text
    )
    values (
      attempt_row.reserved_record_id,
      (request_row->>'questionnaire_version_id')::uuid,
      question_id,
      answer_row->>'question_key',
      answer_row->>'question_label_snapshot',
      array(
        select jsonb_array_elements_text(
          coalesce(answer_row->'selected_option_keys', '[]'::jsonb)
        )
      ),
      array(
        select jsonb_array_elements_text(
          coalesce(answer_row->'selected_option_labels_snapshot', '[]'::jsonb)
        )
      ),
      nullif(answer_row->>'free_text', ''),
      (answer_row->>'option_gap_reported')::boolean,
      nullif(btrim(answer_row->>'feedback_text'), '')
    );
  end loop;

  insert into public.taste_cards (
    id,
    drink_record_id,
    result_type_key,
    taste_axis_scores,
    preference_cues,
    next_drink_directions,
    burdensome_directions,
    summary_paragraphs,
    share_card_text,
    catalog_evidence,
    schema_version,
    rule_version,
    result_snapshot
  )
  values (
    attempt_row.reserved_result_summary_id,
    attempt_row.reserved_record_id,
    case when result_schema_version = 2 then 'taste_card_v2' else 'taste_card_v1' end,
    '{}'::jsonb,
    case
      when result_schema_version = 2
        then coalesce(rendered_row->'core_summary'->'blocks', '[]'::jsonb)
      else jsonb_build_array(rendered_row #>> '{summary,discovery,body}')
    end,
    case
      when result_schema_version = 2
        then coalesce(rendered_row->'next_drink'->'candidates', '[]'::jsonb)
      else jsonb_build_array(rendered_row #>> '{summary,next_choice,body}')
    end,
    case
      when result_schema_version = 2
        then jsonb_build_array(rendered_row #>> '{next_drink,defer_formula}')
      else '[]'::jsonb
    end,
    case
      when result_schema_version = 2
        then coalesce(rendered_row->'discovery'->'blocks', '[]'::jsonb)
      else jsonb_build_array(rendered_row #>> '{discovery,lead}')
    end,
    case
      when result_schema_version = 2 then coalesce(
        rendered_row #>> '{core_summary,blocks,0,text}',
        identification_row->>'alcohol_name_snapshot'
      )
      else rendered_row #>> '{closing,body}'
    end,
    case
      when result_schema_version = 2 then jsonb_build_object(
        'selected_catalog_id', identification_row->'alcohol_item_id',
        'resolved_alcohol_item_id', resolved_alcohol_item_id,
        'entered_alcohol_name', identification_row->'entered_alcohol_name',
        'alcohol_name_snapshot', identification_row->'alcohol_name_snapshot'
      )
      else jsonb_build_object(
        'matched_catalog_item_id', identification_row->'alcohol_item_id',
        'entered_alcohol_name', identification_row->'entered_alcohol_name',
        'alcohol_name_snapshot', identification_row->'alcohol_name_snapshot'
      )
    end,
    result_schema_version,
    case
      when result_schema_version = 2
        then rendered_row #>> '{metadata,rule_version}'
      else version_row->>'claim_registry_version'
    end,
    rendered_row
  );

  semantic_snapshot_row := jsonb_build_object(
    'snapshot_id', input_bundle->>'semantic_snapshot_id',
    'snapshot_status', 'final',
    'subject_record_ref', input_bundle #>> '{canonical_input,subject_record_ref}',
    'canonical_input_digest', input_bundle->>'canonical_input_digest',
    'version_vector', version_row,
    'source_statuses', input_bundle #> '{canonical_input,source_statuses}',
    'observations', input_bundle #> '{canonical_input,observations}',
    'evidence_refs', input_bundle #> '{canonical_input,evidence_refs}',
    'claim_decisions', input_bundle->'decisions',
    'semantic_projection', input_bundle->'semantic_projection',
    'rendered_projection', null,
    'supersedes_snapshot_id', 'none',
    'withdrawal_reason_code', 'none',
    'created_at', input_bundle->>'generated_at'
  );

  if result_schema_version = 2 then
    semantic_snapshot_row := semantic_snapshot_row || jsonb_build_object(
      'evidence_context_v2', input_bundle->'evidence_context_v2',
      'insight_plan_v2', input_bundle->'insight_plan_v2',
      'style_recommendation_plan_v2', input_bundle->'style_recommendation_plan_v2'
    );
  end if;

  if pg_column_size(semantic_snapshot_row) > 524288 then
    raise exception using
      errcode = '22023',
      message = 'taste card semantic snapshot exceeds the persistence limit';
  end if;

  update public.taste_cards set (
    snapshot_id,
    snapshot_ref,
    canonical_input_digest,
    questionnaire_version,
    catalog_taxonomy_version,
    catalog_evidence_version,
    adapter_compatibility_version,
    canonical_schema_version,
    memo_rule_version,
    claim_registry_version,
    claim_rule_versions,
    copy_template_version,
    presentation_version,
    source_statuses,
    semantic_snapshot,
    rendered_snapshot
  ) = (
    generated_snapshot_id,
    input_bundle->>'semantic_snapshot_id',
    input_bundle->>'canonical_input_digest',
    version_row->>'questionnaire_version',
    version_row->>'catalog_taxonomy_version',
    version_row->>'catalog_evidence_version',
    version_row->>'adapter_compatibility_version',
    version_row->>'canonical_schema_version',
    version_row->>'memo_rule_version',
    version_row->>'claim_registry_version',
    version_row->'claim_rule_versions',
    version_row->>'copy_template_version',
    version_row->>'presentation_version',
    input_bundle #> '{canonical_input,source_statuses}',
    semantic_snapshot_row,
    rendered_row
  ), lifecycle = 'final', snapshot_created_at = now()
  where id = attempt_row.reserved_result_summary_id;

  update public.taste_card_generation_attempts
  set state = 'final',
      error_code = null,
      retry_after = null,
      result_summary_id = attempt_row.reserved_result_summary_id,
      claim_snapshot_id = generated_snapshot_id,
      conversion_key_version = input_bundle->>'conversion_key_version',
      conversion_expires_at = nullif(
        input_bundle->>'conversion_expires_at',
        ''
      )::timestamptz,
      completed_at = now(),
      updated_at = now()
  where id = attempt_row.id;

  return public.soolgyul_build_taste_card_result(
    attempt_row.reserved_result_summary_id
  );
end;
$$;

--
-- Name: FUNCTION soolgyul_finalize_taste_card_generation(input_bundle jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_finalize_taste_card_generation(input_bundle jsonb) IS 'Finalizes one unified-entry taste-card record without persisting a redundant start-path discriminator.';

--
-- Name: soolgyul_finalize_withdrawn_account_data(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_finalize_withdrawn_account_data(target_user_id uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare account_row public.users%rowtype; retained_count integer;
begin
  select * into account_row from public.users where id=target_user_id for update;
  if not found then return 0; end if;
  if account_row.purged_at is not null then return 0; end if;
  if account_row.deletion_provider_revoked_at is null then raise exception 'provider_revocation_required'; end if;
  if account_row.account_status <> 'scheduled_deletion'
    or account_row.deletion_scheduled_at is null
    or account_row.deletion_scheduled_at > statement_timestamp() then
    raise exception 'account_purge_not_due';
  end if;
  if exists(select 1 from storage.objects where bucket_id='soolgyul-private'
    and starts_with(name,target_user_id::text || '/')) then
    raise exception 'private_storage_cleanup_required';
  end if;

  -- Preserve memo and questionnaire free text verbatim; never archive support
  -- inquiries, names, account metadata, consent history, or raw engine snapshots.
  insert into public.withdrawn_drink_records(birth_year,gender,record_data)
  select extract(year from account_row.birth_date)::integer,
    case when account_row.gender_consent_accepted_at is not null then account_row.gender end,
    jsonb_build_object(
      'alcohol_item_id',r.alcohol_item_id,
      'entered_alcohol_name',r.entered_alcohol_name,
      'alcohol_name_snapshot',r.alcohol_name_snapshot,
      'category',r.category,
      'one_line_note',r.one_line_note,
      'questionnaire_version_id',r.questionnaire_version_id,
      'answers',coalesce((select jsonb_agg(jsonb_build_object(
        'question_key',a.question_key,'question_label_snapshot',a.question_label_snapshot,
        'selected_option_keys',a.selected_option_keys,
        'selected_option_labels_snapshot',a.selected_option_labels_snapshot,
        'free_text',a.free_text,'feedback_text',a.feedback_text,
        'option_gap_reported',a.option_gap_reported) order by a.question_key,a.id)
        from public.drink_record_answers a where a.drink_record_id=r.id),'[]'::jsonb),
      'card',(select public.soolgyul_strip_retained_card_links(jsonb_build_object(
        'result_type_key',c.result_type_key,'taste_axis_scores',c.taste_axis_scores,
        'preference_cues',c.preference_cues,'next_drink_directions',c.next_drink_directions,
        'burdensome_directions',c.burdensome_directions,
        'summary_paragraphs',c.summary_paragraphs,'share_card_text',c.share_card_text,
        'rendered_snapshot',c.rendered_snapshot))
        from public.taste_cards c where c.drink_record_id=r.id)
    )
  from public.drink_records r
  where r.user_id=target_user_id and r.deleted_at is null;
  get diagnostics retained_count = row_count;

  -- Converted anonymous attempts can still carry an anonymous proof. Remove
  -- them by record linkage too, not just by owner_user_id.
  delete from public.taste_card_generation_attempts a
  where a.owner_user_id=target_user_id or exists (
    select 1 from public.drink_records r where r.user_id=target_user_id
      and (r.id=a.reserved_record_id or exists (
        select 1 from public.taste_cards c where c.drink_record_id=r.id
          and c.id=a.result_summary_id)));
  delete from public.drink_records where user_id=target_user_id;
  update public.users set birth_date=null,gender=null,
    gender_consent_accepted_at=null,gender_consent_version=null,
    display_name=null,email=null,provider_user_id=gen_random_uuid()::text,
    age_confirmed_at=null,profile_created_at=null,last_sign_in_at=null,
    purged_at=statement_timestamp(),updated_at=statement_timestamp()
  where id=target_user_id;
  return retained_count;
end;
$$;

--
-- Name: soolgyul_get_marketing_consent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_get_marketing_consent() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare target uuid := auth.uid();
begin
  if target is null or not public.soolgyul_account_active(target) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;
  return exists(select 1 from public.user_consents
    where user_id = target and consent_type = 'marketing'
      and document_version = 'soolgyul-marketing-v1' and withdrawn_at is null);
end;
$$;

--
-- Name: soolgyul_get_my_deletion_state(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_get_my_deletion_state() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare u public.users%rowtype;
begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 select * into u from public.users where id=auth.uid();
 if not found then raise exception 'account_not_found'; end if;
 return jsonb_build_object('deletion_state',case when u.purged_at is not null then 'purged'
   when u.deletion_scheduled_at is not null then 'scheduled' else 'active' end,
  'requested_at',u.deletion_requested_at,'scheduled_deletion_at',u.deletion_scheduled_at,
  'restore_available',u.purged_at is null and u.disabled_at is null
    and u.deletion_scheduled_at>statement_timestamp(),
  'provider_revoked',u.deletion_provider_revoked_at is not null);
end; $$;

--
-- Name: soolgyul_get_my_profile_preferences(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_get_my_profile_preferences() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  target_user_id uuid;
  current_display_name text;
  current_interest_keys text[];
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  if not public.soolgyul_account_active(target_user_id) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  select profile.display_name
  into current_display_name
  from public.users profile
  where profile.id = target_user_id;

  select coalesce(
    array_agg(
      interest_group.interest_group_key
      order by interest_group.sort_order, interest_group.interest_group_key
    ),
    array[]::text[]
  )
  into current_interest_keys
  from public.user_drink_interests selection
  join public.alcohol_interest_groups interest_group
    on interest_group.id = selection.alcohol_interest_group_id
  where selection.user_id = target_user_id;

  return jsonb_build_object(
    'display_name', current_display_name,
    'interest_group_keys', to_jsonb(current_interest_keys)
  );
end
$$;

--
-- Name: FUNCTION soolgyul_get_my_profile_preferences(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_get_my_profile_preferences() IS 'Returns the active authenticated owner display name and stable interest-group wire keys.';

--
-- Name: soolgyul_get_my_profile_status_v1(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_get_my_profile_status_v1() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  target_user_id uuid;
  current_display_name text;
  current_account_status text;
  has_adult_confirmation boolean;
  has_terms_acceptance boolean;
  has_privacy_acceptance boolean;
  has_marketing_acceptance boolean;
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;

  select product_user.display_name, product_user.account_status
  into current_display_name, current_account_status
  from public.users product_user
  
  where product_user.id = target_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'profile_not_found';
  end if;
  if current_account_status in ('disabled', 'purged') then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  select
    exists (
      select 1
      from public.user_consents consent
      where consent.user_id = target_user_id
        and consent.consent_type = 'age_19'
        and consent.document_version = 'self-attestation-v1'
        and consent.withdrawn_at is null
    ),
    exists (
      select 1
      from public.user_consents consent
      where consent.user_id = target_user_id
        and consent.consent_type = 'terms'
        and consent.document_version = 'soolgyul-terms-v1'
        and consent.withdrawn_at is null
    ),
    exists (
      select 1
      from public.user_consents consent
      where consent.user_id = target_user_id
        and consent.consent_type = 'privacy'
        and consent.document_version = 'soolgyul-privacy-v1'
        and consent.withdrawn_at is null
    ),
    exists (
      select 1
      from public.user_consents consent
      where consent.user_id = target_user_id
        and consent.consent_type = 'marketing'
        and consent.document_version = 'soolgyul-marketing-v1'
        and consent.withdrawn_at is null
    )
  into
    has_adult_confirmation,
    has_terms_acceptance,
    has_privacy_acceptance,
    has_marketing_acceptance;

  return jsonb_build_object(
    'profile_complete',
      current_display_name is not null
      and has_adult_confirmation
      and has_terms_acceptance
      and has_privacy_acceptance,
    'display_name', current_display_name,
    'age_19_or_over_confirmed', has_adult_confirmation,
    'terms_version', case
      when has_terms_acceptance then 'soolgyul-terms-v1'
      else null
    end,
    'privacy_version', case
      when has_privacy_acceptance then 'soolgyul-privacy-v1'
      else null
    end,
    'marketing_opt_in', has_marketing_acceptance,
    'deletion_state', case
      when current_account_status = 'scheduled_deletion' then 'scheduled'
      else 'active'
    end
  );
end
$$;

--
-- Name: soolgyul_get_owned_taste_card_result(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_get_owned_taste_card_result(target_result_summary_id uuid, target_user_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if not public.soolgyul_account_active(target_user_id)
    or not exists (
      select 1
      from public.taste_cards summary_row
      join public.drink_records record_row
        on record_row.id = summary_row.drink_record_id
      where summary_row.id = target_result_summary_id
        and record_row.user_id = target_user_id
        and record_row.deleted_at is null
    )
  then
    raise exception using errcode = 'P0002', message = 'owned result not found';
  end if;
  return public.soolgyul_build_taste_card_result(target_result_summary_id);
end;
$$;

--
-- Name: soolgyul_get_sensory_question_context(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_get_sensory_question_context(target_catalog_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
 select jsonb_build_object(
 'id',item.id,'name',item.name_ko,'name_en',item.name_en,
 'category',category.category_key,'style_key',item.style_key,'target','product',
 'facets',to_jsonb(item.classification_keys),'ingredient_keys',item.ingredient_keys,
 'production_process_keys',item.production_process_keys,
 'aroma_keys',coalesce(to_jsonb(profile.aroma_tags),'[]'::jsonb),
 'texture_keys',coalesce(to_jsonb(profile.texture_tags),'[]'::jsonb),
 'sensory_scale',5,
 'levels',jsonb_strip_nulls(jsonb_build_object(
 'sweetness',profile.sweetness,'acidity',profile.acidity,'bitterness',profile.bitterness,
 'astringency',profile.astringency,'body',profile.body,'alcohol_presence',profile.alcohol_presence)))
 from public.alcohol_items item join public.alcohol_categories category on category.id=item.alcohol_category_id
 left join public.alcohol_tasting_profiles profile on profile.alcohol_item_id=item.id
 where item.id=target_catalog_id and item.publish_status='published';
$$;

--
-- Name: soolgyul_get_taste_card_result_for_attempt(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_get_taste_card_result_for_attempt(target_attempt_ref text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  target_result_id uuid;
begin
  select attempt_row.result_summary_id
  into target_result_id
  from public.taste_card_generation_attempts attempt_row
  where attempt_row.attempt_ref = target_attempt_ref
    and attempt_row.state = 'final';
  if target_result_id is null then
    raise exception using errcode = 'P0002', message = 'final result not found';
  end if;
  return public.soolgyul_build_taste_card_result(target_result_id);
end;
$$;

--
-- Name: soolgyul_guard_final_drink_record_identity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_guard_final_drink_record_identity() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if exists (
    select 1
    from public.taste_cards summary_row
    where summary_row.drink_record_id = old.id
      and summary_row.snapshot_id is not null
  ) then
    raise exception using
      errcode = '23514',
      message = 'final taste card drink identity is immutable';
  end if;
  return new;
end;
$$;

--
-- Name: soolgyul_guard_questionnaire_content(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_guard_questionnaire_content() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  parent_status text;
  parent_question_id uuid;
begin
  if tg_table_name = 'questionnaire_questions' then
    if tg_op = 'DELETE' then
      select status
      into parent_status
      from public.questionnaire_versions
      where id = old.questionnaire_version_id;
    else
      select status
      into parent_status
      from public.questionnaire_versions
      where id = new.questionnaire_version_id;
    end if;
  else
    if tg_op = 'DELETE' then
      parent_question_id := old.questionnaire_question_id;
    else
      parent_question_id := new.questionnaire_question_id;
    end if;

    select version_row.status
    into parent_status
    from public.questionnaire_questions question_row
    join public.questionnaire_versions version_row
      on version_row.id = question_row.questionnaire_version_id
    where question_row.id = parent_question_id;
  end if;

  if parent_status in ('published', 'retired') then
    raise exception using
      errcode = '55000',
      message = 'published questionnaire content is immutable';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

--
-- Name: soolgyul_guard_questionnaire_version(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_guard_questionnaire_version() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception using
        errcode = '55000',
        message = 'questionnaire versions must be created as draft';
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old.status in ('published', 'retired') then
      raise exception using
        errcode = '55000',
        message = 'published questionnaire version is immutable';
    end if;
    return old;
  end if;

  if old.status = 'retired' then
    raise exception using
      errcode = '55000',
      message = 'published questionnaire version is immutable';
  end if;

  if old.status = 'published' then
    if new.status = 'retired'
      and new.id is not distinct from old.id
      and new.version_key is not distinct from old.version_key
      and new.title is not distinct from old.title
      and new.published_at is not distinct from old.published_at
      and new.created_at is not distinct from old.created_at
      and new.supersedes_version_id is not distinct from old.supersedes_version_id
    then
      return new;
    end if;

    raise exception using
      errcode = '55000',
      message = 'published questionnaire version is immutable';
  end if;

  return new;
end;
$$;

--
-- Name: soolgyul_guard_taste_card_content(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_guard_taste_card_content() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if old.snapshot_id is null then return new; end if;
  if new is not distinct from old then return new; end if;
  if old.lifecycle='final' and new.lifecycle in ('withdrawn','superseded')
    and (to_jsonb(new)-'lifecycle'-'withdrawal_reason_code'-'withdrawn_at') =
        (to_jsonb(old)-'lifecycle'-'withdrawal_reason_code'-'withdrawn_at') then return new; end if;
  raise exception using errcode='55000',message='Final taste card content is immutable';
end;
$$;

--
-- Name: soolgyul_invalidate_deletion_revocation_on_login(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_invalidate_deletion_revocation_on_login() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
 if new.last_sign_in_at is distinct from old.last_sign_in_at then
  update public.users set deletion_provider_revoked_at=null
   where id=new.id and deletion_scheduled_at is not null and purged_at is null;
 end if;
 return new;
end; $$;

--
-- Name: soolgyul_lower_catalog_text_array(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_lower_catalog_text_array(values_to_normalize text[]) RETURNS text[]
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO 'pg_catalog'
    AS $$
  select coalesce(
    array_agg(lower(trim(source.value)) order by source.ordinality),
    array[]::text[]
  )
  from unnest(coalesce(values_to_normalize, array[]::text[]))
    with ordinality as source(value, ordinality)
  where trim(source.value) <> '';
$$;

--
-- Name: soolgyul_mark_deletion_provider_revoked(uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_mark_deletion_provider_revoked(target_user_id uuid, requested_at timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
 update public.users set deletion_provider_revoked_at=statement_timestamp()
 where id=target_user_id and deletion_requested_at=requested_at and deletion_scheduled_at is not null
   and purged_at is null;
 return found;
end; $$;

--
-- Name: soolgyul_mark_deletion_provider_revoked_v2(uuid, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_mark_deletion_provider_revoked_v2(target_user_id uuid, requested_at timestamp with time zone, authenticated_at timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
 -- Same lock order as the Auth login trigger: Auth row, then product row.
 perform 1 from auth.users where id=target_user_id and last_sign_in_at=authenticated_at for share;
 if not found then return false; end if;
 update public.users set deletion_provider_revoked_at=statement_timestamp()
 where id=target_user_id and deletion_requested_at=requested_at and deletion_scheduled_at is not null
   and purged_at is null;
 return found;
end; $$;

--
-- Name: soolgyul_normalize_catalog_text(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_normalize_catalog_text(input_value text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO ''
    AS $$
  select lower(
    normalize(
      regexp_replace(
        btrim(coalesce(input_value, '')),
        '[[:space:]]+',
        ' ',
        'g'
      ),
      NFC
    )
  )
$$;

--
-- Name: soolgyul_prepare_admin_editorial_article(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_prepare_admin_editorial_article() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare
  actor_id uuid := (select auth.uid());
begin
  if actor_id is not null then
    if tg_op = 'INSERT' then
      new.created_by := actor_id;
    end if;
    new.updated_by := actor_id;

    if new.status = 'published'
       and (
         tg_op = 'INSERT'
         or old.status is distinct from 'published'
         or new.published_at is null
       ) then
      if tg_op = 'UPDATE' and old.status is distinct from 'published' then
        new.published_at := now();
      else
        new.published_at := coalesce(new.published_at, now());
      end if;
      new.published_by := actor_id;
    end if;
  end if;

  return new;
end
$$;

--
-- Name: soolgyul_prevent_populated_tasting_profile_retargeting(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_prevent_populated_tasting_profile_retargeting() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if new.alcohol_item_id is not distinct from old.alcohol_item_id
  then
    return new;
  end if;

  if old.publish_status <> 'staging'
    or new.publish_status <> 'staging'
    or num_nonnulls(
      nullif(btrim(old.overall_note), ''),
      nullif(btrim(old.aroma_note), ''),
      nullif(btrim(old.palate_note), ''),
      nullif(btrim(old.finish_note), ''),
      nullif(btrim(old.texture_note), ''),
      nullif(btrim(old.body_note), ''),
      old.sweetness,
      old.acidity,
      old.bitterness,
      old.umami,
      old.saltiness,
      old.astringency,
      old.body,
      old.viscosity,
      old.carbonation,
      old.alcohol_presence,
      old.aroma_intensity,
      old.flavour_clarity,
      old.finish_length,
      old.finish_cleanliness
    ) > 0
    or cardinality(old.aroma_tags || old.palate_tags || old.texture_tags || old.finish_tags) > 0
  then
    raise exception 'reviewed or populated tasting profile target is immutable; create a replacement profile'
      using errcode = '23514';
  end if;
  return new;
end
$$;

--
-- Name: soolgyul_prevent_served_item_category_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_prevent_served_item_category_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if new.alcohol_category_id is not distinct from old.alcohol_category_id then
    return new;
  end if;
  if exists (
    select 1 from public.alcohol_tasting_profiles profile
    where profile.alcohol_item_id = old.id
    union all
    select 1 from public.catalog_media_assets media
    where media.alcohol_item_id = old.id
  ) then
    raise exception 'alcohol item category is immutable while serving content exists'
      using errcode = '23514';
  end if;
  return new;
end
$$;

--
-- Name: soolgyul_protect_catalog_term_identity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_protect_catalog_term_identity() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if tg_op = 'DELETE' then
    raise exception
      'catalog terms are append-only; set is_active=false instead of deleting'
      using errcode = '23514';
  end if;

  if new.term_type is distinct from old.term_type
    or new.term_key is distinct from old.term_key
  then
    raise exception
      'catalog term identity is immutable; create a new key and deactivate the old term'
      using errcode = '23514';
  end if;

  return new;
end
$$;

--
-- Name: soolgyul_provision_auth_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_provision_auth_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  resolved_provider text;
  trusted_provider_user_id text;
begin
  if lower(coalesce(new.raw_app_meta_data ->> 'provider', '')) = 'email'
     and lower(coalesce(new.raw_user_meta_data ->> 'soolgyul_test_user', '')) = 'true'
  then
    resolved_provider := 'test';
  else
    resolved_provider := lower(
      coalesce(new.raw_app_meta_data ->> 'provider', '')
    );
  end if;

  if resolved_provider not in ('kakao', 'apple', 'google', 'test') then
    return new;
  end if;

  trusted_provider_user_id := new.id::text;
  if exists (
    select 1
    from public.users product_user
    where product_user.auth_provider = resolved_provider
      and product_user.provider_user_id = trusted_provider_user_id
      and product_user.id <> new.id
  ) then
    raise exception using
      errcode = '23505',
      message = 'trusted_auth_identity_conflict';
  end if;

  begin
    insert into public.users (
      id,
      auth_provider,
      provider_user_id,
      email,
      created_at,
      last_sign_in_at
    ) values (
      new.id,
      resolved_provider,
      trusted_provider_user_id,
      new.email,
      coalesce(new.created_at, now()),
      new.last_sign_in_at
    )
    on conflict (id) do update
    set auth_provider = excluded.auth_provider,
        provider_user_id = excluded.provider_user_id,
        email = excluded.email,
        last_sign_in_at = excluded.last_sign_in_at;
  exception
    when unique_violation then
      raise exception using
        errcode = '23505',
        message = 'trusted_auth_identity_conflict';
  end;

  

  return new;
end
$$;

--
-- Name: soolgyul_related_editorial_articles(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_related_editorial_articles(p_article_id uuid, p_result_limit integer DEFAULT 10) RETURNS TABLE(article_id uuid, relevance_score integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  with source_article as (
    select article.id, article.category_id
    from public.editorial_articles article
    where article.id = p_article_id
      and article.status = 'published'
  ),
  source_interests as (
    select link.alcohol_interest_group_id
    from public.editorial_article_interest_groups link
    join source_article source on source.id = link.article_id
  ),
  viewer_interests as (
    select selection.alcohol_interest_group_id
    from public.user_drink_interests selection
    where auth.uid() is not null
      and selection.user_id = auth.uid()
  ),
  scored_candidates as (
    select
      candidate.id as article_id,
      (
        case when candidate.category_id = source.category_id then 10 else 0 end
        + 5 * (
          select count(*)::integer
          from public.editorial_article_interest_groups candidate_link
          join source_interests source_interest
            on source_interest.alcohol_interest_group_id =
              candidate_link.alcohol_interest_group_id
          where candidate_link.article_id = candidate.id
        )
        + 2 * (
          select count(*)::integer
          from public.editorial_article_interest_groups candidate_link
          join viewer_interests viewer_interest
            on viewer_interest.alcohol_interest_group_id =
              candidate_link.alcohol_interest_group_id
          where candidate_link.article_id = candidate.id
        )
      )::integer as relevance_score
    from public.editorial_articles candidate
    cross join source_article source
    where candidate.status = 'published'
      and candidate.id <> source.id
  )
  select candidate.article_id, candidate.relevance_score
  from scored_candidates candidate
  order by
    candidate.relevance_score desc,
    md5(p_article_id::text || ':' || candidate.article_id::text)
  limit least(greatest(coalesce(p_result_limit, 10), 1), 10)
$$;

--
-- Name: FUNCTION soolgyul_related_editorial_articles(p_article_id uuid, p_result_limit integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_related_editorial_articles(p_article_id uuid, p_result_limit integer) IS 'Returns at most ten published related article IDs. Category and source/viewer interest overlap determine relevance; a stable ID hash breaks ties without freshness bias.';

--
-- Name: soolgyul_replace_my_drink_interests(text[], uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_replace_my_drink_interests(p_interest_group_keys text[], p_idempotency_key uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  target_user_id uuid;
  normalized_interest_keys text[];
  response_payload jsonb;
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'idempotency_key_required';
  end if;
  if p_interest_group_keys is null
    or cardinality(p_interest_group_keys) < 1
    or cardinality(p_interest_group_keys) > 5
  then
    raise exception using errcode = '22023', message = 'drink_interest_count_invalid';
  end if;
  if array_position(p_interest_group_keys, null) is not null
    or (
      select count(distinct interest_key)
      from unnest(p_interest_group_keys) interest_key
    ) <> cardinality(p_interest_group_keys)
  then
    raise exception using errcode = '22023', message = 'drink_interest_keys_invalid';
  end if;

  select array_agg(
    interest_group.interest_group_key
    order by interest_group.sort_order, interest_group.interest_group_key
  )
  into normalized_interest_keys
  from public.alcohol_interest_groups interest_group
  where interest_group.is_active
    and interest_group.interest_group_key = any(p_interest_group_keys);

  if cardinality(coalesce(normalized_interest_keys, array[]::text[]))
    <> cardinality(p_interest_group_keys)
  then
    raise exception using errcode = '22023', message = 'drink_interest_keys_invalid';
  end if;

  perform 1
  from public.users product_user
  where product_user.id = target_user_id
    and product_user.disabled_at is null
    and product_user.deletion_requested_at is null
    and product_user.deletion_scheduled_at is null
    and product_user.purged_at is null
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  delete from public.user_drink_interests selection
  where selection.user_id = target_user_id
    and not exists (
      select 1
      from public.alcohol_interest_groups interest_group
      where interest_group.id = selection.alcohol_interest_group_id
        and interest_group.interest_group_key = any(normalized_interest_keys)
    );

  insert into public.user_drink_interests (
    user_id,
    alcohol_interest_group_id
  )
  select target_user_id, interest_group.id
  from public.alcohol_interest_groups interest_group
  where interest_group.interest_group_key = any(normalized_interest_keys)
    and not exists (
      select 1
      from public.user_drink_interests current_selection
      where current_selection.user_id = target_user_id
        and current_selection.alcohol_interest_group_id = interest_group.id
    )
  order by interest_group.sort_order, interest_group.interest_group_key;

  response_payload := jsonb_build_object(
    'interest_group_keys', to_jsonb(normalized_interest_keys)
  );

  return response_payload;
end
$$;

--
-- Name: FUNCTION soolgyul_replace_my_drink_interests(p_interest_group_keys text[], p_idempotency_key uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_replace_my_drink_interests(p_interest_group_keys text[], p_idempotency_key uuid) IS 'Owner-locked atomic desired-state replacement; no separate request ledger.';

--
-- Name: soolgyul_request_my_account_deletion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_request_my_account_deletion() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare u public.users%rowtype;
begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 select * into u from public.users where id=auth.uid() for update;
 if not found or u.disabled_at is not null or u.purged_at is not null then
  raise exception 'active_account_required'; end if;
 if u.deletion_scheduled_at is null then
  update public.users set deletion_requested_at=statement_timestamp(),
   deletion_scheduled_at=statement_timestamp()+interval '30 days',
   deletion_provider_revoked_at=null where id=u.id;
 end if;
 return public.soolgyul_get_my_deletion_state();
end; $$;

--
-- Name: soolgyul_restore_my_account(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_restore_my_account() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare u public.users%rowtype;
begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 select * into u from public.users where id=auth.uid() for update;
 if not found or u.disabled_at is not null or u.purged_at is not null then
  raise exception 'account_restore_unavailable'; end if;
 if u.deletion_scheduled_at is not null and u.deletion_scheduled_at<=statement_timestamp() then
  raise exception 'restore_window_closed'; end if;
 update public.users set deletion_requested_at=null,deletion_scheduled_at=null,
  deletion_provider_revoked_at=null where id=u.id;
 -- Never alter record.deleted_at or other user content.
 return public.soolgyul_get_my_deletion_state();
end; $$;

--
-- Name: soolgyul_run_account_retention_job(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_run_account_retention_job() RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare token text; request_id bigint;
begin
 select decrypted_secret into token from vault.decrypted_secrets
 where name='account_retention_job_secret';
 if token is null then raise exception 'retention_scheduler_secret_missing'; end if;
 select net.http_post(
  url:='https://naukrykbswfeecxerueq.supabase.co/functions/v1/account-retention-purge',
  headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||token),
  body:='{}'::jsonb,timeout_milliseconds:=120000) into request_id;
 return request_id;
end; $$;

--
-- Name: soolgyul_search_alcohol_catalog(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer DEFAULT 20) RETURNS TABLE(id uuid, name_ko text, name_en text, category_key text, style_key text, abv_percent numeric)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
  with search_input as (
    select
      lower(regexp_replace(trim(coalesce(target_query, '')), '\s+', ' ', 'g'))
        as query,
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
      case
        when lower(item.name_ko) = input.query
          or lower(item.name_en) = input.query then 0
        when lower(item.name_ko) like input.query || '%'
          or lower(item.name_en) like input.query || '%' then 1
        when public.soolgyul_lower_catalog_text_array(item.aliases)
            @> array[input.query]
          or public.soolgyul_lower_catalog_text_array(item.search_keywords)
            @> array[input.query] then 2
        else 3
      end as match_rank,
      input.result_limit
    from public.alcohol_items as item
    join public.alcohol_categories as category
      on category.id = item.alcohol_category_id
     and category.is_active
    cross join search_input as input
    where item.publish_status = 'published'
      and char_length(input.query) between 1 and 100
      and (
        lower(item.name_ko) like '%' || input.query || '%'
        or (
          item.name_en is not null
          and lower(item.name_en) like '%' || input.query || '%'
        )
        or public.soolgyul_lower_catalog_text_array(item.aliases)
          @> array[input.query]
        or public.soolgyul_lower_catalog_text_array(item.search_keywords)
          @> array[input.query]
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

--
-- Name: FUNCTION soolgyul_search_alcohol_catalog(target_query text, target_limit integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer) IS 'Searches active published alcohol products with indexed partial canonical names and indexed normalized exact aliases or keywords.';

--
-- Name: soolgyul_sensory_knowledge_is_valid(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_sensory_knowledge_is_valid(value jsonb) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO ''
    AS $$
select coalesce(case
  when jsonb_typeof(value->'sensory_description') = 'string'
   and jsonb_typeof(value->'sensory_trait_keys') = 'array'
  then length(value->>'sensory_description') between 1 and 600
   and value->>'sensory_description' = btrim(value->>'sensory_description')
   and value->>'sensory_description' = normalize(value->>'sensory_description', NFC)
   and value->>'sensory_description' !~ '[[:cntrl:]]'
   and jsonb_array_length(value->'sensory_trait_keys') <= 8
   and not exists (
     select 1 from jsonb_array_elements(value->'sensory_trait_keys') t(v)
     where jsonb_typeof(v) <> 'string' or (v #>> '{}') not in ('animalic_scent', 'astringent_touch', 'balanced_impression', 'bubble_touch', 'burning', 'clean_ending', 'concentrated_scent', 'cooling_scent', 'dairy_scent', 'dry_ending', 'earthy_scent', 'elastic_texture', 'fermented_scent', 'fine_bubbles', 'floral_scent', 'foam_texture', 'fresh_scent', 'fruit_scent', 'full_volume', 'grain_scent', 'green_scent', 'herbal_scent', 'lactic_scent', 'layered_impression', 'light_volume', 'mouth_coating', 'mouth_drying', 'mouth_gripping', 'nutty_scent', 'prickly_bubbles', 'refreshing_ending', 'resinous_scent', 'savory_scent', 'sharp_scent', 'smoky_scent', 'spice_scent', 'stimulating_touch', 'surface_rough', 'surface_smooth', 'sweet_scent', 'tactile_prickle', 'thick_consistency', 'thin_consistency', 'toasted_scent', 'vegetal_scent', 'warm_scent', 'warming', 'waxy_scent', 'woody_scent')
   )
   and (select count(*) = count(distinct v)
        from jsonb_array_elements(value->'sensory_trait_keys') t(v))
  else false end, false);
$$;

--
-- Name: soolgyul_set_marketing_consent(boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_set_marketing_consent(p_accepted boolean) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare target uuid := auth.uid(); changed_at timestamptz;
begin
  if target is null then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;
  perform 1 from public.users where id = target for update;
  if not public.soolgyul_account_active(target) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;
  if p_accepted is null then
    raise exception using errcode = '22023', message = 'consent_value_required';
  end if;
  changed_at := clock_timestamp();
  if p_accepted then
    if not public.soolgyul_get_marketing_consent() then
      insert into public.user_consents(user_id,consent_type,document_version,accepted_at)
      values(target,'marketing','soolgyul-marketing-v1',changed_at);
    end if;
  else
    update public.user_consents set withdrawn_at = changed_at
      where user_id = target and consent_type = 'marketing' and withdrawn_at is null;
  end if;
  return public.soolgyul_get_marketing_consent();
end;
$$;

--
-- Name: soolgyul_strip_retained_card_links(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_strip_retained_card_links(value jsonb) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
declare result jsonb; entry record;
begin
  if value is null then return null; end if;
  if jsonb_typeof(value) = 'object' then
    if value->>'source' = 'user_photo' then return 'null'::jsonb; end if;
    result := '{}'::jsonb;
    for entry in select * from jsonb_each(value) loop
      if entry.key = any(array[
        'user_id','owner_user_id','user_name','display_name','email',
        'provider_user_id','birth_date','anonymous_session_id','anonymous_session_digest',
        'photo_asset_id','photo_storage_path','private_storage_path','signed_url',
        'conversion_token','conversion_key_version','attempt_ref','idempotency_key',
        'record_id','drink_record_id','generated_from_record_ref','snapshot_ref',
        'snapshot_id','canonical_input_digest','request_digest'
      ]) then continue; end if;
      result := result || jsonb_build_object(entry.key,
        public.soolgyul_strip_retained_card_links(entry.value));
    end loop;
    return result;
  elsif jsonb_typeof(value) = 'array' then
    select coalesce(jsonb_agg(public.soolgyul_strip_retained_card_links(v) order by n),'[]'::jsonb)
      into result from jsonb_array_elements(value) with ordinality a(v,n);
    return result;
  end if;
  return value;
end;
$$;

--
-- Name: soolgyul_submit_support_inquiry(uuid, text, text, text, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_submit_support_inquiry(p_id uuid, p_inquiry_type text, p_reply_email text, p_content text, p_attachment_paths text[] DEFAULT '{}'::text[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  owner_id uuid := auth.uid();
  existing public.support_inquiries%rowtype;
  attachment text;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  -- Serialize submissions for this user, including retries and rate checks.
  perform 1 from public.users where id = owner_id for update;
  if not found or not coalesce(public.soolgyul_account_active(owner_id), false) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;
  select * into existing from public.support_inquiries where id = p_id;
  if found then
    if existing.user_id = owner_id
      and existing.inquiry_type = p_inquiry_type
      and existing.reply_email = btrim(p_reply_email)
      and existing.content = btrim(p_content)
      and existing.attachment_paths = p_attachment_paths then
      return existing.id;
    end if;
    raise exception 'inquiry_request_conflict' using errcode = '22023';
  end if;
  if p_id is null or p_attachment_paths is null
    or cardinality(p_attachment_paths) > 5
    or array_position(p_attachment_paths, null) is not null then
    raise exception 'invalid_inquiry_attachments' using errcode = '22023';
  end if;
  if (select count(*) from public.support_inquiries
      where user_id = owner_id and created_at >= now() - interval '1 hour') >= 10 then
    raise exception 'inquiry_rate_limited' using errcode = 'P0001';
  end if;
  foreach attachment in array p_attachment_paths loop
    if attachment !~ ('^' || owner_id::text || '/inquiries/' || p_id::text ||
        '/[0-4]-[0-9a-f]{64}[.](jpg|png|webp)$')
      or not exists (
        select 1 from storage.objects o
        where o.bucket_id = 'soolgyul-private' and o.name = attachment
          and o.metadata->>'mimetype' in ('image/jpeg', 'image/png', 'image/webp')
          and (o.metadata->>'size')::bigint between 1 and 10485760
      ) then
      raise exception 'invalid_inquiry_attachment' using errcode = '22023';
    end if;
  end loop;
  insert into public.support_inquiries
    (id, user_id, inquiry_type, reply_email, content, attachment_paths)
  values (p_id, owner_id, p_inquiry_type, btrim(p_reply_email), btrim(p_content), p_attachment_paths);
  return p_id;
end;
$_$;

--
-- Name: soolgyul_touch_editorial_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_touch_editorial_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  new.updated_at = now();
  return new;
end
$$;

--
-- Name: soolgyul_update_my_display_name(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_update_my_display_name(p_display_name text, p_idempotency_key uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  target_user_id uuid;
  normalized_display_name text;
  response_payload jsonb;
begin
  target_user_id := auth.uid();
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'idempotency_key_required';
  end if;

  normalized_display_name := btrim(coalesce(p_display_name, ''));
  if char_length(normalized_display_name) < 2
    or char_length(normalized_display_name) > 12
    or normalized_display_name !~ '^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ]+$'
  then
    raise exception using errcode = '22023', message = 'display_name_invalid';
  end if;

  perform 1
  from public.users product_user
  where product_user.id = target_user_id
    and product_user.disabled_at is null
    and product_user.deletion_requested_at is null
    and product_user.deletion_scheduled_at is null
    and product_user.purged_at is null
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  if not exists (
    select 1
    from public.users profile
    where profile.id = target_user_id
  ) then
    raise exception using errcode = 'P0002', message = 'profile_not_found';
  end if;

  update public.users profile
  set display_name = normalized_display_name,
      updated_at = now()
  where profile.id = target_user_id
    and profile.display_name is distinct from normalized_display_name;

  response_payload := jsonb_build_object('display_name', normalized_display_name);

  return response_payload;
end
$_$;

--
-- Name: FUNCTION soolgyul_update_my_display_name(p_display_name text, p_idempotency_key uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_update_my_display_name(p_display_name text, p_idempotency_key uuid) IS 'Owner-locked desired-state update. Legacy UUID is accepted for wire compatibility, not replay history.';

--
-- Name: soolgyul_validate_active_alcohol_category_assignment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_validate_active_alcohol_category_assignment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if tg_op = 'UPDATE'
    and new.alcohol_category_id is not distinct from old.alcohol_category_id
  then
    return new;
  end if;

  if not exists (
    select 1
    from public.alcohol_categories category
    where category.id = new.alcohol_category_id
      and category.is_active
  ) then
    raise exception 'new alcohol item assignments require an active alcohol category'
      using errcode = '23514';
  end if;
  return new;
end
$$;

--
-- Name: soolgyul_validate_alcohol_item_catalog_terms(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_validate_alcohol_item_catalog_terms() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if tg_op = 'INSERT'
    or new.classification_keys is distinct from old.classification_keys
  then
    if not public.soolgyul_catalog_term_keys_are_active(
      new.classification_keys,
      array['classification'],
      array['classification']
    ) then
      raise exception 'classification_keys require active classification terms'
        using errcode = '23514';
    end if;
  end if;

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

  return new;
end
$$;

--
-- Name: soolgyul_validate_tasting_profile_catalog_terms(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_validate_tasting_profile_catalog_terms() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if tg_op = 'INSERT' or new.aroma_tags is distinct from old.aroma_tags then
    if not public.soolgyul_catalog_term_keys_are_active(
      new.aroma_tags, array['sensory_descriptor'], array['aroma']
    ) then
      raise exception 'aroma_tags require active aroma sensory terms'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT' or new.palate_tags is distinct from old.palate_tags then
    if not public.soolgyul_catalog_term_keys_are_active(
      new.palate_tags, array['sensory_descriptor'], array['palate']
    ) then
      raise exception 'palate_tags require active palate sensory terms'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT' or new.finish_tags is distinct from old.finish_tags then
    if not public.soolgyul_catalog_term_keys_are_active(
      new.finish_tags, array['sensory_descriptor'], array['finish']
    ) then
      raise exception 'finish_tags require active finish sensory terms'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT' or new.texture_tags is distinct from old.texture_tags then
    if not public.soolgyul_catalog_term_keys_are_active(
      new.texture_tags, array['sensory_descriptor'], array['texture']
    ) then
      raise exception 'texture_tags require active texture sensory terms'
        using errcode = '23514';
    end if;
  end if;

  return new;
end
$$;

--
-- Name: admin_user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_user_roles (
    user_id uuid NOT NULL,
    role text NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    granted_by uuid,
    CONSTRAINT admin_user_roles_role_check CHECK ((role = ANY (ARRAY['editor'::text, 'admin'::text])))
);

--
-- Name: TABLE admin_user_roles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.admin_user_roles IS 'Backend-owned access grants for the separate Soolgyul administrator web app. Clients may read only their own grant and cannot mutate grants.';

--
-- Name: alcohol_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alcohol_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    category_key text NOT NULL,
    name_ko text NOT NULL,
    name_en text,
    sort_order integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT alcohol_categories_category_key_check CHECK ((category_key ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_categories_name_ko_check CHECK ((btrim(name_ko) <> ''::text)),
    CONSTRAINT alcohol_categories_sort_order_check CHECK ((sort_order >= 0))
);

--
-- Name: alcohol_interest_group_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alcohol_interest_group_categories (
    alcohol_interest_group_id uuid NOT NULL,
    alcohol_category_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE alcohol_interest_group_categories; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.alcohol_interest_group_categories IS 'Maps presentation interest groups to canonical catalog categories. The other group intentionally maps to both other fermented and other distilled categories.';

--
-- Name: alcohol_interest_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alcohol_interest_groups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    interest_group_key text NOT NULL,
    name_ko text NOT NULL,
    name_en text,
    sort_order integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT alcohol_interest_groups_interest_group_key_check CHECK ((interest_group_key ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_interest_groups_name_ko_check CHECK ((btrim(name_ko) <> ''::text)),
    CONSTRAINT alcohol_interest_groups_sort_order_check CHECK ((sort_order >= 0))
);

--
-- Name: TABLE alcohol_interest_groups; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.alcohol_interest_groups IS 'Stable user-facing alcohol interest groups. These keys are presentation preferences, not canonical product categories.';

--
-- Name: alcohol_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alcohol_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name_ko text NOT NULL,
    name_en text,
    aliases text[] DEFAULT '{}'::text[] NOT NULL,
    region text,
    search_keywords text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    alcohol_category_id uuid NOT NULL,
    country_code text,
    abv_percent numeric(5,2),
    style_key text,
    publish_status text DEFAULT 'staging'::text NOT NULL,
    published_at timestamp with time zone,
    classification_keys text[] DEFAULT ARRAY[]::text[] NOT NULL,
    ingredient_keys text[] DEFAULT ARRAY[]::text[] NOT NULL,
    production_process_keys text[] DEFAULT ARRAY[]::text[] NOT NULL,
    representative_volume_ml integer,
    product_group_id uuid,
    vintage_year integer,
    age_statement_years numeric,
    edition_text text,
    batch_text text,
    CONSTRAINT alcohol_items_abv_percent_check CHECK (((abv_percent IS NULL) OR ((abv_percent >= (0)::numeric) AND (abv_percent <= (100)::numeric)))),
    CONSTRAINT alcohol_items_age_statement_years_check CHECK ((age_statement_years > (0)::numeric)),
    CONSTRAINT alcohol_items_aliases_check CHECK (public.soolgyul_catalog_text_array_is_valid(aliases, 50)),
    CONSTRAINT alcohol_items_classification_keys_check CHECK (public.soolgyul_catalog_text_array_is_valid(classification_keys, 64, '^[a-z][a-z0-9_]*(:[a-z][a-z0-9_]*)?$'::text)),
    CONSTRAINT alcohol_items_country_code_check CHECK (((country_code IS NULL) OR (country_code ~ '^[A-Z]{2}$'::text))),
    CONSTRAINT alcohol_items_ingredient_keys_check CHECK (public.soolgyul_catalog_text_array_is_valid(ingredient_keys, 64, '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_items_production_process_keys_check CHECK (public.soolgyul_catalog_text_array_is_valid(production_process_keys, 64, '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_items_publish_gate_check CHECK (((publish_status <> 'published'::text) OR (published_at IS NOT NULL))),
    CONSTRAINT alcohol_items_publish_status_check CHECK ((publish_status = ANY (ARRAY['staging'::text, 'published'::text, 'withdrawn'::text]))),
    CONSTRAINT alcohol_items_representative_volume_ml_check CHECK (((representative_volume_ml IS NULL) OR ((representative_volume_ml >= 1) AND (representative_volume_ml <= 200000)))),
    CONSTRAINT alcohol_items_search_keywords_check CHECK (public.soolgyul_catalog_text_array_is_valid(search_keywords, 100)),
    CONSTRAINT alcohol_items_style_key_check CHECK (((style_key IS NULL) OR (style_key ~ '^[a-z][a-z0-9_]*$'::text))),
    CONSTRAINT alcohol_items_vintage_year_check CHECK (((vintage_year >= 1000) AND (vintage_year <= 2200)))
);

--
-- Name: TABLE alcohol_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.alcohol_items IS 'Single product identity, including explicit vintage, strength, age and batch variants. product_group_id groups related products without inheriting sensory facts.';

--
-- Name: COLUMN alcohol_items.aliases; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_items.aliases IS 'Search-safe aliases only. Commercial packaging, gift, set, and multipack noise remains in repository source snapshots, not serving aliases.';

--
-- Name: COLUMN alcohol_items.search_keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_items.search_keywords IS 'Canonical additional search terms projected from the repository catalog source.';

--
-- Name: COLUMN alcohol_items.representative_volume_ml; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_items.representative_volume_ml IS 'Optional display aid selected from observed packages. Volume does not participate in alcohol product identity.';

--
-- Name: catalog_media_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_media_assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    alcohol_item_id uuid NOT NULL,
    storage_bucket text NOT NULL,
    storage_object_path text NOT NULL,
    media_type text NOT NULL,
    width integer NOT NULL,
    height integer NOT NULL,
    alt_text text,
    attribution_text text,
    publish_status text DEFAULT 'staging'::text NOT NULL,
    published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT catalog_media_assets_height_check CHECK ((height > 0)),
    CONSTRAINT catalog_media_assets_media_type_check CHECK ((media_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text]))),
    CONSTRAINT catalog_media_assets_public_storage_check CHECK (((publish_status <> 'published'::text) OR ((storage_bucket = 'alcohol-product-images'::text) AND (published_at IS NOT NULL)))),
    CONSTRAINT catalog_media_assets_publish_status_check CHECK ((publish_status = ANY (ARRAY['staging'::text, 'published'::text, 'archived'::text]))),
    CONSTRAINT catalog_media_assets_storage_bucket_check CHECK ((storage_bucket = ANY (ARRAY['soolgyul-catalog-private'::text, 'alcohol-product-images'::text]))),
    CONSTRAINT catalog_media_assets_storage_object_path_check CHECK ((btrim(storage_object_path) <> ''::text)),
    CONSTRAINT catalog_media_assets_width_check CHECK ((width > 0))
);

--
-- Name: TABLE catalog_media_assets; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.catalog_media_assets IS 'Service catalog images with product links, storage metadata and publication state.';

--
-- Name: catalog_media_fallbacks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_media_fallbacks (
    alcohol_item_id uuid NOT NULL,
    source_catalog_media_asset_id uuid NOT NULL,
    fallback_basis text DEFAULT 'product_group_representative'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT catalog_media_fallbacks_fallback_basis_check CHECK ((fallback_basis = 'product_group_representative'::text))
);

--
-- Name: TABLE catalog_media_fallbacks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.catalog_media_fallbacks IS 'Explicit product-group representative image fallback. Exact product media always wins in the serving projection.';

--
-- Name: catalog_search_projection_v1; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.catalog_search_projection_v1 WITH (security_invoker='true', security_barrier='true') AS
 SELECT search_row.alcohol_item_id,
    search_row.alcohol_release_id,
    search_row.display_name,
    search_row.secondary_name,
    search_row.producer_or_brand_display,
    search_row.category_key,
    search_row.subcategory_key,
    search_row.style_key,
    search_row.country_code,
    search_row.region_display,
    search_row.abv_percent,
    search_row.search_aliases,
    search_row.descriptor_keys,
    search_row.is_active,
    search_row.published_at,
    search_row.updated_at,
    media.catalog_media_asset_id AS primary_image_asset_id,
    media.storage_object_path AS primary_image_object_path,
    media.alt_text AS primary_image_alt_text,
    media.width AS primary_image_width,
    media.height AS primary_image_height
   FROM (public.soolgyul_catalog_search_projection_rows_v1() search_row(alcohol_item_id, alcohol_release_id, display_name, secondary_name, producer_or_brand_display, category_key, subcategory_key, style_key, country_code, region_display, abv_percent, search_aliases, descriptor_keys, is_active, published_at, updated_at)
     LEFT JOIN public.soolgyul_catalog_primary_media_rows_v1() media(catalog_media_asset_id, alcohol_item_id, alcohol_release_id, storage_object_path, alt_text, width, height, sort_order) ON ((media.alcohol_item_id = search_row.alcohol_item_id)));

--
-- Name: catalog_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_terms (
    term_type text NOT NULL,
    term_key text NOT NULL,
    label_ko text NOT NULL,
    label_en text,
    synonyms text[] DEFAULT ARRAY[]::text[] NOT NULL,
    parent_term_key text,
    applicable_sections text[] NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    taxonomy_version text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    card_label_ko text,
    CONSTRAINT catalog_terms_applicable_sections_check CHECK (((cardinality(applicable_sections) > 0) AND public.soolgyul_catalog_text_array_is_valid(applicable_sections, 9, '^[a-z][a-z0-9_]*$'::text) AND (((term_type = 'classification'::text) AND (applicable_sections <@ ARRAY['classification'::text])) OR ((term_type = 'style'::text) AND (applicable_sections <@ ARRAY['style'::text])) OR ((term_type = 'ingredient'::text) AND (applicable_sections <@ ARRAY['ingredient'::text])) OR ((term_type = 'process'::text) AND (applicable_sections <@ ARRAY['production'::text])) OR ((term_type = 'maturation'::text) AND (applicable_sections <@ ARRAY['maturation'::text])) OR ((term_type = ANY (ARRAY['sensory_descriptor'::text, 'sensory_dimension'::text])) AND (applicable_sections <@ ARRAY['aroma'::text, 'palate'::text, 'finish'::text, 'texture'::text]))))),
    CONSTRAINT catalog_terms_card_label_check CHECK (((card_label_ko IS NULL) OR ((term_type = 'sensory_descriptor'::text) AND ((char_length(card_label_ko) >= 1) AND (char_length(card_label_ko) <= 80)) AND (card_label_ko = btrim(card_label_ko)) AND (card_label_ko !~ '[[:cntrl:]]'::text)))),
    CONSTRAINT catalog_terms_dimension_knowledge_check CHECK (((term_type <> 'sensory_dimension'::text) OR public.soolgyul_sensory_knowledge_is_valid(metadata))),
    CONSTRAINT catalog_terms_label_en_check CHECK (((label_en IS NULL) OR ((NULLIF(btrim(label_en), ''::text) IS NOT NULL) AND (label_en = btrim(label_en)) AND (label_en = NORMALIZE(label_en, NFC))))),
    CONSTRAINT catalog_terms_label_ko_check CHECK (((NULLIF(btrim(label_ko), ''::text) IS NOT NULL) AND (label_ko = btrim(label_ko)) AND (label_ko = NORMALIZE(label_ko, NFC)))),
    CONSTRAINT catalog_terms_metadata_check CHECK ((jsonb_typeof(metadata) = 'object'::text)),
    CONSTRAINT catalog_terms_parent_not_self_check CHECK (((parent_term_key IS NULL) OR (parent_term_key <> term_key))),
    CONSTRAINT catalog_terms_sensory_knowledge_check CHECK (((term_type <> 'sensory_descriptor'::text) OR (NOT is_active) OR public.soolgyul_sensory_knowledge_is_valid(metadata))),
    CONSTRAINT catalog_terms_sort_order_check CHECK ((sort_order >= 0)),
    CONSTRAINT catalog_terms_synonyms_check CHECK (public.soolgyul_catalog_text_array_is_valid(synonyms, 64)),
    CONSTRAINT catalog_terms_taxonomy_version_check CHECK (((taxonomy_version = btrim(taxonomy_version)) AND (taxonomy_version ~ '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$'::text))),
    CONSTRAINT catalog_terms_term_key_check CHECK ((((term_type = 'classification'::text) AND (term_key ~ '^[a-z][a-z0-9_]*:[a-z][a-z0-9_]*$'::text)) OR ((term_type <> 'classification'::text) AND (term_key ~ '^[a-z][a-z0-9_]*$'::text)))),
    CONSTRAINT catalog_terms_term_type_check CHECK ((term_type = ANY (ARRAY['classification'::text, 'style'::text, 'ingredient'::text, 'process'::text, 'maturation'::text, 'sensory_descriptor'::text, 'sensory_dimension'::text]))),
    CONSTRAINT catalog_terms_timestamps_check CHECK ((updated_at >= created_at))
);

--
-- Name: TABLE catalog_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.catalog_terms IS 'Service vocabulary registry. Repository taxonomy remains the source artifact; only active seeded terms may be assigned to serving arrays.';

--
-- Name: COLUMN catalog_terms.applicable_sections; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.catalog_terms.applicable_sections IS 'Allowed assignment sections within term_type; values are type-checked and never free-form at serving write time.';

--
-- Name: COLUMN catalog_terms.card_label_ko; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.catalog_terms.card_label_ko IS 'Optional taste-card display name. Questionnaire label_ko and term_key stay unchanged. Null falls back to label_ko.';

--
-- Name: drink_record_answers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drink_record_answers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    drink_record_id uuid NOT NULL,
    questionnaire_version_id uuid NOT NULL,
    question_key text NOT NULL,
    question_label_snapshot text NOT NULL,
    selected_option_keys text[] DEFAULT '{}'::text[] NOT NULL,
    selected_option_labels_snapshot text[] DEFAULT '{}'::text[] NOT NULL,
    free_text text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    questionnaire_question_id uuid,
    schema_version integer DEFAULT 1 NOT NULL,
    option_gap_reported boolean,
    feedback_text text,
    CONSTRAINT drink_record_answers_feedback_valid CHECK (((feedback_text IS NULL) OR ((option_gap_reported IS TRUE) AND ((char_length(feedback_text) >= 1) AND (char_length(feedback_text) <= 500)) AND (char_length(btrim(feedback_text)) > 0)))),
    CONSTRAINT drink_record_answers_schema_version_positive CHECK ((schema_version > 0))
);

--
-- Name: COLUMN drink_record_answers.question_label_snapshot; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drink_record_answers.question_label_snapshot IS 'Immutable label shown to the user when this answer was recorded.';

--
-- Name: COLUMN drink_record_answers.option_gap_reported; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drink_record_answers.option_gap_reported IS 'Improvement feedback only: null uncollected, false offered/not selected, true submitted missing-expression signal.';

--
-- Name: COLUMN drink_record_answers.feedback_text; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drink_record_answers.feedback_text IS 'Optional per-question improvement note, maximum 500 Unicode code points. Never input to taste-card interpretation or public card output. Shares answer ownership and deletion lifecycle.';

--
-- Name: drink_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drink_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    anonymous_session_id text,
    alcohol_item_id uuid,
    entered_alcohol_name text,
    category text,
    photo_storage_path text,
    one_line_note text,
    saved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    questionnaire_version_id uuid NOT NULL,
    identification_mode text NOT NULL,
    alcohol_name_snapshot text,
    idempotency_key text,
    schema_version integer DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT drink_records_category_check CHECK (((category IS NULL) OR (category = ANY (ARRAY['wine'::text, 'whisky'::text, 'brandy'::text, 'gin'::text, 'rum'::text, 'vodka'::text, 'agave_spirits'::text, 'liqueur'::text, 'sake'::text, 'shochu_awamori'::text, 'korean_traditional'::text, 'beer'::text, 'cider_perry'::text, 'chinese_spirits'::text, 'rtd'::text, 'other_fermented'::text, 'other_distilled'::text, 'highball_rtd_other_spirits'::text])))),
    CONSTRAINT drink_records_check CHECK (((user_id IS NOT NULL) OR (anonymous_session_id IS NOT NULL))),
    CONSTRAINT drink_records_identification_mode_check CHECK ((((identification_mode = 'catalog_match'::text) AND (alcohol_item_id IS NOT NULL) AND (entered_alcohol_name IS NULL)) OR ((identification_mode = 'direct_input'::text) AND (alcohol_item_id IS NULL) AND (NULLIF(btrim(entered_alcohol_name), ''::text) IS NOT NULL)) OR ((identification_mode = 'unknown'::text) AND (alcohol_item_id IS NULL) AND (entered_alcohol_name IS NULL)))),
    CONSTRAINT drink_records_schema_version_positive CHECK ((schema_version > 0))
);

--
-- Name: COLUMN drink_records.photo_storage_path; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.drink_records.photo_storage_path IS 'Nullable path in the private soolgyul storage bucket; it does not determine identification_mode.';

--
-- Name: editorial_article_interest_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.editorial_article_interest_groups (
    article_id uuid NOT NULL,
    alcohol_interest_group_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE editorial_article_interest_groups; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.editorial_article_interest_groups IS 'Many-to-many mapping from an editorial article to user-facing alcohol interest groups.';

--
-- Name: editorial_article_media_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.editorial_article_media_assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    article_id uuid NOT NULL,
    asset_role text NOT NULL,
    storage_bucket text NOT NULL,
    storage_object_path text NOT NULL,
    media_type text NOT NULL,
    width integer,
    height integer,
    alt_text text,
    caption text,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT editorial_article_media_assets_asset_role_check CHECK ((asset_role = ANY (ARRAY['cover'::text, 'content'::text]))),
    CONSTRAINT editorial_article_media_assets_height_check CHECK (((height IS NULL) OR (height > 0))),
    CONSTRAINT editorial_article_media_assets_media_type_check CHECK ((media_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text]))),
    CONSTRAINT editorial_article_media_assets_sort_order_check CHECK ((sort_order >= 0)),
    CONSTRAINT editorial_article_media_assets_storage_bucket_check CHECK ((btrim(storage_bucket) <> ''::text)),
    CONSTRAINT editorial_article_media_assets_storage_object_path_check CHECK ((btrim(storage_object_path) <> ''::text)),
    CONSTRAINT editorial_article_media_assets_width_check CHECK (((width IS NULL) OR (width > 0)))
);

--
-- Name: TABLE editorial_article_media_assets; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.editorial_article_media_assets IS 'Article-owned cover and inline images. flutter-assets is allowed only for bundled initial fixture content; managed content uses a public Supabase Storage bucket.';

--
-- Name: editorial_articles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.editorial_articles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    category_id uuid NOT NULL,
    slug text NOT NULL,
    title text NOT NULL,
    summary text NOT NULL,
    body_markdown text NOT NULL,
    tags text[] DEFAULT ARRAY[]::text[] NOT NULL,
    estimated_read_minutes integer NOT NULL,
    is_recommended boolean DEFAULT false NOT NULL,
    featured_rank integer,
    status text DEFAULT 'draft'::text NOT NULL,
    published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    published_by uuid,
    CONSTRAINT editorial_articles_body_markdown_check CHECK ((btrim(body_markdown) <> ''::text)),
    CONSTRAINT editorial_articles_check CHECK ((((status = 'published'::text) AND (published_at IS NOT NULL)) OR (status <> 'published'::text))),
    CONSTRAINT editorial_articles_estimated_read_minutes_check CHECK (((estimated_read_minutes >= 1) AND (estimated_read_minutes <= 120))),
    CONSTRAINT editorial_articles_featured_rank_check CHECK (((featured_rank IS NULL) OR (featured_rank >= 0))),
    CONSTRAINT editorial_articles_slug_check CHECK ((slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'::text)),
    CONSTRAINT editorial_articles_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text, 'withdrawn'::text]))),
    CONSTRAINT editorial_articles_summary_check CHECK ((btrim(summary) <> ''::text)),
    CONSTRAINT editorial_articles_tags_check CHECK (public.soolgyul_catalog_text_array_is_valid(tags, 16)),
    CONSTRAINT editorial_articles_title_check CHECK ((btrim(title) <> ''::text))
);

--
-- Name: TABLE editorial_articles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.editorial_articles IS 'Administrator-authored Soolgyul information articles. Markdown owns content structure while Flutter owns visual rendering.';

--
-- Name: COLUMN editorial_articles.body_markdown; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.editorial_articles.body_markdown IS 'Markdown body. Inline article media may be referenced with media://<editorial_article_media_assets.id>.';

--
-- Name: COLUMN editorial_articles.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.editorial_articles.status IS 'Published articles are publicly readable; withdrawn preserves publication history without serving the article.';

--
-- Name: COLUMN editorial_articles.created_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.editorial_articles.created_by IS 'Administrator account that created managed content. Initial migration fixtures remain null.';

--
-- Name: COLUMN editorial_articles.updated_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.editorial_articles.updated_by IS 'Last administrator account to change managed content.';

--
-- Name: COLUMN editorial_articles.published_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.editorial_articles.published_by IS 'Administrator account that most recently published the article.';

--
-- Name: editorial_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.editorial_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    category_key text NOT NULL,
    name_ko text NOT NULL,
    sort_order integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT editorial_categories_category_key_check CHECK ((category_key ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT editorial_categories_name_ko_check CHECK ((btrim(name_ko) <> ''::text)),
    CONSTRAINT editorial_categories_sort_order_check CHECK ((sort_order >= 0))
);

--
-- Name: TABLE editorial_categories; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.editorial_categories IS 'Service-managed editorial content categories such as beginner, drink story, and trend.';

--
-- Name: questionnaire_options; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.questionnaire_options (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    questionnaire_question_id uuid NOT NULL,
    option_key text NOT NULL,
    option_label text NOT NULL,
    option_order integer NOT NULL,
    option_group text,
    is_exclusive boolean DEFAULT false NOT NULL,
    scoring_hint jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: questionnaire_questions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.questionnaire_questions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    questionnaire_version_id uuid NOT NULL,
    question_key text NOT NULL,
    question_label text NOT NULL,
    screen_order integer NOT NULL,
    selection_rule text NOT NULL,
    max_select integer,
    unknown_option_exclusive boolean DEFAULT false NOT NULL,
    is_required boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT questionnaire_questions_selection_rule_check CHECK ((selection_rule = ANY (ARRAY['single'::text, 'multiple'::text, 'free_text'::text])))
);

--
-- Name: questionnaire_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.questionnaire_versions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    version_key text NOT NULL,
    status text NOT NULL,
    title text NOT NULL,
    published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    supersedes_version_id uuid,
    CONSTRAINT questionnaire_versions_published_at_check CHECK ((((status = 'draft'::text) AND (published_at IS NULL)) OR ((status = ANY (ARRAY['published'::text, 'retired'::text])) AND (published_at IS NOT NULL)))),
    CONSTRAINT questionnaire_versions_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text, 'retired'::text])))
);

--
-- Name: support_inquiries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.support_inquiries (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    inquiry_type text NOT NULL,
    reply_email text NOT NULL,
    content text NOT NULL,
    attachment_paths text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT support_inquiries_attachment_paths_check CHECK ((cardinality(attachment_paths) <= 5)),
    CONSTRAINT support_inquiries_content_check CHECK (((char_length(btrim(content)) >= 1) AND (char_length(btrim(content)) <= 1000))),
    CONSTRAINT support_inquiries_inquiry_type_check CHECK ((inquiry_type = ANY (ARRAY['bug'::text, 'usage'::text, 'suggestion'::text, 'other'::text]))),
    CONSTRAINT support_inquiries_reply_email_check CHECK ((((char_length(reply_email) >= 3) AND (char_length(reply_email) <= 254)) AND (reply_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'::text)))
);

--
-- Name: TABLE support_inquiries; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.support_inquiries IS 'Private support inbox matching the app form. Owner read, validated RPC-only submission; attachment paths refer to soolgyul-private.';

--
-- Name: taste_card_generation_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taste_card_generation_attempts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    attempt_ref text NOT NULL,
    idempotency_key uuid NOT NULL,
    owner_user_id uuid,
    anonymous_session_digest text,
    request_digest text NOT NULL,
    reserved_record_id uuid DEFAULT gen_random_uuid() NOT NULL,
    reserved_result_summary_id uuid DEFAULT gen_random_uuid() NOT NULL,
    state text DEFAULT 'processing'::text NOT NULL,
    error_code text,
    retry_after timestamp with time zone,
    result_summary_id uuid,
    claim_snapshot_id uuid,
    conversion_key_version text,
    conversion_expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    CONSTRAINT taste_card_generation_attempts_conversion_metadata_check CHECK ((((anonymous_session_digest IS NOT NULL) AND (((conversion_key_version IS NULL) AND (conversion_expires_at IS NULL) AND (state = ANY (ARRAY['processing'::text, 'retryable'::text]))) OR ((NULLIF(btrim(conversion_key_version), ''::text) IS NOT NULL) AND (char_length(conversion_key_version) <= 128) AND (conversion_expires_at IS NOT NULL)))) OR ((owner_user_id IS NOT NULL) AND (conversion_key_version IS NULL) AND (conversion_expires_at IS NULL)))),
    CONSTRAINT taste_card_generation_attempts_digests_check CHECK (((request_digest ~ '^[0-9a-f]{64}$'::text) AND ((anonymous_session_digest IS NULL) OR (anonymous_session_digest ~ '^[0-9a-f]{64}$'::text)))),
    CONSTRAINT taste_card_generation_attempts_error_code_check CHECK (((error_code IS NULL) OR (error_code = ANY (ARRAY['catalog_unavailable'::text, 'history_unavailable'::text, 'engine_temporarily_unavailable'::text])))),
    CONSTRAINT taste_card_generation_attempts_principal_check CHECK (((owner_user_id IS NOT NULL) <> (anonymous_session_digest IS NOT NULL))),
    CONSTRAINT taste_card_generation_attempts_ref_check CHECK (((btrim(attempt_ref) <> ''::text) AND (char_length(attempt_ref) <= 256))),
    CONSTRAINT taste_card_generation_attempts_reserved_ids_check CHECK (((state <> 'final'::text) OR (result_summary_id = reserved_result_summary_id))),
    CONSTRAINT taste_card_generation_attempts_state_check CHECK ((((state = 'processing'::text) AND (error_code IS NULL) AND (retry_after IS NULL) AND (result_summary_id IS NULL) AND (claim_snapshot_id IS NULL) AND (completed_at IS NULL)) OR ((state = 'retryable'::text) AND (NULLIF(btrim(error_code), ''::text) IS NOT NULL) AND (retry_after IS NOT NULL) AND (result_summary_id IS NULL) AND (claim_snapshot_id IS NULL) AND (completed_at IS NULL)) OR ((state = 'final'::text) AND (error_code IS NULL) AND (retry_after IS NULL) AND (result_summary_id IS NOT NULL) AND (claim_snapshot_id IS NOT NULL) AND (completed_at IS NOT NULL))))
);

--
-- Name: TABLE taste_card_generation_attempts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taste_card_generation_attempts IS 'Service-only idempotency and retry state; anonymous principals are stored as digests.';

--
-- Name: taste_cards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taste_cards (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    drink_record_id uuid NOT NULL,
    result_type_key text NOT NULL,
    taste_axis_scores jsonb DEFAULT '{}'::jsonb NOT NULL,
    preference_cues jsonb DEFAULT '[]'::jsonb NOT NULL,
    next_drink_directions jsonb DEFAULT '[]'::jsonb NOT NULL,
    burdensome_directions jsonb DEFAULT '[]'::jsonb NOT NULL,
    summary_paragraphs jsonb DEFAULT '[]'::jsonb NOT NULL,
    share_card_text text NOT NULL,
    catalog_evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    schema_version integer DEFAULT 1 NOT NULL,
    rule_version text DEFAULT 'legacy-rule-v1'::text NOT NULL,
    result_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    snapshot_id uuid,
    snapshot_ref text,
    lifecycle text,
    canonical_input_digest text,
    questionnaire_version text,
    catalog_taxonomy_version text,
    catalog_evidence_version text,
    adapter_compatibility_version text,
    canonical_schema_version text,
    memo_rule_version text,
    claim_registry_version text,
    claim_rule_versions jsonb,
    copy_template_version text,
    presentation_version text,
    source_statuses jsonb,
    semantic_snapshot jsonb,
    rendered_snapshot jsonb,
    supersedes_snapshot_id uuid,
    withdrawal_reason_code text,
    snapshot_created_at timestamp with time zone,
    withdrawn_at timestamp with time zone,
    CONSTRAINT drink_result_summaries_version_envelope_check CHECK (((schema_version > 0) AND (btrim(rule_version) <> ''::text) AND (jsonb_typeof(result_snapshot) = 'object'::text))),
    CONSTRAINT taste_cards_digest_check CHECK ((canonical_input_digest ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT taste_cards_json_check CHECK (((jsonb_typeof(claim_rule_versions) = 'array'::text) AND (jsonb_typeof(source_statuses) = 'object'::text) AND (jsonb_typeof(semantic_snapshot) = 'object'::text) AND (jsonb_typeof(rendered_snapshot) = 'object'::text) AND (pg_column_size(claim_rule_versions) <= 16384) AND (pg_column_size(source_statuses) <= 16384) AND (pg_column_size(semantic_snapshot) <= 524288) AND (pg_column_size(rendered_snapshot) <= 131072))),
    CONSTRAINT taste_cards_lifecycle_check CHECK ((((lifecycle = 'final'::text) AND (withdrawal_reason_code IS NULL) AND (withdrawn_at IS NULL)) OR ((lifecycle = ANY (ARRAY['withdrawn'::text, 'superseded'::text])) AND (NULLIF(btrim(withdrawal_reason_code), ''::text) IS NOT NULL) AND (withdrawn_at IS NOT NULL)))),
    CONSTRAINT taste_cards_ref_check CHECK (((btrim(snapshot_ref) <> ''::text) AND (char_length(snapshot_ref) <= 256))),
    CONSTRAINT taste_cards_snapshot_complete CHECK ((((snapshot_id IS NULL) AND (snapshot_ref IS NULL) AND (lifecycle IS NULL) AND (canonical_input_digest IS NULL) AND (questionnaire_version IS NULL) AND (catalog_taxonomy_version IS NULL) AND (catalog_evidence_version IS NULL) AND (adapter_compatibility_version IS NULL) AND (canonical_schema_version IS NULL) AND (memo_rule_version IS NULL) AND (claim_registry_version IS NULL) AND (claim_rule_versions IS NULL) AND (copy_template_version IS NULL) AND (presentation_version IS NULL) AND (source_statuses IS NULL) AND (semantic_snapshot IS NULL) AND (rendered_snapshot IS NULL) AND (supersedes_snapshot_id IS NULL) AND (withdrawal_reason_code IS NULL) AND (snapshot_created_at IS NULL) AND (withdrawn_at IS NULL) AND true) OR ((snapshot_id IS NOT NULL) AND (snapshot_id IS NOT NULL) AND (snapshot_ref IS NOT NULL) AND (lifecycle IS NOT NULL) AND (canonical_input_digest IS NOT NULL) AND (questionnaire_version IS NOT NULL) AND (catalog_taxonomy_version IS NOT NULL) AND (catalog_evidence_version IS NOT NULL) AND (adapter_compatibility_version IS NOT NULL) AND (canonical_schema_version IS NOT NULL) AND (memo_rule_version IS NOT NULL) AND (claim_registry_version IS NOT NULL) AND (claim_rule_versions IS NOT NULL) AND (copy_template_version IS NOT NULL) AND (presentation_version IS NOT NULL) AND (source_statuses IS NOT NULL) AND (semantic_snapshot IS NOT NULL) AND (rendered_snapshot IS NOT NULL) AND (snapshot_created_at IS NOT NULL) AND true))),
    CONSTRAINT taste_cards_supersedes_check CHECK (((supersedes_snapshot_id IS NULL) OR (supersedes_snapshot_id <> snapshot_id))),
    CONSTRAINT taste_cards_versions_check CHECK (((btrim(questionnaire_version) <> ''::text) AND (btrim(catalog_taxonomy_version) <> ''::text) AND (btrim(catalog_evidence_version) <> ''::text) AND (btrim(adapter_compatibility_version) <> ''::text) AND (btrim(canonical_schema_version) <> ''::text) AND (btrim(memo_rule_version) <> ''::text) AND (btrim(claim_registry_version) <> ''::text) AND (btrim(copy_template_version) <> ''::text) AND (btrim(presentation_version) <> ''::text) AND (char_length(questionnaire_version) <= 128) AND (char_length(catalog_taxonomy_version) <= 128) AND (char_length(catalog_evidence_version) <= 128) AND (char_length(adapter_compatibility_version) <= 128) AND (char_length(canonical_schema_version) <= 128) AND (char_length(memo_rule_version) <= 128) AND (char_length(claim_registry_version) <= 128) AND (char_length(copy_template_version) <= 128) AND (char_length(presentation_version) <= 128)))
);

--
-- Name: TABLE taste_cards; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taste_cards IS 'One taste card per drink record, including immutable rendered content and internal interpretation. Legacy cards retain their original content.';

--
-- Name: user_account_deletions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_account_deletions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    requested_at timestamp with time zone NOT NULL,
    scheduled_purge_at timestamp with time zone NOT NULL,
    restored_at timestamp with time zone,
    purged_at timestamp with time zone,
    status text NOT NULL,
    notice_copy_version text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_account_deletions_status_check CHECK ((status = ANY (ARRAY['scheduled'::text, 'restored'::text, 'purged'::text])))
);

--
-- Name: user_consents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_consents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    consent_type text NOT NULL,
    document_version text NOT NULL,
    accepted_at timestamp with time zone NOT NULL,
    withdrawn_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_consents_check CHECK (((withdrawn_at IS NULL) OR (withdrawn_at >= accepted_at))),
    CONSTRAINT user_consents_consent_type_check CHECK ((consent_type = ANY (ARRAY['age_19'::text, 'terms'::text, 'privacy'::text, 'marketing'::text]))),
    CONSTRAINT user_consents_document_version_check CHECK ((length(btrim(document_version)) > 0))
);

--
-- Name: TABLE user_consents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.user_consents IS 'Append-preserved consent periods. A new acceptance creates a new row; withdrawal closes that row without deleting prior history.';

--
-- Name: user_drink_interests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_drink_interests (
    user_id uuid NOT NULL,
    alcohol_interest_group_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE user_drink_interests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.user_drink_interests IS 'Owner interest selections using the 16 presentation-group keys approved by ADR-038. Mutations go through atomic RPC functions.';

--
-- Name: user_liked_drink_cards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_liked_drink_cards (
    user_id uuid NOT NULL,
    drink_result_summary_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE user_liked_drink_cards; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.user_liked_drink_cards IS 'Private owner-only favorites for the user''s own Soolgyul cards. This is not a social reaction or aggregate like counter.';

--
-- Name: COLUMN user_liked_drink_cards.drink_result_summary_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_liked_drink_cards.drink_result_summary_id IS 'The owner''s saved drink result summary that renders the liked Soolgyul card.';

--
-- Name: user_saved_articles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_saved_articles (
    user_id uuid NOT NULL,
    article_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE user_saved_articles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.user_saved_articles IS 'Private owner-only bookmarks for published Soolgyul editorial articles.';

--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    auth_provider text NOT NULL,
    provider_user_id text NOT NULL,
    email text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_sign_in_at timestamp with time zone,
    disabled_at timestamp with time zone,
    deletion_requested_at timestamp with time zone,
    deletion_scheduled_at timestamp with time zone,
    purged_at timestamp with time zone,
    account_status text GENERATED ALWAYS AS (
CASE
    WHEN (purged_at IS NOT NULL) THEN 'purged'::text
    WHEN ((deletion_requested_at IS NOT NULL) OR (deletion_scheduled_at IS NOT NULL)) THEN 'scheduled_deletion'::text
    WHEN (disabled_at IS NOT NULL) THEN 'disabled'::text
    ELSE 'active'::text
END) STORED NOT NULL,
    display_name text,
    age_confirmed_at timestamp with time zone,
    profile_created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    gender text,
    gender_consent_accepted_at timestamp with time zone,
    gender_consent_version text,
    birth_date date,
    deletion_provider_revoked_at timestamp with time zone,
    CONSTRAINT users_auth_provider_check CHECK ((auth_provider = ANY (ARRAY['kakao'::text, 'apple'::text, 'google'::text, 'test'::text]))),
    CONSTRAINT users_birth_date_check CHECK (((birth_date >= '1900-01-01'::date) AND (birth_date < '2100-01-01'::date))),
    CONSTRAINT users_gender_check CHECK ((gender = ANY (ARRAY['male'::text, 'female'::text, 'other'::text]))),
    CONSTRAINT users_gender_consent_check CHECK ((((gender IS NULL) AND (gender_consent_accepted_at IS NULL) AND (gender_consent_version IS NULL)) OR ((gender IS NOT NULL) AND (gender_consent_accepted_at IS NOT NULL) AND (gender_consent_version IS NOT NULL) AND (gender_consent_version = 'soolgyul-gender-v1'::text))))
);

--
-- Name: TABLE users; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.users IS 'Product account and user profile; client writes use owner RPCs. Consent history remains in user_consents.';

--
-- Name: COLUMN users.account_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.account_status IS 'Derived account lifecycle state. Existing deletion timestamps remain the workflow source until the frontend data contract is approved.';

--
-- Name: COLUMN users.profile_created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.profile_created_at IS 'Original profile creation timestamp retained during profile consolidation; account creation remains created_at.';

--
-- Name: COLUMN users.gender; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.gender IS 'Optional self-reported gender, not inferred from OAuth. Retained only with explicit consent.';

--
-- Name: COLUMN users.birth_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.birth_date IS 'Self-reported calendar birth date for age eligibility and age-based analysis; private, no synthetic backfill, original removed at final account deletion.';

--
-- Name: withdrawn_drink_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.withdrawn_drink_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    birth_year integer,
    gender text,
    record_data jsonb NOT NULL,
    CONSTRAINT withdrawn_drink_records_birth_year_check CHECK (((birth_year >= 1900) AND (birth_year <= 2099))),
    CONSTRAINT withdrawn_drink_records_gender_check CHECK ((gender = ANY (ARRAY['male'::text, 'female'::text, 'other'::text]))),
    CONSTRAINT withdrawn_drink_records_record_data_check CHECK ((jsonb_typeof(record_data) = 'object'::text))
);

--
-- Name: TABLE withdrawn_drink_records; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.withdrawn_drink_records IS 'Restricted post-withdrawal analysis records. Memo/free text retained by policy; not anonymous information. No public or owner access.';

--
-- Name: admin_user_roles admin_user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_user_roles
    ADD CONSTRAINT admin_user_roles_pkey PRIMARY KEY (user_id);

--
-- Name: alcohol_categories alcohol_categories_category_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_categories
    ADD CONSTRAINT alcohol_categories_category_key_key UNIQUE (category_key);

--
-- Name: alcohol_categories alcohol_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_categories
    ADD CONSTRAINT alcohol_categories_pkey PRIMARY KEY (id);

--
-- Name: alcohol_interest_group_categories alcohol_interest_group_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_interest_group_categories
    ADD CONSTRAINT alcohol_interest_group_categories_pkey PRIMARY KEY (alcohol_interest_group_id, alcohol_category_id);

--
-- Name: alcohol_interest_groups alcohol_interest_groups_interest_group_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_interest_groups
    ADD CONSTRAINT alcohol_interest_groups_interest_group_key_key UNIQUE (interest_group_key);

--
-- Name: alcohol_interest_groups alcohol_interest_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_interest_groups
    ADD CONSTRAINT alcohol_interest_groups_pkey PRIMARY KEY (id);

--
-- Name: alcohol_items alcohol_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_items
    ADD CONSTRAINT alcohol_items_pkey PRIMARY KEY (id);

--
-- Name: alcohol_tasting_profiles alcohol_tasting_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_tasting_profiles
    ADD CONSTRAINT alcohol_tasting_profiles_pkey PRIMARY KEY (id);

--
-- Name: catalog_media_assets catalog_media_assets_alcohol_item_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_media_assets
    ADD CONSTRAINT catalog_media_assets_alcohol_item_id_key UNIQUE (alcohol_item_id);

--
-- Name: catalog_media_assets catalog_media_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_media_assets
    ADD CONSTRAINT catalog_media_assets_pkey PRIMARY KEY (id);

--
-- Name: catalog_media_assets catalog_media_assets_storage_bucket_storage_object_path_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_media_assets
    ADD CONSTRAINT catalog_media_assets_storage_bucket_storage_object_path_key UNIQUE (storage_bucket, storage_object_path);

--
-- Name: catalog_media_fallbacks catalog_media_fallbacks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_media_fallbacks
    ADD CONSTRAINT catalog_media_fallbacks_pkey PRIMARY KEY (alcohol_item_id);

--
-- Name: catalog_terms catalog_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_terms
    ADD CONSTRAINT catalog_terms_pkey PRIMARY KEY (term_type, term_key);

--
-- Name: drink_record_answers drink_record_answers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_record_answers
    ADD CONSTRAINT drink_record_answers_pkey PRIMARY KEY (id);

--
-- Name: drink_records drink_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_records
    ADD CONSTRAINT drink_records_pkey PRIMARY KEY (id);

--
-- Name: taste_cards drink_result_summaries_drink_record_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_cards
    ADD CONSTRAINT drink_result_summaries_drink_record_id_key UNIQUE (drink_record_id);

--
-- Name: taste_cards drink_result_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_cards
    ADD CONSTRAINT drink_result_summaries_pkey PRIMARY KEY (id);

--
-- Name: editorial_article_interest_groups editorial_article_interest_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_article_interest_groups
    ADD CONSTRAINT editorial_article_interest_groups_pkey PRIMARY KEY (article_id, alcohol_interest_group_id);

--
-- Name: editorial_article_media_assets editorial_article_media_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_article_media_assets
    ADD CONSTRAINT editorial_article_media_assets_pkey PRIMARY KEY (id);

--
-- Name: editorial_articles editorial_articles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_articles
    ADD CONSTRAINT editorial_articles_pkey PRIMARY KEY (id);

--
-- Name: editorial_articles editorial_articles_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_articles
    ADD CONSTRAINT editorial_articles_slug_key UNIQUE (slug);

--
-- Name: editorial_categories editorial_categories_category_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_categories
    ADD CONSTRAINT editorial_categories_category_key_key UNIQUE (category_key);

--
-- Name: editorial_categories editorial_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_categories
    ADD CONSTRAINT editorial_categories_pkey PRIMARY KEY (id);

--
-- Name: questionnaire_options questionnaire_options_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_options
    ADD CONSTRAINT questionnaire_options_pkey PRIMARY KEY (id);

--
-- Name: questionnaire_options questionnaire_options_questionnaire_question_id_option_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_options
    ADD CONSTRAINT questionnaire_options_questionnaire_question_id_option_key_key UNIQUE (questionnaire_question_id, option_key);

--
-- Name: questionnaire_options questionnaire_options_questionnaire_question_id_option_orde_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_options
    ADD CONSTRAINT questionnaire_options_questionnaire_question_id_option_orde_key UNIQUE (questionnaire_question_id, option_order);

--
-- Name: questionnaire_questions questionnaire_questions_id_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_questions
    ADD CONSTRAINT questionnaire_questions_id_version_key UNIQUE (id, questionnaire_version_id);

--
-- Name: questionnaire_questions questionnaire_questions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_questions
    ADD CONSTRAINT questionnaire_questions_pkey PRIMARY KEY (id);

--
-- Name: questionnaire_questions questionnaire_questions_questionnaire_version_id_question_k_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_questions
    ADD CONSTRAINT questionnaire_questions_questionnaire_version_id_question_k_key UNIQUE (questionnaire_version_id, question_key);

--
-- Name: questionnaire_questions questionnaire_questions_questionnaire_version_id_screen_ord_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_questions
    ADD CONSTRAINT questionnaire_questions_questionnaire_version_id_screen_ord_key UNIQUE (questionnaire_version_id, screen_order);

--
-- Name: questionnaire_versions questionnaire_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_versions
    ADD CONSTRAINT questionnaire_versions_pkey PRIMARY KEY (id);

--
-- Name: questionnaire_versions questionnaire_versions_version_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_versions
    ADD CONSTRAINT questionnaire_versions_version_key_key UNIQUE (version_key);

--
-- Name: support_inquiries support_inquiries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_inquiries
    ADD CONSTRAINT support_inquiries_pkey PRIMARY KEY (id);

--
-- Name: taste_card_generation_attempts taste_card_generation_attempts_attempt_ref_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_card_generation_attempts
    ADD CONSTRAINT taste_card_generation_attempts_attempt_ref_key UNIQUE (attempt_ref);

--
-- Name: taste_card_generation_attempts taste_card_generation_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_card_generation_attempts
    ADD CONSTRAINT taste_card_generation_attempts_pkey PRIMARY KEY (id);

--
-- Name: taste_cards taste_cards_snapshot_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_cards
    ADD CONSTRAINT taste_cards_snapshot_id_key UNIQUE (snapshot_id);

--
-- Name: taste_cards taste_cards_snapshot_ref_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_cards
    ADD CONSTRAINT taste_cards_snapshot_ref_key UNIQUE (snapshot_ref);

--
-- Name: user_account_deletions user_account_deletions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_account_deletions
    ADD CONSTRAINT user_account_deletions_pkey PRIMARY KEY (id);

--
-- Name: user_consents user_consents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_consents
    ADD CONSTRAINT user_consents_pkey PRIMARY KEY (id);

--
-- Name: user_consents user_consents_user_id_consent_type_document_version_accepte_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_consents
    ADD CONSTRAINT user_consents_user_id_consent_type_document_version_accepte_key UNIQUE (user_id, consent_type, document_version, accepted_at);

--
-- Name: user_drink_interests user_drink_interests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_drink_interests
    ADD CONSTRAINT user_drink_interests_pkey PRIMARY KEY (user_id, alcohol_interest_group_id);

--
-- Name: user_liked_drink_cards user_liked_drink_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_liked_drink_cards
    ADD CONSTRAINT user_liked_drink_cards_pkey PRIMARY KEY (user_id, drink_result_summary_id);

--
-- Name: user_saved_articles user_saved_articles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_saved_articles
    ADD CONSTRAINT user_saved_articles_pkey PRIMARY KEY (user_id, article_id);

--
-- Name: users users_auth_provider_provider_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_auth_provider_provider_user_id_key UNIQUE (auth_provider, provider_user_id);

--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);

--
-- Name: withdrawn_drink_records withdrawn_drink_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.withdrawn_drink_records
    ADD CONSTRAINT withdrawn_drink_records_pkey PRIMARY KEY (id);

--
-- Name: admin_user_roles_granted_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX admin_user_roles_granted_by_idx ON public.admin_user_roles USING btree (granted_by) WHERE (granted_by IS NOT NULL);

--
-- Name: alcohol_items_aliases_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_aliases_idx ON public.alcohol_items USING gin (aliases);

--
-- Name: alcohol_items_category_name_en_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_category_name_en_idx ON public.alcohol_items USING btree (alcohol_category_id, public.soolgyul_normalize_catalog_text(name_en)) WHERE (NULLIF(btrim(name_en), ''::text) IS NOT NULL);

--
-- Name: alcohol_items_category_name_ko_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_category_name_ko_idx ON public.alcohol_items USING btree (alcohol_category_id, public.soolgyul_normalize_catalog_text(name_ko));

--
-- Name: INDEX alcohol_items_category_name_ko_idx; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.alcohol_items_category_name_ko_idx IS 'Non-unique product-name lookup; PIM identity also depends on producer and release context';

--
-- Name: alcohol_items_classification_keys_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_classification_keys_idx ON public.alcohol_items USING gin (classification_keys);

--
-- Name: alcohol_items_ingredient_keys_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_ingredient_keys_idx ON public.alcohol_items USING gin (ingredient_keys);

--
-- Name: alcohol_items_name_en_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_name_en_trgm_idx ON public.alcohol_items USING gin (public.soolgyul_normalize_catalog_text(name_en) extensions.gin_trgm_ops);

--
-- Name: alcohol_items_name_ko_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_name_ko_trgm_idx ON public.alcohol_items USING gin (public.soolgyul_normalize_catalog_text(name_ko) extensions.gin_trgm_ops);

--
-- Name: alcohol_items_product_group_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_product_group_idx ON public.alcohol_items USING btree (product_group_id) WHERE (product_group_id IS NOT NULL);

--
-- Name: alcohol_items_production_process_keys_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_production_process_keys_idx ON public.alcohol_items USING gin (production_process_keys);

--
-- Name: alcohol_items_published_aliases_lower_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_published_aliases_lower_idx ON public.alcohol_items USING gin (public.soolgyul_lower_catalog_text_array(aliases)) WHERE (publish_status = 'published'::text);

--
-- Name: alcohol_items_published_category_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_published_category_id_idx ON public.alcohol_items USING btree (alcohol_category_id, id) WHERE (publish_status = 'published'::text);

--
-- Name: alcohol_items_published_name_en_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_published_name_en_trgm_idx ON public.alcohol_items USING gin (lower(name_en) extensions.gin_trgm_ops) WHERE ((publish_status = 'published'::text) AND (name_en IS NOT NULL));

--
-- Name: alcohol_items_published_name_ko_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_published_name_ko_trgm_idx ON public.alcohol_items USING gin (lower(name_ko) extensions.gin_trgm_ops) WHERE (publish_status = 'published'::text);

--
-- Name: alcohol_items_published_search_keywords_lower_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_published_search_keywords_lower_idx ON public.alcohol_items USING gin (public.soolgyul_lower_catalog_text_array(search_keywords)) WHERE (publish_status = 'published'::text);

--
-- Name: alcohol_items_search_keywords_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_search_keywords_idx ON public.alcohol_items USING gin (search_keywords);

--
-- Name: alcohol_tasting_profiles_aroma_tags_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_tasting_profiles_aroma_tags_idx ON public.alcohol_tasting_profiles USING gin (aroma_tags);

--
-- Name: alcohol_tasting_profiles_finish_tags_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_tasting_profiles_finish_tags_idx ON public.alcohol_tasting_profiles USING gin (finish_tags);

--
-- Name: alcohol_tasting_profiles_one_product; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX alcohol_tasting_profiles_one_product ON public.alcohol_tasting_profiles USING btree (alcohol_item_id) WHERE (alcohol_item_id IS NOT NULL);

--
-- Name: alcohol_tasting_profiles_palate_tags_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_tasting_profiles_palate_tags_idx ON public.alcohol_tasting_profiles USING gin (palate_tags);

--
-- Name: alcohol_tasting_profiles_recent_updates_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_tasting_profiles_recent_updates_idx ON public.alcohol_tasting_profiles USING btree (updated_at, id);

--
-- Name: alcohol_tasting_profiles_texture_tags_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_tasting_profiles_texture_tags_idx ON public.alcohol_tasting_profiles USING gin (texture_tags);

--
-- Name: catalog_terms_active_type_sort_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_terms_active_type_sort_idx ON public.catalog_terms USING btree (term_type, sort_order, term_key) WHERE is_active;

--
-- Name: catalog_terms_applicable_sections_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_terms_applicable_sections_idx ON public.catalog_terms USING gin (applicable_sections);

--
-- Name: catalog_terms_synonyms_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_terms_synonyms_idx ON public.catalog_terms USING gin (synonyms);

--
-- Name: drink_record_answers_record_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX drink_record_answers_record_id_idx ON public.drink_record_answers USING btree (drink_record_id);

--
-- Name: drink_record_answers_record_question_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX drink_record_answers_record_question_uidx ON public.drink_record_answers USING btree (drink_record_id, question_key);

--
-- Name: drink_records_idempotency_key_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX drink_records_idempotency_key_uidx ON public.drink_records USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);

--
-- Name: drink_records_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX drink_records_user_id_idx ON public.drink_records USING btree (user_id);

--
-- Name: editorial_article_interest_group_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX editorial_article_interest_group_idx ON public.editorial_article_interest_groups USING btree (alcohol_interest_group_id, article_id);

--
-- Name: editorial_article_media_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX editorial_article_media_order_idx ON public.editorial_article_media_assets USING btree (article_id, asset_role, sort_order);

--
-- Name: editorial_article_one_cover_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX editorial_article_one_cover_idx ON public.editorial_article_media_assets USING btree (article_id) WHERE (asset_role = 'cover'::text);

--
-- Name: editorial_articles_category_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX editorial_articles_category_idx ON public.editorial_articles USING btree (category_id, status, published_at DESC);

--
-- Name: editorial_articles_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX editorial_articles_created_by_idx ON public.editorial_articles USING btree (created_by) WHERE (created_by IS NOT NULL);

--
-- Name: editorial_articles_publication_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX editorial_articles_publication_idx ON public.editorial_articles USING btree (status, published_at DESC);

--
-- Name: editorial_articles_published_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX editorial_articles_published_by_idx ON public.editorial_articles USING btree (published_by) WHERE (published_by IS NOT NULL);

--
-- Name: editorial_articles_tags_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX editorial_articles_tags_idx ON public.editorial_articles USING gin (tags);

--
-- Name: editorial_articles_updated_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX editorial_articles_updated_by_idx ON public.editorial_articles USING btree (updated_by) WHERE (updated_by IS NOT NULL);

--
-- Name: support_inquiries_user_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX support_inquiries_user_created_idx ON public.support_inquiries USING btree (user_id, created_at DESC);

--
-- Name: taste_card_generation_attempts_anon_idempotency_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX taste_card_generation_attempts_anon_idempotency_uidx ON public.taste_card_generation_attempts USING btree (anonymous_session_digest, idempotency_key) WHERE (anonymous_session_digest IS NOT NULL);

--
-- Name: taste_card_generation_attempts_owner_idempotency_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX taste_card_generation_attempts_owner_idempotency_uidx ON public.taste_card_generation_attempts USING btree (owner_user_id, idempotency_key) WHERE (owner_user_id IS NOT NULL);

--
-- Name: taste_card_generation_attempts_reserved_record_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX taste_card_generation_attempts_reserved_record_uidx ON public.taste_card_generation_attempts USING btree (reserved_record_id);

--
-- Name: taste_card_generation_attempts_reserved_result_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX taste_card_generation_attempts_reserved_result_uidx ON public.taste_card_generation_attempts USING btree (reserved_result_summary_id);

--
-- Name: taste_card_generation_attempts_result_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX taste_card_generation_attempts_result_idx ON public.taste_card_generation_attempts USING btree (result_summary_id) WHERE (result_summary_id IS NOT NULL);

--
-- Name: user_account_deletions_one_scheduled_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_account_deletions_one_scheduled_idx ON public.user_account_deletions USING btree (user_id) WHERE (status = 'scheduled'::text);

--
-- Name: user_account_deletions_user_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_account_deletions_user_status_idx ON public.user_account_deletions USING btree (user_id, status);

--
-- Name: user_consents_one_active_document_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_consents_one_active_document_idx ON public.user_consents USING btree (user_id, consent_type, document_version) WHERE (withdrawn_at IS NULL);

--
-- Name: user_consents_user_recorded_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_consents_user_recorded_idx ON public.user_consents USING btree (user_id, accepted_at DESC);

--
-- Name: user_drink_interests_group_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_drink_interests_group_idx ON public.user_drink_interests USING btree (alcohol_interest_group_id);

--
-- Name: user_liked_drink_cards_result_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_liked_drink_cards_result_idx ON public.user_liked_drink_cards USING btree (drink_result_summary_id);

--
-- Name: user_saved_articles_article_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_saved_articles_article_idx ON public.user_saved_articles USING btree (article_id);

--
-- Name: alcohol_categories alcohol_categories_assignment_validate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER alcohol_categories_assignment_validate AFTER DELETE OR UPDATE ON public.alcohol_categories DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.soolgyul_catalog_assignment_category_validate();

--
-- Name: alcohol_categories alcohol_categories_assignment_write_lock; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER alcohol_categories_assignment_write_lock BEFORE INSERT OR DELETE OR UPDATE ON public.alcohol_categories FOR EACH STATEMENT EXECUTE FUNCTION public.soolgyul_catalog_assignment_write_lock();

--
-- Name: alcohol_items alcohol_items_active_category_assignment_validate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER alcohol_items_active_category_assignment_validate BEFORE INSERT OR UPDATE OF alcohol_category_id ON public.alcohol_items FOR EACH ROW EXECUTE FUNCTION public.soolgyul_validate_active_alcohol_category_assignment();

--
-- Name: alcohol_items alcohol_items_assignment_validate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER alcohol_items_assignment_validate AFTER INSERT OR UPDATE ON public.alcohol_items DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.soolgyul_catalog_assignment_row_validate();

--
-- Name: alcohol_items alcohol_items_assignment_write_lock; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER alcohol_items_assignment_write_lock BEFORE INSERT OR DELETE OR UPDATE ON public.alcohol_items FOR EACH STATEMENT EXECUTE FUNCTION public.soolgyul_catalog_assignment_write_lock();

--
-- Name: alcohol_items alcohol_items_catalog_terms_validate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER alcohol_items_catalog_terms_validate BEFORE INSERT OR UPDATE OF classification_keys, ingredient_keys, production_process_keys, style_key ON public.alcohol_items FOR EACH ROW EXECUTE FUNCTION public.soolgyul_validate_alcohol_item_catalog_terms();

--
-- Name: alcohol_items alcohol_items_prevent_served_category_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER alcohol_items_prevent_served_category_change BEFORE UPDATE OF alcohol_category_id ON public.alcohol_items FOR EACH ROW EXECUTE FUNCTION public.soolgyul_prevent_served_item_category_change();

--
-- Name: alcohol_tasting_profiles alcohol_tasting_profiles_catalog_terms_validate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER alcohol_tasting_profiles_catalog_terms_validate BEFORE INSERT OR UPDATE OF aroma_tags, palate_tags, texture_tags, finish_tags ON public.alcohol_tasting_profiles FOR EACH ROW EXECUTE FUNCTION public.soolgyul_validate_tasting_profile_catalog_terms();

--
-- Name: alcohol_tasting_profiles alcohol_tasting_profiles_prevent_populated_retargeting; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER alcohol_tasting_profiles_prevent_populated_retargeting BEFORE UPDATE OF alcohol_item_id ON public.alcohol_tasting_profiles FOR EACH ROW EXECUTE FUNCTION public.soolgyul_prevent_populated_tasting_profile_retargeting();

--
-- Name: catalog_terms catalog_terms_assignment_validate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER catalog_terms_assignment_validate AFTER INSERT OR UPDATE ON public.catalog_terms DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.soolgyul_catalog_assignment_term_validate();

--
-- Name: catalog_terms catalog_terms_assignment_write_lock; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER catalog_terms_assignment_write_lock BEFORE INSERT OR DELETE OR UPDATE ON public.catalog_terms FOR EACH STATEMENT EXECUTE FUNCTION public.soolgyul_catalog_assignment_write_lock();

--
-- Name: catalog_terms catalog_terms_prevent_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER catalog_terms_prevent_delete BEFORE DELETE ON public.catalog_terms FOR EACH ROW EXECUTE FUNCTION public.soolgyul_protect_catalog_term_identity();

--
-- Name: catalog_terms catalog_terms_prevent_identity_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER catalog_terms_prevent_identity_change BEFORE UPDATE OF term_type, term_key ON public.catalog_terms FOR EACH ROW EXECUTE FUNCTION public.soolgyul_protect_catalog_term_identity();

--
-- Name: drink_records drink_records_guard_final_identity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER drink_records_guard_final_identity BEFORE UPDATE OF questionnaire_version_id, alcohol_item_id, entered_alcohol_name, alcohol_name_snapshot, category, identification_mode ON public.drink_records FOR EACH ROW WHEN (((((((old.questionnaire_version_id IS DISTINCT FROM new.questionnaire_version_id) OR (old.alcohol_item_id IS DISTINCT FROM new.alcohol_item_id)) OR (old.entered_alcohol_name IS DISTINCT FROM new.entered_alcohol_name)) OR (old.alcohol_name_snapshot IS DISTINCT FROM new.alcohol_name_snapshot)) OR (old.category IS DISTINCT FROM new.category)) OR (old.identification_mode IS DISTINCT FROM new.identification_mode))) EXECUTE FUNCTION public.soolgyul_guard_final_drink_record_identity();

--
-- Name: editorial_articles editorial_articles_prepare_admin_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER editorial_articles_prepare_admin_write BEFORE INSERT OR UPDATE ON public.editorial_articles FOR EACH ROW EXECUTE FUNCTION public.soolgyul_prepare_admin_editorial_article();

--
-- Name: editorial_articles editorial_articles_touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER editorial_articles_touch_updated_at BEFORE UPDATE ON public.editorial_articles FOR EACH ROW EXECUTE FUNCTION public.soolgyul_touch_editorial_updated_at();

--
-- Name: editorial_categories editorial_categories_touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER editorial_categories_touch_updated_at BEFORE UPDATE ON public.editorial_categories FOR EACH ROW EXECUTE FUNCTION public.soolgyul_touch_editorial_updated_at();

--
-- Name: alcohol_tasting_profiles invalidate_product_sensory_facts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER invalidate_product_sensory_facts BEFORE UPDATE ON public.alcohol_tasting_profiles FOR EACH ROW EXECUTE FUNCTION public.invalidate_product_sensory_facts();

--
-- Name: questionnaire_options questionnaire_options_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER questionnaire_options_immutable BEFORE INSERT OR DELETE OR UPDATE ON public.questionnaire_options FOR EACH ROW EXECUTE FUNCTION public.soolgyul_guard_questionnaire_content();

--
-- Name: questionnaire_questions questionnaire_questions_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER questionnaire_questions_immutable BEFORE INSERT OR DELETE OR UPDATE ON public.questionnaire_questions FOR EACH ROW EXECUTE FUNCTION public.soolgyul_guard_questionnaire_content();

--
-- Name: questionnaire_versions questionnaire_versions_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER questionnaire_versions_immutable BEFORE INSERT OR DELETE OR UPDATE ON public.questionnaire_versions FOR EACH ROW EXECUTE FUNCTION public.soolgyul_guard_questionnaire_version();

--
-- Name: taste_cards taste_cards_content_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER taste_cards_content_immutable BEFORE UPDATE ON public.taste_cards FOR EACH ROW EXECUTE FUNCTION public.soolgyul_guard_taste_card_content();

--
-- Name: user_drink_interests user_drink_interests_enforce_limit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER user_drink_interests_enforce_limit BEFORE INSERT ON public.user_drink_interests FOR EACH ROW EXECUTE FUNCTION public.soolgyul_enforce_drink_interest_limit();

--
-- Name: admin_user_roles admin_user_roles_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_user_roles
    ADD CONSTRAINT admin_user_roles_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.users(id) ON DELETE SET NULL;

--
-- Name: admin_user_roles admin_user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_user_roles
    ADD CONSTRAINT admin_user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: alcohol_interest_group_categories alcohol_interest_group_categorie_alcohol_interest_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_interest_group_categories
    ADD CONSTRAINT alcohol_interest_group_categorie_alcohol_interest_group_id_fkey FOREIGN KEY (alcohol_interest_group_id) REFERENCES public.alcohol_interest_groups(id) ON DELETE RESTRICT;

--
-- Name: alcohol_interest_group_categories alcohol_interest_group_categories_alcohol_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_interest_group_categories
    ADD CONSTRAINT alcohol_interest_group_categories_alcohol_category_id_fkey FOREIGN KEY (alcohol_category_id) REFERENCES public.alcohol_categories(id) ON DELETE RESTRICT;

--
-- Name: alcohol_items alcohol_items_alcohol_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_items
    ADD CONSTRAINT alcohol_items_alcohol_category_id_fkey FOREIGN KEY (alcohol_category_id) REFERENCES public.alcohol_categories(id) ON DELETE RESTRICT;

--
-- Name: alcohol_tasting_profiles alcohol_tasting_profiles_alcohol_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_tasting_profiles
    ADD CONSTRAINT alcohol_tasting_profiles_alcohol_item_id_fkey FOREIGN KEY (alcohol_item_id) REFERENCES public.alcohol_items(id) ON DELETE RESTRICT;

--
-- Name: catalog_media_assets catalog_media_assets_alcohol_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_media_assets
    ADD CONSTRAINT catalog_media_assets_alcohol_item_id_fkey FOREIGN KEY (alcohol_item_id) REFERENCES public.alcohol_items(id) ON DELETE RESTRICT;

--
-- Name: catalog_media_fallbacks catalog_media_fallbacks_alcohol_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_media_fallbacks
    ADD CONSTRAINT catalog_media_fallbacks_alcohol_item_id_fkey FOREIGN KEY (alcohol_item_id) REFERENCES public.alcohol_items(id) ON DELETE CASCADE;

--
-- Name: catalog_media_fallbacks catalog_media_fallbacks_source_catalog_media_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_media_fallbacks
    ADD CONSTRAINT catalog_media_fallbacks_source_catalog_media_asset_id_fkey FOREIGN KEY (source_catalog_media_asset_id) REFERENCES public.catalog_media_assets(id) ON DELETE RESTRICT;

--
-- Name: catalog_terms catalog_terms_parent_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_terms
    ADD CONSTRAINT catalog_terms_parent_fkey FOREIGN KEY (term_type, parent_term_key) REFERENCES public.catalog_terms(term_type, term_key) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

--
-- Name: drink_record_answers drink_record_answers_drink_record_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_record_answers
    ADD CONSTRAINT drink_record_answers_drink_record_id_fkey FOREIGN KEY (drink_record_id) REFERENCES public.drink_records(id) ON DELETE CASCADE;

--
-- Name: drink_record_answers drink_record_answers_question_version_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_record_answers
    ADD CONSTRAINT drink_record_answers_question_version_fkey FOREIGN KEY (questionnaire_question_id, questionnaire_version_id) REFERENCES public.questionnaire_questions(id, questionnaire_version_id) ON DELETE RESTRICT;

--
-- Name: drink_record_answers drink_record_answers_questionnaire_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_record_answers
    ADD CONSTRAINT drink_record_answers_questionnaire_version_id_fkey FOREIGN KEY (questionnaire_version_id) REFERENCES public.questionnaire_versions(id);

--
-- Name: drink_records drink_records_alcohol_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_records
    ADD CONSTRAINT drink_records_alcohol_item_id_fkey FOREIGN KEY (alcohol_item_id) REFERENCES public.alcohol_items(id);

--
-- Name: drink_records drink_records_questionnaire_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_records
    ADD CONSTRAINT drink_records_questionnaire_version_id_fkey FOREIGN KEY (questionnaire_version_id) REFERENCES public.questionnaire_versions(id) ON DELETE RESTRICT;

--
-- Name: drink_records drink_records_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_records
    ADD CONSTRAINT drink_records_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: taste_cards drink_result_summaries_drink_record_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_cards
    ADD CONSTRAINT drink_result_summaries_drink_record_id_fkey FOREIGN KEY (drink_record_id) REFERENCES public.drink_records(id) ON DELETE CASCADE;

--
-- Name: editorial_article_interest_groups editorial_article_interest_group_alcohol_interest_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_article_interest_groups
    ADD CONSTRAINT editorial_article_interest_group_alcohol_interest_group_id_fkey FOREIGN KEY (alcohol_interest_group_id) REFERENCES public.alcohol_interest_groups(id) ON DELETE RESTRICT;

--
-- Name: editorial_article_interest_groups editorial_article_interest_groups_article_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_article_interest_groups
    ADD CONSTRAINT editorial_article_interest_groups_article_id_fkey FOREIGN KEY (article_id) REFERENCES public.editorial_articles(id) ON DELETE CASCADE;

--
-- Name: editorial_article_media_assets editorial_article_media_assets_article_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_article_media_assets
    ADD CONSTRAINT editorial_article_media_assets_article_id_fkey FOREIGN KEY (article_id) REFERENCES public.editorial_articles(id) ON DELETE CASCADE;

--
-- Name: editorial_articles editorial_articles_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_articles
    ADD CONSTRAINT editorial_articles_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.editorial_categories(id) ON DELETE RESTRICT;

--
-- Name: editorial_articles editorial_articles_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_articles
    ADD CONSTRAINT editorial_articles_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;

--
-- Name: editorial_articles editorial_articles_published_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_articles
    ADD CONSTRAINT editorial_articles_published_by_fkey FOREIGN KEY (published_by) REFERENCES public.users(id) ON DELETE SET NULL;

--
-- Name: editorial_articles editorial_articles_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_articles
    ADD CONSTRAINT editorial_articles_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;

--
-- Name: questionnaire_options questionnaire_options_questionnaire_question_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_options
    ADD CONSTRAINT questionnaire_options_questionnaire_question_id_fkey FOREIGN KEY (questionnaire_question_id) REFERENCES public.questionnaire_questions(id) ON DELETE CASCADE;

--
-- Name: questionnaire_questions questionnaire_questions_questionnaire_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_questions
    ADD CONSTRAINT questionnaire_questions_questionnaire_version_id_fkey FOREIGN KEY (questionnaire_version_id) REFERENCES public.questionnaire_versions(id) ON DELETE CASCADE;

--
-- Name: questionnaire_versions questionnaire_versions_supersedes_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_versions
    ADD CONSTRAINT questionnaire_versions_supersedes_version_id_fkey FOREIGN KEY (supersedes_version_id) REFERENCES public.questionnaire_versions(id);

--
-- Name: support_inquiries support_inquiries_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_inquiries
    ADD CONSTRAINT support_inquiries_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: taste_card_generation_attempts taste_card_generation_attempts_claim_snapshot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_card_generation_attempts
    ADD CONSTRAINT taste_card_generation_attempts_claim_snapshot_id_fkey FOREIGN KEY (claim_snapshot_id) REFERENCES public.taste_cards(snapshot_id) ON DELETE RESTRICT;

--
-- Name: taste_card_generation_attempts taste_card_generation_attempts_owner_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_card_generation_attempts
    ADD CONSTRAINT taste_card_generation_attempts_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: taste_card_generation_attempts taste_card_generation_attempts_result_summary_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_card_generation_attempts
    ADD CONSTRAINT taste_card_generation_attempts_result_summary_id_fkey FOREIGN KEY (result_summary_id) REFERENCES public.taste_cards(id) ON DELETE CASCADE;

--
-- Name: taste_cards taste_cards_supersedes_snapshot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_cards
    ADD CONSTRAINT taste_cards_supersedes_snapshot_id_fkey FOREIGN KEY (supersedes_snapshot_id) REFERENCES public.taste_cards(snapshot_id) ON DELETE RESTRICT;

--
-- Name: user_account_deletions user_account_deletions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_account_deletions
    ADD CONSTRAINT user_account_deletions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: user_consents user_consents_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_consents
    ADD CONSTRAINT user_consents_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: user_drink_interests user_drink_interests_alcohol_interest_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_drink_interests
    ADD CONSTRAINT user_drink_interests_alcohol_interest_group_id_fkey FOREIGN KEY (alcohol_interest_group_id) REFERENCES public.alcohol_interest_groups(id) ON DELETE RESTRICT;

--
-- Name: user_drink_interests user_drink_interests_user_id_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_drink_interests
    ADD CONSTRAINT user_drink_interests_user_id_fkey1 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: user_liked_drink_cards user_liked_drink_cards_drink_result_summary_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_liked_drink_cards
    ADD CONSTRAINT user_liked_drink_cards_drink_result_summary_id_fkey FOREIGN KEY (drink_result_summary_id) REFERENCES public.taste_cards(id) ON DELETE CASCADE;

--
-- Name: user_liked_drink_cards user_liked_drink_cards_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_liked_drink_cards
    ADD CONSTRAINT user_liked_drink_cards_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: user_saved_articles user_saved_articles_article_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_saved_articles
    ADD CONSTRAINT user_saved_articles_article_id_fkey FOREIGN KEY (article_id) REFERENCES public.editorial_articles(id) ON DELETE CASCADE;

--
-- Name: user_saved_articles user_saved_articles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_saved_articles
    ADD CONSTRAINT user_saved_articles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: users users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

--
-- Name: admin_user_roles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admin_user_roles ENABLE ROW LEVEL SECURITY;

--
-- Name: admin_user_roles admin_user_roles_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_user_roles_owner_select ON public.admin_user_roles FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) AND public.soolgyul_account_active(user_id)));

--
-- Name: alcohol_categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.alcohol_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: alcohol_categories alcohol_categories_public_read_active; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY alcohol_categories_public_read_active ON public.alcohol_categories FOR SELECT TO authenticated, anon USING (is_active);

--
-- Name: alcohol_interest_group_categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.alcohol_interest_group_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: alcohol_interest_group_categories alcohol_interest_group_categories_active_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY alcohol_interest_group_categories_active_read ON public.alcohol_interest_group_categories FOR SELECT TO authenticated, anon USING (((EXISTS ( SELECT 1
   FROM public.alcohol_interest_groups interest_group
  WHERE ((interest_group.id = alcohol_interest_group_categories.alcohol_interest_group_id) AND interest_group.is_active))) AND (EXISTS ( SELECT 1
   FROM public.alcohol_categories category
  WHERE ((category.id = alcohol_interest_group_categories.alcohol_category_id) AND category.is_active)))));

--
-- Name: alcohol_interest_groups; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.alcohol_interest_groups ENABLE ROW LEVEL SECURITY;

--
-- Name: alcohol_interest_groups alcohol_interest_groups_active_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY alcohol_interest_groups_active_read ON public.alcohol_interest_groups FOR SELECT TO authenticated, anon USING (is_active);

--
-- Name: alcohol_interest_groups alcohol_interest_groups_selected_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY alcohol_interest_groups_selected_read ON public.alcohol_interest_groups FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.user_drink_interests selection
  WHERE ((selection.user_id = auth.uid()) AND (selection.alcohol_interest_group_id = alcohol_interest_groups.id) AND public.soolgyul_account_active(selection.user_id)))));

--
-- Name: alcohol_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.alcohol_items ENABLE ROW LEVEL SECURITY;

--
-- Name: alcohol_tasting_profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.alcohol_tasting_profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: catalog_media_assets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.catalog_media_assets ENABLE ROW LEVEL SECURITY;

--
-- Name: catalog_media_fallbacks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.catalog_media_fallbacks ENABLE ROW LEVEL SECURITY;

--
-- Name: catalog_terms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.catalog_terms ENABLE ROW LEVEL SECURITY;

--
-- Name: drink_record_answers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.drink_record_answers ENABLE ROW LEVEL SECURITY;

--
-- Name: drink_record_answers drink_record_answers_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY drink_record_answers_owner_select ON public.drink_record_answers FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.drink_records r
  WHERE ((r.id = drink_record_answers.drink_record_id) AND (r.user_id = auth.uid()) AND (r.deleted_at IS NULL) AND public.soolgyul_account_active(r.user_id)))));

--
-- Name: drink_records; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.drink_records ENABLE ROW LEVEL SECURITY;

--
-- Name: drink_records drink_records_owner_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY drink_records_owner_insert ON public.drink_records FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id)));

--
-- Name: drink_records drink_records_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY drink_records_owner_select ON public.drink_records FOR SELECT TO authenticated USING (((user_id = auth.uid()) AND (deleted_at IS NULL) AND public.soolgyul_account_active(user_id)));

--
-- Name: drink_records drink_records_owner_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY drink_records_owner_update ON public.drink_records FOR UPDATE TO authenticated USING (((user_id = auth.uid()) AND (deleted_at IS NULL) AND public.soolgyul_account_active(user_id))) WITH CHECK (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id)));

--
-- Name: taste_cards drink_result_summaries_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY drink_result_summaries_owner_select ON public.taste_cards FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.drink_records r
  WHERE ((r.id = taste_cards.drink_record_id) AND (r.user_id = auth.uid()) AND (r.deleted_at IS NULL) AND public.soolgyul_account_active(r.user_id)))));

--
-- Name: editorial_article_interest_groups; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.editorial_article_interest_groups ENABLE ROW LEVEL SECURITY;

--
-- Name: editorial_article_interest_groups editorial_article_interests_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_interests_admin_delete ON public.editorial_article_interest_groups FOR DELETE TO authenticated USING ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_interest_groups.article_id) AND (article.status = 'draft'::text) AND (article.published_at IS NULL)))))));

--
-- Name: editorial_article_interest_groups editorial_article_interests_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_interests_admin_insert ON public.editorial_article_interest_groups FOR INSERT TO authenticated WITH CHECK ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_interest_groups.article_id) AND (article.status = 'draft'::text) AND (article.published_at IS NULL)))))));

--
-- Name: editorial_article_interest_groups editorial_article_interests_anon_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_interests_anon_select ON public.editorial_article_interest_groups FOR SELECT TO anon USING ((EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_interest_groups.article_id) AND (article.status = 'published'::text) AND (article.published_at IS NOT NULL) AND (article.published_at <= now())))));

--
-- Name: editorial_article_interest_groups editorial_article_interests_authenticated_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_interests_authenticated_select ON public.editorial_article_interest_groups FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_interest_groups.article_id) AND (article.status = 'published'::text) AND (article.published_at IS NOT NULL) AND (article.published_at <= now())))) OR public.soolgyul_admin_has_role()));

--
-- Name: editorial_article_media_assets editorial_article_media_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_media_admin_delete ON public.editorial_article_media_assets FOR DELETE TO authenticated USING ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_media_assets.article_id) AND (article.status = 'draft'::text) AND (article.published_at IS NULL)))))));

--
-- Name: editorial_article_media_assets editorial_article_media_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_media_admin_insert ON public.editorial_article_media_assets FOR INSERT TO authenticated WITH CHECK ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_media_assets.article_id) AND (article.status = 'draft'::text) AND (article.published_at IS NULL)))))));

--
-- Name: editorial_article_media_assets editorial_article_media_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_media_admin_update ON public.editorial_article_media_assets FOR UPDATE TO authenticated USING (public.soolgyul_admin_has_role()) WITH CHECK ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_media_assets.article_id) AND (article.status = 'draft'::text) AND (article.published_at IS NULL)))))));

--
-- Name: editorial_article_media_assets editorial_article_media_anon_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_media_anon_select ON public.editorial_article_media_assets FOR SELECT TO anon USING ((EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_media_assets.article_id) AND (article.status = 'published'::text) AND (article.published_at IS NOT NULL) AND (article.published_at <= now())))));

--
-- Name: editorial_article_media_assets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.editorial_article_media_assets ENABLE ROW LEVEL SECURITY;

--
-- Name: editorial_article_media_assets editorial_article_media_authenticated_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_media_authenticated_select ON public.editorial_article_media_assets FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_media_assets.article_id) AND (article.status = 'published'::text) AND (article.published_at IS NOT NULL) AND (article.published_at <= now())))) OR public.soolgyul_admin_has_role()));

--
-- Name: editorial_articles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.editorial_articles ENABLE ROW LEVEL SECURITY;

--
-- Name: editorial_articles editorial_articles_admin_delete_draft; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_articles_admin_delete_draft ON public.editorial_articles FOR DELETE TO authenticated USING ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) AND (status = 'draft'::text) AND (published_at IS NULL)));

--
-- Name: editorial_articles editorial_articles_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_articles_admin_insert ON public.editorial_articles FOR INSERT TO authenticated WITH CHECK ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (status = 'draft'::text) AND (published_at IS NULL))));

--
-- Name: editorial_articles editorial_articles_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_articles_admin_update ON public.editorial_articles FOR UPDATE TO authenticated USING (public.soolgyul_admin_has_role()) WITH CHECK ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (status = 'draft'::text) AND (published_at IS NULL))));

--
-- Name: editorial_articles editorial_articles_anon_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_articles_anon_select ON public.editorial_articles FOR SELECT TO anon USING (((status = 'published'::text) AND (published_at IS NOT NULL) AND (published_at <= now())));

--
-- Name: editorial_articles editorial_articles_authenticated_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_articles_authenticated_select ON public.editorial_articles FOR SELECT TO authenticated USING ((((status = 'published'::text) AND (published_at IS NOT NULL) AND (published_at <= now())) OR public.soolgyul_admin_has_role()));

--
-- Name: editorial_categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.editorial_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: editorial_categories editorial_categories_anon_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_categories_anon_select ON public.editorial_categories FOR SELECT TO anon USING (is_active);

--
-- Name: editorial_categories editorial_categories_authenticated_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_categories_authenticated_select ON public.editorial_categories FOR SELECT TO authenticated USING ((is_active OR public.soolgyul_admin_has_role()));

--
-- Name: questionnaire_options; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.questionnaire_options ENABLE ROW LEVEL SECURITY;

--
-- Name: questionnaire_options questionnaire_options_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY questionnaire_options_public_read ON public.questionnaire_options FOR SELECT TO authenticated, anon USING ((EXISTS ( SELECT 1
   FROM (public.questionnaire_questions q
     JOIN public.questionnaire_versions v ON ((v.id = q.questionnaire_version_id)))
  WHERE ((q.id = questionnaire_options.questionnaire_question_id) AND (v.status = 'published'::text)))));

--
-- Name: questionnaire_questions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.questionnaire_questions ENABLE ROW LEVEL SECURITY;

--
-- Name: questionnaire_questions questionnaire_questions_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY questionnaire_questions_public_read ON public.questionnaire_questions FOR SELECT TO authenticated, anon USING ((EXISTS ( SELECT 1
   FROM public.questionnaire_versions v
  WHERE ((v.id = questionnaire_questions.questionnaire_version_id) AND (v.status = 'published'::text)))));

--
-- Name: questionnaire_versions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.questionnaire_versions ENABLE ROW LEVEL SECURITY;

--
-- Name: questionnaire_versions questionnaire_versions_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY questionnaire_versions_public_read ON public.questionnaire_versions FOR SELECT TO authenticated, anon USING ((status = 'published'::text));

--
-- Name: support_inquiries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.support_inquiries ENABLE ROW LEVEL SECURITY;

--
-- Name: support_inquiries support_inquiries_owner_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY support_inquiries_owner_read ON public.support_inquiries FOR SELECT TO authenticated USING (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id)));

--
-- Name: taste_card_generation_attempts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taste_card_generation_attempts ENABLE ROW LEVEL SECURITY;

--
-- Name: taste_cards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taste_cards ENABLE ROW LEVEL SECURITY;

--
-- Name: user_account_deletions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_account_deletions ENABLE ROW LEVEL SECURITY;

--
-- Name: user_account_deletions user_account_deletions_restore_service_only; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_account_deletions_restore_service_only ON public.user_account_deletions FOR SELECT TO authenticated USING (false);

--
-- Name: user_consents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_consents ENABLE ROW LEVEL SECURITY;

--
-- Name: user_consents user_consents_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_consents_owner_select ON public.user_consents FOR SELECT TO authenticated USING (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id)));

--
-- Name: user_drink_interests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_drink_interests ENABLE ROW LEVEL SECURITY;

--
-- Name: user_drink_interests user_drink_interests_owner_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_drink_interests_owner_delete ON public.user_drink_interests FOR DELETE TO authenticated USING (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id)));

--
-- Name: user_drink_interests user_drink_interests_owner_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_drink_interests_owner_insert ON public.user_drink_interests FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id)));

--
-- Name: user_drink_interests user_drink_interests_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_drink_interests_owner_select ON public.user_drink_interests FOR SELECT TO authenticated USING (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id)));

--
-- Name: user_liked_drink_cards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_liked_drink_cards ENABLE ROW LEVEL SECURITY;

--
-- Name: user_liked_drink_cards user_liked_drink_cards_owner_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_liked_drink_cards_owner_delete ON public.user_liked_drink_cards FOR DELETE TO authenticated USING (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id)));

--
-- Name: user_liked_drink_cards user_liked_drink_cards_owner_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_liked_drink_cards_owner_insert ON public.user_liked_drink_cards FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id) AND (EXISTS ( SELECT 1
   FROM (public.taste_cards result_summary
     JOIN public.drink_records drink_record ON ((drink_record.id = result_summary.drink_record_id)))
  WHERE ((result_summary.id = user_liked_drink_cards.drink_result_summary_id) AND (drink_record.user_id = user_liked_drink_cards.user_id) AND (drink_record.deleted_at IS NULL))))));

--
-- Name: user_liked_drink_cards user_liked_drink_cards_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_liked_drink_cards_owner_select ON public.user_liked_drink_cards FOR SELECT TO authenticated USING (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id) AND (EXISTS ( SELECT 1
   FROM (public.taste_cards result_summary
     JOIN public.drink_records drink_record ON ((drink_record.id = result_summary.drink_record_id)))
  WHERE ((result_summary.id = user_liked_drink_cards.drink_result_summary_id) AND (drink_record.user_id = user_liked_drink_cards.user_id) AND (drink_record.deleted_at IS NULL))))));

--
-- Name: user_saved_articles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_saved_articles ENABLE ROW LEVEL SECURITY;

--
-- Name: user_saved_articles user_saved_articles_owner_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_saved_articles_owner_delete ON public.user_saved_articles FOR DELETE TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) AND public.soolgyul_account_active(user_id)));

--
-- Name: user_saved_articles user_saved_articles_owner_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_saved_articles_owner_insert ON public.user_saved_articles FOR INSERT TO authenticated WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND public.soolgyul_account_active(user_id) AND (EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = user_saved_articles.article_id) AND (article.status = 'published'::text) AND (article.published_at IS NOT NULL) AND (article.published_at <= now()))))));

--
-- Name: user_saved_articles user_saved_articles_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_saved_articles_owner_select ON public.user_saved_articles FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) AND public.soolgyul_account_active(user_id) AND (EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = user_saved_articles.article_id) AND (article.status = 'published'::text) AND (article.published_at IS NOT NULL) AND (article.published_at <= now()))))));

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: users users_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_owner_select ON public.users FOR SELECT TO authenticated USING (((id = auth.uid()) AND public.soolgyul_account_active(id)));

--
-- Name: withdrawn_drink_records; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.withdrawn_drink_records ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

--
-- Name: FUNCTION apply_sensory_product_claims(item_id uuid, source jsonb, entry jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.apply_sensory_product_claims(item_id uuid, source jsonb, entry jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.apply_sensory_product_claims(item_id uuid, source jsonb, entry jsonb) TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_text_array_is_valid(input_values text[], max_items integer, key_pattern text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_text_array_is_valid(input_values text[], max_items integer, key_pattern text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_text_array_is_valid(input_values text[], max_items integer, key_pattern text) TO service_role;

--
-- Name: FUNCTION valid_coded_sensory(p jsonb, item_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.valid_coded_sensory(p jsonb, item_id uuid) TO anon;
GRANT ALL ON FUNCTION public.valid_coded_sensory(p jsonb, item_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.valid_coded_sensory(p jsonb, item_id uuid) TO service_role;

--
-- Name: FUNCTION valid_product_sensory_facts(p jsonb, item_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.valid_product_sensory_facts(p jsonb, item_id uuid) TO anon;
GRANT ALL ON FUNCTION public.valid_product_sensory_facts(p jsonb, item_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.valid_product_sensory_facts(p jsonb, item_id uuid) TO service_role;

--
-- Name: FUNCTION valid_product_sensory_semantics(p jsonb, item_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.valid_product_sensory_semantics(p jsonb, item_id uuid) TO anon;
GRANT ALL ON FUNCTION public.valid_product_sensory_semantics(p jsonb, item_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.valid_product_sensory_semantics(p jsonb, item_id uuid) TO service_role;

--
-- Name: TABLE alcohol_tasting_profiles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.alcohol_tasting_profiles TO service_role;

--
-- Name: FUNCTION assert_product_sensory_catalog_sources(entry jsonb, p public.alcohol_tasting_profiles); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assert_product_sensory_catalog_sources(entry jsonb, p public.alcohol_tasting_profiles) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assert_product_sensory_catalog_sources(entry jsonb, p public.alcohol_tasting_profiles) TO service_role;

--
-- Name: FUNCTION coded_sensory_evidence_matches(coded jsonb, entry jsonb, proof jsonb, semantic boolean); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.coded_sensory_evidence_matches(coded jsonb, entry jsonb, proof jsonb, semantic boolean) TO anon;
GRANT ALL ON FUNCTION public.coded_sensory_evidence_matches(coded jsonb, entry jsonb, proof jsonb, semantic boolean) TO authenticated;
GRANT ALL ON FUNCTION public.coded_sensory_evidence_matches(coded jsonb, entry jsonb, proof jsonb, semantic boolean) TO service_role;

--
-- Name: FUNCTION compact_product_sensory_notes_batch(entries jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.compact_product_sensory_notes_batch(entries jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.compact_product_sensory_notes_batch(entries jsonb) TO service_role;

--
-- Name: FUNCTION encode_sensory_note_evidence(profile jsonb, collection text, fields text[]); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.encode_sensory_note_evidence(profile jsonb, collection text, fields text[]) TO anon;
GRANT ALL ON FUNCTION public.encode_sensory_note_evidence(profile jsonb, collection text, fields text[]) TO authenticated;
GRANT ALL ON FUNCTION public.encode_sensory_note_evidence(profile jsonb, collection text, fields text[]) TO service_role;

--
-- Name: FUNCTION extract_coded_sensory(profile jsonb, collection text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.extract_coded_sensory(profile jsonb, collection text) TO anon;
GRANT ALL ON FUNCTION public.extract_coded_sensory(profile jsonb, collection text) TO authenticated;
GRANT ALL ON FUNCTION public.extract_coded_sensory(profile jsonb, collection text) TO service_role;

--
-- Name: FUNCTION invalidate_product_sensory_facts(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.invalidate_product_sensory_facts() FROM PUBLIC;
GRANT ALL ON FUNCTION public.invalidate_product_sensory_facts() TO service_role;

--
-- Name: FUNCTION refresh_product_sensory_grades_batch(entries jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.refresh_product_sensory_grades_batch(entries jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.refresh_product_sensory_grades_batch(entries jsonb) TO service_role;

--
-- Name: FUNCTION sensory_item_assignment_snapshot(i jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensory_item_assignment_snapshot(i jsonb) TO anon;
GRANT ALL ON FUNCTION public.sensory_item_assignment_snapshot(i jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.sensory_item_assignment_snapshot(i jsonb) TO service_role;

--
-- Name: FUNCTION sensory_literal_balanced_acid_mouthfeel(p text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensory_literal_balanced_acid_mouthfeel(p text) TO anon;
GRANT ALL ON FUNCTION public.sensory_literal_balanced_acid_mouthfeel(p text) TO authenticated;
GRANT ALL ON FUNCTION public.sensory_literal_balanced_acid_mouthfeel(p text) TO service_role;

--
-- Name: FUNCTION sensory_literal_cold_sake_oak(p text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensory_literal_cold_sake_oak(p text) TO anon;
GRANT ALL ON FUNCTION public.sensory_literal_cold_sake_oak(p text) TO authenticated;
GRANT ALL ON FUNCTION public.sensory_literal_cold_sake_oak(p text) TO service_role;

--
-- Name: FUNCTION sensory_literal_fruit_aroma_through_finish(p text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensory_literal_fruit_aroma_through_finish(p text) TO anon;
GRANT ALL ON FUNCTION public.sensory_literal_fruit_aroma_through_finish(p text) TO authenticated;
GRANT ALL ON FUNCTION public.sensory_literal_fruit_aroma_through_finish(p text) TO service_role;

--
-- Name: FUNCTION sensory_literal_gold_fruit_opening(p text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensory_literal_gold_fruit_opening(p text) TO anon;
GRANT ALL ON FUNCTION public.sensory_literal_gold_fruit_opening(p text) TO authenticated;
GRANT ALL ON FUNCTION public.sensory_literal_gold_fruit_opening(p text) TO service_role;

--
-- Name: FUNCTION sensory_literal_lively_smooth_fruit_finish(p text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensory_literal_lively_smooth_fruit_finish(p text) TO anon;
GRANT ALL ON FUNCTION public.sensory_literal_lively_smooth_fruit_finish(p text) TO authenticated;
GRANT ALL ON FUNCTION public.sensory_literal_lively_smooth_fruit_finish(p text) TO service_role;

--
-- Name: FUNCTION sensory_literal_oak_named_long_aroma(p text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensory_literal_oak_named_long_aroma(p text) TO anon;
GRANT ALL ON FUNCTION public.sensory_literal_oak_named_long_aroma(p text) TO authenticated;
GRANT ALL ON FUNCTION public.sensory_literal_oak_named_long_aroma(p text) TO service_role;

--
-- Name: FUNCTION sensory_literal_oak_vanilla_aroma(p text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensory_literal_oak_vanilla_aroma(p text) TO anon;
GRANT ALL ON FUNCTION public.sensory_literal_oak_vanilla_aroma(p text) TO authenticated;
GRANT ALL ON FUNCTION public.sensory_literal_oak_vanilla_aroma(p text) TO service_role;

--
-- Name: FUNCTION sensory_literal_omachi_rice(p text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensory_literal_omachi_rice(p text) TO anon;
GRANT ALL ON FUNCTION public.sensory_literal_omachi_rice(p text) TO authenticated;
GRANT ALL ON FUNCTION public.sensory_literal_omachi_rice(p text) TO service_role;

--
-- Name: FUNCTION sensory_literal_rice_water_sake(p text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensory_literal_rice_water_sake(p text) TO anon;
GRANT ALL ON FUNCTION public.sensory_literal_rice_water_sake(p text) TO authenticated;
GRANT ALL ON FUNCTION public.sensory_literal_rice_water_sake(p text) TO service_role;

--
-- Name: FUNCTION sensory_note_phase_matches(section text, source_field text, excerpt text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sensory_note_phase_matches(section text, source_field text, excerpt text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sensory_note_phase_matches(section text, source_field text, excerpt text) TO service_role;

--
-- Name: FUNCTION sensory_oak_long_aroma_clause(p text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensory_oak_long_aroma_clause(p text) TO anon;
GRANT ALL ON FUNCTION public.sensory_oak_long_aroma_clause(p text) TO authenticated;
GRANT ALL ON FUNCTION public.sensory_oak_long_aroma_clause(p text) TO service_role;

--
-- Name: FUNCTION sensory_semantic_phase_matches(identity jsonb, proof jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sensory_semantic_phase_matches(identity jsonb, proof jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sensory_semantic_phase_matches(identity jsonb, proof jsonb) TO service_role;

--
-- Name: FUNCTION sensory_source_snapshot(p jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensory_source_snapshot(p jsonb) TO anon;
GRANT ALL ON FUNCTION public.sensory_source_snapshot(p jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.sensory_source_snapshot(p jsonb) TO service_role;

--
-- Name: FUNCTION set_product_sensory_catalog_batch(entries jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_product_sensory_catalog_batch(entries jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_product_sensory_catalog_batch(entries jsonb) TO service_role;

--
-- Name: FUNCTION set_product_sensory_facts_batch(entries jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_product_sensory_facts_batch(entries jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_product_sensory_facts_batch(entries jsonb) TO service_role;

--
-- Name: FUNCTION soolgyul_account_active(target_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_account_active(target_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_account_active(target_user_id uuid) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_account_active(target_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_account_active(target_user_id uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_admin_change_editorial_status(article_id uuid, next_status text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_admin_change_editorial_status(article_id uuid, next_status text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_admin_change_editorial_status(article_id uuid, next_status text) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_admin_change_editorial_status(article_id uuid, next_status text) TO authenticated;

--
-- Name: FUNCTION soolgyul_admin_delete_editorial_draft(article_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_admin_delete_editorial_draft(article_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_admin_delete_editorial_draft(article_id uuid) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_admin_delete_editorial_draft(article_id uuid) TO authenticated;

--
-- Name: FUNCTION soolgyul_admin_has_role(required_roles text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_admin_has_role(required_roles text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_admin_has_role(required_roles text[]) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_admin_has_role(required_roles text[]) TO authenticated;

--
-- Name: FUNCTION soolgyul_admin_save_editorial_article(article_id uuid, category_id uuid, article_slug text, article_title text, article_summary text, article_body_markdown text, article_tags text[], read_minutes integer, recommended boolean, feature_rank integer, article_status text, interest_group_ids uuid[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_admin_save_editorial_article(article_id uuid, category_id uuid, article_slug text, article_title text, article_summary text, article_body_markdown text, article_tags text[], read_minutes integer, recommended boolean, feature_rank integer, article_status text, interest_group_ids uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_admin_save_editorial_article(article_id uuid, category_id uuid, article_slug text, article_title text, article_summary text, article_body_markdown text, article_tags text[], read_minutes integer, recommended boolean, feature_rank integer, article_status text, interest_group_ids uuid[]) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_admin_save_editorial_article(article_id uuid, category_id uuid, article_slug text, article_title text, article_summary text, article_body_markdown text, article_tags text[], read_minutes integer, recommended boolean, feature_rank integer, article_status text, interest_group_ids uuid[]) TO authenticated;

--
-- Name: FUNCTION soolgyul_build_taste_card_result(target_result_summary_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_build_taste_card_result(target_result_summary_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_build_taste_card_result(target_result_summary_id uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assert_item_assignment(item_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assert_item_assignment(item_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assert_item_assignment(item_id uuid) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assert_item_assignment(item_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assert_item_assignment(item_id uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assignment_category_validate(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assignment_category_validate() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_category_validate() TO anon;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_category_validate() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_category_validate() TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assignment_issue(code text, field text, key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assignment_issue(code text, field text, key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_issue(code text, field text, key text) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_issue(code text, field text, key text) TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_issue(code text, field text, key text) TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assignment_issues(category text, style text, target text, classifications text[], ingredients text[], processes text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assignment_issues(category text, style text, target text, classifications text[], ingredients text[], processes text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_issues(category text, style text, target text, classifications text[], ingredients text[], processes text[]) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_issues(category text, style text, target text, classifications text[], ingredients text[], processes text[]) TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_issues(category text, style text, target text, classifications text[], ingredients text[], processes text[]) TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assignment_row_validate(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assignment_row_validate() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_row_validate() TO anon;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_row_validate() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_row_validate() TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assignment_term_validate(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assignment_term_validate() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_term_validate() TO anon;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_term_validate() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_term_validate() TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assignment_write_lock(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assignment_write_lock() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_write_lock() TO anon;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_write_lock() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_write_lock() TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_http_url_is_valid(input_value text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_http_url_is_valid(input_value text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_http_url_is_valid(input_value text) TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_primary_media_rows_v1(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_primary_media_rows_v1() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_primary_media_rows_v1() TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_catalog_primary_media_rows_v1() TO anon;
GRANT ALL ON FUNCTION public.soolgyul_catalog_primary_media_rows_v1() TO authenticated;

--
-- Name: FUNCTION soolgyul_catalog_search_projection_rows_v1(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_search_projection_rows_v1() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_search_projection_rows_v1() TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_catalog_search_projection_rows_v1() TO anon;
GRANT ALL ON FUNCTION public.soolgyul_catalog_search_projection_rows_v1() TO authenticated;

--
-- Name: FUNCTION soolgyul_catalog_term_keys_are_active(input_keys text[], allowed_term_types text[], required_sections text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_term_keys_are_active(input_keys text[], allowed_term_types text[], required_sections text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_term_keys_are_active(input_keys text[], allowed_term_types text[], required_sections text[]) TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_timestamp_text_is_valid(input_value text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_timestamp_text_is_valid(input_value text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_timestamp_text_is_valid(input_value text) TO service_role;

--
-- Name: FUNCTION soolgyul_complete_my_profile_v1(p_idempotency_key uuid, p_display_name text, p_birth_year integer, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_complete_my_profile_v1(p_idempotency_key uuid, p_display_name text, p_birth_year integer, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_complete_my_profile_v1(p_idempotency_key uuid, p_display_name text, p_birth_year integer, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean) TO service_role;

--
-- Name: FUNCTION soolgyul_complete_my_profile_v2(p_idempotency_key uuid, p_display_name text, p_birth_year integer, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text, p_gender_consent_accepted boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_complete_my_profile_v2(p_idempotency_key uuid, p_display_name text, p_birth_year integer, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text, p_gender_consent_accepted boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_complete_my_profile_v2(p_idempotency_key uuid, p_display_name text, p_birth_year integer, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text, p_gender_consent_accepted boolean) TO service_role;

--
-- Name: FUNCTION soolgyul_complete_my_profile_v3(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text, p_gender_consent_accepted boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_complete_my_profile_v3(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text, p_gender_consent_accepted boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_complete_my_profile_v3(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text, p_gender_consent_accepted boolean) TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_complete_my_profile_v3(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text, p_gender_consent_accepted boolean) TO service_role;

--
-- Name: FUNCTION soolgyul_convert_anonymous_taste_card(target_user_id uuid, target_result_summary_id uuid, target_anonymous_session_digest text, target_idempotency_key uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_convert_anonymous_taste_card(target_user_id uuid, target_result_summary_id uuid, target_anonymous_session_digest text, target_idempotency_key uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_convert_anonymous_taste_card(target_user_id uuid, target_result_summary_id uuid, target_anonymous_session_digest text, target_idempotency_key uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_enforce_drink_interest_limit(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_enforce_drink_interest_limit() FROM PUBLIC;

--
-- Name: FUNCTION soolgyul_finalize_taste_card_generation(input_bundle jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_finalize_taste_card_generation(input_bundle jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_finalize_taste_card_generation(input_bundle jsonb) TO service_role;

--
-- Name: FUNCTION soolgyul_finalize_withdrawn_account_data(target_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_finalize_withdrawn_account_data(target_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_finalize_withdrawn_account_data(target_user_id uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_get_marketing_consent(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_marketing_consent() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_marketing_consent() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_get_marketing_consent() TO service_role;

--
-- Name: FUNCTION soolgyul_get_my_deletion_state(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_my_deletion_state() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_my_deletion_state() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_get_my_deletion_state() TO service_role;

--
-- Name: FUNCTION soolgyul_get_my_profile_preferences(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_my_profile_preferences() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_my_profile_preferences() TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_get_my_profile_preferences() TO authenticated;

--
-- Name: FUNCTION soolgyul_get_my_profile_status_v1(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_my_profile_status_v1() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_my_profile_status_v1() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_get_my_profile_status_v1() TO service_role;

--
-- Name: FUNCTION soolgyul_get_owned_taste_card_result(target_result_summary_id uuid, target_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_owned_taste_card_result(target_result_summary_id uuid, target_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_owned_taste_card_result(target_result_summary_id uuid, target_user_id uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_get_sensory_question_context(target_catalog_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_sensory_question_context(target_catalog_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_sensory_question_context(target_catalog_id uuid) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_get_sensory_question_context(target_catalog_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_get_sensory_question_context(target_catalog_id uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_get_taste_card_result_for_attempt(target_attempt_ref text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_taste_card_result_for_attempt(target_attempt_ref text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_taste_card_result_for_attempt(target_attempt_ref text) TO service_role;

--
-- Name: FUNCTION soolgyul_guard_final_drink_record_identity(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_guard_final_drink_record_identity() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_guard_final_drink_record_identity() TO service_role;

--
-- Name: FUNCTION soolgyul_guard_questionnaire_content(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.soolgyul_guard_questionnaire_content() TO anon;
GRANT ALL ON FUNCTION public.soolgyul_guard_questionnaire_content() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_guard_questionnaire_content() TO service_role;

--
-- Name: FUNCTION soolgyul_guard_questionnaire_version(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.soolgyul_guard_questionnaire_version() TO anon;
GRANT ALL ON FUNCTION public.soolgyul_guard_questionnaire_version() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_guard_questionnaire_version() TO service_role;

--
-- Name: FUNCTION soolgyul_guard_taste_card_content(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_guard_taste_card_content() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_guard_taste_card_content() TO service_role;

--
-- Name: FUNCTION soolgyul_invalidate_deletion_revocation_on_login(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_invalidate_deletion_revocation_on_login() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_invalidate_deletion_revocation_on_login() TO service_role;

--
-- Name: FUNCTION soolgyul_lower_catalog_text_array(values_to_normalize text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_lower_catalog_text_array(values_to_normalize text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_lower_catalog_text_array(values_to_normalize text[]) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_lower_catalog_text_array(values_to_normalize text[]) TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_lower_catalog_text_array(values_to_normalize text[]) TO service_role;

--
-- Name: FUNCTION soolgyul_mark_deletion_provider_revoked(target_user_id uuid, requested_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_mark_deletion_provider_revoked(target_user_id uuid, requested_at timestamp with time zone) FROM PUBLIC;

--
-- Name: FUNCTION soolgyul_mark_deletion_provider_revoked_v2(target_user_id uuid, requested_at timestamp with time zone, authenticated_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_mark_deletion_provider_revoked_v2(target_user_id uuid, requested_at timestamp with time zone, authenticated_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_mark_deletion_provider_revoked_v2(target_user_id uuid, requested_at timestamp with time zone, authenticated_at timestamp with time zone) TO service_role;

--
-- Name: FUNCTION soolgyul_normalize_catalog_text(input_value text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.soolgyul_normalize_catalog_text(input_value text) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_normalize_catalog_text(input_value text) TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_normalize_catalog_text(input_value text) TO service_role;

--
-- Name: FUNCTION soolgyul_prepare_admin_editorial_article(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_prepare_admin_editorial_article() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_prepare_admin_editorial_article() TO service_role;

--
-- Name: FUNCTION soolgyul_prevent_populated_tasting_profile_retargeting(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.soolgyul_prevent_populated_tasting_profile_retargeting() TO anon;
GRANT ALL ON FUNCTION public.soolgyul_prevent_populated_tasting_profile_retargeting() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_prevent_populated_tasting_profile_retargeting() TO service_role;

--
-- Name: FUNCTION soolgyul_prevent_served_item_category_change(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.soolgyul_prevent_served_item_category_change() TO anon;
GRANT ALL ON FUNCTION public.soolgyul_prevent_served_item_category_change() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_prevent_served_item_category_change() TO service_role;

--
-- Name: FUNCTION soolgyul_protect_catalog_term_identity(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_protect_catalog_term_identity() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_protect_catalog_term_identity() TO service_role;

--
-- Name: FUNCTION soolgyul_provision_auth_user(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_provision_auth_user() FROM PUBLIC;

--
-- Name: FUNCTION soolgyul_related_editorial_articles(p_article_id uuid, p_result_limit integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_related_editorial_articles(p_article_id uuid, p_result_limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_related_editorial_articles(p_article_id uuid, p_result_limit integer) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_related_editorial_articles(p_article_id uuid, p_result_limit integer) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_related_editorial_articles(p_article_id uuid, p_result_limit integer) TO authenticated;

--
-- Name: FUNCTION soolgyul_replace_my_drink_interests(p_interest_group_keys text[], p_idempotency_key uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_replace_my_drink_interests(p_interest_group_keys text[], p_idempotency_key uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_replace_my_drink_interests(p_interest_group_keys text[], p_idempotency_key uuid) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_replace_my_drink_interests(p_interest_group_keys text[], p_idempotency_key uuid) TO authenticated;

--
-- Name: FUNCTION soolgyul_request_my_account_deletion(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_request_my_account_deletion() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_request_my_account_deletion() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_request_my_account_deletion() TO service_role;

--
-- Name: FUNCTION soolgyul_restore_my_account(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_restore_my_account() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_restore_my_account() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_restore_my_account() TO service_role;

--
-- Name: FUNCTION soolgyul_run_account_retention_job(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_run_account_retention_job() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_run_account_retention_job() TO service_role;

--
-- Name: FUNCTION soolgyul_search_alcohol_catalog(target_query text, target_limit integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer) TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer) TO service_role;

--
-- Name: FUNCTION soolgyul_sensory_knowledge_is_valid(value jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.soolgyul_sensory_knowledge_is_valid(value jsonb) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_sensory_knowledge_is_valid(value jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_sensory_knowledge_is_valid(value jsonb) TO service_role;

--
-- Name: FUNCTION soolgyul_set_marketing_consent(p_accepted boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_set_marketing_consent(p_accepted boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_set_marketing_consent(p_accepted boolean) TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_set_marketing_consent(p_accepted boolean) TO service_role;

--
-- Name: FUNCTION soolgyul_strip_retained_card_links(value jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_strip_retained_card_links(value jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_strip_retained_card_links(value jsonb) TO service_role;

--
-- Name: FUNCTION soolgyul_submit_support_inquiry(p_id uuid, p_inquiry_type text, p_reply_email text, p_content text, p_attachment_paths text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_submit_support_inquiry(p_id uuid, p_inquiry_type text, p_reply_email text, p_content text, p_attachment_paths text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_submit_support_inquiry(p_id uuid, p_inquiry_type text, p_reply_email text, p_content text, p_attachment_paths text[]) TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_submit_support_inquiry(p_id uuid, p_inquiry_type text, p_reply_email text, p_content text, p_attachment_paths text[]) TO service_role;

--
-- Name: FUNCTION soolgyul_touch_editorial_updated_at(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_touch_editorial_updated_at() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_touch_editorial_updated_at() TO service_role;

--
-- Name: FUNCTION soolgyul_update_my_display_name(p_display_name text, p_idempotency_key uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_update_my_display_name(p_display_name text, p_idempotency_key uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_update_my_display_name(p_display_name text, p_idempotency_key uuid) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_update_my_display_name(p_display_name text, p_idempotency_key uuid) TO authenticated;

--
-- Name: FUNCTION soolgyul_validate_active_alcohol_category_assignment(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.soolgyul_validate_active_alcohol_category_assignment() TO anon;
GRANT ALL ON FUNCTION public.soolgyul_validate_active_alcohol_category_assignment() TO authenticated;
GRANT ALL ON FUNCTION public.soolgyul_validate_active_alcohol_category_assignment() TO service_role;

--
-- Name: FUNCTION soolgyul_validate_alcohol_item_catalog_terms(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_validate_alcohol_item_catalog_terms() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_validate_alcohol_item_catalog_terms() TO service_role;

--
-- Name: FUNCTION soolgyul_validate_tasting_profile_catalog_terms(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_validate_tasting_profile_catalog_terms() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_validate_tasting_profile_catalog_terms() TO service_role;

--
-- Name: TABLE admin_user_roles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.admin_user_roles TO service_role;
GRANT SELECT ON TABLE public.admin_user_roles TO authenticated;

--
-- Name: TABLE alcohol_categories; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.alcohol_categories TO service_role;
GRANT SELECT ON TABLE public.alcohol_categories TO anon;
GRANT SELECT ON TABLE public.alcohol_categories TO authenticated;

--
-- Name: TABLE alcohol_interest_group_categories; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.alcohol_interest_group_categories TO service_role;
GRANT SELECT ON TABLE public.alcohol_interest_group_categories TO anon;
GRANT SELECT ON TABLE public.alcohol_interest_group_categories TO authenticated;

--
-- Name: TABLE alcohol_interest_groups; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.alcohol_interest_groups TO service_role;
GRANT SELECT ON TABLE public.alcohol_interest_groups TO anon;
GRANT SELECT ON TABLE public.alcohol_interest_groups TO authenticated;

--
-- Name: TABLE alcohol_items; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.alcohol_items TO service_role;

--
-- Name: TABLE catalog_media_assets; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.catalog_media_assets TO service_role;

--
-- Name: TABLE catalog_media_fallbacks; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.catalog_media_fallbacks TO service_role;

--
-- Name: TABLE catalog_search_projection_v1; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.catalog_search_projection_v1 TO anon;
GRANT ALL ON TABLE public.catalog_search_projection_v1 TO authenticated;
GRANT ALL ON TABLE public.catalog_search_projection_v1 TO service_role;

--
-- Name: TABLE catalog_terms; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE public.catalog_terms TO service_role;

--
-- Name: TABLE drink_record_answers; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.drink_record_answers TO service_role;
GRANT SELECT ON TABLE public.drink_record_answers TO authenticated;

--
-- Name: TABLE drink_records; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.drink_records TO service_role;
GRANT SELECT,INSERT,UPDATE ON TABLE public.drink_records TO authenticated;

--
-- Name: TABLE editorial_article_interest_groups; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.editorial_article_interest_groups TO service_role;
GRANT SELECT ON TABLE public.editorial_article_interest_groups TO anon;
GRANT SELECT,INSERT,DELETE ON TABLE public.editorial_article_interest_groups TO authenticated;

--
-- Name: TABLE editorial_article_media_assets; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.editorial_article_media_assets TO service_role;
GRANT SELECT ON TABLE public.editorial_article_media_assets TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.editorial_article_media_assets TO authenticated;

--
-- Name: TABLE editorial_articles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.editorial_articles TO service_role;
GRANT SELECT ON TABLE public.editorial_articles TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.editorial_articles TO authenticated;

--
-- Name: TABLE editorial_categories; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.editorial_categories TO service_role;
GRANT SELECT ON TABLE public.editorial_categories TO anon;
GRANT SELECT ON TABLE public.editorial_categories TO authenticated;

--
-- Name: TABLE questionnaire_options; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.questionnaire_options TO service_role;
GRANT SELECT ON TABLE public.questionnaire_options TO anon;
GRANT SELECT ON TABLE public.questionnaire_options TO authenticated;

--
-- Name: TABLE questionnaire_questions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.questionnaire_questions TO service_role;
GRANT SELECT ON TABLE public.questionnaire_questions TO anon;
GRANT SELECT ON TABLE public.questionnaire_questions TO authenticated;

--
-- Name: TABLE questionnaire_versions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.questionnaire_versions TO service_role;
GRANT SELECT ON TABLE public.questionnaire_versions TO anon;
GRANT SELECT ON TABLE public.questionnaire_versions TO authenticated;

--
-- Name: TABLE support_inquiries; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.support_inquiries TO service_role;
GRANT SELECT ON TABLE public.support_inquiries TO authenticated;

--
-- Name: TABLE taste_card_generation_attempts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taste_card_generation_attempts TO service_role;

--
-- Name: TABLE taste_cards; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taste_cards TO service_role;

--
-- Name: COLUMN taste_cards.id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(id) ON TABLE public.taste_cards TO authenticated;

--
-- Name: COLUMN taste_cards.drink_record_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(drink_record_id) ON TABLE public.taste_cards TO authenticated;

--
-- Name: TABLE user_account_deletions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.user_account_deletions TO service_role;
GRANT SELECT ON TABLE public.user_account_deletions TO authenticated;

--
-- Name: TABLE user_consents; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.user_consents TO service_role;
GRANT SELECT ON TABLE public.user_consents TO authenticated;

--
-- Name: TABLE user_drink_interests; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.user_drink_interests TO service_role;
GRANT SELECT ON TABLE public.user_drink_interests TO authenticated;

--
-- Name: TABLE user_liked_drink_cards; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.user_liked_drink_cards TO service_role;
GRANT SELECT,INSERT,DELETE ON TABLE public.user_liked_drink_cards TO authenticated;

--
-- Name: TABLE user_saved_articles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.user_saved_articles TO service_role;
GRANT SELECT,INSERT,DELETE ON TABLE public.user_saved_articles TO authenticated;

--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.users TO service_role;
GRANT SELECT ON TABLE public.users TO authenticated;

--
-- Name: TABLE withdrawn_drink_records; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.withdrawn_drink_records TO service_role;

--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

--
-- PostgreSQL database dump complete
--

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('soolgyul-private','soolgyul-private',false,10485760,'{image/jpeg,image/png,image/webp}'),
  ('soolgyul-catalog-private','soolgyul-catalog-private',false,20971520,'{image/jpeg,image/png,image/webp}'),
  ('soolgyul-catalog-public','soolgyul-catalog-public',true,5242880,'{image/jpeg,image/png,image/webp}'),
  ('soolgyul-editorial','soolgyul-editorial',true,10485760,'{image/jpeg,image/png,image/webp}'),
  ('soolgyul-catalog-snapshots','soolgyul-catalog-snapshots',false,104857600,'{application/gzip}'),
  ('alcohol-product-images','alcohol-product-images',true,null,'{image/webp}')
on conflict (id) do update set public = excluded.public,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

CREATE POLICY soolgyul_editorial_media_admin_delete ON storage.objects FOR DELETE TO authenticated USING (((bucket_id = 'soolgyul-editorial'::text) AND public.soolgyul_admin_has_role()));
CREATE POLICY soolgyul_editorial_media_admin_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'soolgyul-editorial'::text) AND public.soolgyul_admin_has_role()));
CREATE POLICY soolgyul_editorial_media_admin_update ON storage.objects FOR UPDATE TO authenticated USING (((bucket_id = 'soolgyul-editorial'::text) AND public.soolgyul_admin_has_role())) WITH CHECK (((bucket_id = 'soolgyul-editorial'::text) AND public.soolgyul_admin_has_role()));
CREATE POLICY soolgyul_editorial_media_public_select ON storage.objects FOR SELECT TO authenticated, anon USING ((bucket_id = 'soolgyul-editorial'::text));
CREATE POLICY soolgyul_private_owner_delete ON storage.objects FOR DELETE TO authenticated USING (((bucket_id = 'soolgyul-private'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND public.soolgyul_account_active(auth.uid())));
CREATE POLICY soolgyul_private_owner_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'soolgyul-private'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND public.soolgyul_account_active(auth.uid())));
CREATE POLICY soolgyul_private_owner_read ON storage.objects FOR SELECT TO authenticated USING (((bucket_id = 'soolgyul-private'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND public.soolgyul_account_active(auth.uid())));
CREATE POLICY soolgyul_private_owner_update ON storage.objects FOR UPDATE TO authenticated USING (((bucket_id = 'soolgyul-private'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND public.soolgyul_account_active(auth.uid()))) WITH CHECK (((bucket_id = 'soolgyul-private'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND public.soolgyul_account_active(auth.uid())));

create trigger soolgyul_auth_user_provision after insert on auth.users
  for each row execute function public.soolgyul_provision_auth_user();
create trigger soolgyul_deletion_reauthentication after update of last_sign_in_at on auth.users
  for each row execute function public.soolgyul_invalidate_deletion_revocation_on_login();

select cron.schedule('soolgyul-account-retention', '0 * * * *',
  'select public.soolgyul_run_account_retention_job();');
