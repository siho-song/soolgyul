import { stableId } from "./canonical.ts";
import { catalogProduct } from "../record/record_builder.ts";
import { bundledSensoryKnowledge } from "../dictionary/sensory_knowledge.ts";
import { parseTasteCardResultEnvelope } from "./serialization.ts";
import type { CardFacts } from "../facts/facts.ts";
import type {
  SensoryProduct,
  SensoryRecord,
} from "../record/sensory_record.ts";
import {
  type LetterChange,
  type LetterRecord,
  letterVotes,
  type TasteLettersState,
} from "../taste_letters.ts";
import type {
  AlcoholIdentificationView,
  CreateTasteCardResultRequest,
  RetryableErrorCode,
  TASTE_CARD_WIRE_SCHEMA_VERSION,
  TasteCardResultEnvelope,
  TasteCardView,
} from "./types.ts";
import { boundedFetch, serviceRoleHeaders } from "../../supabase.ts";

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
  }
  | { status: "unidentified" }
  | { status: "unavailable_transient" };

/** The private snapshot that reproduces a card: the record and what was read from it. */
export type TasteCardSnapshot = {
  engine_version: string;
  record: SensoryRecord;
  facts: CardFacts;
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
  getResultForAttempt(attemptRef: string): Promise<TasteCardResultEnvelope>;
  getOwnedResult(
    resultId: string,
    userId: string,
  ): Promise<TasteCardResultEnvelope | null>;
  convertAnonymousTasteCard(
    input: ConvertAnonymousTasteCardInput,
  ): Promise<TasteCardResultEnvelope>;
  /**
   * Marks the record behind the account's card [resultId] deleted; false when
   * the card is not the account's or is already gone.
   */
  deleteOwnedRecord(resultId: string, userId: string): Promise<boolean>;
  /**
   * Every final card of the account: one letter vote per record that can
   * vote, and the ids of all the records read.
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

export class TasteCardRepositoryError extends Error {
  constructor(public readonly code: string, message = code) {
    super(message);
    this.name = "TasteCardRepositoryError";
  }
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
            "&select=id,name_ko,name_en,abv_percent,region_key,style_key," +
            "ingredient_keys,production_process_keys,grape_variety_keys," +
            "category:alcohol_categories(category_key)&limit=1",
        ),
        this.rest<Record<string, unknown>[]>(
          `alcohol_tasting_profiles?alcohol_item_id=eq.${id}` +
            "&select=alcohol_item_id,aroma_note,palate_note," +
            "aroma_tags,palate_tags,finish_tags," +
            "sweetness,acidity,bitterness,astringency,body," +
            "carbonation,aroma_intensity,finish_length,finish_cleanliness," +
            "level_sources&limit=1",
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
      return {
        status: "ready",
        name: name.trim(),
        product: catalogProduct(item, profile, bundledSensoryKnowledge),
        style_label: typeof styleLabel === "string" && styleLabel.trim()
          ? styleLabel.trim()
          : null,
        abv_percent: typeof item.abv_percent === "number"
          ? item.abv_percent
          : null,
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
  ): Promise<TasteCardResultEnvelope> {
    const rows = await this.rpc<Record<string, unknown>[]>(
      "soolgyul_get_taste_card_result_for_attempt",
      { target_attempt_ref: attemptRef },
    );
    const value = Array.isArray(rows) ? rows[0] : rows;
    return parseStoredEnvelope(value);
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
    const rows = await this.rest<Record<string, unknown>[]>(
      "taste_cards?select=drink_record_id,facts:semantic_snapshot->facts," +
        "drink_records!inner(user_id,created_at)" +
        `&drink_records.user_id=eq.${encodeURIComponent(userId)}` +
        "&lifecycle=eq.final" +
        "&order=snapshot_created_at.asc",
    );
    const records: LetterRecord[] = [];
    const sourceRecordIds: string[] = [];
    for (const row of rows) {
      const facts = row.facts as CardFacts | null;
      const record = row.drink_records as { created_at?: unknown } | null;
      if (typeof row.drink_record_id === "string") {
        sourceRecordIds.push(row.drink_record_id);
      }
      // A card from before the engine kept its facts cannot vote.
      if (
        typeof row.drink_record_id !== "string" || !facts ||
        !Array.isArray(facts.reactions) ||
        typeof record?.created_at !== "string"
      ) continue;
      records.push({
        record_id: row.drink_record_id,
        product_name: facts.record.product_name,
        recorded_at: record.created_at,
        votes: letterVotes(facts),
      });
    }
    return { records, source_record_ids: sourceRecordIds };
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
    const response = await this.fetch_impl(
      `${this.supabase_url}/rest/v1/${path}`,
      {
        ...init,
        headers: {
          ...serviceRoleHeaders(this.service_role_key),
          ...init.headers,
        },
      },
    );
    return await parseResponse<T>(response);
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
    error_code: row.error_code === null ? null : enumValue<RetryableErrorCode>(
      row.error_code,
      ["catalog_unavailable", "engine_temporarily_unavailable"],
      "attempt_error_invalid",
    ),
    retry_after: nullableString(row.retry_after),
    result_summary_id: nullableString(row.result_summary_id),
    claim_snapshot_id: nullableString(row.claim_snapshot_id),
    conversion_key_version: nullableString(row.conversion_key_version),
    conversion_expires_at: nullableString(row.conversion_expires_at),
    created_at: requiredString(row.created_at, "attempt_created_at_missing"),
    updated_at: requiredString(row.updated_at, "attempt_updated_at_missing"),
  };
}

function parseStoredEnvelope(value: unknown): TasteCardResultEnvelope {
  const row = asRecord(value);
  const ownershipState = row.ownership_state === "anonymous"
    ? "anonymous" as const
    : "saved" as const;
  // Stored anonymous rows intentionally have no bearer token. Validate the
  // immutable snapshot as a saved envelope first; the orchestrator issues a
  // fresh conversion token before the value crosses the public boundary.
  const parsed = parseTasteCardResultEnvelope({
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

async function parseResponse<T>(response: Response): Promise<T> {
  const text = await response.text();
  const body = text ? JSON.parse(text) : null;
  if (!response.ok) {
    const error = asRecord(body);
    throw new TasteCardRepositoryError(
      typeof error.code === "string" ? error.code : `http_${response.status}`,
      typeof error.message === "string"
        ? error.message
        : "repository_request_failed",
    );
  }
  return body as T;
}

function isTransient(error: unknown): boolean {
  return error instanceof TasteCardRepositoryError &&
    (error.code.startsWith("http_5") || error.code === "57014" ||
      error.code === "08006");
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
