import { stableId } from "../../canonical.ts";
import { catalogProduct } from "../../record_reading/record/record_builder.ts";
import { parseTasteCardResultEnvelope } from "./serialization.ts";
import {
  CATALOG_ITEM_COLUMNS,
  loadRecordReadings,
  TASTING_PROFILE_COLUMNS,
} from "../../record_reading/load_record_readings.ts";
import type { NoteBottle } from "../summary/note.ts";
import type {
  SensoryProduct,
  SensoryRecord,
} from "../../record_reading/record/sensory_record.ts";
import type {
  LetterChange,
  LetterRecord,
  TasteLettersState,
} from "../../taste_letters/letters_from_marks.ts";
import { marksFromRecord } from "../../taste_letters/marks_from_record.ts";
import type {
  AlcoholIdentificationView,
  CreateTasteCardResultRequest,
  QuestionnaireAnswerInput,
  RetryableErrorCode,
  TASTE_CARD_WIRE_SCHEMA_VERSION,
  TasteCardResultEnvelope,
  TasteCardView,
} from "./types.ts";
import {
  boundedFetch,
  postgrestJson,
  serviceRoleHeaders,
} from "../../supabase.ts";
import { TasteCardContractError, TasteCardRepositoryError } from "./errors.ts";

export type TasteCardPrincipal =
  | { kind: "authenticated"; user_id: string }
  | {
    kind: "anonymous";
    anonymous_session_digest: string;
    /** Keyed digest of the address the request came from, when known. */
    client_address_digest?: string | null;
  };

type TasteCardProfileGate = {
  active: boolean;
  complete_adult_profile: boolean;
  display_name: string | null;
};

export type TasteCardAttempt = {
  attempt_ref: string;
  idempotency_key: string;
  request_digest: string;
  state: "processing" | "retryable" | "final";
  reserved_record_id: string;
  reserved_result_summary_id: string;
  error_code: RetryableErrorCode | null;
  retry_after: string | null;
  result_summary_id: string | null;
  claim_snapshot_id: string | null;
  conversion_key_version: string | null;
  conversion_expires_at: string | null;
  created_at: string;
  updated_at: string;
};

export type BeginTasteCardAttemptInput = {
  attempt_ref: string;
  principal: TasteCardPrincipal;
  idempotency_key: string;
  request_digest: string;
  reserved_record_id: string;
  reserved_result_summary_id: string;
};

/** What the catalog says about the item the reader matched. */
export type CatalogMatch =
  | {
    status: "ready";
    /** The item's own name; the card never takes its title from the caller. */
    name: string;
    product: SensoryProduct;
    /** Public URL of the catalog photo, when one is published. */
    image_reference: string | null;
    /** The style's name (준마이 긴조), when the item has a style. */
    style_label: string | null;
    abv_percent: number | null;
    /** What the 테이스팅 노트's head states of the bottle. */
    bottle: NoteBottle;
  }
  | { status: "unidentified" }
  | { status: "unavailable_transient" };

/** The private snapshot a card can be written again from: the answers and the bottle as they were read that day. */
export type TasteCardSnapshot = {
  engine_version: string;
  record: SensoryRecord;
};

export type FinalizeTasteCardGenerationInput = {
  wire_schema_version: typeof TASTE_CARD_WIRE_SCHEMA_VERSION;
  attempt_ref: string;
  principal: TasteCardPrincipal;
  request_digest: string;
  request: CreateTasteCardResultRequest;
  alcohol_identification: AlcoholIdentificationView;
  snapshot_ref: string;
  engine_version: string;
  semantic_snapshot: TasteCardSnapshot;
  rendered_view: TasteCardView;
  generated_at: string;
  conversion_key_version: string | null;
  conversion_expires_at: string | null;
};

/** A card written again from corrected answers, replacing what the record held. */
export type ReviseTasteCardInput = {
  wire_schema_version: typeof TASTE_CARD_WIRE_SCHEMA_VERSION;
  result_id: string;
  user_id: string;
  /** The card the revision was read from; a card changed since is not replaced. */
  base_snapshot_ref: string;
  answers: QuestionnaireAnswerInput[];
  snapshot_ref: string;
  engine_version: string;
  semantic_snapshot: TasteCardSnapshot;
  rendered_view: TasteCardView;
};

