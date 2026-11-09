import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "./helpers/pglite_supabase.ts";

// A reader deletes a saved record from its card. The card server calls one
// service RPC that marks only the owner's live record deleted; clients
// cannot call it.

const OWNER = "a0000000-0000-4000-8000-000000000041";
const STRANGER = "a0000000-0000-4000-8000-000000000042";
const CATEGORY = "c0000000-0000-4000-8000-000000000001";
const ITEM = "b0000000-0000-4000-8000-000000000001";
const RECORD = "d0000000-0000-4000-8000-000000000041";
const CARD = "e0000000-0000-4000-8000-000000000041";
const SNAPSHOT_REF = "c".repeat(64);

async function seed(db: PGlite) {
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${OWNER}', 'owner@example.test', '{"provider":"kakao"}', now()),
      ('${STRANGER}', 'stranger@example.test', '{"provider":"kakao"}', now());
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('${CATEGORY}', 'wine', '와인', 1);
    insert into public.alcohol_items (id, name_ko, alcohol_category_id, publish_status, published_at)
      values ('${ITEM}', '테스트 술', '${CATEGORY}', 'published', now());
    insert into public.drink_records (id, user_id, alcohol_item_id, questionnaire_version)
      values ('${RECORD}', '${OWNER}', '${ITEM}', 'sensory-questionnaire-v1');
    insert into public.taste_cards (id, drink_record_id, snapshot_id, snapshot_ref, lifecycle,
        canonical_schema_version, semantic_snapshot, rendered_snapshot)
      values ('${CARD}', '${RECORD}', gen_random_uuid(), '${SNAPSHOT_REF}', 'final',
        'test', '{}'::jsonb, '{}'::jsonb);
  `);
}

function deleteRecord(db: PGlite, user: string) {
  return db.query<{ id: string }>(
    "select public.soolgyul_delete_owned_drink_record($1, $2) as id",
    [CARD, user],
  );
}

async function deletedAt(db: PGlite) {
  const { rows } = await db.query<{ deleted_at: string | null }>(
    "select deleted_at from public.drink_records where id = $1",
    [RECORD],
  );
  return rows[0].deleted_at;
}

async function failsWith(work: () => Promise<unknown>, message: string) {
  try {
    await work();
  } catch (error) {
    if (String(error).includes(message)) return;
    throw new Error(`expected ${message}, got ${String(error)}`);
  }
  throw new Error(`expected ${message}, but the call succeeded`);
}

Deno.test("deleting a saved record", async (t) => {
  const db = await createSupabaseLikeDatabase();
  await seed(db);

  await t.step("a signed-in client cannot call the delete RPC", async () => {
    await db.exec("set role authenticated;");
    try {
      await failsWith(() => deleteRecord(db, OWNER), "permission denied");
    } finally {
      await db.exec("reset role;");
    }
  });

  await t.step(
    "a stranger's call finds nothing and changes nothing",
    async () => {
      await failsWith(
        () => deleteRecord(db, STRANGER),
        "owned result not found",
      );
      if ((await deletedAt(db)) !== null) throw new Error("record was deleted");
    },
  );

  await t.step("the owner's call marks the record deleted once", async () => {
    const { rows } = await deleteRecord(db, OWNER);
    if (rows[0].id !== RECORD) throw new Error(`returned ${rows[0].id}`);
    if ((await deletedAt(db)) === null) throw new Error("record still live");
    await failsWith(() => deleteRecord(db, OWNER), "owned result not found");
  });

  await db.close();
});
