import {
  resolveTasteCardAuth,
  tasteCardErrorResponse,
  tasteCardJsonBody,
  TasteCardOrchestrationError,
} from "../_shared/soolgyul_edge.ts";
import { TasteCardRepositoryError } from "../_shared/taste_card/repository.ts";
import { TasteCardContractError } from "../_shared/taste_card/serialization.ts";
import { handleTasteCardConversionRequest } from "../taste-card-conversions/index.ts";
import { handleTasteCardGenerationRequest } from "../taste-card-generations/index.ts";
import { handleTasteCardResultRequest } from "../taste-card-results/index.ts";
import type { TasteCardOrchestratorDependencies } from "../_shared/taste_card/orchestrator.ts";

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}

function assertRejects(
  fn: () => unknown | Promise<unknown>,
  code: string,
): Promise<void> {
  return Promise.resolve()
    .then(fn)
    .then(
      () => {
        throw new Error(`Expected rejection ${code}`);
      },
      (error) => {
        if (error?.code !== code) {
          throw new Error(
            `Expected rejection ${code}, received ${error?.code ?? error}`,
          );
        }
      },
    );
}

Deno.test("JSON transport rejects oversized bodies and malformed JSON", async () => {
  const oversized = new Request("https://example.com", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ memo: "가".repeat(70_000) }),
  });
  await assertRejects(
    () => tasteCardJsonBody(oversized),
    "json_body_too_large",
  );

  const malformed = new Request("https://example.com", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{",
  });
  await assertRejects(() => tasteCardJsonBody(malformed), "invalid_json");
});

Deno.test("error responses use an explicit status table and hide unknown codes", async () => {
  const request = new Request("https://example.com");
  const cases: Array<[unknown, number, string]> = [
    [
      new TasteCardContractError("unknown_wire_schema_version", "$request"),
      400,
      "unknown_wire_schema_version",
    ],
    [
      new TasteCardOrchestrationError("anonymous_generation_limit_reached"),
      429,
      "anonymous_generation_limit_reached",
    ],
    [
      new TasteCardOrchestrationError("anonymous_result_expired"),
      410,
      "anonymous_result_expired",
    ],
    [new TasteCardRepositoryError("P0002"), 404, "result_not_found"],
    [
      new TasteCardRepositoryError("42501", "owned by another account"),
      403,
      "access_denied",
    ],
    [
      new TasteCardOrchestrationError("converted_snapshot_mismatch"),
      500,
      "internal_error",
    ],
    [new TasteCardRepositoryError("http_502"), 500, "internal_error"],
    [{ code: "unknown_wire_schema_version" }, 500, "internal_error"],
    [new Error("boom"), 500, "internal_error"],
  ];
  for (const [error, status, code] of cases) {
    const response = tasteCardErrorResponse(request, error);
    assertEquals(response.status, status);
    assertEquals(await response.json(), { error_code: code });
  }
});

Deno.test("anonymous callers must present the anon key and unknown bearers are checked", async () => {
  Deno.env.set("SUPABASE_URL", "https://example.supabase.co");
  Deno.env.set("SUPABASE_ANON_KEY", "anon-key-for-tests");
  try {
    const resolve = (headers: Record<string, string>) =>
      resolveTasteCardAuth(new Request("https://example.test", { headers }));
    await assertRejects(() => resolve({}), "authorization_required");
    await assertRejects(
      () => resolve({ Authorization: "Basic abc" }),
      "authorization_required",
    );
    assertEquals(
      await resolve({ Authorization: "Bearer anon-key-for-tests" }),
      null,
    );
    const originalFetch = globalThis.fetch;
    globalThis.fetch = () => Promise.resolve(new Response("", { status: 401 }));
    try {
      await assertRejects(
        () => resolve({ Authorization: "Bearer not-the-anon-key" }),
        "authorization_rejected",
      );
      await assertRejects(
        () => resolve({ Authorization: "Bearer sb_publishable_unknown" }),
        "authorization_rejected",
      );
      globalThis.fetch = () => Promise.resolve(new Response("{}"));
      assertEquals(
        await resolve({ Authorization: "Bearer sb_publishable_project" }),
        null,
      );
      // The legacy anon key is a JWT with role "anon"; when the runtime's
      // SUPABASE_ANON_KEY is a different key, Auth still vouches for it.
      const jwt = (claims: Record<string, unknown>) =>
        "eyJhbGciOiJIUzI1NiJ9." +
        btoa(JSON.stringify(claims)).replace(/=+$/, "") + ".sig";
      assertEquals(
        await resolve({ Authorization: `Bearer ${jwt({ role: "anon" })}` }),
        null,
      );
      globalThis.fetch = () =>
        Promise.resolve(new Response("", { status: 401 }));
      await assertRejects(
        () => resolve({ Authorization: `Bearer ${jwt({ role: "anon" })}` }),
        "authorization_rejected",
      );
      // A user session (role "authenticated") is still checked as a user.
      await assertRejects(
        () =>
          resolve({
            Authorization: `Bearer ${jwt({ role: "authenticated" })}`,
          }),
        "authorization_rejected",
      );
    } finally {
      globalThis.fetch = originalFetch;
    }
  } finally {
    Deno.env.delete("SUPABASE_URL");
    Deno.env.delete("SUPABASE_ANON_KEY");
  }
});

