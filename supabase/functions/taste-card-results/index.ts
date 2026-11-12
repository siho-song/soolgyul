import {
  answerBeforeWork,
  jsonResponse,
  SoolgyulHttpError,
} from "../_shared/http.ts";
import { errorResponse } from "../_shared/errors.ts";
import { UUID_PATTERN } from "../_shared/contract.ts";
import { resolveCaller, type TasteCardAuthContext } from "../_shared/auth.ts";
import {
  deleteOwnedTasteCardRecord,
  getOwnedTasteCardResult,
  type TasteCardOrchestratorDependencies,
} from "../_shared/taste_card/service/orchestrator.ts";
import { tasteCardDependenciesFromEnv } from "../_shared/taste_card/service/dependencies.ts";

export async function handleTasteCardResultRequest(
  request: Request,
  dependencies?: TasteCardOrchestratorDependencies,
  resolveAuth: (request: Request) => Promise<TasteCardAuthContext | null> =
    resolveCaller,
): Promise<Response> {
  const early = answerBeforeWork(request, ["GET", "DELETE"]);
  if (early !== null) return early;
  try {
    const resolved = dependencies ?? tasteCardDependenciesFromEnv();
    const auth = await resolveAuth(request);
    if (auth === null) {
      throw new SoolgyulHttpError(401, "authorization_required");
    }
    const resultId = new URL(request.url).searchParams.get("result_id");
    if (resultId === null || !UUID_PATTERN.test(resultId)) {
      throw new SoolgyulHttpError(400, "result_id_invalid");
    }
    // GET reads one saved card; DELETE removes the record behind it.
    const body = request.method === "DELETE"
      ? await deleteOwnedTasteCardRecord(resolved, resultId, auth)
      : await getOwnedTasteCardResult(resolved, resultId, auth);
    return jsonResponse(request, 200, body);
  } catch (error) {
    return errorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleTasteCardResultRequest(request));
}