/** What a record was answered with, and under which questionnaire. */
export type RecordAnswers = {
  questionnaire_version: string;
  answers: QuestionnaireAnswerInput[];
};

type ConvertAnonymousTasteCardInput = {
  user_id: string;
  result_id: string;
  snapshot_ref: string;
  anonymous_session_digest: string;
  idempotency_key: string;
};

export interface TasteCardRepository {
  getProfileGate(userId: string): Promise<TasteCardProfileGate>;
  findAttempt(
    principal: TasteCardPrincipal,
    idempotencyKey: string,
  ): Promise<TasteCardAttempt | null>;
  beginAttempt(input: BeginTasteCardAttemptInput): Promise<TasteCardAttempt>;
  loadCatalog(alcoholItemId: string): Promise<CatalogMatch>;
  markRetryable(input: {
    attempt_ref: string;
    error_code: RetryableErrorCode;
    retry_after: string;
  }): Promise<void>;
  refreshConversionExpiry(input: {
    attempt_ref: string;
    conversion_key_version: string;
    conversion_expires_at: string;
  }): Promise<void>;
  finalizeGeneration(
    input: FinalizeTasteCardGenerationInput,
  ): Promise<TasteCardResultEnvelope>;
  /** The attempt's card; null when the card is gone (its record was deleted). */
  getResultForAttempt(
    attemptRef: string,
  ): Promise<TasteCardResultEnvelope | null>;
  getOwnedResult(
    resultId: string,
    userId: string,
  ): Promise<TasteCardResultEnvelope | null>;
  convertAnonymousTasteCard(
    input: ConvertAnonymousTasteCardInput,
  ): Promise<TasteCardResultEnvelope>;
  /** The answers of a record; null when the record is gone. */
  loadRecordAnswers(recordId: string): Promise<RecordAnswers | null>;
  /**
   * Replaces the account's card and its record's answers. Fails with
   * `revision_conflict` when the card is no longer the one revised.
   */
  reviseCard(input: ReviseTasteCardInput): Promise<TasteCardResultEnvelope>;
  /**
   * Marks the record behind the account's card [resultId] deleted; false when
   * the card is not the account's or is already gone.
   */
  deleteOwnedRecord(resultId: string, userId: string): Promise<boolean>;
  /**
   * Every record of the account that has a card: the letter marks its answers
   * put, and the ids of all the records read.
   */
  loadTasteLetterRecords(userId: string): Promise<TasteLetterSource>;
  /**
   * Replaces the account's four letters and the moments they changed. Fails
   * when [sourceRecordIds] are no longer the account's cards.
   */
  saveTasteLetters(
    userId: string,
    state: TasteLettersState,
    changes: readonly LetterChange[],
    sourceRecordIds: readonly string[],
  ): Promise<void>;
}

export type TasteLetterSource = {
  records: LetterRecord[];
  source_record_ids: string[];
};

type FetchLike = typeof fetch;

const CATALOG_IMAGE_BUCKET = "alcohol-product-images";

export class SupabaseTasteCardRepository implements TasteCardRepository {
  constructor(
    private readonly supabase_url: string,
    private readonly service_role_key: string,
    private readonly fetch_impl: FetchLike = boundedFetch,
  ) {
    if (!supabase_url || !service_role_key) {
      throw new Error("supabase_service_configuration_required");
    }
  }

  async getProfileGate(userId: string): Promise<TasteCardProfileGate> {
    const rows = await this.rest<Array<Record<string, unknown>>>(
      `users?id=eq.${encodeURIComponent(userId)}` +
        "&select=display_name,account_status&limit=1",
    );
    const row = rows[0];
    const active = row?.account_status === "active";
    const complete = active &&
      await this.rpc<boolean>("soolgyul_adult_profile_complete", {
          target_user_id: userId,
        }) === true;
    return {
      active,
      complete_adult_profile: complete,
      display_name: typeof row?.display_name === "string"
        ? row.display_name
        : null,
    };
  }

