import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import {
  canonicalJson,
  sha256Hex,
} from "../_shared/taste_card/service/canonical.ts";
import { createSupabaseLikeDatabase } from "./helpers/pglite_supabase.ts";

// The finalizer stores one card per attempt: the record and its answers, the
// rendered view and the private snapshot, and answers every later call for
// the same attempt with the stored result.

const ATTEMPT = "taste-card-attempt:finalize-test";
const SESSION = "anonymous-session-finalize";
const IDEMPOTENCY = "10000000-0000-4000-8000-000000000031";
const RECORD = "20000000-0000-4000-8000-000000000031";
const CARD = "30000000-0000-4000-8000-000000000031";
const SNAPSHOT_REF = "taste-card-snapshot-v3:abc";
const CATEGORY = "c0000000-0000-4000-8000-000000000031";
const ITEM = "40000000-0000-4000-8000-000000000031";
const STAGING_ITEM = "40000000-0000-4000-8000-000000000032";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}

function bundle(overrides: Record<string, unknown> = {}) {
  return {
    wire_schema_version: "taste-card-result-wire-v3",
    attempt_ref: ATTEMPT,
    principal: {
      kind: "anonymous",
      anonymous_session_digest: digest,
    },
    request_digest: "a".repeat(64),
    request: {
      idempotency_key: IDEMPOTENCY,
      anonymous_session_id: SESSION,
      questionnaire_version: "sensory-questionnaire-v1",
      alcohol_identification: identification,
      answers: [
        {
          question_key: "sensory_aroma",
          selected_option_keys: ["notice:aroma:cherry"],
          free_text: null,
        },
        {
          question_key: "sensory_revisit",
          selected_option_keys: ["revisit:wantAgain"],
          free_text: null,
        },
      ],
      q7_free_text: "메모",
      photo_asset_id: null,
    },
    alcohol_identification: identification,
    snapshot_ref: SNAPSHOT_REF,
    engine_version: "card-facts-v2",
    semantic_snapshot: {
      engine_version: "card-facts-v2",
      record: { recordRef: RECORD },
      facts: { nickname: "취향 탐색자" },
    },
    rendered_view: {
      product: {
        drink_name_snapshot: "테스트 술",
        user_name: null,
        image_reference: null,
        category_label: null,
      },
      bite: { nickname: "취향 탐색자", tags: [], summary: "요약", guide: null },
      positive: [],
      burden: [],
      metadata: {
        snapshot_ref: SNAPSHOT_REF,
        schema_version: 3,
        engine_version: "card-facts-v2",
        generated_at: "2026-10-29T00:00:00.000Z",
        generated_from_record_ref: RECORD,
      },
    },
    generated_at: "2026-10-29T00:00:00.000Z",
    conversion_key_version: "local",
    conversion_expires_at: "2026-10-30T00:00:00.000Z",
    ...overrides,
  };
}

const identification = {
  mode: "catalog_match",
  alcohol_item_id: ITEM,
  alcohol_name_snapshot: "테스트 술",
  category: null,
};
const digest = await sha256Hex(SESSION);

async function seedAttempt(db: PGlite) {
  await db.exec(`
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('${CATEGORY}', 'wine', '와인', 1);
    insert into public.alcohol_items (id, name_ko, alcohol_category_id, publish_status, published_at)
      values ('${ITEM}', '테스트 술', '${CATEGORY}', 'published', now()),
             ('${STAGING_ITEM}', '숨은 병', '${CATEGORY}', 'staging', null);
  `);
  await db.query(
    `insert into public.taste_card_generation_attempts
       (attempt_ref, idempotency_key, anonymous_session_digest, request_digest,
        reserved_record_id, reserved_result_summary_id, state)
     values ($1, $2, $3, $4, $5, $6, 'processing')`,
    [ATTEMPT, IDEMPOTENCY, digest, "a".repeat(64), RECORD, CARD],
  );
}

async function finalize(db: PGlite, input: unknown) {
  const { rows } = await db.query<{ result: Record<string, unknown> }>(
    "select public.soolgyul_finalize_taste_card_generation($1::jsonb) as result",
    [JSON.stringify(input)],
  );
  return rows[0].result;
}

async function failsWith(db: PGlite, input: unknown, fragment: string) {
  try {
    await finalize(db, input);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    assert(message.includes(fragment), `expected ${fragment}: ${message}`);
    return;
  }
  throw new Error(`expected failure: ${fragment}`);
}

