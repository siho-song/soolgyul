import {
  completeProfile,
  type EdgeAuthContext,
  profileRepositoryFromRequest,
  resolveProfileAuth,
  SoolgyulHttpError,
  tasteCardCorsHeaders,
  tasteCardErrorResponse,
  tasteCardJsonBody,
  tasteCardJsonResponse,
} from "../_shared/soolgyul_edge.ts";
import { parseCompleteProfileRequest } from "../_shared/soolgyul_contract.ts";
import type { ProfileRepository } from "../_shared/profile/repository.ts";

export async function handleCompleteProfileRequest(
  request: Request,
  repository?: Pick<ProfileRepository, "getStatus" | "upsertProfile">,
  resolveAuth: (request: Request) => Promise<EdgeAuthContext | null> =
    resolveProfileAuth,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: tasteCardCorsHeaders(request),
    });
  }
  if (request.method !== "GET" && request.method !== "POST") {
    return tasteCardJsonResponse(request, 405, {
      error_code: "method_not_allowed",
    });
  }
  try {
    const auth = await resolveAuth(request);
    if (auth === null) {
      throw new SoolgyulHttpError(401, "authorization_required");
    }
    const activeRepository = repository ??
      profileRepositoryFromRequest(request);
    if (request.method === "GET") {
      return tasteCardJsonResponse(
        request,
        200,
        await activeRepository.getStatus(),
      );
    }
    const body = await tasteCardJsonBody(request);
    const status = await completeProfile(
      activeRepository,
      auth,
      parseCompleteProfileRequest(body),
    );
    return tasteCardJsonResponse(request, 200, status);
  } catch (error) {
    return tasteCardErrorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleCompleteProfileRequest(request));
}
