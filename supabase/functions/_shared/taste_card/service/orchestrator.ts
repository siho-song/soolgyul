import { canonicalJson, sha256Hex, stableId } from "./canonical.ts";
import { buildSensoryRecord, categoryLabel } from "../record/record_builder.ts";
import { withCardTerms } from "../writing/terms.ts";
import { CARD_ENGINE_VERSION, writeCard } from "../writing/card_text.ts";
import {
  anonymousSessionDigest,
  type ConversionTokenSigner,
} from "./conversion_token.ts";
import {
  attemptRefFor,
  type CatalogMatch,
  type TasteCardPrincipal,
  type TasteCardRepository,
  type TasteCardSnapshot,
} from "./repository.ts";
import {
  SENSORY_QUESTIONNAIRE_VERSION,
  SensoryQuestionnaireError,
  validateSensoryAnswers,
  verifySensoryRegistry,
} from "../record/questionnaire.ts";
import { computeTasteLetters } from "../taste_letters.ts";
import {
  type AnonymousTasteCardConversionRequest,
  type CreateTasteCardResultRequest,
  type CreateTasteCardResultResponse,
  type RetryableErrorCode,
  TASTE_CARD_WIRE_SCHEMA_VERSION,
  type TasteCardResultEnvelope,
  type TasteCardView,
} from "./types.ts";

export type TasteCardAuthContext = {
  user_id: string;
};

export type TasteCardOrchestratorDependencies = {
  repository: TasteCardRepository;
  token_signer: ConversionTokenSigner;
  now?: () => Date;
  random_uuid?: () => string;
};

export class TasteCardOrchestrationError extends Error {
  constructor(public readonly code: string, message = code) {
    super(message);
    this.name = "TasteCardOrchestrationError";
  }
}

/** Anonymous results live 30 days from the first server receipt. */
const ANONYMOUS_RESULT_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

/** How long a caller waits before retrying after a transient catalog failure. */
const RETRY_AFTER_MS = 30_000;

/** The stored view with the dictionary's explanations of its words attached. */
function explained(stored: TasteCardResultEnvelope): TasteCardResultEnvelope {
  return { ...stored, view: withCardTerms(stored.view) };
}