  async findAttempt(
    principal: TasteCardPrincipal,
    idempotencyKey: string,
  ): Promise<TasteCardAttempt | null> {
    const principalFilter = principal.kind === "authenticated"
      ? `owner_user_id=eq.${encodeURIComponent(principal.user_id)}`
      : `anonymous_session_digest=eq.${principal.anonymous_session_digest}`;
    const rows = await this.rest<Record<string, unknown>[]>(
      "taste_card_generation_attempts?" + principalFilter +
        `&idempotency_key=eq.${encodeURIComponent(idempotencyKey)}` +
        `&select=${attemptColumns}&limit=1`,
    );
    return rows[0] ? parseAttempt(rows[0]) : null;
  }

  async beginAttempt(
    input: BeginTasteCardAttemptInput,
  ): Promise<TasteCardAttempt> {
    const row = {
      attempt_ref: input.attempt_ref,
      idempotency_key: input.idempotency_key,
      owner_user_id: input.principal.kind === "authenticated"
        ? input.principal.user_id
        : null,
      anonymous_session_digest: input.principal.kind === "anonymous"
        ? input.principal.anonymous_session_digest
        : null,
      client_address_digest: input.principal.kind === "anonymous"
        ? input.principal.client_address_digest ?? null
        : null,
      request_digest: input.request_digest,
      reserved_record_id: input.reserved_record_id,
      reserved_result_summary_id: input.reserved_result_summary_id,
      state: "processing",
    };
    try {
      const rows = await this.rest<Record<string, unknown>[]>(
        `taste_card_generation_attempts?select=${attemptColumns}`,
        {
          method: "POST",
          headers: { Prefer: "return=representation" },
          body: JSON.stringify(row),
        },
      );
      if (!rows[0]) throw new TasteCardRepositoryError("attempt_create_failed");
      return parseAttempt(rows[0]);
    } catch (error) {
      if (
        error instanceof TasteCardRepositoryError &&
        error.message === "anonymous_generation_limit_reached"
      ) {
        throw new TasteCardRepositoryError(
          "anonymous_generation_limit_reached",
        );
      }
      if (
        !(error instanceof TasteCardRepositoryError) || error.code !== "23505"
      ) {
        throw error;
      }
      const existing = await this.findAttempt(
        input.principal,
        input.idempotency_key,
      );
      if (!existing) throw error;
      return existing;
    }
  }

  /**
   * Reads the published item, its tasting profile and its photo in one round,
   * then its style's name.
   * Never borrows a related product's profile. Sensory descriptions come from
   * the bundled dictionary, not from a table.
   */
  async loadCatalog(alcoholItemId: string): Promise<CatalogMatch> {
    try {
      const id = encodeURIComponent(alcoholItemId);
      const [itemRows, profileRows, mediaRows] = await Promise.all([
        this.rest<Record<string, unknown>[]>(
          `alcohol_items?id=eq.${id}&publish_status=eq.published` +
            `&select=${CATALOG_ITEM_COLUMNS}&limit=1`,
        ),
        this.rest<Record<string, unknown>[]>(
          `alcohol_tasting_profiles?alcohol_item_id=eq.${id}` +
            `&select=${TASTING_PROFILE_COLUMNS}&limit=1`,
        ),
        this.rest<Record<string, unknown>[]>(
          `catalog_media_assets?alcohol_item_id=eq.${id}` +
            "&publish_status=eq.published&select=alcohol_item_id,media_path" +
            "&limit=1",
        ),
      ]);
      const item = itemRows[0];
      if (!item || item.id !== alcoholItemId) return { status: "unidentified" };
      const profile = profileRows.find((row) =>
        row.alcohol_item_id === alcoholItemId
      ) ?? null;
      const media = mediaRows.find((row) =>
        row.alcohol_item_id === alcoholItemId
      );
      const styleRows = typeof item.style_key === "string"
        ? await this.rest<Record<string, unknown>[]>(
          "catalog_taxonomy?term_type=eq.style&term_key=eq." +
            `${encodeURIComponent(item.style_key)}&select=label_ko&limit=1`,
        )
        : [];
      const styleLabel = styleRows[0]?.label_ko;
      const name = [item.name_ko, item.name_en].find((value) =>
        typeof value === "string" && value.trim() !== ""
      );
      if (typeof name !== "string") return { status: "unidentified" };
      const label = typeof styleLabel === "string" && styleLabel.trim()
        ? styleLabel.trim()
        : null;
      return {
        status: "ready",
        name: name.trim(),
        product: catalogProduct(item, profile),
        style_label: label,
        abv_percent: typeof item.abv_percent === "number"
          ? item.abv_percent
          : null,
        bottle: {
          style_label: label,
          name_en: typeof item.name_en === "string" ? item.name_en : null,
          producer: producerName(item.producer),
          region_key: typeof item.region_key === "string"
            ? item.region_key
            : null,
          vintage_year: positive(item.vintage_year),
          age_years: positive(item.age_statement_years),
          grape_keys: keys(item.grape_variety_keys),
          ingredient_keys: keys(item.ingredient_keys),
        },
        image_reference: typeof media?.media_path === "string"
          ? this.publicCatalogImageUrl(media.media_path)
          : null,
      };
    } catch (error) {
      if (isTransient(error)) return { status: "unavailable_transient" };
      throw error;
    }
  }

