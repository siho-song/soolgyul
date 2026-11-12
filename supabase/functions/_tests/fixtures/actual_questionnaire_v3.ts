import snapshot from "./taste_card_actual_questionnaire_v3.json" with {
  type: "json",
};
import requests from "./taste_card_actual_requests_v3.json" with {
  type: "json",
};
import { HmacConversionTokenSigner } from "../../_shared/taste_card/service/conversion_token.ts";
import type { TasteCardOrchestratorDependencies } from "../../_shared/taste_card/service/orchestrator.ts";
import {
  type BeginTasteCardAttemptInput,
  type FinalizeTasteCardGenerationInput,
  SupabaseTasteCardRepository,
  type TasteCardAttempt,
} from "../../_shared/taste_card/service/repository.ts";
import { parseTasteCardResultEnvelope } from "../../_shared/taste_card/service/serialization.ts";
import {
  type LetterChange,
  letterMarks,
  type LetterRecord,
  type TasteLettersState,
} from "../../_shared/taste_card/taste_letters.ts";
import type {
  RetryableErrorCode,
  TasteCardResultEnvelope,
} from "../../_shared/taste_card/service/types.ts";

export const ACTUAL_REQUESTS_V3 = requests;
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

/**
 * Real HTTP source parsing (PostgREST rows → product) and real orchestration;
 * only persistence is in memory, so a test can read what was finalized.
 */
export class ActualQuestionnaireRepository extends SupabaseTasteCardRepository {
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
      const identifier = (url.searchParams.get("id") ??
        url.searchParams.get("alcohol_item_id"))?.replace(/^eq\./, "");
      let data: unknown;
      if (table === "alcohol_items") {
        data = (rows.items ?? snapshot.items).filter((item) =>
          item.id === identifier
        );
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
    return Promise.resolve(
      structuredClone(this.results.get(attempt.result_summary_id!)!),
    );
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
        product_name: input.semantic_snapshot.facts.record.product_name,
        recorded_at: input.generated_at,
        marks: letterMarks(input.semantic_snapshot.facts),
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
  repository: ActualQuestionnaireRepository,
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
