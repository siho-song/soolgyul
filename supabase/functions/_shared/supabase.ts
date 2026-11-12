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

/** Codes for a failure that may pass on a later try. */
const transientDatabaseCodes = ["57014", "08006"];

/**
 * Sends one PostgREST call and returns its JSON body. A refusal becomes
 * [failure] with the database's code (SQLSTATE), else `http_<status>`. A
 * timeout, a dropped connection, a 502/503/504 and any 5xx without a database
 * code are transient; so are a cancelled statement and a lost connection.
 */
export async function postgrestJson<T>(
  fetchImpl: typeof fetch,
  url: string,
  init: RequestInit,
  failure: (code: string, message: string, transient: boolean) => Error,
): Promise<T> {
  let response: Response;
  let text: string;
  try {
    response = await fetchImpl(url, init);
    text = await response.text();
  } catch (error) {
    const timedOut = error instanceof DOMException &&
      (error.name === "TimeoutError" || error.name === "AbortError");
    throw failure(
      timedOut ? "timeout" : "network_unavailable",
      "repository_request_failed",
      true,
    );
  }
  let body: unknown = null;
  let readable = true;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    readable = false;
  }
  if (!response.ok) {
    const error = readable && body !== null && typeof body === "object"
      ? body as Record<string, unknown>
      : {};
    const databaseCode = typeof error.code === "string" ? error.code : null;
    throw failure(
      databaseCode ?? `http_${response.status}`,
      typeof error.message === "string"
        ? error.message
        : "repository_request_failed",
      [502, 503, 504].includes(response.status) ||
        (response.status >= 500 && databaseCode === null) ||
        transientDatabaseCodes.includes(databaseCode ?? ""),
    );
  }
  if (!readable) {
    throw failure("response_invalid", "repository_response_invalid", false);
  }
  return body as T;
}

/** Rows asked per page: PostgREST's own cap (max_rows) on one answer. */
const PAGE_ROWS = 1000;

/**
 * Reads every row of a list a page at a time, so the API's row cap never
 * cuts it short. [read] gets the page's `&limit=…&offset=…` to append to a
 * query that has a stable `order`; a short page is the last one.
 */
export async function readAllPages<T>(
  read: (page: string) => Promise<T[]>,
): Promise<T[]> {
  const rows: T[] = [];
  for (;;) {
    const page = await read(`&limit=${PAGE_ROWS}&offset=${rows.length}`);
    rows.push(...page);
    if (page.length < PAGE_ROWS) return rows;
  }
}

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