Deno.test("missing service configuration fails with a CORS-bearing 503", async () => {
  for (const name of ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"]) {
    Deno.env.delete(name);
  }
  const response = await handleTasteCardGenerationRequest(
    new Request("https://example.test/functions/v1/taste-card-generations", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Origin: "https://app.soolgyul.com",
      },
      body: "{}",
    }),
  );
  assertEquals(response.status, 503);
  assertEquals(await response.json(), {
    error_code: "service_configuration_missing",
  });
  assertEquals(
    response.headers.get("Access-Control-Allow-Origin"),
    "https://app.soolgyul.com",
  );
});

Deno.test("taste-card HTTP endpoints handle CORS and fail closed before repository work", async () => {
  const unusedDependencies = {} as TasteCardOrchestratorDependencies;
  const options = await handleTasteCardGenerationRequest(
    new Request("https://example.test/functions/v1/taste-card-generations", {
      method: "OPTIONS",
      headers: { Origin: "https://app.soolgyul.com" },
    }),
    unusedDependencies,
  );
  assertEquals(options.status, 204);
  assertEquals(
    options.headers.get("Access-Control-Allow-Origin"),
    "https://app.soolgyul.com",
  );
  for (const origin of ["https://evil.example", "null"]) {
    const rejected = await handleTasteCardGenerationRequest(
      new Request("https://example.test/functions/v1/taste-card-generations", {
        method: "OPTIONS",
        headers: { Origin: origin },
      }),
      unusedDependencies,
    );
    assertEquals(rejected.headers.has("Access-Control-Allow-Origin"), false);
  }
  Deno.env.set("SOOLGYUL_ALLOWED_ORIGINS", "http://localhost:3000");
  try {
    const local = await handleTasteCardGenerationRequest(
      new Request("https://example.test/functions/v1/taste-card-generations", {
        method: "OPTIONS",
        headers: { Origin: "http://localhost:3000" },
      }),
      unusedDependencies,
    );
    assertEquals(
      local.headers.get("Access-Control-Allow-Origin"),
      "http://localhost:3000",
    );
  } finally {
    Deno.env.delete("SOOLGYUL_ALLOWED_ORIGINS");
  }

  const malformed = await handleTasteCardGenerationRequest(
    new Request("https://example.test/functions/v1/taste-card-generations", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ unexpected: true }),
    }),
    unusedDependencies,
    async () => null,
  );
  assertEquals(malformed.status, 400);

  const unauthorizedConversion = await handleTasteCardConversionRequest(
    new Request("https://example.test/functions/v1/taste-card-conversions", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    }),
    unusedDependencies,
    async () => null,
  );
  assertEquals(unauthorizedConversion.status, 401);

  const invalidDetail = await handleTasteCardResultRequest(
    new Request(
      "https://example.test/functions/v1/taste-card-results?result_id=not-a-uuid",
    ),
    unusedDependencies,
    async () => ({ user_id: "user-one" }),
  );
  assertEquals(invalidDetail.status, 400);

  const unauthorizedDelete = await handleTasteCardResultRequest(
    new Request(
      "https://example.test/functions/v1/taste-card-results?result_id=00000000-0000-4000-8000-000000000001",
      { method: "DELETE" },
    ),
    unusedDependencies,
    async () => null,
  );
  assertEquals(unauthorizedDelete.status, 401);

  const wrongMethod = await handleTasteCardResultRequest(
    new Request(
      "https://example.test/functions/v1/taste-card-results?result_id=00000000-0000-4000-8000-000000000001",
      { method: "PUT" },
    ),
    unusedDependencies,
    async () => ({ user_id: "user-one" }),
  );
  assertEquals(wrongMethod.status, 405);
});
