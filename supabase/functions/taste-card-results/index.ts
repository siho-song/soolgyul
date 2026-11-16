import {
  answerBeforeWork,
  jsonResponse,
  readJsonBody,
  SoolgyulHttpError,
} from "../_shared/http.ts";
import { errorResponse } from "../_shared/errors.ts";
import { UUID_PATTERN } from "../_shared/contract.ts";
import { resolveCaller, type TasteCardAuthContext } from "../_shared/auth.ts";
import {
  deleteOwnedTasteCardRecord,
  getOwnedTasteCardAnswers,
  getOwnedTasteCardResult,
  reviseOwnedTasteCard,
  type TasteCardOrchestratorDependencies,
} from "../_shared/taste_card/service/orchestrator.ts";
import { parseReviseTasteCardRequest } from "../_shared/taste_card/service/serialization.ts";
import { tasteCardDependenciesFromEnv } from "../_shared/taste_card/service/dependencies.ts";

export async function handleTasteCardResultRequest(
  request: Request,
  dependencies?: TasteCardOrchestratorDependencies,
  resolveAuth: (request: Request) => Promise<TasteCardAuthContext | null> =
    resolveCaller,
): Promise<Response> {
  const early = answerBeforeWork(request, ["GET", "PATCH", "DELETE"]);
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
    // GET reads one saved card, or with part=answers what its record was
    // answered with; PATCH writes the card again from the answers the
    // member corrected; DELETE removes the record behind it.
    const part = new URL(request.url).searchParams.get("part");
    if (part !== null && (part !== "answers" || request.method !== "GET")) {
      throw new SoolgyulHttpError(400, "part_invalid");
    }
    const body = request.method === "DELETE"
      ? await deleteOwnedTasteCardRecord(resolved, resultId, auth)
      : request.method === "PATCH"
      ? await reviseOwnedTasteCard(
        resolved,
        resultId,
        parseReviseTasteCardRequest(await readJsonBody(request)),
        auth,
      )
      : part === "answers"
      ? await getOwnedTasteCardAnswers(resolved, resultId, auth)
      : await getOwnedTasteCardResult(resolved, resultId, auth);
    return jsonResponse(request, 200, body);
  } catch (error) {
    return errorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleTasteCardResultRequest(request));
}
