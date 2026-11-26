// Which catalog drink a photo of one bottle shows, decided from the app's
// candidates by the model. A drink is answered only when someone is sure of
// it: the model, the catalog's own photo, or the app's label match that the
// model did not contradict.
import { SoolgyulHttpError } from "../http.ts";
import type { LabelCandidateRepository } from "./candidates.ts";
import {
  type JudgeUsage,
  type LabelJudge,
  LabelJudgeUnavailable,
} from "./judge.ts";

/** The most candidates one photo is judged against. */
export const LABEL_PICK_MAX_CANDIDATES = 10;

export type LabelPickRequest = {
  /** The bottle cut out of the photo, a base64 JPEG. */
  photo: string;
  /** The app's candidates, likeliest first. */
  candidateIds: readonly string[];
  /** Whether the app's own label match is sure of the first candidate. */
  appSure: boolean;
};

/** How the answer came about, for the function's log; never sent to the app. */
export type LabelPickTrace = {
  candidates: number;
  app_sure: boolean;
  /** The drink the model picked, sure or not. */
  picked: string | null;
  model_sure: boolean;
  /** What the catalog photo said of an unsure pick; absent when it was not asked. */
  catalog_photo_same?: boolean;
  input_tokens: number;
  output_tokens: number;
};

export type LabelPickResult = {
  /** The drink to show as found; `null` when no one is sure of any. */
  drink_id: string | null;
  trace: LabelPickTrace;
};

export async function pickDrinkOfLabel(
  repository: LabelCandidateRepository,
  judge: LabelJudge,
  request: LabelPickRequest,
): Promise<LabelPickResult> {
  const candidates = await repository.loadCandidates(request.candidateIds);
  const trace: LabelPickTrace = {
    candidates: candidates.length,
    // The app is sure of its first candidate, which must still be published.
    app_sure: request.appSure &&
      candidates[0]?.id === request.candidateIds[0],
    picked: null,
    model_sure: false,
    input_tokens: 0,
    output_tokens: 0,
  };
  if (candidates.length === 0) return { drink_id: null, trace };
  const spend = (usage: JudgeUsage) => {
    trace.input_tokens += usage.input_tokens;
    trace.output_tokens += usage.output_tokens;
  };

  let pick;
  try {
    pick = await judge.pickCandidate(request.photo, candidates);
  } catch (error) {
    if (error instanceof LabelJudgeUnavailable) {
      throw new SoolgyulHttpError(503, "label_pick_unavailable");
    }
    throw error;
  }
  spend(pick.usage);
  const picked = pick.pick === 0 ? null : candidates[pick.pick - 1];
  trace.picked = picked?.id ?? null;
  trace.model_sure = pick.sure;

  if (pick.sure) return { drink_id: picked?.id ?? null, trace };
  if (trace.app_sure) return { drink_id: candidates[0].id, trace };
  if (picked === null || picked.photo_url === null) {
    return { drink_id: null, trace };
  }
  try {
    const match = await judge.matchCatalogPhoto(
      request.photo,
      picked,
      picked.photo_url,
    );
    spend(match.usage);
    trace.catalog_photo_same = match.same;
  } catch (error) {
    // The pick stays a guess, and a guess is not shown.
    if (!(error instanceof LabelJudgeUnavailable)) throw error;
  }
  return {
    drink_id: trace.catalog_photo_same === true ? picked.id : null,
    trace,
  };
}
