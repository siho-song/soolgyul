import type { ProfileStatusResponse } from "../contract.ts";
import { callerHeaders } from "../supabase.ts";

type CompleteProfileStoreInput = {
  user_id: string;
  idempotency_key: string;
  display_name: string;
  birth_year: number;
  birth_date: string;
  gender?: "male" | "female" | "other" | null;
  gender_consent_accepted?: boolean;
  age_19_or_over_confirmed: boolean;
  terms_version: string;
  privacy_version: string;
  marketing_version: string;
  terms_accepted: boolean;
  privacy_accepted: boolean;
  marketing_opt_in: boolean;
};

export interface ProfileRepository {
  getStatus(): Promise<ProfileStatusResponse>;

  upsertProfile(
    input: CompleteProfileStoreInput,
  ): Promise<ProfileStatusResponse>;
}

export class ProfileRepositoryError extends Error {
  constructor(public readonly code: string, message = code) {
    super(message);
    this.name = "ProfileRepositoryError";
  }
}

type FetchLike = typeof fetch;

export class SupabaseProfileRepository implements ProfileRepository {
  constructor(
    private readonly supabase_url: string,
    private readonly anon_key: string,
    private readonly authorization: string,
    private readonly fetch_impl: FetchLike = fetch,
  ) {
    if (!supabase_url || !anon_key || !authorization) {
      throw new ProfileRepositoryError("profile_service_unavailable");
    }
  }

  async upsertProfile(
    input: CompleteProfileStoreInput,
  ): Promise<ProfileStatusResponse> {
    const response = await this.fetch_impl(
      `${this.supabase_url}/rest/v1/rpc/soolgyul_complete_my_profile`,
      {
        method: "POST",
        headers: callerHeaders(this.anon_key, this.authorization),
        body: JSON.stringify({
          p_idempotency_key: input.idempotency_key,
          p_display_name: input.display_name,
          p_birth_date: input.birth_date,
          p_gender: input.gender ?? null,
          p_gender_consent_accepted: input.gender_consent_accepted ?? false,
          p_age_19_or_over_confirmed: input.age_19_or_over_confirmed,
          p_terms_version: input.terms_version,
          p_privacy_version: input.privacy_version,
          p_marketing_version: input.marketing_version,
          p_terms_accepted: input.terms_accepted,
          p_privacy_accepted: input.privacy_accepted,
          p_marketing_opt_in: input.marketing_opt_in,
        }),
      },
    );
    const body = await parseJson(response);
    if (!response.ok) {
      throw new ProfileRepositoryError(publicDatabaseCode(body));
    }
    return parseProfileStatus(body);
  }

  async getStatus(): Promise<ProfileStatusResponse> {
    const response = await this.fetch_impl(
      `${this.supabase_url}/rest/v1/rpc/soolgyul_get_my_profile_status`,
      {
        method: "POST",
        headers: callerHeaders(this.anon_key, this.authorization),
        body: "{}",
      },
    );
    const body = await parseJson(response);
    if (!response.ok) {
      throw new ProfileRepositoryError(publicDatabaseCode(body));
    }
    return parseProfileStatus(body);
  }
}

async function parseJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    throw new ProfileRepositoryError("profile_service_invalid_response");
  }
}

function publicDatabaseCode(value: unknown): string {
  if (value !== null && typeof value === "object") {
    const message = (value as Record<string, unknown>).message;
    if (
      typeof message === "string" &&
      [
        "authentication_required",
        "active_account_required",
        "unsupported_auth_provider",
        "idempotency_key_required",
        "idempotency_key_reused",
        "display_name_invalid",
        "birth_year_invalid",
        "birth_date_invalid",
        "age_gate_required",
        "terms_and_privacy_required",
        "policy_version_invalid",
        "profile_not_found",
      ].includes(message)
    ) {
      return message;
    }
  }
  return "profile_service_error";
}

function parseProfileStatus(value: unknown): ProfileStatusResponse {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new ProfileRepositoryError("profile_service_invalid_response");
  }
  const row = value as Record<string, unknown>;
  if (
    typeof row.profile_complete !== "boolean" ||
    !(typeof row.display_name === "string" || row.display_name === null) ||
    typeof row.age_19_or_over_confirmed !== "boolean" ||
    !(typeof row.terms_version === "string" || row.terms_version === null) ||
    !(typeof row.privacy_version === "string" ||
      row.privacy_version === null) ||
    typeof row.marketing_opt_in !== "boolean" ||
    (row.deletion_state !== "active" && row.deletion_state !== "scheduled") ||
    (row.profile_complete === true &&
      (typeof row.display_name !== "string" ||
        row.age_19_or_over_confirmed !== true ||
        typeof row.terms_version !== "string" ||
        typeof row.privacy_version !== "string"))
  ) {
    throw new ProfileRepositoryError("profile_service_invalid_response");
  }
  return row as ProfileStatusResponse;
}
