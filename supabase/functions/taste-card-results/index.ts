import {
  deleteOwnedTasteCardRecordV1,
  getOwnedTasteCardResultV1,
  resolveTasteCardAuth,
  SoolgyulHttpError,
  tasteCardCorsHeaders,
  tasteCardDependenciesFromEnv,
  tasteCardErrorResponse,
  tasteCardJsonResponse,
} from "../_shared/soolgyul_edge.ts";
import type {
  TasteCardAuthContext,
  TasteCardOrchestratorDependencies,
} from "../_shared/taste_card/orchestrator.ts";

export async function handleTasteCardResultRequest(
  request: Request,
  dependencies?: TasteCardOrchestratorDependencies,
  resolveAuth: (request: Request) => Promise<TasteCardAuthContext | null> =
    resolveTasteCardAuth,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: tasteCardCorsHeaders(request),
    });
  }
  if (request.method !== "GET" && request.method !== "DELETE") {
    return tasteCardJsonResponse(request, 405, {
      error_code: "method_not_allowed",
    });
  }
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
    return tasteCardJsonResponse(request, 200, body);
  } catch (error) {
    return tasteCardErrorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleTasteCardResultRequest(request));
}
