type ProviderIdentity = { provider: string; id: string };
export type ProviderProof = {
  access_token?: string;
  authorization_code?: string;
  refresh_token?: string;
  apple_client?: string;
};
export type Environment = (name: string) => string | undefined;

export class DeletionError extends Error {
  constructor(public code: string, public status = 400) {
    super(code);
  }
}
async function json(response: Response) {
  if (!response.ok) {
    throw new DeletionError("provider_verification_failed", 409);
  }
  return await response.json();
}
const form = (data: Record<string, string>) => ({
  method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams(data),
});
function required(env: Environment, name: string): string {
  const value = env(name);
  if (!value) throw new DeletionError("provider_configuration_missing", 503);
  return value;
}
function decodePart(value: string): Uint8Array<ArrayBuffer> {
  const base = value.replaceAll("-", "+").replaceAll("_", "/");
  return Uint8Array.from(
    atob(base.padEnd(Math.ceil(base.length / 4) * 4, "=")),
    (c) => c.charCodeAt(0),
  );
}
async function verifyAppleIdToken(
  token: string,
  client: string,
  subject: string,
  fetcher: typeof fetch,
) {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new DeletionError("provider_identity_mismatch", 403);
  }
  const header = JSON.parse(new TextDecoder().decode(decodePart(parts[0])));
  const claims = JSON.parse(new TextDecoder().decode(decodePart(parts[1])));
  if (
    header.alg !== "RS256" || claims.iss !== "https://appleid.apple.com" ||
    claims.aud !== client || claims.sub !== subject ||
    typeof claims.exp !== "number" || claims.exp <= Date.now() / 1000
  ) throw new DeletionError("provider_identity_mismatch", 403);
  const jwks = await json(await fetcher("https://appleid.apple.com/auth/keys"));
  const jwk = jwks.keys?.find((k: { kid: string }) => k.kid === header.kid);
  if (!jwk) throw new DeletionError("provider_identity_mismatch", 403);
  const key = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
  if (
    !await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      key,
      decodePart(parts[2]),
      new TextEncoder().encode(parts[0] + "." + parts[1]),
    )
  ) {
    throw new DeletionError("provider_identity_mismatch", 403);
  }
}

/** Validate ownership before allowing revocation. Tokens stay in memory only. */
export async function prepareProviderRevocation(
  identity: ProviderIdentity,
  proof: ProviderProof,
  env: Environment,
  fetcher: typeof fetch = fetch,
): Promise<() => Promise<void>> {
  let revoke: () => Promise<Response>;
  if (identity.provider === "google") {
    if (!proof.access_token) {
      throw new DeletionError("provider_reauthentication_required", 409);
    }
    const allowed = required(env, "GOOGLE_REVOCATION_CLIENT_IDS").split(",")
      .map((s) => s.trim());
    const info = await json(
      await fetcher(
        "https://oauth2.googleapis.com/tokeninfo?" +
          new URLSearchParams({ access_token: proof.access_token }),
      ),
    );
    if (info.sub !== identity.id || !allowed.includes(info.aud)) {
      throw new DeletionError("provider_identity_mismatch", 403);
    }
    revoke = () =>
      fetcher(
        "https://oauth2.googleapis.com/revoke",
        form({ token: proof.access_token! }),
      );
  } else if (identity.provider === "kakao") {
    if (!proof.access_token) {
      throw new DeletionError("provider_reauthentication_required", 409);
    }
    const headers = { Authorization: "Bearer " + proof.access_token };
    const info = await json(
      await fetcher("https://kapi.kakao.com/v2/user/me", { headers }),
    );
    if (String(info.id) !== identity.id) {
      throw new DeletionError("provider_identity_mismatch", 403);
    }
    revoke = () =>
      fetcher("https://kapi.kakao.com/v1/user/unlink", {
        method: "POST",
        headers,
      });
  } else if (identity.provider === "apple") {
    const native = proof.apple_client === "native";
    const client = required(
      env,
      native ? "APPLE_NATIVE_CLIENT_ID" : "APPLE_WEB_CLIENT_ID",
    );
    const secret = required(
      env,
      native ? "APPLE_NATIVE_CLIENT_SECRET" : "APPLE_WEB_CLIENT_SECRET",
    );
    const tokenRequest: Record<string, string> = {
      client_id: client,
      client_secret: secret,
    };
    if (proof.authorization_code) {
      Object.assign(tokenRequest, {
        grant_type: "authorization_code",
        code: proof.authorization_code,
      });
    } else if (proof.refresh_token) {
      Object.assign(tokenRequest, {
        grant_type: "refresh_token",
        refresh_token: proof.refresh_token,
      });
    } else throw new DeletionError("provider_reauthentication_required", 409);
    const tokens = await json(
      await fetcher("https://appleid.apple.com/auth/token", form(tokenRequest)),
    );
    await verifyAppleIdToken(tokens.id_token, client, identity.id, fetcher);
    const token = tokens.refresh_token ?? proof.refresh_token ??
      tokens.access_token;
    if (typeof token !== "string" || !token) {
      throw new DeletionError("provider_verification_failed", 409);
    }
    revoke = () =>
      fetcher(
        "https://appleid.apple.com/auth/revoke",
        form({
          client_id: client,
          client_secret: secret,
          token,
          token_type_hint: tokens.refresh_token || proof.refresh_token
            ? "refresh_token"
            : "access_token",
        }),
      );
  } else throw new DeletionError("unsupported_provider", 409);
  return async () => {
    const response = await revoke();
    if (!response.ok) {
      throw new DeletionError("provider_revocation_failed", 503);
    }
  };
}