export async function createTasteCardResult(
  dependencies: TasteCardOrchestratorDependencies,
  request: CreateTasteCardResultRequest,
  auth: TasteCardAuthContext | null,
): Promise<CreateTasteCardResultResponse> {
  const now = dependencies.now ?? (() => new Date());
  const randomUuid = dependencies.random_uuid ?? (() => crypto.randomUUID());
  const principal = await principalFor(request, auth);
  const userName = await assertPrincipalReady(dependencies, principal);
  const requestDigest = await sha256Hex(canonicalJson(request));
  let attempt = await dependencies.repository.findAttempt(
    principal,
    request.idempotency_key,
  );
  if (attempt && attempt.request_digest !== requestDigest) {
    throw new TasteCardOrchestrationError("idempotency_conflict");
  }
  if (attempt?.state === "final") {
    const stored = await dependencies.repository.getResultForAttempt(
      attempt.attempt_ref,
    );
    return {
      state: "final",
      result: await restoreConversionForReplay(
        dependencies,
        request,
        principal,
        attempt,
        stored,
        now(),
      ),
    };
  }
  if (
    attempt?.state === "retryable" && attempt.retry_after !== null &&
    Date.parse(attempt.retry_after) > now().getTime()
  ) {
    return retryableResponse(attempt, now());
  }

  let createdHere = false;
  if (!attempt) {
    const input = {
      attempt_ref: await attemptRefFor(principal, request.idempotency_key),
      principal,
      idempotency_key: request.idempotency_key,
      request_digest: requestDigest,
      reserved_record_id: randomUuid(),
      reserved_result_summary_id: randomUuid(),
    };
    attempt = await dependencies.repository.beginAttempt(input);
    if (attempt.request_digest !== requestDigest) {
      throw new TasteCardOrchestrationError("idempotency_conflict");
    }
    createdHere = attempt.reserved_record_id === input.reserved_record_id;
  }
  if (attempt.state === "final") {
    const stored = await dependencies.repository.getResultForAttempt(
      attempt.attempt_ref,
    );
    return {
      state: "final",
      result: await restoreConversionForReplay(
        dependencies,
        request,
        principal,
        attempt,
        stored,
        now(),
      ),
    };
  }
  if (
    attempt.state === "processing" && !createdHere &&
    now().getTime() - Date.parse(attempt.updated_at) < 60_000
  ) {
    return {
      state: "retryable",
      idempotency_key: request.idempotency_key,
      attempt_ref: attempt.attempt_ref,
      error_code: "engine_temporarily_unavailable",
      retry_after_ms: 1000,
    };
  }

  await assertQuestionnaire(request);
  const identification = request.alcohol_identification;
  const catalog: CatalogMatch = await dependencies.repository.loadCatalog(
    identification.alcohol_item_id,
  );
  if (catalog.status === "unavailable_transient") {
    return await markRetryable(
      dependencies,
      attempt,
      "catalog_unavailable",
      now(),
    );
  }
  // An item the catalog cannot serve (unpublished since the search) has no
  // product to write a card from; the reader searches again.
  if (catalog.status === "unidentified") {
    throw new TasteCardOrchestrationError("catalog_item_not_found");
  }
  const product = catalog.product;
  const record = buildSensoryRecord(
    attempt.reserved_record_id,
    request.answers,
    product,
  );
  const card = writeCard(record);
  const snapshot: TasteCardSnapshot = {
    engine_version: CARD_ENGINE_VERSION,
    record,
    facts: card.facts,
  };
  const snapshotRef = await stableId("taste-card-snapshot-v3", snapshot);
  const generatedAt = now().toISOString();
  const view: TasteCardView = {
    product: {
      drink_name_snapshot: identification.alcohol_name_snapshot,
      user_name: userName,
      image_reference: request.photo_asset_id !== null
        ? { source: "user_photo", reference: request.photo_asset_id }
        : catalog.image_reference !== null
        ? { source: "catalog", reference: catalog.image_reference }
        : null,
      category_label: categoryLabel(product.category),
      style_label: catalog.style_label,
      abv_percent: catalog.abv_percent,
    },
    bite: {
      nickname: card.nickname,
      tags: card.tags.map((t) => ({ ...t })),
      summary: card.summary,
      brief: card.brief,
      guide: card.guide,
    },
    positive: card.positive,
    burden: card.burden,
    balanced: card.balanced,
    metadata: {
      snapshot_ref: snapshotRef,
      schema_version: 3,
      engine_version: CARD_ENGINE_VERSION,
      generated_at: generatedAt,
      generated_from_record_ref: attempt.reserved_record_id,
    },
  };
  const issued = principal.kind === "anonymous"
    ? await issueConversion(
      dependencies,
      attempt,
      principal.anonymous_session_digest,
      {
        result_id: attempt.reserved_result_summary_id,
        snapshot_ref: snapshotRef,
      },
      now(),
    )
    : null;
  const stored = await dependencies.repository.finalizeGeneration({
    wire_schema_version: TASTE_CARD_WIRE_SCHEMA_VERSION,
    attempt_ref: attempt.attempt_ref,
    principal,
    request_digest: requestDigest,
    request,
    alcohol_identification: { ...identification },
    snapshot_ref: snapshotRef,
    engine_version: CARD_ENGINE_VERSION,
    semantic_snapshot: snapshot,
    rendered_view: view,
    generated_at: generatedAt,
    conversion_key_version: issued
      ? dependencies.token_signer.key_version
      : null,
    conversion_expires_at: issued?.expires_at ?? null,
  });
  if (
    stored.result_id !== attempt.reserved_result_summary_id ||
    stored.snapshot_ref !== snapshotRef ||
    stored.view.metadata.snapshot_ref !== snapshotRef
  ) {
    throw new TasteCardOrchestrationError("persisted_identity_mismatch");
  }
  if (principal.kind === "authenticated") {
    await refreshTasteLetters(dependencies, principal.user_id);
  }
  return {
    state: "final",
    result: issued === null
      ? { ...explained(stored), ownership_state: "saved", conversion: null }
      : {
        ...explained(stored),
        ownership_state: "anonymous",
        conversion: {
          anonymous_session_id: request.anonymous_session_id!,
          conversion_token: issued.token,
        },
      },
  };
}

