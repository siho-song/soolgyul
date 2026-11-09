-- Notices and FAQ answers on soolgyul.com were hand-written HTML. They move
-- to one table the admin console writes and the site reads, so a notice goes
-- out without a deploy. The terms and the privacy policy stay in the
-- repository: their history must be kept and their pages must load without
-- the database.

create table public.site_posts (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('notice', 'faq')),
  title text not null check (btrim(title) <> ''),
  body text not null default '',
  sort_order integer not null default 0,
  status text not null default 'draft'
    check (status in ('draft', 'published', 'withdrawn')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status <> 'published' or published_at is not null)
);

comment on table public.site_posts is
  'Notices and FAQ answers shown on soolgyul.com. Notices read newest published first, FAQ answers by sort_order.';

create index site_posts_kind_idx on public.site_posts (kind, status, sort_order, published_at desc);

-- Same stamps as a post: published_at on the first publish, updated_at on
-- every write.
create trigger site_posts_prepare_admin_write
  before insert or update on public.site_posts
  for each row execute function public.soolgyul_prepare_admin_editorial_article();
create trigger site_posts_touch_updated_at
  before update on public.site_posts
  for each row execute function public.soolgyul_touch_editorial_updated_at();

alter table public.site_posts enable row level security;

-- Anyone reads what is published; administrators read everything. Editors
-- write drafts only, admins publish and delete.
create policy site_posts_anon_select on public.site_posts
  for select to anon
  using (status = 'published');
create policy site_posts_authenticated_select on public.site_posts
  for select to authenticated
  using (status = 'published' or public.soolgyul_admin_has_role());
create policy site_posts_admin_insert on public.site_posts
  for insert to authenticated
  with check (
    public.soolgyul_admin_has_role(array['admin'])
    or (public.soolgyul_admin_has_role(array['editor']) and status = 'draft')
  );
create policy site_posts_admin_update on public.site_posts
  for update to authenticated
  using (
    public.soolgyul_admin_has_role(array['admin'])
    or (public.soolgyul_admin_has_role(array['editor']) and status = 'draft')
  )
  with check (
    public.soolgyul_admin_has_role(array['admin'])
    or (public.soolgyul_admin_has_role(array['editor']) and status = 'draft')
  );
create policy site_posts_admin_delete on public.site_posts
  for delete to authenticated
  using (public.soolgyul_admin_has_role(array['admin']));

grant select on public.site_posts to anon;
grant select, insert, update, delete on public.site_posts to authenticated;

-- The FAQ answers the site carried until now.
insert into public.site_posts (kind, title, body, sort_order, status) values
  ('faq', '기록을 수정하거나 삭제할 수 있나요?',
   '취향 탭에서 기록을 열고 오른쪽 위 ⋮를 눌러 주세요. 메모를 고치거나 기록을 지울 수 있어요.', 1, 'published'),
  ('faq', '찾는 술이 없거나 술 정보가 틀려요.',
   '문의하기로 술 이름을 알려 주세요.', 2, 'published'),
  ('faq', '다른 방법으로 로그인했더니 기록이 없어요.',
   '처음 기록을 남긴 로그인 방법으로 다시 들어와 주세요. 카카오, 구글, 애플은 계정이 따로 만들어져요.', 3, 'published'),
  ('faq', '탈퇴했는데 다시 쓰고 싶어요.',
   '탈퇴 후 30일 안에 다시 로그인하면 그대로 복구돼요.', 4, 'published');
