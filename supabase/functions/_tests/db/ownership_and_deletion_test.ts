import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";

// The SQL that guards a member's data: who may read or claim a card, what a
// scheduled deletion blocks, what the purge keeps and strips, and the small
// owner RPCs the app calls directly (consent, display name, inquiries).

const ids = {
  owner: "a0000000-0000-4000-8000-000000000031",
  other: "a0000000-0000-4000-8000-000000000032",
  leaving: "a0000000-0000-4000-8000-000000000033",
  category: "c0000000-0000-4000-8000-000000000031",
  item: "e0000000-0000-4000-8000-000000000031",
  ownedRecord: "f0000000-0000-4000-8000-000000000031",
  ownedCard: "f0000000-0000-4000-8000-000000000032",
  ownedSnapshot: "f0000000-0000-4000-8000-000000000033",
  anonymousRecord: "f0000000-0000-4000-8000-000000000034",
  anonymousCard: "f0000000-0000-4000-8000-000000000035",
  anonymousSnapshot: "f0000000-0000-4000-8000-000000000036",
  leavingRecord: "f0000000-0000-4000-8000-000000000037",
  leavingCard: "f0000000-0000-4000-8000-000000000038",
  leavingSnapshot: "f0000000-0000-4000-8000-000000000039",
  inquiry: "f0000000-0000-4000-8000-000000000041",
};
const DIGEST = "7".repeat(64);
const FINAL_REF = "attempt:ownership-final";
const PROCESSING_REF = "attempt:ownership-processing";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function same(actual: unknown, expected: unknown, label: string) {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${label}: expected ${b}, received ${a}`);
}
async function rejects(
  work: () => Promise<unknown>,
  fragment: string,
  label: string,
) {
  try {
    await work();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    assert(
      message.includes(fragment),
      `${label}: expected "${fragment}", received "${message}"`,
    );
    return;
  }
  throw new Error(`${label}: expected rejection "${fragment}"`);
}

/** Runs `work` as a client role; `null` is a caller without a session. */
async function asRole(
  db: PGlite,
  role: "anon" | "authenticated",
  userId: string | null,
  work: () => Promise<void>,
) {
  await db.exec(`set role ${role};`);
  await db.query("select set_config('request.jwt.claims', $1, false)", [
    userId === null ? "" : JSON.stringify({ sub: userId }),
  ]);
  try {
    await work();
  } finally {
    await db.exec("reset role;");
    await db.query("select set_config('request.jwt.claims', '', false)");
  }
}

/** What the database holds, read as its owner even inside a member's turn. */
async function held<T>(db: PGlite, sql: string, params: unknown[] = []) {
  const { rows } = await db.query<{ role: string }>(
    "select current_user as role",
  );
  await db.exec("reset role;");
  try {
    return await db.query<T>(sql, params);
  } finally {
    await db.exec(`set role ${rows[0].role};`);
  }
}

async function one<T>(db: PGlite, sql: string, params: unknown[] = []) {
  const { rows } = await db.query<{ v: T }>(sql, params);
  return rows[0].v;
}
const count = (db: PGlite, sql: string, params: unknown[] = []) =>
  one<number>(db, `select count(*)::int as v from (${sql}) q`, params);

async function completeProfile(db: PGlite, userId: string, name: string) {
  await asRole(db, "authenticated", userId, async () => {
    await db.query(
      `select public.soolgyul_complete_my_profile(
         gen_random_uuid(), $1, date '1990-03-21', true, 'soolgyul-terms-v1',
         'soolgyul-privacy-v1', 'soolgyul-marketing-v1', true, true, false)`,
      [name],
    );
  });
}

async function insertCard(
  db: PGlite,
  input: {
    recordId: string;
    cardId: string;
    snapshotId: string;
    userId: string | null;
    sessionId: string | null;
    note?: string;
  },
) {
  await db.query(
    `insert into public.drink_records
       (id, user_id, anonymous_session_id, questionnaire_version, alcohol_item_id,
        idempotency_key, one_line_note)
     values ($1, $2, $3, 'sensory-questionnaire-v1', $4, $5, $6)`,
    [
      input.recordId,
      input.userId,
      input.sessionId,
      ids.item,
      crypto.randomUUID(),
      input.note ?? null,
    ],
  );
  await db.query(
    `insert into public.drink_record_answers
       (drink_record_id, question_key, selected_option_keys)
     values ($1, 'sensory_aroma', array['notice:aroma:cherry'])`,
    [input.recordId],
  );
  await db.query(
    `insert into public.taste_cards
       (id, drink_record_id, lifecycle, snapshot_id, snapshot_ref,
        canonical_schema_version, semantic_snapshot, rendered_snapshot, snapshot_created_at)
     values ($1, $2, 'final', $3, $4, 'card-facts-v2', '{"facts":{}}', $5, now())`,
    [
      input.cardId,
      input.recordId,
      input.snapshotId,
      `taste-card-snapshot-v3:${input.cardId}`,
      JSON.stringify({
        product: {
          drink_name_snapshot: "테스트 술",
          user_name: "민지",
          image_reference: { source: "user_photo", reference: "private/x.jpg" },
          category_label: "와인",
        },
        bite: {
          nickname: "취향 탐색자",
          tags: [],
          summary: "요약",
          guide: null,
        },
        positive: [],
        burden: [],
        balanced: [],
        metadata: {
          snapshot_ref: `taste-card-snapshot-v3:${input.cardId}`,
          schema_version: 3,
          engine_version: "card-facts-v2",
          generated_at: "2026-10-29T00:00:00.000Z",
          generated_from_record_ref: input.recordId,
        },
      }),
    ],
  );
}

async function seed(db: PGlite) {
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${ids.owner}', 'owner@example.test', '{"provider":"kakao"}', now()),
      ('${ids.other}', 'other@example.test', '{"provider":"google"}', now()),
      ('${ids.leaving}', 'leaving@example.test', '{"provider":"apple"}', now());
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('${ids.category}', 'wine', '와인', 1);
    insert into public.alcohol_items (id, name_ko, alcohol_category_id, publish_status, published_at)
      values ('${ids.item}', '테스트 술', '${ids.category}', 'published', now());
  `);
  await completeProfile(db, ids.owner, "민지");
  await completeProfile(db, ids.other, "다른이");
  await completeProfile(db, ids.leaving, "떠날이");
  await insertCard(db, {
    recordId: ids.ownedRecord,
    cardId: ids.ownedCard,
    snapshotId: ids.ownedSnapshot,
    userId: ids.owner,
    sessionId: null,
  });
  await insertCard(db, {
    recordId: ids.anonymousRecord,
    cardId: ids.anonymousCard,
    snapshotId: ids.anonymousSnapshot,
    userId: null,
    sessionId: "anonymous-session-ownership",
  });
  await insertCard(db, {
    recordId: ids.leavingRecord,
    cardId: ids.leavingCard,
    snapshotId: ids.leavingSnapshot,
    userId: ids.leaving,
    sessionId: null,
    note: "떠나기 전 메모",
  });
  await db.query(
    `insert into public.taste_card_generation_attempts
       (attempt_ref, idempotency_key, anonymous_session_digest, request_digest,
        reserved_record_id, reserved_result_summary_id, state, result_summary_id,
        claim_snapshot_id, conversion_key_version, conversion_expires_at, completed_at)
     values ($1, gen_random_uuid(), $2, repeat('a', 64), $3, $4, 'final', $4, $5, 'local',
             now() + interval '1 hour', now())`,
    [
      FINAL_REF,
      DIGEST,
      ids.anonymousRecord,
      ids.anonymousCard,
      ids.anonymousSnapshot,
    ],
  );
  await db.query(
    `insert into public.taste_card_generation_attempts
       (attempt_ref, idempotency_key, anonymous_session_digest, request_digest)
     values ($1, gen_random_uuid(), $2, repeat('b', 64))`,
    [PROCESSING_REF, DIGEST],
  );
}

