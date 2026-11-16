import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { asUser, failsWith, refusal } from "../helpers/db_session.ts";
import { assert } from "../helpers/assert.ts";

// A saved card is written again in place when its member corrects the
// record's answers: the record, the card's id and its date stay; the
// answers and the snapshots are replaced together or not at all.

const OWNER = "a0000000-0000-4000-8000-000000000061";
const STRANGER = "a0000000-0000-4000-8000-000000000062";
const CATEGORY = "c0000000-0000-4000-8000-000000000061";
const ITEM = "b0000000-0000-4000-8000-000000000061";
const RECORD = "d0000000-0000-4000-8000-000000000061";
const CARD = "e0000000-0000-4000-8000-000000000061";
const HELD_REF = "taste-card-snapshot-v3:held";
const NEW_REF = "taste-card-snapshot-v3:revised";

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
    insert into public.drink_records (id, user_id, alcohol_item_id, questionnaire_version, created_at, updated_at)
      values ('${RECORD}', '${OWNER}', '${ITEM}', 'sensory-questionnaire-v1',
        '2026-10-01T00:00:00Z', '2026-10-01T00:00:00Z');
    insert into public.drink_record_answers (drink_record_id, question_key, selected_option_keys) values
      ('${RECORD}', 'sensory_aroma', array['notice:aroma:cherry']),
      ('${RECORD}', 'sensory_revisit', array['revisit:wantAgain']);
    insert into public.taste_cards (id, drink_record_id, snapshot_id, snapshot_ref, lifecycle,
        canonical_schema_version, semantic_snapshot, rendered_snapshot, snapshot_created_at)
      values ('${CARD}', '${RECORD}', gen_random_uuid(), '${HELD_REF}', 'final',
        'card-facts-v1', '{"held":true}'::jsonb, '{"held":true}'::jsonb,
        '2026-10-01T00:00:00Z');
  `);
}

function bundle(overrides: Record<string, unknown> = {}) {
  return {
    wire_schema_version: "taste-card-result-wire-v3",
    result_id: CARD,
    user_id: OWNER,
    base_snapshot_ref: HELD_REF,
    answers: [
      {
        question_key: "sensory_aroma",
        selected_option_keys: [
          "notice:aroma:plum",
          "reaction:aroma:plum:liked",
        ],
        free_text: null,
      },
      {
        question_key: "sensory_revisit",
        selected_option_keys: ["revisit:unsure"],
        free_text: null,
      },
    ],
    snapshot_ref: NEW_REF,
    engine_version: "card-facts-v2",
    semantic_snapshot: { engine_version: "card-facts-v2", revised: true },
    rendered_view: {
      revised: true,
      metadata: { snapshot_ref: NEW_REF, schema_version: 3 },
    },
    ...overrides,
  };
}

const revise = (db: PGlite, input: unknown) =>
  db.query<{ result: Record<string, unknown> }>(
    "select public.soolgyul_revise_taste_card($1::jsonb) as result",
    [JSON.stringify(input)],
  );

async function held(db: PGlite) {
  const card = (await db.query<Record<string, unknown>>(
    `select snapshot_ref, canonical_schema_version, semantic_snapshot,
            rendered_snapshot, snapshot_created_at::text as created
       from public.taste_cards where id = $1`,
    [CARD],
  )).rows[0];
  const answers = (await db.query<{ q: string; keys: string[] }>(
    `select question_key as q, selected_option_keys as keys
       from public.drink_record_answers where drink_record_id = $1
      order by question_key`,
    [RECORD],
  )).rows;
  return { card, answers: answers.map((a) => `${a.q}=${a.keys.join(",")}`) };
}

Deno.test("revise RPC", async (t) => {
  const db = await createSupabaseLikeDatabase();
  await seed(db);
  const before = await held(db);

  await t.step("a client role cannot call it", async () => {
    await asUser(db, OWNER, async () => {
      assert(await refusal(() => revise(db, bundle())), "owner refused");
    });
  });

  await t.step(
    "a bundle that is not whole, another member's card and a card changed since are refused",
    async () => {
      await failsWith(
        () => revise(db, bundle({ answers: [] })),
        "revision bundle is invalid",
      );
      await failsWith(
        () => revise(db, bundle({ snapshot_ref: "other" })),
        "revision bundle is invalid",
      );
      await failsWith(
        () => revise(db, bundle({ user_id: STRANGER })),
        "owned result not found",
      );
      await failsWith(
        () => revise(db, bundle({ base_snapshot_ref: "stale" })),
        "revision_conflict",
      );
      assert(
        JSON.stringify(await held(db)) === JSON.stringify(before),
        "nothing changed by a refused call",
      );
    },
  );

  await t.step(
    "the answers and the card are replaced; the card's id and date stay",
    async () => {
      const { rows } = await revise(db, bundle());
      const result = rows[0].result;
      assert(result.result_id === CARD && result.record_id === RECORD);
      assert(result.snapshot_ref === NEW_REF, JSON.stringify(result));
      const after = await held(db);
      assert(
        after.answers.join(" ") ===
          "sensory_aroma=notice:aroma:plum,reaction:aroma:plum:liked sensory_revisit=revisit:unsure",
        after.answers.join(" "),
      );
      assert(after.card.snapshot_ref === NEW_REF);
      assert(after.card.canonical_schema_version === "card-facts-v2");
      assert(
        (after.card.rendered_snapshot as { revised?: boolean }).revised ===
            true &&
          (after.card.semantic_snapshot as { revised?: boolean }).revised ===
            true,
      );
      assert(after.card.created === before.card.created, "the date stays");
      const updated = (await db.query<{ changed: boolean }>(
        `select updated_at > created_at as changed
           from public.drink_records where id = $1`,
        [RECORD],
      )).rows[0];
      assert(updated.changed, "the record says it changed");
      // The revision it was read from is gone: the same bundle is now stale.
      await failsWith(() => revise(db, bundle()), "revision_conflict");
    },
  );

  await t.step(
    "outside a revision a final card still never changes",
    async () => {
      await failsWith(
        () =>
          db.query(
            `update public.taste_cards set rendered_snapshot = '{}'::jsonb
            where id = $1`,
            [CARD],
          ),
        "Final taste card content is immutable",
      );
    },
  );
});
