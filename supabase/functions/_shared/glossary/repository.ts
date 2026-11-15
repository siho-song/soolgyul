import {
  boundedFetch,
  postgrestJson,
  serviceRoleHeaders,
} from "../supabase.ts";

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

class SavedTermsRepositoryError extends Error {
  constructor(
    public readonly code: string,
    message = code,
    public readonly transient = false,
  ) {
    super(message);
    this.name = "SavedTermsRepositoryError";
  }
}

export class SupabaseSavedTermsRepository implements SavedTermsRepository {
  constructor(
    private readonly supabase_url: string,
    private readonly service_role_key: string,
    private readonly fetch_impl: typeof fetch = boundedFetch,
  ) {
    if (!supabase_url || !service_role_key) {
      throw new Error("supabase_service_configuration_required");
    }
  }

  async accountActive(userId: string): Promise<boolean> {
    const rows = await this.rest<Record<string, unknown>[]>(
      `users?id=eq.${encodeURIComponent(userId)}` +
        "&select=account_status&limit=1",
    );
    return rows[0]?.account_status === "active";
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
    await this.rest<unknown>("user_saved_terms?on_conflict=user_id,term_key", {
      method: "POST",
      headers: { Prefer: "resolution=ignore-duplicates,return=minimal" },
      body: JSON.stringify({ user_id: userId, term_key: termKey }),
    });
  }

  async remove(userId: string, termKey: string): Promise<void> {
    await this.rest<unknown>(
      `user_saved_terms?user_id=eq.${encodeURIComponent(userId)}` +
        `&term_key=eq.${encodeURIComponent(termKey)}`,
      { method: "DELETE", headers: { Prefer: "return=minimal" } },
    );
  }

  private async rest<T>(path: string, init: RequestInit = {}): Promise<T> {
    return await postgrestJson<T>(
      this.fetch_impl,
      `${this.supabase_url}/rest/v1/${path}`,
      {
        ...init,
        headers: {
          ...serviceRoleHeaders(this.service_role_key),
          ...init.headers as Record<string, string> | undefined,
        },
      },
      (code, message, transient) =>
        new SavedTermsRepositoryError(code, message, transient),
    );
  }
}
