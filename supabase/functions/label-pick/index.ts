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
  type LabelCandidateRepository,
  SupabaseLabelCandidateRepository,
} from "../_shared/label_pick/candidates.ts";
import {
  AnthropicLabelJudge,
  type LabelJudge,
} from "../_shared/label_pick/judge.ts";
import {
  LABEL_PICK_MAX_CANDIDATES,
  type LabelPickRequest,
  pickDrinkOfLabel,
} from "../_shared/label_pick/service.ts";

/** A bottle cut out at 640 px is 30–90 kB; base64 adds a third. */
const MAX_PHOTO_BASE64_LENGTH = 280 * 1024;
const MAX_BODY_BYTES = 300 * 1024;
/** `/9j/` is how the base64 of every JPEG begins. */
const BASE64_JPEG = /^\/9j\/[A-Za-z0-9+/]+={0,2}$/;

function labelPickRequestFrom(body: unknown): LabelPickRequest {
  const fields = body && typeof body === "object"
    ? body as Record<string, unknown>
    : {};
  const { photo, candidate_ids: ids, app_sure: appSure } = fields;
  if (
    typeof photo !== "string" || photo.length > MAX_PHOTO_BASE64_LENGTH ||
    !BASE64_JPEG.test(photo)
  ) {
    throw new SoolgyulHttpError(400, "photo_invalid");
  }
  if (
    !Array.isArray(ids) || ids.length === 0 ||
    ids.length > LABEL_PICK_MAX_CANDIDATES ||
    !ids.every((id) => typeof id === "string" && UUID_PATTERN.test(id)) ||
    new Set(ids).size !== ids.length
  ) {
    throw new SoolgyulHttpError(400, "candidate_ids_invalid");
  }
  return { photo, candidateIds: ids as string[], appSure: appSure === true };
}

function repositoryFromEnv(): LabelCandidateRepository {
  const { url, key } = serviceRoleEnv();
  return new SupabaseLabelCandidateRepository(url, key);
}

function judgeFromEnv(): LabelJudge {
  const key = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
  if (!key) throw new SoolgyulHttpError(503, "service_configuration_missing");
  return new AnthropicLabelJudge(key);
}

/**
 * Tells a signed-in member which of the app's candidates the bottle in their
 * photo is. The photo is passed to the model and kept nowhere.
 */
export async function handleLabelPickRequest(
  request: Request,
  repository?: LabelCandidateRepository,
  judge?: LabelJudge,
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
    const pickRequest = labelPickRequestFrom(
      await readJsonBody(request, MAX_BODY_BYTES),
    );
    const started = Date.now();
    const { drink_id, trace } = await pickDrinkOfLabel(
      repository ?? repositoryFromEnv(),
      judge ?? judgeFromEnv(),
      pickRequest,
    );
    console.log(JSON.stringify({
      event: "label_pick",
      shown: drink_id,
      ms: Date.now() - started,
      ...trace,
    }));
    return jsonResponse(request, 200, { drink_id });
  } catch (error) {
    return errorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleLabelPickRequest(request));
}