  async markRetryable(input: {
    attempt_ref: string;
    error_code: RetryableErrorCode;
    retry_after: string;
  }): Promise<void> {
    await this.rest(
      `taste_card_generation_attempts?attempt_ref=eq.${
        encodeURIComponent(input.attempt_ref)
      }`,
      {
        method: "PATCH",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify({
          state: "retryable",
          error_code: input.error_code,
          retry_after: input.retry_after,
          updated_at: new Date().toISOString(),
        }),
      },
    );
  }

  async refreshConversionExpiry(input: {
    attempt_ref: string;
    conversion_key_version: string;
    conversion_expires_at: string;
  }): Promise<void> {
    await this.rest(
      `taste_card_generation_attempts?attempt_ref=eq.${
        encodeURIComponent(input.attempt_ref)
      }`,
      {
        method: "PATCH",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify({
          conversion_key_version: input.conversion_key_version,
          conversion_expires_at: input.conversion_expires_at,
          updated_at: new Date().toISOString(),
        }),
      },
    );
  }

  async finalizeGeneration(
    input: FinalizeTasteCardGenerationInput,
  ): Promise<TasteCardResultEnvelope> {
    const rows = await this.rpc<Record<string, unknown>[]>(
      "soolgyul_finalize_taste_card_generation",
      { input_bundle: input },
    );
    const value = Array.isArray(rows) ? rows[0] : rows;
    return parseStoredEnvelope(value);
  }

  async getResultForAttempt(
    attemptRef: string,
  ): Promise<TasteCardResultEnvelope | null> {
    const rows = await this.rpc<Record<string, unknown>[]>(
      "soolgyul_get_taste_card_result_for_attempt",
      { target_attempt_ref: attemptRef },
    );
    const value = Array.isArray(rows) ? rows[0] : rows;
    return value ? parseStoredEnvelope(value) : null;
  }

  async getOwnedResult(
    resultId: string,
    userId: string,
  ): Promise<TasteCardResultEnvelope | null> {
    try {
      const rows = await this.rpc<Record<string, unknown>[]>(
        "soolgyul_get_owned_taste_card_result",
        { target_result_summary_id: resultId, target_user_id: userId },
      );
      const value = Array.isArray(rows) ? rows[0] : rows;
      return value ? parseStoredEnvelope(value) : null;
    } catch (error) {
      if (error instanceof TasteCardRepositoryError && error.code === "P0002") {
        return null;
      }
      throw error;
    }
  }

  async convertAnonymousTasteCard(
    input: ConvertAnonymousTasteCardInput,
  ): Promise<TasteCardResultEnvelope> {
    await this.rpc("soolgyul_convert_anonymous_taste_card", {
      target_user_id: input.user_id,
      target_result_summary_id: input.result_id,
      target_anonymous_session_digest: input.anonymous_session_digest,
      target_idempotency_key: input.idempotency_key,
    });
    const result = await this.getOwnedResult(input.result_id, input.user_id);
    if (!result || result.snapshot_ref !== input.snapshot_ref) {
      throw new TasteCardRepositoryError("converted_snapshot_mismatch");
    }
    return result;
  }

