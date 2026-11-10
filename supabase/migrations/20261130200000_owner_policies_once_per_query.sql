-- The owner policies asked "who is signed in" and "is the account active"
-- again for every row they checked. Both answers are the same for the whole
-- query, so each policy now asks once (a scalar subquery the planner runs a
-- single time). The rule each policy enforces is unchanged: a row is the
-- caller's own and the caller's account is active.
-- Three foreign keys had no index on the referencing side, so removing a
-- product, a record or an anonymous card scanned the whole referencing table.
set local lock_timeout = '5s';

alter policy users_owner_select on public.users using (
  id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
);

alter policy user_consents_owner_select on public.user_consents using (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
);

alter policy user_drink_interests_owner_select on public.user_drink_interests using (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
);

alter policy admin_user_roles_owner_select on public.admin_user_roles using (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
);

alter policy support_inquiries_owner_read on public.support_inquiries using (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
);

alter policy taste_letters_owner_select on public.taste_letters using (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
);

alter policy taste_letter_changes_owner_select on public.taste_letter_changes using (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
);

alter policy drink_records_owner_select on public.drink_records using (
  user_id = (select auth.uid())
  and deleted_at is null
  and (select public.soolgyul_account_active((select auth.uid())))
);

alter policy drink_result_summaries_owner_select on public.taste_cards using (
  (select public.soolgyul_account_active((select auth.uid())))
  and exists (
    select 1
    from public.drink_records r
    where r.id = taste_cards.drink_record_id
      and r.user_id = (select auth.uid())
      and r.deleted_at is null
  )
);

alter policy drink_record_answers_owner_select on public.drink_record_answers using (
  (select public.soolgyul_account_active((select auth.uid())))
  and exists (
    select 1
    from public.drink_records r
    where r.id = drink_record_answers.drink_record_id
      and r.user_id = (select auth.uid())
      and r.deleted_at is null
  )
);

alter policy user_liked_drink_cards_owner_select on public.user_liked_drink_cards using (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
  and exists (
    select 1
    from public.drink_records record_row
    where record_row.id = user_liked_drink_cards.drink_record_id
      and record_row.user_id = user_liked_drink_cards.user_id
      and record_row.deleted_at is null
  )
);

alter policy user_liked_drink_cards_owner_insert on public.user_liked_drink_cards with check (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
  and exists (
    select 1
    from public.drink_records record_row
    where record_row.id = user_liked_drink_cards.drink_record_id
      and record_row.user_id = user_liked_drink_cards.user_id
      and record_row.deleted_at is null
  )
);

alter policy user_liked_drink_cards_owner_delete on public.user_liked_drink_cards using (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
);

alter policy user_saved_articles_owner_select on public.user_saved_articles using (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
  and exists (
    select 1
    from public.editorial_articles article
    where article.id = user_saved_articles.article_id
      and article.status = 'published'
      and article.published_at is not null
      and article.published_at <= now()
  )
);

alter policy user_saved_articles_owner_delete on public.user_saved_articles using (
  user_id = (select auth.uid())
  and (select public.soolgyul_account_active((select auth.uid())))
);

create index drink_records_alcohol_item_idx
  on public.drink_records (alcohol_item_id);
create index taste_letter_changes_record_idx
  on public.taste_letter_changes (drink_record_id);
create index taste_card_generation_attempts_claim_snapshot_idx
  on public.taste_card_generation_attempts (claim_snapshot_id)
  where claim_snapshot_id is not null;
