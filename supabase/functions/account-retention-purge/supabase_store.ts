import { RETENTION_DAYS, type WithdrawalPurgeStore } from "./finalize.ts";
import { serviceRoleHeaders } from "../_shared/supabase.ts";

export class SupabaseWithdrawalPurgeStore implements WithdrawalPurgeStore {
  constructor(
    private url: string,
    private key: string,
    private fetcher: typeof fetch = fetch,
  ) {}
  private async call(path: string, method = "GET", body?: unknown) {
    const response = await this.fetcher(this.url + path, {
      method,
      headers: serviceRoleHeaders(this.key),
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error("purge_upstream_" + response.status);
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  }
  async getAccount(userId: string) {
    const rows = await this.call(
      "/rest/v1/users?id=eq." + encodeURIComponent(userId) +
        "&select=account_status,deletion_requested_at,purged_at",
    );
    return rows[0] ?? null;
  }
  async revokeProviderAccess(userId: string) {
    // Revocation happens while the withdrawing person can provide a fresh token.
    // The delayed worker never fabricates success or stores long-lived OAuth tokens.
    const rows = await this.call(
      "/rest/v1/users?id=eq." + encodeURIComponent(userId) +
        "&select=deletion_provider_revoked_at",
    );
    if (!rows[0]?.deletion_provider_revoked_at) {
      throw new Error("provider_revocation_required");
    }
  }
  async deletePrivateStorage(userId: string) {
    const paths: string[] = [];
    const root = userId + "/";
    const visit = async (prefix: string, depth: number) => {
      if (depth > 12) throw new Error("storage_depth_exceeded");
      for (let offset = 0;; offset += 100) {
        const entries = await this.call(
          "/storage/v1/object/list/soolgyul-private",
          "POST",
          {
            prefix,
            limit: 100,
            offset,
            sortBy: { column: "name", order: "asc" },
          },
        );
        if (!Array.isArray(entries)) throw new Error("invalid_storage_listing");
        for (const entry of entries) {
          if (
            typeof entry.name !== "string" || entry.name.includes("/") ||
            [".", ".."].includes(entry.name)
          ) throw new Error("invalid_storage_path");
          const path = prefix + "/" + entry.name;
          if (!path.startsWith(root)) throw new Error("invalid_storage_path");
          if (entry.id == null) await visit(path, depth + 1);
          else paths.push(path);
          if (paths.length > 10000) {
            throw new Error("storage_batch_limit_exceeded");
          }
        }
        if (entries.length < 100) break;
      }
    };
    await visit(userId, 0);
    for (let i = 0; i < paths.length; i += 100) {
      await this.call("/storage/v1/object/soolgyul-private", "DELETE", {
        prefixes: paths.slice(i, i + 100),
      });
    }
  }
  async preserveRecordsAndClearAccount(userId: string) {
    const count = await this.call(
      "/rest/v1/rpc/soolgyul_finalize_withdrawn_account_data",
      "POST",
      { target_user_id: userId },
    );
    if (!Number.isInteger(count) || count < 0) {
      throw new Error("invalid_retained_count");
    }
    return count;
  }
  async deleteAuthAccount(userId: string) {
    const response = await this.fetcher(
      this.url + "/auth/v1/admin/users/" + encodeURIComponent(userId),
      {
        method: "DELETE",
        headers: serviceRoleHeaders(this.key),
        body: JSON.stringify({ should_soft_delete: false }),
        signal: AbortSignal.timeout(15000),
      },
    );
    if (!response.ok && response.status !== 404) {
      throw new Error("auth_deletion_failed");
    }
  }
  async listDueUsers() {
    const requestedBefore = new Date(
      Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000,
    );
    return await this.call(
      "/rest/v1/users?select=id&or=(purged_at.not.is.null,and(deletion_requested_at.lte." +
        encodeURIComponent(requestedBefore.toISOString()) +
        ",deletion_provider_revoked_at.not.is.null))&order=deletion_requested_at.asc&limit=5",
    );
  }
}
