// Firebase Cloud Messaging over its HTTP v1 API: an access token from the
// service account's key, and one notification to one phone.

export type FcmAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

export type FcmNotice = { title: string; body: string };

/** What became of one notification: taken, the phone is gone, or not taken. */
export type FcmOutcome = "sent" | "gone" | "failed";

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

/** The service account from its JSON key file, or `null` when it is not one. */
export function fcmAccountFrom(raw: string | undefined): FcmAccount | null {
  try {
    const key = JSON.parse(raw ?? "") as Record<string, unknown>;
    const { project_id, client_email, private_key } = key;
    if (
      typeof project_id !== "string" || !project_id ||
      typeof client_email !== "string" || !client_email ||
      typeof private_key !== "string" || !private_key
    ) {
      return null;
    }
    return { project_id, client_email, private_key };
  } catch {
    return null;
  }
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_")
    .replaceAll("=", "");
}

const jsonPart = (value: unknown) =>
  base64Url(new TextEncoder().encode(JSON.stringify(value)));

/** Signs a short-lived claim with the account's key and trades it for an access token. */
export async function fcmAccessToken(
  account: FcmAccount,
  fetcher: typeof fetch,
  now: Date,
): Promise<string> {
  const pem = account.private_key.replace(/-----[A-Z ]+-----/g, "")
    .replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (char) => char.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const issuedAt = Math.floor(now.getTime() / 1000);
  const signing = `${jsonPart({ alg: "RS256", typ: "JWT" })}.${
    jsonPart({
      iss: account.client_email,
      scope: SCOPE,
      aud: TOKEN_URL,
      iat: issuedAt,
      exp: issuedAt + 600,
    })
  }`;
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(signing),
    ),
  );
  const response = await fetcher(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${signing}.${base64Url(signature)}`,
    }),
  });
  const body = response.ok ? await response.json() : null;
  if (!response.ok) await response.body?.cancel();
  if (typeof body?.access_token !== "string" || !body.access_token) {
    throw new Error("fcm_access_token_refused");
  }
  return body.access_token;
}

/**
 * Sends one notification to one phone. Only "not found" means the phone is
 * gone: an "invalid argument" may be the message's fault, and forgetting
 * every phone over a bad message would be worse than keeping a dead one.
 */
export async function sendFcm(
  fetcher: typeof fetch,
  projectId: string,
  accessToken: string,
  token: string,
  notice: FcmNotice,
): Promise<FcmOutcome> {
  try {
    const response = await fetcher(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: notice,
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      },
    );
    await response.body?.cancel();
    if (response.ok) return "sent";
    return response.status === 404 ? "gone" : "failed";
  } catch {
    return "failed";
  }
}
