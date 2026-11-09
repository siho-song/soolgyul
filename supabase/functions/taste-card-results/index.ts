import {
  answerBeforeWork,
  jsonResponse,
  SoolgyulHttpError,
} from "../_shared/http.ts";
import { errorResponse } from "../_shared/errors.ts";
import { resolveCaller } from "../_shared/auth.ts";
import {
  deleteOwnedTasteCardRecordV1,
  getOwnedTasteCardResultV1,
  type TasteCardAuthContext,
  type TasteCardOrchestratorDependencies,
} from "../_shared/taste_card/orchestrator.ts";
import { tasteCardDependenciesFromEnv } from "../_shared/taste_card/dependencies.ts";

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
    if (
      resultId === null ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(resultId)
    ) {
      throw new SoolgyulHttpError(400, "result_id_invalid");
    }
    // GET reads one saved card; DELETE removes the record behind it.
    const body = request.method === "DELETE"
      ? await deleteOwnedTasteCardRecordV1(resolved, resultId, auth)
      : await getOwnedTasteCardResultV1(resolved, resultId, auth);
    return jsonResponse(request, 200, body);
  } catch (error) {
    return errorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleTasteCardResultRequest(request));
}
