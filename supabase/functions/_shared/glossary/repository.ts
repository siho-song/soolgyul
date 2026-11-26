import { readAccount } from "../database/accounts.ts";
import { type ServiceRest, serviceRest } from "../database/service_rest.ts";
import { boundedFetch } from "../supabase.ts";

/** One saved term as the table keeps it. */
export type SavedTermRow = { term_key: string; created_at: string };

/**
 * The reader's saved terms, read and written with the service role: the
 * table is closed to clients so that only keys the dictionary has get in.
 */
export interface SavedTermsRepository {
  accountActive(userId: string): Promise<boolean>;
  /** Newest first. */
  list(userId: string): Promise<SavedTermRow[]>;
  /** Saving a saved term again keeps its first day. */
  save(userId: string, termKey: string): Promise<void>;
  /** Taking out a term that is not there is no error. */
  remove(userId: string, termKey: string): Promise<void>;
}

export class SupabaseSavedTermsRepository implements SavedTermsRepository {
  private readonly rest: ServiceRest;

  constructor(
    supabaseUrl: string,
    serviceRoleKey: string,
    fetchImpl: typeof fetch = boundedFetch,
  ) {
    this.rest = serviceRest(supabaseUrl, serviceRoleKey, fetchImpl);
  }

  async accountActive(userId: string): Promise<boolean> {
    return (await readAccount(this.rest, userId)).active;
  }

  async list(userId: string): Promise<SavedTermRow[]> {
    const rows = await this.rest<Record<string, unknown>[]>(
      `user_saved_terms?user_id=eq.${encodeURIComponent(userId)}` +
        "&select=term_key,created_at&order=created_at.desc,term_key.asc",
    );
    return rows.map((row) => ({
      term_key: String(row.term_key),
      created_at: String(row.created_at),
    }));
  }

  async save(userId: string, termKey: string): Promise<void> {
    await this.rest("user_saved_terms?on_conflict=user_id,term_key", {
      method: "POST",
      headers: { Prefer: "resolution=ignore-duplicates,return=minimal" },
      body: JSON.stringify({ user_id: userId, term_key: termKey }),
    });
  }

  async remove(userId: string, termKey: string): Promise<void> {
    await this.rest(
      `user_saved_terms?user_id=eq.${encodeURIComponent(userId)}` +
        `&term_key=eq.${encodeURIComponent(termKey)}`,
      { method: "DELETE", headers: { Prefer: "return=minimal" } },
    );
  }
}
