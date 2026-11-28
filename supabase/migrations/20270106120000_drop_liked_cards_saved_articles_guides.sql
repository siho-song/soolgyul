-- The app no longer has 좋아요한 카드, 저장한 글 or the home's 다음 한 잔
-- 가이드, so nothing reads these: the two owner functions and the two tables
-- go, and the rows the tables held with them. No other function, policy,
-- trigger or view reads them, and no table points at them.
set local lock_timeout = '5s';

drop function if exists public.soolgyul_my_recent_card_guides(integer);
drop function if exists public.soolgyul_my_liked_cards(text, boolean, integer, integer);

drop table if exists public.user_liked_drink_cards;
drop table if exists public.user_saved_articles;
