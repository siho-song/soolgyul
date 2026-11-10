import type { EdgeAuthContext } from "../../_shared/auth.ts";
import { SoolgyulEdgeError } from "../../_shared/errors.ts";
import { completeProfile } from "../../_shared/profile/complete_profile.ts";
import type { ProfileRepository } from "../../_shared/profile/repository.ts";
import { SupabaseProfileRepository } from "../../_shared/profile/repository.ts";
import { handleCompleteProfileRequest } from "../../complete-profile/index.ts";

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

const auth: EdgeAuthContext = {
  user_id: "user-1",
  auth_provider: "kakao",
  provider_user_id: "kakao-1",
};

const validBody = {
  idempotency_key: "10000000-0000-4000-8000-000000000001",
  display_name: "테스터",
  birth_year: 1990,
  birth_date: "1990-03-21",
  age_19_or_over_confirmed: true,
  terms_version: "soolgyul-terms-v1",
  privacy_version: "soolgyul-privacy-v1",
  marketing_version: "soolgyul-marketing-v1",
  terms_accepted: true,
  privacy_accepted: true,
  marketing_opt_in: false,
};

Deno.test("complete-profile rejects invalid, missing, future and inconsistent birth dates", async () => {
  const repository: ProfileRepository = {
    getStatus() {
      throw new Error("must not read");
    },
    upsertProfile() {
      throw new Error("must not store");
    },
  };
  for (
    const value of [
      "2001-02-29",
      "1990-04-31",
      "1990-13-01",
      "1990-00-01",
      "1990-03-00",
      "2990-03-21",
      "1890-03-21",
      "1990-3-21",
      "1990-03-21T00:00:00Z",
      "1991-03-21",
      null,
      19900321,
    ]
  ) {
    const response = await handleCompleteProfileRequest(
      request({ ...validBody, birth_date: value }),
      repository,
      () => Promise.resolve(auth),
    );
    assertEquals(response.status, 400);
    assertEquals(await response.json(), { error_code: "birth_date_invalid" });
  }
  const { birth_date: _removed, ...oldBody } = validBody;
  const response = await handleCompleteProfileRequest(
    request(oldBody),
    repository,
    () => Promise.resolve(auth),
  );
  assertEquals(response.status, 400);
});

