import { SoolgyulHttpError } from "../../http.ts";
import { serviceRoleEnv } from "../../supabase.ts";
import { HmacConversionTokenSigner } from "./conversion_token.ts";
import type { TasteCardOrchestratorDependencies } from "./orchestrator.ts";
import { SupabaseTasteCardRepository } from "./repository.ts";

/** The card engine's store and ticket signer, from the function's secrets. */
export function tasteCardDependenciesFromEnv(): TasteCardOrchestratorDependencies {
  const { url, key } = serviceRoleEnv();
  const conversionSecret = Deno.env.get("TASTE_CARD_CONVERSION_SECRET") ?? "";
  const conversionKeyVersion = Deno.env.get(
    "TASTE_CARD_CONVERSION_KEY_VERSION",
  ) ?? "";
  if (conversionSecret.length < 32 || !conversionKeyVersion.trim()) {
    throw new SoolgyulHttpError(503, "service_configuration_missing");
  }
  return {
    repository: new SupabaseTasteCardRepository(url, key),
    // The ticket travels in the store link and is claimed after the app's
    // sign-in, which may be days later. A week covers an install; the link
    // is the whole credential, so it does not live as long as the card.
    token_signer: new HmacConversionTokenSigner(
      conversionSecret,
      conversionKeyVersion,
      7 * 24 * 60 * 60,
    ),
  };
}

/**
 * A keyed digest of the address a request came from, to count how many cards
 * one address makes. The header is set by the platform's edge and cannot be
 * sent by the caller; the address itself is never stored.
 */
export async function clientAddressDigest(
  request: Request,
): Promise<string | null> {
  const address = request.headers.get("cf-connecting-ip")?.trim() ?? "";
  const secret = Deno.env.get("TASTE_CARD_CONVERSION_SECRET") ?? "";
  if (address === "" || secret.length < 32) return null;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`taste-card-client-address-v1:${address}`),
  );
  return Array.from(new Uint8Array(signature), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}
