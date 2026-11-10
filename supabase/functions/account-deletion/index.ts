import { allowedOrigin, corsHeaders } from "../_shared/http.ts";
import {
  DeletionError,
  type Environment,
  prepareProviderRevocation,
  type ProviderProof,
} from "./providers.ts";
import {
  boundedFetch,
  callerHeaders,
  serviceRoleHeaders,
} from "../_shared/supabase.ts";

export async function handleAccountDeletion(
  request: Request,
  env: Environment = Deno.env.get,
  fetcher: typeof fetch = boundedFetch,
): Promise<Response> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    ...corsHeaders(request),
  };
  const reply = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers });
  if (request.headers.has("Origin") && allowedOrigin(request) === null) {
    return reply(403, { error_code: "origin_rejected" });
  }
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers });
  }
  if (!["GET", "POST"].includes(request.method)) {
    return reply(405, { error_code: "method_not_allowed" });
  }
  try {
    const account = await signedInAccount(request, env, fetcher);
    if (request.method === "GET") {
      return reply(200, await account.rpc("soolgyul_get_my_deletion_state"));
    }
    const raw = await request.text();
    if (raw.length > 16384) throw new DeletionError("request_too_large", 413);
    let body;
    try {
      body = JSON.parse(raw);
    } catch {
      throw new DeletionError("invalid_request");
    }
    if (body?.action === "restore") {
      return reply(200, await account.rpc("soolgyul_restore_my_account"));
    }
    if (body?.action !== "request" || body.confirmed !== true) {
      throw new DeletionError("confirmation_required");
    }
    return reply(200, await requestDeletion(account, body.proof, env, fetcher));
  } catch (error) {
    // Never return/log upstream bodies, credentials, tokens or free text.
    return reply(error instanceof DeletionError ? error.status : 503, {
      error_code: error instanceof DeletionError
        ? error.code
        : "account_service_unavailable",
    });
  }
}

/** The caller's account: who they are, and the calls made in their name. */
type SignedInAccount = {
  // deno-lint-ignore no-explicit-any
  user: any;
  // deno-lint-ignore no-explicit-any
  rpc: (name: string, body?: unknown, admin?: boolean) => Promise<any>;
  revokeSessions: () => Promise<void>;
};

/** Confirms the session with Auth before anything is read or changed. */
async function signedInAccount(
  request: Request,
  env: Environment,
  fetcher: typeof fetch,
): Promise<SignedInAccount> {
  const url = env("SUPABASE_URL");
  const key = env("SUPABASE_ANON_KEY");
  const service = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key || !service) {
    throw new DeletionError("server_configuration_missing", 503);
  }
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    throw new DeletionError("authorization_required", 401);
  }
  const authResponse = await fetcher(url + "/auth/v1/user", {
    headers: { apikey: key, Authorization: authorization },
  });
  if (!authResponse.ok) {
    throw new DeletionError("authorization_rejected", 401);
  }
  const user = await authResponse.json();
  if (typeof user.id !== "string") {
    throw new DeletionError("authorization_rejected", 401);
  }
  const rpc = async (name: string, body: unknown = {}, admin = false) => {
    const response = await fetcher(url + "/rest/v1/rpc/" + name, {
      method: "POST",
      headers: admin
        ? serviceRoleHeaders(service)
        : callerHeaders(key, authorization),
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      const failure = await response.json().catch(() => ({}));
      const known = [
        "restore_window_closed",
        "active_account_required",
        "account_restore_unavailable",
        "account_not_found",
      ];
      throw new DeletionError(
        known.includes(failure.message)
          ? failure.message
          : "account_action_failed",
        409,
      );
    }
    return response.json();
  };
  const revokeSessions = async () => {
    const logout = await fetcher(url + "/auth/v1/logout?scope=global", {
      method: "POST",
      headers: { apikey: key, Authorization: authorization },
    });
    if (!logout.ok && logout.status !== 401) {
      throw new DeletionError("session_revocation_pending", 503);
    }
  };
  return { user, rpc, revokeSessions };
}

/**
 * Schedules the deletion: every linked social login is checked first, then
 * the account is scheduled, the logins are unlinked and the sessions end.
 */
async function requestDeletion(
  { user, rpc, revokeSessions }: SignedInAccount,
  // deno-lint-ignore no-explicit-any
  proof: any,
  env: Environment,
  fetcher: typeof fetch,
) {
  const current = await rpc("soolgyul_get_my_deletion_state");
  if (current.deletion_state === "purged") {
    throw new DeletionError("account_restore_unavailable", 409);
  }
  if (current.deletion_state === "scheduled" && current.provider_revoked) {
    await revokeSessions();
    return current;
  }
  const identities = user.identities ?? [];
  // Do not silently revoke only one of several linked social identities.
  if (
    identities.length === 0 ||
    new Set(identities.map((i: { provider: string }) => i.provider)).size !==
      identities.length
  ) {
    throw new DeletionError("linked_provider_review_required", 409);
  }
  const revocations: Array<() => Promise<void>> = [];
  for (const identity of identities) {
    const sub = identity.identity_data?.sub ?? identity.id;
    if (typeof sub !== "string") {
      throw new DeletionError("provider_identity_mismatch", 403);
    }
    revocations.push(
      await prepareProviderRevocation(
        { provider: identity.provider, id: sub },
        (proof?.providers?.[identity.provider] ??
          (identities.length === 1 ? proof : {})) as ProviderProof ?? {},
        env,
        fetcher,
      ),
    );
  }
  // Only the server may schedule it, and only after the checks above.
  const scheduled = await rpc("soolgyul_request_account_deletion", {
    target_user_id: user.id,
  }, true);
  for (const revoke of revocations) await revoke();
  const marked = await rpc("soolgyul_mark_deletion_provider_revoked", {
    target_user_id: user.id,
    requested_at: scheduled.requested_at,
    authenticated_at: user.last_sign_in_at,
  }, true);
  if (marked !== true) throw new DeletionError("deletion_state_changed", 409);
  // Invalidate refresh sessions globally. Product RLS already denies reads.
  await revokeSessions();
  return { ...scheduled, provider_revoked: true };
}

if (import.meta.main) Deno.serve((request) => handleAccountDeletion(request));
