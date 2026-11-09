-- Card-news posts tell their story on the photos and in the summary, so the
-- body may be empty. The admin editor no longer requires it.
alter table public.editorial_articles
  drop constraint if exists editorial_articles_body_check,
  drop constraint if exists editorial_articles_body_markdown_check;
