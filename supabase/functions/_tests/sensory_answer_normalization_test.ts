import { normalizeSensoryAnswers } from "../_shared/taste_card/record/answer_normalization.ts";
import {
  sensoryOptionsV1,
  type SensoryOptionV1,
} from "../_shared/taste_card/record/questionnaire.ts";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}

const options = new Map(
  sensoryOptionsV1().map((option) => [option.option_key, option]),
);
function row(key: string): SensoryOptionV1 {
  const option = options.get(key);
  assert(option, `unknown test option: ${key}`);
  return option;
}

Deno.test("answer normalization: notice, reaction and multiple reasons stay attached to their subject", () => {
  const rows = [
    "notice:aroma:cherry",
    "reaction:aroma:cherry:liked",
    "target:aroma:cherry:liked",
    "reason:aroma:cherry:liked:pronounced",
    "reason:aroma:cherry:liked:harmony",
    "notice:aroma:oak",
    "reaction:aroma:oak:disliked",
  ].map(row);
  const original = JSON.stringify(rows);
  const result = normalizeSensoryAnswers(rows, {});
  assert(result.answers.length === 2);
  const cherry = result.answers.find((answer) =>
    answer.key === "aroma.cherry"
  )!;
  assert(cherry.phase === "mid" && cherry.reaction === "positive");
  assert(cherry.reasons.join() === "distinctIntensityAccepted,harmonious");
  assert(
    cherry.observations.map((item) => item.meaning).join() ===
      "harmonious,noticed,pronouncedIntensity",
  );
  assert(cherry.answerRefs.includes("target:aroma:cherry:liked"));
  assert(cherry.reasonRefs.length === 2);
  assert(
    result.answers.find((answer) => answer.key === "aroma.oak")!.reasons
      .length === 0,
  );
  assert(
    JSON.stringify(normalizeSensoryAnswers([...rows].reverse(), {})) ===
      JSON.stringify(result),
  );
  assert(JSON.stringify(rows) === original, "input mutated");
});

Deno.test("answer normalization: phase and opposite finish responses are never collapsed", () => {
  const mid = row("reaction:taste:acidity:liked");
  const later = structuredClone(mid);
  later.phase = "finish";
  later.option_key = "later-acidity";
  const result = normalizeSensoryAnswers([
    mid,
    later,
    row("finish:aromaEcho"),
    row("finish:offFlavor"),
    row("finish:heavy"),
  ], {});
  const acidity = result.answers.filter((answer) =>
    answer.key === "taste.acidity"
  );
  assert(
    acidity.length === 2 &&
      new Set(acidity.map((answer) => answer.phase)).size === 2,
  );
  const echo = result.answers.find((answer) =>
    answer.key === "finish.aroma_echo"
  )!;
  const off = result.answers.find((answer) =>
    answer.key === "finish.off_flavor"
  )!;
  assert(echo.reaction === "positive" && off.reaction === "burden");
  assert(echo.observations[0].meaning === "lingeringAroma");
  assert(off.observations[0].meaning === "lingeringOffFlavor");
  assert(
    result.answers.find((answer) => answer.key === "finish.weight")!
      .reaction === "burden",
  );
});

Deno.test("answer normalization: missing, unknown, 적당했어요 and revisit remain distinct", () => {
  const result = normalizeSensoryAnswers([
    row("aroma:unsure"),
    row("reaction:taste:sweetness:fine"),
    row("revisit:unsure"),
  ], {});
  assert(result.answers.length === 1);
  assert(result.answers[0].reaction === "neutral");
  assert(result.sectionStates.aroma.state === "unknown");
  assert(result.sectionStates.taste.state === "answered");
  assert(result.sectionStates.mouthfeel.state === "unanswered");
  assert(result.sectionStates.finish.state === "unanswered");
  assert(result.revisit.intent === "unknown");
  assert(result.revisit.answerRefs[0] === "revisit:unsure");
  assert(normalizeSensoryAnswers([], {}).revisit.intent === null);
});

Deno.test("answer normalization: wanting more is not a measured low intensity; unknown reason is not unknown sensation", () => {
  const result = normalizeSensoryAnswers(
    [
      "notice:aroma:cherry",
      "reaction:aroma:cherry:disliked",
      "reason:aroma:cherry:disliked:too_weak",
      "reaction:taste:sweetness:liked",
      "reason:taste:sweetness:liked:unspecified",
    ].map(row),
    {},
  );
  const cherry = result.answers.find((answer) =>
    answer.key === "aroma.cherry"
  )!;
  assert(
    cherry.observations.some((item) => item.meaning === "wantsMoreIntensity"),
  );
  const sweet = result.answers.find((answer) =>
    answer.key === "taste.sweetness"
  )!;
  assert(sweet.reaction === "positive" && sweet.reasons[0] === "reasonUnknown");
  assert(result.sectionStates.taste.state === "answered");
});
