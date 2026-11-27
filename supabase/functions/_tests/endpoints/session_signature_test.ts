import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  createLocalJWKSet,
  exportJWK,
  generateKeyPair,
  SignJWT,
} from "npm:jose@6.2.18";
import { resolveCallerBySignature } from "../../_shared/auth.ts";
import { SoolgyulHttpError } from "../../_shared/http.ts";

const MEMBER = "7f0c1a52-2d1e-4c59-9a4e-2f5f6f1f0a11";

type Claims = Record<string, unknown>;

/** A project's signing key, its public half as Auth publishes it, and a token signer. */
async function project() {
  const { publicKey, privateKey } = await generateKeyPair("ES256");
  const keys = createLocalJWKSet({
    keys: [{ ...await exportJWK(publicKey), kid: "key-1", alg: "ES256" }],
  });
  const token = (claims: Claims, expires: string | number = "1h") =>
    new SignJWT({ role: "authenticated", ...claims })
      .setProtectedHeader({ alg: "ES256", kid: "key-1" })
      .setAudience("authenticated")
      .setSubject(MEMBER)
      .setExpirationTime(expires)
      .sign(privateKey);
  return { keys, token };
}

function callWith(bearer: string | null): Request {
  return new Request("https://example.test", {
    headers: bearer === null ? {} : { Authorization: `Bearer ${bearer}` },
  });
}

async function refusal(run: () => Promise<unknown>): Promise<[number, string]> {
  const error = await assertRejects(run, SoolgyulHttpError);
  return [error.status, error.message];
}

Deno.test("a session is told by its signature: a member's passes, anything else is refused", async (t) => {
  Deno.env.set("SUPABASE_URL", "https://example.supabase.co");
  Deno.env.set("SUPABASE_ANON_KEY", "anon-key-for-tests");
  const { keys, token } = await project();
  const resolve = (bearer: string | null) =>
    resolveCallerBySignature(callWith(bearer), keys);
  try {
    await t.step("a member's unexpired session gives the member", async () => {
      assertEquals(await resolve(await token({})), { user_id: MEMBER });
    });

    await t.step("a project key is an anonymous caller", async () => {
      assertEquals(await resolve("anon-key-for-tests"), null);
      assertEquals(await resolve("sb_publishable_abc"), null);
    });

    await t.step("no bearer is asked for one", async () => {
      assertEquals(await refusal(() => resolve(null)), [
        401,
        "authorization_required",
      ]);
    });

    await t.step("an expired session is refused", async () => {
      const expired = await token({}, Math.floor(Date.now() / 1000) - 60);
      assertEquals(await refusal(() => resolve(expired)), [
        401,
        "authorization_rejected",
      ]);
    });

    await t.step("a token another key signed is refused", async () => {
      const other = await project();
      const forged = await other.token({});
      assertEquals(await refusal(() => resolve(forged)), [
        401,
        "authorization_rejected",
      ]);
    });

    await t.step("a token whose claims were changed is refused", async () => {
      const [head, , signature] = (await token({})).split(".");
      const claims = btoa(JSON.stringify({
        role: "authenticated",
        aud: "authenticated",
        sub: "someone-else",
        exp: Math.floor(Date.now() / 1000) + 3600,
      })).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
      assertEquals(
        await refusal(() => resolve(`${head}.${claims}.${signature}`)),
        [401, "authorization_rejected"],
      );
    });

    await t.step(
      "a token that is not a member's session is refused",
      async () => {
        const service = await token({ role: "service_role" });
        assertEquals(await refusal(() => resolve(service)), [
          401,
          "authorization_rejected",
        ]);
        assertEquals(await refusal(() => resolve("not-a-token")), [
          401,
          "authorization_rejected",
        ]);
      },
    );

    await t.step(
      "keys that cannot be fetched refuse as unavailable",
      async () => {
        const down = () => Promise.reject(new TypeError("network"));
        assertEquals(
          await refusal(async () =>
            resolveCallerBySignature(callWith(await token({})), down)
          ),
          [503, "auth_service_unavailable"],
        );
      },
    );
  } finally {
    Deno.env.delete("SUPABASE_URL");
    Deno.env.delete("SUPABASE_ANON_KEY");
  }
});