  async loadRecordAnswers(recordId: string): Promise<RecordAnswers | null> {
    const rows = await this.rest<Record<string, unknown>[]>(
      `drink_records?id=eq.${encodeURIComponent(recordId)}` +
        "&select=questionnaire_version," +
        "answers:drink_record_answers(question_key,selected_option_keys)" +
        "&limit=1",
    );
    const row = rows[0];
    if (!row || typeof row.questionnaire_version !== "string") return null;
    const answers = Array.isArray(row.answers) ? row.answers : [];
    return {
      questionnaire_version: row.questionnaire_version,
      answers: answers.flatMap((answer: Record<string, unknown>) =>
        typeof answer.question_key === "string"
          ? [{
            question_key: answer.question_key,
            selected_option_keys: keys(answer.selected_option_keys),
            free_text: null,
          }]
          : []
      ),
    };
  }

  async reviseCard(
    input: ReviseTasteCardInput,
  ): Promise<TasteCardResultEnvelope> {
    const rows = await this.rpc<Record<string, unknown>[]>(
      "soolgyul_revise_taste_card",
      { input_bundle: input },
    );
    const value = Array.isArray(rows) ? rows[0] : rows;
    return parseStoredEnvelope(value);
  }

  async deleteOwnedRecord(resultId: string, userId: string): Promise<boolean> {
    try {
      await this.rpc("soolgyul_delete_owned_drink_record", {
        target_result_summary_id: resultId,
        target_user_id: userId,
      });
      return true;
    } catch (error) {
      if (error instanceof TasteCardRepositoryError && error.code === "P0002") {
        return false;
      }
      throw error;
    }
  }

  async loadTasteLetterRecords(userId: string): Promise<TasteLetterSource> {
    // Every record that has a card: the store refuses letters whose source
    // list misses one. The marks come from the answers, not from the card.
    const answered = await loadRecordReadings(
      (path) => this.rest(path),
      userId,
    );
    return {
      // A record that cannot be read puts no mark.
      records: answered.flatMap(({ record_id, recorded_at, reading }) =>
        reading
          ? [{
            record_id,
            product_name: reading.bottle.name,
            recorded_at,
            marks: marksFromRecord(reading),
          }]
          : []
      ),
      source_record_ids: answered.map((record) => record.record_id),
    };
  }

  async saveTasteLetters(
    userId: string,
    state: TasteLettersState,
    changes: readonly LetterChange[],
    sourceRecordIds: readonly string[],
  ): Promise<void> {
    await this.rpc("soolgyul_save_taste_letters", {
      target_user_id: userId,
      state,
      changes,
      source_record_ids: sourceRecordIds,
    });
  }

