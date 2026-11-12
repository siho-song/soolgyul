import { sha256Hex } from "./canonical.ts";
import { ConversionTokenError } from "./errors.ts";

type ConversionTokenClaims = {
  version: 1;
  key_version: string;
  result_id: string;
  snapshot_ref: string;
  anonymous_session_digest: string;
  expires_at_epoch_seconds: number;
};

type ConversionTokenIssueInput = {
  result_id: string;
  snapshot_ref: string;
  anonymous_session_digest: string;
};

type ConversionTokenIssueOptions = {
  /** Latest acceptable expiry; the token never outlives this instant. */
  not_after?: Date;
};

export type ConversionTokenSigner = {
  readonly key_version: string;
  issue(
    input: ConversionTokenIssueInput,
    options?: ConversionTokenIssueOptions,
  ): Promise<{
    token: string;
    expires_at: string;
  }>;
  verify(token: string): Promise<ConversionTokenClaims>;
};

export class HmacConversionTokenSigner implements ConversionTokenSigner {
  constructor(
    private readonly secret: string,
    public readonly key_version: string,
    private readonly ttl_seconds = 15 * 60,
    private readonly now: () => Date = () => new Date(),
  ) {
    if (secret.length < 32) {
      throw new Error("conversion_signing_secret_too_short");
    }
    if (!key_version.trim()) throw new Error("conversion_key_version_required");
    if (!Number.isInteger(ttl_seconds) || ttl_seconds <= 0) {
      throw new Error("conversion_ttl_invalid");
    }
  }

  async issue(
    input: ConversionTokenIssueInput,
    options: ConversionTokenIssueOptions = {},
  ): Promise<{
    token: string;
    expires_at: string;
  }> {
    assertDigest(input.anonymous_session_digest);
    const nowSeconds = Math.floor(this.now().getTime() / 1000);
    const latest = options.not_after === undefined
      ? Number.POSITIVE_INFINITY
      : Math.floor(options.not_after.getTime() / 1000);
    const expires = Math.min(nowSeconds + this.ttl_seconds, latest);
    if (expires <= nowSeconds) {
      throw new ConversionTokenError("conversion_window_closed");
    }
    const header = encodeJson({
      algorithm: "HS256",
      key_version: this.key_version,
    });
    const claims: ConversionTokenClaims = {
      version: 1,
      key_version: this.key_version,
      result_id: required(input.result_id, "conversion_result_required"),
      snapshot_ref: required(
        input.snapshot_ref,
        "conversion_snapshot_required",
      ),
      anonymous_session_digest: input.anonymous_session_digest,
      expires_at_epoch_seconds: expires,
    };
    const payload = encodeJson(claims);
    const signature = await this.sign(`${header}.${payload}`);
    return {
      token: `${header}.${payload}.${signature}`,
      expires_at: new Date(expires * 1000).toISOString(),
    };
  }

  async verify(token: string): Promise<ConversionTokenClaims> {
    const parts = token.split(".");
    if (parts.length !== 3 || parts.some((part) => part.length === 0)) {
      throw new ConversionTokenError("conversion_token_malformed");
    }
    const [headerEncoded, payloadEncoded, signatureEncoded] = parts;
    const header = decodeJson(headerEncoded);
    exactKeys(header, ["algorithm", "key_version"]);
    if (
      header.algorithm !== "HS256" || header.key_version !== this.key_version
    ) {
      throw new ConversionTokenError("conversion_token_key_rejected");
    }
    const valid = await crypto.subtle.verify(
      "HMAC",
      await this.key(),
      decodeBase64Url(signatureEncoded).buffer as ArrayBuffer,
      new TextEncoder().encode(`${headerEncoded}.${payloadEncoded}`),
    );
    if (!valid) throw new ConversionTokenError("conversion_token_rejected");

    const payload = decodeJson(payloadEncoded);
    exactKeys(payload, [
      "version",
      "key_version",
      "result_id",
      "snapshot_ref",
      "anonymous_session_digest",
      "expires_at_epoch_seconds",
    ]);
    if (payload.version !== 1 || payload.key_version !== this.key_version) {
      throw new ConversionTokenError("conversion_token_contract_rejected");
    }
    const claims = payload as ConversionTokenClaims;
    required(claims.result_id, "conversion_result_required");
    required(claims.snapshot_ref, "conversion_snapshot_required");
    assertDigest(claims.anonymous_session_digest);
    if (
      !Number.isInteger(claims.expires_at_epoch_seconds) ||
      claims.expires_at_epoch_seconds <= Math.floor(this.now().getTime() / 1000)
    ) {
      throw new ConversionTokenError("conversion_token_expired");
    }
    return claims;
  }

  private async sign(value: string): Promise<string> {
    const signature = await crypto.subtle.sign(
      "HMAC",
      await this.key(),
      new TextEncoder().encode(value),
    );
    return encodeBase64Url(new Uint8Array(signature));
  }

  private async key(): Promise<CryptoKey> {
    return await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(this.secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign", "verify"],
    );
  }
}

export async function anonymousSessionDigest(
  sessionId: string,
): Promise<string> {
  const normalized = sessionId.trim();
  if (!normalized) throw new ConversionTokenError("anonymous_session_required");
  return await sha256Hex(normalized);
}

function assertDigest(value: string): void {
  if (!/^[0-9a-f]{64}$/.test(value)) {
    throw new ConversionTokenError("anonymous_session_digest_invalid");
  }
}

function required(value: string, code: string): string {
  if (!value.trim()) throw new ConversionTokenError(code);
  return value;
}

function encodeJson(value: unknown): string {
  return encodeBase64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function decodeJson(value: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(new TextDecoder().decode(decodeBase64Url(value)));
    if (
      parsed === null || typeof parsed !== "object" || Array.isArray(parsed)
    ) {
      throw new Error("not_object");
    }
    return parsed as Record<string, unknown>;
  } catch {
    throw new ConversionTokenError("conversion_token_malformed");
  }
}

function exactKeys(object: Record<string, unknown>, keys: string[]): void {
  if (
    Object.keys(object).sort().join("\u0000") !==
      [...keys].sort().join("\u0000")
  ) {
    throw new ConversionTokenError("conversion_token_contract_rejected");
  }
}

function encodeBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

function decodeBase64Url(value: string): Uint8Array {
  try {
    const base64 = value.replaceAll("-", "+").replaceAll("_", "/") +
      "=".repeat((4 - value.length % 4) % 4);
    return Uint8Array.from(
      atob(base64),
      (character) => character.charCodeAt(0),
    );
  } catch {
    throw new ConversionTokenError("conversion_token_malformed");
  }
}
