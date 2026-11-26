// The card service with only its persistence in memory: real HTTP source
// parsing (PostgREST rows → product) and real orchestration, so a test can
// read what was finalized.
import { HmacConversionTokenSigner } from "../../_shared/taste_card/service/conversion_token.ts";
import type { TasteCardOrchestratorDependencies } from "../../_shared/taste_card/service/orchestrator.ts";
import {
  type BeginTasteCardAttemptInput,
  type FinalizeTasteCardGenerationInput,
  type ReviseTasteCardInput,
  SupabaseTasteCardRepository,
  type TasteCardAttempt,
} from "../../_shared/taste_card/service/repository.ts";
import { parseTasteCardResultEnvelope } from "../../_shared/taste_card/service/serialization.ts";
import { TasteCardRepositoryError } from "../../_shared/taste_card/service/errors.ts";
import type {
  LetterChange,
  LetterRecord,
  TasteLettersState,
} from "../../_shared/taste_letters/letters_from_marks.ts";
import { marksFromRecord } from "../../_shared/taste_letters/marks_from_record.ts";
import { readRecord } from "../../_shared/record_reading/read_record.ts";
import { SENSORY_QUESTIONNAIRE_VERSION } from "../../_shared/record_reading/record/questionnaire.ts";
import type {
  CreateTasteCardResultRequest,
  RetryableErrorCode,
  TasteCardResultEnvelope,
} from "../../_shared/taste_card/service/types.ts";
import { answersOf } from "./card_fixture_record.ts";

export const ITEM = "30000000-0000-4000-8000-000000000001";
export const ANON = "10000000-0000-4000-8000-000000000001";

/**
 * A catalog-match request for ITEM (샤또 마고) as the app sends it: the
 * questions that were answered, 다시 마시고 싶은지 always (네 unless a key
 * says otherwise).
 */
export function tasteCardRequest(
  keys: readonly string[] = [],
  overrides: Partial<CreateTasteCardResultRequest> = {},
): CreateTasteCardResultRequest {
  return {
    idempotency_key: ANON,
    anonymous_session_id: "anonymous-session-one",
    questionnaire_version: SENSORY_QUESTIONNAIRE_VERSION,
    alcohol_identification: {
      mode: "catalog_match",
      alcohol_item_id: ITEM,
      alcohol_name_snapshot: "샤또 마고",
      category: "wine",
    },
    answers: answersOf(
      keys.some((key) => key.startsWith("revisit:"))
        ? keys
        : ["revisit:wantAgain", ...keys],
    ),
    q7_free_text: null,
    photo_asset_id: null,
    ...overrides,
  };
}
const instant = "2026-09-05T00:00:00.000Z";

export type CatalogRows = {
  items?: readonly Record<string, unknown>[];
  profiles?: readonly Record<string, unknown>[];
  media?: readonly Record<string, unknown>[];
  /** catalog_taxonomy style rows: term_key and label_ko. */
  styles?: readonly Record<string, unknown>[];
  /** Answer every catalog read with this HTTP status instead (e.g. 503). */
  failWith?: number;
};

