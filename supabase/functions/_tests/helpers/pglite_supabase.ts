import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { pg_trgm } from "npm:@electric-sql/pglite@0.3.14/contrib/pg_trgm";

// A PGlite database that mimics a fresh Supabase project (client roles,
// auth/storage/cron stubs and the permissive default privileges) with every
// migration applied. Shared by the DB tests.

const MIGRATIONS_DIR = "supabase/migrations";

export const SUPABASE_LIKE_PRELUDE = `
create schema extensions;
create extension pg_trgm with schema extensions;
create function extensions.digest(input text, algorithm text) returns bytea
  language sql immutable as $$ select sha256(convert_to(input, 'UTF8')) $$;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
alter default privileges for role postgres in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on sequences to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on functions to anon, authenticated, service_role;
create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_app_meta_data jsonb not null default '{}'::jsonb,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  last_sign_in_at timestamptz
);
create table auth.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  ip inet,
  user_agent text
);
create function auth.uid() returns uuid language sql stable as $$
  select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
$$;
create schema storage;
create table storage.buckets (
  id text primary key, name text, public boolean,
  file_size_limit bigint, allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null,
  name text not null,
  created_at timestamptz not null default now()
);
alter table storage.objects enable row level security;
grant usage on schema auth, storage to anon, authenticated, service_role;
grant all on storage.objects to anon, authenticated, service_role;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;
create schema cron;
create table cron.job (jobname text primary key, schedule text not null, command text not null);
create function cron.unschedule(job_name text) returns boolean
  language sql as $$ delete from cron.job where jobname = job_name returning true $$;
create function cron.schedule(job_name text, schedule text, command text) returns bigint
  language sql as $$
  insert into cron.job values (job_name, schedule, command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command
  returning 1::bigint
$$;
`;

export async function createSupabaseLikeDatabase(): Promise<PGlite> {
  const db = new PGlite({ extensions: { pg_trgm } });
  await db.exec(SUPABASE_LIKE_PRELUDE);
  await applyMigrations(db);
  return db;
}

export async function applyMigrations(db: PGlite) {
  const files = [...Deno.readDirSync(MIGRATIONS_DIR)]
    .filter((entry) => entry.isFile && entry.name.endsWith(".sql"))
    .map((entry) => entry.name)
    .sort();
  for (const file of files) {
    const sql = await Deno.readTextFile(`${MIGRATIONS_DIR}/${file}`);
    // Extensions are provided by the prelude or are not needed to apply DDL.
    await db.exec(sql.replace(/^create extension .*$/gm, ""));
  }
  await db.exec("reset search_path; set row_security = on;");
}
