-- Cards made without an account are kept thirty days, yet the job that
-- removes them ran every five minutes and read every record to find them.
-- It now runs hourly and finds them through an index. The scheduler's own
-- run log was never trimmed; it now keeps two weeks.
set local lock_timeout = '5s';

create index drink_records_anonymous_created_idx
  on public.drink_records (created_at)
  where user_id is null and anonymous_session_id is not null;
create index taste_card_generation_attempts_anonymous_created_idx
  on public.taste_card_generation_attempts (created_at)
  where anonymous_session_digest is not null;

select cron.schedule('soolgyul-anonymous-retention', '20 * * * *',
  'select public.soolgyul_purge_expired_anonymous_taste_cards();');
select cron.schedule('soolgyul-job-run-log-retention', '40 18 * * *',
  $job$delete from cron.job_run_details where end_time < now() - interval '14 days'$job$);
