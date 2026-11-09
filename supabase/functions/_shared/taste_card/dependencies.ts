import { SoolgyulHttpError } from "../http.ts";
import { serviceRoleEnv } from "../supabase.ts";
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
    // sign-in, days later; the retention window caps it.
    token_signer: new HmacConversionTokenSigner(
      conversionSecret,
      conversionKeyVersion,
      30 * 24 * 60 * 60,
    ),
  };
}
