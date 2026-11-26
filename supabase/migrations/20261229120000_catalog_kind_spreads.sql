-- The card engine reads how many published bottles of each kind sit on each
-- level and carry each grape, place and method. Those counts were a file
-- built by hand and shipped inside the functions, so they aged: places the
-- dictionary came to tell apart were counted as carried by no bottle. The
-- counts now live here, replaced every night by a job that counts the
-- catalog with the engine's own reading, and the functions read this row
-- (the shipped file stays as what they start with).
--
-- The night job runs outside the database (the count takes longer than a
-- function may compute) and holds one secret that lets it do two things
-- only: read the published bottles' facts, and replace this row.

create table public.catalog_kind_spreads (
  id boolean primary key default true check (id),
  spreads jsonb not null
    check (jsonb_typeof(spreads) = 'object' and jsonb_typeof(spreads -> 'kinds') = 'object'),
  bottles integer not null check (bottles > 0),
  counted_at timestamptz not null default now()
);

comment on table public.catalog_kind_spreads is
  'One row: what the published catalog holds, counted by kind of drink (levels, ABV spread, grapes, places, methods). Replaced every night; read by the card and fit functions.';

alter table public.catalog_kind_spreads enable row level security;
revoke all on table public.catalog_kind_spreads from public, anon, authenticated;
grant all on table public.catalog_kind_spreads to service_role;

-- The night job's secret is kept in the vault under this name.
create function public.soolgyul_require_kind_spreads_job(job_secret text)
returns void
language plpgsql stable security definer
set search_path to ''
as $$
declare expected text;
begin
  select decrypted_secret into expected from vault.decrypted_secrets
  where name = 'kind_spreads_job_secret';
  if expected is null or job_secret is null or job_secret <> expected then
    raise exception using errcode = 'P0001', message = 'kind_spreads_job_refused';
  end if;
end;
$$;
revoke all on function public.soolgyul_require_kind_spreads_job(text)
  from public, anon, authenticated;

-- A page of the published bottles as the count reads them, in id order.
-- One json value a page, so the API's row cap does not cut it.
create function public.soolgyul_kind_spreads_bottles(
  job_secret text,
  after_id uuid default null,
  page_size integer default 2000
)
returns jsonb
language plpgsql stable security definer
set search_path to ''
as $$
begin
  perform public.soolgyul_require_kind_spreads_job(job_secret);
  if page_size is null or page_size < 1 or page_size > 5000 then
    raise exception using errcode = '22023', message = 'page_size_invalid';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(page) order by page.id)
    from (
      select
        item.id, item.style_key, category.category_key, item.abv_percent,
        item.name_ko, item.region_key,
        item.grape_variety_keys as grapes,
        item.production_process_keys as processes,
        item.ingredient_keys as ingredients,
        profile.sweetness, profile.acidity, profile.bitterness,
        profile.astringency, profile.body, profile.carbonation,
        profile.finish_length, profile.finish_character,
        profile.aroma_intensity, profile.aroma_tags
      from public.alcohol_items item
      join public.alcohol_categories category
        on category.id = item.alcohol_category_id
      left join public.alcohol_tasting_profiles profile
        on profile.alcohol_item_id = item.id
      where item.publish_status = 'published'
        and (after_id is null or item.id > after_id)
      order by item.id
      limit page_size
    ) page
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.soolgyul_kind_spreads_bottles(text, uuid, integer)
  from public, authenticated;
grant execute on function public.soolgyul_kind_spreads_bottles(text, uuid, integer)
  to anon, service_role;

-- Replaces the count. A count of fewer than half the bottles of the one it
-- replaces is a read that went wrong, and is refused.
create function public.soolgyul_store_kind_spreads(job_secret text, new_spreads jsonb)
returns void
language plpgsql security definer
set search_path to ''
as $$
declare
  counted integer;
  held integer;
begin
  perform public.soolgyul_require_kind_spreads_job(job_secret);
  if jsonb_typeof(new_spreads) is distinct from 'object'
    or jsonb_typeof(new_spreads -> 'kinds') is distinct from 'object'
    or new_spreads -> 'kinds' = '{}'::jsonb
    or jsonb_typeof(new_spreads -> 'bottles') is distinct from 'number'
  then
    raise exception using errcode = '22023', message = 'kind_spreads_invalid';
  end if;
  counted := (new_spreads ->> 'bottles')::integer;
  select bottles into held from public.catalog_kind_spreads;
  if counted < 1 or (held is not null and counted * 2 < held) then
    raise exception using errcode = 'P0001', message = 'kind_spreads_too_few_bottles';
  end if;
  insert into public.catalog_kind_spreads (id, spreads, bottles, counted_at)
  values (true, new_spreads, counted, now())
  on conflict (id) do update
    set spreads = excluded.spreads, bottles = excluded.bottles,
        counted_at = excluded.counted_at;
end;
$$;
revoke all on function public.soolgyul_store_kind_spreads(text, jsonb)
  from public, authenticated;
grant execute on function public.soolgyul_store_kind_spreads(text, jsonb)
  to anon, service_role;
