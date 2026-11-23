/**
 * The night's count of the catalog, read from the database in place of the
 * copy a function ships with.
 *
 * A function calls [useCatalogKindSpreads] before it serves a request. The
 * row is read once an hour for each running instance; between reads the call
 * costs nothing. A read that fails, or a count the engine will not take,
 * leaves the count in use as it was and is tried again a few minutes later,
 * so a card is never held up or refused for it.
 */
import { serviceRoleHeaders } from "../../supabase.ts";
import { useKindSpreads } from "./kind_place.ts";

const KEEP_MS = 60 * 60 * 1000;
const RETRY_MS = 5 * 60 * 1000;
const WAIT_MS = 2000;

let readAgainAt = 0;
let reading: Promise<void> | null = null;

async function read(
  env: (name: string) => string | undefined,
  fetcher: typeof fetch,
): Promise<boolean> {
  const url = env("SUPABASE_URL"), key = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return false;
  try {
    const response = await fetcher(
      `${url}/rest/v1/catalog_kind_spreads?select=spreads&limit=1`,
      {
        headers: serviceRoleHeaders(key),
        signal: AbortSignal.timeout(WAIT_MS),
      },
    );
    if (!response.ok) {
      await response.body?.cancel();
      return false;
    }
    const rows = await response.json() as { spreads?: unknown }[];
    return Array.isArray(rows) && rows.length === 1 &&
      useKindSpreads(rows[0].spreads);
  } catch {
    return false;
  }
}

/** Brings the count in use up to the night's, when it is time to look again. */
export function useCatalogKindSpreads(
  env: (name: string) => string | undefined = Deno.env.get,
  fetcher: typeof fetch = fetch,
  now: () => number = Date.now,
): Promise<void> {
  if (now() < readAgainAt) return Promise.resolve();
  // Requests that arrive together wait on one read.
  reading ??= read(env, fetcher).then((taken) => {
    readAgainAt = now() + (taken ? KEEP_MS : RETRY_MS);
  }).finally(() => {
    reading = null;
  });
  return reading;
}

/** Forgets when the count was last read; for tests. */
export function forgetCatalogKindSpreads(): void {
  readAgainAt = 0;
  useKindSpreads(null);
}