/** The store in memory; every catalog read is answered from [rows]. */
export class MemoryTasteCardRepository extends SupabaseTasteCardRepository {
  attempts = new Map<string, TasteCardAttempt>();
  results = new Map<string, TasteCardResultEnvelope>();
  owners = new Map<string, string>();
  finalized: FinalizeTasteCardGenerationInput | null = null;
  snapshots = new Map<string, FinalizeTasteCardGenerationInput>();
  finalizations = 0;
  catalogReads = 0;
  constructor(rows: CatalogRows = {}) {
    super("https://offline.invalid", "offline-test-key", (input, init) => {
      if ((init?.method ?? "GET") !== "GET") {
        throw new Error("external_write_forbidden");
      }
      this.catalogReads += 1;
      if (rows.failWith) {
        return Promise.resolve(
          new Response(JSON.stringify({ message: "down" }), {
            status: rows.failWith,
            headers: { "content-type": "application/json" },
          }),
        );
      }
      const url = new URL(String(input));
      const table = url.pathname.split("/").at(-1);
      // One id, asked as `eq.<id>` or as `in.(<id>)`.
      const identifier = (url.searchParams.get("id") ??
        url.searchParams.get("alcohol_item_id"))?.replace(
          /^eq\.|^in\.\(|\)$/g,
          "",
        );
      let data: unknown;
      if (table === "alcohol_items") {
        data = (rows.items ?? []).filter((item) => item.id === identifier);
      } else if (table === "alcohol_tasting_profiles") {
        data = (rows.profiles ?? []).filter((row) =>
          row.alcohol_item_id === identifier
        );
      } else if (table === "catalog_media_assets") {
        data = (rows.media ?? []).filter((row) =>
          row.alcohol_item_id === identifier
        );
      } else if (table === "catalog_taxonomy") {
        const key = url.searchParams.get("term_key")?.replace(/^eq\./, "");
        data = (rows.styles ?? []).filter((row) => row.term_key === key);
      } else throw new Error(`unexpected_source_read:${table}`);
      return Promise.resolve(
        new Response(JSON.stringify(data), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    });
  }
  override getProfileGate(userId: string) {
    return Promise.resolve({
      active: userId !== "inactive-user",
      complete_adult_profile: userId !== "inactive-user",
      display_name: "민지",
    });
  }
  override findAttempt(
    principal: Parameters<SupabaseTasteCardRepository["findAttempt"]>[0],
    idempotencyKey: string,
  ) {
    return Promise.resolve(
      this.attempts.get(`${JSON.stringify(principal)}:${idempotencyKey}`) ??
        null,
    );
  }
  override beginAttempt(input: BeginTasteCardAttemptInput) {
    const key = `${JSON.stringify(input.principal)}:${input.idempotency_key}`;
    const existing = this.attempts.get(key);
    if (existing) return Promise.resolve(existing);
    const attempt: TasteCardAttempt = {
      ...input,
      state: "processing",
      error_code: null,
      retry_after: null,
      result_summary_id: null,
      claim_snapshot_id: null,
      conversion_key_version: null,
      conversion_expires_at: null,
      created_at: instant,
      updated_at: instant,
    };
    this.attempts.set(key, attempt);
    return Promise.resolve(attempt);
  }
  override finalizeGeneration(input: FinalizeTasteCardGenerationInput) {
    this.finalizations += 1;
    this.finalized = input;
    const attempt = this.attemptByRef(input.attempt_ref);
    // Like parseStoredEnvelope, validate before the orchestrator attaches the
    // anonymous bearer token. Tokens are never persisted in a snapshot.
    const stored = parseTasteCardResultEnvelope({
      wire_schema_version: input.wire_schema_version,
      result_id: attempt.reserved_result_summary_id,
      record_id: attempt.reserved_record_id,
      snapshot_ref: input.snapshot_ref,
      ownership_state: "saved",
      alcohol_identification: input.alcohol_identification,
      view: input.rendered_view,
      conversion: null,
      created_at: input.generated_at,
    });
    const result: TasteCardResultEnvelope = input.principal.kind === "anonymous"
      ? { ...stored, ownership_state: "anonymous" }
      : stored;
    if (input.principal.kind === "authenticated") {
      this.owners.set(result.result_id, input.principal.user_id);
    }
    Object.assign(attempt, {
      state: "final",
      result_summary_id: result.result_id,
      claim_snapshot_id: input.snapshot_ref,
      conversion_key_version: input.conversion_key_version,
      conversion_expires_at: input.conversion_expires_at,
    });
    this.results.set(result.result_id, result);
    this.snapshots.set(result.result_id, input);
    return Promise.resolve(structuredClone(result));
  }
  override getResultForAttempt(attemptRef: string) {
    const attempt = this.attemptByRef(attemptRef);
    const result = this.results.get(attempt.result_summary_id!);
    return Promise.resolve(result ? structuredClone(result) : null);
  }
  override getOwnedResult(resultId: string, userId: string) {
    const result = this.results.get(resultId);
    return Promise.resolve(
      result && this.owners.get(resultId) === userId
        ? structuredClone(result)
        : null,
    );
  }
  override convertAnonymousTasteCard(
    input: Parameters<
      SupabaseTasteCardRepository["convertAnonymousTasteCard"]
    >[0],
  ) {
    const result = this.results.get(input.result_id);
    if (!result || result.snapshot_ref !== input.snapshot_ref) {
      return Promise.reject(new Error("missing anonymous result"));
    }
    const saved: TasteCardResultEnvelope = {
      ...result,
      ownership_state: "saved",
      conversion: null,
    };
    this.results.set(input.result_id, saved);
    this.owners.set(input.result_id, input.user_id);
    return Promise.resolve(structuredClone(saved));
  }
  revisions = 0;
  override loadRecordAnswers(recordId: string) {
    const input = [...this.snapshots.values()].find((stored) =>
      this.attemptByRef(stored.attempt_ref).reserved_record_id === recordId
    );
    return Promise.resolve(
      input
        ? structuredClone({
          questionnaire_version: input.request.questionnaire_version,
          answers: input.request.answers,
        })
        : null,
    );
  }
  override reviseCard(input: ReviseTasteCardInput) {
    const held = this.results.get(input.result_id);
    const finalized = this.snapshots.get(input.result_id);
    if (
      !held || !finalized || this.owners.get(input.result_id) !== input.user_id
    ) {
      return Promise.reject(new TasteCardRepositoryError("P0002"));
    }
    if (held.snapshot_ref !== input.base_snapshot_ref) {
      return Promise.reject(
        new TasteCardRepositoryError("P0001", "revision_conflict"),
      );
    }
    this.revisions += 1;
    // The record, the card's id and its date stay; what was written changes.
    const revised = parseTasteCardResultEnvelope({
      ...held,
      snapshot_ref: input.snapshot_ref,
      view: input.rendered_view,
    });
    this.results.set(input.result_id, revised);
    this.snapshots.set(input.result_id, {
      ...finalized,
      request: { ...finalized.request, answers: input.answers },
      snapshot_ref: input.snapshot_ref,
      semantic_snapshot: input.semantic_snapshot,
      rendered_view: input.rendered_view,
    });
    return Promise.resolve(structuredClone(revised));
  }
  override deleteOwnedRecord(resultId: string, userId: string) {
    if (this.owners.get(resultId) !== userId) return Promise.resolve(false);
    this.owners.delete(resultId);
    this.results.delete(resultId);
    this.snapshots.delete(resultId);
    return Promise.resolve(true);
  }
  letters = new Map<
    string,
    { state: TasteLettersState; changes: readonly LetterChange[] }
  >();
  override loadTasteLetterRecords(userId: string) {
    const records: LetterRecord[] = [];
    for (const [resultId, input] of this.snapshots) {
      if (this.owners.get(resultId) !== userId) continue;
      records.push({
        record_id: this.attemptByRef(input.attempt_ref).reserved_record_id,
        product_name: input.semantic_snapshot.record.product.name,
        recorded_at: input.generated_at,
        marks: marksOf(input.semantic_snapshot.record),
      });
    }
    return Promise.resolve({
      records,
      source_record_ids: records.map((record) => record.record_id),
    });
  }
  override saveTasteLetters(
    userId: string,
    state: TasteLettersState,
    changes: readonly LetterChange[],
    _sourceRecordIds: readonly string[],
  ) {
    this.letters.set(userId, structuredClone({ state, changes }));
    return Promise.resolve();
  }
  override refreshConversionExpiry(
    input: {
      attempt_ref: string;
      conversion_key_version: string;
      conversion_expires_at: string;
    },
  ) {
    Object.assign(this.attemptByRef(input.attempt_ref), {
      conversion_key_version: input.conversion_key_version,
      conversion_expires_at: input.conversion_expires_at,
    });
    return Promise.resolve();
  }
  override markRetryable(
    input: {
      attempt_ref: string;
      error_code: RetryableErrorCode;
      retry_after: string;
    },
  ): Promise<void> {
    Object.assign(this.attemptByRef(input.attempt_ref), {
      state: "retryable",
      error_code: input.error_code,
      retry_after: input.retry_after,
    });
    return Promise.resolve();
  }
  private attemptByRef(ref: string): TasteCardAttempt {
    const attempt = [...this.attempts.values()].find((item) =>
      item.attempt_ref === ref
    );
    if (!attempt) throw new Error("missing attempt");
    return attempt;
  }
}

/** Dependencies with a fixed clock and sequential ids, for repeatable cards. */
export function testDependencies(
  repository: MemoryTasteCardRepository,
  now = new Date(instant),
): TasteCardOrchestratorDependencies {
  let count = 0;
  return {
    repository,
    now: () => now,
    random_uuid: () =>
      `90000000-0000-4000-8000-${String(++count).padStart(12, "0")}`,
    token_signer: new HmacConversionTokenSigner(
      "local-test-only-not-a-real-signing-secret",
      "local",
      900,
      () => now,
    ),
  };
}

/** The marks one record puts on the letters' rulers. */
export function marksOf(
  record: Parameters<typeof readRecord>[0],
) {
  return marksFromRecord(readRecord(record));
}
