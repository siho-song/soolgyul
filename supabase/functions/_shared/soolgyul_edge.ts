import {
  type CompleteProfileRequest,
  isValidProfileBirthDate,
  type ProfileStatusResponse,
  SoolgyulContractError,
} from "./soolgyul_contract.ts";
import { jsonResponse } from "./http.ts";
import {
  ConversionTokenError,
  HmacConversionTokenSigner,
} from "./taste_card/conversion_token.ts";
import {
  type TasteCardAuthContext,
  TasteCardOrchestrationError,
  type TasteCardOrchestratorDependencies,
} from "./taste_card/orchestrator.ts";
import {
  SupabaseTasteCardRepository,
  TasteCardRepositoryError,
} from "./taste_card/repository.ts";
import { TasteCardContractError } from "./taste_card/serialization.ts";
import {
  type ProfileRepository,
  ProfileRepositoryError,
  SupabaseProfileRepository,
} from "./profile/repository.ts";

export {
  convertAnonymousTasteCardV1,
  createTasteCardResultV1,
  deleteOwnedTasteCardRecordV1,
  getOwnedTasteCardResultV1,
  TasteCardOrchestrationError,
} from "./taste_card/orchestrator.ts";
export {
  corsHeaders as tasteCardCorsHeaders,
  jsonResponse as tasteCardJsonResponse,
} from "./http.ts";

export type AuthProvider = "kakao" | "apple" | "google";

export type EdgeAuthContext = {
  user_id: string;
  auth_provider: AuthProvider;
  provider_user_id: string;
};

export class SoolgyulEdgeError extends Error {
  constructor(public code: string, message = code) {
    super(message);
    this.name = "SoolgyulEdgeError";
  }
}

export class SoolgyulHttpError extends Error {
  constructor(public status: number, public code: string) {
    super(code);
    this.name = "SoolgyulHttpError";
  }
}

export function tasteCardDependenciesFromEnv(): TasteCardOrchestratorDependencies {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const conversionSecret = Deno.env.get("TASTE_CARD_CONVERSION_SECRET") ?? "";
  const conversionKeyVersion = Deno.env.get(
    "TASTE_CARD_CONVERSION_KEY_VERSION",
  ) ?? "";
  if (
    !supabaseUrl || !serviceRoleKey || conversionSecret.length < 32 ||
    !conversionKeyVersion.trim()
  ) {
    throw new SoolgyulHttpError(503, "service_configuration_missing");
  }
  return {
    repository: new SupabaseTasteCardRepository(
      supabaseUrl,
      serviceRoleKey,
    ),
    // The ticket travels in the store link and is claimed after the app's
    // sign-in, days later; the retention window caps it.
    token_signer: new HmacConversionTokenSigner(
      conversionSecret,
      conversionKeyVersion,
      30 * 24 * 60 * 60,
    ),
  };
}

export function profileRepositoryFromRequest(
  request: Request,
): ProfileRepository {
  return new SupabaseProfileRepository(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    request.headers.get("Authorization") ?? "",
  );
}

type AuthUser = {
  id?: unknown;
  app_metadata?: { provider?: unknown };
  identities?: Array<{ provider?: unknown; user_id?: unknown; id?: unknown }>;
};

function authEnvironment(): { supabaseUrl: string; anonKey: string } {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !anonKey) {
    throw new SoolgyulHttpError(503, "auth_service_unavailable");
  }
  return { supabaseUrl, anonKey };
}

/** Validates a user session bearer with Auth and returns the user record. */
async function fetchAuthUser(
  authorization: string,
): Promise<AuthUser & { id: string }> {
  const { supabaseUrl, anonKey } = authEnvironment();
  const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { apikey: anonKey, Authorization: authorization },
  });
  if (!response.ok) throw new SoolgyulHttpError(401, "authorization_rejected");
  const body = await response.json() as AuthUser;
  if (typeof body.id !== "string" || !body.id) {
    throw new SoolgyulHttpError(401, "authorization_rejected");
  }
  return body as AuthUser & { id: string };
}

/**
 * Anonymous callers must still present the project's anon or publishable key
 * as the bearer; any other bearer is validated as a user session.
 */
export async function resolveTasteCardAuth(
  request: Request,
): Promise<TasteCardAuthContext | null> {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    throw new SoolgyulHttpError(401, "authorization_required");
  }
  const { supabaseUrl, anonKey } = authEnvironment();
  const bearer = authorization.slice("Bearer ".length);
  if (bearer === anonKey) return null;
  if (bearer.startsWith("sb_publishable_") || isAnonRoleJwt(bearer)) {
    // A publishable key is not a JWT, and the runtime's SUPABASE_ANON_KEY may
    // differ from the legacy anon key the app was built with; Auth confirms
    // the key belongs to this project before the caller is treated as anonymous.
    const settings = await fetch(`${supabaseUrl}/auth/v1/settings`, {
      headers: { apikey: bearer },
    });
    await settings.body?.cancel();
    if (!settings.ok) {
      throw new SoolgyulHttpError(401, "authorization_rejected");
    }
    return null;
  }
  const user = await fetchAuthUser(authorization);
  return { user_id: user.id };
}

