import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";

// The one-line note is the only field a record's owner writes after the
// card: through one RPC that touches nothing else.

const OWNER = "a0000000-0000-4000-8000-000000000021";
const STRANGER = "a0000000-0000-4000-8000-000000000022";
const CATEGORY = "c0000000-0000-4000-8000-000000000001";
const ITEM = "b0000000-0000-4000-8000-000000000001";
const RECORD = "d0000000-0000-4000-8000-000000000001";
const DELETED_RECORD = "d0000000-0000-4000-8000-000000000002";

async function asUser(db: PGlite, user: string, work: () => Promise<void>) {
  await db.exec("set role authenticated;");
  await db.query("select set_config('request.jwt.claims', $1, false)", [
    JSON.stringify({ sub: user }),
  ]);
  try {
    await work();
  } finally {
    await db.exec("reset role;");
  }
}

async function seed(db: PGlite) {
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${OWNER}', 'owner@example.test', '{"provider":"kakao"}', now()),
      ('${STRANGER}', 'stranger@example.test', '{"provider":"kakao"}', now());
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('${CATEGORY}', 'wine', '와인', 1);
    insert into public.alcohol_items (id, name_ko, alcohol_category_id, publish_status, published_at)
      values ('${ITEM}', '테스트 술', '${CATEGORY}', 'published', now());
    insert into public.drink_records (id, user_id, alcohol_item_id, questionnaire_version, deleted_at) values
      ('${RECORD}', '${OWNER}', '${ITEM}', 'sensory-questionnaire-v1', null),
      ('${DELETED_RECORD}', '${OWNER}', '${ITEM}', 'sensory-questionnaire-v1', now());
  `);
}

async function record(db: PGlite) {
  const { rows } = await db.query<{ one_line_note: string | null }>(
    "select one_line_note from public.drink_records where id = $1",
    [RECORD],
  );
  return rows[0];
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

Deno.test("record note", async (t) => {
  const db = await createSupabaseLikeDatabase();
  await seed(db);

  await t.step(
    "the owner adds, changes and clears the note of a live record",
    async () => {
      await asUser(db, OWNER, async () => {
        await db.query(
          "select public.soolgyul_update_my_drink_record_note($1, $2)",
          [RECORD, "  뒤에 달큰함이 남아서 좋았어요  "],
        );
        if (
          (await record(db)).one_line_note !== "뒤에 달큰함이 남아서 좋았어요"
        ) {
          throw new Error("note not trimmed and stored");
        }
        await db.query(
          "select public.soolgyul_update_my_drink_record_note($1, $2)",
          [RECORD, "   "],
        );
        if ((await record(db)).one_line_note !== null) {
          throw new Error("blank note should clear");
        }
        await failsWith(
          () =>
            db.query(
              "select public.soolgyul_update_my_drink_record_note($1, $2)",
              [
                DELETED_RECORD,
                "메모",
              ],
            ),
          "record_not_found",
        );
      });
      await asUser(db, STRANGER, async () => {
        await failsWith(
          () =>
            db.query(
              "select public.soolgyul_update_my_drink_record_note($1, $2)",
              [
                RECORD,
                "남의 기록",
              ],
            ),
          "record_not_found",
        );
      });
      await db.query("select set_config('request.jwt.claims', '', false)");
      await failsWith(
        () =>
          db.query(
            "select public.soolgyul_update_my_drink_record_note($1, $2)",
            [
              RECORD,
              "익명",
            ],
          ),
        "authentication_required",
      );
    },
  );

  await db.close();
});
