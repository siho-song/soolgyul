/**
 * Calls into the project's own database as the service role (PostgREST), for
 * the server-side reads and writes a caller's own session is not allowed.
 * Every repository asks through here, so the address, the headers and what a
 * failure becomes are written once.
 */
import {
  boundedFetch,
  postgrestJson,
  serviceRoleHeaders,
} from "../supabase.ts";

/**
 * A database call failed, or what it returned does not read. The code is the
 * database's (SQLSTATE) when it gave one. `transient` when trying again later
 * may succeed: a timeout, a dropped connection, an unavailable server.
 */
export class DatabaseError extends Error {
  constructor(
    public readonly code: string,
    message = code,
    public readonly transient = false,
  ) {
    super(message);
    this.name = "DatabaseError";
  }
}

/** One call: a table's name with its query, or `rpc/<name>`, and the JSON it answers. */
export type ServiceRest = <T = unknown>(
  path: string,
  init?: RequestInit,
) => Promise<T>;

/**
 * The caller for one project. [failure] makes the error a refused or failed
 * call is thrown as; a repository whose callers tell its errors apart passes
 * its own.
 */
export function serviceRest(
  supabaseUrl: string,
  serviceRoleKey: string,
  fetchImpl: typeof fetch = boundedFetch,
  failure: (code: string, message: string, transient: boolean) => Error = (
    code,
    message,
    transient,
  ) => new DatabaseError(code, message, transient),
): ServiceRest {
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("supabase_service_configuration_required");
  }
  return <T>(path: string, init: RequestInit = {}) =>
    postgrestJson<T>(
      fetchImpl,
      `${supabaseUrl}/rest/v1/${path}`,
      {
        ...init,
        headers: {
          ...serviceRoleHeaders(serviceRoleKey),
          ...init.headers as Record<string, string> | undefined,
        },
      },
      failure,
    );
}

/** Calls a database function with its arguments. */
export function callRpc<T = unknown>(
  rest: ServiceRest,
  name: string,
  body: unknown,
): Promise<T> {
  return rest<T>(`rpc/${name}`, { method: "POST", body: JSON.stringify(body) });
}

/** The strings of a list column, in its own order; anything else in it is dropped. */
export function stringsOf(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}