Deno.test("finalize RPC", async (t) => {
  const db = await createSupabaseLikeDatabase();
  await seedAttempt(db);
  const count = async (table: string) =>
    (await db.query<{ n: number }>(`select count(*)::int as n from ${table}`))
      .rows[0].n;

  await t.step(
    "rejects another wire version, a stale snapshot ref, a missing snapshot and a foreign session",
    async () => {
      await failsWith(
        db,
        bundle({ wire_schema_version: "taste-card-result-wire-v2" }),
        "wire schema version",
      );
      await failsWith(
        db,
        bundle({ snapshot_ref: "other" }),
        "snapshot is invalid",
      );
      await failsWith(
        db,
        bundle({ semantic_snapshot: null }),
        "finalization bundle is invalid",
      );
      await failsWith(
        db,
        bundle({ request_digest: "b".repeat(64) }),
        "idempotency_conflict",
      );
      await failsWith(
        db,
        bundle({
          principal: {
            kind: "anonymous",
            anonymous_session_digest: "0".repeat(64),
          },
        }),
        "principal mismatch",
      );
      assert(
        await count("public.taste_cards") === 0,
        "nothing stored by a rejected call",
      );
    },
  );

  await t.step(
    "a record needs a published catalog item; a drink entered by name is refused",
    async () => {
      const withIdentification = (value: Record<string, unknown>) =>
        bundle({
          alcohol_identification: value,
          request: { ...bundle().request, alcohol_identification: value },
        });
      await failsWith(
        db,
        withIdentification({
          ...identification,
          alcohol_item_id: STAGING_ITEM,
        }),
        "not publishable",
      );
      await failsWith(
        db,
        withIdentification({ ...identification, alcohol_item_id: null }),
        "catalog identifier required",
      );
      await failsWith(
        db,
        withIdentification({
          mode: "direct_input",
          alcohol_item_id: null,
          entered_alcohol_name: "테스트 술",
          alcohol_name_snapshot: "테스트 술",
          category: null,
        }),
        "identification mode is invalid",
      );
      assert(
        await count("public.drink_records") === 0,
        "nothing stored by a rejected call",
      );
    },
  );

  await t.step(
    "stores the record, its answers and the card once, then replays the stored result",
    async () => {
      const result = await finalize(db, bundle());
      assert(result.result_id === CARD && result.record_id === RECORD);
      assert(result.snapshot_ref === SNAPSHOT_REF);
      assert(result.ownership_state === "anonymous");
      assert(
        canonicalJson(result.rendered_snapshot) ===
          canonicalJson(bundle().rendered_view),
        "the rendered view is returned as stored",
      );
      assert(
        result.wire_schema_version === "taste-card-result-wire-v3",
        "the stored result names the wire the server parses",
      );
      const cards = await db.query<
        { canonical_schema_version: string; semantic_snapshot: unknown }
      >(
        "select canonical_schema_version, semantic_snapshot from public.taste_cards where id = $1",
        [CARD],
      );
      assert(cards.rows.length === 1);
      assert(cards.rows[0].canonical_schema_version === "card-facts-v2");
      assert(
        canonicalJson(cards.rows[0].semantic_snapshot) ===
          canonicalJson(bundle().semantic_snapshot),
      );
      const answers = await db.query<{ question_key: string }>(
        "select question_key from public.drink_record_answers where drink_record_id = $1 order by question_key",
        [RECORD],
      );
      assert(
        answers.rows.map((row) => row.question_key).join() ===
          "sensory_aroma,sensory_revisit",
      );
      const records = await db.query<
        { one_line_note: string | null; alcohol_item_id: string }
      >(
        "select one_line_note, alcohol_item_id from public.drink_records where id = $1",
        [RECORD],
      );
      assert(records.rows[0].one_line_note === "메모");
      assert(
        records.rows[0].alcohol_item_id === ITEM,
        "record points at the item",
      );
      assert(
        canonicalJson(result.alcohol_identification) === canonicalJson({
          mode: "catalog_match",
          alcohol_item_id: ITEM,
          alcohol_name_snapshot: "테스트 술",
          category: "wine",
        }),
        "identification is rebuilt from the record and the catalog",
      );
      const attempt = await db.query<
        { state: string; result_summary_id: string }
      >(
        "select state, result_summary_id from public.taste_card_generation_attempts where attempt_ref = $1",
        [ATTEMPT],
      );
      assert(
        attempt.rows[0].state === "final" &&
          attempt.rows[0].result_summary_id === CARD,
      );
      // A second call for the final attempt returns the same card and writes nothing.
      const again = await finalize(db, bundle());
      assert(canonicalJson(again) === canonicalJson(result));
      assert(await count("public.taste_cards") === 1);
    },
  );

  await db.close();
});
