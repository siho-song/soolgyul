// Who is calling: a signed-in user checked with Auth, or an anonymous
// caller holding the project's public key.
import { SoolgyulHttpError } from "./http.ts";
import type { TasteCardAuthContext } from "./taste_card/service/orchestrator.ts";

export type AuthProvider = "kakao" | "apple" | "google";

export type EdgeAuthContext = {
  user_id: string;
  auth_provider: AuthProvider;
  provider_user_id: string;
};

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
export async function resolveCaller(
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

export async function resolveProfileCaller(
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
