import {
  handleMarketingPush,
  marketingHoursOpen,
} from "../../marketing-push/index.ts";
import { assert, same } from "../helpers/assert.ts";

// The marketing notification endpoint against a pretend database and
// notification service: what goes out, to whom, when it is refused, and what
// is kept afterwards.

const PUSH = "c0000000-0000-4000-8000-000000000001";
const NOON = new Date("2026-11-13T03:00:00Z"); // 12:00 in Korea

const keyPair = await crypto.subtle.generateKey(
  {
    name: "RSASSA-PKCS1-v1_5",
    modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]),
    hash: "SHA-256",
  },
  true,
  ["sign", "verify"],
);
const pkcs8 = new Uint8Array(
  await crypto.subtle.exportKey("pkcs8", keyPair.privateKey),
);
const serviceAccount = JSON.stringify({
  project_id: "soolgyul-test",
  client_email: "sender@soolgyul-test.iam.gserviceaccount.com",
  private_key: `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...pkcs8)).replace(/(.{64})/g, "$1\n")
  }\n-----END PRIVATE KEY-----\n`,
});

const env = (overrides: Record<string, string | undefined> = {}) => {
  const values: Record<string, string | undefined> = {
    SUPABASE_URL: "https://project.test",
    SUPABASE_ANON_KEY: "sb_publishable_test",
    SUPABASE_SERVICE_ROLE_KEY: "sb_secret_test",
    FIREBASE_SERVICE_ACCOUNT: serviceAccount,
    ...overrides,
  };
  return (name: string) => values[name];
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

type Call = { url: string; headers: Headers; body: string };

/** The database and the notification service; [phones] says what each phone's send answers. */
function backend(
  phones: Record<string, number>,
  start: () => Response = () => new Response(null, { status: 204 }),
) {
  const calls: Call[] = [];
  const fetcher = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const body = String(init?.body ?? "");
    calls.push({ url, headers: new Headers(init?.headers), body });
    if (url === "https://oauth2.googleapis.com/token") {
      return Promise.resolve(json(200, { access_token: "google-access" }));
    }
    if (url.endsWith("/rpc/soolgyul_admin_start_marketing_push")) {
      return Promise.resolve(start());
    }
    if (url.includes("/rpc/soolgyul_marketing_push_devices")) {
      return Promise.resolve(
        json(200, Object.keys(phones).map((token) => ({ token }))),
      );
    }
    if (url.endsWith("/messages:send")) {
      const token = JSON.parse(body).message.token as string;
      return Promise.resolve(json(phones[token], {}));
    }
    if (url.endsWith("/rpc/soolgyul_finish_marketing_push")) {
      return Promise.resolve(new Response(null, { status: 204 }));
    }
    return Promise.resolve(json(500, {}));
  }) as typeof fetch;
  const named = (part: string) => calls.filter((c) => c.url.includes(part));
  return { fetcher, calls, named };
}

const send = (
  body: unknown = { id: PUSH, title: "주말 한 잔", body: "새 글" },
) =>
  new Request("https://edge.test/marketing-push", {
    method: "POST",
    headers: {
      Authorization: "Bearer admin-session",
      "Content-Type": "application/json",
      Origin: "https://admin.soolgyul.com",
    },
    body: JSON.stringify(body),
  });

Deno.test("a send goes to every phone, marked as an advertisement, and is kept with its counts", async () => {
  const server = backend({ "phone-a": 200, "phone-b": 404, "phone-c": 500 });
  const response = await handleMarketingPush(
    send({ id: PUSH, title: " 주말 한 잔 ", body: "새 글" }),
    env(),
    server.fetcher,
    () => NOON,
  );
  same(response.status, 200);
  same(await response.json(), { device_count: 3, sent_count: 1 });
  same(
    response.headers.get("Access-Control-Allow-Origin"),
    "https://admin.soolgyul.com",
  );

  const [started] = server.named("soolgyul_admin_start_marketing_push");
  same(started.headers.get("Authorization"), "Bearer admin-session");
  same(started.headers.get("apikey"), "sb_publishable_test");
  same(JSON.parse(started.body), {
    p_id: PUSH,
    p_title: "주말 한 잔",
    p_body: "새 글",
  });

  const sends = server.named("/messages:send");
  same(sends.length, 3);
  assert(sends[0].url.includes("/projects/soolgyul-test/"));
  same(sends[0].headers.get("Authorization"), "Bearer google-access");
  same(JSON.parse(sends[0].body).message.notification, {
    title: "(광고) 주말 한 잔",
    body: "새 글\n수신거부: 마이페이지 > 약관 및 정책",
  });

  // Only the phone the service no longer knows is forgotten.
  const [finished] = server.named("soolgyul_finish_marketing_push");
  same(finished.headers.get("Authorization"), "Bearer sb_secret_test");
  same(JSON.parse(finished.body), {
    p_id: PUSH,
    p_device_count: 3,
    p_sent_count: 1,
    p_gone_tokens: ["phone-b"],
  });
});

