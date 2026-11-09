-- 나의 술결 네 글자. Each saved card gives one vote per axis (향 F/R, 단맛 D/S,
-- 무게 L/H, 여운 C/P); the server replays an account's cards and stores the
-- four letters with their shares, plus every moment a letter first appeared
-- or flipped (the account's 변천사). Rules live in taste_letters.ts; these
-- rows are a cache of that replay, replaced whole on every card so a deleted
-- record drops out of both tables.

create table public.taste_letters (
  user_id uuid primary key references public.users(id) on delete cascade,
  rule_version text not null,
  record_count integer not null check (record_count >= 0),
  axes jsonb not null check (jsonb_typeof(axes) = 'object'),
  updated_at timestamptz not null default now()
);
comment on table public.taste_letters is
  'One row per account: the four taste letters, each with its share and vote count, replayed from the saved cards.';

create table public.taste_letter_changes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  drink_record_id uuid not null references public.drink_records(id) on delete cascade,
  axis text not null check (axis in ('aroma', 'sweetness', 'weight', 'finish')),
  from_letter text check (from_letter is null or char_length(from_letter) = 1),
  to_letter text not null check (char_length(to_letter) = 1),
  left_share integer not null check (left_share between 0 and 100),
  right_share integer not null check (right_share between 0 and 100),
  product_name text not null,
  changed_at timestamptz not null,
  rule_version text not null,
  unique (user_id, drink_record_id, axis)
);
comment on table public.taste_letter_changes is
  'The moments a taste letter first appeared (from_letter null) or flipped, with the record that tipped it.';
create index taste_letter_changes_user_idx
  on public.taste_letter_changes (user_id, changed_at);

alter table public.taste_letters enable row level security;
alter table public.taste_letter_changes enable row level security;
create policy taste_letters_owner_select on public.taste_letters
  for select to authenticated
  using (user_id = auth.uid() and public.soolgyul_account_active(user_id));
create policy taste_letter_changes_owner_select on public.taste_letter_changes
  for select to authenticated
  using (user_id = auth.uid() and public.soolgyul_account_active(user_id));
grant select on table public.taste_letters to authenticated;
grant select on table public.taste_letter_changes to authenticated;
grant all on table public.taste_letters to service_role;
grant all on table public.taste_letter_changes to service_role;

create or replace function public.soolgyul_save_taste_letters(
  target_user_id uuid,
  state jsonb,
  changes jsonb
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
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
revoke execute on function public.soolgyul_save_taste_letters(uuid, jsonb, jsonb) from public;
revoke execute on function public.soolgyul_save_taste_letters(uuid, jsonb, jsonb) from anon, authenticated;
grant execute on function public.soolgyul_save_taste_letters(uuid, jsonb, jsonb) to service_role;
