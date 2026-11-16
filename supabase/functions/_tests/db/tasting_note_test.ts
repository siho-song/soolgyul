import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { asUser, failsWith } from "../helpers/db_session.ts";

// 테이스팅 노트 is written by the record's owner after the card, through one
// RPC that changes only the fields it is given; the price stays with a
// record kept without its owner.

const OWNER = "a0000000-0000-4000-8000-000000000051";
const STRANGER = "a0000000-0000-4000-8000-000000000052";
const CATEGORY = "c0000000-0000-4000-8000-000000000001";
const ITEM = "b0000000-0000-4000-8000-000000000001";
const RECORD = "d0000000-0000-4000-8000-000000000051";
const OTHER_RECORD = "d0000000-0000-4000-8000-000000000052";
const MISSING_RECORD = "d0000000-0000-4000-8000-000000000059";
const CARD = "e0000000-0000-4000-8000-000000000051";
const OTHER_CARD = "e0000000-0000-4000-8000-000000000052";

async function seed(db: PGlite) {
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${OWNER}', 'owner@example.test', '{"provider":"kakao"}', now()),
      ('${STRANGER}', 'stranger@example.test', '{"provider":"kakao"}', now());
    update public.users set birth_date = '1993-04-12' where id = '${OWNER}';
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('${CATEGORY}', 'wine', '와인', 1);
    insert into public.alcohol_items (id, name_ko, alcohol_category_id, publish_status, published_at)
      values ('${ITEM}', '테스트 술', '${CATEGORY}', 'published', now());
    insert into public.drink_records (id, user_id, alcohol_item_id, questionnaire_version)
      values
        ('${RECORD}', '${OWNER}', '${ITEM}', 'sensory-questionnaire-v1'),
        ('${OTHER_RECORD}', '${OWNER}', '${ITEM}', 'sensory-questionnaire-v1');
    insert into public.taste_cards (id, drink_record_id, snapshot_id, snapshot_ref, lifecycle,
        canonical_schema_version, semantic_snapshot, rendered_snapshot)
      values
        ('${CARD}', '${RECORD}', gen_random_uuid(), repeat('a', 64), 'final',
          'test', '{}'::jsonb, '{}'::jsonb),
        ('${OTHER_CARD}', '${OTHER_RECORD}', gen_random_uuid(), repeat('b', 64), 'final',
          'test', '{}'::jsonb, '{}'::jsonb);
  `);
}

const save = (db: PGlite, record: string, note: unknown) =>
  db.query("select public.soolgyul_save_my_tasting_note($1, $2::jsonb)", [
    record,
    JSON.stringify(note),
  ]);

async function note(db: PGlite, record = RECORD) {
  const { rows } = await db.query<Record<string, unknown>>(
    `select purchase_price_won, purchase_price_unit, purchase_place, appearance,
       appearance_texture, serving, aroma_memo, palate_memo, finish_memo,
       one_line_note
     from public.tasting_notes where drink_record_id = $1`,
    [record],
  );
  return rows[0] ?? null;
}

function expectNote(actual: unknown, expected: unknown, label: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${label}: ${JSON.stringify(actual)}`);
  }
}

const EMPTY = {
  purchase_price_won: null,
  purchase_price_unit: null,
  purchase_place: null,
  appearance: null,
  appearance_texture: null,
  serving: null,
  aroma_memo: null,
  palate_memo: null,
  finish_memo: null,
  one_line_note: null,
};