export async function convertAnonymousTasteCard(
  dependencies: TasteCardOrchestratorDependencies,
  request: AnonymousTasteCardConversionRequest,
  auth: TasteCardAuthContext,
): Promise<TasteCardResultEnvelope> {
  const profile = await dependencies.repository.getProfileGate(auth.user_id);
  if (!profile.active) {
    throw new TasteCardOrchestrationError("active_account_required");
  }
  if (!profile.complete_adult_profile) {
    throw new TasteCardOrchestrationError("complete_profile_required");
  }
  const sessionDigest = await anonymousSessionDigest(
    request.anonymous_session_id,
  );
  const claims = await dependencies.token_signer.verify(
    request.conversion_token,
  );
  if (
    claims.result_id !== request.result_id ||
    claims.anonymous_session_digest !== sessionDigest
  ) {
    throw new TasteCardOrchestrationError("conversion_token_claim_mismatch");
  }
  const result = await dependencies.repository.convertAnonymousTasteCard({
    user_id: auth.user_id,
    result_id: request.result_id,
    snapshot_ref: claims.snapshot_ref,
    anonymous_session_digest: sessionDigest,
    idempotency_key: request.idempotency_key,
  });
  if (result.snapshot_ref !== claims.snapshot_ref) {
    throw new TasteCardOrchestrationError("converted_snapshot_mismatch");
  }
  await refreshTasteLetters(dependencies, auth.user_id);
  return { ...explained(result), ownership_state: "saved", conversion: null };
}

/**
 * Deletes the record behind one of the account's saved cards, then recomputes
 * the account's 네 글자 without it.
 */
export async function deleteOwnedTasteCardRecord(
  dependencies: Pick<TasteCardOrchestratorDependencies, "repository">,
  resultId: string,
  auth: TasteCardAuthContext,
): Promise<{ deleted: true }> {
  const profile = await dependencies.repository.getProfileGate(auth.user_id);
  if (!profile.active) {
    throw new TasteCardOrchestrationError("active_account_required");
  }
  const deleted = await dependencies.repository.deleteOwnedRecord(
    resultId,
    auth.user_id,
  );
  if (!deleted) throw new TasteCardOrchestrationError("result_not_found");
  await refreshTasteLetters(dependencies, auth.user_id);
  return { deleted: true };
}

/**
 * Recomputes the account's 네 글자 from every saved card and stores them,
 * trying once more on a passing failure. The record change is already saved,
 * so a second failure is logged and the letters catch up on the next card
 * instead of failing the request.
 */
async function refreshTasteLetters(
  dependencies: Pick<TasteCardOrchestratorDependencies, "repository">,
  userId: string,
): Promise<void> {
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const records = await dependencies.repository.loadTasteLetterRecords(
        userId,
      );
      const { state, changes } = computeTasteLetters(records);
      await dependencies.repository.saveTasteLetters(userId, state, changes);
      return;
    } catch (error) {
      console.warn(
        `taste_letters: not refreshed, attempt ${attempt} (${
          error instanceof Error ? error.message : String(error)
        })`,
      );
    }
  }
}

export async function getOwnedTasteCardResult(
  dependencies: Pick<TasteCardOrchestratorDependencies, "repository">,
  resultId: string,
  auth: TasteCardAuthContext,
): Promise<TasteCardResultEnvelope> {
  const profile = await dependencies.repository.getProfileGate(auth.user_id);
  if (!profile.active) {
    throw new TasteCardOrchestrationError("active_account_required");
  }
  const result = await dependencies.repository.getOwnedResult(
    resultId,
    auth.user_id,
  );
  if (!result) throw new TasteCardOrchestrationError("result_not_found");
  return { ...explained(result), ownership_state: "saved", conversion: null };
}

/** The questionnaire the request answered must be the one the server writes cards from. */
async function assertQuestionnaire(
  request: CreateTasteCardResultRequest,
): Promise<void> {
  if (request.questionnaire_version !== SENSORY_QUESTIONNAIRE_VERSION) {
    throw new TasteCardOrchestrationError("questionnaire_contract_invalid");
  }
  try {
    await verifySensoryRegistry();
    validateSensoryAnswers(request.answers);
  } catch (error) {
    if (error instanceof SensoryQuestionnaireError) {
      throw new TasteCardOrchestrationError(
        "sensory_questionnaire_invalid",
        error.message,
      );
    }
    throw error;
  }
}

async function markRetryable(
  dependencies: TasteCardOrchestratorDependencies,
  attempt: { attempt_ref: string; idempotency_key: string },
  errorCode: RetryableErrorCode,
  now: Date,
): Promise<CreateTasteCardResultResponse> {
  const retryAfter = new Date(now.getTime() + RETRY_AFTER_MS);
  await dependencies.repository.markRetryable({
    attempt_ref: attempt.attempt_ref,
    error_code: errorCode,
    retry_after: retryAfter.toISOString(),
  });
  return {
    state: "retryable",
    idempotency_key: attempt.idempotency_key,
    attempt_ref: attempt.attempt_ref,
    error_code: errorCode,
    retry_after_ms: RETRY_AFTER_MS,
  };
}

