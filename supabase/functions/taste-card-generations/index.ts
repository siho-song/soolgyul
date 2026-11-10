import {
  answerBeforeWork,
  jsonResponse,
  readJsonBody,
} from "../_shared/http.ts";
import { errorResponse } from "../_shared/errors.ts";
import { resolveCaller } from "../_shared/auth.ts";
import {
  createTasteCardResult,
  type TasteCardAuthContext,
  type TasteCardOrchestratorDependencies,
} from "../_shared/taste_card/service/orchestrator.ts";
import { tasteCardDependenciesFromEnv } from "../_shared/taste_card/service/dependencies.ts";
import { parseCreateTasteCardResultRequest } from "../_shared/taste_card/service/serialization.ts";

export async function handleTasteCardGenerationRequest(
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
    const result = await createTasteCardResult(
      resolved,
      parseCreateTasteCardResultRequest(body),
      auth,
    );
    return jsonResponse(request, 200, result);
  } catch (error) {
    return errorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleTasteCardGenerationRequest(request));
}