/** True for a project API key in JWT form (role "anon"), never for a user session (role "authenticated"). */
function isAnonRoleJwt(bearer: string): boolean {
  const parts = bearer.split(".");
  if (parts.length !== 3) return false;
  try {
    const payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(
      atob(payload.padEnd(payload.length + (4 - payload.length % 4) % 4, "=")),
    );
    return claims?.role === "anon";
  } catch {
    return false;
  }
}

export async function resolveProfileAuth(
  request: Request,
): Promise<EdgeAuthContext | null> {
  const authorization = request.headers.get("Authorization");
  if (!authorization) return null;
  if (!authorization.startsWith("Bearer ")) {
    throw new SoolgyulHttpError(401, "authorization_rejected");
  }
  const user = await fetchAuthUser(authorization);
  const provider = user.app_metadata?.provider;
  if (provider !== "kakao" && provider !== "apple" && provider !== "google") {
    throw new SoolgyulHttpError(403, "unsupported_auth_provider");
  }
  const identity = user.identities?.find((item) => item.provider === provider);
  const providerUserId = typeof identity?.user_id === "string"
    ? identity.user_id
    : typeof identity?.id === "string"
    ? identity.id
    : user.id;
  return {
    user_id: user.id,
    auth_provider: provider,
    provider_user_id: providerUserId,
  };
}

export async function tasteCardJsonBody(request: Request): Promise<unknown> {
  const maximumBytes = 64 * 1024;
  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    throw new SoolgyulHttpError(415, "json_body_required");
  }
  const declaredLength = Number(request.headers.get("Content-Length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new SoolgyulHttpError(413, "json_body_too_large");
  }
  try {
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (bytes.byteLength > maximumBytes) {
      throw new SoolgyulHttpError(413, "json_body_too_large");
    }
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch (error) {
    if (error instanceof SoolgyulHttpError) throw error;
    throw new SoolgyulHttpError(400, "invalid_json");
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

export function tasteCardErrorResponse(
  request: Request,
  error: unknown,
): Response {
  const { status, code } = publicError(error);
  return jsonResponse(request, status, { error_code: code });
}

const supportedProviders: AuthProvider[] = ["kakao", "apple", "google"];

export function assertSupportedProvider(auth: EdgeAuthContext): void {
  if (!supportedProviders.includes(auth.auth_provider)) {
    throw new SoolgyulEdgeError("unsupported_auth_provider");
  }
}

export async function completeProfile(
  repository: Pick<ProfileRepository, "upsertProfile">,
  auth: EdgeAuthContext,
  request: CompleteProfileRequest,
): Promise<ProfileStatusResponse> {
  assertSupportedProvider(auth);
  assertTermsPrivacyAgeGate(request);
  if (!isValidProfileBirthDate(request.birth_date, request.birth_year)) {
    throw new SoolgyulEdgeError("birth_date_invalid");
  }

  return await repository.upsertProfile({
    user_id: auth.user_id,
    idempotency_key: request.idempotency_key,
    display_name: request.display_name.trim(),
    birth_year: request.birth_year,
    birth_date: request.birth_date,
    ...(request.gender !== undefined ? { gender: request.gender } : {}),
    ...(request.gender_consent_accepted !== undefined
      ? { gender_consent_accepted: request.gender_consent_accepted }
      : {}),
    age_19_or_over_confirmed: request.age_19_or_over_confirmed,
    terms_version: request.terms_version,
    privacy_version: request.privacy_version,
    marketing_version: request.marketing_version,
    terms_accepted: request.terms_accepted,
    privacy_accepted: request.privacy_accepted,
    marketing_opt_in: request.marketing_opt_in,
  });
}

function assertTermsPrivacyAgeGate(request: CompleteProfileRequest): void {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(request.idempotency_key)
  ) {
    throw new SoolgyulEdgeError("idempotency_key_required");
  }
  if (!request.display_name.trim()) {
    throw new SoolgyulEdgeError("display_name_required");
  }
  if (!request.terms_accepted || !request.privacy_accepted) {
    throw new SoolgyulEdgeError("terms_and_privacy_required");
  }
  if (
    request.terms_version !== "soolgyul-terms-v1" ||
    request.privacy_version !== "soolgyul-privacy-v1" ||
    request.marketing_version !== "soolgyul-marketing-v1"
  ) {
    throw new SoolgyulEdgeError("policy_version_invalid");
  }
  const currentYear = new Date().getFullYear();
  if (
    !request.age_19_or_over_confirmed || currentYear - request.birth_year < 19
  ) {
    throw new SoolgyulEdgeError("age_gate_required");
  }
}
