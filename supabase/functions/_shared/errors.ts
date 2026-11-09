// The errors an edge function may answer with, and how each becomes a
// status and a public error code. Anything not listed is an internal failure
// and never leaks its code.
import { jsonResponse, SoolgyulHttpError } from "./http.ts";
import { SoolgyulContractError } from "./soolgyul_contract.ts";
import { ConversionTokenError } from "./taste_card/conversion_token.ts";
import { TasteCardOrchestrationError } from "./taste_card/orchestrator.ts";
import { TasteCardRepositoryError } from "./taste_card/repository.ts";
import { TasteCardContractError } from "./taste_card/serialization.ts";
import { ProfileRepositoryError } from "./profile/repository.ts";

export class SoolgyulEdgeError extends Error {
  constructor(public code: string, message = code) {
    super(message);
    this.name = "SoolgyulEdgeError";
  }
}

/**
 * HTTP status for every error code a client may legitimately see. Codes that
 * are not listed here, and errors of any other type, are internal failures and
 * never leak their code.
 */
const errorStatuses: Readonly<Record<string, number>> = {
  // Request shape and policy gates.
  age_gate_required: 400,
  anonymous_session_required: 400,
  authenticated_anonymous_session_forbidden: 400,
  birth_date_invalid: 400,
  birth_year_invalid: 400,
  conversion_token_claim_mismatch: 400,
  display_name_invalid: 400,
  display_name_required: 400,
  idempotency_key_required: 400,
  policy_version_invalid: 400,
  questionnaire_contract_invalid: 400,
  sensory_questionnaire_invalid: 400,
  terms_and_privacy_required: 400,
  unsupported_questionnaire_option: 400,
  // Authentication and account state.
  authentication_required: 401,
  active_account_required: 403,
  complete_profile_required: 403,
  unsupported_auth_provider: 403,
  // Lookups, conflicts and expiry.
  catalog_item_not_found: 404,
  profile_not_found: 404,
  result_not_found: 404,
  anonymous_result_claimed: 409,
  idempotency_conflict: 409,
  idempotency_key_reused: 409,
  anonymous_result_expired: 410,
  anonymous_generation_limit_reached: 429,
  // Upstream availability.
  profile_service_unavailable: 503,
};

/** Database errors surfaced by service RPCs, keyed by SQLSTATE. */
const databaseErrorStatuses: Readonly<
  Record<string, { status: number; code: string }>
> = {
  "22023": { status: 400, code: "request_invalid" },
  "42501": { status: 403, code: "access_denied" },
  P0002: { status: 404, code: "result_not_found" },
};

function publicError(error: unknown): { status: number; code: string } {
  if (error instanceof SoolgyulHttpError) {
    return { status: error.status, code: error.code };
  }
  if (
    error instanceof TasteCardContractError ||
    error instanceof SoolgyulContractError ||
    error instanceof ConversionTokenError
  ) {
    return { status: 400, code: error.code };
  }
  if (
    error instanceof SoolgyulEdgeError ||
    error instanceof TasteCardOrchestrationError ||
    error instanceof ProfileRepositoryError ||
    error instanceof TasteCardRepositoryError
  ) {
    const database = error instanceof TasteCardRepositoryError
      ? databaseErrorStatuses[error.code]
      : undefined;
    if (database !== undefined) return database;
    const status = errorStatuses[error.code];
    if (status !== undefined) return { status, code: error.code };
  }
  return { status: 500, code: "internal_error" };
}

export function errorResponse(
  request: Request,
  error: unknown,
): Response {
  const { status, code } = publicError(error);
  return jsonResponse(request, status, { error_code: code });
}
