// The headers and secrets every call into the project's own APIs needs.
import { SoolgyulHttpError } from "./http.ts";

/**
 * `fetch` that gives up after ten seconds, so a stalled call into the
 * project's own APIs fails the request instead of holding it open.
 */
export const boundedFetch: typeof fetch = (input, init) =>
  fetch(input, {
    ...init,
    signal: init?.signal ?? AbortSignal.timeout(10_000),
  });

/** The service role through PostgREST, Storage and the Auth admin API. */
export function serviceRoleHeaders(key: string): Record<string, string> {
  return {
    apikey: key,
    Authorization: `Bearer ${key}`,
    "Content-Type": "application/json",
  };
}

/** The caller's own session, so row security applies to them. */
export function callerHeaders(
  anonKey: string,
  authorization: string,
): Record<string, string> {
  return {
    apikey: anonKey,
    Authorization: authorization,
    "Content-Type": "application/json",
  };
}

/** The project URL and service role key; a 503 when either is missing. */
export function serviceRoleEnv(): { url: string; key: string } {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) {
    throw new SoolgyulHttpError(503, "service_configuration_missing");
  }
  return { url, key };
}
