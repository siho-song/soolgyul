// 나의 용어 사전. GET answers the signed-in reader's saved terms; POST saves
// one or takes one out ({ key, saved }) and answers the list as it then is.
import {
  answerBeforeWork,
  jsonResponse,
  readJsonBody,
  SoolgyulHttpError,
} from "../_shared/http.ts";
import { errorResponse } from "../_shared/errors.ts";
import { resolveCaller, type TasteCardAuthContext } from "../_shared/auth.ts";
import { serviceRoleEnv } from "../_shared/supabase.ts";
import {
  type SavedTermsRepository,
  SupabaseSavedTermsRepository,
} from "../_shared/glossary/repository.ts";
import {
  type SavedTermChange,
  savedTermsForUser,
} from "../_shared/glossary/service.ts";

function changeFrom(body: unknown): SavedTermChange {
  const { key, saved } = body && typeof body === "object"
    ? body as Record<string, unknown>
    : {};
  if (
    typeof key !== "string" || key.length === 0 || key.length > 120 ||
    typeof saved !== "boolean"
  ) {
    throw new SoolgyulHttpError(400, "term_change_invalid");
  }
  return { key, saved };
}

function repositoryFromEnv(): SavedTermsRepository {
  const { url, key } = serviceRoleEnv();
  return new SupabaseSavedTermsRepository(url, key);
}

export async function handleSavedTermsRequest(
  request: Request,
  repository?: SavedTermsRepository,
  resolveAuth: (request: Request) => Promise<TasteCardAuthContext | null> =
    resolveCaller,
): Promise<Response> {
  const early = answerBeforeWork(request, ["GET", "POST"]);
  if (early !== null) return early;
  try {
    const auth = await resolveAuth(request);
    if (auth === null) {
      throw new SoolgyulHttpError(401, "authorization_required");
    }
    const change = request.method === "POST"
      ? changeFrom(await readJsonBody(request))
      : undefined;
    const result = await savedTermsForUser(
      repository ?? repositoryFromEnv(),
      auth.user_id,
      change,
    );
    return jsonResponse(request, 200, result);
  } catch (error) {
    return errorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleSavedTermsRequest(request));
}
