import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { failsWith } from "../helpers/db_session.ts";

// A reader deletes a saved record from its card. The card server calls one
// service RPC that removes only the owner's record and keeps it without its
// owner or memo; clients cannot call it.

const OWNER = "a0000000-0000-4000-8000-000000000041";
const STRANGER = "a0000000-0000-4000-8000-000000000042";
const CATEGORY = "c0000000-0000-4000-8000-000000000001";
const ITEM = "b0000000-0000-4000-8000-000000000001";
const RECORD = "d0000000-0000-4000-8000-000000000041";
const CARD = "e0000000-0000-4000-8000-000000000041";
const SNAPSHOT = "e0000000-0000-4000-8000-000000000043";
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
    update public.users set birth_date = '1993-04-12' where id = '${OWNER}';
    insert into public.drink_records (id, user_id, alcohol_item_id, questionnaire_version, one_line_note)
      values ('${RECORD}', '${OWNER}', '${ITEM}', 'sensory-questionnaire-v1', '지울 메모');
    insert into public.drink_record_answers (drink_record_id, question_key, selected_option_keys)
      values ('${RECORD}', 'sensory_finish', array['finish:heavy']);
    insert into public.taste_cards (id, drink_record_id, snapshot_id, snapshot_ref, lifecycle,
        canonical_schema_version, semantic_snapshot, rendered_snapshot)
      values ('${CARD}', '${RECORD}', '${SNAPSHOT}', '${SNAPSHOT_REF}', 'final',
        'test', '{}'::jsonb, '{}'::jsonb);
  `);
}

function deleteRecord(db: PGlite, user: string) {
  return db.query<{ id: string }>(
    "select public.soolgyul_delete_owned_drink_record($1, $2) as id",
    [CARD, user],
  );
}

async function liveRecords(db: PGlite) {
  const { rows } = await db.query<{ n: number }>(
    "select count(*)::int as n from public.drink_records where id = $1",
    [RECORD],
  );
  return rows[0].n;
}

async function retained(db: PGlite) {
  const { rows } = await db.query<
    { birth_year_band: number; gender: string | null; record_data: unknown }
  >("select birth_year_band, gender, record_data from public.retained_drink_records");
  return rows;
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
      if ((await liveRecords(db)) !== 1) throw new Error("record was deleted");
      if ((await retained(db)).length !== 0) throw new Error("record was kept");
    },
  );

  await t.step(
    "the owner's call removes the record once and keeps it without its owner",
    async () => {
      // An attempt that names the card only by its snapshot goes with it;
      // left behind, it would block removing the card.
      await db.exec(`
        insert into public.drink_records (id, user_id, alcohol_item_id, questionnaire_version)
          values ('d0000000-0000-4000-8000-000000000042', '${STRANGER}', '${ITEM}', 'sensory-questionnaire-v1');
        insert into public.taste_cards (id, drink_record_id, snapshot_id, snapshot_ref, lifecycle,
            canonical_schema_version, semantic_snapshot, rendered_snapshot)
          values ('e0000000-0000-4000-8000-000000000042', 'd0000000-0000-4000-8000-000000000042',
            gen_random_uuid(), repeat('d', 64), 'final', 'test', '{}'::jsonb, '{}'::jsonb);
        insert into public.taste_card_generation_attempts
            (attempt_ref, idempotency_key, owner_user_id, request_digest, state,
             reserved_result_summary_id, result_summary_id, claim_snapshot_id, completed_at)
          values ('by-snapshot', gen_random_uuid(), '${STRANGER}', repeat('a', 64), 'final',
            'e0000000-0000-4000-8000-000000000042', 'e0000000-0000-4000-8000-000000000042',
            '${SNAPSHOT}', now());
      `);
      const { rows } = await deleteRecord(db, OWNER);
      const { rows: attempts } = await db.query(
        "select 1 from public.taste_card_generation_attempts where attempt_ref = 'by-snapshot'",
      );
      if (attempts.length !== 0) throw new Error("attempt left behind");
      if (rows[0].id !== RECORD) throw new Error(`returned ${rows[0].id}`);
      if ((await liveRecords(db)) !== 0) throw new Error("record still live");
      const kept = await retained(db);
      if (kept.length !== 1) throw new Error(`kept ${kept.length} rows`);
      if (kept[0].birth_year_band !== 1990 || kept[0].gender !== null) {
        throw new Error("kept row carries more than the five-year band");
      }
      const text = JSON.stringify(kept[0].record_data);
      for (const secret of [OWNER, RECORD, CARD, "지울 메모"]) {
        if (text.includes(secret)) throw new Error(`kept row holds ${secret}`);
      }
      if (!text.includes("finish:heavy") || !text.includes(ITEM)) {
        throw new Error("kept row lost the answers or the drink");
      }
      await failsWith(() => deleteRecord(db, OWNER), "owned result not found");
      if ((await retained(db)).length !== 1) throw new Error("kept twice");
    },
  );

  await db.close();
});
