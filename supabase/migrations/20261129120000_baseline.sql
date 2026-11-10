-- Baseline: the live Supabase schema as of 2026-11-10, replacing all earlier migrations.

create extension if not exists pgcrypto with schema extensions;
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
-- Dumped by pg_dump version 17.11 (Homebrew)

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
      and account.purged_at is null
  );
$$;

--
-- Name: FUNCTION soolgyul_admin_has_role(required_roles text[]); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_admin_has_role(required_roles text[]) IS 'Authoritative RLS helper for active editor/admin access. Role grants cannot be changed by an authenticated client.';

--
-- Name: soolgyul_admin_save_editorial_article(uuid, text, text, text[], text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_admin_save_editorial_article(article_id uuid, article_body text, article_status text, interest_keys text[], instagram_link text DEFAULT NULL::text) RETURNS uuid
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
  if exists (
    select 1
    from unnest(coalesce(interest_keys, array[]::text[])) as input(interest_key)
    where not exists (
      select 1
      from public.alcohol_categories category
      where category.is_active
        and category.interest_key = input.interest_key
    )
  ) then
    raise exception 'unknown interest key' using errcode = '22023';
  end if;

  if article_id is null then
    insert into public.editorial_articles (body, status, instagram_url)
    values (
      coalesce(article_body, ''),
      article_status,
      nullif(btrim(instagram_link), '')
    )
    returning id into saved_id;
  else
    update public.editorial_articles
    set body = coalesce(article_body, ''),
        status = article_status,
        instagram_url = nullif(btrim(instagram_link), '')
    where id = article_id
      and (is_admin or (status = 'draft' and published_at is null))
    returning id into saved_id;

    if saved_id is null then
      raise exception 'article is not editable' using errcode = '42501';
    end if;
  end if;

  delete from public.editorial_article_interests
  where editorial_article_interests.article_id = saved_id;

  insert into public.editorial_article_interests (article_id, interest_key)
  select distinct saved_id, input.interest_key
  from unnest(coalesce(interest_keys, array[]::text[])) as input(interest_key);

  return saved_id;
end
$$;

--
-- Name: soolgyul_adult_profile_complete(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_adult_profile_complete(target_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.users profile_row
    where profile_row.id = target_user_id
      and profile_row.age_confirmed_at is not null
  )
  and (
    select count(distinct consent.consent_type) = 3
    from public.user_consents consent
    where consent.user_id = target_user_id
      and consent.withdrawn_at is null
      and (consent.consent_type, consent.document_version) in (
        ('age_19', 'self-attestation-v1'),
        ('terms', 'soolgyul-terms-v1'),
        ('privacy', 'soolgyul-privacy-v1')
      )
  );
$$;

--
-- Name: soolgyul_anonymize_discovery_events(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_anonymize_discovery_events(target_user_id uuid DEFAULT NULL::uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare changed integer;
begin
  update public.drink_discovery_events e
  set user_id = null,
    occurred_at = date_trunc('day', e.occurred_at, 'Asia/Seoul'),
    birth_year_band = extract(year from u.birth_date)::integer
      - extract(year from u.birth_date)::integer % 5,
    gender = case when u.gender_consent_accepted_at is not null then u.gender end
  from public.users u
  where e.user_id = u.id
    and (case when target_user_id is null
      then e.occurred_at < statement_timestamp() - interval '13 months'
      else e.user_id = target_user_id end);
  get diagnostics changed = row_count;
  return changed;
end;
$$;

--
-- Name: soolgyul_build_taste_card_result(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_build_taste_card_result(target_result_summary_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select jsonb_build_object(
    'wire_schema_version', 'taste-card-result-wire-v3',
    'result_id', summary_row.id::text,
    'record_id', record_row.id::text,
    'snapshot_ref', summary_row.snapshot_ref,
    'ownership_state', case
      when record_row.user_id is null then 'anonymous'
      else 'saved'
    end,
    'alcohol_identification', jsonb_build_object(
      'mode', 'catalog_match',
      'alcohol_item_id', record_row.alcohol_item_id,
      'alcohol_name_snapshot', item_row.name_ko,
      'category', category_row.category_key
    ),
    'rendered_snapshot', summary_row.rendered_snapshot,
    'created_at', summary_row.snapshot_created_at
  )
  from public.taste_cards summary_row
  join public.drink_records record_row
    on record_row.id = summary_row.drink_record_id
  join public.alcohol_items item_row
    on item_row.id = record_row.alcohol_item_id
  left join public.alcohol_categories category_row
    on category_row.id = item_row.alcohol_category_id
  where summary_row.lifecycle = 'final' and summary_row.id = target_result_summary_id
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
  errors := public.soolgyul_catalog_assignment_issues(category,item.style_key,'product',item.ingredient_keys,item.production_process_keys);
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
-- Name: soolgyul_catalog_assignment_issues(text, text, text, text[], text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_assignment_issues(category text, style text, target text, ingredients text[] DEFAULT '{}'::text[], processes text[] DEFAULT '{}'::text[]) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $_$
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
$_$;

--
-- Name: FUNCTION soolgyul_catalog_assignment_issues(category text, style text, target text, ingredients text[], processes text[]); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_catalog_assignment_issues(category text, style text, target text, ingredients text[], processes text[]) IS 'Read-only assignment audit against the active catalog terms; empty arrays mean unknown, not absence.';

--
-- Name: soolgyul_catalog_assignment_row_validate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_assignment_row_validate() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
begin
 if tg_op='UPDATE' and row(new.alcohol_category_id,new.style_key,new.ingredient_keys,new.production_process_keys)
 is not distinct from row(old.alcohol_category_id,old.style_key,old.ingredient_keys,old.production_process_keys) then return null; end if;
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
-- Name: soolgyul_catalog_primary_media_rows(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_primary_media_rows() RETURNS TABLE(catalog_media_asset_id uuid, alcohol_item_id uuid, media_path text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select media.id, item.id, media.media_path
  from public.alcohol_items item
  join public.catalog_media_assets media on media.alcohol_item_id = item.id
  where item.publish_status = 'published'
    and media.publish_status = 'published'
    and media.published_at is not null
$$;

--
-- Name: soolgyul_catalog_search_projection_rows(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_catalog_search_projection_rows() RETURNS TABLE(alcohol_item_id uuid, alcohol_release_id uuid, display_name text, secondary_name text, producer_or_brand_display text, category_key text, subcategory_key text, style_key text, country_code text, region_display text, abv_percent numeric, search_aliases text[], descriptor_keys text[], is_active boolean, published_at timestamp with time zone, updated_at timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;

--
-- Name: FUNCTION soolgyul_catalog_search_projection_rows(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.soolgyul_catalog_search_projection_rows() IS 'Reviewed public catalog rows. Exact release sensory overrides product fallback when available.';

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
        select 1 from public.catalog_taxonomy term
        where term.term_key=assigned.term_key and term.term_type=any(allowed_term_types)
          and term.is_active
          and (required_sections is null or term.applicable_sections && required_sections)
      )
    ),false
  )
$_$;

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
-- Name: soolgyul_complete_my_profile(uuid, text, date, boolean, text, text, text, boolean, boolean, boolean, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_complete_my_profile(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text DEFAULT NULL::text, p_gender_consent_accepted boolean DEFAULT false) RETURNS jsonb
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
  if p_birth_date is null or not isfinite(p_birth_date)
    or p_birth_date < date '1900-01-01' or p_birth_date > current_date then
    raise exception using errcode = '22023', message = 'birth_date_invalid';
  end if;
  if (p_gender is not null and p_gender not in ('male', 'female', 'other'))
    or (p_gender is not null and not coalesce(p_gender_consent_accepted, false))
    or (p_gender is null and coalesce(p_gender_consent_accepted, false)) then
    raise exception using errcode = '22023', message = 'gender_consent_invalid';
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

  if not coalesce(p_age_19_or_over_confirmed, false)
    or extract(year from current_date)::integer
      - extract(year from p_birth_date)::integer < 19
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
    return public.soolgyul_get_my_profile_status();
  end if;

  update public.users profile
  set display_name = normalized_display_name,
      age_confirmed_at = coalesce(profile.age_confirmed_at, accepted_timestamp),
      birth_date = p_birth_date,
      gender = p_gender,
      gender_consent_accepted_at = case when p_gender is null then null else accepted_timestamp end,
      gender_consent_version = case when p_gender is null then null else 'soolgyul-gender-v1' end,
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

  if not public.soolgyul_adult_profile_complete(target_user_id) then
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
-- Name: soolgyul_delete_owned_drink_record(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_delete_owned_drink_record(target_result_summary_id uuid, target_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  deleted_record_id uuid;
begin
  if not public.soolgyul_account_active(target_user_id) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  update public.drink_records record_row
    set deleted_at = now(),
        updated_at = now()
    from public.taste_cards summary_row
    where summary_row.id = target_result_summary_id
      and record_row.id = summary_row.drink_record_id
      and record_row.user_id = target_user_id
      and record_row.deleted_at is null
    returning record_row.id into deleted_record_id;

  if deleted_record_id is null then
    raise exception using errcode = 'P0002', message = 'owned result not found';
  end if;
  return deleted_record_id;
end;
$$;

--
-- Name: soolgyul_deletion_due_at(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_deletion_due_at(requested_at timestamp with time zone) RETURNS timestamp with time zone
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select requested_at + interval '30 days';
$$;

--
-- Name: soolgyul_editorial_object_editable(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_editorial_object_editable(object_path text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select public.soolgyul_admin_has_role(array['admin'])
    or (
      public.soolgyul_admin_has_role(array['editor'])
      and not exists (
        select 1
        from public.editorial_article_media_assets media
        join public.editorial_articles article on article.id = media.article_id
        where media.storage_bucket = 'soolgyul-editorial'
          and media.storage_object_path = object_path
          and article.status = 'published'
      )
    );
$$;

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
      and current_selection.interest_key = new.interest_key
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
  rendered_row jsonb := input_bundle->'rendered_view';
  snapshot_row jsonb := input_bundle->'semantic_snapshot';
  answer_row jsonb;
  generated_snapshot_id uuid := gen_random_uuid();
  principal_kind text := input_bundle #>> '{principal,kind}';
  selected_catalog_id uuid;
  resolved_alcohol_item_id uuid;
begin
  if jsonb_typeof(input_bundle) is distinct from 'object'
    or jsonb_typeof(request_row) is distinct from 'object'
    or jsonb_typeof(identification_row) is distinct from 'object'
    or jsonb_typeof(rendered_row) is distinct from 'object'
    or jsonb_typeof(snapshot_row) is distinct from 'object'
  then
    raise exception using
      errcode = '22023',
      message = 'taste card finalization bundle is invalid';
  end if;

  if input_bundle->>'wire_schema_version' is distinct from 'taste-card-result-wire-v3' then
    raise exception using
      errcode = '22023',
      message = 'taste card wire schema version is invalid';
  end if;

  if (
    rendered_row #>> '{metadata,schema_version}' is distinct from '3'
    or rendered_row #>> '{metadata,snapshot_ref}'
      is distinct from input_bundle->>'snapshot_ref'
    or nullif(btrim(coalesce(input_bundle->>'engine_version', '')), '') is null
    or pg_column_size(rendered_row) > 131072
    or pg_column_size(snapshot_row) > 524288
  ) then
    raise exception using
      errcode = '22023',
      message = 'taste card snapshot is invalid';
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
      or not public.soolgyul_adult_profile_complete(attempt_row.owner_user_id)
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

  if identification_row->>'mode' is distinct from 'catalog_match' then
    raise exception using errcode = '22023', message = 'identification mode is invalid';
  end if;

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

  insert into public.drink_records (
    id,
    user_id,
    anonymous_session_id,
    questionnaire_version,
    alcohol_item_id,
    one_line_note,
    idempotency_key
  )
  values (
    attempt_row.reserved_record_id,
    case when principal_kind = 'authenticated' then attempt_row.owner_user_id else null end,
    case when principal_kind = 'anonymous' then request_row->>'anonymous_session_id' else null end,
    request_row->>'questionnaire_version',
    resolved_alcohol_item_id,
    nullif(request_row->>'q7_free_text', ''),
    request_row->>'idempotency_key'
  );

  for answer_row in
    select value
    from jsonb_array_elements(coalesce(request_row->'answers', '[]'::jsonb))
  loop
    insert into public.drink_record_answers (
      drink_record_id,
      question_key,
      selected_option_keys,
      free_text
    )
    values (
      attempt_row.reserved_record_id,
      answer_row->>'question_key',
      array(
        select jsonb_array_elements_text(
          coalesce(answer_row->'selected_option_keys', '[]'::jsonb)
        )
      ),
      nullif(answer_row->>'free_text', '')
    );
  end loop;

  insert into public.taste_cards (
    id,
    drink_record_id,
    snapshot_id,
    snapshot_ref,
    lifecycle,
    canonical_schema_version,
    semantic_snapshot,
    rendered_snapshot,
    snapshot_created_at
  )
  values (
    attempt_row.reserved_result_summary_id,
    attempt_row.reserved_record_id,
    generated_snapshot_id,
    input_bundle->>'snapshot_ref',
    'final',
    input_bundle->>'engine_version',
    snapshot_row,
    rendered_row,
    now()
  );

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
declare account_row public.users%rowtype; retained_count integer; birth integer;
begin
  select * into account_row from public.users where id=target_user_id for update;
  if not found then return 0; end if;
  if account_row.purged_at is not null then return 0; end if;
  if account_row.deletion_provider_revoked_at is null then raise exception 'provider_revocation_required'; end if;
  if account_row.account_status <> 'scheduled_deletion'
    or account_row.deletion_requested_at is null
    or public.soolgyul_deletion_due_at(account_row.deletion_requested_at) > statement_timestamp() then
    raise exception 'account_purge_not_due';
  end if;
  if exists(select 1 from storage.objects where bucket_id='soolgyul-private'
    and starts_with(name,target_user_id::text || '/')) then
    raise exception 'private_storage_cleanup_required';
  end if;

  -- Keep only what cannot point back to the reader: no memo, no free text,
  -- no inquiries, names, account metadata, consent history or raw snapshots.
  birth := extract(year from account_row.birth_date)::integer;
  insert into public.withdrawn_drink_records(birth_year_band,gender,record_data)
  select birth - birth % 5,
    case when account_row.gender_consent_accepted_at is not null then account_row.gender end,
    jsonb_build_object(
      'alcohol_item_id',r.alcohol_item_id,
      'questionnaire_version',r.questionnaire_version,
      'answers',coalesce((select jsonb_agg(jsonb_build_object(
        'question_key',a.question_key,
        'selected_option_keys',a.selected_option_keys) order by a.question_key,a.id)
        from public.drink_record_answers a where a.drink_record_id=r.id),'[]'::jsonb),
      'card',(select public.soolgyul_strip_retained_card_links(jsonb_build_object('rendered_snapshot',c.rendered_snapshot))
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
  perform public.soolgyul_anonymize_discovery_events(target_user_id);
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
-- Name: soolgyul_fold_korean_sound(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_fold_korean_sound(input_value text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
    SET search_path TO ''
    AS $$
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

--
-- Name: soolgyul_fold_korean_sound_array(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_fold_korean_sound_array(input_values text[]) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO ''
    AS $$
  select coalesce(string_agg(public.soolgyul_fold_korean_sound(value), ' ' order by ordinality), '')
  from unnest(coalesce(input_values, array[]::text[])) with ordinality as source(value, ordinality);
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
   when u.deletion_requested_at is not null then 'scheduled' else 'active' end,
  'requested_at',u.deletion_requested_at,
  'scheduled_deletion_at',public.soolgyul_deletion_due_at(u.deletion_requested_at),
  'restore_available',u.purged_at is null and u.disabled_at is null
    and public.soolgyul_deletion_due_at(u.deletion_requested_at)>statement_timestamp(),
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
      selection.interest_key
      order by interest.sort_order, selection.interest_key
    ),
    array[]::text[]
  )
  into current_interest_keys
  from public.user_drink_interests selection
  left join lateral (
    select min(category.sort_order) as sort_order
    from public.alcohol_categories category
    where category.interest_key = selection.interest_key
  ) interest on true
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
-- Name: soolgyul_get_my_profile_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_get_my_profile_status() RETURNS jsonb
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
      and public.soolgyul_adult_profile_complete(target_user_id),
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
    'id', item.id,
    'name', item.name_ko,
    'name_en', item.name_en,
    'category', category.category_key,
    'style_key', item.style_key,
    'target', 'product',
    'ingredient_keys', item.ingredient_keys,
    'production_process_keys', item.production_process_keys,
    'abv_percent', item.abv_percent,
    'aroma_keys', coalesce(to_jsonb(profile.aroma_tags), '[]'::jsonb),
    'texture_keys', '[]'::jsonb,
    'sensory_scale', 5,
    'levels', jsonb_strip_nulls(jsonb_build_object(
      'sweetness', profile.sweetness,
      'acidity', profile.acidity,
      'bitterness', profile.bitterness,
      'astringency', profile.astringency,
      'body', profile.body)))
  from public.alcohol_items item
  join public.alcohol_categories category on category.id = item.alcohol_category_id
  left join public.alcohol_tasting_profiles profile on profile.alcohol_item_id = item.id
  where item.id = target_catalog_id and item.publish_status = 'published';
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
-- Name: soolgyul_guard_taste_card_content(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_guard_taste_card_content() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if new is not distinct from old then return new; end if;
  raise exception using errcode = '55000', message = 'Final taste card content is immutable';
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
   where id=new.id and deletion_requested_at is not null and purged_at is null;
 end if;
 return new;
end; $$;

--
-- Name: soolgyul_level_sources_are_valid(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_level_sources_are_valid(sources jsonb) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    SET search_path TO ''
    AS $$
  select jsonb_typeof(sources) = 'object'
    and not exists (
      select 1
      from jsonb_each(sources) as entry(dimension, grade)
      where entry.dimension not in (
          'sweetness', 'acidity', 'bitterness', 'astringency', 'body',
          'carbonation', 'aroma_intensity', 'finish_length',
          'finish_cleanliness')
        or jsonb_typeof(entry.grade) <> 'number'
        or (entry.grade #>> '{}') not in ('1', '2', '3', '4')
    );
$$;

--
-- Name: soolgyul_limit_anonymous_taste_card_attempts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_limit_anonymous_taste_card_attempts() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if new.anonymous_session_digest is null then
    return new;
  end if;
  if (
    select count(*)
    from public.taste_card_generation_attempts attempt_row
    where attempt_row.anonymous_session_digest = new.anonymous_session_digest
      and attempt_row.created_at > now() - interval '24 hours'
  ) >= 10 then
    raise exception using
      errcode = 'P0001',
      message = 'anonymous_generation_limit_reached';
  end if;
  return new;
end;
$$;

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
-- Name: soolgyul_mark_deletion_provider_revoked(uuid, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_mark_deletion_provider_revoked(target_user_id uuid, requested_at timestamp with time zone, authenticated_at timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
 -- Same lock order as the Auth login trigger: Auth row, then product row.
 perform 1 from auth.users where id=target_user_id and last_sign_in_at=authenticated_at for share;
 if not found then return false; end if;
 update public.users set deletion_provider_revoked_at=statement_timestamp()
 where id=target_user_id and deletion_requested_at=requested_at and purged_at is null;
 return found;
end; $$;

--
-- Name: soolgyul_my_drink_history(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_my_drink_history(p_from timestamp with time zone, p_to timestamp with time zone) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(jsonb_agg(t.row_json order by t.created_at, t.id), '[]'::jsonb)
  from (
    select c.id, r.created_at,
      jsonb_build_object(
        'result_id', c.id::text,
        'recorded_at', r.created_at,
        'alcohol_item_id', r.alcohol_item_id::text,
        'name', item_row.name_ko,
        'category_key', category_row.category_key,
        'category_label', category_row.name_ko,
        'note', r.one_line_note,
        'summary', c.rendered_snapshot #>> '{bite,summary}',
        'brief', c.rendered_snapshot #>> '{bite,brief}',
        'tags', coalesce((
          select jsonb_agg(jsonb_build_object(
            'label', tag ->> 'label',
            'kind', tag ->> 'kind'
          ))
          from jsonb_array_elements(
            case jsonb_typeof(c.rendered_snapshot #> '{bite,tags}')
              when 'array' then c.rendered_snapshot #> '{bite,tags}'
              else '[]'::jsonb
            end
          ) as tag
          where tag ->> 'label' <> ''
        ), '[]'::jsonb)
      ) as row_json
    from public.drink_records r
    join public.taste_cards c
      on c.drink_record_id = r.id and c.lifecycle = 'final'
    join public.alcohol_items item_row on item_row.id = r.alcohol_item_id
    left join public.alcohol_categories category_row
      on category_row.id = item_row.alcohol_category_id
    where r.user_id = auth.uid()
      and r.deleted_at is null
      and public.soolgyul_account_active(auth.uid())
      and r.created_at >= p_from
      and r.created_at < p_to
      and p_to - p_from <= interval '45 days'
  ) t;
$$;

--
-- Name: soolgyul_my_liked_cards(text, boolean, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_my_liked_cards(p_category text DEFAULT NULL::text, p_latest_first boolean DEFAULT true, p_offset integer DEFAULT 0, p_limit integer DEFAULT 30) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  with liked as (
    select
      l.drink_record_id,
      l.created_at as liked_at,
      r.created_at as recorded_at,
      r.one_line_note,
      r.alcohol_item_id,
      item_row.name_ko,
      c.id as result_id,
      c.rendered_snapshot #>> '{bite,brief}' as brief,
      c.rendered_snapshot #>> '{bite,summary}' as summary,
      category_row.interest_key
    from public.user_liked_drink_cards l
    join public.drink_records r
      on r.id = l.drink_record_id
      and r.user_id = l.user_id
      and r.deleted_at is null
    join public.alcohol_items item_row on item_row.id = r.alcohol_item_id
    left join public.taste_cards c
      on c.drink_record_id = r.id and c.lifecycle = 'final'
    left join public.alcohol_categories category_row
      on category_row.id = item_row.alcohol_category_id
    where l.user_id = auth.uid()
      and public.soolgyul_account_active(auth.uid())
      and (p_category is null or category_row.interest_key = p_category)
  ),
  page as (
    select liked.*, row_number() over (
      order by
        case when p_latest_first then liked_at end desc,
        case when p_latest_first then drink_record_id end desc,
        liked_at asc,
        drink_record_id asc
    ) as position
    from liked
    order by position
    offset greatest(coalesce(p_offset, 0), 0)
    limit least(greatest(coalesce(p_limit, 30), 0), 50)
  )
  select jsonb_build_object(
    'total', (select count(*) from liked),
    'cards', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'drink_record_id', page.drink_record_id::text,
          'liked_at', page.liked_at,
          'recorded_at', page.recorded_at,
          'note', page.one_line_note,
          'alcohol_item_id', page.alcohol_item_id::text,
          'name', page.name_ko,
          'result_id', page.result_id::text,
          'brief', page.brief,
          'summary', page.summary,
          'interest_key', page.interest_key
        )
        order by page.position
      )
      from page
    ), '[]'::jsonb)
  );
$$;

--
-- Name: soolgyul_my_recent_card_guides(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_my_recent_card_guides(p_limit integer DEFAULT 3) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;

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
begin
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
  if new.alcohol_item_id is not distinct from old.alcohol_item_id then
    return new;
  end if;
  if num_nonnulls(
      nullif(btrim(old.aroma_note), ''), nullif(btrim(old.palate_note), ''),
      nullif(btrim(old.finish_note), ''), nullif(btrim(old.texture_note), ''),
      old.sweetness, old.acidity, old.bitterness, old.astringency, old.body,
      old.carbonation, old.aroma_intensity, old.finish_length,
      old.finish_cleanliness) > 0
    or cardinality(old.aroma_tags || old.palate_tags || old.finish_tags) > 0
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
     and lower(coalesce(new.raw_app_meta_data ->> 'soolgyul_test_user', '')) = 'true'
  then
    resolved_provider := 'test';
  else
    resolved_provider := lower(
      coalesce(new.raw_app_meta_data ->> 'provider', '')
    );
  end if;

  if resolved_provider not in ('kakao', 'apple', 'google', 'test', 'email') then
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
-- Name: soolgyul_purge_expired_anonymous_taste_cards(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_purge_expired_anonymous_taste_cards(batch_limit integer DEFAULT 500) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  cutoff timestamptz := now() - interval '30 days';
  deleted_records integer;
begin
  -- Attempts first: an attempt still referencing the card snapshot would block
  -- the cascading card delete below.
  delete from public.taste_card_generation_attempts attempt_row
  where attempt_row.anonymous_session_digest is not null
    and attempt_row.created_at < cutoff;

  with expired as (
    select record_row.id
    from public.drink_records record_row
    where record_row.user_id is null
      and record_row.anonymous_session_id is not null
      and record_row.created_at < cutoff
    order by record_row.created_at
    limit greatest(batch_limit, 1)
  )
  delete from public.drink_records record_row
  using expired
  where record_row.id = expired.id;
  get diagnostics deleted_records = row_count;
  return deleted_records;
end;
$$;

--
-- Name: soolgyul_record_discovery_event(text, text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_record_discovery_event(event_kind text, event_surface text, target_alcohol_item_id uuid DEFAULT NULL::uuid, event_query text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  actor uuid := auth.uid();
  member uuid;
  cleaned text := nullif(left(btrim(regexp_replace(
    coalesce(event_query, ''), '\s+', ' ', 'g')), 120), '');
begin
  if actor is not null then
    -- A reader on the way out is no longer counted.
    if not public.soolgyul_account_active(actor) then return; end if;
    member := actor;
    if (select count(*) from public.drink_discovery_events
        where user_id = member
          and occurred_at > statement_timestamp() - interval '1 hour') >= 300 then
      return;
    end if;
  elsif (select count(*) from public.drink_discovery_events
         where user_id is null
           and occurred_at > statement_timestamp() - interval '1 minute') >= 600 then
    return;
  end if;
  insert into public.drink_discovery_events
    (kind, surface, alcohol_item_id, query_text, user_id)
  values (event_kind, event_surface, target_alcohol_item_id, cleaned, member);
exception
  when check_violation or foreign_key_violation then
    raise exception 'discovery_event_invalid' using errcode = '22023';
end;
$$;

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

  select array_agg(interest.interest_key order by interest.sort_order, interest.interest_key)
  into normalized_interest_keys
  from (
    select category.interest_key, min(category.sort_order) as sort_order
    from public.alcohol_categories category
    where category.is_active
      and category.interest_key = any(p_interest_group_keys)
    group by category.interest_key
  ) interest;

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
    and product_user.purged_at is null
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  delete from public.user_drink_interests selection
  where selection.user_id = target_user_id
    and selection.interest_key <> all(normalized_interest_keys);

  insert into public.user_drink_interests (user_id, interest_key)
  select target_user_id, chosen.interest_key
  from unnest(normalized_interest_keys) with ordinality as chosen(interest_key, position)
  where not exists (
    select 1
    from public.user_drink_interests current_selection
    where current_selection.user_id = target_user_id
      and current_selection.interest_key = chosen.interest_key
  )
  order by chosen.position;

  return jsonb_build_object('interest_group_keys', to_jsonb(normalized_interest_keys));
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
 if u.deletion_requested_at is null then
  update public.users set deletion_requested_at=statement_timestamp(),
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
 if u.deletion_requested_at is not null
   and public.soolgyul_deletion_due_at(u.deletion_requested_at)<=statement_timestamp() then
  raise exception 'restore_window_closed'; end if;
 update public.users set deletion_requested_at=null,
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
-- Name: soolgyul_save_taste_letters(uuid, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_save_taste_letters(target_user_id uuid, state jsonb, changes jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if jsonb_typeof(state) is distinct from 'object'
    or jsonb_typeof(state->'axes') is distinct from 'object'
    or jsonb_typeof(changes) is distinct from 'array'
  then
    raise exception using errcode = '22023', message = 'taste letters payload is invalid';
  end if;

  insert into public.taste_letters (user_id, rule_version, record_count, axes, updated_at)
  values (
    target_user_id,
    state->>'rule_version',
    (state->>'record_count')::integer,
    state->'axes',
    now()
  )
  on conflict (user_id) do update
    set rule_version = excluded.rule_version,
        record_count = excluded.record_count,
        axes = excluded.axes,
        updated_at = excluded.updated_at;

  delete from public.taste_letter_changes where user_id = target_user_id;
  insert into public.taste_letter_changes (
    user_id, drink_record_id, axis, from_letter, to_letter,
    left_share, right_share, product_name, changed_at, rule_version
  )
  select
    target_user_id,
    (change->>'record_id')::uuid,
    change->>'axis',
    change->>'from_letter',
    change->>'to_letter',
    (change->>'left_share')::integer,
    (change->>'right_share')::integer,
    change->>'product_name',
    (change->>'changed_at')::timestamptz,
    state->>'rule_version'
  from jsonb_array_elements(changes) as change;
end;
$$;

--
-- Name: soolgyul_search_alcohol_catalog(text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer DEFAULT 20, target_offset integer DEFAULT 0) RETURNS TABLE(id uuid, name_ko text, name_en text, category_key text, style_key text, style_label text, abv_percent numeric, media_path text, country_code text, region text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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
      greatest(1, least(coalesce(target_limit, 20), 20)) as result_limit,
      greatest(0, least(coalesce(target_offset, 0), 1000)) as result_offset
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
  limit (select result_limit from search_input)
  offset (select result_offset from search_input);
end
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
    and product_user.purged_at is null
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'active_account_required';
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
-- Name: soolgyul_update_my_drink_record_note(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.soolgyul_update_my_drink_record_note(p_record_id uuid, p_note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  target_user_id uuid := auth.uid();
begin
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_record_id is null then
    raise exception using errcode = '22023', message = 'record_id_required';
  end if;
  if not public.soolgyul_account_active(target_user_id) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  -- The note has no length limit; blank clears it.
  update public.drink_records
    set one_line_note = nullif(btrim(coalesce(p_note, '')), ''),
        updated_at = now()
    where id = p_record_id and user_id = target_user_id and deleted_at is null;
  if not found then
    raise exception using errcode = 'P0002', message = 'record_not_found';
  end if;
end
$$;

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
  return new;
end
$$;

SET default_tablespace = '';

SET default_table_access_method = heap;

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
    interest_key text,
    CONSTRAINT alcohol_categories_category_key_check CHECK ((category_key ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_categories_interest_key_check CHECK ((interest_key ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_categories_name_ko_check CHECK ((btrim(name_ko) <> ''::text)),
    CONSTRAINT alcohol_categories_sort_order_check CHECK ((sort_order >= 0))
);

--
-- Name: COLUMN alcohol_categories.interest_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_categories.interest_key IS 'Drink-interest key this category is offered under (user interests, editorial links). Null when the category is not an interest choice; the two other_* categories share ''other''.';

--
-- Name: alcohol_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alcohol_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name_ko text NOT NULL,
    name_en text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    alcohol_category_id uuid NOT NULL,
    country_code text,
    abv_percent numeric(5,2),
    style_key text,
    publish_status text DEFAULT 'staging'::text NOT NULL,
    published_at timestamp with time zone,
    ingredient_keys text[] DEFAULT ARRAY[]::text[] NOT NULL,
    production_process_keys text[] DEFAULT ARRAY[]::text[] NOT NULL,
    vintage_year integer,
    age_statement_years numeric,
    grape_variety_keys text[] DEFAULT ARRAY[]::text[] NOT NULL,
    producer_id uuid,
    search_fold_text text GENERATED ALWAYS AS (((((public.soolgyul_fold_korean_sound(name_ko) || ' '::text) || public.soolgyul_fold_korean_sound(COALESCE(name_en, ''::text))) || ' '::text) || public.soolgyul_fold_korean_sound_array(regexp_split_to_array(name_ko, '\s+'::text)))) STORED,
    region_key text,
    CONSTRAINT alcohol_items_abv_percent_check CHECK (((abv_percent IS NULL) OR ((abv_percent >= (0)::numeric) AND (abv_percent <= (100)::numeric)))),
    CONSTRAINT alcohol_items_age_statement_years_check CHECK ((age_statement_years > (0)::numeric)),
    CONSTRAINT alcohol_items_country_code_check CHECK (((country_code IS NULL) OR (country_code ~ '^[A-Z]{2}$'::text))),
    CONSTRAINT alcohol_items_grape_variety_keys_check CHECK (public.soolgyul_catalog_text_array_is_valid(grape_variety_keys, 64, '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_items_ingredient_keys_check CHECK (public.soolgyul_catalog_text_array_is_valid(ingredient_keys, 64, '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_items_production_process_keys_check CHECK (public.soolgyul_catalog_text_array_is_valid(production_process_keys, 64, '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_items_publish_gate_check CHECK (((publish_status <> 'published'::text) OR (published_at IS NOT NULL))),
    CONSTRAINT alcohol_items_publish_status_check CHECK ((publish_status = ANY (ARRAY['staging'::text, 'published'::text, 'withdrawn'::text]))),
    CONSTRAINT alcohol_items_region_key_check CHECK ((region_key ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_items_style_key_check CHECK (((style_key IS NULL) OR (style_key ~ '^[a-z][a-z0-9_]*$'::text))),
    CONSTRAINT alcohol_items_vintage_year_check CHECK (((vintage_year >= 1000) AND (vintage_year <= 2200)))
);

--
-- Name: TABLE alcohol_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.alcohol_items IS 'Single product identity, including explicit vintage, strength, age and batch variants. product_group_id groups related products without inheriting sensory facts.';

--
-- Name: COLUMN alcohol_items.grape_variety_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_items.grape_variety_keys IS 'Grape variety keys of a wine, main grape first (style-profiles.json wine_grapes keys). Empty for other kinds or when unknown.';

--
-- Name: COLUMN alcohol_items.producer_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_items.producer_id IS 'The producer row; search also matches the producer''s names through it.';

--
-- Name: alcohol_tasting_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alcohol_tasting_profiles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    alcohol_item_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    aroma_note text,
    palate_note text,
    finish_note text,
    texture_note text,
    sweetness public.sensory_level_5,
    acidity public.sensory_level_5,
    bitterness public.sensory_level_5,
    astringency public.sensory_level_5,
    body public.sensory_level_5,
    carbonation public.sensory_level_5,
    aroma_intensity public.sensory_level_5,
    finish_length public.sensory_level_5,
    finish_cleanliness public.sensory_level_5,
    aroma_tags text[] DEFAULT ARRAY[]::text[] NOT NULL,
    palate_tags text[] DEFAULT ARRAY[]::text[] NOT NULL,
    finish_tags text[] DEFAULT ARRAY[]::text[] NOT NULL,
    level_sources jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT alcohol_tasting_profiles_aroma_tags_check CHECK (public.soolgyul_catalog_text_array_is_valid(aroma_tags, 64, '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_tasting_profiles_direct_content_check CHECK (((num_nonnulls(NULLIF(btrim(aroma_note), ''::text), NULLIF(btrim(palate_note), ''::text), NULLIF(btrim(finish_note), ''::text), NULLIF(btrim(texture_note), ''::text), sweetness, acidity, bitterness, astringency, body, carbonation, aroma_intensity, finish_length, finish_cleanliness) > 0) OR (cardinality(((aroma_tags || palate_tags) || finish_tags)) > 0))),
    CONSTRAINT alcohol_tasting_profiles_finish_tags_check CHECK (public.soolgyul_catalog_text_array_is_valid(finish_tags, 64, '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT alcohol_tasting_profiles_level_sources_check CHECK (public.soolgyul_level_sources_are_valid(level_sources)),
    CONSTRAINT alcohol_tasting_profiles_palate_tags_check CHECK (public.soolgyul_catalog_text_array_is_valid(palate_tags, 64, '^[a-z][a-z0-9_]*$'::text))
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
-- Name: COLUMN alcohol_tasting_profiles.level_sources; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.alcohol_tasting_profiles.level_sources IS 'Per-level evidence grade: 1 the maker''s own statement, 2 an outside rating of this bottle, 3 aggregated user votes or reader answers, 4 a kind-level estimate (table, style or category median, sibling product, fill). A level column without a grade is unknown. Source names are kept only in the local working copy.';

--
-- Name: catalog_media_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_media_assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    alcohol_item_id uuid NOT NULL,
    media_path text NOT NULL,
    publish_status text DEFAULT 'staging'::text NOT NULL,
    published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT catalog_media_assets_media_path_check CHECK ((btrim(media_path) <> ''::text)),
    CONSTRAINT catalog_media_assets_media_path_format_check CHECK ((media_path ~ '^[a-z_]+/[0-9a-f-]{36}\.webp$'::text)),
    CONSTRAINT catalog_media_assets_publish_check CHECK (((publish_status <> 'published'::text) OR (published_at IS NOT NULL))),
    CONSTRAINT catalog_media_assets_publish_status_check CHECK ((publish_status = ANY (ARRAY['staging'::text, 'published'::text, 'archived'::text])))
);

--
-- Name: TABLE catalog_media_assets; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.catalog_media_assets IS 'One serving image path per product in the public alcohol-product-images bucket, with publish state.';

--
-- Name: catalog_search_projection; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.catalog_search_projection WITH (security_invoker='true', security_barrier='true') AS
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
    media.media_path AS primary_image_media_path
   FROM (public.soolgyul_catalog_search_projection_rows() search_row(alcohol_item_id, alcohol_release_id, display_name, secondary_name, producer_or_brand_display, category_key, subcategory_key, style_key, country_code, region_display, abv_percent, search_aliases, descriptor_keys, is_active, published_at, updated_at)
     LEFT JOIN public.soolgyul_catalog_primary_media_rows() media(catalog_media_asset_id, alcohol_item_id, media_path) ON ((media.alcohol_item_id = search_row.alcohol_item_id)));

--
-- Name: catalog_taxonomy; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_taxonomy (
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
    CONSTRAINT catalog_taxonomy_applicable_sections_check CHECK (((cardinality(applicable_sections) > 0) AND public.soolgyul_catalog_text_array_is_valid(applicable_sections, 9, '^[a-z][a-z0-9_]*$'::text) AND (((term_type = 'classification'::text) AND (applicable_sections <@ ARRAY['classification'::text])) OR ((term_type = 'style'::text) AND (applicable_sections <@ ARRAY['style'::text])) OR ((term_type = 'ingredient'::text) AND (applicable_sections <@ ARRAY['ingredient'::text])) OR ((term_type = 'process'::text) AND (applicable_sections <@ ARRAY['production'::text])) OR ((term_type = 'maturation'::text) AND (applicable_sections <@ ARRAY['maturation'::text])) OR ((term_type = 'region'::text) AND (applicable_sections <@ ARRAY['region'::text])) OR ((term_type = ANY (ARRAY['sensory_descriptor'::text, 'sensory_dimension'::text])) AND (applicable_sections <@ ARRAY['aroma'::text, 'palate'::text, 'finish'::text, 'texture'::text]))))),
    CONSTRAINT catalog_taxonomy_label_en_check CHECK (((label_en IS NULL) OR ((NULLIF(btrim(label_en), ''::text) IS NOT NULL) AND (label_en = btrim(label_en)) AND (label_en = NORMALIZE(label_en, NFC))))),
    CONSTRAINT catalog_taxonomy_label_ko_check CHECK (((NULLIF(btrim(label_ko), ''::text) IS NOT NULL) AND (label_ko = btrim(label_ko)) AND (label_ko = NORMALIZE(label_ko, NFC)))),
    CONSTRAINT catalog_taxonomy_metadata_check CHECK ((jsonb_typeof(metadata) = 'object'::text)),
    CONSTRAINT catalog_taxonomy_parent_not_self_check CHECK (((parent_term_key IS NULL) OR (parent_term_key <> term_key))),
    CONSTRAINT catalog_taxonomy_sort_order_check CHECK ((sort_order >= 0)),
    CONSTRAINT catalog_taxonomy_synonyms_check CHECK (public.soolgyul_catalog_text_array_is_valid(synonyms, 64)),
    CONSTRAINT catalog_taxonomy_taxonomy_version_check CHECK (((taxonomy_version = btrim(taxonomy_version)) AND (taxonomy_version ~ '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$'::text))),
    CONSTRAINT catalog_taxonomy_term_key_check CHECK ((((term_type = 'classification'::text) AND (term_key ~ '^[a-z][a-z0-9_]*:[a-z][a-z0-9_]*$'::text)) OR ((term_type <> 'classification'::text) AND (term_key ~ '^[a-z][a-z0-9_]*$'::text)))),
    CONSTRAINT catalog_taxonomy_term_type_check CHECK ((term_type = ANY (ARRAY['classification'::text, 'style'::text, 'ingredient'::text, 'process'::text, 'maturation'::text, 'sensory_descriptor'::text, 'region'::text]))),
    CONSTRAINT catalog_taxonomy_timestamps_check CHECK ((updated_at >= created_at))
);

--
-- Name: TABLE catalog_taxonomy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.catalog_taxonomy IS 'Classification skeleton the database searches and validates with: region tree, style/ingredient/process/maturation keys, sensory tag keys. Prose lives in catalog/dictionary/terms.json.';

--
-- Name: COLUMN catalog_taxonomy.applicable_sections; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.catalog_taxonomy.applicable_sections IS 'Allowed assignment sections within term_type; values are type-checked and never free-form at serving write time.';

--
-- Name: drink_discovery_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drink_discovery_events (
    id bigint NOT NULL,
    occurred_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    kind text NOT NULL,
    surface text NOT NULL,
    alcohol_item_id uuid,
    query_text text,
    user_id uuid,
    birth_year_band integer,
    gender text,
    CONSTRAINT drink_discovery_events_birth_year_band_check CHECK ((((birth_year_band >= 1900) AND (birth_year_band <= 2095)) AND ((birth_year_band % 5) = 0))),
    CONSTRAINT drink_discovery_events_gender_check CHECK ((gender = ANY (ARRAY['male'::text, 'female'::text, 'other'::text]))),
    CONSTRAINT drink_discovery_events_identity_or_profile CHECK (((user_id IS NULL) OR ((birth_year_band IS NULL) AND (gender IS NULL)))),
    CONSTRAINT drink_discovery_events_kind_check CHECK ((kind = ANY (ARRAY['search_pick'::text, 'search_empty'::text, 'label_match'::text, 'label_miss'::text, 'fit_view'::text]))),
    CONSTRAINT drink_discovery_events_query_shape CHECK (
CASE kind
    WHEN 'search_empty'::text THEN (query_text IS NOT NULL)
    WHEN 'label_miss'::text THEN (query_text IS NOT NULL)
    WHEN 'search_pick'::text THEN true
    ELSE (query_text IS NULL)
END),
    CONSTRAINT drink_discovery_events_query_text_check CHECK (((char_length(query_text) >= 1) AND (char_length(query_text) <= 120))),
    CONSTRAINT drink_discovery_events_surface_check CHECK ((surface = ANY (ARRAY['record'::text, 'taste_fit'::text])))
);

--
-- Name: TABLE drink_discovery_events; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.drink_discovery_events IS 'What readers look for. Linked to an active member for at most 13 months, then anonymous (day, five-year birth band, consented gender). Written only through soolgyul_record_discovery_event; no client reads.';

--
-- Name: drink_discovery_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.drink_discovery_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.drink_discovery_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: drink_record_answers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drink_record_answers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    drink_record_id uuid NOT NULL,
    question_key text NOT NULL,
    selected_option_keys text[] DEFAULT '{}'::text[] NOT NULL,
    free_text text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: drink_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drink_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    anonymous_session_id text,
    alcohol_item_id uuid NOT NULL,
    one_line_note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    idempotency_key text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    questionnaire_version text NOT NULL,
    CONSTRAINT drink_records_check CHECK (((user_id IS NOT NULL) OR (anonymous_session_id IS NOT NULL))),
    CONSTRAINT drink_records_questionnaire_version_valid CHECK (((char_length(questionnaire_version) >= 1) AND (char_length(questionnaire_version) <= 64)))
);

--
-- Name: editorial_article_interests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.editorial_article_interests (
    article_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    interest_key text NOT NULL,
    CONSTRAINT editorial_article_interests_interest_key_check CHECK ((interest_key ~ '^[a-z][a-z0-9_]*$'::text))
);

--
-- Name: TABLE editorial_article_interests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.editorial_article_interests IS 'Drink interests (alcohol_categories.interest_key) an editorial article is about.';

--
-- Name: editorial_article_media_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.editorial_article_media_assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    article_id uuid NOT NULL,
    storage_bucket text NOT NULL,
    storage_object_path text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT editorial_article_media_assets_sort_order_check CHECK ((sort_order >= 0)),
    CONSTRAINT editorial_article_media_assets_storage_bucket_check CHECK ((btrim(storage_bucket) <> ''::text)),
    CONSTRAINT editorial_article_media_assets_storage_object_path_check CHECK ((btrim(storage_object_path) <> ''::text))
);

--
-- Name: TABLE editorial_article_media_assets; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.editorial_article_media_assets IS 'A post''s photos in gallery order; the first one is the cover. flutter-assets is allowed only for bundled fixtures.';

--
-- Name: editorial_articles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.editorial_articles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    body text NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    instagram_url text,
    CONSTRAINT editorial_articles_check CHECK ((((status = 'published'::text) AND (published_at IS NOT NULL)) OR (status <> 'published'::text))),
    CONSTRAINT editorial_articles_instagram_url_check CHECK (((instagram_url IS NULL) OR (instagram_url ~ '^https://(www\.)?instagram\.com/'::text))),
    CONSTRAINT editorial_articles_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text, 'withdrawn'::text])))
);

--
-- Name: TABLE editorial_articles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.editorial_articles IS 'Administrator-authored posts: photos swiped through in order plus a plain text with line breaks.';

--
-- Name: COLUMN editorial_articles.body; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.editorial_articles.body IS 'Markdown body. Inline article media may be referenced with media://<editorial_article_media_assets.id>.';

--
-- Name: COLUMN editorial_articles.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.editorial_articles.status IS 'Published articles are publicly readable; withdrawn preserves publication history without serving the article.';

--
-- Name: producers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    producer_key text NOT NULL,
    name_ko text,
    name_en text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    name_native text,
    search_fold_text text GENERATED ALWAYS AS (((((public.soolgyul_fold_korean_sound(COALESCE(name_ko, ''::text)) || ' '::text) || public.soolgyul_fold_korean_sound(COALESCE(name_en, ''::text))) || ' '::text) || public.soolgyul_fold_korean_sound(COALESCE(name_native, ''::text)))) STORED,
    CONSTRAINT producers_name_check CHECK ((COALESCE(name_ko, name_en) IS NOT NULL)),
    CONSTRAINT producers_name_en_check CHECK (((name_en IS NULL) OR (btrim(name_en) <> ''::text))),
    CONSTRAINT producers_name_ko_check CHECK (((name_ko IS NULL) OR (btrim(name_ko) <> ''::text))),
    CONSTRAINT producers_name_native_check CHECK (((name_native IS NULL) OR (btrim(name_native) <> ''::text))),
    CONSTRAINT producers_producer_key_check CHECK ((producer_key ~ '^[a-z0-9][a-z0-9_]*$'::text))
);

--
-- Name: TABLE producers; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.producers IS 'Who makes the product: winery, distillery, brewery or brand. One row per producer_key; items link through alcohol_items.producer_id.';

--
-- Name: COLUMN producers.name_native; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.producers.name_native IS 'The producer''s name in its own script as printed on the label (Japanese for sake: brand 銘柄 or brewery 蔵元, whichever name_en names); null when not collected.';

--
-- Name: site_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.site_posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kind text NOT NULL,
    title text NOT NULL,
    body text DEFAULT ''::text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT site_posts_check CHECK (((status <> 'published'::text) OR (published_at IS NOT NULL))),
    CONSTRAINT site_posts_kind_check CHECK ((kind = ANY (ARRAY['notice'::text, 'faq'::text]))),
    CONSTRAINT site_posts_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text, 'withdrawn'::text]))),
    CONSTRAINT site_posts_title_check CHECK ((btrim(title) <> ''::text))
);

--
-- Name: TABLE site_posts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.site_posts IS 'Notices and FAQ answers shown on soolgyul.com. Notices read newest published first, FAQ answers by sort_order.';

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
    snapshot_id uuid NOT NULL,
    snapshot_ref text NOT NULL,
    lifecycle text NOT NULL,
    canonical_schema_version text NOT NULL,
    semantic_snapshot jsonb NOT NULL,
    rendered_snapshot jsonb NOT NULL,
    snapshot_created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT taste_cards_json_check CHECK (((jsonb_typeof(semantic_snapshot) = 'object'::text) AND (jsonb_typeof(rendered_snapshot) = 'object'::text) AND (pg_column_size(semantic_snapshot) <= 524288) AND (pg_column_size(rendered_snapshot) <= 131072))),
    CONSTRAINT taste_cards_lifecycle_check CHECK ((lifecycle = 'final'::text)),
    CONSTRAINT taste_cards_ref_check CHECK (((btrim(snapshot_ref) <> ''::text) AND (char_length(snapshot_ref) <= 256))),
    CONSTRAINT taste_cards_version_check CHECK (((char_length(btrim(canonical_schema_version)) >= 1) AND (char_length(btrim(canonical_schema_version)) <= 128)))
);

--
-- Name: TABLE taste_cards; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taste_cards IS 'One taste card per drink record, including immutable rendered content and internal interpretation. Legacy cards retain their original content.';

--
-- Name: taste_letter_changes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taste_letter_changes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    drink_record_id uuid NOT NULL,
    axis text NOT NULL,
    from_letter text,
    to_letter text NOT NULL,
    left_share integer NOT NULL,
    right_share integer NOT NULL,
    product_name text NOT NULL,
    changed_at timestamp with time zone NOT NULL,
    rule_version text NOT NULL,
    CONSTRAINT taste_letter_changes_axis_check CHECK ((axis = ANY (ARRAY['aroma'::text, 'sweetness'::text, 'weight'::text, 'finish'::text]))),
    CONSTRAINT taste_letter_changes_from_letter_check CHECK (((from_letter IS NULL) OR (char_length(from_letter) = 1))),
    CONSTRAINT taste_letter_changes_left_share_check CHECK (((left_share >= 0) AND (left_share <= 100))),
    CONSTRAINT taste_letter_changes_right_share_check CHECK (((right_share >= 0) AND (right_share <= 100))),
    CONSTRAINT taste_letter_changes_to_letter_check CHECK ((char_length(to_letter) = 1))
);

--
-- Name: TABLE taste_letter_changes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taste_letter_changes IS 'The moments a taste letter first appeared (from_letter null) or flipped, with the record that tipped it.';

--
-- Name: taste_letters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taste_letters (
    user_id uuid NOT NULL,
    rule_version text NOT NULL,
    record_count integer NOT NULL,
    axes jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT taste_letters_axes_check CHECK ((jsonb_typeof(axes) = 'object'::text)),
    CONSTRAINT taste_letters_record_count_check CHECK ((record_count >= 0))
);

--
-- Name: TABLE taste_letters; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taste_letters IS 'One row per account: the four taste letters, each with its share and vote count, replayed from the saved cards.';

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
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    interest_key text NOT NULL,
    CONSTRAINT user_drink_interests_interest_key_check CHECK ((interest_key ~ '^[a-z][a-z0-9_]*$'::text))
);

--
-- Name: TABLE user_drink_interests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.user_drink_interests IS 'Owner interest selections by alcohol_categories.interest_key, at most five per user. Mutations go through soolgyul_replace_my_drink_interests.';

--
-- Name: user_liked_drink_cards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_liked_drink_cards (
    user_id uuid NOT NULL,
    drink_record_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE user_liked_drink_cards; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.user_liked_drink_cards IS 'Private owner-only favorites for the user''s own Soolgyul cards. This is not a social reaction or aggregate like counter.';

--
-- Name: COLUMN user_liked_drink_cards.drink_record_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_liked_drink_cards.drink_record_id IS 'The owner''s drink record whose card is liked.';

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
    purged_at timestamp with time zone,
    display_name text,
    age_confirmed_at timestamp with time zone,
    profile_created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    gender text,
    gender_consent_accepted_at timestamp with time zone,
    gender_consent_version text,
    birth_date date,
    deletion_provider_revoked_at timestamp with time zone,
    account_status text GENERATED ALWAYS AS (
CASE
    WHEN (purged_at IS NOT NULL) THEN 'purged'::text
    WHEN (deletion_requested_at IS NOT NULL) THEN 'scheduled_deletion'::text
    WHEN (disabled_at IS NOT NULL) THEN 'disabled'::text
    ELSE 'active'::text
END) STORED,
    CONSTRAINT users_auth_provider_check CHECK ((auth_provider = ANY (ARRAY['kakao'::text, 'apple'::text, 'google'::text, 'test'::text, 'email'::text]))),
    CONSTRAINT users_birth_date_check CHECK (((birth_date >= '1900-01-01'::date) AND (birth_date < '2100-01-01'::date))),
    CONSTRAINT users_gender_check CHECK ((gender = ANY (ARRAY['male'::text, 'female'::text, 'other'::text]))),
    CONSTRAINT users_gender_consent_check CHECK ((((gender IS NULL) AND (gender_consent_accepted_at IS NULL) AND (gender_consent_version IS NULL)) OR ((gender IS NOT NULL) AND (gender_consent_accepted_at IS NOT NULL) AND (gender_consent_version IS NOT NULL) AND (gender_consent_version = 'soolgyul-gender-v1'::text))))
);

--
-- Name: TABLE users; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.users IS 'Product account and user profile; client writes use owner RPCs. Consent history remains in user_consents.';

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
    gender text,
    record_data jsonb NOT NULL,
    birth_year_band integer,
    CONSTRAINT withdrawn_drink_records_birth_year_band_check CHECK ((((birth_year_band >= 1900) AND (birth_year_band <= 2095)) AND ((birth_year_band % 5) = 0))),
    CONSTRAINT withdrawn_drink_records_gender_check CHECK ((gender = ANY (ARRAY['male'::text, 'female'::text, 'other'::text]))),
    CONSTRAINT withdrawn_drink_records_record_data_check CHECK ((jsonb_typeof(record_data) = 'object'::text))
);

--
-- Name: TABLE withdrawn_drink_records; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.withdrawn_drink_records IS 'Anonymous post-withdrawal analysis records: five-year birth band, consented gender, product, chosen answers and card text. No memo, free text, ids or account links. No public or owner access.';

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
-- Name: alcohol_categories alcohol_categories_interest_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_categories
    ADD CONSTRAINT alcohol_categories_interest_key_key UNIQUE (interest_key);

--
-- Name: alcohol_categories alcohol_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_categories
    ADD CONSTRAINT alcohol_categories_pkey PRIMARY KEY (id);

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
-- Name: catalog_media_assets catalog_media_assets_media_path_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_media_assets
    ADD CONSTRAINT catalog_media_assets_media_path_key UNIQUE (media_path);

--
-- Name: catalog_media_assets catalog_media_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_media_assets
    ADD CONSTRAINT catalog_media_assets_pkey PRIMARY KEY (id);

--
-- Name: catalog_taxonomy catalog_taxonomy_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_taxonomy
    ADD CONSTRAINT catalog_taxonomy_pkey PRIMARY KEY (term_type, term_key);

--
-- Name: drink_discovery_events drink_discovery_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_discovery_events
    ADD CONSTRAINT drink_discovery_events_pkey PRIMARY KEY (id);

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
-- Name: editorial_article_interests editorial_article_interests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_article_interests
    ADD CONSTRAINT editorial_article_interests_pkey PRIMARY KEY (article_id, interest_key);

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
-- Name: producers producers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producers
    ADD CONSTRAINT producers_pkey PRIMARY KEY (id);

--
-- Name: producers producers_producer_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producers
    ADD CONSTRAINT producers_producer_key_key UNIQUE (producer_key);

--
-- Name: site_posts site_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.site_posts
    ADD CONSTRAINT site_posts_pkey PRIMARY KEY (id);

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
-- Name: taste_cards taste_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_cards
    ADD CONSTRAINT taste_cards_pkey PRIMARY KEY (id);

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
-- Name: taste_letter_changes taste_letter_changes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_letter_changes
    ADD CONSTRAINT taste_letter_changes_pkey PRIMARY KEY (id);

--
-- Name: taste_letter_changes taste_letter_changes_user_id_drink_record_id_axis_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_letter_changes
    ADD CONSTRAINT taste_letter_changes_user_id_drink_record_id_axis_key UNIQUE (user_id, drink_record_id, axis);

--
-- Name: taste_letters taste_letters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_letters
    ADD CONSTRAINT taste_letters_pkey PRIMARY KEY (user_id);

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
    ADD CONSTRAINT user_drink_interests_pkey PRIMARY KEY (user_id, interest_key);

--
-- Name: user_liked_drink_cards user_liked_drink_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_liked_drink_cards
    ADD CONSTRAINT user_liked_drink_cards_pkey PRIMARY KEY (user_id, drink_record_id);

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
-- Name: alcohol_items_producer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_producer_idx ON public.alcohol_items USING btree (producer_id);

--
-- Name: alcohol_items_production_process_keys_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_production_process_keys_idx ON public.alcohol_items USING gin (production_process_keys);

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
-- Name: alcohol_items_published_search_fold_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alcohol_items_published_search_fold_trgm_idx ON public.alcohol_items USING gin (search_fold_text extensions.gin_trgm_ops) WHERE (publish_status = 'published'::text);

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
-- Name: catalog_taxonomy_active_type_sort_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_taxonomy_active_type_sort_idx ON public.catalog_taxonomy USING btree (term_type, sort_order, term_key) WHERE is_active;

--
-- Name: catalog_taxonomy_applicable_sections_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_taxonomy_applicable_sections_idx ON public.catalog_taxonomy USING gin (applicable_sections);

--
-- Name: catalog_taxonomy_synonyms_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_taxonomy_synonyms_idx ON public.catalog_taxonomy USING gin (synonyms);

--
-- Name: drink_discovery_events_item_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX drink_discovery_events_item_idx ON public.drink_discovery_events USING btree (alcohol_item_id) WHERE (alcohol_item_id IS NOT NULL);

--
-- Name: drink_discovery_events_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX drink_discovery_events_occurred_at_idx ON public.drink_discovery_events USING btree (occurred_at);

--
-- Name: drink_discovery_events_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX drink_discovery_events_user_idx ON public.drink_discovery_events USING btree (user_id) WHERE (user_id IS NOT NULL);

--
-- Name: drink_record_answers_record_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX drink_record_answers_record_id_idx ON public.drink_record_answers USING btree (drink_record_id);

--
-- Name: drink_record_answers_record_question_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX drink_record_answers_record_question_uidx ON public.drink_record_answers USING btree (drink_record_id, question_key);

--
-- Name: drink_records_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX drink_records_user_id_idx ON public.drink_records USING btree (user_id);

--
-- Name: editorial_article_interests_interest_key_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX editorial_article_interests_interest_key_idx ON public.editorial_article_interests USING btree (interest_key, article_id);

--
-- Name: editorial_article_media_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX editorial_article_media_order_idx ON public.editorial_article_media_assets USING btree (article_id, sort_order);

--
-- Name: editorial_articles_publication_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX editorial_articles_publication_idx ON public.editorial_articles USING btree (status, published_at DESC);

--
-- Name: producers_search_fold_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX producers_search_fold_trgm_idx ON public.producers USING gin (search_fold_text extensions.gin_trgm_ops);

--
-- Name: site_posts_kind_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX site_posts_kind_idx ON public.site_posts USING btree (kind, status, sort_order, published_at DESC);

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
-- Name: taste_letter_changes_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX taste_letter_changes_user_idx ON public.taste_letter_changes USING btree (user_id, changed_at);

--
-- Name: user_consents_one_active_document_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_consents_one_active_document_idx ON public.user_consents USING btree (user_id, consent_type, document_version) WHERE (withdrawn_at IS NULL);

--
-- Name: user_consents_user_recorded_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_consents_user_recorded_idx ON public.user_consents USING btree (user_id, accepted_at DESC);

--
-- Name: user_liked_drink_cards_record_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_liked_drink_cards_record_idx ON public.user_liked_drink_cards USING btree (drink_record_id);

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

CREATE TRIGGER alcohol_items_catalog_terms_validate BEFORE INSERT OR UPDATE OF ingredient_keys, production_process_keys, style_key, region_key ON public.alcohol_items FOR EACH ROW EXECUTE FUNCTION public.soolgyul_validate_alcohol_item_catalog_terms();

--
-- Name: alcohol_items alcohol_items_prevent_served_category_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER alcohol_items_prevent_served_category_change BEFORE UPDATE OF alcohol_category_id ON public.alcohol_items FOR EACH ROW EXECUTE FUNCTION public.soolgyul_prevent_served_item_category_change();

--
-- Name: alcohol_tasting_profiles alcohol_tasting_profiles_catalog_terms_validate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER alcohol_tasting_profiles_catalog_terms_validate BEFORE INSERT OR UPDATE OF aroma_tags, palate_tags, finish_tags ON public.alcohol_tasting_profiles FOR EACH ROW EXECUTE FUNCTION public.soolgyul_validate_tasting_profile_catalog_terms();

--
-- Name: alcohol_tasting_profiles alcohol_tasting_profiles_prevent_populated_retargeting; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER alcohol_tasting_profiles_prevent_populated_retargeting BEFORE UPDATE OF alcohol_item_id ON public.alcohol_tasting_profiles FOR EACH ROW EXECUTE FUNCTION public.soolgyul_prevent_populated_tasting_profile_retargeting();

--
-- Name: catalog_taxonomy catalog_taxonomy_assignment_validate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER catalog_taxonomy_assignment_validate AFTER INSERT OR UPDATE ON public.catalog_taxonomy DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.soolgyul_catalog_assignment_term_validate();

--
-- Name: catalog_taxonomy catalog_taxonomy_assignment_write_lock; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER catalog_taxonomy_assignment_write_lock BEFORE INSERT OR DELETE OR UPDATE ON public.catalog_taxonomy FOR EACH STATEMENT EXECUTE FUNCTION public.soolgyul_catalog_assignment_write_lock();

--
-- Name: catalog_taxonomy catalog_taxonomy_prevent_identity_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER catalog_taxonomy_prevent_identity_change BEFORE UPDATE OF term_type, term_key ON public.catalog_taxonomy FOR EACH ROW EXECUTE FUNCTION public.soolgyul_protect_catalog_term_identity();

--
-- Name: drink_records drink_records_guard_final_identity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER drink_records_guard_final_identity BEFORE UPDATE OF questionnaire_version, alcohol_item_id ON public.drink_records FOR EACH ROW WHEN (((old.questionnaire_version IS DISTINCT FROM new.questionnaire_version) OR (old.alcohol_item_id IS DISTINCT FROM new.alcohol_item_id))) EXECUTE FUNCTION public.soolgyul_guard_final_drink_record_identity();

--
-- Name: editorial_articles editorial_articles_prepare_admin_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER editorial_articles_prepare_admin_write BEFORE INSERT OR UPDATE ON public.editorial_articles FOR EACH ROW EXECUTE FUNCTION public.soolgyul_prepare_admin_editorial_article();

--
-- Name: editorial_articles editorial_articles_touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER editorial_articles_touch_updated_at BEFORE UPDATE ON public.editorial_articles FOR EACH ROW EXECUTE FUNCTION public.soolgyul_touch_editorial_updated_at();

--
-- Name: site_posts site_posts_prepare_admin_write; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER site_posts_prepare_admin_write BEFORE INSERT OR UPDATE ON public.site_posts FOR EACH ROW EXECUTE FUNCTION public.soolgyul_prepare_admin_editorial_article();

--
-- Name: site_posts site_posts_touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER site_posts_touch_updated_at BEFORE UPDATE ON public.site_posts FOR EACH ROW EXECUTE FUNCTION public.soolgyul_touch_editorial_updated_at();

--
-- Name: taste_card_generation_attempts taste_card_generation_attempts_anonymous_limit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER taste_card_generation_attempts_anonymous_limit BEFORE INSERT ON public.taste_card_generation_attempts FOR EACH ROW EXECUTE FUNCTION public.soolgyul_limit_anonymous_taste_card_attempts();

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
-- Name: alcohol_items alcohol_items_alcohol_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_items
    ADD CONSTRAINT alcohol_items_alcohol_category_id_fkey FOREIGN KEY (alcohol_category_id) REFERENCES public.alcohol_categories(id) ON DELETE RESTRICT;

--
-- Name: alcohol_items alcohol_items_producer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alcohol_items
    ADD CONSTRAINT alcohol_items_producer_id_fkey FOREIGN KEY (producer_id) REFERENCES public.producers(id) ON DELETE RESTRICT;

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
-- Name: catalog_taxonomy catalog_taxonomy_parent_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_taxonomy
    ADD CONSTRAINT catalog_taxonomy_parent_fkey FOREIGN KEY (term_type, parent_term_key) REFERENCES public.catalog_taxonomy(term_type, term_key) ON UPDATE RESTRICT ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

--
-- Name: drink_discovery_events drink_discovery_events_alcohol_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_discovery_events
    ADD CONSTRAINT drink_discovery_events_alcohol_item_id_fkey FOREIGN KEY (alcohol_item_id) REFERENCES public.alcohol_items(id) ON DELETE SET NULL;

--
-- Name: drink_discovery_events drink_discovery_events_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_discovery_events
    ADD CONSTRAINT drink_discovery_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;

--
-- Name: drink_record_answers drink_record_answers_drink_record_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_record_answers
    ADD CONSTRAINT drink_record_answers_drink_record_id_fkey FOREIGN KEY (drink_record_id) REFERENCES public.drink_records(id) ON DELETE CASCADE;

--
-- Name: drink_records drink_records_alcohol_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_records
    ADD CONSTRAINT drink_records_alcohol_item_id_fkey FOREIGN KEY (alcohol_item_id) REFERENCES public.alcohol_items(id);

--
-- Name: drink_records drink_records_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drink_records
    ADD CONSTRAINT drink_records_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: editorial_article_interests editorial_article_interests_article_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_article_interests
    ADD CONSTRAINT editorial_article_interests_article_id_fkey FOREIGN KEY (article_id) REFERENCES public.editorial_articles(id) ON DELETE CASCADE;

--
-- Name: editorial_article_interests editorial_article_interests_interest_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_article_interests
    ADD CONSTRAINT editorial_article_interests_interest_key_fkey FOREIGN KEY (interest_key) REFERENCES public.alcohol_categories(interest_key) ON UPDATE CASCADE;

--
-- Name: editorial_article_media_assets editorial_article_media_assets_article_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.editorial_article_media_assets
    ADD CONSTRAINT editorial_article_media_assets_article_id_fkey FOREIGN KEY (article_id) REFERENCES public.editorial_articles(id) ON DELETE CASCADE;

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
-- Name: taste_cards taste_cards_drink_record_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_cards
    ADD CONSTRAINT taste_cards_drink_record_id_fkey FOREIGN KEY (drink_record_id) REFERENCES public.drink_records(id) ON DELETE CASCADE;

--
-- Name: taste_letter_changes taste_letter_changes_drink_record_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_letter_changes
    ADD CONSTRAINT taste_letter_changes_drink_record_id_fkey FOREIGN KEY (drink_record_id) REFERENCES public.drink_records(id) ON DELETE CASCADE;

--
-- Name: taste_letter_changes taste_letter_changes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_letter_changes
    ADD CONSTRAINT taste_letter_changes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: taste_letters taste_letters_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taste_letters
    ADD CONSTRAINT taste_letters_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: user_consents user_consents_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_consents
    ADD CONSTRAINT user_consents_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: user_drink_interests user_drink_interests_interest_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_drink_interests
    ADD CONSTRAINT user_drink_interests_interest_key_fkey FOREIGN KEY (interest_key) REFERENCES public.alcohol_categories(interest_key) ON UPDATE CASCADE;

--
-- Name: user_drink_interests user_drink_interests_user_id_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_drink_interests
    ADD CONSTRAINT user_drink_interests_user_id_fkey1 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

--
-- Name: user_liked_drink_cards user_liked_drink_cards_drink_record_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_liked_drink_cards
    ADD CONSTRAINT user_liked_drink_cards_drink_record_id_fkey FOREIGN KEY (drink_record_id) REFERENCES public.drink_records(id) ON DELETE CASCADE;

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
-- Name: catalog_taxonomy; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.catalog_taxonomy ENABLE ROW LEVEL SECURITY;

--
-- Name: drink_discovery_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.drink_discovery_events ENABLE ROW LEVEL SECURITY;

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
-- Name: drink_records drink_records_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY drink_records_owner_select ON public.drink_records FOR SELECT TO authenticated USING (((user_id = auth.uid()) AND (deleted_at IS NULL) AND public.soolgyul_account_active(user_id)));

--
-- Name: taste_cards drink_result_summaries_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY drink_result_summaries_owner_select ON public.taste_cards FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.drink_records r
  WHERE ((r.id = taste_cards.drink_record_id) AND (r.user_id = auth.uid()) AND (r.deleted_at IS NULL) AND public.soolgyul_account_active(r.user_id)))));

--
-- Name: editorial_article_interests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.editorial_article_interests ENABLE ROW LEVEL SECURITY;

--
-- Name: editorial_article_interests editorial_article_interests_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_interests_admin_delete ON public.editorial_article_interests FOR DELETE TO authenticated USING ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_interests.article_id) AND (article.status = 'draft'::text) AND (article.published_at IS NULL)))))));

--
-- Name: editorial_article_interests editorial_article_interests_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_interests_admin_insert ON public.editorial_article_interests FOR INSERT TO authenticated WITH CHECK ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_interests.article_id) AND (article.status = 'draft'::text) AND (article.published_at IS NULL)))))));

--
-- Name: editorial_article_interests editorial_article_interests_anon_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_interests_anon_select ON public.editorial_article_interests FOR SELECT TO anon USING ((EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_interests.article_id) AND (article.status = 'published'::text) AND (article.published_at IS NOT NULL) AND (article.published_at <= now())))));

--
-- Name: editorial_article_interests editorial_article_interests_authenticated_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_article_interests_authenticated_select ON public.editorial_article_interests FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_interests.article_id) AND (article.status = 'published'::text) AND (article.published_at IS NOT NULL) AND (article.published_at <= now())))) OR public.soolgyul_admin_has_role()));

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

CREATE POLICY editorial_article_media_admin_update ON public.editorial_article_media_assets FOR UPDATE TO authenticated USING ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (EXISTS ( SELECT 1
   FROM public.editorial_articles article
  WHERE ((article.id = editorial_article_media_assets.article_id) AND (article.status = 'draft'::text) AND (article.published_at IS NULL))))))) WITH CHECK ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (EXISTS ( SELECT 1
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

CREATE POLICY editorial_articles_admin_update ON public.editorial_articles FOR UPDATE TO authenticated USING ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (status = 'draft'::text) AND (published_at IS NULL)))) WITH CHECK ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (status = 'draft'::text) AND (published_at IS NULL))));

--
-- Name: editorial_articles editorial_articles_anon_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_articles_anon_select ON public.editorial_articles FOR SELECT TO anon USING (((status = 'published'::text) AND (published_at IS NOT NULL) AND (published_at <= now())));

--
-- Name: editorial_articles editorial_articles_authenticated_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY editorial_articles_authenticated_select ON public.editorial_articles FOR SELECT TO authenticated USING ((((status = 'published'::text) AND (published_at IS NOT NULL) AND (published_at <= now())) OR public.soolgyul_admin_has_role()));

--
-- Name: producers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.producers ENABLE ROW LEVEL SECURITY;

--
-- Name: producers producers_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY producers_read ON public.producers FOR SELECT TO authenticated, anon USING (true);

--
-- Name: site_posts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.site_posts ENABLE ROW LEVEL SECURITY;

--
-- Name: site_posts site_posts_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY site_posts_admin_delete ON public.site_posts FOR DELETE TO authenticated USING (public.soolgyul_admin_has_role(ARRAY['admin'::text]));

--
-- Name: site_posts site_posts_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY site_posts_admin_insert ON public.site_posts FOR INSERT TO authenticated WITH CHECK ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (status = 'draft'::text))));

--
-- Name: site_posts site_posts_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY site_posts_admin_update ON public.site_posts FOR UPDATE TO authenticated USING ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (status = 'draft'::text)))) WITH CHECK ((public.soolgyul_admin_has_role(ARRAY['admin'::text]) OR (public.soolgyul_admin_has_role(ARRAY['editor'::text]) AND (status = 'draft'::text))));

--
-- Name: site_posts site_posts_anon_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY site_posts_anon_select ON public.site_posts FOR SELECT TO anon USING ((status = 'published'::text));

--
-- Name: site_posts site_posts_authenticated_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY site_posts_authenticated_select ON public.site_posts FOR SELECT TO authenticated USING (((status = 'published'::text) OR public.soolgyul_admin_has_role()));

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
-- Name: taste_letter_changes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taste_letter_changes ENABLE ROW LEVEL SECURITY;

--
-- Name: taste_letter_changes taste_letter_changes_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY taste_letter_changes_owner_select ON public.taste_letter_changes FOR SELECT TO authenticated USING (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id)));

--
-- Name: taste_letters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taste_letters ENABLE ROW LEVEL SECURITY;

--
-- Name: taste_letters taste_letters_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY taste_letters_owner_select ON public.taste_letters FOR SELECT TO authenticated USING (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id)));

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
   FROM public.drink_records record_row
  WHERE ((record_row.id = user_liked_drink_cards.drink_record_id) AND (record_row.user_id = user_liked_drink_cards.user_id) AND (record_row.deleted_at IS NULL))))));

--
-- Name: user_liked_drink_cards user_liked_drink_cards_owner_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_liked_drink_cards_owner_select ON public.user_liked_drink_cards FOR SELECT TO authenticated USING (((user_id = auth.uid()) AND public.soolgyul_account_active(user_id) AND (EXISTS ( SELECT 1
   FROM public.drink_records record_row
  WHERE ((record_row.id = user_liked_drink_cards.drink_record_id) AND (record_row.user_id = user_liked_drink_cards.user_id) AND (record_row.deleted_at IS NULL))))));

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
-- Name: FUNCTION soolgyul_account_active(target_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_account_active(target_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_account_active(target_user_id uuid) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_account_active(target_user_id uuid) TO authenticated;

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
-- Name: FUNCTION soolgyul_admin_save_editorial_article(article_id uuid, article_body text, article_status text, interest_keys text[], instagram_link text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_admin_save_editorial_article(article_id uuid, article_body text, article_status text, interest_keys text[], instagram_link text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_admin_save_editorial_article(article_id uuid, article_body text, article_status text, interest_keys text[], instagram_link text) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_admin_save_editorial_article(article_id uuid, article_body text, article_status text, interest_keys text[], instagram_link text) TO authenticated;

--
-- Name: FUNCTION soolgyul_adult_profile_complete(target_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_adult_profile_complete(target_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_adult_profile_complete(target_user_id uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_anonymize_discovery_events(target_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_anonymize_discovery_events(target_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_anonymize_discovery_events(target_user_id uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_build_taste_card_result(target_result_summary_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_build_taste_card_result(target_result_summary_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_build_taste_card_result(target_result_summary_id uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assert_item_assignment(item_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assert_item_assignment(item_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assert_item_assignment(item_id uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assignment_category_validate(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assignment_category_validate() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_category_validate() TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assignment_issue(code text, field text, key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assignment_issue(code text, field text, key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_issue(code text, field text, key text) TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assignment_issues(category text, style text, target text, ingredients text[], processes text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assignment_issues(category text, style text, target text, ingredients text[], processes text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_issues(category text, style text, target text, ingredients text[], processes text[]) TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assignment_row_validate(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assignment_row_validate() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_row_validate() TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assignment_term_validate(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assignment_term_validate() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_term_validate() TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_assignment_write_lock(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_assignment_write_lock() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_assignment_write_lock() TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_primary_media_rows(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_primary_media_rows() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_primary_media_rows() TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_catalog_primary_media_rows() TO authenticated;

--
-- Name: FUNCTION soolgyul_catalog_search_projection_rows(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_search_projection_rows() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_search_projection_rows() TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_term_keys_are_active(input_keys text[], allowed_term_types text[], required_sections text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_term_keys_are_active(input_keys text[], allowed_term_types text[], required_sections text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_term_keys_are_active(input_keys text[], allowed_term_types text[], required_sections text[]) TO service_role;

--
-- Name: FUNCTION soolgyul_catalog_text_array_is_valid(input_values text[], max_items integer, key_pattern text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_catalog_text_array_is_valid(input_values text[], max_items integer, key_pattern text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_catalog_text_array_is_valid(input_values text[], max_items integer, key_pattern text) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_catalog_text_array_is_valid(input_values text[], max_items integer, key_pattern text) TO authenticated;

--
-- Name: FUNCTION soolgyul_complete_my_profile(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text, p_gender_consent_accepted boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_complete_my_profile(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text, p_gender_consent_accepted boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_complete_my_profile(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text, p_gender_consent_accepted boolean) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_complete_my_profile(p_idempotency_key uuid, p_display_name text, p_birth_date date, p_age_19_or_over_confirmed boolean, p_terms_version text, p_privacy_version text, p_marketing_version text, p_terms_accepted boolean, p_privacy_accepted boolean, p_marketing_opt_in boolean, p_gender text, p_gender_consent_accepted boolean) TO authenticated;

--
-- Name: FUNCTION soolgyul_convert_anonymous_taste_card(target_user_id uuid, target_result_summary_id uuid, target_anonymous_session_digest text, target_idempotency_key uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_convert_anonymous_taste_card(target_user_id uuid, target_result_summary_id uuid, target_anonymous_session_digest text, target_idempotency_key uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_convert_anonymous_taste_card(target_user_id uuid, target_result_summary_id uuid, target_anonymous_session_digest text, target_idempotency_key uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_delete_owned_drink_record(target_result_summary_id uuid, target_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_delete_owned_drink_record(target_result_summary_id uuid, target_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_delete_owned_drink_record(target_result_summary_id uuid, target_user_id uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_deletion_due_at(requested_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_deletion_due_at(requested_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_deletion_due_at(requested_at timestamp with time zone) TO service_role;

--
-- Name: FUNCTION soolgyul_editorial_object_editable(object_path text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_editorial_object_editable(object_path text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_editorial_object_editable(object_path text) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_editorial_object_editable(object_path text) TO authenticated;

--
-- Name: FUNCTION soolgyul_enforce_drink_interest_limit(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_enforce_drink_interest_limit() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_enforce_drink_interest_limit() TO service_role;

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
-- Name: FUNCTION soolgyul_fold_korean_sound(input_value text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_fold_korean_sound(input_value text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_fold_korean_sound(input_value text) TO service_role;

--
-- Name: FUNCTION soolgyul_fold_korean_sound_array(input_values text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_fold_korean_sound_array(input_values text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_fold_korean_sound_array(input_values text[]) TO service_role;

--
-- Name: FUNCTION soolgyul_get_marketing_consent(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_marketing_consent() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_marketing_consent() TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_get_marketing_consent() TO authenticated;

--
-- Name: FUNCTION soolgyul_get_my_deletion_state(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_my_deletion_state() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_my_deletion_state() TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_get_my_deletion_state() TO authenticated;

--
-- Name: FUNCTION soolgyul_get_my_profile_preferences(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_my_profile_preferences() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_my_profile_preferences() TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_get_my_profile_preferences() TO authenticated;

--
-- Name: FUNCTION soolgyul_get_my_profile_status(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_my_profile_status() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_my_profile_status() TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_get_my_profile_status() TO authenticated;

--
-- Name: FUNCTION soolgyul_get_owned_taste_card_result(target_result_summary_id uuid, target_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_owned_taste_card_result(target_result_summary_id uuid, target_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_owned_taste_card_result(target_result_summary_id uuid, target_user_id uuid) TO service_role;

--
-- Name: FUNCTION soolgyul_get_sensory_question_context(target_catalog_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_get_sensory_question_context(target_catalog_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_get_sensory_question_context(target_catalog_id uuid) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_get_sensory_question_context(target_catalog_id uuid) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_get_sensory_question_context(target_catalog_id uuid) TO authenticated;

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
-- Name: FUNCTION soolgyul_level_sources_are_valid(sources jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_level_sources_are_valid(sources jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_level_sources_are_valid(sources jsonb) TO service_role;

--
-- Name: FUNCTION soolgyul_limit_anonymous_taste_card_attempts(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_limit_anonymous_taste_card_attempts() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_limit_anonymous_taste_card_attempts() TO service_role;

--
-- Name: FUNCTION soolgyul_lower_catalog_text_array(values_to_normalize text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_lower_catalog_text_array(values_to_normalize text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_lower_catalog_text_array(values_to_normalize text[]) TO service_role;

--
-- Name: FUNCTION soolgyul_mark_deletion_provider_revoked(target_user_id uuid, requested_at timestamp with time zone, authenticated_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_mark_deletion_provider_revoked(target_user_id uuid, requested_at timestamp with time zone, authenticated_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_mark_deletion_provider_revoked(target_user_id uuid, requested_at timestamp with time zone, authenticated_at timestamp with time zone) TO service_role;

--
-- Name: FUNCTION soolgyul_my_drink_history(p_from timestamp with time zone, p_to timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_my_drink_history(p_from timestamp with time zone, p_to timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_my_drink_history(p_from timestamp with time zone, p_to timestamp with time zone) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_my_drink_history(p_from timestamp with time zone, p_to timestamp with time zone) TO authenticated;

--
-- Name: FUNCTION soolgyul_my_liked_cards(p_category text, p_latest_first boolean, p_offset integer, p_limit integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_my_liked_cards(p_category text, p_latest_first boolean, p_offset integer, p_limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_my_liked_cards(p_category text, p_latest_first boolean, p_offset integer, p_limit integer) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_my_liked_cards(p_category text, p_latest_first boolean, p_offset integer, p_limit integer) TO authenticated;

--
-- Name: FUNCTION soolgyul_my_recent_card_guides(p_limit integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_my_recent_card_guides(p_limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_my_recent_card_guides(p_limit integer) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_my_recent_card_guides(p_limit integer) TO authenticated;

--
-- Name: FUNCTION soolgyul_normalize_catalog_text(input_value text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_normalize_catalog_text(input_value text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_normalize_catalog_text(input_value text) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_normalize_catalog_text(input_value text) TO authenticated;

--
-- Name: FUNCTION soolgyul_prepare_admin_editorial_article(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_prepare_admin_editorial_article() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_prepare_admin_editorial_article() TO service_role;

--
-- Name: FUNCTION soolgyul_prevent_populated_tasting_profile_retargeting(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_prevent_populated_tasting_profile_retargeting() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_prevent_populated_tasting_profile_retargeting() TO service_role;

--
-- Name: FUNCTION soolgyul_prevent_served_item_category_change(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_prevent_served_item_category_change() FROM PUBLIC;
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
GRANT ALL ON FUNCTION public.soolgyul_provision_auth_user() TO service_role;

--
-- Name: FUNCTION soolgyul_purge_expired_anonymous_taste_cards(batch_limit integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_purge_expired_anonymous_taste_cards(batch_limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_purge_expired_anonymous_taste_cards(batch_limit integer) TO service_role;

--
-- Name: FUNCTION soolgyul_record_discovery_event(event_kind text, event_surface text, target_alcohol_item_id uuid, event_query text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_record_discovery_event(event_kind text, event_surface text, target_alcohol_item_id uuid, event_query text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_record_discovery_event(event_kind text, event_surface text, target_alcohol_item_id uuid, event_query text) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_record_discovery_event(event_kind text, event_surface text, target_alcohol_item_id uuid, event_query text) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_record_discovery_event(event_kind text, event_surface text, target_alcohol_item_id uuid, event_query text) TO authenticated;

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
GRANT ALL ON FUNCTION public.soolgyul_request_my_account_deletion() TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_request_my_account_deletion() TO authenticated;

--
-- Name: FUNCTION soolgyul_restore_my_account(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_restore_my_account() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_restore_my_account() TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_restore_my_account() TO authenticated;

--
-- Name: FUNCTION soolgyul_run_account_retention_job(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_run_account_retention_job() FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_run_account_retention_job() TO service_role;

--
-- Name: FUNCTION soolgyul_save_taste_letters(target_user_id uuid, state jsonb, changes jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_save_taste_letters(target_user_id uuid, state jsonb, changes jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_save_taste_letters(target_user_id uuid, state jsonb, changes jsonb) TO service_role;

--
-- Name: FUNCTION soolgyul_search_alcohol_catalog(target_query text, target_limit integer, target_offset integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer, target_offset integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer, target_offset integer) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer, target_offset integer) TO anon;
GRANT ALL ON FUNCTION public.soolgyul_search_alcohol_catalog(target_query text, target_limit integer, target_offset integer) TO authenticated;

--
-- Name: FUNCTION soolgyul_set_marketing_consent(p_accepted boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_set_marketing_consent(p_accepted boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_set_marketing_consent(p_accepted boolean) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_set_marketing_consent(p_accepted boolean) TO authenticated;

--
-- Name: FUNCTION soolgyul_strip_retained_card_links(value jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_strip_retained_card_links(value jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_strip_retained_card_links(value jsonb) TO service_role;

--
-- Name: FUNCTION soolgyul_submit_support_inquiry(p_id uuid, p_inquiry_type text, p_reply_email text, p_content text, p_attachment_paths text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_submit_support_inquiry(p_id uuid, p_inquiry_type text, p_reply_email text, p_content text, p_attachment_paths text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_submit_support_inquiry(p_id uuid, p_inquiry_type text, p_reply_email text, p_content text, p_attachment_paths text[]) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_submit_support_inquiry(p_id uuid, p_inquiry_type text, p_reply_email text, p_content text, p_attachment_paths text[]) TO authenticated;

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
-- Name: FUNCTION soolgyul_update_my_drink_record_note(p_record_id uuid, p_note text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_update_my_drink_record_note(p_record_id uuid, p_note text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.soolgyul_update_my_drink_record_note(p_record_id uuid, p_note text) TO service_role;
GRANT ALL ON FUNCTION public.soolgyul_update_my_drink_record_note(p_record_id uuid, p_note text) TO authenticated;

--
-- Name: FUNCTION soolgyul_validate_active_alcohol_category_assignment(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.soolgyul_validate_active_alcohol_category_assignment() FROM PUBLIC;
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
-- Name: TABLE alcohol_items; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.alcohol_items TO service_role;

--
-- Name: TABLE alcohol_tasting_profiles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.alcohol_tasting_profiles TO service_role;

--
-- Name: TABLE catalog_media_assets; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.catalog_media_assets TO service_role;

--
-- Name: TABLE catalog_search_projection; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.catalog_search_projection TO service_role;
GRANT ALL ON TABLE public.catalog_search_projection TO anon;
GRANT ALL ON TABLE public.catalog_search_projection TO authenticated;

--
-- Name: TABLE catalog_taxonomy; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE public.catalog_taxonomy TO service_role;

--
-- Name: TABLE drink_discovery_events; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.drink_discovery_events TO service_role;

--
-- Name: SEQUENCE drink_discovery_events_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.drink_discovery_events_id_seq TO service_role;

--
-- Name: TABLE drink_record_answers; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.drink_record_answers TO service_role;
GRANT SELECT ON TABLE public.drink_record_answers TO authenticated;

--
-- Name: TABLE drink_records; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.drink_records TO service_role;
GRANT SELECT ON TABLE public.drink_records TO authenticated;

--
-- Name: TABLE editorial_article_interests; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.editorial_article_interests TO service_role;
GRANT SELECT ON TABLE public.editorial_article_interests TO anon;
GRANT SELECT,INSERT,DELETE ON TABLE public.editorial_article_interests TO authenticated;

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
-- Name: TABLE producers; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.producers TO service_role;
GRANT SELECT ON TABLE public.producers TO anon;
GRANT SELECT ON TABLE public.producers TO authenticated;

--
-- Name: TABLE site_posts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.site_posts TO service_role;
GRANT SELECT ON TABLE public.site_posts TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.site_posts TO authenticated;

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
-- Name: TABLE taste_letter_changes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taste_letter_changes TO service_role;
GRANT SELECT ON TABLE public.taste_letter_changes TO authenticated;

--
-- Name: TABLE taste_letters; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taste_letters TO service_role;
GRANT SELECT ON TABLE public.taste_letters TO authenticated;

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

-- Storage, auth and cron objects the dump of the public schema leaves out.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('soolgyul-private','soolgyul-private',false,10485760,'{image/jpeg,image/png,image/webp}'),
  ('soolgyul-editorial','soolgyul-editorial',true,10485760,'{image/jpeg,image/png,image/webp}'),
  ('soolgyul-catalog-snapshots','soolgyul-catalog-snapshots',false,104857600,'{application/gzip}'),
  ('alcohol-product-images','alcohol-product-images',true,null,'{image/webp}')
on conflict (id) do update set public = excluded.public,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

CREATE POLICY soolgyul_editorial_media_admin_delete ON storage.objects FOR DELETE TO authenticated USING (((bucket_id = 'soolgyul-editorial'::text) AND public.soolgyul_editorial_object_editable(name)));
CREATE POLICY soolgyul_editorial_media_admin_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'soolgyul-editorial'::text) AND public.soolgyul_admin_has_role()));
CREATE POLICY soolgyul_editorial_media_admin_update ON storage.objects FOR UPDATE TO authenticated USING (((bucket_id = 'soolgyul-editorial'::text) AND public.soolgyul_editorial_object_editable(name))) WITH CHECK (((bucket_id = 'soolgyul-editorial'::text) AND public.soolgyul_editorial_object_editable(name)));
CREATE POLICY soolgyul_editorial_media_public_select ON storage.objects FOR SELECT TO authenticated, anon USING ((bucket_id = 'soolgyul-editorial'::text));
CREATE POLICY soolgyul_private_owner_delete ON storage.objects FOR DELETE TO authenticated USING (((bucket_id = 'soolgyul-private'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND public.soolgyul_account_active(auth.uid())));
CREATE POLICY soolgyul_private_owner_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'soolgyul-private'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND public.soolgyul_account_active(auth.uid())));
CREATE POLICY soolgyul_private_owner_read ON storage.objects FOR SELECT TO authenticated USING (((bucket_id = 'soolgyul-private'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND public.soolgyul_account_active(auth.uid())));
CREATE POLICY soolgyul_private_owner_update ON storage.objects FOR UPDATE TO authenticated USING (((bucket_id = 'soolgyul-private'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND public.soolgyul_account_active(auth.uid()))) WITH CHECK (((bucket_id = 'soolgyul-private'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND public.soolgyul_account_active(auth.uid())));

CREATE TRIGGER soolgyul_auth_user_provision AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.soolgyul_provision_auth_user();
CREATE TRIGGER soolgyul_deletion_reauthentication AFTER UPDATE OF last_sign_in_at ON auth.users FOR EACH ROW EXECUTE FUNCTION public.soolgyul_invalidate_deletion_revocation_on_login();

select cron.schedule('soolgyul-account-retention', '0 * * * *',
  'select public.soolgyul_run_account_retention_job();');
select cron.schedule('soolgyul-anonymous-retention', '*/5 * * * *',
  'select public.soolgyul_purge_expired_anonymous_taste_cards();');
select cron.schedule('soolgyul-discovery-anonymize', '30 18 * * *',
  'select public.soolgyul_anonymize_discovery_events()');

-- Reference rows the migrations seeded: the catalog taxonomy and the first
-- FAQ answers. Everything else is loaded by the catalog sync or written in
-- the product.
-- The assignment check needs active alcohol_categories rows, which the
-- catalog sync loads later; it is paused for these rows, and the deferred
-- parent check is settled before the trigger is switched back on.
alter table public.catalog_taxonomy disable trigger catalog_taxonomy_assignment_validate;

insert into public.catalog_taxonomy ("term_type", "term_key", "label_ko", "label_en", "synonyms", "parent_term_key", "applicable_sections", "metadata", "taxonomy_version", "sort_order", "is_active") values
  ('ingredient', 'apple_fruit', '사과', 'Apple', '{애플}', NULL, '{ingredient}', '{"definition": "Apple fruit material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '140', 'true'),
  ('ingredient', 'apricot_fruit', '살구', 'Apricot', '{}', NULL, '{ingredient}', '{"definition": "Apricot fruit material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '340', 'true'),
  ('ingredient', 'aronia_fruit', '아로니아', 'Aronia', '{}', NULL, '{ingredient}', '{"definition": "Aronia (chokeberry) fruit material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '350', 'true'),
  ('ingredient', 'barley', '보리', 'Barley', '{대맥}', NULL, '{ingredient}', '{"definition": "Barley material without a supported malt status.", "ingredient_type_key": "grain", "applies_to_categories": ["korean_traditional", "whisky"]}', '2.0.0', '10', 'true'),
  ('ingredient', 'berry_fruit', '베리류', 'Berry fruit', '{베리}', NULL, '{ingredient}', '{"definition": "Berry-family fruit without a narrower supported species.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional", "wine"]}', '2.0.0', '200', 'true'),
  ('ingredient', 'blueberry_fruit', '블루베리', 'Blueberry', '{}', NULL, '{ingredient}', '{"definition": "Blueberry fruit material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '360', 'true'),
  ('ingredient', 'bokbunja_fruit', '복분자', 'Bokbunja (Korean black raspberry)', '{}', NULL, '{ingredient}', '{"definition": "Rubus coreanus fruit (복분자) material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '370', 'true'),
  ('ingredient', 'buckwheat', '메밀', 'Buckwheat', '{소바}', NULL, '{ingredient}', '{"definition": "Buckwheat material.", "ingredient_type_key": "grain", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '100', 'true'),
  ('ingredient', 'caramel_colour', '캐러멜 색소', 'Caramel colour', '{"카라멜 색소"}', NULL, '{ingredient}', '{"definition": "Caramel colouring explicitly declared; caramel sensory notes are separate.", "ingredient_type_key": "additive", "applies_to_categories": ["whisky"]}', '2.0.0', '330', 'true'),
  ('ingredient', 'cherry_fruit', '체리', 'Cherry', '{버찌}', NULL, '{ingredient}', '{"definition": "Cherry fruit explicitly used as a fermentable or flavouring material, including cherry spirit identified as Kirsch.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '160', 'true'),
  ('ingredient', 'citrus_fruit', '감귤류', 'Citrus fruit', '{시트러스}', NULL, '{ingredient}', '{"definition": "Citrus-family fruit without a narrower supported species.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional", "sake", "wine"]}', '2.0.0', '190', 'true'),
  ('ingredient', 'corn', '옥수수', 'Corn', '{메이즈}', NULL, '{ingredient}', '{"definition": "Corn or maize material.", "ingredient_type_key": "grain", "applies_to_categories": ["korean_traditional", "whisky"]}', '2.0.0', '70', 'true'),
  ('ingredient', 'glutinous_rice', '찹쌀', 'Glutinous rice', '{"sticky rice"}', 'rice', '{ingredient}', '{"definition": "Rice explicitly identified as glutinous rice.", "ingredient_type_key": "grain", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '50', 'true'),
  ('ingredient', 'grape', '포도', 'Grape', '{"양조용 포도"}', NULL, '{ingredient}', '{"definition": "Grape material without a supported variety.", "ingredient_type_key": "grape", "applies_to_categories": ["korean_traditional", "wine"]}', '2.0.0', '130', 'true'),
  ('ingredient', 'hardy_kiwi_fruit', '다래', 'Hardy kiwi', '{}', NULL, '{ingredient}', '{"definition": "Hardy kiwi (다래, 참다래) fruit material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '380', 'true'),
  ('ingredient', 'herb_botanical', '허브', 'Herb', '{허브류}', NULL, '{ingredient}', '{"definition": "Herbal botanical without a narrower supported species.", "ingredient_type_key": "botanical", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '240', 'true'),
  ('ingredient', 'honey', '꿀', 'Honey', '{벌꿀}', NULL, '{ingredient}', '{"definition": "Honey material.", "ingredient_type_key": "other", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '220', 'true'),
  ('ingredient', 'hop_material', '홉', 'Hop', '{호프}', NULL, '{ingredient}', '{"definition": "Hop without a supported variety.", "ingredient_type_key": "botanical", "applies_to_categories": ["whisky"]}', '2.0.0', '250', 'true'),
  ('ingredient', 'koji_starter', '코지', 'Koji', '{누룩곰팡이,"쌀 누룩",쌀국,쌀누룩,입국}', NULL, '{ingredient}', '{"definition": "Koji starter without a supported type.", "ingredient_type_key": "other", "applies_to_categories": ["sake"]}', '2.0.0', '280', 'true'),
  ('ingredient', 'lactic_bacteria', '유산균', 'Lactic acid bacteria', '{젖산균}', NULL, '{ingredient}', '{"definition": "Lactic-acid bacteria culture without a supported strain.", "ingredient_type_key": "other", "applies_to_categories": ["korean_traditional", "sake", "wine"]}', '2.0.0', '270', 'true'),
  ('ingredient', 'malted_barley', '맥아', 'Malted barley', '{몰트,"보리 맥아"}', 'barley', '{ingredient}', '{"definition": "Barley explicitly supported as malted.", "ingredient_type_key": "grain", "applies_to_categories": ["whisky"]}', '2.0.0', '20', 'true'),
  ('ingredient', 'meoru_fruit', '머루', 'Meoru (Korean wild grape)', '{}', NULL, '{ingredient}', '{"definition": "Vitis coignetiae wild grape (머루) material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '390', 'true'),
  ('ingredient', 'millet', '조·기장', 'Millet', '{잡곡}', NULL, '{ingredient}', '{"definition": "Millet-family grain where a narrower species is not established.", "ingredient_type_key": "grain", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '110', 'true'),
  ('ingredient', 'mulberry_fruit', '오디', 'Mulberry', '{}', NULL, '{ingredient}', '{"definition": "Mulberry fruit (오디, 뽕) material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '400', 'true'),
  ('ingredient', 'nuruk_starter', '누룩', 'Nuruk', '{"전통 누룩"}', NULL, '{ingredient}', '{"definition": "Nuruk starter without a supported subtype.", "ingredient_type_key": "other", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '310', 'true'),
  ('ingredient', 'oat', '귀리', 'Oat', '{오트}', NULL, '{ingredient}', '{"definition": "Oat grain material.", "ingredient_type_key": "grain", "applies_to_categories": ["korean_traditional", "whisky"]}', '2.0.0', '120', 'true'),
  ('ingredient', 'omija_fruit', '오미자', 'Omija (schisandra berry)', '{}', NULL, '{ingredient}', '{"definition": "Schisandra chinensis berry (오미자) fruit material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '410', 'true'),
  ('ingredient', 'peach_fruit', '복숭아', 'Peach', '{피치}', NULL, '{ingredient}', '{"definition": "Peach fruit material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional", "wine"]}', '2.0.0', '180', 'true'),
  ('ingredient', 'pear_fruit', '배', 'Pear', '{페어}', NULL, '{ingredient}', '{"definition": "Pear fruit material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '150', 'true'),
  ('ingredient', 'persimmon_fruit', '감', 'Persimmon', '{}', NULL, '{ingredient}', '{"definition": "Persimmon (단감, 홍시) fruit material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '420', 'true'),
  ('ingredient', 'plum_fruit', '자두·매실', 'Plum', '{매실,플럼}', NULL, '{ingredient}', '{"definition": "Plum-family fruit material; exact species and source wording should be retained.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional", "sake"]}', '2.0.0', '170', 'true'),
  ('ingredient', 'pomegranate_fruit', '석류', 'Pomegranate', '{}', NULL, '{ingredient}', '{"definition": "Pomegranate fruit material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '430', 'true'),
  ('ingredient', 'quince_fruit', '모과', 'Chinese quince', '{}', NULL, '{ingredient}', '{"definition": "Chinese quince (모과) fruit material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '440', 'true'),
  ('ingredient', 'rice', '쌀', 'Rice', '{미곡}', NULL, '{ingredient}', '{"definition": "Rice material without a narrower supported form or variety.", "ingredient_type_key": "grain", "applies_to_categories": ["korean_traditional", "sake"]}', '2.0.0', '30', 'true'),
  ('ingredient', 'rice_omachi', '오마치 쌀', 'Omachi rice', '{Omachi,오마치}', 'rice', '{ingredient}', '{"definition": "Rice explicitly identified as the Omachi variety.", "ingredient_type_key": "grain", "applies_to_categories": ["sake"]}', '2.0.0', '40', 'true'),
  ('ingredient', 'rye', '호밀', 'Rye', '{라이}', NULL, '{ingredient}', '{"definition": "Rye grain material.", "ingredient_type_key": "grain", "applies_to_categories": ["whisky"]}', '2.0.0', '80', 'true'),
  ('ingredient', 'sorghum', '수수', 'Sorghum', '{고량}', NULL, '{ingredient}', '{"definition": "Sorghum grain material.", "ingredient_type_key": "grain", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '90', 'true'),
  ('ingredient', 'strawberry_fruit', '딸기', 'Strawberry', '{}', NULL, '{ingredient}', '{"definition": "Strawberry fruit material.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '450', 'true'),
  ('ingredient', 'sweet_potato', '고구마', 'Sweet potato', '{감저}', NULL, '{ingredient}', '{"definition": "Sweet-potato material.", "ingredient_type_key": "other", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '230', 'true'),
  ('ingredient', 'tropical_fruit_material', '열대과일', 'Tropical fruit', '{"트로피컬 프루트"}', NULL, '{ingredient}', '{"definition": "Tropical fruit without a narrower supported species.", "ingredient_type_key": "fruit", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '210', 'true'),
  ('ingredient', 'water_material', '물', 'Water', '{양조용수,용수,정제수,희석수}', NULL, '{ingredient}', '{"definition": "Water explicitly documented as an ingredient, brewing water or dilution water.", "ingredient_type_key": "water", "applies_to_categories": ["korean_traditional", "sake", "whisky", "wine"]}', '2.0.0', '320', 'true'),
  ('ingredient', 'wheat', '밀', 'Wheat', '{소맥}', NULL, '{ingredient}', '{"definition": "Wheat material.", "ingredient_type_key": "grain", "applies_to_categories": ["korean_traditional", "whisky"]}', '2.0.0', '60', 'true'),
  ('ingredient', 'white_koji', '백국', 'White koji', '{"시로 코지"}', 'koji_starter', '{ingredient}', '{"definition": "Koji explicitly identified as white koji.", "ingredient_type_key": "other", "applies_to_categories": ["sake"]}', '2.0.0', '290', 'true'),
  ('ingredient', 'yeast', '효모', 'Yeast', '{이스트}', NULL, '{ingredient}', '{"definition": "Yeast culture without a supported strain.", "ingredient_type_key": "other", "applies_to_categories": ["korean_traditional", "sake", "whisky", "wine"]}', '2.0.0', '260', 'true'),
  ('ingredient', 'yellow_koji', '황국', 'Yellow koji', '{"키 코지"}', 'koji_starter', '{ingredient}', '{"definition": "Koji explicitly identified as yellow koji.", "ingredient_type_key": "other", "applies_to_categories": ["sake"]}', '2.0.0', '300', 'true'),
  ('maturation', 'american_oak', '아메리칸 오크', 'American oak', '{"미국산 오크"}', 'oak_wood', '{maturation}', '{"kind_key": "wood_species", "definition": "American oak is explicitly documented; exact species may remain in source text.", "process_stage": "maturation", "applies_to_categories": ["sake", "whisky", "wine"]}', '2.0.0', '70', 'true'),
  ('maturation', 'amphora_vessel', '암포라', 'Amphora', '{"점토 항아리"}', NULL, '{maturation}', '{"kind_key": "maturation_vessel", "definition": "Fermentation, holding or maturation in amphora or a documented clay vessel.", "process_stage": "maturation", "applies_to_categories": ["korean_traditional", "wine"]}', '2.0.0', '30', 'true'),
  ('maturation', 'bottle_ageing', '병 숙성', 'Bottle ageing', '{"병입 숙성"}', NULL, '{maturation}', '{"kind_key": "maturation_vessel", "definition": "A documented period of bottle ageing precedes release.", "process_stage": "maturation", "applies_to_categories": ["korean_traditional", "sake", "whisky", "wine"]}', '2.0.0', '50', 'true'),
  ('maturation', 'cask_finishing', '캐스크 피니시', 'Cask finishing', '{"피니시 숙성"}', NULL, '{maturation}', '{"kind_key": "maturation_regime", "definition": "A distinct finishing maturation stage is explicitly documented; finishing vessel is linked separately.", "process_stage": "maturation", "applies_to_categories": ["korean_traditional", "sake", "whisky", "wine"]}', '2.0.0', '210', 'true'),
  ('maturation', 'charred_cask', '차링 캐스크', 'Charred cask', '{"그을린 오크통"}', 'wooden_cask', '{maturation}', '{"kind_key": "vessel_treatment", "definition": "Cask charring is explicitly documented; char level is stored separately if available.", "process_stage": "maturation", "applies_to_categories": ["whisky"]}', '2.0.0', '200', 'true'),
  ('maturation', 'concrete_vessel', '콘크리트 용기', 'Concrete vessel', '{"콘크리트 탱크"}', NULL, '{maturation}', '{"kind_key": "maturation_vessel", "definition": "Holding or maturation in a concrete vessel is explicitly documented.", "process_stage": "maturation", "applies_to_categories": ["wine"]}', '2.0.0', '40', 'true'),
  ('maturation', 'european_oak', '유러피언 오크', 'European oak', '{"유럽산 오크"}', 'oak_wood', '{maturation}', '{"kind_key": "wood_species", "definition": "European oak is explicitly documented; exact species and origin may remain in source text.", "process_stage": "maturation", "applies_to_categories": ["sake", "whisky", "wine"]}', '2.0.0', '80', 'true'),
  ('maturation', 'ex_beer_cask', '맥주 캐스크', 'Ex-beer cask', '{"IPA 캐스크","스타우트 캐스크"}', 'wooden_cask', '{maturation}', '{"kind_key": "prior_fill", "definition": "A cask previously holding beer (IPA, stout, ale) is explicitly documented.", "process_stage": "maturation", "applies_to_categories": ["whisky"]}', '2.0.0', '170', 'true'),
  ('maturation', 'ex_bourbon_cask', '버번 캐스크', 'Ex-bourbon cask', '{"버번 배럴"}', 'wooden_cask', '{maturation}', '{"kind_key": "prior_fill", "definition": "A cask previously holding bourbon is explicitly documented.", "process_stage": "maturation", "applies_to_categories": ["sake", "whisky", "wine"]}', '2.0.0', '110', 'true'),
  ('maturation', 'ex_brandy_cask', '브랜디 캐스크', 'Ex-brandy cask', '{"코냑 캐스크"}', 'wooden_cask', '{maturation}', '{"kind_key": "prior_fill", "definition": "A cask previously holding brandy is explicitly documented.", "process_stage": "maturation", "applies_to_categories": ["sake", "whisky"]}', '2.0.0', '180', 'true'),
  ('maturation', 'ex_port_cask', '포트 캐스크', 'Ex-port cask', '{"포트 와인 캐스크"}', 'ex_wine_cask', '{maturation}', '{"kind_key": "prior_fill", "definition": "A cask previously holding port is explicitly documented.", "process_stage": "maturation", "applies_to_categories": ["korean_traditional", "sake", "whisky"]}', '2.0.0', '140', 'true'),
  ('maturation', 'ex_rum_cask', '럼 캐스크', 'Ex-rum cask', '{"럼 배럴"}', 'wooden_cask', '{maturation}', '{"kind_key": "prior_fill", "definition": "A cask previously holding rum is explicitly documented.", "process_stage": "maturation", "applies_to_categories": ["sake", "whisky"]}', '2.0.0', '150', 'true'),
  ('maturation', 'ex_rye_cask', '라이 캐스크', 'Ex-rye whiskey cask', '{"rye barrel","라이 위스키 캐스크"}', 'wooden_cask', '{maturation}', '{"kind_key": "prior_fill", "definition": "A cask previously holding rye whiskey is explicitly documented.", "process_stage": "maturation", "applies_to_categories": ["whisky"]}', '2.0.0', '160', 'true'),
  ('maturation', 'ex_sherry_cask', '셰리 캐스크', 'Ex-sherry cask', '{"쉐리 캐스크"}', 'wooden_cask', '{maturation}', '{"kind_key": "prior_fill", "definition": "A sherry-seasoned or former sherry cask is explicitly documented; the exact wording is retained.", "process_stage": "maturation", "applies_to_categories": ["sake", "whisky", "wine"]}', '2.0.0', '120', 'true'),
  ('maturation', 'ex_wine_cask', '와인 캐스크', 'Ex-wine cask', '{"와인 배럴"}', 'wooden_cask', '{maturation}', '{"kind_key": "prior_fill", "definition": "A cask previously holding wine is explicitly documented; wine type is stored separately when known.", "process_stage": "maturation", "applies_to_categories": ["korean_traditional", "sake", "whisky"]}', '2.0.0', '130', 'true'),
  ('maturation', 'extended_maturation', '장기 숙성', 'Extended maturation', '{Koshu,고슈,"숙성 사케"}', NULL, '{maturation}', '{"kind_key": "maturation_regime", "definition": "Matured for years beyond the usual release age; for sake, koshu.", "process_stage": "maturation", "applies_to_categories": ["korean_traditional", "sake"]}', '2.0.0', '240', 'true'),
  ('maturation', 'fractional_ageing', '분획 숙성', 'Fractional ageing', '{"솔레라 숙성"}', NULL, '{maturation}', '{"kind_key": "maturation_regime", "definition": "A solera or other fractional-aging regime is explicitly documented.", "process_stage": "maturation", "applies_to_categories": ["wine"]}', '2.0.0', '220', 'true'),
  ('maturation', 'mizunara_oak', '미즈나라 오크', 'Mizunara oak', '{물참나무}', 'oak_wood', '{maturation}', '{"kind_key": "wood_species", "definition": "Mizunara oak is explicitly documented.", "process_stage": "maturation", "applies_to_categories": ["sake", "whisky"]}', '2.0.0', '90', 'true'),
  ('maturation', 'new_oak_cask', '새 오크통', 'New oak cask', '{"버진 오크"}', 'wooden_cask', '{maturation}', '{"kind_key": "prior_fill", "definition": "A new or first-fill unused oak cask is explicitly documented.", "process_stage": "maturation", "applies_to_categories": ["whisky", "wine"]}', '2.0.0', '100', 'true'),
  ('maturation', 'oak_wood', '오크', 'Oak', '{참나무}', 'wooden_cask', '{maturation}', '{"kind_key": "wood_species", "definition": "Oak is documented without a narrower species or origin.", "process_stage": "maturation", "applies_to_categories": ["korean_traditional", "sake", "whisky", "wine"]}', '2.0.0', '60', 'true'),
  ('maturation', 'single_cask_maturation', '단일 캐스크 숙성', 'Single-cask maturation', '{"싱글 배럴 숙성"}', NULL, '{maturation}', '{"kind_key": "maturation_regime", "definition": "The release is explicitly matured and released from one cask.", "process_stage": "maturation", "applies_to_categories": ["korean_traditional", "sake", "whisky"]}', '2.0.0', '230', 'true'),
  ('maturation', 'stainless_steel_vessel', '스테인리스 용기', 'Stainless-steel vessel', '{"스테인리스 탱크"}', NULL, '{maturation}', '{"kind_key": "maturation_vessel", "definition": "Holding or maturation in stainless steel is explicitly documented.", "process_stage": "maturation", "applies_to_categories": ["korean_traditional", "sake", "wine"]}', '2.0.0', '20', 'true'),
  ('maturation', 'toasted_cask', '토스팅 캐스크', 'Toasted cask', '{"토스트 오크"}', 'wooden_cask', '{maturation}', '{"kind_key": "vessel_treatment", "definition": "Cask toasting is explicitly documented; toast level is stored separately if available.", "process_stage": "maturation", "applies_to_categories": ["whisky", "wine"]}', '2.0.0', '190', 'true'),
  ('maturation', 'wooden_cask', '목재 캐스크', 'Wooden cask', '{나무통}', NULL, '{maturation}', '{"kind_key": "maturation_vessel", "definition": "Maturation in a wooden cask is explicitly documented, without a supported wood species.", "process_stage": "maturation", "applies_to_categories": ["korean_traditional", "sake", "whisky", "wine"]}', '2.0.0', '10', 'true'),
  ('process', 'atmospheric_distillation', '상압 증류', 'Atmospheric distillation', '{常圧蒸留}', NULL, '{production}', '{"kind_key": "distillation", "definition": "Distillation at normal atmospheric pressure is explicitly documented (常圧蒸留); it carries heavier aroma compounds over than reduced-pressure distillation.", "process_stage": "distillation", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '110', 'true'),
  ('process', 'biodynamic_certified', '바이오다이내믹 인증', 'Certified biodynamic', '{"생명역동농법 인증"}', NULL, '{production}', '{"kind_key": "preparation", "definition": "Certified biodynamic farming is explicitly documented.", "process_stage": "preparation", "applies_to_categories": ["wine"]}', '2.0.0', '330', 'true'),
  ('process', 'bottle_secondary_fermentation', '병내 2차 발효', 'Bottle secondary fermentation', '{"병 발효","전통 방식"}', NULL, '{production}', '{"kind_key": "carbonation", "definition": "Secondary fermentation in bottle is explicitly documented.", "process_stage": "carbonation", "applies_to_categories": ["sake", "wine"]}', '2.0.0', '230', 'true'),
  ('process', 'cask_strength', '캐스크 스트렝스', 'Cask strength', '{"배럴 프루프","캐스크 스트렝쓰"}', NULL, '{production}', '{"kind_key": "bottling", "definition": "Bottled at the strength it left the cask, without dilution to a standard ABV.", "process_stage": "bottling", "applies_to_categories": ["korean_traditional", "whisky"]}', '2.0.0', '300', 'true'),
  ('process', 'charcoal_filtration', '활성탄 여과', 'Charcoal filtration', '{"숯 여과"}', NULL, '{production}', '{"kind_key": "filtration", "definition": "Charcoal or activated-carbon filtration is explicitly documented.", "process_stage": "filtration", "applies_to_categories": ["korean_traditional", "sake", "whisky"]}', '2.0.0', '150', 'true'),
  ('process', 'chill_filtration', '냉각여과', 'Chill filtration', '{"칠 필터링"}', NULL, '{production}', '{"kind_key": "filtration", "definition": "Chill filtration is explicitly documented.", "process_stage": "filtration", "excludes_term_keys": ["non_chill_filtered"], "applies_to_categories": ["whisky"]}', '2.0.0', '130', 'true'),
  ('process', 'coarse_filtered', '니고리', 'Nigori (coarse filtered)', '{니고리자케,"탁한 사케"}', NULL, '{production}', '{"kind_key": "filtration", "definition": "Pressed through a coarse mesh so lees remain and the drink is cloudy.", "process_stage": "filtration", "applies_to_categories": ["sake"]}', '2.0.0', '360', 'true'),
  ('process', 'cold_stabilised', '저온 안정화', 'Cold stabilised', '{"콜드 스태빌라이즈드"}', NULL, '{production}', '{"kind_key": "stabilization", "definition": "Cold stabilisation is explicitly documented.", "process_stage": "stabilization", "applies_to_categories": ["wine"]}', '2.0.0', '200', 'true'),
  ('process', 'column_distillation', '연속식 증류', 'Column distillation', '{연속증류기,"컬럼 스틸"}', NULL, '{production}', '{"kind_key": "distillation", "definition": "Column or continuous distillation is explicitly documented.", "process_stage": "distillation", "applies_to_categories": ["korean_traditional", "whisky"]}', '2.0.0', '70', 'true'),
  ('process', 'cultured_fermentation', '배양 효모 발효', 'Cultured fermentation', '{"선별 효모"}', NULL, '{production}', '{"kind_key": "fermentation", "definition": "A selected or cultured fermentation organism is explicitly documented.", "process_stage": "fermentation", "applies_to_categories": ["korean_traditional", "sake", "whisky", "wine"]}', '2.0.0', '10', 'true'),
  ('process', 'double_distillation', '2회 증류', 'Double distillation', '{"이중 증류"}', NULL, '{production}', '{"kind_key": "distillation", "definition": "Two distillation passes are explicitly documented.", "process_stage": "distillation", "applies_to_categories": ["korean_traditional", "whisky"]}', '2.0.0', '90', 'true'),
  ('process', 'forced_carbonation', '탄산 주입', 'Forced carbonation', '{"강제 탄산"}', NULL, '{production}', '{"kind_key": "carbonation", "definition": "Exogenous carbonation is explicitly documented.", "process_stage": "carbonation", "applies_to_categories": ["korean_traditional", "sake", "wine"]}', '2.0.0', '250', 'true'),
  ('process', 'kimoto_starter', '기모토', 'Kimoto starter', '{생모토}', NULL, '{production}', '{"kind_key": "fermentation", "definition": "Yeast starter made by the traditional kimoto method with natural lactic bacteria.", "process_stage": "fermentation", "applies_to_categories": ["sake"]}', '2.0.0', '370', 'true'),
  ('process', 'maceration', '침용', 'Maceration', '{마세레이션}', NULL, '{production}', '{"kind_key": "preparation", "definition": "Maceration of a documented material is explicitly described.", "process_stage": "preparation", "applies_to_categories": ["korean_traditional", "wine"]}', '2.0.0', '210', 'true'),
  ('process', 'malolactic_fermentation', '말로락틱 발효', 'Malolactic fermentation', '{MLF,"유산 발효"}', NULL, '{production}', '{"kind_key": "fermentation", "definition": "Malolactic conversion is explicitly documented.", "process_stage": "fermentation", "applies_to_categories": ["wine"]}', '2.0.0', '40', 'true'),
  ('process', 'mixed_culture_fermentation', '혼합 배양 발효', 'Mixed-culture fermentation', '{"믹스드 컬처"}', NULL, '{production}', '{"kind_key": "fermentation", "definition": "More than one documented microorganism or culture participates in fermentation.", "process_stage": "fermentation", "applies_to_categories": ["wine"]}', '2.0.0', '30', 'true'),
  ('process', 'multi_cask_blend', '다중 캐스크 블렌드', 'Multi-cask blend', '{"배럴 블렌딩"}', NULL, '{production}', '{"kind_key": "blending", "definition": "Components from more than one cask are explicitly documented.", "process_stage": "blending", "applies_to_categories": ["whisky"]}', '2.0.0', '270', 'true'),
  ('process', 'multi_vintage_blend', '다빈티지 블렌드', 'Multi-vintage blend', '{"논빈티지 블렌딩"}', NULL, '{production}', '{"kind_key": "blending", "definition": "Components from more than one vintage are explicitly documented.", "process_stage": "blending", "applies_to_categories": ["sake", "wine"]}', '2.0.0', '260', 'true'),
  ('process', 'natural_wine_claim', '내추럴 와인 표방', 'Natural wine claim', '{"자연주의 와인"}', NULL, '{production}', '{"kind_key": "preparation", "definition": "The producer presents the wine as natural wine; a claim, not a certification.", "process_stage": "preparation", "applies_to_categories": ["wine"]}', '2.0.0', '340', 'true'),
  ('process', 'non_chill_filtered', '비냉각여과', 'Non-chill filtered', '{논칠필터드}', NULL, '{production}', '{"kind_key": "filtration", "definition": "A non-chill-filtered claim is explicitly documented.", "process_stage": "filtration", "excludes_term_keys": ["chill_filtration"], "applies_to_categories": ["whisky"]}', '2.0.0', '140', 'true'),
  ('process', 'organic_certified', '유기 인증', 'Certified organic', '{"오가닉 인증","유기농 인증"}', NULL, '{production}', '{"kind_key": "preparation", "definition": "Certified organic farming or production is explicitly documented.", "process_stage": "preparation", "applies_to_categories": ["korean_traditional", "sake", "whisky", "wine"]}', '2.0.0', '320', 'true'),
  ('process', 'parallel_multiple_fermentation', '병행복발효', 'Parallel multiple fermentation', '{"병행 복발효"}', NULL, '{production}', '{"kind_key": "fermentation", "definition": "Saccharification and alcoholic fermentation are explicitly documented as proceeding in parallel.", "process_stage": "fermentation", "applies_to_categories": ["korean_traditional", "sake"]}', '2.0.0', '50', 'true'),
  ('process', 'pasteurised', '살균', 'Pasteurised', '{"가열 살균"}', NULL, '{production}', '{"kind_key": "stabilization", "definition": "Pasteurisation is explicitly documented.", "process_stage": "stabilization", "excludes_term_keys": ["unpasteurised"], "applies_to_categories": ["korean_traditional", "sake", "wine"]}', '2.0.0', '180', 'true'),
  ('process', 'peated_malt', '피트 처리 맥아', 'Peated malt', '{peated,피티드}', NULL, '{production}', '{"kind_key": "preparation", "definition": "Malt dried over peat smoke is explicitly documented for the product or its distillery.", "process_stage": "preparation", "applies_to_categories": ["whisky"]}', '2.0.0', '220', 'true'),
  ('process', 'pot_distillation', '단식 증류', 'Pot distillation', '{단식증류기,"팟 스틸"}', NULL, '{production}', '{"kind_key": "distillation", "definition": "Pot-still or batch distillation is explicitly documented.", "process_stage": "distillation", "applies_to_categories": ["korean_traditional", "whisky"]}', '2.0.0', '60', 'true'),
  ('process', 'rice_water_only_claim', '쌀과 물만 사용 표방', 'Rice and water only claim', '{"쌀과 물로만 양조 표방"}', NULL, '{production}', '{"kind_key": "other", "definition": "Explicit wording claims rice and water only. Preserve the stated scope without inferring absent yeast, junmai grade, additive absence or removing existing ingredient facts.", "process_stage": "other", "applies_to_categories": ["sake"]}', '2.0.0', '170', 'true'),
  ('process', 'single_distillation', '1회 증류', 'Single distillation', '{"한 번 증류"}', NULL, '{production}', '{"kind_key": "distillation", "definition": "A single distillation pass is explicitly documented.", "process_stage": "distillation", "applies_to_categories": ["korean_traditional", "whisky"]}', '2.0.0', '80', 'true'),
  ('process', 'small_batch', '스몰 배치', 'Small batch', '{"소량 배치"}', NULL, '{production}', '{"kind_key": "blending", "definition": "Release blended from a small, named number of casks or a single small run.", "process_stage": "blending", "applies_to_categories": ["korean_traditional", "whisky"]}', '2.0.0', '310', 'true'),
  ('process', 'solera_blending', '솔레라 블렌딩', 'Solera blending', '{"분획 블렌딩"}', NULL, '{production}', '{"kind_key": "blending", "definition": "A solera or fractional-blending system is explicitly documented.", "process_stage": "blending", "applies_to_categories": ["wine"]}', '2.0.0', '280', 'true'),
  ('process', 'spirit_fortification', '증류주 첨가 강화', 'Spirit fortification', '{"주정 첨가"}', NULL, '{production}', '{"kind_key": "other", "definition": "Addition of a documented spirit or alcohol for fortification is explicitly supported.", "process_stage": "other", "applies_to_categories": ["korean_traditional", "wine"]}', '2.0.0', '290', 'true'),
  ('process', 'spontaneous_fermentation', '자연발효', 'Spontaneous fermentation', '{"야생 발효"}', NULL, '{production}', '{"kind_key": "fermentation", "definition": "The producer explicitly documents spontaneous fermentation.", "process_stage": "fermentation", "applies_to_categories": ["wine"]}', '2.0.0', '20', 'true'),
  ('process', 'tank_secondary_fermentation', '탱크 2차 발효', 'Tank secondary fermentation', '{"샤르마 방식"}', NULL, '{production}', '{"kind_key": "carbonation", "definition": "Secondary fermentation in a closed tank is explicitly documented.", "process_stage": "carbonation", "applies_to_categories": ["sake", "wine"]}', '2.0.0', '240', 'true'),
  ('process', 'triple_distillation', '3회 증류', 'Triple distillation', '{"삼중 증류"}', NULL, '{production}', '{"kind_key": "distillation", "definition": "Three distillation passes are explicitly documented.", "process_stage": "distillation", "applies_to_categories": ["whisky"]}', '2.0.0', '100', 'true'),
  ('process', 'undiluted', '겐슈', 'Genshu (undiluted)', '{무가수,원주}', NULL, '{production}', '{"kind_key": "bottling", "definition": "Bottled without adding water after pressing or distillation.", "process_stage": "bottling", "applies_to_categories": ["sake"]}', '2.0.0', '350', 'true'),
  ('process', 'unfiltered_claim', '무여과 표방', 'Unfiltered claim', '{논필터드}', NULL, '{production}', '{"kind_key": "filtration", "definition": "An unfiltered claim is explicit; visible haze alone is insufficient.", "process_stage": "filtration", "applies_to_categories": ["korean_traditional", "sake", "whisky", "wine"]}', '2.0.0', '160', 'true'),
  ('process', 'unpasteurised', '비살균', 'Unpasteurised', '{나마,생}', NULL, '{production}', '{"kind_key": "stabilization", "definition": "An unpasteurised or raw claim is explicitly documented.", "process_stage": "stabilization", "excludes_term_keys": ["pasteurised"], "applies_to_categories": ["korean_traditional", "sake", "wine"]}', '2.0.0', '190', 'true'),
  ('process', 'vacuum_distillation', '감압 증류', 'Vacuum distillation', '{"저온 감압 증류"}', NULL, '{production}', '{"kind_key": "distillation", "definition": "Reduced-pressure distillation is explicitly documented.", "process_stage": "distillation", "applies_to_categories": ["korean_traditional", "whisky"]}', '2.0.0', '120', 'true'),
  ('process', 'yamahai_starter', '야마하이', 'Yamahai starter', '{산폐}', NULL, '{production}', '{"kind_key": "fermentation", "definition": "Yeast starter made by the yamahai method, kimoto without the mashing step.", "process_stage": "fermentation", "applies_to_categories": ["sake"]}', '2.0.0', '380', 'true'),
  ('region', 'am', '아르메니아', 'Armenia', '{}', NULL, '{region}', '{}', '2.0.0', '10', 'true'),
  ('region', 'am_aragatsotn', '아라가초튼', 'Aragatsotn', '{}', 'am', '{region}', '{}', '2.0.0', '20', 'true'),
  ('region', 'ar', '아르헨티나', 'Argentina', '{}', NULL, '{region}', '{}', '2.0.0', '30', 'true'),
  ('region', 'ar_altamira', '알타미라', 'Altamira', '{}', 'ar_mendoza', '{region}', '{}', '2.0.0', '100', 'true'),
  ('region', 'ar_cafayate', '까파야떼', 'Cafayate', '{}', 'ar_salta', '{region}', '{}', '2.0.0', '110', 'true'),
  ('region', 'ar_cafayate_valley', '카파야테 밸리', 'Cafayate Valley', '{}', 'ar', '{region}', '{}', '2.0.0', '40', 'true'),
  ('region', 'ar_calchaqui_valley', '칼차키 밸리', 'Calchaqui Valley', '{}', 'ar_cafayate', '{region}', '{}', '2.0.0', '200', 'true'),
  ('region', 'ar_eastern_mendoza', '이스턴 멘도사', 'Eastern Mendoza', '{}', 'ar_mendoza', '{region}', '{}', '2.0.0', '120', 'true'),
  ('region', 'ar_gualtallary', '괄탈라리', 'Gualtallary', '{}', 'ar_mendoza', '{region}', '{}', '2.0.0', '130', 'true'),
  ('region', 'ar_lujan_de_cuyo', '루한 데 쿠요', 'Lujan de Cuyo', '{}', 'ar_mendoza_river_area', '{region}', '{}', '2.0.0', '210', 'true'),
  ('region', 'ar_mendoza', '멘도사', 'Mendoza', '{}', 'ar', '{region}', '{}', '2.0.0', '60', 'true'),
  ('region', 'ar_mendoza_river_area', '멘도사 리버 에어리어', 'Mendoza River Area', '{}', 'ar_mendoza', '{region}', '{}', '2.0.0', '140', 'true'),
  ('region', 'ar_northern_mendoza', '노던 멘도사', 'Northern Mendoza', '{}', 'ar_mendoza', '{region}', '{}', '2.0.0', '150', 'true'),
  ('region', 'ar_patagonia', '파타고니아', 'Patagonia', '{}', 'ar_rio_negro', '{region}', '{}', '2.0.0', '160', 'true'),
  ('region', 'ar_rio_negro', '리오 네그로', 'Rio Negro', '{}', 'ar', '{region}', '{}', '2.0.0', '70', 'true'),
  ('region', 'ar_salta', '살타', 'Salta', '{}', 'ar', '{region}', '{}', '2.0.0', '80', 'true'),
  ('region', 'ar_san_juan', '산 후안', 'San Juan', '{}', 'ar', '{region}', '{}', '2.0.0', '90', 'true'),
  ('region', 'ar_tulum', '툴룸', 'Tulum', '{}', 'ar_san_juan', '{region}', '{}', '2.0.0', '170', 'true'),
  ('region', 'ar_tupungato', '투푼가토', 'Tupungato', '{}', 'ar_uco_valley', '{region}', '{}', '2.0.0', '220', 'true'),
  ('region', 'ar_uco_valley', '우코 밸리', 'Uco Valley', '{}', 'ar_mendoza', '{region}', '{}', '2.0.0', '180', 'true'),
  ('region', 'ar_ullum_zonda', '우윰-존다', 'Ullum-Zonda', '{}', 'ar_san_juan', '{region}', '{}', '2.0.0', '190', 'true'),
  ('region', 'at', '오스트리아', 'Austria', '{}', NULL, '{region}', '{}', '2.0.0', '230', 'true'),
  ('region', 'at_burgenland', '부르겐란트', 'Burgenland', '{}', 'at', '{region}', '{}', '2.0.0', '240', 'true'),
  ('region', 'at_kamptal', '캄프탈', 'Kamptal', '{}', 'at_niederosterreich', '{region}', '{}', '2.0.0', '290', 'true'),
  ('region', 'at_karnten', '카린시아', 'Kärnten', '{}', 'at', '{region}', '{}', '2.0.0', '250', 'true'),
  ('region', 'at_kremstal', '크렘스탈', 'Kremstal', '{}', 'at_niederosterreich', '{region}', '{}', '2.0.0', '300', 'true'),
  ('region', 'at_mittelburgenland', '미텔부르겐란트', 'Mittelburgenland', '{}', 'at_burgenland', '{region}', '{}', '2.0.0', '310', 'true'),
  ('region', 'at_neusiedlersee', '노이지들러제', 'Neusiedlersee', '{}', 'at_burgenland', '{region}', '{}', '2.0.0', '320', 'true'),
  ('region', 'at_neusiedlersee_hugelland', '노이지들러제 휘겔란트', 'Neusiedlersee Hügelland', '{}', 'at_burgenland', '{region}', '{}', '2.0.0', '330', 'true'),
  ('region', 'at_niederosterreich', '니더외스터라이히', 'Niederosterreich', '{}', 'at', '{region}', '{}', '2.0.0', '260', 'true'),
  ('region', 'at_steiermark', '슈타이어마르크', 'Steiermark', '{}', 'at', '{region}', '{}', '2.0.0', '270', 'true'),
  ('region', 'at_sudburgenland', '쥐드부르겐란트', 'Sudburgenland', '{}', 'at_burgenland', '{region}', '{}', '2.0.0', '340', 'true'),
  ('region', 'at_thermenregion', '테르멘레기온', 'Thermenregion', '{}', 'at_niederosterreich', '{region}', '{}', '2.0.0', '350', 'true'),
  ('region', 'at_traisental', '트라이젠탈', 'Traisental', '{}', 'at_niederosterreich', '{region}', '{}', '2.0.0', '360', 'true'),
  ('region', 'at_wachau', '바우', 'Wachau', '{바하우}', 'at_niederosterreich', '{region}', '{}', '2.0.0', '370', 'true'),
  ('region', 'at_wagram', '바그람', 'Wagram', '{}', 'at_niederosterreich', '{region}', '{}', '2.0.0', '380', 'true'),
  ('region', 'at_weinland', '바인란트', 'Weinland', '{}', 'at', '{region}', '{}', '2.0.0', '280', 'true'),
  ('region', 'at_weinviertel', '바인피어텔', 'Weinviertel', '{}', 'at_niederosterreich', '{region}', '{}', '2.0.0', '390', 'true'),
  ('region', 'au', '호주', 'Australia', '{}', NULL, '{region}', '{}', '2.0.0', '400', 'true'),
  ('region', 'au_adelaide', '아들레이드', 'Adelaide', '{}', 'au_mclaren_vale', '{region}', '{}', '2.0.0', '980', 'true'),
  ('region', 'au_adelaide_hills', '애들레이드 힐즈', 'Adelaide Hills', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '480', 'true'),
  ('region', 'au_adelaide_plains', '애들레이드 플레인스', 'Adelaide Plains', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '490', 'true'),
  ('region', 'au_alpine_valleys', '알파인 밸리스', 'Alpine Valleys', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '500', 'true'),
  ('region', 'au_australian_capital_territory', '오스트레일리언 캐피탈 테리토리', 'Australian Capital Territory', '{}', 'au', '{region}', '{}', '2.0.0', '410', 'true'),
  ('region', 'au_barossa_valley', '바로사 밸리', 'Barossa Valley', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '510', 'true'),
  ('region', 'au_beechworth', '비치워스', 'Beechworth', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '520', 'true'),
  ('region', 'au_bendigo', '벤디고', 'Bendigo', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '530', 'true'),
  ('region', 'au_canberra_district', '캔버라 디스트릭트', 'Canberra District', '{}', 'au_australian_capital_territory', '{region}', '{}', '2.0.0', '540', 'true'),
  ('region', 'au_central_ranges', '센트럴 레인지', 'Central Ranges', '{}', 'au_new_south_wales', '{region}', '{}', '2.0.0', '550', 'true'),
  ('region', 'au_clare_valley', '클레어 밸리', 'Clare Valley', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '560', 'true'),
  ('region', 'au_coonawarra', '쿠나와라', 'Coonawarra', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '570', 'true'),
  ('region', 'au_eden_valley', '에덴 밸리', 'Eden Valley', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '580', 'true'),
  ('region', 'au_fleurieu', '플레리유', 'Fleurieu', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '590', 'true'),
  ('region', 'au_geelong', '질롱', 'Geelong', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '600', 'true'),
  ('region', 'au_geographe', '지오그래프', 'Geographe', '{}', 'au_western_australia', '{region}', '{}', '2.0.0', '610', 'true'),
  ('region', 'au_gippsland', '깁스랜드', 'Gippsland', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '620', 'true'),
  ('region', 'au_goulburn_valley', '골번 밸리', 'Goulburn Valley', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '630', 'true'),
  ('region', 'au_grampians', '그램피언스', 'Grampians', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '640', 'true'),
  ('region', 'au_great_southern', '그레이트 서던', 'Great Southern', '{}', 'au_western_australia', '{region}', '{}', '2.0.0', '650', 'true'),
  ('region', 'au_heathcote', '히스코트', 'Heathcôte', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '660', 'true'),
  ('region', 'au_hilltops', '힐탑스', 'Hilltops', '{}', 'au_new_south_wales', '{region}', '{}', '2.0.0', '670', 'true'),
  ('region', 'au_hunter_valley', '헌터 밸리', 'Hunter Valley', '{}', 'au_new_south_wales', '{region}', '{}', '2.0.0', '680', 'true'),
  ('region', 'au_kangaroo_island', '캥거루 아일랜드', 'Kangaroo Island', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '690', 'true'),
  ('region', 'au_king_valley', '킹 밸리', 'King Valley', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '700', 'true'),
  ('region', 'au_langhorne_creek', '랭혼 크릭', 'Langhorne Creek', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '710', 'true'),
  ('region', 'au_limestone_coast', '라임스톤 코스트', 'Limestone Coast', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '720', 'true'),
  ('region', 'au_macedon_ranges', '마케돈 레인지스', 'Macedon Ranges', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '730', 'true'),
  ('region', 'au_margaret_river', '마가렛 리버', 'Margaret River', '{}', 'au_western_australia', '{region}', '{}', '2.0.0', '740', 'true'),
  ('region', 'au_mclaren_vale', '맥라렌 베일', 'McLaren Vale', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '750', 'true'),
  ('region', 'au_mornington_peninsula', '모닝턴 페닌슐라', 'Mornington Peninsula', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '760', 'true'),
  ('region', 'au_mount_benson', '마운트 벤슨', 'Mount Benson', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '770', 'true'),
  ('region', 'au_mount_gambier', '마운트 갬비어', 'Mount Gambier', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '780', 'true'),
  ('region', 'au_mudgee', '멋지', 'Mudgee', '{머쥐}', 'au_new_south_wales', '{region}', '{}', '2.0.0', '790', 'true'),
  ('region', 'au_murray_darling', '머레이 달링', 'Murray Darling', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '800', 'true'),
  ('region', 'au_new_england_australia', '뉴 잉글랜드 오스트레일리아', 'New England Australia', '{}', 'au_new_south_wales', '{region}', '{}', '2.0.0', '810', 'true'),
  ('region', 'au_new_south_wales', '뉴 사우스 웨일즈', 'New South Wales', '{}', 'au', '{region}', '{}', '2.0.0', '420', 'true'),
  ('region', 'au_orange', '오렌지', 'Orange', '{}', 'au_new_south_wales', '{region}', '{}', '2.0.0', '820', 'true'),
  ('region', 'au_padthaway', '패더웨이', 'Padthaway', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '830', 'true'),
  ('region', 'au_pemberton', '펨버튼', 'Pemberton', '{}', 'au_western_australia', '{region}', '{}', '2.0.0', '840', 'true'),
  ('region', 'au_polish_hill_river', '폴리쉬 힐 리버', 'Polish Hill River', '{}', 'au_clare_valley', '{region}', '{}', '2.0.0', '990', 'true'),
  ('region', 'au_pyrenees', '피레네', 'Pyrenees', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '850', 'true'),
  ('region', 'au_riverina', '리베리나', 'Riverina', '{}', 'au_new_south_wales', '{region}', '{}', '2.0.0', '860', 'true'),
  ('region', 'au_riverland', '리버랜드', 'Riverland', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '870', 'true'),
  ('region', 'au_rutherglen', '루더글렌', 'Rutherglen', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '880', 'true'),
  ('region', 'au_south_australia', '사우스 오스트레일리아', 'South Australia', '{}', 'au', '{region}', '{}', '2.0.0', '430', 'true'),
  ('region', 'au_south_eastern_australia', '사우스 이스턴 오스트레일리아', 'South Eastern Australia', '{}', 'au', '{region}', '{}', '2.0.0', '440', 'true'),
  ('region', 'au_southern_fleurieu', '서던 플러리어', 'Southern Fleurieu', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '890', 'true'),
  ('region', 'au_southern_highlands', '서던 하일랜즈', 'Southern Highlands', '{}', 'au_new_south_wales', '{region}', '{}', '2.0.0', '900', 'true'),
  ('region', 'au_strathbogie_ranges', '스트래스보기 레인지스', 'Strathbogie Ranges', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '910', 'true'),
  ('region', 'au_swan_district', '스완 디스트릭', 'Swan District', '{}', 'au_western_australia', '{region}', '{}', '2.0.0', '920', 'true'),
  ('region', 'au_swan_hill', '스완 힐', 'Swan Hill', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '930', 'true'),
  ('region', 'au_tasmania', '태즈메이니아', 'Tasmania', '{}', 'au', '{region}', '{}', '2.0.0', '450', 'true'),
  ('region', 'au_tumbarumba', '툼바룸바', 'Tumbarumba', '{}', 'au_new_south_wales', '{region}', '{}', '2.0.0', '940', 'true'),
  ('region', 'au_upper_goulburn', '어퍼 골번', 'Upper Goulburn', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '950', 'true'),
  ('region', 'au_victoria', '빅토리아', 'Victoria', '{}', 'au', '{region}', '{}', '2.0.0', '460', 'true'),
  ('region', 'au_western_australia', '웨스턴 오스트레일리아', 'Western Australia', '{}', 'au', '{region}', '{}', '2.0.0', '470', 'true'),
  ('region', 'au_wrattonbully', '래튼불리', 'Wrattonbully', '{}', 'au_south_australia', '{region}', '{}', '2.0.0', '960', 'true'),
  ('region', 'au_yarra_valley', '야라 밸리', 'Yarra Valley', '{}', 'au_victoria', '{region}', '{}', '2.0.0', '970', 'true'),
  ('region', 'az', '아제르바이잔', 'Azerbaijan', '{}', NULL, '{region}', '{}', '2.0.0', '1000', 'true'),
  ('region', 'be', '벨기에', 'Belgium', '{}', NULL, '{region}', '{}', '2.0.0', '1010', 'true'),
  ('region', 'bg', '불가리아', 'Bulgaria', '{}', NULL, '{region}', '{}', '2.0.0', '1020', 'true'),
  ('region', 'bg_oryahovo', '오랴호보', 'Oryahovo', '{}', 'bg', '{region}', '{}', '2.0.0', '1030', 'true'),
  ('region', 'bg_pazardzhik', '파자르지크', 'pazardzhik', '{}', 'bg', '{region}', '{}', '2.0.0', '1040', 'true'),
  ('region', 'bg_plovdiv', '플로브디프', 'Plovdiv', '{}', 'bg', '{region}', '{}', '2.0.0', '1050', 'true'),
  ('region', 'bg_thracian_valley', '트라키안 밸리', 'Thracian Valley', '{}', 'bg', '{region}', '{}', '2.0.0', '1060', 'true'),
  ('region', 'br', '브라질', 'Brazil', '{}', NULL, '{region}', '{}', '2.0.0', '1070', 'true'),
  ('region', 'ca', '캐나다', 'Canada', '{}', NULL, '{region}', '{}', '2.0.0', '1080', 'true'),
  ('region', 'ca_british_columbia', '브리티쉬 콜롬비아', 'British Columbia', '{}', 'ca', '{region}', '{}', '2.0.0', '1100', 'true'),
  ('region', 'ca_niagara_peninsula', '나이아가라 페닌슐라', 'Niagara Peninsula', '{}', 'ca_ontario', '{region}', '{}', '2.0.0', '1110', 'true'),
  ('region', 'ca_okanagan_valley', '오카나간 밸리', 'Okanagan Valley', '{}', 'ca_british_columbia', '{region}', '{}', '2.0.0', '1120', 'true'),
  ('region', 'ca_ontario', '온타리오', 'Ontario', '{}', 'ca', '{region}', '{}', '2.0.0', '1130', 'true'),
  ('region', 'ch', '스위스', 'Switzerland', '{}', NULL, '{region}', '{}', '2.0.0', '1140', 'true'),
  ('region', 'ch_vaud', '보', 'Vaud', '{}', 'ch', '{region}', '{}', '2.0.0', '1150', 'true'),
  ('region', 'cl', '칠레', 'Chile', '{}', NULL, '{region}', '{}', '2.0.0', '1160', 'true'),
  ('region', 'cl_aconcagua', '아콩카구아', 'Aconcagua', '{}', 'cl', '{region}', '{}', '2.0.0', '1170', 'true'),
  ('region', 'cl_aconcagua_valley', '아콩카구아 밸리', 'Aconcagua Valley', '{}', 'cl_aconcagua', '{region}', '{}', '2.0.0', '1230', 'true'),
  ('region', 'cl_apalta_valley', '아팔타 밸리', 'Apalta Valley', '{}', 'cl_cholchagua_valley', '{region}', '{}', '2.0.0', '1490', 'true'),
  ('region', 'cl_bio_bio_valley', '비오-비오 밸리', 'Bio-Bio-Valley', '{}', 'cl_southern_region', '{region}', '{}', '2.0.0', '1240', 'true'),
  ('region', 'cl_cachapoal_valley', '카차포알 밸리', 'Cachapoal Valley', '{}', 'cl_rapel_valley', '{region}', '{}', '2.0.0', '1400', 'true'),
  ('region', 'cl_casablanca_valley', '카사블랑카 밸리', 'Casablanca Valley', '{}', 'cl_aconcagua', '{region}', '{}', '2.0.0', '1250', 'true'),
  ('region', 'cl_cauquenes', '카우케네스', 'Cauquenes', '{}', 'cl_tutuven_valley', '{region}', '{}', '2.0.0', '1500', 'true'),
  ('region', 'cl_central_valley', '센트럴 밸리', 'Central Valley', '{}', 'cl', '{region}', '{}', '2.0.0', '1180', 'true'),
  ('region', 'cl_choapa_valley', '초아파 밸리', 'Choapa Valley', '{}', 'cl_coquimbo', '{region}', '{}', '2.0.0', '1260', 'true'),
  ('region', 'cl_cholchagua_valley', '콜차구아 밸리', 'Cholchagua Valley', '{}', 'cl_rapel_valley', '{region}', '{}', '2.0.0', '1410', 'true'),
  ('region', 'cl_coelemu', '코엘레무', 'Coelemu', '{}', 'cl_itata_valley', '{region}', '{}', '2.0.0', '1420', 'true'),
  ('region', 'cl_coquimbo', '코킴보', 'Coquimbo', '{}', 'cl', '{region}', '{}', '2.0.0', '1190', 'true'),
  ('region', 'cl_curico_valley', '쿠리코 밸리', 'Curico Valley', '{}', 'cl', '{region}', '{}', '2.0.0', '1200', 'true'),
  ('region', 'cl_elqui_valley', '엘퀴 밸리', 'Elqui Valley', '{}', 'cl_coquimbo', '{region}', '{}', '2.0.0', '1270', 'true'),
  ('region', 'cl_isla_de_maipo', '이슬라 디 마이포', 'Isla de Maipo', '{}', 'cl_maipo_valley', '{region}', '{}', '2.0.0', '1430', 'true'),
  ('region', 'cl_itata_valley', '이타타 밸리', 'Itata Valley', '{}', 'cl_southern_region', '{region}', '{}', '2.0.0', '1280', 'true'),
  ('region', 'cl_leyda_valley', '레이다 밸리', 'Leyda Valley', '{}', 'cl_aconcagua', '{region}', '{}', '2.0.0', '1290', 'true'),
  ('region', 'cl_limari_valley', '리마리 밸리', 'Limari Valley', '{}', 'cl_coquimbo', '{region}', '{}', '2.0.0', '1300', 'true'),
  ('region', 'cl_loncomilla_valley', '론코미야 밸리', 'Loncomilla Valley', '{}', 'cl_maule_valley', '{region}', '{}', '2.0.0', '1440', 'true'),
  ('region', 'cl_lontue_valley', '론투에 밸리', 'Lontue Valley', '{}', 'cl_curico_valley', '{region}', '{}', '2.0.0', '1310', 'true'),
  ('region', 'cl_maipo_valley', '마이포 밸리', 'Maipo Valley', '{}', 'cl_central_valley', '{region}', '{}', '2.0.0', '1320', 'true'),
  ('region', 'cl_malleco_valley', '마에이코 밸리', 'Malleco Valley', '{"말레코 밸리"}', 'cl_southern_region', '{region}', '{}', '2.0.0', '1330', 'true'),
  ('region', 'cl_maule_valley', '마울레 밸리', 'Maule Valley', '{}', 'cl_central_valley', '{region}', '{}', '2.0.0', '1340', 'true'),
  ('region', 'cl_millahue_valley', '미야후밸리', 'Millahue Valley', '{}', 'cl', '{region}', '{}', '2.0.0', '1210', 'true'),
  ('region', 'cl_molina', '몰리나', 'Molina', '{}', 'cl_curico_valley', '{region}', '{}', '2.0.0', '1350', 'true'),
  ('region', 'cl_palmilla', '팔미야', 'Palmilla', '{}', 'cl_cholchagua_valley', '{region}', '{}', '2.0.0', '1510', 'true'),
  ('region', 'cl_peumo', '페우모', 'Peumo', '{}', 'cl_cachapoal_valley', '{region}', '{}', '2.0.0', '1520', 'true'),
  ('region', 'cl_pirque', '피르케', 'Pirque', '{}', 'cl_maipo_valley', '{region}', '{}', '2.0.0', '1450', 'true'),
  ('region', 'cl_puente_alto', '푸엔테 알토', 'Puente Alto', '{}', 'cl_maipo_valley', '{region}', '{}', '2.0.0', '1460', 'true'),
  ('region', 'cl_rapel_valley', '라펠 밸리', 'Rapel Valley', '{}', 'cl_central_valley', '{region}', '{}', '2.0.0', '1360', 'true'),
  ('region', 'cl_sagrada_familia', '사그라다 파밀리아', 'Sagrada Familia', '{}', 'cl_curico_valley', '{region}', '{}', '2.0.0', '1370', 'true'),
  ('region', 'cl_san_antonio_valley', '산 안토니오 밸리', 'San Antonio Valley', '{}', 'cl_aconcagua', '{region}', '{}', '2.0.0', '1380', 'true'),
  ('region', 'cl_santiago', '산티아고', 'Santiago', '{}', 'cl_maipo_valley', '{region}', '{}', '2.0.0', '1470', 'true'),
  ('region', 'cl_southern_region', '서던 리젼', 'Southern Region', '{}', 'cl', '{region}', '{}', '2.0.0', '1220', 'true'),
  ('region', 'cl_tutuven_valley', '투투벤 밸리', 'Tutuven Valley', '{}', 'cl_maule_valley', '{region}', '{}', '2.0.0', '1480', 'true'),
  ('region', 'cl_zapallar', '자파야', 'Zapallar', '{}', 'cl_aconcagua', '{region}', '{}', '2.0.0', '1390', 'true'),
  ('region', 'cn', '중국', 'China', '{}', NULL, '{region}', '{}', '2.0.0', '1530', 'true'),
  ('region', 'cn_ningxia', '닝샤', 'Ningxia', '{}', 'cn', '{region}', '{}', '2.0.0', '1540', 'true'),
  ('region', 'cn_north_east_region', '북동부 지방', 'North East Region', '{}', 'cn', '{region}', '{}', '2.0.0', '1550', 'true'),
  ('region', 'cn_shandong_peninsula', '산둥', 'Shandong Peninsula', '{}', 'cn', '{region}', '{}', '2.0.0', '1570', 'true'),
  ('region', 'cz', '체코', 'Czechia', '{}', NULL, '{region}', '{}', '2.0.0', '1580', 'true'),
  ('region', 'de', '독일', 'Germany', '{}', NULL, '{region}', '{}', '2.0.0', '1590', 'true'),
  ('region', 'de_baden', '바덴', 'Baden', '{}', 'de', '{region}', '{}', '2.0.0', '1600', 'true'),
  ('region', 'de_bayern', '바이에른', 'Bayern', '{}', 'de', '{region}', '{}', '2.0.0', '1610', 'true'),
  ('region', 'de_bereich_bernkastel', '베라이히 베른카슈텔', 'Bereich Bernkastel', '{}', 'de_mosel_saar_ruwer', '{region}', '{}', '2.0.0', '1690', 'true'),
  ('region', 'de_bernkastel', '베른카스텔', 'Bernkastel', '{}', 'de_mosel_saar_ruwer', '{region}', '{}', '2.0.0', '1700', 'true'),
  ('region', 'de_bernkastel_kues', '베른카스텔-쿠에스', 'Bernkastel-Kues', '{}', 'de_bernkastel', '{region}', '{}', '2.0.0', '1780', 'true'),
  ('region', 'de_blankenhornsberger', '블랑켄호른스베르거', 'Blankenhornsberger', '{}', 'de_baden', '{region}', '{}', '2.0.0', '1710', 'true'),
  ('region', 'de_franken', '프랑켄', 'Franken', '{}', 'de', '{region}', '{}', '2.0.0', '1620', 'true'),
  ('region', 'de_mosel', '모젤', 'Mosel', '{}', 'de', '{region}', '{}', '2.0.0', '1630', 'true'),
  ('region', 'de_mosel_saar_ruwer', '모젤-자르-루버', 'Mosel-Saar-Ruwer', '{}', 'de', '{region}', '{}', '2.0.0', '1640', 'true'),
  ('region', 'de_nahe', '나헤', 'Nahe', '{}', 'de', '{region}', '{}', '2.0.0', '1650', 'true'),
  ('region', 'de_nurnberger', '뉘른베르크', 'Nurnberger', '{}', 'de_bayern', '{region}', '{}', '2.0.0', '1720', 'true'),
  ('region', 'de_pfalz', '팔츠', 'Pfalz', '{}', 'de', '{region}', '{}', '2.0.0', '1660', 'true'),
  ('region', 'de_piesport', '피스포트', 'Piesport', '{}', 'de_mosel_saar_ruwer', '{region}', '{}', '2.0.0', '1730', 'true'),
  ('region', 'de_rheingau', '라인가우', 'Rheingau', '{}', 'de', '{region}', '{}', '2.0.0', '1670', 'true'),
  ('region', 'de_rheinhessen', '라인헤센', 'Rheinhessen', '{}', 'de', '{region}', '{}', '2.0.0', '1680', 'true'),
  ('region', 'de_winningen_rottegen', '위닝겐 뢰트겐', 'Winningen Rottegen', '{}', 'de_mosel_saar_ruwer', '{region}', '{}', '2.0.0', '1740', 'true'),
  ('region', 'de_winninger_domgarten', '위닝겐 돔가르텐', 'Winninger Domgarten', '{}', 'de_mosel_saar_ruwer', '{region}', '{}', '2.0.0', '1750', 'true'),
  ('region', 'de_winninger_hamm', '위닝겐 햄', 'Winninger Hamm', '{}', 'de_mosel_saar_ruwer', '{region}', '{}', '2.0.0', '1760', 'true'),
  ('region', 'de_winninger_uhlen_rottegen', '위닝겐 울렌 & 뢰트겐', 'Winninger Uhlen & Rottegen', '{}', 'de_mosel_saar_ruwer', '{region}', '{}', '2.0.0', '1770', 'true'),
  ('region', 'dk', '덴마크', 'Denmark', '{}', NULL, '{region}', '{}', '2.0.0', '1790', 'true'),
  ('region', 'eg', '이집트', 'Egypt', '{}', NULL, '{region}', '{}', '2.0.0', '1800', 'true'),
  ('region', 'es', '스페인', 'Spain', '{}', NULL, '{region}', '{}', '2.0.0', '1810', 'true'),
  ('region', 'es_', 'Extremadura', '엑스트라마두라', '{}', 'es', '{region}', '{}', '2.0.0', '1820', 'true'),
  ('region', 'es_alella', '알레야', 'Alella', '{}', 'es', '{region}', '{}', '2.0.0', '1830', 'true'),
  ('region', 'es_alicante', '알리칸테', 'Alicante', '{}', 'es_valencia', '{region}', '{}', '2.0.0', '2310', 'true'),
  ('region', 'es_almansa', '알만사', 'Almansa', '{}', 'es_castilla', '{region}', '{}', '2.0.0', '2320', 'true'),
  ('region', 'es_andalucia', '안달루시아', 'Andalucía', '{}', 'es', '{region}', '{}', '2.0.0', '1840', 'true'),
  ('region', 'es_aragon', '아라곤', 'Aragon', '{}', 'es', '{region}', '{}', '2.0.0', '1850', 'true'),
  ('region', 'es_bierzo', '비에르소', 'Bierzo', '{}', 'es_castilla', '{region}', '{}', '2.0.0', '2330', 'true'),
  ('region', 'es_binissalem_mallorca', '비니살렘 마요르카', 'Binissalem Mallorca', '{}', 'es', '{region}', '{}', '2.0.0', '1860', 'true'),
  ('region', 'es_bizkaiko_txakolina', '비즈카이코 차콜리나', 'Bizkaiko Txakolina', '{}', 'es', '{region}', '{}', '2.0.0', '1870', 'true'),
  ('region', 'es_bullas', '부야스', 'Bullas', '{}', 'es', '{region}', '{}', '2.0.0', '1880', 'true'),
  ('region', 'es_calatayud', '칼라타유드', 'Calatayud', '{깔라따유드}', 'es_aragon', '{region}', '{}', '2.0.0', '2340', 'true'),
  ('region', 'es_campo_de_borja', '캄포 데 보르하', 'Campo de Borja', '{}', 'es_aragon', '{region}', '{}', '2.0.0', '2350', 'true'),
  ('region', 'es_carinena', '까리네냐', 'Carinena', '{}', 'es_aragon', '{region}', '{}', '2.0.0', '2360', 'true'),
  ('region', 'es_castilla', '카스티야', 'Castilla', '{}', 'es', '{region}', '{}', '2.0.0', '1890', 'true'),
  ('region', 'es_castilla_la_mancha', '카스티야 라 만차', 'Castilla-La Mancha', '{}', 'es', '{region}', '{}', '2.0.0', '1900', 'true'),
  ('region', 'es_castilla_y_leon', '카스티야 이 레옹', 'Castilla Y Leon', '{}', 'es_leon', '{region}', '{}', '2.0.0', '2370', 'true'),
  ('region', 'es_cataluna', '까탈루냐', 'Cataluna', '{}', 'es', '{region}', '{}', '2.0.0', '1910', 'true'),
  ('region', 'es_cava', '까바', 'Cava', '{}', 'es', '{region}', '{}', '2.0.0', '1920', 'true'),
  ('region', 'es_cigales', '시갈레스', 'Cigales', '{}', 'es', '{region}', '{}', '2.0.0', '1930', 'true'),
  ('region', 'es_conca_de_barbera', '콘카 데 바르베라', 'Conca de Barbera', '{}', 'es', '{region}', '{}', '2.0.0', '1940', 'true'),
  ('region', 'es_costers_del_segre', '코스터스 델 세그레', 'Costers del Segre', '{}', 'es', '{region}', '{}', '2.0.0', '1950', 'true'),
  ('region', 'es_dominio_de_valdepusa', '도미니오 데 발데푸사', 'Dominio de Valdepusa', '{}', 'es', '{region}', '{}', '2.0.0', '1960', 'true'),
  ('region', 'es_emporda', '엠포르다', 'Empordà', '{}', 'es', '{region}', '{}', '2.0.0', '1970', 'true'),
  ('region', 'es_extremandura', '에스트레마두라', 'Extremandura', '{}', 'es', '{region}', '{}', '2.0.0', '1980', 'true'),
  ('region', 'es_galicia', '갈리시아', 'Galicia', '{}', 'es', '{region}', '{}', '2.0.0', '1990', 'true'),
  ('region', 'es_getariako_txakolina', '게타리아코 차콜리나', 'Getariako Txakolina', '{}', 'es', '{region}', '{}', '2.0.0', '2000', 'true'),
  ('region', 'es_jerez_xeres_sherry', '헤레즈-헤레스-셰리', 'Jerez-Xeres-Sherry', '{}', 'es', '{region}', '{}', '2.0.0', '2010', 'true'),
  ('region', 'es_jumilla', '후미야', 'Jumilla', '{}', 'es', '{region}', '{}', '2.0.0', '2020', 'true'),
  ('region', 'es_la_mancha', '라 만차', 'La Mancha', '{}', 'es', '{region}', '{}', '2.0.0', '2030', 'true'),
  ('region', 'es_leon', '레온', 'Leon', '{}', 'es', '{region}', '{}', '2.0.0', '2040', 'true'),
  ('region', 'es_malaga', '말라가', 'Malaga', '{}', 'es', '{region}', '{}', '2.0.0', '2050', 'true'),
  ('region', 'es_manchuela', '만추엘라', 'Manchuela', '{}', 'es', '{region}', '{}', '2.0.0', '2060', 'true'),
  ('region', 'es_manzanilla_sanlucar_de_barrameda', '만자니아 산루카 데 바라메다', 'Manzanilla Sanlucar de Barrameda', '{}', 'es', '{region}', '{}', '2.0.0', '2070', 'true'),
  ('region', 'es_mentrida', '멘트리다', 'Mentrida', '{}', 'es', '{region}', '{}', '2.0.0', '2080', 'true'),
  ('region', 'es_montilla_moriles', '몬티야 모리레스', 'Montilla Moriles', '{}', 'es_andalucia', '{region}', '{}', '2.0.0', '2380', 'true'),
  ('region', 'es_montsant', '몬산트', 'Montsant', '{}', 'es', '{region}', '{}', '2.0.0', '2090', 'true'),
  ('region', 'es_murcia', '무르시아', 'Murcia', '{}', 'es_jumilla', '{region}', '{}', '2.0.0', '2390', 'true'),
  ('region', 'es_navarra', '나바라', 'Navarra', '{}', 'es', '{region}', '{}', '2.0.0', '2100', 'true'),
  ('region', 'es_ourense', '오우렌세', 'Ourense', '{}', 'es', '{region}', '{}', '2.0.0', '2110', 'true'),
  ('region', 'es_penedes', '페네데스', 'Penedes', '{}', 'es_cataluna', '{region}', '{}', '2.0.0', '2400', 'true'),
  ('region', 'es_pla_de_bages', '플라 데 바제스', 'Pla de Bages', '{}', 'es', '{region}', '{}', '2.0.0', '2120', 'true'),
  ('region', 'es_priorat', '프리오랏', 'Priorat', '{}', 'es_cataluna', '{region}', '{}', '2.0.0', '2410', 'true'),
  ('region', 'es_rias_baixas', '리아스 바이사스', 'Rias Baixas', '{}', 'es', '{region}', '{}', '2.0.0', '2130', 'true'),
  ('region', 'es_ribeira_sacra', '리베이라 사크라', 'Ribeira Sacra', '{}', 'es', '{region}', '{}', '2.0.0', '2140', 'true'),
  ('region', 'es_ribeiro', '리베이로', 'Ribeiro', '{}', 'es', '{region}', '{}', '2.0.0', '2150', 'true'),
  ('region', 'es_ribera_del_duero', '리베라 델 두에로', 'Ribera del Duero', '{}', 'es', '{region}', '{}', '2.0.0', '2160', 'true'),
  ('region', 'es_ribera_del_guadiana', '리베라 델 구아디아나', 'Ribera del Guadiana', '{}', 'es', '{region}', '{}', '2.0.0', '2170', 'true'),
  ('region', 'es_ribera_del_jucar', '리베라 델 후카르', 'Ribera del Jucar', '{}', 'es', '{region}', '{}', '2.0.0', '2180', 'true'),
  ('region', 'es_rioja', '리오하', 'Rioja', '{}', 'es', '{region}', '{}', '2.0.0', '2190', 'true'),
  ('region', 'es_rioja_alta', '리오하 알타', 'Rioja Alta', '{}', 'es_rioja', '{region}', '{}', '2.0.0', '2420', 'true'),
  ('region', 'es_rueda', '루에다', 'Rueda', '{}', 'es', '{region}', '{}', '2.0.0', '2200', 'true'),
  ('region', 'es_sierras_de_malaga', '시에라 데 말라가', 'Sierras de Malaga', '{}', 'es', '{region}', '{}', '2.0.0', '2210', 'true'),
  ('region', 'es_somontano', '소몬타노', 'Somontano', '{}', 'es_aragon', '{region}', '{}', '2.0.0', '2430', 'true'),
  ('region', 'es_tarragona', '타라고나', 'Tarragona', '{}', 'es', '{region}', '{}', '2.0.0', '2220', 'true'),
  ('region', 'es_terra_alta', '테라 알타', 'Terra Alta', '{}', 'es', '{region}', '{}', '2.0.0', '2230', 'true'),
  ('region', 'es_toro', '토로', 'Toro', '{}', 'es_castilla', '{region}', '{}', '2.0.0', '2440', 'true'),
  ('region', 'es_utiel_requena', '우티엘 레께나', 'Utiel Requena', '{}', 'es', '{region}', '{}', '2.0.0', '2240', 'true'),
  ('region', 'es_valdeorras', '발데오라스', 'Valdeorras', '{}', 'es', '{region}', '{}', '2.0.0', '2250', 'true'),
  ('region', 'es_valdepenas', '발데페냐스', 'Valdepenas', '{}', 'es', '{region}', '{}', '2.0.0', '2260', 'true'),
  ('region', 'es_valencia', '발렌시아', 'Valencia', '{}', 'es', '{region}', '{}', '2.0.0', '2270', 'true'),
  ('region', 'es_valle_de_la_orotava', '발레 데 라 오로타바', 'Valle de La Orotava', '{}', 'es', '{region}', '{}', '2.0.0', '2280', 'true'),
  ('region', 'es_vinos_de_madrid', '비노스 데 마드리드', 'Vinos de Madrid', '{마드리드}', 'es', '{region}', '{}', '2.0.0', '2290', 'true'),
  ('region', 'es_yecla', '예클라', 'Yecla', '{}', 'es', '{region}', '{}', '2.0.0', '2300', 'true'),
  ('region', 'fi', '핀란드', 'Finland', '{}', NULL, '{region}', '{}', '2.0.0', '2450', 'true'),
  ('region', 'fr', '프랑스', 'France', '{}', NULL, '{region}', '{}', '2.0.0', '2460', 'true'),
  ('region', 'fr_aloxe_corton', '알록스-꼬르통', 'Aloxe-Corton', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '3620', 'true'),
  ('region', 'fr_alsace', '알자스', 'Alsace', '{}', 'fr', '{region}', '{}', '2.0.0', '2470', 'true'),
  ('region', 'fr_anjou', '앙주', 'Anjou', '{}', 'fr_anjou_saumur', '{region}', '{}', '2.0.0', '3630', 'true'),
  ('region', 'fr_anjou_saumur', '앙쥬-소뮈르', 'Anjou-Saumur', '{}', 'fr_loire', '{region}', '{}', '2.0.0', '2700', 'true'),
  ('region', 'fr_arbois', '아흐보아', 'Arbois', '{}', 'fr_jura', '{region}', '{}', '2.0.0', '2710', 'true'),
  ('region', 'fr_ardeche', '아르데슈', 'Ardeche', '{}', 'fr_provence', '{region}', '{}', '2.0.0', '3640', 'true'),
  ('region', 'fr_armagnac', '아르마냑', 'Armagnac', '{}', 'fr', '{region}', '{}', '2.0.0', '2480', 'true'),
  ('region', 'fr_auxey_duresses', '오쎄-뒤레쓰', 'Auxey-Duresses', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '3650', 'true'),
  ('region', 'fr_bandol', '방돌', 'Bandol', '{}', 'fr_provence', '{region}', '{}', '2.0.0', '3660', 'true'),
  ('region', 'fr_banyuls', '바뉠스', 'Banyuls', '{}', 'fr_languedoc_roussillon', '{region}', '{}', '2.0.0', '3670', 'true'),
  ('region', 'fr_barsac', '바르삭', 'Barsac', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '2720', 'true'),
  ('region', 'fr_bas_rhin', '바 랭', 'Bas Rhin', '{}', 'fr_alsace', '{region}', '{}', '2.0.0', '2730', 'true'),
  ('region', 'fr_beaujolais', '보졸레', 'Beaujolais', '{}', 'fr_bourgogne', '{region}', '{}', '2.0.0', '2740', 'true'),
  ('region', 'fr_beaune', '본', 'Beaune', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '3680', 'true'),
  ('region', 'fr_bergerac', '베르쥬악', 'Bergerac', '{베르주라크}', 'fr_southwest_france', '{region}', '{}', '2.0.0', '2750', 'true'),
  ('region', 'fr_blagny', '블라니', 'Blagny', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '3690', 'true'),
  ('region', 'fr_blaye', '블라이', 'Blaye', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '2760', 'true'),
  ('region', 'fr_blaye_cotes_de_bordeaux', '블라이 꼬뜨 드 보르도', 'Blaye Cotes de Bordeaux', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '2770', 'true'),
  ('region', 'fr_bonnezeaux', '본죠', 'Bonnezeaux', '{}', 'fr_anjou_saumur', '{region}', '{}', '2.0.0', '3700', 'true'),
  ('region', 'fr_bordeaux', '보르도', 'Bordeaux', '{}', 'fr', '{region}', '{}', '2.0.0', '2490', 'true'),
  ('region', 'fr_bordeaux_cotes_de_francs', '보르도 꼬뜨 드 프랑', 'Bordeaux Côtes de Francs', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '2780', 'true'),
  ('region', 'fr_bordeaux_superieur', '보르도 쒸뻬리외르', 'Bordeaux Superieur', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '2790', 'true'),
  ('region', 'fr_bourgogne', '부르고뉴', 'Bourgogne', '{}', 'fr', '{region}', '{}', '2.0.0', '2500', 'true'),
  ('region', 'fr_bourgogne_cote_chalonnaise', '부르고뉴 꼬뜨 샬로네즈', 'Bourgogne cote Chalonnaise', '{}', 'fr_cote_chalonnaise', '{region}', '{}', '2.0.0', '3710', 'true'),
  ('region', 'fr_bourgogne_hautes_cotes_de_beaune', '부르고뉴 오뜨 꼬뜨 드 본', 'Bourgogne Hautes Côtes de Beaune', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '3720', 'true'),
  ('region', 'fr_bourgogne_hautes_cotes_de_nuits', '부르고뉴 오뜨 꼬뜨 드 뉘', 'Bourgogne Hautes Côtes de Nuits', '{}', 'fr_cote_de_nuits', '{region}', '{}', '2.0.0', '3730', 'true'),
  ('region', 'fr_bourgueil', '부르괴이', 'Bourgueil', '{}', 'fr_touraine', '{region}', '{}', '2.0.0', '3740', 'true'),
  ('region', 'fr_bouzeron', '부즈롱', 'Bouzeron', '{}', 'fr_cote_chalonnaise', '{region}', '{}', '2.0.0', '3750', 'true'),
  ('region', 'fr_brouilly', '브루이', 'Brouilly', '{}', 'fr_beaujolais', '{region}', '{}', '2.0.0', '3760', 'true'),
  ('region', 'fr_buzet', '뷔제', 'Buzet', '{}', 'fr_southwest_france', '{region}', '{}', '2.0.0', '2800', 'true'),
  ('region', 'fr_cadillac_cotes_de_bordeaux', '까디약 꼬뜨 드 보르도', 'Cadillac Cotes de Bordeaux', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '2810', 'true'),
  ('region', 'fr_cahors', '까오르', 'Cahors', '{}', 'fr_southwest_france', '{region}', '{}', '2.0.0', '2820', 'true'),
  ('region', 'fr_cairanne', '께란', 'Cairanne', '{}', 'fr_cotes_du_rhone', '{region}', '{}', '2.0.0', '3770', 'true'),
  ('region', 'fr_calvados', '깔바도스', 'Calvados', '{}', 'fr', '{region}', '{}', '2.0.0', '2510', 'true'),
  ('region', 'fr_canon_fronsac', '까농 프롱삭', 'Canon Fronsac', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '2830', 'true'),
  ('region', 'fr_castillon_cotes_de_bordeaux', '까스띠용 꼬뜨 드 보르도', 'Castillon Côtes de Bordeaux', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '2840', 'true'),
  ('region', 'fr_central_loire', '센트럴 루아르', 'Central Loire', '{}', 'fr_loire', '{region}', '{}', '2.0.0', '2850', 'true'),
  ('region', 'fr_chablis', '샤블리', 'Chablis', '{}', 'fr_bourgogne', '{region}', '{}', '2.0.0', '2860', 'true'),
  ('region', 'fr_chablis_grand_cru', '샤블리 그랑 크뤼', 'Chablis Grand Cru', '{}', 'fr_chablis', '{region}', '{}', '2.0.0', '3780', 'true'),
  ('region', 'fr_chablis_premier_cru', '샤블리 프리미에 크뤼', 'Chablis Premier Cru', '{}', 'fr_chablis', '{region}', '{}', '2.0.0', '3790', 'true'),
  ('region', 'fr_chambolle_musigny', '샹볼 뮈지니', 'Chambolle Musigny', '{}', 'fr_cote_de_nuits', '{region}', '{}', '2.0.0', '3800', 'true'),
  ('region', 'fr_champagne', '샹빠뉴', 'Champagne', '{}', 'fr', '{region}', '{}', '2.0.0', '2530', 'true'),
  ('region', 'fr_chassagne_montrachet', '샤샤뉴-몽라셰', 'Chassagne-Montrachet', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '3810', 'true'),
  ('region', 'fr_chateau_chalon', '샤또-살롱', 'Chateau-Chalon', '{}', 'fr_jura', '{region}', '{}', '2.0.0', '2870', 'true'),
  ('region', 'fr_chateau_grillet', '샤또-그리에', 'Chateau-Grillet', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '2880', 'true'),
  ('region', 'fr_chateauneuf_du_pape', '샤또네프 뒤 빠쁘', 'Chateauneuf du Pape', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '2890', 'true'),
  ('region', 'fr_chenas', '쉐나', 'Chenas', '{}', 'fr_beaujolais', '{region}', '{}', '2.0.0', '3820', 'true'),
  ('region', 'fr_chinon', '쉬농', 'Chinon', '{}', 'fr_touraine', '{region}', '{}', '2.0.0', '3830', 'true'),
  ('region', 'fr_chorey_les_beaune', '쇼레이 레 본', 'Chorey-les-Beaune', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '3840', 'true'),
  ('region', 'fr_cognac', '꼬냑', 'Cognac', '{}', 'fr', '{region}', '{}', '2.0.0', '2540', 'true'),
  ('region', 'fr_condrieu', '꽁드리유', 'Condrieu', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '2910', 'true'),
  ('region', 'fr_corbieres', '꼬르비에르', 'Corbieres', '{}', 'fr_languedoc_roussillon', '{region}', '{}', '2.0.0', '3850', 'true'),
  ('region', 'fr_cornas', '꼬르나스', 'Cornas', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '2920', 'true'),
  ('region', 'fr_corsica', '코르시카', 'Corsica', '{}', 'fr', '{region}', '{}', '2.0.0', '2550', 'true'),
  ('region', 'fr_costieres_de_nimes', '꼬스띠에르 드 님', 'Costieres de Nîmes', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '2930', 'true'),
  ('region', 'fr_cote_chalonnaise', '꼬뜨 샬로네즈', 'Côte Chalonnaise', '{}', 'fr_bourgogne', '{region}', '{}', '2.0.0', '2940', 'true'),
  ('region', 'fr_cote_d_or', '꼬뜨 도르', 'Cote d''Or', '{}', 'fr_bourgogne', '{region}', '{}', '2.0.0', '2950', 'true'),
  ('region', 'fr_cote_de_beaune', '꼬뜨 드 본', 'Côte de Beaune', '{}', 'fr_bourgogne', '{region}', '{}', '2.0.0', '2960', 'true'),
  ('region', 'fr_cote_de_beaune_villages', '꼬뜨 드 본-빌라쥬', 'Côte de Beaune-Villages', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '3860', 'true'),
  ('region', 'fr_cote_de_brouilly', '꼬뜨 드 브루이', 'Côte de Brouilly', '{}', 'fr_beaujolais', '{region}', '{}', '2.0.0', '3870', 'true'),
  ('region', 'fr_cote_de_nuits', '꼬뜨 드 뉘', 'Côte de Nuits', '{}', 'fr_bourgogne', '{region}', '{}', '2.0.0', '2970', 'true'),
  ('region', 'fr_cote_de_nuits_villages', '꼬뜨 드 뉘-빌라쥬', 'Côte de Nuits-Villages', '{}', 'fr_cote_de_nuits', '{region}', '{}', '2.0.0', '3880', 'true'),
  ('region', 'fr_cote_de_sezanne', '꼬뜨 드 세잔느', 'Côte de Sezanne', '{}', 'fr_champagne', '{region}', '{}', '2.0.0', '2980', 'true'),
  ('region', 'fr_cote_des_bar', '꼬뜨 데 바', 'Côte des Bar', '{"꼬뜨 드 바"}', 'fr_champagne', '{region}', '{}', '2.0.0', '2990', 'true'),
  ('region', 'fr_cote_des_blancs', '꼬뜨 데 블랑', 'Côte des Blancs', '{}', 'fr_champagne', '{region}', '{}', '2.0.0', '3000', 'true'),
  ('region', 'fr_cote_rotie', '꼬뜨 로띠', 'Côte-Rotie', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3010', 'true'),
  ('region', 'fr_coteaux_d_aix_en_provence', '꼬또 닥상 프로방스', 'Côteaux d''Aix en Provence', '{}', 'fr_provence', '{region}', '{}', '2.0.0', '3890', 'true'),
  ('region', 'fr_coteaux_de_l_aubance', '꼬또 드 로방스', 'Côteaux de l''Aubance', '{}', 'fr_anjou_saumur', '{region}', '{}', '2.0.0', '3900', 'true'),
  ('region', 'fr_coteaux_du_languedoc', '꼬또 뒤 랑그독', 'Côteaux du Languedoc', '{}', 'fr_languedoc_roussillon', '{region}', '{}', '2.0.0', '3910', 'true'),
  ('region', 'fr_coteaux_du_layon', '꼬또 뒤 레이옹', 'Côteaux du Layon', '{}', 'fr_anjou_saumur', '{region}', '{}', '2.0.0', '3920', 'true'),
  ('region', 'fr_cotes_de_bergerac', '꼬뜨 드 베르쥬악', 'Côtes de Bergerac', '{}', 'fr_southwest_france', '{region}', '{}', '2.0.0', '3020', 'true'),
  ('region', 'fr_cotes_de_blaye', '꼬뜨 드 블라이', 'Côtes de Blaye', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3030', 'true'),
  ('region', 'fr_cotes_de_bourg', '꼬뜨 드 부르그', 'Côtes de Bourg', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3040', 'true'),
  ('region', 'fr_cotes_de_duras', '꼬뜨 드 뒤라', 'Côtes de Duras', '{}', 'fr_southwest_france', '{region}', '{}', '2.0.0', '3050', 'true'),
  ('region', 'fr_cotes_de_frontonnais', '꼬뜨 드 프롱또네', 'Côtes de Frontonnais', '{}', 'fr_southwest_france', '{region}', '{}', '2.0.0', '3060', 'true'),
  ('region', 'fr_cotes_de_gascogne', '꼬뜨 드 가스꼬뉴', 'Côtes de Gascogne', '{가스꼬뉴,가스코뉴}', 'fr_southwest_france', '{region}', '{}', '2.0.0', '3070', 'true'),
  ('region', 'fr_cotes_de_provence', '꼬뜨 드 프로방스', 'Côtes de Provence', '{}', 'fr_provence', '{region}', '{}', '2.0.0', '3930', 'true'),
  ('region', 'fr_cotes_de_roussillon', '꼬뜨 드 루씨용', 'Côtes de Roussillon', '{}', 'fr_languedoc_roussillon', '{region}', '{}', '2.0.0', '3940', 'true'),
  ('region', 'fr_cotes_du_jura', '꼬뜨 뒤 쥐라', 'Cotes du Jura', '{}', 'fr_jura', '{region}', '{}', '2.0.0', '3080', 'true'),
  ('region', 'fr_cotes_du_luberon', '꼬뜨 뒤 뤼베롱', 'Côtes du Luberon', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3090', 'true'),
  ('region', 'fr_cotes_du_marmandais', '꼬뜨 뒤 마랑데', 'Côtes du Marmandais', '{}', 'fr_southwest_france', '{region}', '{}', '2.0.0', '3100', 'true'),
  ('region', 'fr_cotes_du_rhone', '꼬뜨 뒤 론', 'Côtes du Rhone', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3110', 'true'),
  ('region', 'fr_cotes_du_roussillon_villages', '꼬뜨 드 루씨용 빌라쥬', 'Côtes du Roussillon Villages', '{}', 'fr_languedoc_roussillon', '{region}', '{}', '2.0.0', '3950', 'true'),
  ('region', 'fr_cotes_du_ventoux', '꼬뜨 뒤 벙뚜', 'Côtes du Ventoux', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3120', 'true'),
  ('region', 'fr_cotes_du_vivarais', '꼬뜨 뒤 비바레', 'Côtes du Vivarais', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3130', 'true'),
  ('region', 'fr_crozes_hermitage', '크로즈-에르미타주', 'Crozes-Hermitage', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3140', 'true'),
  ('region', 'fr_entre_deux_mers', '엉트르-두-메르', 'Entre-Deux-Mers', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3150', 'true'),
  ('region', 'fr_faugeres', '포줴흐', 'Faugeres', '{}', 'fr_languedoc_roussillon', '{region}', '{}', '2.0.0', '3960', 'true'),
  ('region', 'fr_fitou', '피투', 'Fitou', '{}', 'fr_languedoc_roussillon', '{region}', '{}', '2.0.0', '3970', 'true'),
  ('region', 'fr_fixin', '픽상', 'Fixin', '{}', 'fr_cote_de_nuits', '{region}', '{}', '2.0.0', '3980', 'true'),
  ('region', 'fr_flageyechezeaux', '플라제 에세죠', 'Flagey‐Échezeaux', '{}', 'fr_cote_de_nuits', '{region}', '{}', '2.0.0', '3990', 'true'),
  ('region', 'fr_fleurie', '플뢰리', 'Fleurie', '{}', 'fr_beaujolais', '{region}', '{}', '2.0.0', '4000', 'true'),
  ('region', 'fr_francs_cotes_de_bordeaux', '프랑 꼬뜨 드 보르도', 'Francs Côtes de Bordeaux', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3160', 'true'),
  ('region', 'fr_fronsac', '프롱삭', 'Fronsac', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3170', 'true'),
  ('region', 'fr_gaillac', '가이약', 'Gaillac', '{}', 'fr_southwest_france', '{region}', '{}', '2.0.0', '3180', 'true'),
  ('region', 'fr_gard', '가드', 'Gard', '{}', 'fr', '{region}', '{}', '2.0.0', '2560', 'true'),
  ('region', 'fr_gevrey_chambertin', '쥬브레-샹베르땅', 'Gevrey-Chambertin', '{}', 'fr_cote_de_nuits', '{region}', '{}', '2.0.0', '4010', 'true'),
  ('region', 'fr_gigondas', '지공다스', 'Gigondas', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3190', 'true'),
  ('region', 'fr_givry', '지브리', 'Givry', '{}', 'fr_cote_chalonnaise', '{region}', '{}', '2.0.0', '4020', 'true'),
  ('region', 'fr_graves', '그라브', 'Graves', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3200', 'true'),
  ('region', 'fr_graves_de_vayres', '그라브-드-베르', 'Graves-de-Vayres', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3210', 'true'),
  ('region', 'fr_graves_superieures', '그라브 수페리외르', 'Graves Superieures', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3220', 'true'),
  ('region', 'fr_haut_medoc', '오-메독', 'Haut-Medoc', '{}', 'fr_medoc', '{region}', '{}', '2.0.0', '4030', 'true'),
  ('region', 'fr_haut_rhin', '오 랭', 'Haut Rhin', '{}', 'fr_alsace', '{region}', '{}', '2.0.0', '3230', 'true'),
  ('region', 'fr_hautes_cotes_de_nuits', '오뜨 꼬뜨 드 뉘', 'Hautes-Côtes de Nuits', '{}', 'fr_bourgogne', '{region}', '{}', '2.0.0', '3240', 'true'),
  ('region', 'fr_hermitage', '에르미타주', 'Hermitage', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3250', 'true'),
  ('region', 'fr_irancy', '이랑시', 'Irancy', '{}', 'fr_chablis', '{region}', '{}', '2.0.0', '4040', 'true'),
  ('region', 'fr_julienas', '쥘리에나', 'Julienas', '{}', 'fr_beaujolais', '{region}', '{}', '2.0.0', '4050', 'true'),
  ('region', 'fr_jura', '쥐라', 'Jura', '{}', 'fr', '{region}', '{}', '2.0.0', '2570', 'true'),
  ('region', 'fr_jurancon', '쥐랑송', 'Jurancon', '{}', 'fr_southwest_france', '{region}', '{}', '2.0.0', '3260', 'true'),
  ('region', 'fr_ladoix', '라두와', 'Ladoix', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '4060', 'true'),
  ('region', 'fr_lalande_de_pomerol', '라랑드 드 뽀므롤', 'Lalande de Pomerol', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3270', 'true'),
  ('region', 'fr_languedoc', '랑그독', 'Languedoc', '{}', 'fr', '{region}', '{}', '2.0.0', '2580', 'true'),
  ('region', 'fr_languedoc_roussillon', '랑그독 루씨용', 'Languedoc Roussillon', '{}', 'fr_southern_france', '{region}', '{}', '2.0.0', '3280', 'true'),
  ('region', 'fr_limoux', '리무', 'Limoux', '{}', 'fr_languedoc_roussillon', '{region}', '{}', '2.0.0', '4070', 'true'),
  ('region', 'fr_lirac', '리락', 'Lirac', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3290', 'true'),
  ('region', 'fr_listrac_medoc', '리스트락-메독', 'Listrac-Medoc', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3300', 'true'),
  ('region', 'fr_loire', '루아르', 'Loire', '{}', 'fr', '{region}', '{}', '2.0.0', '2590', 'true'),
  ('region', 'fr_lorraine', '로렌', 'Lorraine', '{}', 'fr', '{region}', '{}', '2.0.0', '2600', 'true'),
  ('region', 'fr_loupiac', '루피악', 'Loupiac', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3310', 'true'),
  ('region', 'fr_luberon', '루베롱', 'Luberon', '{}', 'fr_provence', '{region}', '{}', '2.0.0', '4080', 'true'),
  ('region', 'fr_lussac_saint_emilion', '뤼싹 생 떼밀리옹', 'Lussac-Saint-Emilion', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3320', 'true'),
  ('region', 'fr_macon', '마꽁', 'Macon', '{}', 'fr_maconnais', '{region}', '{}', '2.0.0', '4090', 'true'),
  ('region', 'fr_macon_villages', '마꽁-빌라쥬', 'Macon-Villages', '{}', 'fr_maconnais', '{region}', '{}', '2.0.0', '4100', 'true'),
  ('region', 'fr_maconnais', '마꼬네', 'Maconnais', '{마코네}', 'fr_bourgogne', '{region}', '{}', '2.0.0', '3330', 'true'),
  ('region', 'fr_madiran', '마디랑', 'Madiran', '{}', 'fr_southwest_france', '{region}', '{}', '2.0.0', '3340', 'true'),
  ('region', 'fr_maranges', '마랑쥬', 'Maranges', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '4110', 'true'),
  ('region', 'fr_margaux', '마고', 'Margaux', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3350', 'true'),
  ('region', 'fr_marsannay', '막사네', 'Marsannay', '{}', 'fr_cote_de_nuits', '{region}', '{}', '2.0.0', '4120', 'true'),
  ('region', 'fr_medoc', '메독', 'Medoc', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3360', 'true'),
  ('region', 'fr_menetou_salon', '메네뚜-살롱', 'Menetou-Salon', '{}', 'fr_central_loire', '{region}', '{}', '2.0.0', '4130', 'true'),
  ('region', 'fr_mercurey', '메르퀴레', 'Mercurey', '{}', 'fr_cote_chalonnaise', '{region}', '{}', '2.0.0', '4140', 'true'),
  ('region', 'fr_meursault', '뫼르소', 'Meursault', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '4150', 'true'),
  ('region', 'fr_minervois', '미네르브와', 'Minervois', '{}', 'fr_languedoc_roussillon', '{region}', '{}', '2.0.0', '4160', 'true'),
  ('region', 'fr_monbazillac', '몽바지악', 'Monbazillac', '{}', 'fr_southwest_france', '{region}', '{}', '2.0.0', '3370', 'true'),
  ('region', 'fr_montagne_de_reims', '몽따뉴 드 랭스', 'Montagne de Reims', '{}', 'fr_champagne', '{region}', '{}', '2.0.0', '3380', 'true'),
  ('region', 'fr_montagne_saint_emilion', '몽따뉴-생-떼밀리옹', 'Montagne-Saint-Emilion', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3390', 'true'),
  ('region', 'fr_montagny', '몽따니', 'Montagny', '{}', 'fr_cote_chalonnaise', '{region}', '{}', '2.0.0', '4170', 'true'),
  ('region', 'fr_monthelie', '몽텔리', 'Monthelie', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '4180', 'true'),
  ('region', 'fr_morey_st_denis', '모레이-생-드니', 'Morey-St-Denis', '{}', 'fr_cote_de_nuits', '{region}', '{}', '2.0.0', '4190', 'true'),
  ('region', 'fr_morgon', '모르공', 'Morgon', '{}', 'fr_beaujolais', '{region}', '{}', '2.0.0', '4200', 'true'),
  ('region', 'fr_moulin_a_vent', '물랭-아-방', 'Moulin-a-Vent', '{}', 'fr_beaujolais', '{region}', '{}', '2.0.0', '4210', 'true'),
  ('region', 'fr_moulis', '물리', 'Moulis', '{}', 'fr_medoc', '{region}', '{}', '2.0.0', '4220', 'true'),
  ('region', 'fr_muscadet', '뮈스까데', 'Muscadet', '{}', 'fr_pays_nantais', '{region}', '{}', '2.0.0', '4230', 'true'),
  ('region', 'fr_muscadet_sevre_et_maine', '뮈스까데 세브르 에 멘느', 'Muscadet Sevre et Maine', '{}', 'fr_pays_nantais', '{region}', '{}', '2.0.0', '4240', 'true'),
  ('region', 'fr_normandi', '노르망디', 'Normandi', '{}', 'fr', '{region}', '{}', '2.0.0', '2610', 'true'),
  ('region', 'fr_nuits_st_georges', '뉘-생-조르쥬', 'Nuits-St-Georges', '{}', 'fr_cote_de_nuits', '{region}', '{}', '2.0.0', '4250', 'true'),
  ('region', 'fr_palette', '빨레뜨', 'Palette', '{}', 'fr_provence', '{region}', '{}', '2.0.0', '4260', 'true'),
  ('region', 'fr_pauillac', '뽀이약', 'Pauillac', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3400', 'true'),
  ('region', 'fr_pays_d_oc', '페이 독', 'Pays d''Oc', '{페이독}', 'fr', '{region}', '{}', '2.0.0', '2620', 'true'),
  ('region', 'fr_pays_nantais', '뻬이 낭떼', 'Pays Nantais', '{}', 'fr_loire', '{region}', '{}', '2.0.0', '3410', 'true'),
  ('region', 'fr_pernand_vergelesses', '뻬르낭-베르즐레스', 'Pernand-Vergelesses', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '4270', 'true'),
  ('region', 'fr_pessac_leognan', '뻬싹-레오냥', 'Pessac-Leognan', '{"빼싹 레오냥"}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3420', 'true'),
  ('region', 'fr_petit_chablis', '쁘띠 샤블리', 'Petit Chablis', '{}', 'fr_chablis', '{region}', '{}', '2.0.0', '4280', 'true'),
  ('region', 'fr_pezenas', '페즈나스', 'Pezenas', '{}', 'fr_southern_france', '{region}', '{}', '2.0.0', '3430', 'true'),
  ('region', 'fr_pomerol', '뽀므롤', 'Pomerol', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3440', 'true'),
  ('region', 'fr_pommard', '뽀마르', 'Pommard', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '4290', 'true'),
  ('region', 'fr_pouilly_fuisse', '뿌이-퓌세', 'Pouilly-Fuisse', '{"푸이 퓌세"}', 'fr_maconnais', '{region}', '{}', '2.0.0', '4300', 'true'),
  ('region', 'fr_pouilly_fume', '뿌이-퓌메', 'Pouilly-Fume', '{"푸이 퓌메"}', 'fr_central_loire', '{region}', '{}', '2.0.0', '4310', 'true'),
  ('region', 'fr_pouilly_loche', '뿌이-로슈', 'Pouilly-Loche', '{}', 'fr_maconnais', '{region}', '{}', '2.0.0', '4320', 'true'),
  ('region', 'fr_pouilly_vinzelles', '뿌이-뱅즐레', 'Pouilly-Vinzelles', '{}', 'fr_maconnais', '{region}', '{}', '2.0.0', '4330', 'true'),
  ('region', 'fr_premieres_cotes_de_blaye', '프리미에 꼬뜨 드 블라이', 'Premieres Côtes de Blaye', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3450', 'true'),
  ('region', 'fr_premieres_cotes_de_bordeaux', '프리미에르 꼬뜨 드 보르도', 'Premieres Côtes de Bordeaux', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3460', 'true'),
  ('region', 'fr_provence', '프로방스', 'Provence', '{}', 'fr_southern_france', '{region}', '{}', '2.0.0', '3470', 'true'),
  ('region', 'fr_puisseguin_saint_emilion', '퓌스갱-생-떼밀리옹', 'Puisseguin-Saint-Emilion', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3480', 'true'),
  ('region', 'fr_puligny_montrachet', '쀨리니-몽라셰', 'Puligny-Montrachet', '{"뿔리니 몽라쉐"}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '4340', 'true'),
  ('region', 'fr_pupillin', '푸퓔랑', 'Pupillin', '{}', 'fr_jura', '{region}', '{}', '2.0.0', '3490', 'true'),
  ('region', 'fr_rasteau', '라스또', 'Rasteau', '{}', 'fr_cotes_du_rhone', '{region}', '{}', '2.0.0', '4350', 'true'),
  ('region', 'fr_regnie', '레니에', 'Regnie', '{}', 'fr_beaujolais', '{region}', '{}', '2.0.0', '4360', 'true'),
  ('region', 'fr_reuilly', '뢰이이', 'Reuilly', '{}', 'fr_central_loire', '{region}', '{}', '2.0.0', '4370', 'true'),
  ('region', 'fr_rhone', '론', 'Rhone', '{}', 'fr', '{region}', '{}', '2.0.0', '2640', 'true'),
  ('region', 'fr_rivesaltes', '리브잘트', 'Rivesaltes', '{}', 'fr_languedoc_roussillon', '{region}', '{}', '2.0.0', '4380', 'true'),
  ('region', 'fr_roussillon', '루시옹', 'Roussillon', '{}', 'fr', '{region}', '{}', '2.0.0', '2650', 'true'),
  ('region', 'fr_rully', '륄리', 'Rully', '{}', 'fr_cote_chalonnaise', '{region}', '{}', '2.0.0', '4390', 'true'),
  ('region', 'fr_sablet', '사블레', 'Sablet', '{}', 'fr_cotes_du_rhone', '{region}', '{}', '2.0.0', '4400', 'true'),
  ('region', 'fr_saint_amour', '생-따무르', 'Saint-Amour', '{}', 'fr_beaujolais', '{region}', '{}', '2.0.0', '4410', 'true'),
  ('region', 'fr_saint_aubin', '생-오방', 'Saint-Aubin', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '4420', 'true'),
  ('region', 'fr_saint_bris', '생-브리', 'Saint-Bris', '{}', 'fr_chablis', '{region}', '{}', '2.0.0', '4430', 'true'),
  ('region', 'fr_saint_emilion', '생-떼밀리옹', 'Saint-Emilion', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3500', 'true'),
  ('region', 'fr_saint_emilion_grand_cru', '생-떼밀리옹 그랑 크뤼', 'Saint-Emilion Grand Cru', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3510', 'true'),
  ('region', 'fr_saint_estephe', '생-떼스테프', 'Saint Estephe', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3520', 'true'),
  ('region', 'fr_saint_joseph', '생-죠셉', 'Saint-Joseph', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3530', 'true'),
  ('region', 'fr_saint_julien', '생-쥴리앙', 'Saint-Julien', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3540', 'true'),
  ('region', 'fr_saint_peray', '생-페레', 'Saint-Peray', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3550', 'true'),
  ('region', 'fr_saint_romain', '생-로망', 'Saint-Romain', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '4440', 'true'),
  ('region', 'fr_saint_veran', '생-베랑', 'Saint Veran', '{"생 베랑"}', 'fr_maconnais', '{region}', '{}', '2.0.0', '4450', 'true'),
  ('region', 'fr_sainte_foy_bordeaux', '생트-푸와-보르도', 'Sainte-Foy-Bordeaux', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3560', 'true'),
  ('region', 'fr_sancerre', '상세르', 'Sancerre', '{}', 'fr_central_loire', '{region}', '{}', '2.0.0', '4460', 'true'),
  ('region', 'fr_santenay', '상트네', 'Santenay', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '4470', 'true'),
  ('region', 'fr_saumur', '소뮈르', 'Saumur', '{}', 'fr_anjou_saumur', '{region}', '{}', '2.0.0', '4480', 'true'),
  ('region', 'fr_saumur_champigny', '소뮈르-샹삐니', 'Saumur-Champigny', '{}', 'fr_anjou_saumur', '{region}', '{}', '2.0.0', '4490', 'true'),
  ('region', 'fr_sauternes', '소테른', 'Sauternes', '{}', 'fr_bordeaux', '{region}', '{}', '2.0.0', '3570', 'true'),
  ('region', 'fr_savennieres', '사브니에르', 'Savennieres', '{}', 'fr_anjou_saumur', '{region}', '{}', '2.0.0', '4500', 'true'),
  ('region', 'fr_savigny_les_beaune', '사비니-레-본', 'Savigny-les-Beaune', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '4510', 'true'),
  ('region', 'fr_savoie', '사부아', 'Savoie', '{}', 'fr', '{region}', '{}', '2.0.0', '2660', 'true'),
  ('region', 'fr_savoie_bugey', '사부아 뷔게이', 'Savoie-Bugey', '{}', 'fr', '{region}', '{}', '2.0.0', '2670', 'true'),
  ('region', 'fr_seguret', '세귀레', 'Seguret', '{}', 'fr_cotes_du_rhone', '{region}', '{}', '2.0.0', '4520', 'true'),
  ('region', 'fr_southern_france', '서던 프랑스', 'Southern France', '{}', 'fr', '{region}', '{}', '2.0.0', '2680', 'true'),
  ('region', 'fr_southwest_france', '사우스웨스트 프랑스', 'Southwest France', '{}', 'fr', '{region}', '{}', '2.0.0', '2690', 'true'),
  ('region', 'fr_st_nicolas_de_bourgueil', '생-니꼴라-드-부르괴이', 'St-Nicolas-de-Bourgueil', '{}', 'fr_touraine', '{region}', '{}', '2.0.0', '4530', 'true'),
  ('region', 'fr_tavel', '따벨', 'Tavel', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3580', 'true'),
  ('region', 'fr_touraine', '뚜렌느', 'Touraine', '{}', 'fr_loire', '{region}', '{}', '2.0.0', '3590', 'true'),
  ('region', 'fr_vacqueyras', '바께이라', 'Vacqueyras', '{}', 'fr_rhone', '{region}', '{}', '2.0.0', '3600', 'true'),
  ('region', 'fr_vallee_de_la_marne', '발레 드 라 마른', 'Vallee de la Marne', '{}', 'fr_champagne', '{region}', '{}', '2.0.0', '3610', 'true'),
  ('region', 'fr_vinsobres', '뱅소브르', 'Vinsobres', '{}', 'fr_cotes_du_rhone', '{region}', '{}', '2.0.0', '4540', 'true'),
  ('region', 'fr_vire_clesse', '비레-클레쎄', 'Vire-Clesse', '{}', 'fr_maconnais', '{region}', '{}', '2.0.0', '4550', 'true'),
  ('region', 'fr_volnay', '볼네', 'Volnay', '{}', 'fr_cote_de_beaune', '{region}', '{}', '2.0.0', '4560', 'true'),
  ('region', 'fr_vosne_romanee', '본-로마네', 'Vosne-Romanee', '{}', 'fr_cote_de_nuits', '{region}', '{}', '2.0.0', '4570', 'true'),
  ('region', 'fr_vougeot', '부조', 'Vougeot', '{}', 'fr_cote_de_nuits', '{region}', '{}', '2.0.0', '4580', 'true'),
  ('region', 'fr_vouvray', '부브레', 'Vouvray', '{}', 'fr_touraine', '{region}', '{}', '2.0.0', '4590', 'true'),
  ('region', 'gb', '영국', 'United Kingdom', '{}', NULL, '{region}', '{}', '2.0.0', '4600', 'true'),
  ('region', 'gb_arran', '아란', 'Arran', '{아란섬}', 'gb_scotland', '{region}', '{}', '2.0.0', '4620', 'true'),
  ('region', 'gb_campbeltown', '캠벨타운', 'Campbeltown', '{}', 'gb_scotland', '{region}', '{}', '2.0.0', '4630', 'true'),
  ('region', 'gb_highland', '하이랜드', 'Highland', '{}', 'gb_scotland', '{region}', '{}', '2.0.0', '4640', 'true'),
  ('region', 'gb_islay', '아일라', 'Islay', '{아일라섬}', 'gb_scotland', '{region}', '{}', '2.0.0', '4650', 'true'),
  ('region', 'gb_jura', '주라', 'Jura', '{주라섬}', 'gb_scotland', '{region}', '{}', '2.0.0', '4660', 'true'),
  ('region', 'gb_lowland', '로우랜드', 'Lowland', '{}', 'gb_scotland', '{region}', '{}', '2.0.0', '4670', 'true'),
  ('region', 'gb_mull', '멀', 'Mull', '{멀섬}', 'gb_scotland', '{region}', '{}', '2.0.0', '4680', 'true'),
  ('region', 'gb_orkney', '오크니', 'Orkney', '{오크니섬}', 'gb_scotland', '{region}', '{}', '2.0.0', '4690', 'true'),
  ('region', 'gb_scotland', '스코틀랜드', 'Scotland', '{}', 'gb', '{region}', '{}', '2.0.0', '4610', 'true'),
  ('region', 'gb_skye', '스카이', 'Skye', '{스카이섬}', 'gb_scotland', '{region}', '{}', '2.0.0', '4700', 'true'),
  ('region', 'gb_speyside', '스페이사이드', 'Speyside', '{}', 'gb_scotland', '{region}', '{}', '2.0.0', '4710', 'true'),
  ('region', 'ge', '조지아', 'Georgia', '{}', NULL, '{region}', '{}', '2.0.0', '4720', 'true'),
  ('region', 'ge_adjara', '앗자라', 'Adjara', '{}', 'ge', '{region}', '{}', '2.0.0', '4730', 'true'),
  ('region', 'ge_guria_samegrelo', '구리아-사메그렐로', 'Guria-Samegrelo', '{}', 'ge', '{region}', '{}', '2.0.0', '4740', 'true'),
  ('region', 'ge_imereti', '이머레티', 'Imereti', '{이메레티}', 'ge', '{region}', '{}', '2.0.0', '4750', 'true'),
  ('region', 'ge_kakheti', '카헤티', 'Kakheti', '{}', 'ge_napareuli', '{region}', '{}', '2.0.0', '4800', 'true'),
  ('region', 'ge_kartli', '카르틀리', 'Kartli', '{}', 'ge', '{region}', '{}', '2.0.0', '4760', 'true'),
  ('region', 'ge_kindzmarauli', '킨즈마라울리', 'Kindzmarauli', '{}', 'ge_kakheti', '{region}', '{}', '2.0.0', '4810', 'true'),
  ('region', 'ge_kisiskhevi', '키시스헤비', 'Kisiskhevi', '{}', 'ge_kakheti', '{region}', '{}', '2.0.0', '4820', 'true'),
  ('region', 'ge_napareuli', '나파레울리', 'Napareuli', '{}', 'ge', '{region}', '{}', '2.0.0', '4770', 'true'),
  ('region', 'ge_racha_lechkhumi', '라차-레흐후미', 'Racha-Lechkhumi', '{}', 'ge', '{region}', '{}', '2.0.0', '4780', 'true'),
  ('region', 'ge_telavi', '텔라비', 'Telavi', '{}', 'ge', '{region}', '{}', '2.0.0', '4790', 'true'),
  ('region', 'gr', '그리스', 'Greece', '{}', NULL, '{region}', '{}', '2.0.0', '4830', 'true'),
  ('region', 'gr_amindeo', '아민데오', 'Amindeo', '{}', 'gr_macedonia', '{region}', '{}', '2.0.0', '4930', 'true'),
  ('region', 'gr_central_greece_and_attica', '센트럴 그리스 앤드 아티카', 'Central Greece and Attica', '{}', 'gr', '{region}', '{}', '2.0.0', '4840', 'true'),
  ('region', 'gr_crete', '크레타', 'Crete', '{}', 'gr', '{region}', '{}', '2.0.0', '4850', 'true'),
  ('region', 'gr_epanomi', '에파노미', 'Epanomi', '{}', 'gr_macedonia', '{region}', '{}', '2.0.0', '4940', 'true'),
  ('region', 'gr_epirus', '에피루스', 'Epirus', '{}', 'gr', '{region}', '{}', '2.0.0', '4860', 'true'),
  ('region', 'gr_macedonia', '마케도니아', 'Macedonia', '{}', 'gr', '{region}', '{}', '2.0.0', '4870', 'true'),
  ('region', 'gr_mantinia', '만티니아', 'Mantinia', '{}', 'gr_peloponnese', '{region}', '{}', '2.0.0', '4950', 'true'),
  ('region', 'gr_naoussa', '나우싸', 'Naoussa', '{}', 'gr_macedonia', '{region}', '{}', '2.0.0', '4960', 'true'),
  ('region', 'gr_nemea', '네메아', 'Nemea', '{}', 'gr_peloponnese', '{region}', '{}', '2.0.0', '4970', 'true'),
  ('region', 'gr_peloponnese', '펠로폰네소스', 'Peloponnese', '{}', 'gr', '{region}', '{}', '2.0.0', '4880', 'true'),
  ('region', 'gr_samos', '사모스', 'Samos', '{}', 'gr', '{region}', '{}', '2.0.0', '4890', 'true'),
  ('region', 'gr_santorini', '산토리니', 'Santorini', '{}', 'gr_the_cyclades_islands', '{region}', '{}', '2.0.0', '4980', 'true'),
  ('region', 'gr_the_cyclades_islands', '더 키클라데스 아일랜드', 'The Cyclades Islands', '{}', 'gr', '{region}', '{}', '2.0.0', '4900', 'true'),
  ('region', 'gr_thessaly', '테살리아', 'Thessaly', '{}', 'gr', '{region}', '{}', '2.0.0', '4910', 'true'),
  ('region', 'gr_thrace', '트라케', 'Thrace', '{}', 'gr', '{region}', '{}', '2.0.0', '4920', 'true'),
  ('region', 'gr_zitsa', '지차', 'Zitsa', '{}', 'gr_epirus', '{region}', '{}', '2.0.0', '4990', 'true'),
  ('region', 'hr', '크로아티아', 'Croatia', '{}', NULL, '{region}', '{}', '2.0.0', '5000', 'true'),
  ('region', 'hr_dalmatia', '달마티아', 'Dalmatia', '{}', 'hr', '{region}', '{}', '2.0.0', '5010', 'true'),
  ('region', 'hu', '헝가리', 'Hungary', '{}', NULL, '{region}', '{}', '2.0.0', '5020', 'true'),
  ('region', 'hu_eger', '에게르', 'Eger', '{}', 'hu_the_northeast', '{region}', '{}', '2.0.0', '5050', 'true'),
  ('region', 'hu_the_northeast', '더 노스이스트', 'The Northeast', '{}', 'hu', '{region}', '{}', '2.0.0', '5030', 'true'),
  ('region', 'hu_tokaj_hegyalja', '토카이-헤갈라야', 'Tokaj-Hegyalja', '{}', 'hu_tokaji', '{region}', '{}', '2.0.0', '5070', 'true'),
  ('region', 'hu_tokaji', '토카이', 'Tokaji', '{}', 'hu_the_northeast', '{region}', '{}', '2.0.0', '5060', 'true'),
  ('region', 'hu_villany', '빌라니', 'Villány', '{}', 'hu', '{region}', '{}', '2.0.0', '5040', 'true'),
  ('region', 'id', '인도네시아', 'Indonesia', '{}', NULL, '{region}', '{}', '2.0.0', '5080', 'true'),
  ('region', 'ie', '아일랜드', 'Ireland', '{}', NULL, '{region}', '{}', '2.0.0', '5090', 'true'),
  ('region', 'il', '이스라엘', 'Israel', '{}', NULL, '{region}', '{}', '2.0.0', '5100', 'true'),
  ('region', 'in', '인도', 'India', '{}', NULL, '{region}', '{}', '2.0.0', '5110', 'true'),
  ('region', 'in_goa', '고아', 'Goa', '{}', 'in', '{region}', '{}', '2.0.0', '5120', 'true'),
  ('region', 'it', '이탈리아', 'Italy', '{}', NULL, '{region}', '{}', '2.0.0', '5130', 'true'),
  ('region', 'it_abruzzo', '아브루쪼', 'Abruzzo', '{}', 'it', '{region}', '{}', '2.0.0', '5140', 'true'),
  ('region', 'it_acqui', '아퀴', 'Acqui', '{}', 'it_piemonte', '{region}', '{}', '2.0.0', '5380', 'true'),
  ('region', 'it_alba', '알바', 'Alba', '{}', 'it_piemonte', '{region}', '{}', '2.0.0', '5390', 'true'),
  ('region', 'it_alto_adige', '알토 아디제', 'Alto Adige', '{}', 'it', '{region}', '{}', '2.0.0', '5150', 'true'),
  ('region', 'it_asti', '아스티', 'Asti', '{}', 'it_piemonte', '{region}', '{}', '2.0.0', '5400', 'true'),
  ('region', 'it_avellino', '아벨리노', 'Avellino', '{}', 'it_campania', '{region}', '{}', '2.0.0', '5410', 'true'),
  ('region', 'it_barbaresco', '바르바레스코', 'Barbaresco', '{}', 'it_piemonte', '{region}', '{}', '2.0.0', '5420', 'true'),
  ('region', 'it_bardolino', '바르돌리노', 'Bardolino', '{}', 'it_veneto', '{region}', '{}', '2.0.0', '5430', 'true'),
  ('region', 'it_barolo', '바롤로', 'Barolo', '{}', 'it_piemonte', '{region}', '{}', '2.0.0', '5440', 'true'),
  ('region', 'it_basilicata', '바실리카타', 'Basilicata', '{}', 'it', '{region}', '{}', '2.0.0', '5160', 'true'),
  ('region', 'it_bolgheri', '볼게리', 'Bolgheri', '{}', 'it_toscana', '{region}', '{}', '2.0.0', '5450', 'true'),
  ('region', 'it_brunello_di_montalcino', '브루넬로 디 몬탈치노', 'Brunello di Montalcino', '{}', 'it_toscana', '{region}', '{}', '2.0.0', '5460', 'true'),
  ('region', 'it_calabria', '칼라브리아', 'Calabria', '{}', 'it', '{region}', '{}', '2.0.0', '5170', 'true'),
  ('region', 'it_campania', '깜빠니아', 'Campania', '{캄파니아}', 'it', '{region}', '{}', '2.0.0', '5190', 'true'),
  ('region', 'it_cannubi', '칸누비', 'Cannubi', '{}', 'it_barolo', '{region}', '{}', '2.0.0', '5810', 'true'),
  ('region', 'it_carmignano', '카르미냐노', 'Carmignano', '{}', 'it_toscana', '{region}', '{}', '2.0.0', '5470', 'true'),
  ('region', 'it_castellina_uga', '카스텔리나 UGA', 'Castellina UGA', '{}', 'it_chianti_classico', '{region}', '{}', '2.0.0', '5820', 'true'),
  ('region', 'it_chianti', '키안티', 'Chianti', '{}', 'it_toscana', '{region}', '{}', '2.0.0', '5480', 'true'),
  ('region', 'it_chianti_classico', '키안티 클라시코', 'Chianti Classico', '{}', 'it_toscana', '{region}', '{}', '2.0.0', '5490', 'true'),
  ('region', 'it_cinque_terre', '친퀘 테레', 'Cinque Terre', '{}', 'it_liguria', '{region}', '{}', '2.0.0', '5500', 'true'),
  ('region', 'it_colli_euganei', '꼴리 에가네이', 'Colli Euganei', '{}', 'it_veneto', '{region}', '{}', '2.0.0', '5510', 'true'),
  ('region', 'it_conegliano', '꼬넬리아노', 'Conegliano', '{}', 'it_veneto', '{region}', '{}', '2.0.0', '5520', 'true'),
  ('region', 'it_conegliano_valdobbiadene', '코넬리아노 발도비아데네', 'Conegliano Valdobbiadene', '{}', 'it_veneto', '{region}', '{}', '2.0.0', '5530', 'true'),
  ('region', 'it_conero', '꼬네로', 'Conero', '{}', 'it_marche', '{region}', '{}', '2.0.0', '5540', 'true'),
  ('region', 'it_emilia', '에밀리아', 'Emilia', '{}', 'it', '{region}', '{}', '2.0.0', '5200', 'true'),
  ('region', 'it_emilia_romagna', '에밀리아 로마냐', 'Emilia-Romagna', '{}', 'it', '{region}', '{}', '2.0.0', '5210', 'true'),
  ('region', 'it_fara_vicentino', '파라 비센티노', 'Fara Vicentino', '{}', 'it_vicenza', '{region}', '{}', '2.0.0', '5830', 'true'),
  ('region', 'it_franciacorta', '프란치아코르타', 'Franciacorta', '{}', 'it_lombardia', '{region}', '{}', '2.0.0', '5550', 'true'),
  ('region', 'it_friuli_venezia_giulia', '프리울리 베네찌아 줄리아', 'Friuli Venezia Giulia', '{}', 'it', '{region}', '{}', '2.0.0', '5220', 'true'),
  ('region', 'it_gattinara', '가띠나라', 'Gattinara', '{}', 'it_piemonte', '{region}', '{}', '2.0.0', '5560', 'true'),
  ('region', 'it_gavi', '가비', 'Gavi', '{}', 'it_piemonte', '{region}', '{}', '2.0.0', '5570', 'true'),
  ('region', 'it_greve_uga', '그레베 UGA', 'Greve UGA', '{}', 'it_chianti_classico', '{region}', '{}', '2.0.0', '5840', 'true'),
  ('region', 'it_irpinia', '이르삐니아', 'Irpinia', '{}', 'it_avellino', '{region}', '{}', '2.0.0', '5850', 'true'),
  ('region', 'it_la_morra', '라 모라', 'La Morra', '{}', 'it_barolo', '{region}', '{}', '2.0.0', '5860', 'true'),
  ('region', 'it_langhe', '랑게', 'Langhe', '{}', 'it_piemonte', '{region}', '{}', '2.0.0', '5580', 'true'),
  ('region', 'it_lazio', '라치오', 'Lazio', '{}', 'it', '{region}', '{}', '2.0.0', '5230', 'true'),
  ('region', 'it_liguria', '리구리아', 'Liguria', '{}', 'it', '{region}', '{}', '2.0.0', '5240', 'true'),
  ('region', 'it_lombardia', '롬바르디아', 'Lombardia', '{}', 'it', '{region}', '{}', '2.0.0', '5250', 'true'),
  ('region', 'it_lugana', '루가나', 'Lugana', '{}', 'it_verona', '{region}', '{}', '2.0.0', '5870', 'true'),
  ('region', 'it_manduria', '만두리아', 'Manduria', '{}', 'it_puglia', '{region}', '{}', '2.0.0', '5590', 'true'),
  ('region', 'it_marche', '마르케', 'Marche', '{}', 'it', '{region}', '{}', '2.0.0', '5260', 'true'),
  ('region', 'it_maremma', '마렘마', 'Maremma', '{}', 'it_toscana', '{region}', '{}', '2.0.0', '5600', 'true'),
  ('region', 'it_molise', '몰리제', 'Molise', '{}', 'it', '{region}', '{}', '2.0.0', '5270', 'true'),
  ('region', 'it_monferrato', '몬페라토', 'Monferrato', '{}', 'it_piemonte', '{region}', '{}', '2.0.0', '5610', 'true'),
  ('region', 'it_montalcino', '몬탈치노', 'Montalcino', '{}', 'it_toscana', '{region}', '{}', '2.0.0', '5620', 'true'),
  ('region', 'it_montefalco', '몬테팔코', 'Montefalco', '{}', 'it_umbria', '{region}', '{}', '2.0.0', '5630', 'true'),
  ('region', 'it_montepulciano', '몬테풀치아노', 'Montepulciano', '{}', 'it_toscana', '{region}', '{}', '2.0.0', '5640', 'true'),
  ('region', 'it_orvieto', '오르비에토', 'Orvieto', '{}', 'it_umbria', '{region}', '{}', '2.0.0', '5660', 'true'),
  ('region', 'it_panzano_uga', '판자노 UGA', 'Panzano UGA', '{}', 'it_chianti_classico', '{region}', '{}', '2.0.0', '5890', 'true'),
  ('region', 'it_piemonte', '피에몬테', 'Piemonte', '{}', 'it', '{region}', '{}', '2.0.0', '5280', 'true'),
  ('region', 'it_prosecco', '프로세코', 'Prosecco', '{}', 'it_veneto', '{region}', '{}', '2.0.0', '5670', 'true'),
  ('region', 'it_puglia', '뿔리아', 'Puglia', '{}', 'it', '{region}', '{}', '2.0.0', '5290', 'true'),
  ('region', 'it_rocche_dell_annunziata', '로케 델 아눈지아타', 'Rocche dell''Annunziata', '{}', 'it_barolo', '{region}', '{}', '2.0.0', '5900', 'true'),
  ('region', 'it_roma', '로마', 'Roma', '{}', 'it_lazio', '{region}', '{}', '2.0.0', '5680', 'true'),
  ('region', 'it_salento', '살렌토', 'Salento', '{}', 'it_puglia', '{region}', '{}', '2.0.0', '5690', 'true'),
  ('region', 'it_sardegna', '사르데냐', 'Sardegna', '{}', 'it', '{region}', '{}', '2.0.0', '5300', 'true'),
  ('region', 'it_sardegna_sardinia', '사르데냐, 사르디니아', 'Sardegna, Sardinia', '{}', 'it', '{region}', '{}', '2.0.0', '5310', 'true'),
  ('region', 'it_sicilia', '시칠리아', 'Sicilia', '{}', 'it', '{region}', '{}', '2.0.0', '5320', 'true'),
  ('region', 'it_siena', '시에나', 'Siena', '{}', 'it_toscana', '{region}', '{}', '2.0.0', '5700', 'true'),
  ('region', 'it_soave', '소아베', 'Soave', '{}', 'it_veneto', '{region}', '{}', '2.0.0', '5710', 'true'),
  ('region', 'it_torgiano', '토르지아노', 'Torgiano', '{}', 'it_umbria', '{region}', '{}', '2.0.0', '5720', 'true'),
  ('region', 'it_toscana', '토스카나', 'Toscana', '{}', 'it', '{region}', '{}', '2.0.0', '5330', 'true'),
  ('region', 'it_trentino_alto_adige', '트렌티노-알토 아디제', 'Trentino-Alto Adige', '{}', 'it', '{region}', '{}', '2.0.0', '5340', 'true'),
  ('region', 'it_trento', '트렌토', 'Trento', '{}', 'it_trentino_alto_adige', '{region}', '{}', '2.0.0', '5730', 'true'),
  ('region', 'it_treviso', '트레비조', 'Treviso', '{트레비소}', 'it_veneto', '{region}', '{}', '2.0.0', '5740', 'true'),
  ('region', 'it_trezzo_tinella', '트레조 티넬라', 'Trezzo Tinella', '{}', 'it_piemonte', '{region}', '{}', '2.0.0', '5750', 'true'),
  ('region', 'it_umbria', '움브리아', 'Umbria', '{}', 'it', '{region}', '{}', '2.0.0', '5350', 'true'),
  ('region', 'it_valdobbiadene', '발도비아데네', 'Valdobbiadene', '{}', 'it_veneto', '{region}', '{}', '2.0.0', '5760', 'true'),
  ('region', 'it_valle_d_aosta', '발레 다오스타', 'Valle d''Aosta', '{}', 'it', '{region}', '{}', '2.0.0', '5360', 'true'),
  ('region', 'it_valpolicella', '발폴리첼라', 'Valpolicella', '{}', 'it_veneto', '{region}', '{}', '2.0.0', '5770', 'true'),
  ('region', 'it_veneto', '베네토', 'Veneto', '{}', 'it', '{region}', '{}', '2.0.0', '5370', 'true'),
  ('region', 'it_vernaccia_di_san_gimignano', '베르나챠 디 산 지미냐노', 'Vernaccia di San Gimignano', '{}', 'it_toscana', '{region}', '{}', '2.0.0', '5780', 'true'),
  ('region', 'it_verona', '베로나', 'Verona', '{}', 'it_veneto', '{region}', '{}', '2.0.0', '5790', 'true'),
  ('region', 'it_vicenza', '비첸차', 'vicenza', '{}', 'it_veneto', '{region}', '{}', '2.0.0', '5800', 'true'),
  ('region', 'jo', '요르단', 'Jordan', '{}', NULL, '{region}', '{}', '2.0.0', '5910', 'true'),
  ('region', 'jp', '일본', 'Japan', '{}', NULL, '{region}', '{}', '2.0.0', '5920', 'true'),
  ('region', 'jp_aichi', '아이치현', 'Aichi', '{}', 'jp', '{region}', '{}', '2.0.0', '5930', 'true'),
  ('region', 'jp_akashi', '아카시시', 'Akashi', '{아키시시}', 'jp_hyogo', '{region}', '{}', '2.0.0', '6400', 'true'),
  ('region', 'jp_akita', '아키타현', 'Akita', '{}', 'jp', '{region}', '{}', '2.0.0', '5940', 'true'),
  ('region', 'jp_aomori', '아오모리현', 'Aomori', '{}', 'jp', '{region}', '{}', '2.0.0', '5950', 'true'),
  ('region', 'jp_chiba', '치바현', 'Chiba', '{지바현}', 'jp', '{region}', '{}', '2.0.0', '5960', 'true'),
  ('region', 'jp_ehime', '에히메현', 'Ehime', '{}', 'jp', '{region}', '{}', '2.0.0', '5970', 'true'),
  ('region', 'jp_fukui', '후쿠이현', 'Fukui', '{}', 'jp', '{region}', '{}', '2.0.0', '5980', 'true'),
  ('region', 'jp_fukuoka', '후쿠오카현', 'Fukuoka', '{}', 'jp', '{region}', '{}', '2.0.0', '5990', 'true'),
  ('region', 'jp_fukushima', '후쿠시마현', 'Fukushima', '{}', 'jp', '{region}', '{}', '2.0.0', '6000', 'true'),
  ('region', 'jp_gifu', '기후현', 'Gifu', '{}', 'jp', '{region}', '{}', '2.0.0', '6010', 'true'),
  ('region', 'jp_gunma', '군마현', 'Gunma', '{}', 'jp', '{region}', '{}', '2.0.0', '6020', 'true'),
  ('region', 'jp_hiroshima', '히로시마현', 'Hiroshima', '{}', 'jp', '{region}', '{}', '2.0.0', '6030', 'true'),
  ('region', 'jp_hokkaido', '홋카이도', 'Hokkaido', '{}', 'jp', '{region}', '{}', '2.0.0', '6040', 'true'),
  ('region', 'jp_hyogo', '효고현', 'Hyogo', '{효고}', 'jp', '{region}', '{}', '2.0.0', '6050', 'true'),
  ('region', 'jp_ibaraki', '이바라키현', 'Ibaraki', '{}', 'jp', '{region}', '{}', '2.0.0', '6060', 'true'),
  ('region', 'jp_ishikawa', '이시카와현', 'Ishikawa', '{}', 'jp', '{region}', '{}', '2.0.0', '6070', 'true'),
  ('region', 'jp_iwate', '이와테현', 'Iwate', '{}', 'jp', '{region}', '{}', '2.0.0', '6080', 'true'),
  ('region', 'jp_kagawa', '가가와현', 'Kagawa', '{}', 'jp', '{region}', '{}', '2.0.0', '6090', 'true'),
  ('region', 'jp_kagoshima', '가고시마현', 'Kagoshima', '{가고시마}', 'jp', '{region}', '{}', '2.0.0', '6100', 'true'),
  ('region', 'jp_kanagawa', '가나가와현', 'Kanagawa', '{}', 'jp', '{region}', '{}', '2.0.0', '6110', 'true'),
  ('region', 'jp_katsunuma', '카츠누마', 'Katsunuma', '{}', 'jp_yamanashi', '{region}', '{}', '2.0.0', '6410', 'true'),
  ('region', 'jp_kochi', '고치현', 'Kochi', '{}', 'jp', '{region}', '{}', '2.0.0', '6120', 'true'),
  ('region', 'jp_kumamoto', '구마모토현', 'Kumamoto', '{}', 'jp', '{region}', '{}', '2.0.0', '6130', 'true'),
  ('region', 'jp_kyoto', '교토부', 'Kyoto', '{}', 'jp', '{region}', '{}', '2.0.0', '6140', 'true'),
  ('region', 'jp_mie', '미에현', 'Mie', '{}', 'jp', '{region}', '{}', '2.0.0', '6150', 'true'),
  ('region', 'jp_miyagi', '미야기현', 'Miyagi', '{}', 'jp', '{region}', '{}', '2.0.0', '6160', 'true'),
  ('region', 'jp_miyazaki', '미야자키현', 'Miyazaki', '{}', 'jp', '{region}', '{}', '2.0.0', '6170', 'true'),
  ('region', 'jp_nagano', '나가노현', 'Nagano', '{}', 'jp', '{region}', '{}', '2.0.0', '6180', 'true'),
  ('region', 'jp_nagasaki', '나가사키현', 'Nagasaki', '{}', 'jp', '{region}', '{}', '2.0.0', '6190', 'true'),
  ('region', 'jp_nara', '나라현', 'Nara', '{}', 'jp', '{region}', '{}', '2.0.0', '6200', 'true'),
  ('region', 'jp_niigata', '니가타현', 'Niigata', '{니가타}', 'jp', '{region}', '{}', '2.0.0', '6210', 'true'),
  ('region', 'jp_nishinomiya', '니시노미야', 'Nishinomiya', '{}', 'jp_hyogo', '{region}', '{}', '2.0.0', '6420', 'true'),
  ('region', 'jp_oita', '오이타현', 'Oita', '{}', 'jp', '{region}', '{}', '2.0.0', '6220', 'true'),
  ('region', 'jp_okayama', '오카야마현', 'Okayama', '{}', 'jp', '{region}', '{}', '2.0.0', '6230', 'true'),
  ('region', 'jp_okinawa', '오키나와현', 'Okinawa', '{}', 'jp', '{region}', '{}', '2.0.0', '6240', 'true'),
  ('region', 'jp_osaka', '오사카부', 'Osaka', '{}', 'jp', '{region}', '{}', '2.0.0', '6250', 'true'),
  ('region', 'jp_saga', '사가현', 'Saga', '{}', 'jp', '{region}', '{}', '2.0.0', '6260', 'true'),
  ('region', 'jp_saitama', '사이타마현', 'Saitama', '{}', 'jp', '{region}', '{}', '2.0.0', '6270', 'true'),
  ('region', 'jp_shiga', '시가현', 'Shiga', '{}', 'jp', '{region}', '{}', '2.0.0', '6280', 'true'),
  ('region', 'jp_shimane', '시마네현', 'Shimane', '{}', 'jp', '{region}', '{}', '2.0.0', '6290', 'true'),
  ('region', 'jp_shizuoka', '시즈오카현', 'Shizuoka', '{}', 'jp', '{region}', '{}', '2.0.0', '6300', 'true'),
  ('region', 'jp_tochigi', '도치기현', 'Tochigi', '{토치기현}', 'jp', '{region}', '{}', '2.0.0', '6310', 'true'),
  ('region', 'jp_tokushima', '도쿠시마현', 'Tokushima', '{}', 'jp', '{region}', '{}', '2.0.0', '6320', 'true'),
  ('region', 'jp_tokyo', '도쿄도', 'Tokyo', '{}', 'jp', '{region}', '{}', '2.0.0', '6330', 'true'),
  ('region', 'jp_tottori', '돗토리현', 'Tottori', '{}', 'jp', '{region}', '{}', '2.0.0', '6340', 'true'),
  ('region', 'jp_toyama', '도야마현', 'Toyama', '{}', 'jp', '{region}', '{}', '2.0.0', '6350', 'true'),
  ('region', 'jp_wakayama', '와카야마현', 'Wakayama', '{}', 'jp', '{region}', '{}', '2.0.0', '6360', 'true'),
  ('region', 'jp_yamagata', '야마가타현', 'Yamagata', '{}', 'jp', '{region}', '{}', '2.0.0', '6370', 'true'),
  ('region', 'jp_yamaguchi', '야마구치현', 'Yamaguchi', '{}', 'jp', '{region}', '{}', '2.0.0', '6380', 'true'),
  ('region', 'jp_yamanashi', '야마나시현', 'Yamanashi', '{}', 'jp', '{region}', '{}', '2.0.0', '6390', 'true'),
  ('region', 'kr', '한국', 'Korea', '{}', NULL, '{region}', '{}', '2.0.0', '6430', 'true'),
  ('region', 'kr_andong', '안동시', 'Andong', '{}', 'kr_gyeongsangbukdo', '{region}', '{}', '2.0.0', '6610', 'true'),
  ('region', 'kr_ansan', '안산시', 'Ansan', '{대부도}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '6620', 'true'),
  ('region', 'kr_anyang', '안양시', 'Anyang', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '6630', 'true'),
  ('region', 'kr_asan', '아산시', 'Asan', '{}', 'kr_chungcheongnamdo', '{region}', '{}', '2.0.0', '6640', 'true'),
  ('region', 'kr_boeun', '보은군', 'Boeun', '{}', 'kr_chungcheongbukdo', '{region}', '{}', '2.0.0', '6650', 'true'),
  ('region', 'kr_boseong', '보성군', 'Boseong', '{}', 'kr_jeollanamdo', '{region}', '{}', '2.0.0', '6660', 'true'),
  ('region', 'kr_buan', '부안군', 'Buan', '{}', 'kr_jeollabukdo', '{region}', '{}', '2.0.0', '6670', 'true'),
  ('region', 'kr_busan', '부산', 'Busan', '{부산광역시}', 'kr', '{region}', '{}', '2.0.0', '6440', 'true'),
  ('region', 'kr_changnyeong', '창녕군', 'Changnyeong', '{}', 'kr_gyeongsangnamdo', '{region}', '{}', '2.0.0', '6680', 'true'),
  ('region', 'kr_changwon', '창원시', 'Changwon', '{}', 'kr_gyeongsangnamdo', '{region}', '{}', '2.0.0', '6690', 'true'),
  ('region', 'kr_cheonan', '천안시', 'Cheonan', '{}', 'kr_chungcheongnamdo', '{region}', '{}', '2.0.0', '6700', 'true'),
  ('region', 'kr_cheongju', '청주시', 'Cheongju', '{}', 'kr_chungcheongbukdo', '{region}', '{}', '2.0.0', '6710', 'true'),
  ('region', 'kr_cheorwon', '철원군', 'Cheorwon', '{}', 'kr_gangwondo', '{region}', '{}', '2.0.0', '6720', 'true'),
  ('region', 'kr_chilgok', '칠곡군', 'Chilgok', '{}', 'kr_gyeongsangbukdo', '{region}', '{}', '2.0.0', '6730', 'true'),
  ('region', 'kr_chungcheongbukdo', '충청북도', 'Chungcheongbukdo', '{충북}', 'kr', '{region}', '{}', '2.0.0', '6450', 'true'),
  ('region', 'kr_chungcheongnamdo', '충청남도', 'Chungcheongnamdo', '{충남}', 'kr', '{region}', '{}', '2.0.0', '6460', 'true'),
  ('region', 'kr_chungju', '충주시', 'Chungju', '{}', 'kr_chungcheongbukdo', '{region}', '{}', '2.0.0', '6740', 'true'),
  ('region', 'kr_daedeok', '대덕구', 'Daedeok', '{}', 'kr_daejeon', '{region}', '{}', '2.0.0', '6750', 'true'),
  ('region', 'kr_daegu', '대구', 'Daegu', '{대구광역시}', 'kr', '{region}', '{}', '2.0.0', '6470', 'true'),
  ('region', 'kr_daejeon', '대전', 'Daejeon', '{대전광역시}', 'kr', '{region}', '{}', '2.0.0', '6480', 'true'),
  ('region', 'kr_dalseong', '달성군', 'Dalseong', '{}', 'kr_daegu', '{region}', '{}', '2.0.0', '6760', 'true'),
  ('region', 'kr_damyang', '담양군', 'Damyang', '{}', 'kr_jeollanamdo', '{region}', '{}', '2.0.0', '6770', 'true'),
  ('region', 'kr_dangjin', '당진시', 'Dangjin', '{}', 'kr_chungcheongnamdo', '{region}', '{}', '2.0.0', '6780', 'true'),
  ('region', 'kr_danyang', '단양군', 'Danyang', '{}', 'kr_chungcheongbukdo', '{region}', '{}', '2.0.0', '6790', 'true'),
  ('region', 'kr_eunpyeong', '은평구', 'Eunpyeong', '{}', 'kr_seoul', '{region}', '{}', '2.0.0', '6800', 'true'),
  ('region', 'kr_ganghwa', '강화군', 'Ganghwa', '{}', 'kr_incheon', '{region}', '{}', '2.0.0', '6810', 'true'),
  ('region', 'kr_gangjin', '강진군', 'Gangjin', '{}', 'kr_jeollanamdo', '{region}', '{}', '2.0.0', '6820', 'true'),
  ('region', 'kr_gangwondo', '강원도', 'Gangwondo', '{강원}', 'kr', '{region}', '{}', '2.0.0', '6490', 'true'),
  ('region', 'kr_gapyeong', '가평군', 'Gapyeong', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '6830', 'true'),
  ('region', 'kr_geumjeong', '금정구', 'Geumjeong', '{}', 'kr_busan', '{region}', '{}', '2.0.0', '6840', 'true'),
  ('region', 'kr_geumsan', '금산군', 'Geumsan', '{}', 'kr_chungcheongnamdo', '{region}', '{}', '2.0.0', '6850', 'true'),
  ('region', 'kr_gimcheon', '김천시', 'Gimcheon', '{김천}', 'kr_gyeongsangbukdo', '{region}', '{}', '2.0.0', '6860', 'true'),
  ('region', 'kr_gimhae', '김해시', 'Gimhae', '{}', 'kr_gyeongsangnamdo', '{region}', '{}', '2.0.0', '6870', 'true'),
  ('region', 'kr_gimpo', '김포시', 'Gimpo', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '6880', 'true'),
  ('region', 'kr_gochang', '고창군', 'Gochang', '{}', 'kr_jeollabukdo', '{region}', '{}', '2.0.0', '6890', 'true'),
  ('region', 'kr_goesan', '괴산군', 'Goesan', '{}', 'kr_chungcheongbukdo', '{region}', '{}', '2.0.0', '6900', 'true'),
  ('region', 'kr_goheung', '고흥군', 'Goheung', '{}', 'kr_jeollanamdo', '{region}', '{}', '2.0.0', '6910', 'true'),
  ('region', 'kr_gongju', '공주시', 'Gongju', '{}', 'kr_chungcheongnamdo', '{region}', '{}', '2.0.0', '6920', 'true'),
  ('region', 'kr_guri', '구리시', 'Guri', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '6930', 'true'),
  ('region', 'kr_gwacheon', '과천시', 'Gwacheon', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '6940', 'true'),
  ('region', 'kr_gwangju', '광주', 'Gwangju', '{광주광역시}', 'kr', '{region}', '{}', '2.0.0', '6500', 'true'),
  ('region', 'kr_gwangju_si', '광주시', 'Gwangju', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '6950', 'true'),
  ('region', 'kr_gwangyang', '광양시', 'Gwangyang', '{}', 'kr_jeollanamdo', '{region}', '{}', '2.0.0', '6960', 'true'),
  ('region', 'kr_gyeonggido', '경기도', 'Gyeonggido', '{경기}', 'kr', '{region}', '{}', '2.0.0', '6510', 'true'),
  ('region', 'kr_gyeongju', '경주시', 'Gyeongju', '{}', 'kr_gyeongsangbukdo', '{region}', '{}', '2.0.0', '6970', 'true'),
  ('region', 'kr_gyeongsangbukdo', '경상북도', 'Gyeongsangbukdo', '{경북}', 'kr', '{region}', '{}', '2.0.0', '6520', 'true'),
  ('region', 'kr_gyeongsangnamdo', '경상남도', 'Gyeongsangnamdo', '{경남}', 'kr', '{region}', '{}', '2.0.0', '6530', 'true'),
  ('region', 'kr_hadong', '하동군', 'Hadong', '{하동}', 'kr_gyeongsangnamdo', '{region}', '{}', '2.0.0', '6980', 'true'),
  ('region', 'kr_haenam', '해남군', 'Haenam', '{}', 'kr_jeollanamdo', '{region}', '{}', '2.0.0', '6990', 'true'),
  ('region', 'kr_hamyang', '함양군', 'Hamyang', '{}', 'kr_gyeongsangnamdo', '{region}', '{}', '2.0.0', '7000', 'true'),
  ('region', 'kr_hongcheon', '홍천군', 'Hongcheon', '{}', 'kr_gangwondo', '{region}', '{}', '2.0.0', '7010', 'true'),
  ('region', 'kr_hongseong', '홍성군', 'Hongseong', '{}', 'kr_chungcheongnamdo', '{region}', '{}', '2.0.0', '7020', 'true'),
  ('region', 'kr_hwaseong', '화성시', 'Hwaseong', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '7030', 'true'),
  ('region', 'kr_icheon', '이천시', 'Icheon', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '7040', 'true'),
  ('region', 'kr_iksan', '익산시', 'Iksan', '{}', 'kr_jeollabukdo', '{region}', '{}', '2.0.0', '7050', 'true'),
  ('region', 'kr_incheon', '인천', 'Incheon', '{인천광역시}', 'kr', '{region}', '{}', '2.0.0', '6540', 'true'),
  ('region', 'kr_inje', '인제군', 'Inje', '{}', 'kr_gangwondo', '{region}', '{}', '2.0.0', '7060', 'true'),
  ('region', 'kr_jangsu', '장수군', 'Jangsu', '{}', 'kr_jeollabukdo', '{region}', '{}', '2.0.0', '7070', 'true'),
  ('region', 'kr_jecheon', '제천시', 'Jecheon', '{}', 'kr_chungcheongbukdo', '{region}', '{}', '2.0.0', '7080', 'true'),
  ('region', 'kr_jeju', '제주시', 'Jeju', '{}', 'kr_jejudo', '{region}', '{}', '2.0.0', '7090', 'true'),
  ('region', 'kr_jejudo', '제주도', 'Jejudo', '{제주}', 'kr', '{region}', '{}', '2.0.0', '6550', 'true'),
  ('region', 'kr_jeollabukdo', '전라북도', 'Jeollabukdo', '{전북}', 'kr', '{region}', '{}', '2.0.0', '6560', 'true'),
  ('region', 'kr_jeollanamdo', '전라남도', 'Jeollanamdo', '{전남}', 'kr', '{region}', '{}', '2.0.0', '6570', 'true'),
  ('region', 'kr_jeongeup', '정읍시', 'Jeongeup', '{}', 'kr_jeollabukdo', '{region}', '{}', '2.0.0', '7100', 'true'),
  ('region', 'kr_jeonju', '전주시', 'Jeonju', '{}', 'kr_jeollabukdo', '{region}', '{}', '2.0.0', '7110', 'true'),
  ('region', 'kr_jindo', '진도군', 'Jindo', '{}', 'kr_jeollanamdo', '{region}', '{}', '2.0.0', '7120', 'true'),
  ('region', 'kr_mapo', '마포구', 'Mapo', '{}', 'kr_seoul', '{region}', '{}', '2.0.0', '7130', 'true'),
  ('region', 'kr_miryang', '밀양시', 'Miryang', '{}', 'kr_gyeongsangnamdo', '{region}', '{}', '2.0.0', '7140', 'true'),
  ('region', 'kr_muju', '무주군', 'Muju', '{무주}', 'kr_jeollabukdo', '{region}', '{}', '2.0.0', '7150', 'true'),
  ('region', 'kr_mungyeong', '문경시', 'Mungyeong', '{문경}', 'kr_gyeongsangbukdo', '{region}', '{}', '2.0.0', '7160', 'true'),
  ('region', 'kr_naju', '나주시', 'Naju', '{}', 'kr_jeollanamdo', '{region}', '{}', '2.0.0', '7170', 'true'),
  ('region', 'kr_namhae', '남해군', 'Namhae', '{}', 'kr_gyeongsangnamdo', '{region}', '{}', '2.0.0', '7180', 'true'),
  ('region', 'kr_namyangju', '남양주시', 'Namyangju', '{남양주}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '7190', 'true'),
  ('region', 'kr_nonsan', '논산시', 'Nonsan', '{}', 'kr_chungcheongnamdo', '{region}', '{}', '2.0.0', '7200', 'true'),
  ('region', 'kr_osan', '오산시', 'Osan', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '7210', 'true'),
  ('region', 'kr_paju', '파주시', 'Paju', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '7220', 'true'),
  ('region', 'kr_pocheon', '포천시', 'Pocheon', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '7230', 'true'),
  ('region', 'kr_pohang', '포항시', 'Pohang', '{}', 'kr_gyeongsangbukdo', '{region}', '{}', '2.0.0', '7240', 'true'),
  ('region', 'kr_pyeongtaek', '평택시', 'Pyeongtaek', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '7250', 'true'),
  ('region', 'kr_sancheong', '산청군', 'Sancheong', '{}', 'kr_gyeongsangnamdo', '{region}', '{}', '2.0.0', '7260', 'true'),
  ('region', 'kr_sangju', '상주시', 'Sangju', '{}', 'kr_gyeongsangbukdo', '{region}', '{}', '2.0.0', '7270', 'true'),
  ('region', 'kr_sejong', '세종', 'Sejong', '{세종특별자치시}', 'kr', '{region}', '{}', '2.0.0', '6580', 'true'),
  ('region', 'kr_seocheon', '서천군', 'Seocheon', '{}', 'kr_chungcheongnamdo', '{region}', '{}', '2.0.0', '7280', 'true'),
  ('region', 'kr_seocho', '서초구', 'Seocho', '{}', 'kr_seoul', '{region}', '{}', '2.0.0', '7290', 'true'),
  ('region', 'kr_seogwipo', '서귀포시', 'Seogwipo', '{}', 'kr_jejudo', '{region}', '{}', '2.0.0', '7300', 'true'),
  ('region', 'kr_seongdong', '성동구', 'Seongdong', '{}', 'kr_seoul', '{region}', '{}', '2.0.0', '7310', 'true'),
  ('region', 'kr_seosan', '서산시', 'Seosan', '{}', 'kr_chungcheongnamdo', '{region}', '{}', '2.0.0', '7320', 'true'),
  ('region', 'kr_seoul', '서울', 'Seoul', '{서울특별시}', 'kr', '{region}', '{}', '2.0.0', '6590', 'true'),
  ('region', 'kr_siheung', '시흥시', 'Siheung', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '7330', 'true'),
  ('region', 'kr_sunchang', '순창군', 'Sunchang', '{}', 'kr_jeollabukdo', '{region}', '{}', '2.0.0', '7340', 'true'),
  ('region', 'kr_uijeongbu', '의정부시', 'Uijeongbu', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '7350', 'true'),
  ('region', 'kr_uljin', '울진군', 'Uljin', '{}', 'kr_gyeongsangbukdo', '{region}', '{}', '2.0.0', '7360', 'true'),
  ('region', 'kr_ulju', '울주군', 'Ulju', '{}', 'kr_ulsan', '{region}', '{}', '2.0.0', '7370', 'true'),
  ('region', 'kr_ulsan', '울산', 'Ulsan', '{울산광역시}', 'kr', '{region}', '{}', '2.0.0', '6600', 'true'),
  ('region', 'kr_wando', '완도군', 'Wando', '{}', 'kr_jeollanamdo', '{region}', '{}', '2.0.0', '7380', 'true'),
  ('region', 'kr_wanju', '완주군', 'Wanju', '{}', 'kr_jeollabukdo', '{region}', '{}', '2.0.0', '7390', 'true'),
  ('region', 'kr_wonju', '원주시', 'Wonju', '{}', 'kr_gangwondo', '{region}', '{}', '2.0.0', '7400', 'true'),
  ('region', 'kr_yanggu', '양구군', 'Yanggu', '{}', 'kr_gangwondo', '{region}', '{}', '2.0.0', '7410', 'true'),
  ('region', 'kr_yangpyeong', '양평군', 'Yangpyeong', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '7420', 'true'),
  ('region', 'kr_yangsan', '양산시', 'Yangsan', '{}', 'kr_gyeongsangnamdo', '{region}', '{}', '2.0.0', '7430', 'true'),
  ('region', 'kr_yecheon', '예천군', 'Yecheon', '{}', 'kr_gyeongsangbukdo', '{region}', '{}', '2.0.0', '7440', 'true'),
  ('region', 'kr_yeoju', '여주시', 'Yeoju', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '7450', 'true'),
  ('region', 'kr_yeongcheon', '영천시', 'Yeongcheon', '{영천}', 'kr_gyeongsangbukdo', '{region}', '{}', '2.0.0', '7460', 'true'),
  ('region', 'kr_yeongdeok', '영덕군', 'Yeongdeok', '{}', 'kr_gyeongsangbukdo', '{region}', '{}', '2.0.0', '7470', 'true'),
  ('region', 'kr_yeongdo', '영도구', 'Yeongdo', '{}', 'kr_busan', '{region}', '{}', '2.0.0', '7480', 'true'),
  ('region', 'kr_yeongdong', '영동군', 'Yeongdong', '{영동}', 'kr_chungcheongbukdo', '{region}', '{}', '2.0.0', '7490', 'true'),
  ('region', 'kr_yeongju', '영주시', 'Yeongju', '{영주}', 'kr_gyeongsangbukdo', '{region}', '{}', '2.0.0', '7500', 'true'),
  ('region', 'kr_yeongwol', '영월군', 'Yeongwol', '{}', 'kr_gangwondo', '{region}', '{}', '2.0.0', '7510', 'true'),
  ('region', 'kr_yeonsu', '연수구', 'Yeonsu', '{}', 'kr_incheon', '{region}', '{}', '2.0.0', '7520', 'true'),
  ('region', 'kr_yeosu', '여수시', 'Yeosu', '{}', 'kr_jeollanamdo', '{region}', '{}', '2.0.0', '7530', 'true'),
  ('region', 'kr_yesan', '예산군', 'Yesan', '{}', 'kr_chungcheongnamdo', '{region}', '{}', '2.0.0', '7540', 'true'),
  ('region', 'kr_yongin', '용인시', 'Yongin', '{}', 'kr_gyeonggido', '{region}', '{}', '2.0.0', '7550', 'true'),
  ('region', 'lb', '레바논', 'Lebanon', '{}', NULL, '{region}', '{}', '2.0.0', '7560', 'true'),
  ('region', 'lb_bekaa_valley', '베카 밸리', 'Bekaa Valley', '{}', 'lb', '{region}', '{}', '2.0.0', '7570', 'true'),
  ('region', 'ma', '모로코', 'Morocco', '{}', NULL, '{region}', '{}', '2.0.0', '7580', 'true'),
  ('region', 'md', '몰도바', 'Moldova', '{}', NULL, '{region}', '{}', '2.0.0', '7590', 'true'),
  ('region', 'md_codru', '코드루', 'Codru', '{}', 'md', '{region}', '{}', '2.0.0', '7600', 'true'),
  ('region', 'mm', '미얀마', 'Myanmar', '{}', NULL, '{region}', '{}', '2.0.0', '7610', 'true'),
  ('region', 'mx', '멕시코', 'Mexico', '{}', NULL, '{region}', '{}', '2.0.0', '7620', 'true'),
  ('region', 'nl', '네덜란드', 'Netherlands', '{}', NULL, '{region}', '{}', '2.0.0', '7630', 'true'),
  ('region', 'np', '네팔', 'Nepal', '{}', NULL, '{region}', '{}', '2.0.0', '7640', 'true'),
  ('region', 'nz', '뉴질랜드', 'New Zealand', '{}', NULL, '{region}', '{}', '2.0.0', '7650', 'true'),
  ('region', 'nz_auckland', '오클랜드', 'Auckland', '{}', 'nz_north_island', '{region}', '{}', '2.0.0', '7680', 'true'),
  ('region', 'nz_bannockburn', '배녹번', 'Bannockburn', '{}', 'nz_central_otago', '{region}', '{}', '2.0.0', '7780', 'true'),
  ('region', 'nz_canterbury', '캔터버리', 'Canterbury', '{}', 'nz_south_island', '{region}', '{}', '2.0.0', '7690', 'true'),
  ('region', 'nz_central_otago', '센트럴 오타고', 'Central Otago', '{}', 'nz_south_island', '{region}', '{}', '2.0.0', '7700', 'true'),
  ('region', 'nz_gibbston_valley', '깁스톤 밸리', 'Gibbston Valley', '{}', 'nz_central_otago', '{region}', '{}', '2.0.0', '7790', 'true'),
  ('region', 'nz_gisborne', '기스본', 'Gisborne', '{}', 'nz_north_island', '{region}', '{}', '2.0.0', '7710', 'true'),
  ('region', 'nz_hawke_s_bay', '혹스 베이', 'Hawke''s Bay', '{"호크스 베이"}', 'nz_north_island', '{region}', '{}', '2.0.0', '7720', 'true'),
  ('region', 'nz_marlborough', '말보로', 'Marlborough', '{}', 'nz_south_island', '{region}', '{}', '2.0.0', '7730', 'true'),
  ('region', 'nz_martinborough', '마틴보로', 'Martinborough', '{}', 'nz_wairarapa', '{region}', '{}', '2.0.0', '7800', 'true'),
  ('region', 'nz_nelson', '넬슨', 'Nelson', '{}', 'nz_south_island', '{region}', '{}', '2.0.0', '7740', 'true'),
  ('region', 'nz_north_island', '노스 아일랜드', 'North Island', '{}', 'nz', '{region}', '{}', '2.0.0', '7660', 'true'),
  ('region', 'nz_ohau', '오하우', 'Ohau', '{}', 'nz_north_island', '{region}', '{}', '2.0.0', '7750', 'true'),
  ('region', 'nz_south_island', '사우스 아일랜드', 'South Island', '{}', 'nz', '{region}', '{}', '2.0.0', '7670', 'true'),
  ('region', 'nz_waipara_valley', '와이파라 밸리', 'Waipara Valley', '{}', 'nz_south_island', '{region}', '{}', '2.0.0', '7760', 'true'),
  ('region', 'nz_wairarapa', '와이라라파', 'Wairarapa', '{}', 'nz_north_island', '{region}', '{}', '2.0.0', '7770', 'true'),
  ('region', 'ph', '필리핀', 'Philippines', '{}', NULL, '{region}', '{}', '2.0.0', '7810', 'true'),
  ('region', 'pt', '포르투갈', 'Portugal', '{}', NULL, '{region}', '{}', '2.0.0', '7820', 'true'),
  ('region', 'pt_acores', '아조레스', 'Acores', '{}', 'pt', '{region}', '{}', '2.0.0', '7830', 'true'),
  ('region', 'pt_alentejo', '알렌테주', 'Alentejo', '{}', 'pt', '{region}', '{}', '2.0.0', '7840', 'true'),
  ('region', 'pt_bairrada', '바이라다', 'Bairrada', '{}', 'pt', '{region}', '{}', '2.0.0', '7850', 'true'),
  ('region', 'pt_beira', '베이라', 'Beira', '{}', 'pt', '{region}', '{}', '2.0.0', '7860', 'true'),
  ('region', 'pt_beira_interior', '베이라 인테리어', 'Beira Interior', '{}', 'pt', '{region}', '{}', '2.0.0', '7870', 'true'),
  ('region', 'pt_dao_e_lafoes', '다웅 에 라포에스', 'Dao E Lafoes', '{}', 'pt', '{region}', '{}', '2.0.0', '7880', 'true'),
  ('region', 'pt_douro', '도우로 밸리', 'Douro', '{도우로,"두오로 밸리"}', 'pt_porto', '{region}', '{}', '2.0.0', '7970', 'true'),
  ('region', 'pt_lisboa', '리스보아', 'Lisboa', '{}', 'pt', '{region}', '{}', '2.0.0', '7890', 'true'),
  ('region', 'pt_madeira', '마데이라', 'Madeira', '{}', 'pt', '{region}', '{}', '2.0.0', '7900', 'true'),
  ('region', 'pt_minho', '미뉴', 'Minho', '{}', 'pt', '{region}', '{}', '2.0.0', '7910', 'true'),
  ('region', 'pt_palmela', '팔메라', 'Palmela', '{}', 'pt_peninsula_de_setubal', '{region}', '{}', '2.0.0', '7980', 'true'),
  ('region', 'pt_peninsula_de_setubal', '페닌슐라 데 세투발', 'Peninsula de Setubal', '{}', 'pt', '{region}', '{}', '2.0.0', '7920', 'true'),
  ('region', 'pt_porto', '포르토', 'Porto', '{포르투}', 'pt', '{region}', '{}', '2.0.0', '7930', 'true'),
  ('region', 'pt_porto_e_douro', '포르투 에 도우루', 'Porto E Douro', '{}', 'pt', '{region}', '{}', '2.0.0', '7940', 'true'),
  ('region', 'pt_setubal', '세투발', 'Setubal', '{}', 'pt_peninsula_de_setubal', '{region}', '{}', '2.0.0', '7990', 'true'),
  ('region', 'pt_tejo', '테주', 'Tejo', '{}', 'pt', '{region}', '{}', '2.0.0', '7950', 'true'),
  ('region', 'pt_vinho_verde', '비뉴 베르데', 'Vinho Verde', '{}', 'pt', '{region}', '{}', '2.0.0', '7960', 'true'),
  ('region', 'ro', '루마니아', 'Romania', '{}', NULL, '{region}', '{}', '2.0.0', '8000', 'true'),
  ('region', 'ro_dobrogea', '도브루자', 'Dobrogea', '{}', 'ro', '{region}', '{}', '2.0.0', '8010', 'true'),
  ('region', 'ro_oltenia_muntenia', '올테니아-문테니아', 'Oltenia-Muntenia', '{}', 'ro', '{region}', '{}', '2.0.0', '8020', 'true'),
  ('region', 'ro_oprisor', '오프리소르', 'Oprisor', '{}', 'ro_oltenia_muntenia', '{region}', '{}', '2.0.0', '8030', 'true'),
  ('region', 'rs', '세르비아', 'Serbia', '{}', NULL, '{region}', '{}', '2.0.0', '8040', 'true'),
  ('region', 'se', '스웨덴', 'Sweden', '{}', NULL, '{region}', '{}', '2.0.0', '8050', 'true'),
  ('region', 'si', '슬로베니아', 'Slovenia', '{}', NULL, '{region}', '{}', '2.0.0', '8060', 'true'),
  ('region', 'si_goriska_brda', '고리스카 브르다', 'Goriska Brda', '{}', 'si', '{region}', '{}', '2.0.0', '8070', 'true'),
  ('region', 'si_kras', 'Kras', 'Kras', '{}', 'si', '{region}', '{}', '2.0.0', '8080', 'true'),
  ('region', 'si_podravje', '포드라베', 'Podravje', '{}', 'si', '{region}', '{}', '2.0.0', '8090', 'true'),
  ('region', 'si_prekmurje', 'Prekmurje', 'Prekmurje', '{}', 'si', '{region}', '{}', '2.0.0', '8100', 'true'),
  ('region', 'si_primorska', '프리모리에', 'Primorska', '{}', 'si', '{region}', '{}', '2.0.0', '8110', 'true'),
  ('region', 'si_slovenska_istra', 'Slovenska Istra', 'Slovenska Istra', '{}', 'si', '{region}', '{}', '2.0.0', '8120', 'true'),
  ('region', 'si_stajerska_slovenija', 'Stajerska Slovenija', 'Stajerska Slovenija', '{}', 'si', '{region}', '{}', '2.0.0', '8130', 'true'),
  ('region', 'si_vipava', '비파바', 'Vipava', '{}', 'si', '{region}', '{}', '2.0.0', '8140', 'true'),
  ('region', 'sk', '슬로바키아', 'Slovakia', '{}', NULL, '{region}', '{}', '2.0.0', '8150', 'true'),
  ('region', 'th', '태국', 'Thailand', '{}', NULL, '{region}', '{}', '2.0.0', '8160', 'true'),
  ('region', 'tr', '튀르키예', 'Türkiye', '{}', NULL, '{region}', '{}', '2.0.0', '8170', 'true'),
  ('region', 'tw', '대만', 'Taiwan', '{}', NULL, '{region}', '{}', '2.0.0', '8180', 'true'),
  ('region', 'ua', '우크라이나', 'Ukraine', '{}', NULL, '{region}', '{}', '2.0.0', '8190', 'true'),
  ('region', 'ua_odesa', '오데사', 'Odesa', '{}', 'ua', '{region}', '{}', '2.0.0', '8200', 'true'),
  ('region', 'us', '미국', 'United States', '{}', NULL, '{region}', '{}', '2.0.0', '8210', 'true'),
  ('region', 'us_alameda_county', '앨러미다 카운티', 'Alameda County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8310', 'true'),
  ('region', 'us_alexander_valley', '알렉산더 밸리', 'Alexander Valley', '{}', 'us_sonoma_county', '{region}', '{}', '2.0.0', '8620', 'true'),
  ('region', 'us_amador_county', '아마도르 카운티', 'Amador County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8320', 'true'),
  ('region', 'us_ancient_lakes', '에인션트 레이크스', 'Ancient Lakes', '{}', 'us_columbia_valley', '{region}', '{}', '2.0.0', '8630', 'true'),
  ('region', 'us_anderson_valley', '앤더슨 밸리', 'Anderson Valley', '{}', 'us_mendocino_county', '{region}', '{}', '2.0.0', '8640', 'true'),
  ('region', 'us_applegate_valley', '애플게이트 밸리', 'Applegate Valley', '{}', 'us_southern_oregon', '{region}', '{}', '2.0.0', '8650', 'true'),
  ('region', 'us_arroyo_grande_valley', '아로요 그란데 밸리', 'Arroyo Grande Valley', '{}', 'us_san_luis_obispo_county', '{region}', '{}', '2.0.0', '8660', 'true'),
  ('region', 'us_arroyo_seco', '아로요 세코', 'Arroyo Seco', '{}', 'us_monterey_county', '{region}', '{}', '2.0.0', '8670', 'true'),
  ('region', 'us_atlas_peak_ava', '알타스 피크 AVA', 'Atlas Peak AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '8680', 'true'),
  ('region', 'us_borden_ranch', '보든 랜치', 'Borden Ranch', '{}', 'us_sacramento_county', '{region}', '{}', '2.0.0', '8690', 'true'),
  ('region', 'us_california', '캘리포니아', 'California', '{}', 'us', '{region}', '{}', '2.0.0', '8220', 'true'),
  ('region', 'us_calistoga_ava', '캘리스토가 AVA', 'Calistoga AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '8700', 'true'),
  ('region', 'us_central_coast', '센트럴 코스트', 'Central Coast', '{}', 'us_california', '{region}', '{}', '2.0.0', '8330', 'true'),
  ('region', 'us_chalk_hill', '초크 힐', 'Chalk Hill', '{}', 'us_sonoma_county', '{region}', '{}', '2.0.0', '8710', 'true'),
  ('region', 'us_chehalem_mountain', '체할렘 마운틴', 'Chehalem Mountain', '{}', 'us_willamette_valley', '{region}', '{}', '2.0.0', '8720', 'true'),
  ('region', 'us_cienega_valley', '시에네가 밸리', 'Cienega Valley', '{}', 'us_san_benito_county', '{region}', '{}', '2.0.0', '8730', 'true'),
  ('region', 'us_clarksburg', '클라크스버그', 'Clarksburg', '{}', 'us_sacramento_county', '{region}', '{}', '2.0.0', '8740', 'true'),
  ('region', 'us_cole_ranch', '콜 랜치', 'Cole Ranch', '{}', 'us_mendocino_county', '{region}', '{}', '2.0.0', '8750', 'true'),
  ('region', 'us_columbia_gorge', '콜롬비아 고지', 'Columbia Gorge', '{}', 'us_oregon', '{region}', '{}', '2.0.0', '8340', 'true'),
  ('region', 'us_columbia_valley', '콜롬비아 밸리', 'Columbia Valley', '{}', 'us_washington_state', '{region}', '{}', '2.0.0', '8350', 'true'),
  ('region', 'us_diamond_mountain_district_ava', '다이아몬드 마운틴 디스트릭트 AVA', 'Diamond Mountain District AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '8760', 'true'),
  ('region', 'us_dry_creek_valley', '드라이 크릭 밸리', 'Dry Creek Valley', '{}', 'us_sonoma_county', '{region}', '{}', '2.0.0', '8770', 'true'),
  ('region', 'us_dundee_hills', '던디 힐', 'Dundee Hills', '{}', 'us_willamette_valley', '{region}', '{}', '2.0.0', '8780', 'true'),
  ('region', 'us_eastern_oregon', '이스턴 오리건', 'Eastern Oregon', '{}', 'us_oregon', '{region}', '{}', '2.0.0', '8360', 'true'),
  ('region', 'us_edna_valley', '에드나 밸리', 'Edna Valley', '{}', 'us_san_luis_obispo_county', '{region}', '{}', '2.0.0', '8790', 'true'),
  ('region', 'us_el_dorado', '엘 도라도', 'El Dorado', '{}', 'us_el_dorado_county', '{region}', '{}', '2.0.0', '8800', 'true'),
  ('region', 'us_el_dorado_county', '엘 도라도 카운티', 'El Dorado County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8370', 'true'),
  ('region', 'us_eola_amity_hills', '이올라-아미티 힐즈', 'Eola-Amity Hills', '{}', 'us_willamette_valley', '{region}', '{}', '2.0.0', '8810', 'true'),
  ('region', 'us_goose_gap', '구스 갭', 'Goose Gap', '{}', 'us_columbia_valley', '{region}', '{}', '2.0.0', '8820', 'true'),
  ('region', 'us_green_valley', '그린 밸리', 'Green Valley', '{}', 'us_solano_county', '{region}', '{}', '2.0.0', '8830', 'true'),
  ('region', 'us_hames_valley', '헤임즈 벨리', 'Hames Valley', '{}', 'us_monterey_county', '{region}', '{}', '2.0.0', '8840', 'true'),
  ('region', 'us_happy_canyon_of_santa_barbara', '해피 캐년 오브 산타 바바라', 'Happy Canyon of Santa Barbara', '{}', 'us_santa_barbara_county', '{region}', '{}', '2.0.0', '8850', 'true'),
  ('region', 'us_high_valley', '하이 밸리', 'High Valley', '{}', 'us_lake_county', '{region}', '{}', '2.0.0', '8860', 'true'),
  ('region', 'us_horse_heaven_hills', '홀스 헤븐 힐스', 'Horse Heaven Hills', '{}', 'us_columbia_valley', '{region}', '{}', '2.0.0', '8870', 'true'),
  ('region', 'us_howell_mountain_ava', '하월 마운틴 AVA', 'Howell Mountain AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '8880', 'true'),
  ('region', 'us_kentucky', '켄터키', 'Kentucky', '{}', 'us', '{region}', '{}', '2.0.0', '8230', 'true'),
  ('region', 'us_knights_valley', '나이츠 밸리', 'Knights Valley', '{}', 'us_sonoma_county', '{region}', '{}', '2.0.0', '8890', 'true'),
  ('region', 'us_lake_county', '레이크 카운티', 'Lake County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8380', 'true'),
  ('region', 'us_livermore_valley', '리버모어 밸리', 'Livermore Valley', '{}', 'us_alameda_county', '{region}', '{}', '2.0.0', '8900', 'true'),
  ('region', 'us_lodi', '로다이', 'Lodi', '{로디}', 'us_san_joaquin_county', '{region}', '{}', '2.0.0', '8910', 'true'),
  ('region', 'us_los_angeles_county', '로스 엔젤레스 카운티', 'Los Angeles County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8390', 'true'),
  ('region', 'us_los_carneros', '로스 카네로스', 'Los Carneros', '{}', 'us_sonoma_county', '{region}', '{}', '2.0.0', '8920', 'true'),
  ('region', 'us_los_carneros_ava', '로스 카네로스 AVA', 'Los Carneros AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '8930', 'true'),
  ('region', 'us_madera', '마데라', 'Madera', '{}', 'us_madera_county', '{region}', '{}', '2.0.0', '8940', 'true'),
  ('region', 'us_madera_county', '마데라 카운티', 'Madera County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8400', 'true'),
  ('region', 'us_mcminnville', '맥민빌', 'McMinnville', '{}', 'us_willamette_valley', '{region}', '{}', '2.0.0', '8950', 'true'),
  ('region', 'us_mendocino', '멘도치노', 'Mendocino', '{}', 'us_mendocino_county', '{region}', '{}', '2.0.0', '8960', 'true'),
  ('region', 'us_mendocino_county', '멘도치노 카운티', 'Mendocino County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8410', 'true'),
  ('region', 'us_minnesota', '미네소타', 'Minnesota', '{}', 'us', '{region}', '{}', '2.0.0', '8240', 'true'),
  ('region', 'us_mokelumne_river', '마켈럼니 리버', 'Mokelumne River', '{}', 'us_san_joaquin_county', '{region}', '{}', '2.0.0', '8970', 'true'),
  ('region', 'us_monterey', '몬터레이', 'Monterey', '{몬테레이}', 'us_monterey_county', '{region}', '{}', '2.0.0', '8980', 'true'),
  ('region', 'us_monterey_county', '몬터레이 카운티', 'Monterey County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8420', 'true'),
  ('region', 'us_mt_veeder_ava', '마운틴 비더 AVA', 'Mt. Veeder AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '8990', 'true'),
  ('region', 'us_napa_county', '나파 카운티', 'Napa County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8430', 'true'),
  ('region', 'us_napa_valley_ava', '나파 밸리 AVA', 'Napa Valley AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '9000', 'true'),
  ('region', 'us_new_york_state', '뉴욕 스테이트', 'New York State', '{}', 'us', '{region}', '{}', '2.0.0', '8250', 'true'),
  ('region', 'us_north_coast', '노스 코스트', 'North Coast', '{}', 'us_california', '{region}', '{}', '2.0.0', '8440', 'true'),
  ('region', 'us_oak_knoll_district_of_napa_valley_ava', '오크 놀 디스트릭트 오브 나파 밸리 AVA', 'Oak Knoll District of Napa Valley AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '9010', 'true'),
  ('region', 'us_oakville_ava', '오크빌 AVA', 'Oakville AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '9020', 'true'),
  ('region', 'us_oregon', '오리건', 'Oregon', '{}', 'us', '{region}', '{}', '2.0.0', '8260', 'true'),
  ('region', 'us_paso_robles', '파소 로블스', 'Paso Robles', '{}', 'us_san_luis_obispo_county', '{region}', '{}', '2.0.0', '9030', 'true'),
  ('region', 'us_potter_valley', '포터 밸리', 'Potter Valley', '{}', 'us_mendocino_county', '{region}', '{}', '2.0.0', '9040', 'true'),
  ('region', 'us_rattlesnake_hills', '래틀스네이크 힐스', 'Rattlesnake Hills', '{}', 'us_washington_state', '{region}', '{}', '2.0.0', '8450', 'true'),
  ('region', 'us_red_hills_lake_county', '레드 힐 레이크 카운티', 'Red Hills Lake County', '{}', 'us_lake_county', '{region}', '{}', '2.0.0', '9050', 'true'),
  ('region', 'us_red_mountain', '레드 마운틴', 'Red Mountain', '{}', 'us_washington_state', '{region}', '{}', '2.0.0', '8460', 'true'),
  ('region', 'us_redwood_valley', '레드우드 밸리', 'Redwood Valley', '{}', 'us_mendocino_county', '{region}', '{}', '2.0.0', '9060', 'true'),
  ('region', 'us_ribbon_ridge', '리본 릿지', 'Ribbon Ridge', '{}', 'us_willamette_valley', '{region}', '{}', '2.0.0', '9070', 'true'),
  ('region', 'us_riverside_county', '리버사이드 카운티', 'Riverside County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8470', 'true'),
  ('region', 'us_rogue_valley', '로그 밸리', 'Rogue Valley', '{}', 'us_southern_oregon', '{region}', '{}', '2.0.0', '9080', 'true'),
  ('region', 'us_royal_slope', '로얄 슬로프', 'Royal Slope', '{}', 'us_columbia_valley', '{region}', '{}', '2.0.0', '9090', 'true'),
  ('region', 'us_russian_river_valley', '러시안 리버 밸리', 'Russian River Valley', '{}', 'us_sonoma_county', '{region}', '{}', '2.0.0', '9100', 'true'),
  ('region', 'us_rutherford_ava', '러더포드 AVA', 'Rutherford AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '9110', 'true'),
  ('region', 'us_sacramento_county', '새크라멘토 카운티', 'Sacramento County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8480', 'true'),
  ('region', 'us_saddle_rock_malibu', '새들 락-말리부', 'Saddle Rock-Malibu', '{}', 'us_los_angeles_county', '{region}', '{}', '2.0.0', '9120', 'true'),
  ('region', 'us_san_benito_county', '샌 베니토 카운티', 'San Benito County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8490', 'true'),
  ('region', 'us_san_francisco_bay', '샌프란시스코 베이', 'San Francisco Bay', '{}', 'us_alameda_county', '{region}', '{}', '2.0.0', '9130', 'true'),
  ('region', 'us_san_joaquin_county', '샌 호아퀸 카운티', 'San Joaquin County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8500', 'true'),
  ('region', 'us_san_lucas', '샌 루카스', 'San Lucas', '{}', 'us_monterey_county', '{region}', '{}', '2.0.0', '9140', 'true'),
  ('region', 'us_san_luis_obispo_county', '샌 루이스 오비스포 카운티', 'San Luis Obispo County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8510', 'true'),
  ('region', 'us_san_mateo_county', '샌 마테오 카운티', 'San Mateo County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8520', 'true'),
  ('region', 'us_santa_barbara_county', '산타 바바라 카운티', 'Santa Barbara County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8530', 'true'),
  ('region', 'us_santa_clara_county', '산타 클라라 카운티', 'Santa Clara County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8540', 'true'),
  ('region', 'us_santa_clara_vally', '산타 클라라 밸리', 'Santa Clara Vally', '{}', 'us_santa_clara_county', '{region}', '{}', '2.0.0', '9150', 'true'),
  ('region', 'us_santa_cruz_mountains', '산타 크루즈 마운틴스', 'Santa Cruz Mountains', '{}', 'us_san_mateo_county', '{region}', '{}', '2.0.0', '9160', 'true'),
  ('region', 'us_santa_lucia_highlands', '산타 루치아 하이랜즈', 'Santa Lucia Highlands', '{}', 'us_monterey_county', '{region}', '{}', '2.0.0', '9170', 'true'),
  ('region', 'us_santa_maria_valley', '산타 마리아 밸리', 'Santa Maria Valley', '{}', 'us_santa_barbara_county', '{region}', '{}', '2.0.0', '9180', 'true'),
  ('region', 'us_santa_rita_hills', '산타 리타 힐스', 'Santa Rita Hills', '{}', 'us_santa_barbara_county', '{region}', '{}', '2.0.0', '9190', 'true'),
  ('region', 'us_santa_ynez_valley', '산타 이네스 밸리', 'Santa Ynez Valley', '{}', 'us_santa_barbara_county', '{region}', '{}', '2.0.0', '9200', 'true'),
  ('region', 'us_sierra_foothills', '시에라 풋힐즈', 'Sierra Foothills', '{}', 'us_california', '{region}', '{}', '2.0.0', '8550', 'true'),
  ('region', 'us_snipes_mountain', '스나입스 마운틴', 'Snipes Mountain', '{}', 'us_washington_state', '{region}', '{}', '2.0.0', '8560', 'true'),
  ('region', 'us_solano_county', '솔라노 카운티', 'Solano County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8570', 'true'),
  ('region', 'us_sonoma', '소노마', 'Sonoma', '{}', 'us', '{region}', '{}', '2.0.0', '8270', 'true'),
  ('region', 'us_sonoma_coast', '소노마 코스트', 'Sonoma Coast', '{}', 'us_sonoma_county', '{region}', '{}', '2.0.0', '9210', 'true'),
  ('region', 'us_sonoma_county', '소노마 카운티', 'Sonoma County', '{}', 'us_california', '{region}', '{}', '2.0.0', '8580', 'true'),
  ('region', 'us_sonoma_mountain', '소노마 마운틴', 'Sonoma Mountain', '{}', 'us_sonoma_county', '{region}', '{}', '2.0.0', '9220', 'true'),
  ('region', 'us_sonoma_valley', '소노마 밸리', 'Sonoma Valley', '{}', 'us_sonoma_county', '{region}', '{}', '2.0.0', '9230', 'true'),
  ('region', 'us_southern_oregon', '서던 오리건', 'Southern Oregon', '{}', 'us_oregon', '{region}', '{}', '2.0.0', '8590', 'true'),
  ('region', 'us_spring_mountain_district_ava', '스프링 마운틴 디스트릭트 AVA', 'Spring Mountain district AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '9240', 'true'),
  ('region', 'us_st_helena_ava', '세인트 헬레나 AVA', 'St. Helena AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '9250', 'true'),
  ('region', 'us_stags_leap_district_ava', '스택스 립 디스트릭트 AVA', 'Stags Leap District AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '9260', 'true'),
  ('region', 'us_temecula_valley', '테메큘라 밸리', 'Temecula Valley', '{}', 'us_riverside_county', '{region}', '{}', '2.0.0', '9270', 'true'),
  ('region', 'us_tennessee', '테네시', 'Tennessee', '{}', 'us', '{region}', '{}', '2.0.0', '8280', 'true'),
  ('region', 'us_virginia', '버지니아', 'Virginia', '{}', 'us', '{region}', '{}', '2.0.0', '8290', 'true'),
  ('region', 'us_wahluke_slope', '왈루크 슬로프', 'Wahluke Slope', '{}', 'us_columbia_valley', '{region}', '{}', '2.0.0', '9280', 'true'),
  ('region', 'us_walla_walla_valley', '왈라 왈라 밸리', 'Walla Walla Valley', '{}', 'us_columbia_valley', '{region}', '{}', '2.0.0', '9290', 'true'),
  ('region', 'us_washington_state', '워싱턴', 'Washington State', '{}', 'us', '{region}', '{}', '2.0.0', '8300', 'true'),
  ('region', 'us_willakenzie_estate', '윌라켄지 이스테이트', 'WillaKenzie Estate', '{}', 'us_oregon', '{region}', '{}', '2.0.0', '8600', 'true'),
  ('region', 'us_willamette_valley', '윌라멧 밸리', 'Willamette Valley', '{}', 'us_oregon', '{region}', '{}', '2.0.0', '8610', 'true'),
  ('region', 'us_yakima_valley', '야키마 밸리', 'Yakima Valley', '{}', 'us_columbia_valley', '{region}', '{}', '2.0.0', '9300', 'true'),
  ('region', 'us_yamhill_carlton', '얌힐-칼튼', 'Yamhill-Carlton', '{}', 'us_willamette_valley', '{region}', '{}', '2.0.0', '9310', 'true'),
  ('region', 'us_yorville_highlands', '요크빌 하이랜즈', 'Yorville Highlands', '{}', 'us_mendocino_county', '{region}', '{}', '2.0.0', '9320', 'true'),
  ('region', 'us_yountville_ava', '욘트빌 AVA', 'Yountville AVA', '{}', 'us_napa_county', '{region}', '{}', '2.0.0', '9330', 'true'),
  ('region', 'uy', '우루과이', 'Uruguay', '{}', NULL, '{region}', '{}', '2.0.0', '9340', 'true'),
  ('region', 'uy_juanico', '후아니코', 'Juanico', '{}', 'uy', '{region}', '{}', '2.0.0', '9350', 'true'),
  ('region', 'uy_maldonado', '말도나도', 'Maldonado', '{}', 'uy', '{region}', '{}', '2.0.0', '9360', 'true'),
  ('region', 'za', '남아프리카공화국', 'South Africa', '{}', NULL, '{region}', '{}', '2.0.0', '9370', 'true'),
  ('region', 'za_breede_river_valley', '브리드 리버 밸리', 'Breede River Valley', '{}', 'za', '{region}', '{}', '2.0.0', '9380', 'true'),
  ('region', 'za_breedekloof', '브리덱루프', 'Breedekloof', '{}', 'za_breede_river_valley', '{region}', '{}', '2.0.0', '9440', 'true'),
  ('region', 'za_cape_south_coast', '케이프 사우스 코스트', 'Cape South Coast', '{}', 'za', '{region}', '{}', '2.0.0', '9390', 'true'),
  ('region', 'za_cape_town', '케이프 타운', 'Cape Town', '{}', 'za', '{region}', '{}', '2.0.0', '9400', 'true'),
  ('region', 'za_coastal_region', '코스탈 리젼', 'Coastal Region', '{}', 'za', '{region}', '{}', '2.0.0', '9410', 'true'),
  ('region', 'za_constantia', '콘스탄시아', 'Constantia', '{}', 'za_coastal_region', '{region}', '{}', '2.0.0', '9450', 'true'),
  ('region', 'za_darling', '달링', 'Darling', '{}', 'za_coastal_region', '{region}', '{}', '2.0.0', '9460', 'true'),
  ('region', 'za_elgin', '엘진', 'Elgin', '{}', 'za_overberg', '{region}', '{}', '2.0.0', '9550', 'true'),
  ('region', 'za_franschhoek_franschhoek_valley', '프란스후크', 'Franschhoek / Franschhoek Valley', '{}', 'za_coastal_region', '{region}', '{}', '2.0.0', '9470', 'true'),
  ('region', 'za_groenekloof', '그뢰네클루프', 'Groenekloof', '{}', 'za_darling', '{region}', '{}', '2.0.0', '9560', 'true'),
  ('region', 'za_jonkershoek_valley', '존커셕 밸리', 'Jonkershoek Valley', '{}', 'za_stellenbosch', '{region}', '{}', '2.0.0', '9570', 'true'),
  ('region', 'za_lutzville_valley', '루츠빌 밸리', 'Lutzville Valley', '{}', 'za_olifants_river', '{region}', '{}', '2.0.0', '9480', 'true'),
  ('region', 'za_olifants_river', '올리판츠 리버', 'Olifants River', '{}', 'za', '{region}', '{}', '2.0.0', '9420', 'true'),
  ('region', 'za_overberg', '오버버그', 'Overberg', '{}', 'za_cape_south_coast', '{region}', '{}', '2.0.0', '9490', 'true'),
  ('region', 'za_paarl', '팔', 'Paarl', '{}', 'za_coastal_region', '{region}', '{}', '2.0.0', '9500', 'true'),
  ('region', 'za_robertson', '로버트슨', 'Robertson', '{}', 'za_breede_river_valley', '{region}', '{}', '2.0.0', '9510', 'true'),
  ('region', 'za_stellenbosch', '스텔렌보쉬', 'Stellenbosch', '{}', 'za_coastal_region', '{region}', '{}', '2.0.0', '9520', 'true'),
  ('region', 'za_swartland', '스와르트랜드', 'Swartland', '{}', 'za_coastal_region', '{region}', '{}', '2.0.0', '9530', 'true'),
  ('region', 'za_walker_bay', '워커 베이', 'Walker Bay', '{}', 'za_cape_south_coast', '{region}', '{}', '2.0.0', '9540', 'true'),
  ('region', 'za_wellington', '웰링턴', 'Wellington', '{}', 'za_paarl', '{region}', '{}', '2.0.0', '9580', 'true'),
  ('region', 'za_western_cape', '웨스턴 케이프', 'Western Cape', '{}', 'za', '{region}', '{}', '2.0.0', '9430', 'true'),
  ('sensory_descriptor', 'acacia', '아카시아꽃', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["acacia"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '470', 'true'),
  ('sensory_descriptor', 'agave', '아가베', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["agave"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '450', 'true'),
  ('sensory_descriptor', 'aged_aromatic', '묵은 양주', NULL, '{"다크 럼",란치오,마데이라,버번,브랜디,코냑}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["cognac", "dark_rum", "madeira", "brandy_note", "bourbon_note", "aged_aromatic", "rancio"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1060', 'true'),
  ('sensory_descriptor', 'alcohol_aroma', '알코올', NULL, '{}', NULL, '{aroma}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1290', 'true'),
  ('sensory_descriptor', 'almond', '아몬드', NULL, '{"설탕 코팅된 아몬드",아마레토}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["almond", "sugar_coated_almond", "amaretto"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '830', 'true'),
  ('sensory_descriptor', 'angular_character', '날카롭고 각진 감각', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1300', 'true'),
  ('sensory_descriptor', 'animalic', '동물성', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1310', 'true'),
  ('sensory_descriptor', 'apple', '사과', NULL, '{"골든 애플","구운 사과","노란 사과","달콤한 사과","레드 애플","리몬첼라 사과","붉은 사과","붉은 사과 껍질","빨간 사과","사과 껍질","사과 농축액","사과 사이더","사과 주스","신선한 사과","안누르카 사과","잘 익은 사과","푸른 과수원 과일"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["apple", "baked_apple", "red_apple_skin", "ripe_apple", "fresh_apple", "sweet_apple", "limoncella_apple", "annurca_apple", "apple_juice", "apple_concentrate", "apple_peel", "apple_cider", "green_orchard_fruit", "yellow_apple", "red_apple", "golden_apple"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '10', 'true'),
  ('sensory_descriptor', 'apricot', '살구', NULL, '{"절인 살구"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["apricot", "pickled_apricot"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '60', 'true'),
  ('sensory_descriptor', 'astringent_texture', '떫은 질감', NULL, '{"가루처럼 느껴지는 질감","거친 질감","백악질 질감","분필 같은 질감","입안을 조이는 감각","입안이 마르는 감각","입안이 오므라드는 감각"}', NULL, '{finish,palate,texture}', '{"user_visible": true, "sensory_service": {"domain": "texture", "status": "representative", "version": "2.0.0", "source_keys": ["drying_texture", "gripping_texture", "puckering_texture", "powdery_texture", "rough_texture", "chalky_texture"], "category_key": "texture", "category_label_ko": "질감 및 여운", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1230', 'true'),
  ('sensory_descriptor', 'balanced_character', '균형 잡힌 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1320', 'true'),
  ('sensory_descriptor', 'banana', '바나나', NULL, '{바나나칩}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["banana", "banana_chip"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '300', 'true'),
  ('sensory_descriptor', 'barley', '보리', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["barley"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '740', 'true'),
  ('sensory_descriptor', 'beeswax', '밀랍', NULL, '{}', NULL, '{aroma,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1330', 'true'),
  ('sensory_descriptor', 'bell_pepper', '피망', NULL, '{파프리카}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["bell_pepper", "paprika"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '560', 'true'),
  ('sensory_descriptor', 'berry', '베리', NULL, '{"검은 베리",구스베리,"달콤한 라즈베리","달콤한 블랙베리",라즈베리,랍스베리,레드커런트,보이젠베리,복분자,"붉은 베리","브램블·야생 베리 덤불",블랙라즈베리,블랙베리,블랙커런트,빌베리,"신선한 라즈베리","신선한 블랙베리","야생 베리",엘더베리,오디,오미자,"잘 익은 라즈베리","잘 익은 블랙베리",커런트,"크렘 드 카시스"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["berry", "bilberry", "blackberry", "blackcurrant", "bokbunja", "boysenberry", "bramble", "gooseberry", "omija", "raspberry", "redcurrant", "ripe_raspberry", "fresh_raspberry", "sweet_raspberry", "ripe_blackberry", "fresh_blackberry", "sweet_blackberry", "red_berry", "dark_berry", "creme_de_cassis", "wild_berry", "black_raspberry", "elderberry", "currant", "mulberry"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '100', 'true'),
  ('sensory_descriptor', 'black_fruit', '검은 과일', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1340', 'true'),
  ('sensory_descriptor', 'black_mulberry', '검은 뽕나무', NULL, '{}', NULL, '{aroma}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1350', 'true'),
  ('sensory_descriptor', 'black_tea', '홍차', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["black_tea"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '540', 'true'),
  ('sensory_descriptor', 'blueberry', '블루베리', NULL, '{"달콤한 블루베리","블루베리 페이스트","신선한 블루베리","잘 익은 블루베리"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["blueberry", "ripe_blueberry", "fresh_blueberry", "sweet_blueberry", "blueberry_paste"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '130', 'true'),
  ('sensory_descriptor', 'borisu_note', '보리수', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1360', 'true'),
  ('sensory_descriptor', 'bread', '빵·케이크', NULL, '{"과일 케이크","다이제스티브 비스켓","다이제스티브 비스킷","레몬 타르트",레몬타르트,브리오슈,"블랙 포레스트 케이크",비스킷,빵,빵·비스킷,쇼트브레드,웨이퍼,"체리 타르트","체리 파이",케이크,쿠키,"쿠키 반죽","크리스마스 케이크",타르트,파이,"팬 케이크",팬케이크,페이스트리}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["bakery", "biscuit", "black_forest_cake", "bread", "brioche", "cherry_tart", "christmas_cake", "cookie_dough", "fruit_cake", "pastry", "pie", "cake", "shortbread", "tart", "cherry_pie", "lemon_tart", "digestive_biscuit", "pancake", "cookie", "wafer"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '630', 'true'),
  ('sensory_descriptor', 'bright_character', '화사한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1370', 'true'),
  ('sensory_descriptor', 'broad_aroma', '폭넓은 아로마', NULL, '{}', NULL, '{aroma}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1380', 'true'),
  ('sensory_descriptor', 'brown_sugar', '흑설탕', NULL, '{"데메라라 설탕"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["brown_sugar", "demerara_sugar"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '790', 'true'),
  ('sensory_descriptor', 'bubbles_texture', '기포 (스파클링)', NULL, '{"거품 같은 질감","고운 기포","따끔하게 닿는 기포","부드러운 기포","사르르 사라지는 기포","조밀한 기포"}', NULL, '{finish,palate,texture}', '{"user_visible": true, "sensory_service": {"domain": "texture", "status": "representative", "version": "2.0.0", "source_keys": ["fine_bubbles", "foamy_texture", "prickly_bubbles", "soft_bubbles", "dissipating_bubbles", "dense_bubbles"], "category_key": "texture", "category_label_ko": "질감 및 여운", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1250', 'true'),
  ('sensory_descriptor', 'butter', '버터', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["butter"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '900', 'true'),
  ('sensory_descriptor', 'candied_character', '당절임한', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1390', 'true'),
  ('sensory_descriptor', 'candy', '캔디', NULL, '{"과일 캔디","라무네 소다","레몬 캔디",루트비어,버블검,"붉은 감초",솜사탕,젤리,콜라,"페어리 플로스"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["candy", "cotton_candy", "jelly", "bubblegum", "fruit_candy", "lemon_candy", "ramune", "red_liquorice", "cola_note", "root_beer"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '820', 'true'),
  ('sensory_descriptor', 'caramel', '캐러멜', NULL, '{"다크 캐러멜","크리미한 카라멜","크리미한 캐러멜"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["caramel", "dark_caramel", "creamy_caramel"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '780', 'true'),
  ('sensory_descriptor', 'cashew', '캐슈넛', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["cashew"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '870', 'true'),
  ('sensory_descriptor', 'celery', '셀러리', NULL, '{}', NULL, '{aroma}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["celery"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '600', 'true'),
  ('sensory_descriptor', 'cereal', '곡물', NULL, '{귀리,메밀,수수,호밀}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["buckwheat", "oat", "rye", "sorghum", "cereal"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '640', 'true'),
  ('sensory_descriptor', 'chamomile', '캐모마일', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["chamomile"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '510', 'true'),
  ('sensory_descriptor', 'cheese', '치즈', NULL, '{크림치즈}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["cheese", "cream_cheese"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '920', 'true'),
  ('sensory_descriptor', 'cherry', '체리', NULL, '{"달콤한 블랙체리","달콤한 체리","마라스카 체리","마라스키노 체리","모렐로 체리","붉은 체리",블랙체리,빙체리,"새콤한 체리","설탕에 절인 체리","신선한 블랙체리","신선한 체리",앵두,"잘 익은 블랙체리","잘 익은 체리",키르슈}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["black_cherry", "candied_cherry", "cherry", "fresh_cherry", "korean_cherry", "sour_cherry", "ripe_cherry", "sweet_cherry", "ripe_black_cherry", "fresh_black_cherry", "sweet_black_cherry", "kirsch", "bing_cherry", "marasca_cherry", "morello_cherry", "red_cherry", "maraschino_cherry"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '90', 'true'),
  ('sensory_descriptor', 'cherry_wood', '체리나무', NULL, '{}', NULL, '{aroma,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["cherry_wood"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1100', 'true'),
  ('sensory_descriptor', 'chocolate', '초콜릿', NULL, '{다크초콜릿,밀크초콜릿,"세미스위트 초콜릿","카카오 닙","카카오 닙스",카카오닙스,코코아,"코코아 버터",화이트초콜릿}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["dark_chocolate", "milk_chocolate", "white_chocolate", "chocolate", "cocoa", "semisweet_chocolate", "cocoa_nibs", "cocoa_butter"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '670', 'true'),
  ('sensory_descriptor', 'cinnamon', '계피', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["cinnamon"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1130', 'true'),
  ('sensory_descriptor', 'citrus', '시트러스', NULL, '{"노란 포멜로",베르가모트,스다치,시쿠와사,"시트러스 과일 껍질","시트러스 오일",카보스,포멜로}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["bergamot", "kabosu", "pomelo", "shikuwasa", "sudachi", "citrus_peel", "citrus", "yellow_pomelo", "citrus_oil"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '190', 'true'),
  ('sensory_descriptor', 'clean_character', '깨끗한 인상', NULL, '{}', NULL, '{aroma,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1400', 'true'),
  ('sensory_descriptor', 'clean_finish', '깔끔한 마무리', NULL, '{}', NULL, '{finish}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1410', 'true'),
  ('sensory_descriptor', 'clear_character', '또렷한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1420', 'true'),
  ('sensory_descriptor', 'clove', '정향', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["clove"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1150', 'true'),
  ('sensory_descriptor', 'coating_texture', '입안을 감싸는 질감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1430', 'true'),
  ('sensory_descriptor', 'coconut', '코코넛', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["coconut"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '310', 'true'),
  ('sensory_descriptor', 'coffee', '커피', NULL, '{에스프레소,"커피 콩",커피콩}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["coffee", "espresso"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '880', 'true'),
  ('sensory_descriptor', 'complex_character', '복합적인 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1440', 'true'),
  ('sensory_descriptor', 'complex_finish', '복합적인 여운', NULL, '{}', NULL, '{finish}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1450', 'true'),
  ('sensory_descriptor', 'concentrated_character', '농축된 풍미', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1460', 'true'),
  ('sensory_descriptor', 'concentrated_texture', '농축된 질감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1470', 'true'),
  ('sensory_descriptor', 'concentrated_umami', '농축된 감칠맛 인상', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1480', 'true'),
  ('sensory_descriptor', 'cooked_preserved_fruit', '졸인 과일', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1490', 'true'),
  ('sensory_descriptor', 'cool_character', '시원한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1500', 'true'),
  ('sensory_descriptor', 'coriander_seed', '코리앤더 씨드', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["coriander_seed"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1160', 'true'),
  ('sensory_descriptor', 'corn', '옥수수', NULL, '{팝콘}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["corn", "popcorn"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '720', 'true'),
  ('sensory_descriptor', 'cranberry', '크랜베리', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["cranberry"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '120', 'true'),
  ('sensory_descriptor', 'cream', '크림', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["cream"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '910', 'true'),
  ('sensory_descriptor', 'crisp_acidity', '크리스피한 산미', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1510', 'true'),
  ('sensory_descriptor', 'crisp_character', '크리스피한 감각 인상', NULL, '{}', NULL, '{aroma,finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1520', 'true'),
  ('sensory_descriptor', 'crushed_character', '으깬 과실의 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1530', 'true'),
  ('sensory_descriptor', 'cucumber', '오이', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["cucumber"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '590', 'true'),
  ('sensory_descriptor', 'dairy', '유제품', NULL, '{우유}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["dairy", "milk"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '710', 'true'),
  ('sensory_descriptor', 'dairy_creamy', '유제품·크림', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "pending", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1540', 'true'),
  ('sensory_descriptor', 'deep_character', '깊은 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1550', 'true'),
  ('sensory_descriptor', 'deepened_character', '깊이가 더해진 인상', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1560', 'true'),
  ('sensory_descriptor', 'dessert_aromatic', '디저트', NULL, '{누가,당밀,"레몬 커드",마시멜로,마지팬,머랭,"브레드 푸딩",사쿠라모치,사탕수수,설탕,시럽,"옥수수 시럽",커스터드,"크렘 브륄레","크렘 캐러멜","크리스마스 푸딩","터키쉬 딜라이트",티라미수,퍼지,푸딩}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["sugarcane", "corn_syrup", "molasses_note", "christmas_pudding", "creme_brulee", "tiramisu", "lemon_curd", "marshmallow", "nougat", "fudge", "turkish_delight", "sakura_mochi", "marzipan", "custard", "creme_caramel", "meringue", "sugar_aroma", "pudding", "syrup", "bread_pudding", "dessert_aromatic"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '650', 'true'),
  ('sensory_descriptor', 'dried_character', '말린', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1570', 'true'),
  ('sensory_descriptor', 'dried_fruit', '말린 과일', NULL, '{곶감,대추,대추야자,"럼 건포도",럼레이즌,"말린 무화과","말린 살구","말린 크랜베리","말린 파인애플","쉐리에 절인 건포도",프룬}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["date", "dried_apricot", "dried_fig", "dried_persimmon", "dried_pineapple", "prune", "jujube", "dried_fruit", "dried_cranberry"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '280', 'true'),
  ('sensory_descriptor', 'dry_character', '드라이한 인상', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1580', 'true'),
  ('sensory_descriptor', 'dry_finish', '드라이한 마무리', NULL, '{}', NULL, '{finish}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1590', 'true'),
  ('sensory_descriptor', 'dusty_character', '먼지 같은 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1600', 'true'),
  ('sensory_descriptor', 'earl_grey', '얼그레이', NULL, '{}', NULL, '{aroma,finish}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["earl_grey"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '550', 'true'),
  ('sensory_descriptor', 'earth', '흙', NULL, '{나무이끼,"마른 흙","숲 바닥","젖은 낙엽","젖은 흙"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["wet_earth", "dry_earth", "earth", "forest_floor", "tree_moss", "wet_leaf"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '950', 'true'),
  ('sensory_descriptor', 'effervescent_texture', '탄산감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1610', 'true'),
  ('sensory_descriptor', 'essential_oil', '에센셜 오일', NULL, '{}', NULL, '{palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1620', 'true'),
  ('sensory_descriptor', 'ester', '에스테르', NULL, '{}', NULL, '{aroma}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1630', 'true'),
  ('sensory_descriptor', 'exotic_character', '이국적인 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1640', 'true'),
  ('sensory_descriptor', 'fermentation', '발효 향', NULL, '{발사믹,발효,브렛,식초,"식초 향","야생 발효","야생 발효 향","왁스 향",유산발효}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["brett", "lactic", "fermentation", "balsamic", "vinegar", "wild_fermentation"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1040', 'true'),
  ('sensory_descriptor', 'fine_grained_character', '고운 입자감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1650', 'true'),
  ('sensory_descriptor', 'firm_character', '탄탄한 감각의 인상', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1660', 'true'),
  ('sensory_descriptor', 'firm_texture', '탄탄한 질감', NULL, '{"단단한 구조감","입안을 채우는 볼륨감","쫀득한 질감","팽팽한 긴장감"}', NULL, '{finish,palate,texture}', '{"user_visible": true, "sensory_service": {"domain": "texture", "status": "representative", "version": "2.0.0", "source_keys": ["chewy_texture", "firm_structure", "mouthfilling_texture", "taut_texture"], "category_key": "texture", "category_label_ko": "질감 및 여운", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1220', 'true'),
  ('sensory_descriptor', 'first_impression', '첫 입안의 인상', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1670', 'true'),
  ('sensory_descriptor', 'floral', '꽃', NULL, '{국화,금목서,등나무꽃,라일락,"말린 꽃",매화,배꽃,백합,벚꽃,복숭아꽃,"붉은 꽃",사과꽃,살구꽃,"시트러스 꽃",아이리스,엘더플라워,연꽃,"오렌지 꽃",용안꽃,제라늄,제비꽃,진달래,프랑지파니,프리지아,"피나무 꽃",허니서클,헤더,"흰 꽃","흰 라일락",히비스커스}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["cherry_blossom", "orange_blossom", "apple_blossom", "elderflower", "lily", "longan_blossom", "pear_blossom", "frangipani", "honeysuckle", "osmanthus", "lilac", "white_flower", "azalea", "hibiscus", "peach_blossom", "violet", "iris", "red_flower", "chrysanthemum", "heather", "dried_flower", "floral", "freesia", "white_lilac", "apricot_blossom", "linden_blossom", "plum_blossom", "citrus_blossom", "geranium", "lotus_flower", "wisteria"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '370', 'true'),
  ('sensory_descriptor', 'flowing_texture', '흐르는 질감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1680', 'true'),
  ('sensory_descriptor', 'forest_character', '숲을 연상시키는 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1690', 'true'),
  ('sensory_descriptor', 'fragrant_character', '향긋한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1700', 'true'),
  ('sensory_descriptor', 'fresh_acidity', '신선한 산미', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1710', 'true'),
  ('sensory_descriptor', 'fresh_fig', '무화과', NULL, '{"달콤한 무화과","신선한 무화과","잘 익은 무화과"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["fresh_fig", "ripe_fresh_fig", "sweet_fresh_fig"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '250', 'true'),
  ('sensory_descriptor', 'fresh_fresh_fruit', '신선한 과일', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1720', 'true'),
  ('sensory_descriptor', 'fresh_fruit', '과일', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "pending", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1730', 'true'),
  ('sensory_descriptor', 'freshly_baked_character', '갓 구운 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1740', 'true'),
  ('sensory_descriptor', 'fruit', '과실', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "pending", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1750', 'true'),
  ('sensory_descriptor', 'fruit_syrup', '과일시럽', NULL, '{"과일 시럽","무화과 시럽"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["fruit_syrup", "fig_syrup"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '270', 'true'),
  ('sensory_descriptor', 'fully_ripe_character', '농익은 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1760', 'true'),
  ('sensory_descriptor', 'gentle_character', '부드러운 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1770', 'true'),
  ('sensory_descriptor', 'gentle_spread_character', '가볍게 퍼지는 인상', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1780', 'true'),
  ('sensory_descriptor', 'ginger', '생강', NULL, '{"분말 생강","생강 사탕"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["ginger", "ginger_candy", "powdered_ginger"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1140', 'true'),
  ('sensory_descriptor', 'ginjo_aroma', '긴조', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["ginjo_aroma"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1190', 'true'),
  ('sensory_descriptor', 'glossy_texture', '윤기 있는 질감', NULL, '{}', NULL, '{texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1790', 'true'),
  ('sensory_descriptor', 'gradual_emergence', '점차 드러나는 감각', NULL, '{}', NULL, '{aroma,finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1800', 'true'),
  ('sensory_descriptor', 'grain_bakery_nut', '곡물·빵·견과', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "pending", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1810', 'true'),
  ('sensory_descriptor', 'grape', '포도', NULL, '{거봉,"포도 껍질","포도 주스",포도주스}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["kyoho_grape", "grape_skin", "grape", "grape_juice"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '200', 'true'),
  ('sensory_descriptor', 'grapefruit', '자몽', NULL, '{"레드 자몽","핑크 자몽"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["grapefruit", "pink_grapefruit", "red_grapefruit"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '350', 'true'),
  ('sensory_descriptor', 'green_apple', '청사과', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["green_apple"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '20', 'true'),
  ('sensory_descriptor', 'green_grape', '청포도', NULL, '{머스캣}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["green_grape", "muscat"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '210', 'true'),
  ('sensory_descriptor', 'green_tea', '녹차', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["green_tea"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '520', 'true'),
  ('sensory_descriptor', 'hawthorn', '산사나무', NULL, '{}', NULL, '{aroma,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1820', 'true'),
  ('sensory_descriptor', 'hay', '건초', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["hay"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '430', 'true'),
  ('sensory_descriptor', 'hazelnut', '헤이즐넛', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["hazelnut"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '850', 'true'),
  ('sensory_descriptor', 'heavy_texture', '묵직한 질감', NULL, '{"걸쭉한 질감","과즙감 있는 질감","끈적한 질감","녹진한 질감","두터운 질감","시럽 같은 질감","오일리한 질감","크리미한 질감"}', NULL, '{finish,palate,texture}', '{"user_visible": true, "sensory_service": {"domain": "texture", "status": "representative", "version": "2.0.0", "source_keys": ["creamy_texture", "oily_texture", "sticky_texture", "syrupy_texture", "thick_texture", "unctuous_texture", "viscous_texture", "juicy_texture"], "category_key": "texture", "category_label_ko": "질감 및 여운", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1200', 'true'),
  ('sensory_descriptor', 'herbal', '허브', NULL, '{가리그,"가리그 허브",고수,딜,레몬그라스,레몬밤,로즈마리,"말린 허브",머틀,바질,"분말 세이지",생허브,세이지,"세이지 가루",쑥,오레가노,월계수잎,자소엽,"지중해 허브",타임,회향}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["basil", "rosemary", "thyme", "sage", "cilantro", "dill", "fennel", "shiso", "lemongrass", "fresh_herb", "herbal", "dried_herb", "mediterranean_herb", "myrtle", "lemon_balm", "oregano", "mugwort", "garrigue", "powdered_sage", "bay_leaf"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '390', 'true'),
  ('sensory_descriptor', 'herbal_green_tea', '허브·풀·차', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "pending", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1830', 'true'),
  ('sensory_descriptor', 'honey', '꿀', NULL, '{꽃꿀,"마누카 꿀",벌집,"사과 꿀"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["honey", "apple_honey", "manuka_honey", "floral_honey", "honeycomb"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '810', 'true'),
  ('sensory_descriptor', 'hop', '홉', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["hop"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '400', 'true'),
  ('sensory_descriptor', 'immediate_onset', '즉각적인 감각 발현', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1840', 'true'),
  ('sensory_descriptor', 'in_glass_development', '잔 안에서의 변화', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1850', 'true'),
  ('sensory_descriptor', 'incense', '인센스', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["incense"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1090', 'true'),
  ('sensory_descriptor', 'integrated_character', '녹아든 감각의 인상', NULL, '{}', NULL, '{aroma,finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1860', 'true'),
  ('sensory_descriptor', 'intensity_character', '강도감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1870', 'true'),
  ('sensory_descriptor', 'jalapeno', '할라피뇨', NULL, '{}', NULL, '{aroma}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["jalapeno"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '570', 'true'),
  ('sensory_descriptor', 'jammy', '과일잼', NULL, '{"당절임 과일","데친 과일",마멀레이드,애플버터,"졸인 사과",콤포트}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["jammy", "marmalade", "stewed_apple", "compote", "poached_fruit", "apple_butter", "candied_fruit"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '260', 'true'),
  ('sensory_descriptor', 'jasmine', '자스민', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["jasmine"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '480', 'true'),
  ('sensory_descriptor', 'juicy_character', '과즙을 연상시키는 인상', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1880', 'true'),
  ('sensory_descriptor', 'juniper', '주니퍼베리', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["juniper"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1170', 'true'),
  ('sensory_descriptor', 'kiwi', '키위', NULL, '{"골든 키위"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["kiwi", "golden_kiwi"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '320', 'true'),
  ('sensory_descriptor', 'korean_melon', '참외', NULL, '{}', NULL, '{aroma,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["korean_melon"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '230', 'true'),
  ('sensory_descriptor', 'lavender', '라벤더', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["lavender"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '500', 'true'),
  ('sensory_descriptor', 'layered_character', '층을 이루는 감각', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1890', 'true'),
  ('sensory_descriptor', 'leaf', '풀·나뭇잎', NULL, '{"대나무 잎",밀싹,"블랙커런트 잎",블랙커런트잎,연잎,잎,"카시스 잎","토마토 잎",토마토잎,풀}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["bamboo_leaf", "leaf", "grass", "wheatgrass", "blackcurrant_leaf", "tomato_leaf", "lotus_leaf"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '420', 'true'),
  ('sensory_descriptor', 'leather', '가죽', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["leather"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1270', 'true'),
  ('sensory_descriptor', 'lemon_lime', '레몬·라임', NULL, '{라임,"라임 껍질",레몬,"레몬 껍질","레몬 셔벗","레몬 소르베","레몬 주스",레몬셔벗,"말린 레몬 껍질",말린레몬껍질,"메이어 레몬","절인 레몬","카피르 라임"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["lemon", "lemon_peel", "lime", "lime_peel", "meyer_lemon", "lemon_juice", "preserved_lemon", "lemon_sorbet", "dried_lemon_peel", "kaffir_lime", "lemon_lime"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '170', 'true'),
  ('sensory_descriptor', 'light_texture', '가벼운 질감', NULL, '{"묽고 물 같은 질감"}', NULL, '{finish,palate,texture}', '{"user_visible": true, "sensory_service": {"domain": "texture", "status": "representative", "version": "2.0.0", "source_keys": ["watery_texture"], "category_key": "texture", "category_label_ko": "질감 및 여운", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1240', 'true'),
  ('sensory_descriptor', 'linear_texture', '곧게 뻗는 입안 느낌', NULL, '{}', NULL, '{texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1900', 'true'),
  ('sensory_descriptor', 'lingonberry', '월귤나무', NULL, '{}', NULL, '{aroma}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1910', 'true'),
  ('sensory_descriptor', 'lively_acidity', '경쾌한 산미', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1920', 'true'),
  ('sensory_descriptor', 'lively_character', '생동감 있는 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1930', 'true'),
  ('sensory_descriptor', 'luscious_texture', '감미로운 질감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1940', 'true'),
  ('sensory_descriptor', 'lychee', '리치', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["lychee"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '150', 'true'),
  ('sensory_descriptor', 'macadamia', '마카다미아', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["macadamia"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '860', 'true'),
  ('sensory_descriptor', 'malt', '맥아', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["malt"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '750', 'true'),
  ('sensory_descriptor', 'mango', '망고', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["mango"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '330', 'true'),
  ('sensory_descriptor', 'maple_syrup', '메이플 시럽', NULL, '{메이플}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["maple_syrup", "maple_note"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '800', 'true'),
  ('sensory_descriptor', 'matcha', '말차', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["matcha"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '530', 'true'),
  ('sensory_descriptor', 'medicinal', '약품', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1950', 'true'),
  ('sensory_descriptor', 'medicinal_herb', '약초', NULL, '{가라나,약재,인삼,허니부쉬}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["ginseng", "guarana", "honeybush", "medicinal_herb"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '460', 'true'),
  ('sensory_descriptor', 'medium_dry_character', '중간 정도로 드라이한 인상', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1960', 'true'),
  ('sensory_descriptor', 'melon', '멜론', NULL, '{"머스크 멜론","멜론 껍질",허니듀,"화이트 멜론","흰 멜론"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["melon", "melon_peel", "musk_melon", "honeydew", "white_melon"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '220', 'true'),
  ('sensory_descriptor', 'mid_palate', '중구개', NULL, '{}', NULL, '{palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1970', 'true'),
  ('sensory_descriptor', 'mineral', '미네랄', NULL, '{"굴 껍질",금속,분필,석회암,"젖은 초크",조개껍데기,철분,활석}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["mineral", "chalk", "oyster_shell", "iron", "metallic", "shell_note", "wet_chalk", "limestone", "talc"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '980', 'true'),
  ('sensory_descriptor', 'mint', '민트', NULL, '{멘톨,스피어민트,애플민트,유칼립투스,페퍼민트}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["mint", "eucalyptus", "spearmint", "peppermint", "menthol", "apple_mint"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '380', 'true'),
  ('sensory_descriptor', 'mocha', '모카', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["mocha"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '890', 'true'),
  ('sensory_descriptor', 'moist_texture', '촉촉한 질감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1980', 'true'),
  ('sensory_descriptor', 'mouth_edge_roughness', '입안 가장자리의 거친 감촉', NULL, '{}', NULL, '{texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '1990', 'true'),
  ('sensory_descriptor', 'mouthwatering_acidity', '침이 고이는 산미', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2000', 'true'),
  ('sensory_descriptor', 'mouthwatering_character', '침이 고이는 맛의 인상', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2010', 'true'),
  ('sensory_descriptor', 'mushroom', '버섯', NULL, '{능이버섯,송로버섯}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["neungi_mushroom", "truffle", "mushroom"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '960', 'true'),
  ('sensory_descriptor', 'musk', '머스크', NULL, '{머스크향,사향}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["musk"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1280', 'true'),
  ('sensory_descriptor', 'natural_character', '자연스러운 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2020', 'true'),
  ('sensory_descriptor', 'naturally_fermented_carbonation', '자연 발효 탄산', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2030', 'true'),
  ('sensory_descriptor', 'nuruk', '누룩·코지', NULL, '{코지}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["nuruk", "koji"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1180', 'true'),
  ('sensory_descriptor', 'nutty', '견과', NULL, '{땅콩,"땅콩 버터",땅콩버터,밤,"브라질 너트",살구씨,"설탕 코팅 아몬드",참깨·흑임자,"체리 씨앗","콜라 너트","토피 넛",토피넛,프랄린,피칸}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["pecan", "apricot_kernel", "cherry_pit", "sesame", "kola_nut", "nutty", "chestnut", "praline", "peanut", "brazil_nut", "peanut_butter", "toffee_nut"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '680', 'true'),
  ('sensory_descriptor', 'nutty_character', '고소한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2040', 'true'),
  ('sensory_descriptor', 'oak', '오크', NULL, '{"떡갈 나무",떡갈나무,"와인 배럴"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["oak", "tteokgal_oak", "wine_barrel"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1080', 'true'),
  ('sensory_descriptor', 'oily_character', '오일리한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2050', 'true'),
  ('sensory_descriptor', 'olive', '올리브', NULL, '{"검은 올리브","그린 올리브"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["olive", "black_olive", "green_olive"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1010', 'true'),
  ('sensory_descriptor', 'orange_tangerine', '오렌지·귤', NULL, '{귤,금귤,"금귤 껍질",만다린,"블러드 오렌지","비터 오렌지",오렌지,"오렌지 껍질","오렌지 주스",오렌지주스,클레멘타인}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["orange", "orange_peel", "tangerine", "mandarin", "clementine", "kumquat", "kumquat_peel", "blood_orange", "orange_juice", "bitter_orange", "orange_tangerine"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '160', 'true'),
  ('sensory_descriptor', 'orchard_character', '과수원', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2060', 'true'),
  ('sensory_descriptor', 'orchard_fruit', '사과·배', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2070', 'true'),
  ('sensory_descriptor', 'overall_flavour', '전체 풍미', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2080', 'true'),
  ('sensory_descriptor', 'overall_structure', '전체 구조', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2090', 'true'),
  ('sensory_descriptor', 'overall_texture', '전체 질감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2100', 'true'),
  ('sensory_descriptor', 'peach', '복숭아', NULL, '{"달콤한 복숭아","신선한 복숭아","잘 익은 복숭아",천도복숭아,"흰 복숭아"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["peach", "nectarine", "ripe_peach", "fresh_peach", "sweet_peach", "white_peach"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '50', 'true'),
  ('sensory_descriptor', 'pear', '배', NULL, '{"그린 페어","꿀에 절인 배","달콤한 배","신선한 배","잘 익은 배"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["pear", "ripe_pear", "fresh_pear", "sweet_pear", "green_pear", "honeyed_pear"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '30', 'true'),
  ('sensory_descriptor', 'peat', '피트', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["peat"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1120', 'true'),
  ('sensory_descriptor', 'pepper', '후추', NULL, '{백후추,"분홍 후추",통후추,페퍼콘,"핑크 페퍼",핑크페퍼,흑후추}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["black_pepper", "white_pepper", "pepper", "pink_pepper", "peppercorn"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1020', 'true'),
  ('sensory_descriptor', 'persistent_bubbles', '지속적인 기포', NULL, '{}', NULL, '{texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2110', 'true'),
  ('sensory_descriptor', 'persistent_character', '계속 남는 감각', NULL, '{}', NULL, '{aroma,finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2120', 'true'),
  ('sensory_descriptor', 'petrol', '석유', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2130', 'true'),
  ('sensory_descriptor', 'phenolic', '페놀릭', NULL, '{}', NULL, '{palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2140', 'true'),
  ('sensory_descriptor', 'pineapple', '파인애플', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["pineapple"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '340', 'true'),
  ('sensory_descriptor', 'plain_character', '담백한 맛의 인상', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2150', 'true'),
  ('sensory_descriptor', 'plum', '자두', NULL, '{"검은 자두","달콤한 자두","신선한 자두","잘 익은 자두"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["plum", "ripe_plum", "fresh_plum", "sweet_plum", "black_plum"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '70', 'true'),
  ('sensory_descriptor', 'pomegranate', '석류', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["pomegranate"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '360', 'true'),
  ('sensory_descriptor', 'potato', '감자', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["potato"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '610', 'true'),
  ('sensory_descriptor', 'powerful_character', '힘 있는 풍미의 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2160', 'true'),
  ('sensory_descriptor', 'quince', '모과', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["quince"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '40', 'true'),
  ('sensory_descriptor', 'raisin', '건포도', NULL, '{"럼 레이즌","셰리에 절인 건포도"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["raisin", "rum_raisin", "sherry_soaked_raisin"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '290', 'true'),
  ('sensory_descriptor', 'red_fruit', '붉은 과일', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2170', 'true'),
  ('sensory_descriptor', 'refined_character', '섬세한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2180', 'true'),
  ('sensory_descriptor', 'refined_structure', '섬세한 구조감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2190', 'true'),
  ('sensory_descriptor', 'refreshing_character', '산뜻하고 상쾌한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2200', 'true'),
  ('sensory_descriptor', 'refreshing_finish', '산뜻하고 상쾌한 마무리', NULL, '{}', NULL, '{finish}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2210', 'true'),
  ('sensory_descriptor', 'relative_intensity_increase', '이전 상태보다 강해진 감각', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2220', 'true'),
  ('sensory_descriptor', 'restrained_character', '절제된 인상', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2230', 'true'),
  ('sensory_descriptor', 'restrained_texture', '절제된 질감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2240', 'true'),
  ('sensory_descriptor', 'rhubarb', '루바브', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "pending", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2250', 'true'),
  ('sensory_descriptor', 'rice', '쌀', NULL, '{누룽지,쌀겨}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["rice", "scorched_rice", "rice_bran"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '730', 'true'),
  ('sensory_descriptor', 'rich_character', '풍부한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2260', 'true'),
  ('sensory_descriptor', 'rich_texture', '풍성한 질감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2270', 'true'),
  ('sensory_descriptor', 'ripe_fresh_fruit', '잘 익은 과일', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2280', 'true'),
  ('sensory_descriptor', 'roasted', '로스팅', NULL, '{"배럴 토스트"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["roasted", "barrel_toast"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '690', 'true'),
  ('sensory_descriptor', 'rose', '장미', NULL, '{장미꽃잎,장미수}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["rose", "rose_petals", "rose_water"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '490', 'true'),
  ('sensory_descriptor', 'saline', '바닷바람', NULL, '{요오드,해초}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["saline", "seaweed", "iodine"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '990', 'true'),
  ('sensory_descriptor', 'savory', '고기·감칠맛', NULL, '{간장,고기,바베큐,바비큐,베이컨,세이보리,육수}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["meaty", "bacon", "savory", "soy_sauce", "broth", "barbecue"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1000', 'true'),
  ('sensory_descriptor', 'sherry', '셰리', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["sherry"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1070', 'true'),
  ('sensory_descriptor', 'silky_character', '실키한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2290', 'true'),
  ('sensory_descriptor', 'slim_texture', '슬림한 입안 느낌', NULL, '{}', NULL, '{texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2300', 'true'),
  ('sensory_descriptor', 'smoke', '스모키', NULL, '{"나무 연기",모닥불,숯·탄내,아스팔트,타르,"훈제 베이컨"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["bonfire", "smoke", "char", "smoked_bacon", "tar", "wood_smoke", "asphalt"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '940', 'true'),
  ('sensory_descriptor', 'smoke_peat', '연기·피트', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "pending", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2310', 'true'),
  ('sensory_descriptor', 'soft_texture', '부드러운 질감', NULL, '{"둥근 질감","매끄러운 질감","벨벳 같은 질감","새틴 같은 질감","섬세하고 정제된 질감","실키한 질감","폭신한 질감"}', NULL, '{finish,palate,texture}', '{"user_visible": true, "sensory_service": {"domain": "texture", "status": "representative", "version": "2.0.0", "source_keys": ["rounded_texture", "refined_texture", "silky_texture", "smooth_texture", "velvety_texture", "satin_texture", "pillowy_texture"], "category_key": "texture", "category_label_ko": "질감 및 여운", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1210', 'true'),
  ('sensory_descriptor', 'solvent', '용제', NULL, '{}', NULL, '{aroma,finish}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2320', 'true'),
  ('sensory_descriptor', 'spice', '향신료', NULL, '{감초,"검은 감초","베이킹 스파이스","붉은 고추",사프란,산초,아니스,올스파이스,육두구,"지중해 스파이스",칠리,카다멈,팔각}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["liquorice", "anise", "cardamom", "nutmeg", "sansho", "spice", "allspice", "black_liquorice", "baking_spice", "chilli", "saffron", "red_chilli", "mediterranean_spice", "star_anise"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1030', 'true'),
  ('sensory_descriptor', 'spicy_sensation', '자극 (스파이시)', NULL, '{"기포로 확정할 수 없는 따끔한 촉감","은근히 따뜻해지는 촉감","입안의 자극","화끈하게 타는 자극"}', NULL, '{finish,palate,texture}', '{"user_visible": true, "sensory_service": {"domain": "texture", "status": "representative", "version": "2.0.0", "source_keys": ["burning_sensation", "tactile_prickle", "warming_sensation", "tactile_stimulation"], "category_key": "texture", "category_label_ko": "질감 및 여운", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1260', 'true'),
  ('sensory_descriptor', 'stone_fruit', '복숭아·자두', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2330', 'true'),
  ('sensory_descriptor', 'strawberry', '딸기', NULL, '{"달콤한 딸기","신선한 딸기","야생 딸기","잘 익은 딸기"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["strawberry", "fresh_strawberry", "ripe_strawberry", "sweet_strawberry", "wild_strawberry"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '110', 'true'),
  ('sensory_descriptor', 'structuring_acidity', '구조를 잡는 산미', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2340', 'true'),
  ('sensory_descriptor', 'sulfurous', '유황', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2350', 'true'),
  ('sensory_descriptor', 'supple_texture', '유연한 질감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2360', 'true'),
  ('sensory_descriptor', 'sweet_aromatic', '달콤함', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2370', 'true'),
  ('sensory_descriptor', 'sweet_fresh_fruit', '달콤한 과일', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2380', 'true'),
  ('sensory_descriptor', 'sweet_potato', '고구마', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["sweet_potato"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '620', 'true'),
  ('sensory_descriptor', 'sweet_tart_character', '새콤달콤한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2390', 'true'),
  ('sensory_descriptor', 'sweetness_character', '단맛의 성격', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2400', 'true'),
  ('sensory_descriptor', 'tannin', '탄닌의 존재', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2410', 'true'),
  ('sensory_descriptor', 'tart_scent', '새콤한 아로마', NULL, '{}', NULL, '{aroma}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2420', 'true'),
  ('sensory_descriptor', 'tea', '차', NULL, '{벚꽃차,우롱차}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["cherry_blossom_tea", "tea", "oolong_tea"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '410', 'true'),
  ('sensory_descriptor', 'technical_note', '특이한 냄새', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2430', 'true'),
  ('sensory_descriptor', 'toast', '토스트', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["toast"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '700', 'true'),
  ('sensory_descriptor', 'toasted_character', '토스트한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2440', 'true'),
  ('sensory_descriptor', 'toasty_savory_character', '구수한 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2450', 'true'),
  ('sensory_descriptor', 'tobacco', '담배', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["tobacco"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1110', 'true'),
  ('sensory_descriptor', 'toffee', '토피', NULL, '{버터스카치}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["toffee", "butterscotch"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '660', 'true'),
  ('sensory_descriptor', 'tomato', '토마토', NULL, '{"토마토 페이스트"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["tomato", "tomato_paste"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '580', 'true'),
  ('sensory_descriptor', 'tongue_tip_bitterness', '혀끝에 남는 쌉싸름함', NULL, '{}', NULL, '{finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2460', 'true'),
  ('sensory_descriptor', 'toward_finish_emergence', '마무리로 갈수록 드러남', NULL, '{}', NULL, '{aroma,finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2470', 'true'),
  ('sensory_descriptor', 'tropical_fruit', '열대과일', NULL, '{구아바,"구아바 껍질",로즈애플,용과,잭프루트,타마린드,파파야,패션프루트}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["guava", "papaya", "passion_fruit", "rose_apple", "tamarind", "tropical_fruit", "guava_peel", "jackfruit", "dragon_fruit"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '140', 'true'),
  ('sensory_descriptor', 'ume', '매실', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["ume"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '80', 'true'),
  ('sensory_descriptor', 'unripe_fruit', '풋과일', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2480', 'true'),
  ('sensory_descriptor', 'vanilla', '바닐라', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["vanilla"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '770', 'true'),
  ('sensory_descriptor', 'vegetal', '채소', NULL, '{"녹색 채소",도라지,미나리,뿌리채소,"신선한 식물의 풍미",아스파라거스,완두,"익힌 채소",팥,"흰 아스파라거스"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["pea", "red_bean", "plant_note", "vegetal", "white_asparagus", "green_vegetable", "root_vegetable", "asparagus", "water_parsley", "balloonflower_root", "cooked_vegetal"], "category_key": "botanical", "category_label_ko": "꽃·허브·채소·잎", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '440', 'true'),
  ('sensory_descriptor', 'vodka_flavour', '보드카 풍미', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2490', 'true'),
  ('sensory_descriptor', 'walnut', '호두', NULL, '{"꿀에 절인 호두"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["walnut", "honeyed_walnut"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '840', 'true'),
  ('sensory_descriptor', 'warm_character', '따뜻한 풍미 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2500', 'true'),
  ('sensory_descriptor', 'watermelon', '수박', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["watermelon"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '240', 'true'),
  ('sensory_descriptor', 'wax', '왁스', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2510', 'true'),
  ('sensory_descriptor', 'waxy_texture', '왁시한 질감', NULL, '{}', NULL, '{finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "pending", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2520', 'true'),
  ('sensory_descriptor', 'wet_stone', '돌', NULL, '{"돌 같은 미네랄",부싯돌,슬레이트,"젖은 돌",흑연}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["flint", "wet_stone", "graphite", "slate", "stone_mineral"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '970', 'true'),
  ('sensory_descriptor', 'wheat', '밀', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["wheat"], "category_key": "bakery_sweets_nuts", "category_label_ko": "곡물·디저트·견과·로스팅", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '760', 'true'),
  ('sensory_descriptor', 'white_fruit', '흰 과일', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2530', 'true'),
  ('sensory_descriptor', 'wide_spread_character', '넓게 퍼지는 감각', NULL, '{}', NULL, '{aroma,finish,palate,texture}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2540', 'true'),
  ('sensory_descriptor', 'wild_character', '야생의', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2550', 'true'),
  ('sensory_descriptor', 'wild_fruit', '야생 열매', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2560', 'true'),
  ('sensory_descriptor', 'wilted_character', '시든 인상', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2570', 'true'),
  ('sensory_descriptor', 'wine_note', '와인', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2580', 'true'),
  ('sensory_descriptor', 'wood', '나무', NULL, '{백단향,삼나무,소나무,솔잎,송진,장작,향나무}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["pine", "cedar", "juniper_wood", "sandalwood", "pine_resin", "wood", "firewood", "pine_needle"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '930', 'true'),
  ('sensory_descriptor', 'wood_vanilla', '나무·바닐라', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "pending", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2590', 'true'),
  ('sensory_descriptor', 'yeast', '효모', NULL, '{"효모 앙금"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["yeast", "yeast_lees"], "category_key": "earthy_spices_savory", "category_label_ko": "나무·자연·향신료·기타", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '1050', 'true'),
  ('sensory_descriptor', 'yellow_fruit', '노란 과일', NULL, '{}', NULL, '{aroma,finish,palate}', '{"user_visible": false, "sensory_service": {"status": "hidden", "version": "2.0.0"}, "onboarding_selectable": false}', '4.0.0', '2600', 'true'),
  ('sensory_descriptor', 'yuzu', '유자', NULL, '{"유자 껍질"}', NULL, '{aroma,finish,palate}', '{"user_visible": true, "sensory_service": {"domain": "descriptor", "status": "representative", "version": "2.0.0", "source_keys": ["yuzu", "yuzu_peel"], "category_key": "fruit", "category_label_ko": "과일 계열", "is_representative": true}, "onboarding_selectable": true}', '4.0.0', '180', 'true'),
  ('style', 'american_whisky', '아메리칸 위스키', 'American whiskey', '{}', NULL, '{style}', '{"definition": "미국 위스키 중 버번·라이·테네시·특정 곡물 등 기존 계열로 설명되지 않는 제품. 원산지 확인을 요구하며 버번 요건을 추정하지 않는다.", "category_key": "whisky", "applies_to_categories": ["whisky"]}', '2.0.0', '340', 'true'),
  ('style', 'blended_malt_whisky', '블렌디드 몰트 위스키', 'Blended malt whisky', '{"blended malt","블렌디드 몰트"}', NULL, '{style}', '{"definition": "A blend explicitly identified as composed of malt whiskies from more than one distillery.", "category_key": "whisky", "applies_to_categories": ["whisky"]}', '2.0.0', '110', 'true'),
  ('style', 'blended_whisky', '블렌디드 위스키', 'Blended whisky', '{blended,블렌디드}', NULL, '{style}', '{"definition": "Whisky explicitly identified as a blend; component types are separate facets when known.", "category_key": "whisky", "applies_to_categories": ["whisky"]}', '2.0.0', '90', 'true'),
  ('style', 'bourbon', '버번', 'Bourbon', '{"bourbon whisky","버번 위스키"}', NULL, '{style}', '{"definition": "Whisky explicitly designated bourbon under applicable labeling rules.", "category_key": "whisky", "applies_to_categories": ["whisky"]}', '2.0.0', '100', 'true'),
  ('style', 'corn_whisky', '콘 위스키', 'Corn whisky', '{"corn whiskey","옥수수 위스키"}', NULL, '{style}', '{"definition": "Whisky explicitly identified as corn whisky under applicable labeling rules.", "category_key": "whisky", "applies_to_categories": ["whisky"]}', '2.0.0', '140', 'true'),
  ('style', 'daiginjo', '다이긴조', 'Daiginjo', '{daiginjo-shu,다이긴죠}', NULL, '{style}', '{"definition": "Sake explicitly labeled daiginjo under the applicable Japanese labeling standard.", "category_key": "sake", "definition_source": "Japan National Tax Agency specific designation sake overview", "source_standard_url": "https://www.nta.go.jp/about/organization/sapporo/release/r7/kanpyokai/03.htm", "applies_to_categories": ["sake"]}', '2.0.0', '170', 'true'),
  ('style', 'diluted_soju', '희석식 소주', 'Diluted soju', '{"희석 소주"}', NULL, '{style}', '{"definition": "Korean soju explicitly classified as diluted soju.", "category_key": "korean_traditional", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '270', 'true'),
  ('style', 'distilled_soju', '증류식 소주', 'Distilled soju', '{"전통 소주"}', NULL, '{style}', '{"definition": "Korean soju explicitly classified as distilled soju.", "category_key": "korean_traditional", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '260', 'true'),
  ('style', 'fortified_wine', '주정강화 와인', 'Fortified wine', '{"주정 강화","포티파이드 와인"}', NULL, '{style}', '{"definition": "Wine supported as fortified or liqueur wine by product evidence.", "category_key": "wine", "definition_source": "OIV International Code of Oenological Practices, liqueur wine and fortification", "source_standard_url": "https://www.oiv.int/standards/international-code-of-oenological-practices/part-i-definitions/special-wines", "applies_to_categories": ["wine"]}', '2.0.0', '50', 'true'),
  ('style', 'futsushu', '후쓰슈', 'Futsushu', '{"ordinary sake",보통주}', NULL, '{style}', '{"definition": "Sake explicitly identified as ordinary sake rather than a specific-designation sake.", "category_key": "sake", "applies_to_categories": ["sake"]}', '2.0.0', '210', 'true'),
  ('style', 'ginjo', '긴조', 'Ginjo', '{ginjo-shu,긴죠}', NULL, '{style}', '{"definition": "Sake explicitly labeled ginjo under the applicable Japanese labeling standard.", "category_key": "sake", "definition_source": "Japan National Tax Agency specific designation sake overview", "source_standard_url": "https://www.nta.go.jp/about/organization/sapporo/release/r7/kanpyokai/03.htm", "applies_to_categories": ["sake"]}', '2.0.0', '160', 'true'),
  ('style', 'grain_whisky', '그레인 위스키', 'Grain whisky', '{"blended grain","Blended grain whisky","single grain","Single grain whisky","블렌디드 그레인","블렌디드 그레인 위스키","싱글 그레인 위스키",싱글그레인}', NULL, '{style}', '{"definition": "싱글 그레인과 블렌디드 그레인의 서비스 대표 계열. 버번·라이·위트·콘은 곡물 원료라는 이유로 이 계열에 합치지 않는다.", "category_key": "whisky", "applies_to_categories": ["whisky"]}', '2.0.0', '80', 'true'),
  ('style', 'gwahaju', '과하주', 'Gwahaju', '{}', NULL, '{style}', '{"definition": "발효주에 증류주를 더하는 혼양 방식의 한국 과하주. 약주나 증류식 소주 단독 유형과 구분한다.", "category_key": "korean_traditional", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '320', 'true'),
  ('style', 'honjozo', '혼조조', 'Honjozo', '{honjozo-shu,"Tokubetsu honjozo","tokubetsu honjozo-shu","도쿠베츠 혼조조","특별 혼조조",혼죠조}', NULL, '{style}', '{"definition": "Sake explicitly labeled honjozo.", "category_key": "sake", "definition_source": "Japan National Tax Agency specific designation sake overview", "source_standard_url": "https://www.nta.go.jp/about/organization/sapporo/release/r7/kanpyokai/03.htm", "applies_to_categories": ["sake"]}', '2.0.0', '200', 'true'),
  ('style', 'junmai', '준마이', 'Junmai', '{junmai-shu,"Tokubetsu junmai","tokubetsu junmai-shu","도쿠베츠 준마이",준마이슈,"특별 준마이"}', NULL, '{style}', '{"definition": "Sake explicitly labeled junmai under the applicable Japanese labeling standard.", "category_key": "sake", "definition_source": "Japan National Tax Agency specific designation sake overview", "source_standard_url": "https://www.nta.go.jp/about/organization/sapporo/release/r7/kanpyokai/03.htm", "applies_to_categories": ["sake"]}', '2.0.0', '150', 'true'),
  ('style', 'junmai_daiginjo', '준마이 다이긴조', 'Junmai daiginjo', '{"junmai daiginjo-shu",준마이다이긴조}', NULL, '{style}', '{"definition": "Sake explicitly labeled junmai daiginjo.", "category_key": "sake", "definition_source": "Japan National Tax Agency specific designation sake overview", "source_standard_url": "https://www.nta.go.jp/about/organization/sapporo/release/r7/kanpyokai/03.htm", "applies_to_categories": ["sake"]}', '2.0.0', '190', 'true'),
  ('style', 'junmai_ginjo', '준마이 긴조', 'Junmai ginjo', '{"junmai ginjo-shu",준마이긴조}', NULL, '{style}', '{"definition": "Sake explicitly labeled junmai ginjo.", "category_key": "sake", "definition_source": "Japan National Tax Agency specific designation sake overview", "source_standard_url": "https://www.nta.go.jp/about/organization/sapporo/release/r7/kanpyokai/03.htm", "applies_to_categories": ["sake"]}', '2.0.0', '180', 'true'),
  ('style', 'korean_cheongju', '청주', 'Korean cheongju', '{"한국 청주"}', NULL, '{style}', '{"definition": "Korean traditional alcohol explicitly classified as cheongju.", "category_key": "korean_traditional", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '240', 'true'),
  ('style', 'korean_fruit_wine', '과실주', 'Korean fruit wine', '{"한국 과실주"}', NULL, '{style}', '{"definition": "Korean traditional product explicitly classified as fruit wine.", "category_key": "korean_traditional", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '250', 'true'),
  ('style', 'madeira_wine', '마데이라 와인', 'Madeira wine', '{"마데라 와인"}', NULL, '{style}', '{"definition": "마데이라의 주정강화 와인으로 확인된 제품군. 당도·품종·숙성 연수는 별도이며 마데이라통 숙성 상품은 포함하지 않는다.", "category_key": "wine", "definition_source": "Blandy''s Madeira wine portfolio", "source_standard_url": "https://blandys.com/en/wines-portfolio/", "applies_to_categories": ["wine"]}', '2.0.0', '300', 'true'),
  ('style', 'orange_wine', '오렌지 와인', 'Orange wine', '{"스킨 콘택트 화이트","앰버 와인"}', NULL, '{style}', '{"definition": "White-grape wine supported as made with extended pomace contact; color alone is insufficient.", "category_key": "wine", "definition_source": "OIV definition of white wine with maceration", "source_standard_url": "https://www.oiv.int/standards/international-code-of-oenological-practices/part-i-definitions/special-wines", "applies_to_categories": ["wine"]}', '2.0.0', '60', 'true'),
  ('style', 'port_wine', '포트 와인', 'Port wine', '{"Porto wine","포르투 와인"}', NULL, '{style}', '{"definition": "포르투갈 도루의 포트로 제품별 출처에서 확인된 주정강화 와인. 루비·토니·화이트 등의 차이와 당도는 별도이며 포트통 숙성 상품은 포함하지 않는다.", "category_key": "wine", "definition_source": "IVDP Port wine introduction", "source_standard_url": "https://www.ivdp.pt/en/wines/port-wines/introduction/", "applies_to_categories": ["wine"]}', '2.0.0', '280', 'true'),
  ('style', 'red_wine', '레드 와인', 'Red wine', '{red,레드}', NULL, '{style}', '{"definition": "Wine whose reviewed primary presentation is red wine.", "category_key": "wine", "applies_to_categories": ["wine"]}', '2.0.0', '10', 'true'),
  ('style', 'rose_wine', '로제 와인', 'Rosé wine', '{rose,rosé,로제}', NULL, '{style}', '{"definition": "Wine whose reviewed primary presentation is rosé wine.", "category_key": "wine", "applies_to_categories": ["wine"]}', '2.0.0', '30', 'true'),
  ('style', 'rye_whisky', '라이 위스키', 'Rye whisky', '{"rye whiskey",라이}', NULL, '{style}', '{"definition": "Whisky explicitly identified as rye whisky under applicable labeling rules.", "category_key": "whisky", "applies_to_categories": ["whisky"]}', '2.0.0', '120', 'true'),
  ('style', 'sherry_wine', '셰리 와인', 'Sherry wine', '{"Jerez wine","쉐리 와인"}', NULL, '{style}', '{"definition": "헤레스의 셰리로 제품별 출처에서 확인된 주정강화 와인. 피노·올로로소·PX 등의 차이는 별도이며 셰리통 숙성 증류주는 제외한다.", "category_key": "wine", "definition_source": "Consejo Regulador Jerez, Sherry wine families", "source_standard_url": "https://www.sherry.wine/sherry-wine/dry-sherry-wines/fino", "applies_to_categories": ["wine"]}', '2.0.0', '290', 'true'),
  ('style', 'single_malt_whisky', '싱글 몰트 위스키', 'Single malt whisky', '{"american single malt","American single malt whisky","single malt",싱글몰트,"아메리칸 싱글 몰트 위스키","아메리칸 싱글몰트"}', NULL, '{style}', '{"definition": "Whisky explicitly identified as single malt under its applicable jurisdiction or producer claim.", "category_key": "whisky", "applies_to_categories": ["whisky"]}', '2.0.0', '70', 'true'),
  ('style', 'single_pot_still_whisky', '싱글 팟 스틸 위스키', 'Single pot still whiskey', '{}', NULL, '{style}', '{"definition": "Single Pot Still로 식별된 단일 증류소의 몰트·비몰트 곡물 팟스틸 위스키. 싱글몰트로 바꾸지 않는다.", "category_key": "whisky", "applies_to_categories": ["whisky"]}', '2.0.0', '330', 'true'),
  ('style', 'sparkling_wine', '스파클링 와인', 'Sparkling wine', '{"발포성 와인",스파클링}', NULL, '{style}', '{"definition": "Wine supported as sparkling by product evidence; production method remains a separate facet.", "category_key": "wine", "definition_source": "OIV International Code of Oenological Practices, special wines", "source_standard_url": "https://www.oiv.int/standards/international-code-of-oenological-practices/part-i-definitions/special-wines", "applies_to_categories": ["wine"]}', '2.0.0', '40', 'true'),
  ('style', 'takju', '탁주', 'Takju', '{막걸리}', NULL, '{style}', '{"definition": "Korean traditional alcohol explicitly classified as takju.", "category_key": "korean_traditional", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '220', 'true'),
  ('style', 'tennessee_whisky', '테네시 위스키', 'Tennessee whiskey', '{"테네시 위스키 계열"}', NULL, '{style}', '{"definition": "제품별 제조사 설명에서 테네시 위스키로 확인된 제품군. 브랜드나 생산지만으로 분류하지 않고 명시된 라이·싱글몰트·블렌드는 각 제품 정체성을 따른다.", "category_key": "whisky", "definition_source": "Jack Daniel''s producer product definitions", "source_standard_url": "https://pressroom.jackdaniels.com/products/", "applies_to_categories": ["whisky"]}', '2.0.0', '310', 'true'),
  ('style', 'vermouth', '베르무트', 'Vermouth', '{}', NULL, '{style}', '{"definition": "제품별 자료에서 베르무트로 식별된 방향성 와인. 일반 화이트·레드·순수 증류주와 구별한다.", "category_key": "wine", "applies_to_categories": ["wine"]}', '2.0.0', '350', 'true'),
  ('style', 'wheat_whisky', '위트 위스키', 'Wheat whisky', '{"wheat whiskey","밀 위스키"}', NULL, '{style}', '{"definition": "Whisky explicitly identified as wheat whisky under applicable labeling rules.", "category_key": "whisky", "applies_to_categories": ["whisky"]}', '2.0.0', '130', 'true'),
  ('style', 'white_wine', '화이트 와인', 'White wine', '{white,화이트}', NULL, '{style}', '{"definition": "Wine whose reviewed primary presentation is white wine.", "category_key": "wine", "applies_to_categories": ["wine"]}', '2.0.0', '20', 'true'),
  ('style', 'yakju', '약주', 'Yakju', '{"한국 약주"}', NULL, '{style}', '{"definition": "Korean traditional alcohol explicitly classified as yakju.", "category_key": "korean_traditional", "applies_to_categories": ["korean_traditional"]}', '2.0.0', '230', 'true');

set constraints all immediate;
alter table public.catalog_taxonomy enable trigger catalog_taxonomy_assignment_validate;

insert into public.site_posts ("kind", "title", "body", "sort_order", "status") values
  ('faq', '기록을 수정하거나 삭제할 수 있나요?', '취향 탭에서 기록을 열고 오른쪽 위 ⋮를 눌러 주세요. 메모를 고치거나 기록을 지울 수 있어요.', '1', 'published'),
  ('faq', '찾는 술이 없거나 술 정보가 틀려요.', '문의하기로 술 이름을 알려 주세요.', '2', 'published'),
  ('faq', '다른 방법으로 로그인했더니 기록이 없어요.', '처음 기록을 남긴 로그인 방법으로 다시 들어와 주세요. 카카오, 구글, 애플은 계정이 따로 만들어져요.', '3', 'published'),
  ('faq', '탈퇴했는데 다시 쓰고 싶어요.', '탈퇴 후 30일 안에 다시 로그인하면 그대로 복구돼요.', '4', 'published');