Deno.test("ownership and deletion", async (t) => {
  const db = await createSupabaseLikeDatabase();
  await seed(db);

  const owned = (cardId: string, userId: string) =>
    one<Record<string, unknown>>(
      db,
      "select public.soolgyul_get_owned_taste_card_result($1, $2) as v",
      [cardId, userId],
    );
  const convert = (userId: string, digest = DIGEST) =>
    db.query<{ converted: boolean; drink_record_id: string }>(
      `select * from public.soolgyul_convert_anonymous_taste_card($1, $2, $3, gen_random_uuid())`,
      [userId, ids.anonymousCard, digest],
    );
  const deletionState = () =>
    one<Record<string, unknown>>(
      db,
      "select public.soolgyul_get_my_deletion_state() as v",
    );

  await t.step(
    "a card is read only by its owner, and only from an active account",
    async () => {
      const result = await owned(ids.ownedCard, ids.owner);
      same(
        [result.result_id, result.record_id, result.ownership_state],
        [ids.ownedCard, ids.ownedRecord, "saved"],
        "owner reads the card",
      );
      await rejects(
        () => owned(ids.ownedCard, ids.other),
        "owned result not found",
        "another account",
      );
      await rejects(
        () => owned(ids.anonymousCard, ids.owner),
        "owned result not found",
        "an unclaimed anonymous card",
      );
      // The attempt reads the anonymous card; a processing attempt has none.
      const byAttempt = await one<Record<string, unknown>>(
        db,
        "select public.soolgyul_get_taste_card_result_for_attempt($1) as v",
        [FINAL_REF],
      );
      same(
        [byAttempt.result_id, byAttempt.ownership_state],
        [ids.anonymousCard, "anonymous"],
        "final attempt",
      );
      await rejects(
        () =>
          one(
            db,
            "select public.soolgyul_get_taste_card_result_for_attempt($1) as v",
            [PROCESSING_REF],
          ),
        "final result not found",
        "processing attempt",
      );
      // The client roles never call these service functions.
      await asRole(db, "authenticated", ids.owner, async () => {
        await rejects(
          () => owned(ids.ownedCard, ids.owner),
          "permission denied",
          "authenticated get_owned",
        );
        await rejects(
          () => convert(ids.owner),
          "permission denied",
          "authenticated convert",
        );
      });
    },
  );

  await t.step(
    "conversion needs the proof and an active, completed account; afterwards the card is the member's",
    async () => {
      await rejects(
        () => convert(ids.owner, "0".repeat(64)),
        "proof is invalid or expired",
        "wrong session digest",
      );
      // An account scheduled for deletion cannot claim a card.
      await db.query("select public.soolgyul_request_account_deletion($1)", [
        ids.leaving,
      ]);
      await rejects(
        () => convert(ids.leaving),
        "active account required",
        "scheduled account",
      );
      await asRole(db, "authenticated", ids.leaving, async () => {
        await db.query("select public.soolgyul_restore_my_account()");
      });

      const first = await convert(ids.owner);
      same(
        [first.rows[0].converted, first.rows[0].drink_record_id],
        [true, ids.anonymousRecord],
        "first conversion",
      );
      const claimed = await owned(ids.anonymousCard, ids.owner);
      same(claimed.ownership_state, "saved", "claimed card is saved");
      same(
        await one(
          db,
          "select anonymous_session_id as v from public.drink_records where id = $1",
          [ids.anonymousRecord],
        ),
        null,
        "the anonymous session is forgotten",
      );
      const again = await convert(ids.owner);
      same(again.rows[0].converted, false, "same owner retry is a no-op");
      await rejects(
        () => owned(ids.anonymousCard, ids.other),
        "owned result not found",
        "another account after conversion",
      );
      await rejects(
        () => convert(ids.other),
        "owned by another account",
        "another account converting",
      );
    },
  );

  await t.step(
    "taste letters are saved by the service only and read by their owner only",
    async () => {
      const save = (userId: string) =>
        db.query(
          "select public.soolgyul_save_taste_letters($1, $2::jsonb, $3::jsonb)",
          [
            userId,
            JSON.stringify({
              rule_version: "taste-letters-v1",
              record_count: 1,
              axes: { aroma: { letter: "F", share: 100, votes: 1 } },
            }),
            JSON.stringify([{
              record_id: userId === ids.leaving
                ? ids.leavingRecord
                : ids.ownedRecord,
              axis: "aroma",
              from_letter: null,
              to_letter: "F",
              left_share: 100,
              right_share: 0,
              product_name: "테스트 술",
              changed_at: "2026-11-01T00:00:00Z",
            }]),
          ],
        );
      await asRole(db, "authenticated", ids.owner, async () => {
        await rejects(
          () => save(ids.owner),
          "permission denied",
          "authenticated save",
        );
      });
      await rejects(
        () =>
          db.query(
            "select public.soolgyul_save_taste_letters($1, '[]'::jsonb, '[]'::jsonb)",
            [ids.owner],
          ),
        "payload is invalid",
        "malformed state",
      );
      await save(ids.owner);
      await save(ids.owner);
      await save(ids.leaving);
      same(
        await count(
          db,
          "select 1 from public.taste_letter_changes where user_id = $1",
          [ids.owner],
        ),
        1,
        "changes are replaced whole",
      );
      // Letters computed from a card list that has since changed are refused.
      const current = await db.query<{ id: string }>(
        `select record_row.id from public.drink_records record_row
         join public.taste_cards card on card.drink_record_id = record_row.id
         where record_row.user_id = $1 and card.lifecycle = 'final'`,
        [ids.owner],
      );
      const saveFrom = (recordIds: string[]) =>
        db.query(
          `select public.soolgyul_save_taste_letters($1,
             '{"rule_version":"taste-letters-v1","record_count":0,"axes":{}}'::jsonb,
             '[]'::jsonb, $2::uuid[])`,
          [ids.owner, recordIds],
        );
      await rejects(
        () =>
          saveFrom([...current.rows.map((row) => row.id), ids.leavingRecord]),
        "taste_letters_stale",
        "computed with a card that is not the account's",
      );
      await rejects(
        () => saveFrom(current.rows.slice(1).map((row) => row.id)),
        "taste_letters_stale",
        "computed without one of the account's cards",
      );
      same(
        await count(
          db,
          "select 1 from public.taste_letter_changes where user_id = $1",
          [ids.owner],
        ),
        1,
        "a refused save changes nothing",
      );
      await saveFrom(current.rows.map((row) => row.id));
      await save(ids.owner);
      const visible = (table: string) =>
        count(db, `select 1 from public.${table}`);
      await asRole(db, "authenticated", ids.owner, async () => {
        same(await visible("taste_letters"), 1, "owner letters");
        same(await visible("taste_letter_changes"), 1, "owner changes");
        await rejects(
          () =>
            db.query("delete from public.taste_letters where user_id = $1", [
              ids.owner,
            ]),
          "permission denied",
          "owner cannot write",
        );
      });
      await asRole(db, "authenticated", ids.other, async () => {
        same(await visible("taste_letters"), 0, "another account's letters");
        same(await visible("taste_letter_changes"), 0, "another's changes");
      });
      await asRole(db, "anon", null, async () => {
        await rejects(
          () => visible("taste_letters"),
          "permission denied",
          "anon letters",
        );
      });
    },
  );

  await t.step(
    "consent is append-only, the display name is checked, an inquiry belongs to its sender",
    async () => {
      const consent = (accepted: boolean | null) =>
        one<boolean>(
          db,
          "select public.soolgyul_set_marketing_consent($1) as v",
          [accepted],
        );
      const consentRows = () =>
        held<{ withdrawn: boolean }>(
          db,
          `select withdrawn_at is not null as withdrawn from public.user_consents
         where user_id = $1 and consent_type = 'marketing' order by accepted_at`,
          [ids.owner],
        );
      await asRole(db, "authenticated", ids.owner, async () => {
        same(
          await one(db, "select public.soolgyul_get_marketing_consent() as v"),
          false,
          "no consent yet",
        );
        same(await consent(true), true, "accept");
        same(await consent(true), true, "accept again");
        same((await consentRows()).rows.length, 1, "one open period");
        same(await consent(false), false, "withdraw");
        same(await consent(true), true, "accept once more");
        same(
          (await consentRows()).rows.map((r) => r.withdrawn),
          [true, false],
          "the closed period stays",
        );
        await rejects(
          () => consent(null),
          "consent_value_required",
          "null consent",
        );

        const rename = (name: string | null, key: string | null) =>
          one<{ display_name: string }>(
            db,
            "select public.soolgyul_update_my_display_name($1, $2) as v",
            [name, key],
          );
        same(
          (await rename("  새이름 ", crypto.randomUUID())).display_name,
          "새이름",
          "trimmed and stored",
        );
        await rejects(
          () => rename("a", crypto.randomUUID()),
          "display_name_invalid",
          "too short",
        );
        await rejects(
          () => rename("이름!", crypto.randomUUID()),
          "display_name_invalid",
          "punctuation",
        );
        await rejects(
          () => rename("새이름", null),
          "idempotency_key_required",
          "no key",
        );

        const inquiry = (content: string) =>
          one<string>(
            db,
            "select public.soolgyul_submit_support_inquiry($1, 'bug', 'me@example.test', $2) as v",
            [ids.inquiry, content],
          );
        same(await inquiry("앱이 멈춰요"), ids.inquiry, "submitted");
        same(
          await inquiry("앱이 멈춰요"),
          ids.inquiry,
          "retry returns the same",
        );
        await rejects(
          () => inquiry("다른 내용"),
          "inquiry_request_conflict",
          "same id, other content",
        );
        // More than five attachments are refused before storage is consulted
        // (the PGlite storage stub has no metadata to check a path against).
        await rejects(
          () =>
            db.query(
              `select public.soolgyul_submit_support_inquiry(gen_random_uuid(), 'bug',
               'me@example.test', '첨부', array_fill('x'::text, array[6]))`,
            ),
          "invalid_inquiry_attachments",
          "too many attachments",
        );
        same(
          (await held(db, "select 1 from public.support_inquiries")).rows
            .length,
          1,
          "the inquiry is kept",
        );
        // Sent and answered by e-mail: no member reads the table.
        await rejects(
          () => db.query("select 1 from public.support_inquiries"),
          "permission denied",
          "the sender reading the table",
        );
      });
      await asRole(db, "authenticated", null, async () => {
        await rejects(
          () => consent(true),
          "active_account_required",
          "consent without a session",
        );
        await rejects(
          () =>
            db.query(
              "select public.soolgyul_submit_support_inquiry(gen_random_uuid(), 'bug', 'me@example.test', '익명')",
            ),
          "authentication_required",
          "inquiry without a session",
        );
      });
    },
  );

  await t.step(
    "a scheduled deletion can be restored, blocks the owner RPCs, and is reset by a new login",
    async () => {
      await asRole(db, "authenticated", ids.leaving, async () => {
        same((await deletionState()).deletion_state, "active", "before");
        // A signed-in session cannot schedule its own withdrawal: that
        // would skip the check with the login provider.
        await rejects(
          () =>
            db.query("select public.soolgyul_request_account_deletion($1)", [
              ids.leaving,
            ]),
          "permission denied",
          "direct request",
        );
      });
      const requested = await one<Record<string, unknown>>(
        db,
        "select public.soolgyul_request_account_deletion($1) as v",
        [ids.leaving],
      );
      await asRole(db, "authenticated", ids.leaving, async () => {
        same(
          [requested.deletion_state, requested.restore_available],
          ["scheduled", true],
          "requested",
        );
        same((await deletionState()).provider_revoked, false, "not revoked");
        await rejects(
          () =>
            db.query(
              "select public.soolgyul_update_my_display_name('새이름', gen_random_uuid())",
            ),
          "active_account_required",
          "rename while scheduled",
        );
        await rejects(
          () => db.query("select public.soolgyul_set_marketing_consent(true)"),
          "active_account_required",
          "consent while scheduled",
        );
        same(
          await count(db, "select 1 from public.taste_letters"),
          0,
          "letters hidden while scheduled",
        );
        same(
          await count(db, "select 1 from public.drink_records"),
          0,
          "records hidden while scheduled",
        );
        const restored = await one<Record<string, unknown>>(
          db,
          "select public.soolgyul_restore_my_account() as v",
        );
        same(restored.deletion_state, "active", "restored");
        same(
          await count(db, "select 1 from public.drink_records"),
          1,
          "records back after restore",
        );
      });
      await db.query("select public.soolgyul_request_account_deletion($1)", [
        ids.leaving,
      ]);
      await rejects(
        () => owned(ids.leavingCard, ids.leaving),
        "owned result not found",
        "card read while scheduled",
      );

      // The worker marks the provider revoked against the login it verified.
      const requestedAt = await one<string>(
        db,
        "select deletion_requested_at as v from public.users where id = $1",
        [ids.leaving],
      );
      const signedInAt = await one<string>(
        db,
        "select last_sign_in_at as v from auth.users where id = $1",
        [ids.leaving],
      );
      const mark = (authenticatedAt: string) =>
        one<boolean>(
          db,
          "select public.soolgyul_mark_deletion_provider_revoked($1, $2, $3) as v",
          [ids.leaving, requestedAt, authenticatedAt],
        );
      same(await mark("2020-01-01T00:00:00Z"), false, "stale login proof");
      same(await mark(signedInAt), true, "current login proof");
      await asRole(db, "authenticated", ids.leaving, async () => {
        same((await deletionState()).provider_revoked, true, "revoked");
      });
      // A new login (soolgyul_deletion_reauthentication) voids the revocation.
      await db.query(
        "update auth.users set last_sign_in_at = now() + interval '1 minute' where id = $1",
        [ids.leaving],
      );
      same(
        await one(
          db,
          "select deletion_provider_revoked_at as v from public.users where id = $1",
          [ids.leaving],
        ),
        null,
        "revocation reset by the login trigger",
      );
      await rejects(
        () =>
          db.query(
            "select public.soolgyul_finalize_withdrawn_account_data($1)",
            [ids.leaving],
          ),
        "account_purge_not_due",
        "purge before its day, also after a new login",
      );
    },
  );

  await t.step(
    "the purge waits for its day, keeps the records without the person, and the cron job calls it",
    async () => {
      const finalize = () =>
        one<number>(
          db,
          "select public.soolgyul_finalize_withdrawn_account_data($1) as v",
          [ids.leaving],
        );
      // What the person leaves behind: a liked card and a private photo.
      await db.query(
        "insert into public.user_liked_drink_cards (user_id, drink_record_id) values ($1, $2)",
        [ids.leaving, ids.leavingRecord],
      );
      await db.query(
        "insert into storage.objects (bucket_id, name) values ('soolgyul-private', $1)",
        [`${ids.leaving}/drink-records/${ids.leavingRecord}/photo.jpg`],
      );
      // The login above reset the revocation mark and the member never
      // confirmed again; the purge still runs on its day.
      same(
        await one(
          db,
          "select deletion_provider_revoked_at as v from public.users where id = $1",
          [ids.leaving],
        ),
        null,
        "revocation still reset",
      );
      await rejects(finalize, "account_purge_not_due", "before the 30 days");
      await db.query(
        "update public.users set deletion_requested_at = now() - interval '31 days' where id = $1",
        [ids.leaving],
      );
      await asRole(db, "authenticated", ids.leaving, async () => {
        same(
          (await deletionState()).restore_available,
          false,
          "restore window closed",
        );
        await rejects(
          () => db.query("select public.soolgyul_restore_my_account()"),
          "restore_window_closed",
          "restore after the window",
        );
      });
      await rejects(
        finalize,
        "private_storage_cleanup_required",
        "with private objects left",
      );
      await db.query(
        "delete from storage.objects where name like $1",
        [`${ids.leaving}/%`],
      );

      // A search the person made while still active.
      await db.query(
        `insert into public.drink_discovery_events
           (kind, surface, alcohol_item_id, query_text, user_id)
         values ('search_pick', 'record', $1, '떠나는 사람 검색', $2)`,
        [ids.item, ids.leaving],
      );

      same(await finalize(), 1, "one record retained");
      const retained = await db.query<
        {
          birth_year_band: number;
          gender: string | null;
          record_data: Record<string, unknown>;
        }
      >("select birth_year_band, gender, record_data from public.withdrawn_drink_records");
      same(retained.rows.length, 1, "retained rows");
      const [row] = retained.rows;
      same(
        [row.birth_year_band, row.gender],
        [1990, null],
        "five-year band kept, no gender without consent",
      );
      same("one_line_note" in row.record_data, false, "memo not kept");
      const answers = row.record_data.answers as Record<string, unknown>[];
      same(
        answers[0].selected_option_keys,
        ["notice:aroma:cherry"],
        "answers kept",
      );
      const events = await db.query<
        { user_id: string | null; birth_year_band: number; midnight: boolean }
      >(
        `select user_id, birth_year_band,
           occurred_at = date_trunc('day', occurred_at, 'Asia/Seoul') as midnight
         from public.drink_discovery_events where query_text = '떠나는 사람 검색'`,
      );
      same(
        events.rows,
        [{ user_id: null, birth_year_band: 1990, midnight: true }],
        "the person's events lose the account link",
      );
      const card = JSON.stringify(row.record_data.card);
      assert(
        card.includes("취향 탐색자") && !card.includes("민지") &&
          !card.includes(ids.leavingRecord) && !card.includes("snapshot_ref") &&
          !card.includes("private/x.jpg"),
        `card links stripped: ${card}`,
      );
      same(
        await count(
          db,
          "select 1 from public.drink_records where user_id = $1",
          [
            ids.leaving,
          ],
        ),
        0,
        "records gone",
      );
      same(
        await count(
          db,
          "select 1 from public.user_liked_drink_cards where user_id = $1",
          [ids.leaving],
        ),
        0,
        "liked cards gone",
      );
      same(
        await count(
          db,
          "select 1 from public.taste_letter_changes where user_id = $1",
          [ids.leaving],
        ),
        0,
        "letter changes gone",
      );
      const account = await db.query<
        {
          status: string;
          display_name: string | null;
          birth_date: string | null;
        }
      >(
        "select account_status as status, display_name, birth_date from public.users where id = $1",
        [ids.leaving],
      );
      same(
        account.rows,
        [{
          status: "purged",
          display_name: null,
          birth_date: null,
        }],
        "the person is gone from the account",
      );
      same(await finalize(), 0, "a second purge does nothing");
      await asRole(db, "authenticated", ids.leaving, async () => {
        same((await deletionState()).deletion_state, "purged", "state");
        await rejects(
          () => db.query("select public.soolgyul_restore_my_account()"),
          "account_restore_unavailable",
          "restore after purge",
        );
      });
      // The worker then deletes the Auth account; the cascade removes the rest.
      await db.query("delete from auth.users where id = $1", [ids.leaving]);
      same(
        await count(
          db,
          "select 1 from public.taste_letters where user_id = $1",
          [
            ids.leaving,
          ],
        ),
        0,
        "letters gone with the account",
      );
      same(
        await count(db, "select 1 from public.users where id = $1", [
          ids.leaving,
        ]),
        0,
        "account row gone",
      );
      same(
        await count(db, "select 1 from public.withdrawn_drink_records"),
        1,
        "retained records survive the account",
      );
      const job = await db.query<{ schedule: string; command: string }>(
        "select schedule, command from cron.job where jobname = 'soolgyul-account-retention'",
      );
      same(
        job.rows,
        [{
          schedule: "0 * * * *",
          command: "select public.soolgyul_run_account_retention_job();",
        }],
        "hourly retention job",
      );
    },
  );

  await db.close();
});
