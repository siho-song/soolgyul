-- The bottom menu has four tabs now and the calendar of records is the 기록
-- tab (it was 취향), so the FAQ answer that sends the reader there names it.
update public.site_posts
   set body = '기록 탭에서 기록을 열고 오른쪽 위 ⋮를 눌러 주세요. 메모를 고치거나 기록을 지울 수 있어요.'
 where kind = 'faq'
   and title = '기록을 수정하거나 삭제할 수 있나요?';