  private publicCatalogImageUrl(storageObjectPath: string): string {
    if (/^https:\/\//i.test(storageObjectPath)) return storageObjectPath;
    const encodedPath = storageObjectPath
      .split("/")
      .map((segment) => encodeURIComponent(segment))
      .join("/");
    return `${this.supabase_url}/storage/v1/object/public/${
      encodeURIComponent(CATALOG_IMAGE_BUCKET)
    }/${encodedPath}`;
  }

  private async rest<T = unknown>(
    path: string,
    init: RequestInit = {},
  ): Promise<T> {
    return await postgrestJson<T>(
      this.fetch_impl,
      `${this.supabase_url}/rest/v1/${path}`,
      {
        ...init,
        headers: {
          ...serviceRoleHeaders(this.service_role_key),
          ...init.headers,
        },
      },
      (code, message, transient) =>
        new TasteCardRepositoryError(code, message, transient),
    );
  }

  private async rpc<T = unknown>(name: string, body: unknown): Promise<T> {
    return await this.rest<T>(`rpc/${name}`, {
      method: "POST",
      body: JSON.stringify(body),
    });
  }
}

const attemptColumns = [
  "attempt_ref",
  "idempotency_key",
  "request_digest",
  "state",
  "reserved_record_id",
  "reserved_result_summary_id",
  "error_code",
  "retry_after",
  "result_summary_id",
  "claim_snapshot_id",
  "conversion_key_version",
  "conversion_expires_at",
  "created_at",
  "updated_at",
].join(",");

/** The embedded producer row's name, Korean first. */
function producerName(value: unknown): string | null {
  const row = value && typeof value === "object"
    ? value as Record<string, unknown>
    : {};
  const name = [row.name_ko, row.name_en].find((v) =>
    typeof v === "string" && v.trim() !== ""
  );
  return typeof name === "string" ? name.trim() : null;
}

/** A key column as the catalog keeps it, in its own order. */
function keys(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((key): key is string => typeof key === "string")
    : [];
}

/** A year or an age as the catalog keeps it; PostgREST sends a numeric as a number or a string. */
function positive(value: unknown): number | null {
  const number = typeof value === "string" ? Number(value) : value;
  return typeof number === "number" && Number.isFinite(number) && number > 0
    ? number
    : null;
}

function parseAttempt(row: Record<string, unknown>): TasteCardAttempt {
  return {
    attempt_ref: requiredString(row.attempt_ref, "attempt_ref_missing"),
    idempotency_key: requiredString(
      row.idempotency_key,
      "idempotency_key_missing",
    ),
    request_digest: requiredString(
      row.request_digest,
      "request_digest_missing",
    ),
    state: enumValue(
      row.state,
      ["processing", "retryable", "final"],
      "attempt_state_invalid",
    ),
    reserved_record_id: requiredString(
      row.reserved_record_id,
      "reserved_record_id_missing",
    ),
    reserved_result_summary_id: requiredString(
      row.reserved_result_summary_id,
      "reserved_result_summary_id_missing",
    ),
    error_code: parseAttemptErrorCode(row.error_code),
    retry_after: nullableString(row.retry_after),
    result_summary_id: nullableString(row.result_summary_id),
    claim_snapshot_id: nullableString(row.claim_snapshot_id),
    conversion_key_version: nullableString(row.conversion_key_version),
    conversion_expires_at: nullableString(row.conversion_expires_at),
    created_at: requiredString(row.created_at, "attempt_created_at_missing"),
    updated_at: requiredString(row.updated_at, "attempt_updated_at_missing"),
  };
}

/**
 * The table also allows `history_unavailable`, which nothing writes any more;
 * it reads as the general retry the app knows.
 */
function parseAttemptErrorCode(value: unknown): RetryableErrorCode | null {
  if (value === null) return null;
  const code = enumValue(
    value,
    [
      "catalog_unavailable",
      "history_unavailable",
      "engine_temporarily_unavailable",
    ],
    "attempt_error_invalid",
  );
  return code === "history_unavailable"
    ? "engine_temporarily_unavailable"
    : code;
}

/**
 * A stored card read back for the client. Stored data that does not read is
 * the server's fault, never the caller's: it fails as an internal error.
 */
function parseStoredEnvelope(value: unknown): TasteCardResultEnvelope {
  const row = asRecord(value);
  const ownershipState = row.ownership_state === "anonymous"
    ? "anonymous" as const
    : "saved" as const;
  // Stored anonymous rows intentionally have no bearer token. Validate the
  // immutable snapshot as a saved envelope first; the orchestrator issues a
  // fresh conversion token before the value crosses the public boundary.
  const parsed = parseStoredWire({
    wire_schema_version: requiredString(
      row.wire_schema_version,
      "stored_wire_schema_version_missing",
    ),
    result_id: requiredString(row.result_id, "stored_result_id_missing"),
    record_id: nullableString(row.record_id),
    snapshot_ref: requiredString(
      row.snapshot_ref,
      "stored_snapshot_ref_missing",
    ),
    ownership_state: "saved",
    alcohol_identification: asRecord(row.alcohol_identification),
    view: asRecord(row.rendered_snapshot),
    conversion: null,
    created_at: requiredString(row.created_at, "stored_created_at_missing"),
  });
  return ownershipState === "anonymous"
    ? { ...parsed, ownership_state: ownershipState }
    : parsed;
}

function parseStoredWire(value: unknown): TasteCardResultEnvelope {
  try {
    return parseTasteCardResultEnvelope(value);
  } catch (error) {
    if (error instanceof TasteCardContractError) {
      throw new TasteCardRepositoryError(
        "stored_result_invalid",
        error.message,
      );
    }
    throw error;
  }
}

function isTransient(error: unknown): boolean {
  return error instanceof TasteCardRepositoryError && error.transient;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function requiredString(value: unknown, code: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new TasteCardRepositoryError(code);
  }
  return value;
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function enumValue<T extends string>(
  value: unknown,
  allowed: readonly T[],
  code: string,
): T {
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    throw new TasteCardRepositoryError(code);
  }
  return value as T;
}

export async function attemptRefFor(
  principal: TasteCardPrincipal,
  idempotencyKey: string,
): Promise<string> {
  return await stableId("taste-card-attempt", { principal, idempotencyKey });
}
