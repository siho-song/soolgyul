import {
  answerBeforeWork,
  jsonResponse,
  readJsonBody,
} from "../_shared/http.ts";
import { errorResponse } from "../_shared/errors.ts";
import {
  requireSignedIn,
  resolveCaller,
  type TasteCardAuthContext,
} from "../_shared/auth.ts";
import {
  convertAnonymousTasteCard,
  type TasteCardOrchestratorDependencies,
} from "../_shared/taste_card/service/orchestrator.ts";
import { tasteCardDependenciesFromEnv } from "../_shared/taste_card/service/dependencies.ts";
import { parseAnonymousTasteCardConversionRequest } from "../_shared/taste_card/service/serialization.ts";
import { serveWithKindSpreads } from "../_shared/record_reading/facts/kind_spreads_live.ts";

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
    const [body, caller] = await Promise.all([
      readJsonBody(request),
      resolveAuth(request),
    ]);
    const auth = requireSignedIn(caller);
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
  serveWithKindSpreads((request) => handleTasteCardConversionRequest(request));
}
