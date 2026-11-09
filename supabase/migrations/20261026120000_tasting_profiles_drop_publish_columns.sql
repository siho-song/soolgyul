-- alcohol_tasting_profiles carried its own publish_status/published_at, but every
-- reader (card engine, recommendation scan, questionnaire context RPC) gates on
-- alcohol_items.publish_status and loads the profile by item id. 57,776 published
-- items had a 'staging' profile row, so the column only misled. Decided 2026-10-26:
-- the item's status is the single publish gate; the profile columns go away.
alter table public.alcohol_tasting_profiles
  drop column if exists publish_status,
  drop column if exists published_at;
