-- When a screen stalled, nothing recorded which statement had been slow;
-- only running totals existed. A statement that takes over a second is now
-- written to the Postgres log, for the app's requests (authenticator) and
-- for scheduled jobs and maintenance (postgres). The roles exist on a
-- Supabase project only, so a plain Postgres is left as it is.
do $$
declare
  role_name text;
begin
  foreach role_name in array array['authenticator', 'postgres'] loop
    if exists (select 1 from pg_catalog.pg_roles where rolname = role_name) then
      execute format(
        'alter role %I set log_min_duration_statement = %L', role_name, '1s'
      );
    end if;
  end loop;
end
$$;