Deno.test("the access token is asked with a claim signed by the service account", async () => {
  const server = backend({});
  await handleMarketingPush(send(), env(), server.fetcher, () => NOON);
  const [asked] = server.named("oauth2.googleapis.com");
  const assertion = new URLSearchParams(asked.body).get("assertion") ?? "";
  const [header, claims, signature] = assertion.split(".");
  const bytes = (part: string) =>
    Uint8Array.from(
      atob(part.replaceAll("-", "+").replaceAll("_", "/")),
      (char) => char.charCodeAt(0),
    );
  assert(
    await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      keyPair.publicKey,
      bytes(signature),
      new TextEncoder().encode(`${header}.${claims}`),
    ),
    "the claim is signed with the account's key",
  );
  const claim = JSON.parse(new TextDecoder().decode(bytes(claims)));
  same([claim.iss, claim.scope, claim.aud, claim.exp - claim.iat], [
    "sender@soolgyul-test.iam.gserviceaccount.com",
    "https://www.googleapis.com/auth/firebase.messaging",
    "https://oauth2.googleapis.com/token",
    600,
  ]);
});

Deno.test("nothing is sent at night in Korea", async () => {
  same(
    ["22:59", "23:00", "11:59", "12:00"].map((utc) =>
      marketingHoursOpen(new Date(`2026-11-13T${utc}:00Z`))
    ),
    // 07:59, 08:00, 20:59 and 21:00 in Korea.
    [false, true, true, false],
  );
  const server = backend({ "phone-a": 200 });
  const response = await handleMarketingPush(
    send(),
    env(),
    server.fetcher,
    () => new Date("2026-11-13T12:00:00Z"),
  );
  same([response.status, await response.json(), server.calls.length], [
    409,
    { error_code: "marketing_push_night_hours" },
    0,
  ]);
});

Deno.test("a refusal by the database sends nothing", async () => {
  for (
    const [code, status, error] of [
      ["42501", 403, "admin_role_required"],
      ["23505", 409, "marketing_push_already_sent"],
      ["22023", 400, "marketing_push_invalid"],
      ["PGRST301", 401, "authorization_rejected"],
    ] as const
  ) {
    const server = backend(
      { "phone-a": 200 },
      () => json(code.startsWith("PGRST") ? 401 : 400, { code, message: "x" }),
    );
    const response = await handleMarketingPush(
      send(),
      env(),
      server.fetcher,
      () => NOON,
    );
    same([response.status, await response.json()], [status, {
      error_code: error,
    }], code);
    same(server.named("/messages:send").length, 0, `${code} sends`);
  }
});

Deno.test("a request that cannot be a send is answered before any work", async () => {
  const server = backend({ "phone-a": 200 });
  const cases: Array<
    [Request, Record<string, string | undefined>, number, string]
  > = [
    [
      send({ id: "not-an-id", title: "제목", body: "내용" }),
      {},
      400,
      "marketing_push_invalid",
    ],
    [send({ id: PUSH, title: "제목" }), {}, 400, "marketing_push_invalid"],
    [
      send(),
      { FIREBASE_SERVICE_ACCOUNT: undefined },
      503,
      "marketing_push_unavailable",
    ],
    [
      send(),
      { FIREBASE_SERVICE_ACCOUNT: "{}" },
      503,
      "marketing_push_unavailable",
    ],
    [
      new Request("https://edge.test/marketing-push", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      }),
      {},
      401,
      "authorization_required",
    ],
    [
      new Request("https://edge.test/marketing-push", {
        method: "POST",
        headers: {
          Authorization: "Bearer admin-session",
          "Content-Type": "application/json",
          Origin: "https://elsewhere.example",
        },
        body: "{}",
      }),
      {},
      403,
      "origin_rejected",
    ],
  ];
  for (const [request, overrides, status, error] of cases) {
    const response = await handleMarketingPush(
      request,
      env(overrides),
      server.fetcher,
      () => NOON,
    );
    same([response.status, await response.json()], [status, {
      error_code: error,
    }]);
  }
  same(server.calls.length, 0, "calls");
});
