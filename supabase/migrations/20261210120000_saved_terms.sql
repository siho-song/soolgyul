-- 나의 용어 사전: a member saves the explanation of a term from its help
-- balloon to read again from the profile. Only the dictionary's key of the
-- term is kept (aroma:cherry); the name and the explanation are read from the
-- dictionary when the list is served. The dictionary is not in the database,
-- so the saved-terms function checks the key and writes with the service
-- role; no client reads or writes the table.
set local lock_timeout = '5s';

create table public.user_saved_terms (
  user_id uuid not null references public.users (id) on delete cascade,
  term_key text not null,
  created_at timestamp with time zone not null default now(),
  constraint user_saved_terms_pkey primary key (user_id, term_key),
  constraint user_saved_terms_term_key_check
    check (term_key ~ '^[a-z][a-z_]*:[a-z0-9][a-z0-9_]*$' and length(term_key) <= 120)
);

comment on table public.user_saved_terms is
  'Private owner-only list of dictionary terms a member saved from a help balloon, by dictionary key.';

alter table public.user_saved_terms enable row level security;

revoke all on table public.user_saved_terms from public, anon, authenticated;
grant all on table public.user_saved_terms to service_role;
