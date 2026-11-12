import {
  answerBeforeWork,
  jsonResponse,
  readJsonBody,
  SoolgyulHttpError,
} from "../_shared/http.ts";
import { errorResponse } from "../_shared/errors.ts";
import { UUID_PATTERN } from "../_shared/contract.ts";
import { resolveCaller, type TasteCardAuthContext } from "../_shared/auth.ts";
import { serviceRoleEnv } from "../_shared/supabase.ts";
import {
  SupabaseTasteFitRepository,
  type TasteFitRepository,
} from "../_shared/taste_fit/repository.ts";
import {
  judgeProductsForUser,
  TASTE_FIT_MAX_PRODUCTS,
} from "../_shared/taste_fit/service.ts";

function productIdsFrom(body: unknown): string[] {
  const ids = body && typeof body === "object"
    ? (body as Record<string, unknown>).product_ids
    : undefined;
  if (
    !Array.isArray(ids) || ids.length === 0 ||
    ids.length > TASTE_FIT_MAX_PRODUCTS ||
    !ids.every((id) => typeof id === "string" && UUID_PATTERN.test(id))
  ) {
    throw new SoolgyulHttpError(400, "product_ids_invalid");
  }
  return [...new Set(ids as string[])];
}

function repositoryFromEnv(): TasteFitRepository {
  const { url, key } = serviceRoleEnv();
  return new SupabaseTasteFitRepository(url, key);
}

export async function handleTasteFitRequest(
  request: Request,
  repository?: TasteFitRepository,
  resolveAuth: (request: Request) => Promise<TasteCardAuthContext | null> =
    resolveCaller,
): Promise<Response> {
  const early = answerBeforeWork(request, ["POST"]);
  if (early !== null) return early;
  try {
    const auth = await resolveAuth(request);
    if (auth === null) {
      throw new SoolgyulHttpError(401, "authorization_required");
    }
    const productIds = productIdsFrom(await readJsonBody(request));
    const result = await judgeProductsForUser(
      repository ?? repositoryFromEnv(),
      auth.user_id,
      productIds,
    );
    return jsonResponse(request, 200, result);
  } catch (error) {
    return errorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleTasteFitRequest(request));
}