async function principalFor(
  request: CreateTasteCardResultRequest,
  auth: TasteCardAuthContext | null,
): Promise<TasteCardPrincipal> {
  if (auth !== null) {
    if (request.anonymous_session_id !== null) {
      throw new TasteCardOrchestrationError(
        "authenticated_anonymous_session_forbidden",
      );
    }
    return { kind: "authenticated", user_id: auth.user_id };
  }
  if (request.anonymous_session_id === null) {
    throw new TasteCardOrchestrationError("anonymous_session_required");
  }
  return {
    kind: "anonymous",
    anonymous_session_digest: await anonymousSessionDigest(
      request.anonymous_session_id,
    ),
  };
}

/** Account gates apply to every request, including replays of stored results. */
async function assertPrincipalReady(
  dependencies: Pick<TasteCardOrchestratorDependencies, "repository">,
  principal: TasteCardPrincipal,
): Promise<string | null> {
  if (principal.kind === "anonymous") return null;
  const profile = await dependencies.repository.getProfileGate(
    principal.user_id,
  );
  if (!profile.active) {
    throw new TasteCardOrchestrationError("active_account_required");
  }
  if (!profile.complete_adult_profile) {
    throw new TasteCardOrchestrationError("complete_profile_required");
  }
  return profile.display_name;
}

/**
 * Issues a conversion token that never outlives the anonymous retention
 * window counted from the attempt's first receipt, so retries and token
 * refreshes cannot extend it (ADR-150).
 */
async function issueConversion(
  dependencies: TasteCardOrchestratorDependencies,
  attempt: { attempt_ref: string; created_at: string },
  anonymousSessionDigest: string,
  target: { result_id: string; snapshot_ref: string },
  now: Date,
): Promise<{ token: string; expires_at: string }> {
  const notAfter = new Date(
    Date.parse(attempt.created_at) + ANONYMOUS_RESULT_RETENTION_MS,
  );
  if (now.getTime() >= notAfter.getTime()) {
    throw new TasteCardOrchestrationError("anonymous_result_expired");
  }
  return await dependencies.token_signer.issue({
    result_id: target.result_id,
    snapshot_ref: target.snapshot_ref,
    anonymous_session_digest: anonymousSessionDigest,
  }, { not_after: notAfter });
}

async function restoreConversionForReplay(
  dependencies: TasteCardOrchestratorDependencies,
  request: CreateTasteCardResultRequest,
  principal: TasteCardPrincipal,
  attempt: { attempt_ref: string; created_at: string },
  stored: TasteCardResultEnvelope,
  now: Date,
): Promise<TasteCardResultEnvelope> {
  if (principal.kind === "authenticated") {
    return { ...explained(stored), ownership_state: "saved", conversion: null };
  }
  if (stored.ownership_state === "saved") {
    // A member already claimed this card; the anonymous session gets no
    // further proof for it.
    throw new TasteCardOrchestrationError("anonymous_result_claimed");
  }
  const issued = await issueConversion(
    dependencies,
    attempt,
    principal.anonymous_session_digest,
    { result_id: stored.result_id, snapshot_ref: stored.snapshot_ref },
    now,
  );
  await dependencies.repository.refreshConversionExpiry({
    attempt_ref: attempt.attempt_ref,
    conversion_key_version: dependencies.token_signer.key_version,
    conversion_expires_at: issued.expires_at,
  });
  return {
    ...explained(stored),
    ownership_state: "anonymous",
    conversion: {
      anonymous_session_id: request.anonymous_session_id!,
      conversion_token: issued.token,
    },
  };
}

function retryableResponse(
  attempt: NonNullable<Awaited<ReturnType<TasteCardRepository["findAttempt"]>>>,
  now: Date,
): CreateTasteCardResultResponse {
  return {
    state: "retryable",
    idempotency_key: attempt.idempotency_key,
    attempt_ref: attempt.attempt_ref,
    error_code: attempt.error_code ?? "engine_temporarily_unavailable",
    retry_after_ms: attempt.retry_after === null
      ? null
      : Math.max(0, Date.parse(attempt.retry_after) - now.getTime()),
  };
}
