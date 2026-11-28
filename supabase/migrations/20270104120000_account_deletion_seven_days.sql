-- A deleted account can be brought back by signing in again for 7 days, not
-- 30: the shorter wait is the product's decision. Everything that asks
-- whether an account is still restorable or due for its purge reads this
-- function at that moment, so an account already waiting is held to 7 days
-- from its own request too. The FAQ answer says the same, under the
-- feature's new name (계정 삭제).
set local lock_timeout = '5s';

create or replace function public.soolgyul_deletion_due_at(requested_at timestamp with time zone)
 returns timestamp with time zone
 language sql
 stable
 set search_path to ''
as $function$
  select requested_at + interval '7 days';
$function$;

update public.site_posts
   set title = '계정을 삭제했는데 다시 쓰고 싶어요.',
       body = '삭제를 요청한 뒤 7일 안에 다시 로그인하면 그대로 복구돼요.'
 where kind = 'faq'
   and title = '탈퇴했는데 다시 쓰고 싶어요.';
