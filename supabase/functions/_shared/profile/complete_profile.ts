import type { AuthProvider, EdgeAuthContext } from "../auth.ts";
import { SoolgyulEdgeError } from "../errors.ts";
import {
  type CompleteProfileRequest,
  isValidProfileBirthDate,
  type ProfileStatusResponse,
} from "../soolgyul_contract.ts";
import {
  type ProfileRepository,
  SupabaseProfileRepository,
} from "./repository.ts";

/** The profile store acting as the caller, under their own session. */
export function profileRepositoryFromRequest(
  request: Request,
): ProfileRepository {
  return new SupabaseProfileRepository(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    request.headers.get("Authorization") ?? "",
  );
}

const supportedProviders: AuthProvider[] = ["kakao", "apple", "google"];

function assertSupportedProvider(auth: EdgeAuthContext): void {
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
