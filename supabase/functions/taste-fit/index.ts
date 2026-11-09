import {
  resolveTasteCardAuth,
  SoolgyulHttpError,
  tasteCardCorsHeaders,
  tasteCardErrorResponse,
  tasteCardJsonBody,
  tasteCardJsonResponse,
} from "../_shared/soolgyul_edge.ts";
import type { TasteCardAuthContext } from "../_shared/taste_card/orchestrator.ts";
import {
  SupabaseTasteFitRepository,
  type TasteFitRepository,
} from "../_shared/taste_fit/repository.ts";
import {
  judgeProductsForUser,
  TASTE_FIT_MAX_PRODUCTS,
} from "../_shared/taste_fit/service.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function productIdsFrom(body: unknown): string[] {
  const ids = body && typeof body === "object"
    ? (body as Record<string, unknown>).product_ids
    : undefined;
  if (
    !Array.isArray(ids) || ids.length === 0 ||
    ids.length > TASTE_FIT_MAX_PRODUCTS ||
    !ids.every((id) => typeof id === "string" && UUID.test(id))
  ) {
    throw new SoolgyulHttpError(400, "product_ids_invalid");
  }
  return [...new Set(ids as string[])];
}

function repositoryFromEnv(): TasteFitRepository {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceRoleKey) {
    throw new SoolgyulHttpError(503, "service_configuration_missing");
  }
  return new SupabaseTasteFitRepository(supabaseUrl, serviceRoleKey);
}

export async function handleTasteFitRequest(
  request: Request,
  repository?: TasteFitRepository,
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
    const auth = await resolveAuth(request);
    if (auth === null) {
      throw new SoolgyulHttpError(401, "authorization_required");
    }
    const productIds = productIdsFrom(await tasteCardJsonBody(request));
    const result = await judgeProductsForUser(
      repository ?? repositoryFromEnv(),
      auth.user_id,
      productIds,
    );
    return tasteCardJsonResponse(request, 200, result);
  } catch (error) {
    return tasteCardErrorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleTasteFitRequest(request));
}
