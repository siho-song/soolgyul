import { handleAccountDeletion } from "../../account-deletion/index.ts";
import { prepareProviderRevocation } from "../../account-deletion/providers.ts";
import {
  finalizeWithdrawnAccount,
  type WithdrawalPurgeStore,
} from "../../account-retention-purge/finalize.ts";
import { handleRetentionJob } from "../../account-retention-purge/index.ts";
import { SupabaseWithdrawalPurgeStore } from "../../account-retention-purge/supabase_store.ts";
import { assert } from "../helpers/assert.ts";

Deno.test("Apple revocation exchanges code, verifies signature/subject/audience and revokes refresh token", async () => {
  const keys = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const encode = (bytes: Uint8Array) =>
    btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll(
      "/",
      "_",
    ).replaceAll("=", "");
  const part = (v: unknown) =>
    encode(new TextEncoder().encode(JSON.stringify(v)));
  const signing = part({ alg: "RS256", kid: "test" }) + "." +
    part({
      iss: "https://appleid.apple.com",
      aud: "app",
      sub: "owner",
      exp: Math.floor(Date.now() / 1000) + 60,
    });
  const jwt = signing + "." +
    encode(
      new Uint8Array(
        await crypto.subtle.sign(
          "RSASSA-PKCS1-v1_5",
          keys.privateKey,
          new TextEncoder().encode(signing),
        ),
      ),
    );
  const publicKey = await crypto.subtle.exportKey("jwk", keys.publicKey);
  let revoked = false;
  const fetcher = (async (url: string | URL | Request, init?: RequestInit) => {
    if (String(url).endsWith("/token")) {
      return response({ id_token: jwt, refresh_token: "refresh" });
    }
    if (String(url).endsWith("/keys")) {
      return response({ keys: [{ ...publicKey, kid: "test" }] });
    }
    if (String(url).endsWith("/revoke")) {
      const body = new URLSearchParams(String(init?.body));
      assert(
        body.get("token") === "refresh" && body.get("client_id") === "app",
      );
      revoked = true;
      return response({});
    }
    throw new Error("unexpected request");
  }) as typeof fetch;
  const appleEnv = (
    name: string,
  ) => ({
    APPLE_NATIVE_CLIENT_ID: "app",
    APPLE_NATIVE_CLIENT_SECRET: "test-secret",
  }[name]);
  const revoke = await prepareProviderRevocation(
    { provider: "apple", id: "owner" },
    { apple_client: "native", authorization_code: "code" },
    appleEnv,
    fetcher,
  );
  assert(!revoked);
  await revoke();
  assert(revoked);
  let mismatch = false;
  try {
    await prepareProviderRevocation(
      { provider: "apple", id: "other" },
      { apple_client: "native", authorization_code: "code" },
      appleEnv,
      fetcher,
    );
  } catch {
    mismatch = true;
  }
  assert(mismatch);
});
const env = (
  name: string,
) => ({
  SUPABASE_URL: "https://db.test",
  SUPABASE_ANON_KEY: "public",
  SUPABASE_SERVICE_ROLE_KEY: "service",
  GOOGLE_REVOCATION_CLIENT_IDS: "client",
}[name]);
const response = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status });
function req(body?: unknown, authorized = true) {
  return new Request("https://edge.test", {
    method: body ? "POST" : "GET",
    headers: authorized ? { Authorization: "Bearer user" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
}
Deno.test("account deletion verifies authentication and does not log or return upstream errors", async () => {
  let count = 0;
  const fetcher = (async () => {
    count++;
    return response({ secret: "not exposed" }, 401);
  }) as typeof fetch;
  assert(
    (await handleAccountDeletion(req(undefined, false), env, fetcher))
          .status === 401 && count === 0,
  );
  const result = await handleAccountDeletion(req(), env, fetcher);
  assert(
    result.status === 401 && !(await result.text()).includes("not exposed"),
  );
});
Deno.test("deletion confirms owner proof, schedules, revokes and marks current generation only", async () => {
  const calls: string[] = [];
  const fetcher = (async (url: string | URL | Request, init?: RequestInit) => {
    const path = String(url);
    calls.push(path);
    if (path.endsWith("/auth/v1/user")) {
      return response({
        id: "owner",
        identities: [{
          provider: "google",
          identity_data: { sub: "google-user" },
        }],
      });
    }
    if (path.endsWith("/soolgyul_get_my_deletion_state")) {
      return response({ deletion_state: "active" });
    }
    if (path.includes("tokeninfo")) {
      return response({ sub: "google-user", aud: "client" });
    }
    if (path.endsWith("/soolgyul_request_account_deletion")) {
      // Scheduled by the server for the verified session's own account.
      assert(JSON.parse(String(init?.body)).target_user_id === "owner");
      assert(
        new Headers(init?.headers).get("authorization") === "Bearer service",
      );
      return response({ deletion_state: "scheduled", requested_at: "now" });
    }
    if (path.endsWith("/revoke")) return response({});
    if (path.endsWith("/soolgyul_mark_deletion_provider_revoked")) {
      assert(JSON.parse(String(init?.body)).target_user_id === "owner");
      return response(true);
    }
    if (path.includes("/logout")) return response({});
    throw new Error("unexpected call");
  }) as typeof fetch;
  const result = await handleAccountDeletion(
    req({
      action: "request",
      confirmed: true,
      user_id: "attacker",
      proof: { access_token: "temporary" },
    }),
    env,
    fetcher,
  );
  assert(result.status === 200);
  assert(
    calls.findIndex((x) => x.endsWith("/soolgyul_request_account_deletion")) <
      calls.findIndex((x) => x.endsWith("/revoke")),
  );
});
Deno.test("wrong provider owner/client and missing Apple configuration fail closed", async () => {
  for (
    const info of [{ sub: "other", aud: "client" }, {
      sub: "owner",
      aud: "unrelated-app",
    }]
  ) {
    let failed = false;
    try {
      await prepareProviderRevocation(
        { provider: "google", id: "owner" },
        { access_token: "secret" },
        env,
        (async () => response(info)) as typeof fetch,
      );
    } catch {
      failed = true;
    }
    assert(failed);
  }
  let appleCalled = false, failed = false;
  try {
    await prepareProviderRevocation(
      { provider: "apple", id: "owner" },
      { authorization_code: "code", apple_client: "native" },
      env,
      (async () => {
        appleCalled = true;
        return response({});
      }) as typeof fetch,
    );
  } catch {
    failed = true;
  }
  assert(failed && !appleCalled);
});
Deno.test("retention worker rejects user JWT without touching database", async () => {
  const result = await handleRetentionJob(
    req({}),
    (name) => name === "ACCOUNT_RETENTION_JOB_SECRET" ? "scheduler" : env(name),
    (() => {
      throw new Error("must not fetch");
    }) as typeof fetch,
  );
  assert(result.status === 401);
});
Deno.test("retention worker purges each due account and counts what failed", async () => {
  const deletedAuth: string[] = [];
  const tried: string[] = [];
  const fetcher = (async (url: string | URL | Request, init?: RequestInit) => {
    const path = String(url);
    if (path.includes("/rest/v1/users?select=id&")) {
      // The account waited on longest comes first, so one that keeps
      // failing does not hold the others back.
      assert(path.includes("order=purge_attempted_at.asc.nullsfirst,"));
      return response([{ id: "gone" }, { id: "stuck" }]);
    }
    if (init?.method === "PATCH") {
      assert("purge_attempted_at" in JSON.parse(String(init.body)));
      tried.push(path.split("id=eq.").pop()!);
      return response(null);
    }
    if (path.includes("/auth/v1/admin/users/")) {
      const id = path.split("/").pop()!;
      deletedAuth.push(id);
      return response({}, id === "stuck" ? 500 : 200);
    }
    // The support inbox has nothing due on this run.
    if (path.includes("/rpc/soolgyul_due_support_inquiries")) {
      return response([]);
    }
    if (path.includes("/rpc/soolgyul_stale_inquiry_uploads")) {
      return response([]);
    }
    // Both accounts were cleared before; only their Auth users remain.
    return response([{
      account_status: "scheduled_deletion",
      deletion_requested_at: "2026-08-02T00:00:00Z",
      purged_at: "2026-09-02T00:00:00Z",
    }]);
  }) as typeof fetch;
  const result = await handleRetentionJob(
    new Request("https://edge.test", {
      method: "POST",
      headers: { Authorization: "Bearer scheduler" },
    }),
    (name) => name === "ACCOUNT_RETENTION_JOB_SECRET" ? "scheduler" : env(name),
    fetcher,
  );
  assert(result.status === 503);
  assert(
    JSON.stringify(await result.json()) ===
      '{"completed":1,"failed":1,"inquiries":{"closed":0,"failed":0,"stale_uploads":0}}',
  );
  assert(deletedAuth.join() === "gone,stuck");
  assert(tried.join() === "gone,stuck");
});
Deno.test("retention worker removes an old inquiry's photos before closing it, and photos nobody sent", async () => {
  const photo = (inquiry: string, file: string) =>
    "a0000000-0000-4000-8000-000000000001/inquiries/" + inquiry + "/" + file;
  const done = "b0000000-0000-4000-8000-000000000001";
  const stuck = "b0000000-0000-4000-8000-000000000002";
  const left = photo("b0000000-0000-4000-8000-000000000003", "0-c.jpg");
  const steps: string[] = [];
  const fetcher = (async (url: string | URL | Request, init?: RequestInit) => {
    const path = String(url);
    const body = init?.body ? JSON.parse(String(init.body)) : null;
    if (path.includes("/rest/v1/users?select=id&")) return response([]);
    if (path.includes("/rpc/soolgyul_due_support_inquiries")) {
      return response([
        { id: done, attachment_paths: [photo(done, "0-a.jpg")] },
        { id: stuck, attachment_paths: [] },
      ]);
    }
    if (path.includes("/rpc/soolgyul_stale_inquiry_uploads")) {
      return response([left]);
    }
    if (path.includes("/storage/v1/object/soolgyul-private")) {
      assert(init?.method === "DELETE");
      steps.push("files:" + body.prefixes.join());
      return response([]);
    }
    if (path.includes("/rpc/soolgyul_close_support_inquiry")) {
      steps.push("close:" + body.target_inquiry_id);
      return response(true, body.target_inquiry_id === stuck ? 500 : 200);
    }
    throw new Error("unexpected call " + path);
  }) as typeof fetch;
  const result = await handleRetentionJob(
    new Request("https://edge.test", {
      method: "POST",
      headers: { Authorization: "Bearer scheduler" },
    }),
    (name) => name === "ACCOUNT_RETENTION_JOB_SECRET" ? "scheduler" : env(name),
    fetcher,
  );
  // One inquiry could not be closed, so the run asks to be looked at.
  assert(result.status === 503);
  assert(
    JSON.stringify(await result.json()) ===
      '{"completed":0,"failed":0,"inquiries":{"closed":1,"failed":1,"stale_uploads":1}}',
  );
  assert(
    steps.join(" ") ===
      "files:" + photo(done, "0-a.jpg") + " close:" + done + " close:" + stuck +
        " files:" + left,
  );
});
Deno.test("inquiry photo deletion refuses a path outside a member's inquiries folder", async () => {
  let called = false, failed = false;
  try {
    await new SupabaseWithdrawalPurgeStore(
      "https://db.test",
      "secret",
      (async () => {
        called = true;
        return response([]);
      }) as typeof fetch,
    ).deleteInquiryUploads(["editorial/cover.jpg"]);
  } catch {
    failed = true;
  }
  assert(failed && !called);
});
Deno.test("private storage deletion traverses folders, paginates, and deletes only exact user prefix", async () => {
  const deleted: string[] = [];
  const fetcher = (async (url: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body));
    if (String(url).includes("/object/list/")) {
      // A second pass finds the folder empty.
      if (deleted.length > 0) return response([]);
      if (body.prefix === "u") {
        return response([{ id: null, name: "inquiries" }]);
      }
      if (body.offset === 0) {
        return response(
          Array.from(
            { length: 100 },
            (_, i) => ({ id: String(i), name: i + ".jpg" }),
          ),
        );
      }
      return response([{ id: "last", name: "last.jpg" }]);
    }
    deleted.push(...body.prefixes);
    return response([]);
  }) as typeof fetch;
  await new SupabaseWithdrawalPurgeStore("https://db.test", "secret", fetcher)
    .deletePrivateStorage("u");
  assert(
    deleted.length === 101 &&
      deleted.every((p) => p.startsWith("u/inquiries/")),
  );
});

// The purge worker over a fake store: order, failure stops, and what cannot be purged.
function purgeFixture(failure = "") {
  const calls: string[] = [];
  const account = {
    account_status: "scheduled_deletion",
    deletion_requested_at: "2026-08-02T00:00:00Z",
    purged_at: null as string | null,
  };
  const run = async (name: string) => {
    calls.push(name);
    if (name === failure) throw new Error(name);
  };
  const store: WithdrawalPurgeStore = {
    getAccount: async () => account,
    deletePrivateStorage: () => run("storage"),
    preserveRecordsAndClearAccount: async () => {
      await run("retain");
      account.purged_at = "2026-09-23T00:00:00Z";
      return 2;
    },
    deleteAuthAccount: () => run("auth"),
  };
  return { store, calls, account };
}
const purgeNow = new Date("2026-09-23T00:00:00Z");
Deno.test("withdrawal preserves records before Auth cascade and supports Auth retry", async () => {
  const f = purgeFixture("auth");
  try {
    await finalizeWithdrawnAccount(f.store, "u", purgeNow);
  } catch { /* Auth unavailable */ }
  assert(f.calls.join(",") === "storage,retain,auth");
  f.store.deleteAuthAccount = async () => {
    f.calls.push("retry_auth");
  };
  await finalizeWithdrawnAccount(f.store, "u", purgeNow);
  assert(f.calls.join(",") === "storage,retain,auth,retry_auth");
});
Deno.test("withdrawal failures never proceed to downstream destructive steps", async () => {
  for (
    const [failure, expected] of [["storage", "storage"], [
      "retain",
      "storage,retain",
    ]]
  ) {
    const f = purgeFixture(failure);
    let failed = false;
    try {
      await finalizeWithdrawnAccount(f.store, "u", purgeNow);
    } catch {
      failed = true;
    }
    assert(failed && f.calls.join(",") === expected);
  }
});
Deno.test("active, missing-deadline and not-due accounts cannot be purged", async () => {
  for (
    const change of [{ account_status: "active" }, {
      deletion_requested_at: null,
    }, { deletion_requested_at: "2026-12-02T00:00:00Z" }]
  ) {
    const f = purgeFixture();
    Object.assign(f.account, change);
    let failed = false;
    try {
      await finalizeWithdrawnAccount(f.store, "u", purgeNow);
    } catch {
      failed = true;
    }
    assert(failed && f.calls.length === 0);
  }
});
Deno.test("already absent account requires no further work", async () => {
  const f = purgeFixture();
  f.store.getAccount = async () => null;
  const result = await finalizeWithdrawnAccount(f.store, "u", purgeNow);
  assert(result.already_absent && f.calls.length === 0);
});
