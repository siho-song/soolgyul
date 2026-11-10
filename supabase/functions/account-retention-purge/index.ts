import { finalizeWithdrawnAccount } from "./finalize.ts";
import { SupabaseWithdrawalPurgeStore } from "./supabase_store.ts";

export async function handleRetentionJob(
  request: Request,
  env = Deno.env.get,
  fetcher: typeof fetch = fetch,
) {
  const reply = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), {
      status,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    });
  const secret = env("ACCOUNT_RETENTION_JOB_SECRET");
  // This is a dedicated scheduler credential, never an end-user JWT/public key.
  if (!secret || request.headers.get("authorization") !== "Bearer " + secret) {
    return reply(401, { error_code: "unauthorized" });
  }
  if (request.method !== "POST") {
    return reply(405, { error_code: "method_not_allowed" });
  }
  const url = env("SUPABASE_URL"), key = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    return reply(503, { error_code: "server_configuration_missing" });
  }
  try {
    const store = new SupabaseWithdrawalPurgeStore(url, key, fetcher);
    const due = await store.listDueUsers();
    let completed = 0, failed = 0;
    for (const row of due) {
      try {
        await store.markAttempt(row.id);
        await finalizeWithdrawnAccount(store, row.id);
        completed++;
      } catch {
        failed++;
      } // Do not emit identifiers or upstream payloads to logs.
    }
    return reply(failed ? 503 : 200, { completed, failed });
  } catch {
    return reply(503, { error_code: "retention_job_failed" });
  }
}
if (import.meta.main) Deno.serve((request) => handleRetentionJob(request));