Deno.test("tasting note", async (t) => {
  const db = await createSupabaseLikeDatabase();
  await seed(db);

  await t.step(
    "only the fields given change, and a null clears one",
    async () => {
      await asUser(db, OWNER, async () => {
        await save(db, RECORD, {
          price_won: 38000,
          price_unit: "bottle",
          purchase_place: "smart_order_shop",
        });
        expectNote(await note(db), {
          ...EMPTY,
          purchase_price_won: 38000,
          purchase_price_unit: "bottle",
          purchase_place: "smart_order_shop",
        }, "price and place");
        await save(db, RECORD, {
          appearance: "ruby",
          appearance_texture: "heavy",
          aroma_memo: "  잘 익은 자두  ",
        });
        await save(db, RECORD, {
          purchase_place: null,
          // One glass drunk two ways; a way named twice is kept once.
          serving: ["neat", "rocks", "neat"],
          palate_memo: " 끝에 쌉쌀함 ",
          finish_memo: "길게 남는다",
          memo: " 지울 메모 ",
        });
        expectNote(await note(db), {
          purchase_price_won: 38000,
          purchase_price_unit: "bottle",
          purchase_place: null,
          appearance: "ruby",
          appearance_texture: "heavy",
          serving: ["neat", "rocks"],
          aroma_memo: "잘 익은 자두",
          palate_memo: "끝에 쌉쌀함",
          finish_memo: "길게 남는다",
          one_line_note: "지울 메모",
        }, "partial saves");
        await failsWith(
          () => save(db, MISSING_RECORD, { serving: ["neat"] }),
          "record_not_found",
        );
      });
    },
  );

  await t.step("a note left with nothing is no row", async () => {
    await asUser(db, OWNER, async () => {
      await save(db, OTHER_RECORD, { serving: ["highball"] });
      await save(db, OTHER_RECORD, { serving: null, aroma_memo: " " });
      expectNote(await note(db, OTHER_RECORD), null, "emptied note");
      // No way at all clears the field as a null does.
      await save(db, OTHER_RECORD, { serving: ["highball"] });
      await save(db, OTHER_RECORD, { serving: [] });
      expectNote(await note(db, OTHER_RECORD), null, "no way left");
      await save(db, OTHER_RECORD, { appearance: null });
      expectNote(await note(db, OTHER_RECORD), null, "nothing saved");
    });
  });

  await t.step(
    "the owner reads the note; a stranger neither reads nor writes it",
    async () => {
      await asUser(db, OWNER, async () => {
        if ((await note(db)) === null) throw new Error("the owner cannot read");
      });
      await asUser(db, STRANGER, async () => {
        if ((await note(db)) !== null) {
          throw new Error("a stranger read the note");
        }
        await failsWith(
          () => save(db, RECORD, { serving: ["rocks"] }),
          "record_not_found",
        );
      });
      await db.query("select set_config('request.jwt.claims', '', false)");
      await failsWith(
        () => save(db, RECORD, { serving: ["rocks"] }),
        "authentication_required",
      );
    },
  );

  await t.step(
    "the 취향 tab's records carry the price and the place",
    async () => {
      await asUser(db, OWNER, async () => {
        await save(db, RECORD, { purchase_place: "bar" });
        const { rows } = await db.query<{ history: Record<string, unknown>[] }>(
          "select public.soolgyul_my_drink_history(now() - interval '1 day', now() + interval '1 day') as history",
        );
        const byCard = new Map(
          rows[0].history.map((entry) => [entry.result_id, entry]),
        );
        const priced = byCard.get(CARD);
        const plain = byCard.get(OTHER_CARD);
        if (
          priced?.price_won !== 38000 || priced?.price_unit !== "bottle" ||
          priced?.purchase_place !== "bar" || priced?.note !== "지울 메모"
        ) {
          throw new Error(`history lost the price: ${JSON.stringify(priced)}`);
        }
        if (plain?.price_won !== null || plain?.purchase_place !== null) {
          throw new Error(`history invented a price: ${JSON.stringify(plain)}`);
        }
      });
    },
  );

  await t.step(
    "anything out of bounds is refused and changes nothing",
    async () => {
      await asUser(db, OWNER, async () => {
        for (
          const bad of [
            { price_won: 0, price_unit: "bottle" },
            { price_won: 10000001, price_unit: "bottle" },
            { price_won: 1000.5, price_unit: "bottle" },
            { price_won: 1000, price_unit: "can" },
            { price_won: null },
            { purchase_place: "street" },
            { appearance: "Ruby Red" },
            { serving: 3 },
            { serving: "neat" },
            { serving: ["Neat"] },
            { serving: [3] },
            { serving: Array.from({ length: 9 }, (_, i) => `way_${i}`) },
            { aroma_memo: "가".repeat(201) },
            { colour: "ruby" },
            [],
          ]
        ) {
          await failsWith(() => save(db, RECORD, bad), "note_invalid");
        }
      });
      const row = await note(db);
      if (row?.purchase_price_won !== 38000 || row?.appearance !== "ruby") {
        throw new Error(
          `a refused note changed the row: ${JSON.stringify(row)}`,
        );
      }
    },
  );

  await t.step(
    "a record kept without its owner keeps the price, not the memo or the rest of the note",
    async () => {
      await db.query(
        "select public.soolgyul_delete_owned_drink_record($1, $2)",
        [CARD, OWNER],
      );
      const { rows } = await db.query<Record<string, unknown>>(
        "select purchase_price_won, purchase_price_unit, record_data from public.retained_drink_records",
      );
      if (
        rows.length !== 1 || rows[0].purchase_price_won !== 38000 ||
        rows[0].purchase_price_unit !== "bottle"
      ) {
        throw new Error(`deleted card lost the price: ${JSON.stringify(rows)}`);
      }
      const kept = JSON.stringify(rows[0]);
      if (kept.includes("지울 메모") || kept.includes("자두")) {
        throw new Error("kept row holds the member's own words");
      }
      expectNote(await note(db), null, "note of a deleted record");
    },
  );
});
