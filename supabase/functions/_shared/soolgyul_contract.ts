// Profile completion request/status contract and the canonical category keys.

export type DeletionState = "active" | "scheduled";

export const ALCOHOL_CATEGORY_KEYS = [
  "wine",
  "whisky",
  "korean_traditional",
  "sake",
] as const;

export type AlcoholCategory = typeof ALCOHOL_CATEGORY_KEYS[number];

/** Every record points at one catalog item; a drink cannot be entered by name. */
export type AlcoholIdentificationInput = {
  mode: "catalog_match";
  alcohol_item_id: string;
  alcohol_name_snapshot: string;
  category: AlcoholCategory | null;
};

export type CompleteProfileRequest = {
  gender?: "male" | "female" | "other" | null;
  gender_consent_accepted?: boolean;
  idempotency_key: string;
  display_name: string;
  birth_year: number;
  birth_date: string;
  age_19_or_over_confirmed: boolean;
  terms_version: string;
  privacy_version: string;
  marketing_version: string;
  terms_accepted: boolean;
  privacy_accepted: boolean;
  marketing_opt_in: boolean;
};

export type ProfileStatusResponse = {
  profile_complete: boolean;
  display_name: string | null;
  age_19_or_over_confirmed: boolean;
  terms_version: string | null;
  privacy_version: string | null;
  marketing_opt_in: boolean;
  deletion_state: DeletionState;
};

const COMPLETE_PROFILE_REQUEST_FIELDS = [
  "idempotency_key",
  "display_name",
  "birth_year",
  "birth_date",
  "age_19_or_over_confirmed",
  "terms_version",
  "privacy_version",
  "marketing_version",
  "terms_accepted",
  "privacy_accepted",
  "marketing_opt_in",
] as const;

export class SoolgyulContractError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "SoolgyulContractError";
  }
}

export function parseCompleteProfileRequest(
  value: unknown,
): CompleteProfileRequest {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new SoolgyulContractError("complete_profile_request_invalid");
  }
  const input = value as Record<string, unknown>;
  const keys = Object.keys(input);
  if (
    keys.some((key) =>
      ![...COMPLETE_PROFILE_REQUEST_FIELDS, "gender", "gender_consent_accepted"]
        .includes(key)
    ) ||
    COMPLETE_PROFILE_REQUEST_FIELDS.some((field) => !keys.includes(field))
  ) {
    throw new SoolgyulContractError("complete_profile_request_invalid");
  }
  if (
    (input.gender !== undefined && input.gender !== null &&
      !["male", "female", "other"].includes(input.gender as string)) ||
    (input.gender_consent_accepted !== undefined &&
      typeof input.gender_consent_accepted !== "boolean") ||
    (input.gender != null && input.gender_consent_accepted !== true) ||
    (input.gender == null && input.gender_consent_accepted === true)
  ) {
    throw new SoolgyulContractError("complete_profile_request_invalid");
  }
  if (
    typeof input.idempotency_key !== "string" ||
    typeof input.display_name !== "string" ||
    typeof input.birth_year !== "number" ||
    !Number.isInteger(input.birth_year) ||
    typeof input.age_19_or_over_confirmed !== "boolean" ||
    typeof input.terms_version !== "string" ||
    typeof input.privacy_version !== "string" ||
    typeof input.marketing_version !== "string" ||
    typeof input.terms_accepted !== "boolean" ||
    typeof input.privacy_accepted !== "boolean" ||
    typeof input.marketing_opt_in !== "boolean"
  ) {
    throw new SoolgyulContractError("complete_profile_request_invalid");
  }
  if (!isValidProfileBirthDate(input.birth_date, input.birth_year)) {
    throw new SoolgyulContractError("birth_date_invalid");
  }
  return input as CompleteProfileRequest;
}

export function isValidProfileBirthDate(
  value: unknown,
  year: unknown,
): boolean {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.getTime()) &&
    date.toISOString().slice(0, 10) === value &&
    date.getUTCFullYear() === year && date.getUTCFullYear() >= 1900 &&
    value <= new Date().toISOString().slice(0, 10);
}
