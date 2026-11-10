import {
  answerBeforeWork,
  jsonResponse,
  readJsonBody,
  SoolgyulHttpError,
} from "../_shared/http.ts";
import { errorResponse } from "../_shared/errors.ts";
import { type EdgeAuthContext, resolveProfileCaller } from "../_shared/auth.ts";
import {
  completeProfile,
  profileRepositoryFromRequest,
} from "../_shared/profile/complete_profile.ts";
import { parseCompleteProfileRequest } from "../_shared/contract.ts";
import type { ProfileRepository } from "../_shared/profile/repository.ts";

export async function handleCompleteProfileRequest(
  request: Request,
  repository?: Pick<ProfileRepository, "getStatus" | "upsertProfile">,
  resolveAuth: (request: Request) => Promise<EdgeAuthContext | null> =
    resolveProfileCaller,
): Promise<Response> {
  const early = answerBeforeWork(request, ["GET", "POST"]);
  if (early !== null) return early;
  try {
    const auth = await resolveAuth(request);
    if (auth === null) {
      throw new SoolgyulHttpError(401, "authorization_required");
    }
    const activeRepository = repository ??
      profileRepositoryFromRequest(request);
    if (request.method === "GET") {
      return jsonResponse(
        request,
        200,
        await activeRepository.getStatus(),
      );
    }
    const body = await readJsonBody(request);
    const status = await completeProfile(
      activeRepository,
      auth,
      parseCompleteProfileRequest(body),
    );
    return jsonResponse(request, 200, status);
  } catch (error) {
    return errorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleCompleteProfileRequest(request));
}