function request(body: unknown = validBody): Request {
  return new Request("https://example.test/functions/v1/complete-profile", {
    method: "POST",
    headers: {
      Authorization: "Bearer user-token",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

Deno.test("complete-profile gender requires explicit consent and passes through to RPC", async () => {
  let calls = 0;
  const repository = new SupabaseProfileRepository(
    "https://example.test",
    "anon",
    "Bearer test",
    async (url, init) => {
      calls++;
      assertEquals(
        String(url).endsWith("/soolgyul_complete_my_profile"),
        true,
      );
      const body = JSON.parse(String(init?.body));
      assertEquals(body.p_birth_date, "1990-03-21");
      assertEquals("p_birth_year" in body, false);
      assertEquals(body.p_gender, "female");
      assertEquals(body.p_gender_consent_accepted, true);
      return Response.json({
        profile_complete: true,
        display_name: "테스터",
        age_19_or_over_confirmed: true,
        terms_version: validBody.terms_version,
        privacy_version: validBody.privacy_version,
        marketing_opt_in: false,
        deletion_state: "active",
      });
    },
  );
  for (
    const extra of [
      { gender: "female" },
      { gender: "invalid", gender_consent_accepted: true },
      { gender: "male", gender_consent_accepted: false },
      { gender: null, gender_consent_accepted: true },
      { gender: 12, gender_consent_accepted: true },
      { gender: null, gender_consent_accepted: "true" },
    ]
  ) {
    const result = await handleCompleteProfileRequest(
      request({ ...validBody, ...extra }),
      repository,
      () => Promise.resolve(auth),
    );
    assertEquals(result.status, 400);
  }
  assertEquals(calls, 0);
  const result = await handleCompleteProfileRequest(
    request({ ...validBody, gender: "female", gender_consent_accepted: true }),
    repository,
    () => Promise.resolve(auth),
  );
  assertEquals(result.status, 200);
  assertEquals(calls, 1);
});

Deno.test("complete-profile saves the approved account-completion contract", async () => {
  let storedInput: unknown;
  const repository: ProfileRepository = {
    getStatus() {
      throw new Error("must not read");
    },
    upsertProfile(input) {
      storedInput = input;
      return Promise.resolve({
        profile_complete: true,
        display_name: input.display_name,
        age_19_or_over_confirmed: true,
        terms_version: input.terms_version,
        privacy_version: input.privacy_version,
        marketing_opt_in: input.marketing_opt_in,
        deletion_state: "active",
      });
    },
  };

  const response = await handleCompleteProfileRequest(
    request(),
    repository,
    () => Promise.resolve(auth),
  );

  assertEquals(response.status, 200);
  assertEquals(storedInput, {
    user_id: "user-1",
    ...validBody,
  });
  assertEquals(await response.json(), {
    profile_complete: true,
    display_name: "테스터",
    age_19_or_over_confirmed: true,
    terms_version: "soolgyul-terms-v1",
    privacy_version: "soolgyul-privacy-v1",
    marketing_opt_in: false,
    deletion_state: "active",
  });
});

Deno.test("complete-profile rejects unauthenticated and malformed requests", async () => {
  const repository: ProfileRepository = {
    getStatus() {
      throw new Error("must not read");
    },
    upsertProfile() {
      throw new Error("must not store");
    },
  };
  const unauthorized = await handleCompleteProfileRequest(
    request(),
    repository,
    () => Promise.resolve(null),
  );
  assertEquals(unauthorized.status, 401);
  assertEquals(await unauthorized.json(), {
    error_code: "authorization_required",
  });

  const malformed = await handleCompleteProfileRequest(
    request({ display_name: "테스터" }),
    repository,
    () => Promise.resolve(auth),
  );
  assertEquals(malformed.status, 400);
  assertEquals(await malformed.json(), {
    error_code: "complete_profile_request_invalid",
  });
});

Deno.test("complete-profile exposes safe authorization and retry conflicts", async () => {
  for (
    const [code, expectedStatus] of [
      ["unsupported_auth_provider", 403],
      ["active_account_required", 403],
      ["idempotency_key_reused", 409],
    ] as const
  ) {
    const repository: ProfileRepository = {
      getStatus() {
        throw new Error("must not read");
      },
      upsertProfile() {
        throw new SoolgyulEdgeError(code);
      },
    };
    const response = await handleCompleteProfileRequest(
      request(),
      repository,
      () => Promise.resolve(auth),
    );
    assertEquals(response.status, expectedStatus);
    assertEquals(await response.json(), { error_code: code });
  }
});

Deno.test("complete-profile GET returns the current server profile state", async () => {
  const repository: ProfileRepository = {
    getStatus() {
      return Promise.resolve({
        profile_complete: false,
        display_name: null,
        age_19_or_over_confirmed: false,
        terms_version: null,
        privacy_version: null,
        marketing_opt_in: false,
        deletion_state: "active" as const,
      });
    },
    upsertProfile() {
      throw new Error("must not store");
    },
  };
  const response = await handleCompleteProfileRequest(
    new Request("https://example.test/functions/v1/complete-profile", {
      method: "GET",
      headers: { Authorization: "Bearer user-token" },
    }),
    repository,
    () => Promise.resolve(auth),
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    profile_complete: false,
    display_name: null,
    age_19_or_over_confirmed: false,
    terms_version: null,
    privacy_version: null,
    marketing_opt_in: false,
    deletion_state: "active",
  });
});

Deno.test("complete-profile enforces OAuth provider, terms, privacy, and age gates", async () => {
  const stored: unknown[] = [];
  const repository = {
    upsertProfile(input: unknown) {
      stored.push(input);
      return Promise.resolve({
        profile_complete: true,
        display_name: "민지",
        age_19_or_over_confirmed: true,
        terms_version: "soolgyul-terms-v1",
        privacy_version: "soolgyul-privacy-v1",
        marketing_opt_in: false,
        deletion_state: "active" as const,
      });
    },
  };

  await assertRejects(() =>
    completeProfile(repository, {
      user_id: "user-incomplete",
      auth_provider: "email" as "google",
      provider_user_id: "email-1",
    }, {
      idempotency_key: "10000000-0000-4000-8000-000000000001",
      display_name: "민지",
      birth_year: 1990,
      birth_date: "1990-03-21",
      age_19_or_over_confirmed: true,
      terms_version: "soolgyul-terms-v1",
      privacy_version: "soolgyul-privacy-v1",
      marketing_version: "soolgyul-marketing-v1",
      terms_accepted: true,
      privacy_accepted: true,
      marketing_opt_in: false,
    }), "unsupported_auth_provider");

  await assertRejects(() =>
    completeProfile(repository, {
      user_id: "user-incomplete",
      auth_provider: "google",
      provider_user_id: "google-1",
    }, {
      idempotency_key: "10000000-0000-4000-8000-000000000002",
      display_name: "민지",
      birth_year: new Date().getFullYear() - 18,
      birth_date: `${new Date().getFullYear() - 18}-01-01`,
      age_19_or_over_confirmed: true,
      terms_version: "soolgyul-terms-v1",
      privacy_version: "soolgyul-privacy-v1",
      marketing_version: "soolgyul-marketing-v1",
      terms_accepted: true,
      privacy_accepted: true,
      marketing_opt_in: false,
    }), "age_gate_required");

  await assertRejects(() =>
    completeProfile(repository, {
      user_id: "user-incomplete",
      auth_provider: "apple",
      provider_user_id: "apple-1",
    }, {
      idempotency_key: "10000000-0000-4000-8000-000000000003",
      display_name: "민지",
      birth_year: 1990,
      birth_date: "1990-03-21",
      age_19_or_over_confirmed: true,
      terms_version: "soolgyul-terms-v1",
      privacy_version: "soolgyul-privacy-v1",
      marketing_version: "soolgyul-marketing-v1",
      terms_accepted: false,
      privacy_accepted: true,
      marketing_opt_in: false,
    }), "terms_and_privacy_required");

  const status = await completeProfile(repository, {
    user_id: "user-incomplete",
    auth_provider: "google",
    provider_user_id: "google-1",
  }, {
    idempotency_key: "10000000-0000-4000-8000-000000000004",
    display_name: "민지",
    birth_year: 1990,
    birth_date: "1990-03-21",
    age_19_or_over_confirmed: true,
    terms_version: "soolgyul-terms-v1",
    privacy_version: "soolgyul-privacy-v1",
    marketing_version: "soolgyul-marketing-v1",
    terms_accepted: true,
    privacy_accepted: true,
    marketing_opt_in: false,
  });

  assertEquals(status.profile_complete, true);
  assertEquals(stored.length, 1);
});
