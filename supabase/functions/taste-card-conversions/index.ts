import {
  answerBeforeWork,
  jsonResponse,
  readJsonBody,
  SoolgyulHttpError,
} from "../_shared/http.ts";
import { errorResponse } from "../_shared/errors.ts";
import { resolveCaller } from "../_shared/auth.ts";
import {
  convertAnonymousTasteCard,
  type TasteCardAuthContext,
  type TasteCardOrchestratorDependencies,
} from "../_shared/taste_card/orchestrator.ts";
import { tasteCardDependenciesFromEnv } from "../_shared/taste_card/dependencies.ts";
import { parseAnonymousTasteCardConversionRequest } from "../_shared/taste_card/serialization.ts";

export async function handleTasteCardConversionRequest(
  request: Request,
  dependencies?: TasteCardOrchestratorDependencies,
  resolveAuth: (request: Request) => Promise<TasteCardAuthContext | null> =
    resolveCaller,
): Promise<Response> {
  const early = answerBeforeWork(request, ["POST"]);
  if (early !== null) return early;
  try {
    const resolved = dependencies ?? tasteCardDependenciesFromEnv();
    const [body, auth] = await Promise.all([
      readJsonBody(request),
      resolveAuth(request),
    ]);
    if (auth === null) {
      throw new SoolgyulHttpError(401, "authorization_required");
    }
    const result = await convertAnonymousTasteCard(
      resolved,
      parseAnonymousTasteCardConversionRequest(body),
      auth,
    );
    return jsonResponse(request, 200, result);
  } catch (error) {
    return errorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleTasteCardConversionRequest(request));
}
