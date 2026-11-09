-- Idempotency is enforced per principal on taste_card_generation_attempts,
-- whose reserved record id is the drink_records primary key. The global
-- unique index on drink_records.idempotency_key made an anonymous card and a
-- later signed-in retry with the same client key fail with 23505.
drop index if exists public.drink_records_idempotency_key_uidx;
