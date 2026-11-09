import {
  createTasteCardResultV1,
  resolveTasteCardAuth,
  tasteCardCorsHeaders,
  tasteCardDependenciesFromEnv,
  tasteCardErrorResponse,
  tasteCardJsonBody,
  tasteCardJsonResponse,
} from "../_shared/soolgyul_edge.ts";
import { parseCreateTasteCardResultRequestV1 } from "../_shared/taste_card/serialization.ts";
import type {
  TasteCardAuthContext,
  TasteCardOrchestratorDependencies,
} from "../_shared/taste_card/orchestrator.ts";

export async function handleTasteCardGenerationRequest(
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
  if (request.method !== "POST") {
    return tasteCardJsonResponse(request, 405, {
      error_code: "method_not_allowed",
    });
  }
  try {
    const resolved = dependencies ?? tasteCardDependenciesFromEnv();
    const [body, auth] = await Promise.all([
      tasteCardJsonBody(request),
      resolveAuth(request),
    ]);
    const result = await createTasteCardResultV1(
      resolved,
      parseCreateTasteCardResultRequestV1(body),
      auth,
    );
    return tasteCardJsonResponse(request, 200, result);
  } catch (error) {
    return tasteCardErrorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleTasteCardGenerationRequest(request));
}
