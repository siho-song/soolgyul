-- Sign-in records (when, from which IP address) are kept three months, the
-- period the Protection of Communications Secrets Act asks of an internet
-- service, then deleted. Supabase Auth writes them to auth.audit_log_entries
-- once "write audit logs to the database" is on in the project's Auth
-- settings; this job is the other half and removes what is older.

select cron.schedule('soolgyul-sign-in-records-retention', '10 18 * * *',
  $$delete from auth.audit_log_entries where created_at < now() - interval '3 months'$$);
