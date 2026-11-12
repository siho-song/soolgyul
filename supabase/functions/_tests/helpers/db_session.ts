import type { PGlite } from "npm:@electric-sql/pglite@0.3.14";

// Shared by the DB tests: run work as a client role the way PostgREST would,
// and the few checks they all need.

/**
 * Runs `work` as a client role; `null` is a caller without a session. The
 * role and the session claims are reset afterwards.
 */
export async function asRole<T>(
  db: PGlite,
  role: "anon" | "authenticated",
  userId: string | null,
  work: () => Promise<T>,
): Promise<T> {
  await db.exec(`set role ${role};`);
  await db.query("select set_config('request.jwt.claims', $1, false)", [
    userId === null ? "" : JSON.stringify({ sub: userId }),
  ]);
  try {
    return await work();
  } finally {
    await db.exec("reset role;");
    await db.query("select set_config('request.jwt.claims', '', false)");
  }
}

/** Runs `work` as a signed-in member. */
export const asUser = <T>(db: PGlite, userId: string, work: () => Promise<T>) =>
  asRole(db, "authenticated", userId, work);

/** The message `work` fails with, or null when it succeeds. */
export async function refusal(work: () => Promise<unknown>) {
  try {
    await work();
  } catch (error) {
    return (error as Error).message;
  }
  return null;
}

/** Passes when `work` fails with a message that holds `message`. */
export async function failsWith(work: () => Promise<unknown>, message: string) {
  try {
    await work();
  } catch (error) {
    if (String(error).includes(message)) return;
    throw new Error(`expected ${message}, got ${String(error)}`);
  }
  throw new Error(`expected ${message}, but the call succeeded`);
}

/** JSON with object keys sorted at every depth; jsonb reorders keys. */
export function sortedJson(value: unknown): string {
  return JSON.stringify(
    value,
    (_key, v) =>
      v !== null && typeof v === "object" && !Array.isArray(v)
        ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, v[k]]))
        : v,
  );
}
