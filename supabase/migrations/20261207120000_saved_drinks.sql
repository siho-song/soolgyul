-- 저장한 술: a member keeps a bottle from the fit page to come back to. The
-- badge the fit page showed at that moment is kept beside it, so the verdicts
-- can later be checked against what the member answered when they recorded
-- the same bottle (drink_records.alcohol_item_id). The list is the owner's
-- alone: no counts, no ranking.
set local lock_timeout = '5s';

create table public.user_saved_drinks (
  user_id uuid not null references public.users (id) on delete cascade,
  alcohol_item_id uuid not null references public.alcohol_items (id) on delete cascade,
  -- Null when the bottle was saved before a verdict came, or by a member
  -- without a card to judge by.
  fit_badge text,
  created_at timestamp with time zone not null default now(),
  constraint user_saved_drinks_pkey primary key (user_id, alcohol_item_id),
  constraint user_saved_drinks_fit_badge_check
    check (fit_badge in ('star', 'caution', 'neutral', 'no_info'))
);

comment on table public.user_saved_drinks is
  'Private owner-only list of catalog bottles a member saved from the fit page, with the badge shown then.';

create index user_saved_drinks_item_idx on public.user_saved_drinks (alcohol_item_id);

alter table public.user_saved_drinks enable row level security;

-- The owner reads the rows (the heart's state, the count on the profile);
-- writes go through the two functions below, which check the bottle.
create policy user_saved_drinks_owner_select on public.user_saved_drinks
  for select to authenticated
  using (
    user_id = (select auth.uid())
    and (select public.soolgyul_account_active((select auth.uid())))
  );

revoke all on table public.user_saved_drinks from public, anon, authenticated;
grant select on table public.user_saved_drinks to authenticated;
grant all on table public.user_saved_drinks to service_role;

create function public.soolgyul_save_my_drink(
  p_alcohol_item_id uuid,
  p_fit_badge text default null
) returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_user_id uuid := auth.uid();
begin
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if not public.soolgyul_my_account_ready() then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;
  if p_fit_badge is not null
     and p_fit_badge not in ('star', 'caution', 'neutral', 'no_info') then
    raise exception using errcode = '22023', message = 'fit_badge_invalid';
  end if;
  if not exists (
    select 1
    from public.alcohol_items item
    where item.id = p_alcohol_item_id
      and item.publish_status = 'published'
  ) then
    raise exception using errcode = 'P0002', message = 'drink_not_found';
  end if;

  -- Saving again keeps the first day and the badge shown then.
  insert into public.user_saved_drinks (user_id, alcohol_item_id, fit_badge)
  values (target_user_id, p_alcohol_item_id, p_fit_badge)
  on conflict (user_id, alcohol_item_id) do nothing;
end
$function$;

create function public.soolgyul_unsave_my_drink(p_alcohol_item_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_user_id uuid := auth.uid();
begin
  if target_user_id is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if not public.soolgyul_account_active(target_user_id) then
    raise exception using errcode = '42501', message = 'active_account_required';
  end if;

  -- Taking out a bottle that is not there is no error.
  delete from public.user_saved_drinks
  where user_id = target_user_id and alcohol_item_id = p_alcohol_item_id;
end
$function$;

-- One page of the owner's saved bottles, newest first, each as a search
-- result row so the app shows it like one.
create function public.soolgyul_my_saved_drinks(
  p_offset integer default 0,
  p_limit integer default 30
) returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  with saved as (
    select
      kept.alcohol_item_id,
      kept.created_at as saved_at,
      item.name_ko,
      item.name_en,
      item.style_key,
      item.region_key,
      item.abv_percent,
      item.country_code,
      item.alcohol_category_id
    from public.user_saved_drinks kept
    join public.alcohol_items item
      on item.id = kept.alcohol_item_id
      and item.publish_status = 'published'
    where kept.user_id = auth.uid()
      and public.soolgyul_account_active(auth.uid())
  ),
  page as (
    select saved.*
    from saved
    order by saved.saved_at desc, saved.alcohol_item_id desc
    offset greatest(coalesce(p_offset, 0), 0)
    limit least(greatest(coalesce(p_limit, 30), 0), 50)
  )
  select jsonb_build_object(
    'total', (select count(*) from saved),
    'drinks', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', page.alcohol_item_id::text,
          'saved_at', page.saved_at,
          'name_ko', page.name_ko,
          'name_en', page.name_en,
          'category_key', category.category_key,
          'style_key', page.style_key,
          'style_label', coalesce(style_term.label_ko, category.name_ko),
          'abv_percent', page.abv_percent,
          'media_path', (
            select media.media_path
            from public.catalog_media_assets media
            where media.alcohol_item_id = page.alcohol_item_id
              and media.publish_status = 'published'
              and media.published_at is not null
          ),
          'country_code', page.country_code,
          'region', region_term.label_ko
        )
        order by page.saved_at desc, page.alcohol_item_id desc
      )
      from page
      join public.alcohol_categories category
        on category.id = page.alcohol_category_id
      left join public.catalog_taxonomy style_term
        on style_term.term_type = 'style'
        and style_term.term_key = page.style_key
        and style_term.is_active
      left join public.catalog_taxonomy region_term
        on region_term.term_type = 'region'
        and region_term.term_key = page.region_key
    ), '[]'::jsonb)
  );
$function$;

revoke all on function public.soolgyul_save_my_drink(uuid, text) from public, anon;
revoke all on function public.soolgyul_unsave_my_drink(uuid) from public, anon;
revoke all on function public.soolgyul_my_saved_drinks(integer, integer) from public, anon;
grant execute on function public.soolgyul_save_my_drink(uuid, text) to authenticated, service_role;
grant execute on function public.soolgyul_unsave_my_drink(uuid) to authenticated, service_role;
grant execute on function public.soolgyul_my_saved_drinks(integer, integer) to authenticated, service_role;
