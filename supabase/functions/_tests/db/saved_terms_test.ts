import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { asRole, asUser, refusal } from "../helpers/db_session.ts";
import { same } from "../helpers/assert.ts";

// 나의 용어 사전: the saved-terms function keeps a member's terms by their
// dictionary key with the service role. No client touches the table, a key
// that is not shaped like one is refused, and the rows leave with the account.

const OWNER = "a0000000-0000-4000-8000-000000000081";

Deno.test("saved terms are kept by key, closed to clients, and leave with the account", async () => {
  const db = await createSupabaseLikeDatabase();
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${OWNER}', 'owner@example.test', '{"provider":"kakao"}', now());
    insert into public.user_saved_terms (user_id, term_key) values
      ('${OWNER}', 'aroma:cherry'), ('${OWNER}', 'maturation:sherry_cask');
  `);
  const count = async () =>
    (await db.query<{ n: number }>(
      "select count(*)::int as n from public.user_saved_terms",
    )).rows[0].n;
  same(await count(), 2);

  for (const key of ["cherry", "Aroma:cherry", "aroma:", "aroma:che rry"]) {
    const refused = await refusal(() =>
      db.query(
        "insert into public.user_saved_terms (user_id, term_key) values ($1, $2)",
        [OWNER, key],
      )
    );
    same(refused?.includes("user_saved_terms_term_key_check"), true, key);
  }

  for (
    const work of [
      () => db.query("select * from public.user_saved_terms"),
      () =>
        db.query(
          "insert into public.user_saved_terms (user_id, term_key) values ($1, 'aroma:plum')",
          [OWNER],
        ),
      () => db.query("delete from public.user_saved_terms"),
    ]
  ) {
    same(
      (await refusal(() => asUser(db, OWNER, work)))?.includes("denied"),
      true,
    );
    same(
      (await refusal(() => asRole(db, "anon", null, work)))?.includes("denied"),
      true,
    );
  }

  await db.query("delete from public.users where id = $1", [OWNER]);
  same(await count(), 0);
});
