import { parseCreateTasteCardResultRequest } from "../../_shared/taste_card/service/serialization.ts";
import {
  SENSORY_MEANING_VERSION,
  SENSORY_QUESTIONNAIRE_VERSION,
  SENSORY_QUESTIONS,
  sensoryDefinition,
  sensoryOptions,
  validateSensoryAnswers,
  verifySensoryRegistry,
} from "../../_shared/taste_card/record/questionnaire.ts";
import type {
  CreateTasteCardResultRequest,
  QuestionnaireAnswerInput,
} from "../../_shared/taste_card/service/types.ts";

function check(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}
function equal(actual: unknown, expected: unknown) {
  check(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${JSON.stringify(actual)} != ${JSON.stringify(expected)}`,
  );
}
function answer(
  section: keyof typeof SENSORY_QUESTIONS,
  ids: string[],
): QuestionnaireAnswerInput {
  return {
    question_key: section,
    selected_option_keys: ids,
    free_text: null,
  };
}
function request(
  overrides: Partial<Record<keyof typeof SENSORY_QUESTIONS, string[]>> = {},
): CreateTasteCardResultRequest {
  return {
    idempotency_key: "10000000-0000-4000-8000-000000000001",
    anonymous_session_id: "sensory-test",
    questionnaire_version: SENSORY_QUESTIONNAIRE_VERSION,
    alcohol_identification: {
      mode: "catalog_match",
      alcohol_item_id: "30000000-0000-4000-8000-000000000001",
      alcohol_name_snapshot: "테스트 술",
      category: "wine",
    },
    answers: Object.keys(SENSORY_QUESTIONS).map((key) =>
      answer(
        key as keyof typeof SENSORY_QUESTIONS,
        overrides[key as keyof typeof SENSORY_QUESTIONS] ??
          (key === "sensory_revisit"
            ? ["revisit:wantAgain"]
            : key === "sensory_taste"
            ? ["reaction:taste:sweetness:fine"]
            : []),
      )
    ),
    q7_free_text: null,
    photo_asset_id: null,
  };
}
function rejects(answers: QuestionnaireAnswerInput[], code?: string) {
  let error: unknown;
  try {
    validateSensoryAnswers(answers);
  } catch (caught) {
    error = caught;
  }
  check(error instanceof Error, "invalid answer accepted");
  if (code) check(error.message.includes(code), error.message);
}

Deno.test("sensory registry is immutable and meanings carry the same version", async () => {
  await verifySensoryRegistry();
  const options = sensoryOptions();
  equal(new Set(options.map((item) => item.option_key)).size, options.length);
  check(
    options.length > 1000,
    "exercise the PostgREST nested-row-limit boundary",
  );
  check(!options.some((item) => item.option_key.endsWith(":option_gap")));
  const meanings = await Deno.readTextFile(
    new URL(
      "../../../../lib/src/core/sensory/sensory_meanings.dart",
      import.meta.url,
    ),
  );
  check(meanings.includes(SENSORY_MEANING_VERSION));
});

Deno.test("sensory tastes are always answered; the other sections may stay unknown", () => {
  validateSensoryAnswers(request().answers);
  validateSensoryAnswers(
    request({
      sensory_aroma: ["aroma:unsure"],
      sensory_taste: [
        "reaction:taste:sweetness:fine",
        "reaction:taste:acidity:fine",
      ],
      sensory_mouthfeel: ["mouthfeel:unsure"],
      sensory_finish: ["finish:unsure"],
    }).answers,
  );
  rejects(request({ sensory_taste: [] }).answers, "taste_required");
  check(!sensoryDefinition("taste:unsure"));
  check(!sensoryDefinition("taste:nothing_stood_out"));
});

Deno.test("every dictionary aroma and every contextual reason has a valid parent path", () => {
  for (const option of sensoryOptions()) {
    if (option.kind !== "reason") continue;
    const section = option.section as "aroma" | "taste";
    const ids = [
      ...(section === "aroma" ? [`notice:aroma:${option.subject}`] : []),
      `reaction:${section}:${option.subject}:${option.side}`,
      option.option_key,
    ];
    validateSensoryAnswers(request({ [`sensory_${section}`]: ids }).answers);
    equal(option.reaction, "none");
    check(option.semantic_key.startsWith("questionnaire.fact."));
  }
  equal(
    sensoryOptions().find((o) =>
      o.option_key === "reason:taste:bitterness:disliked:disharmony"
    )?.meaning,
    "masksOtherSensations",
  );
  equal(
    sensoryDefinition("reason:taste:acidity:disliked:too_weak")?.value,
    "wantsMoreIntensity",
  );
});

Deno.test("sensory wire rejects unknown/duplicate IDs, wrong sections, missing revisit and injected meaning", () => {
  for (
    const ids of [
      ["notice:aroma:not_a_dictionary_key"],
      ["notice:aroma:apple", "notice:aroma:apple"],
      ["reaction:taste:sweetness:liked"],
      ["aroma:option_gap"],
    ]
  ) rejects(request({ sensory_aroma: ids }).answers);
  rejects(request({ sensory_revisit: [] }).answers, "revisit_required");
  rejects(
    request({ sensory_revisit: ["revisit:wantAgain", "revisit:unsure"] })
      .answers,
  );
  const duplicate = request().answers;
  duplicate.push(duplicate[0]);
  rejects(duplicate, "question_unknown_or_duplicate");
  const unknown = request().answers;
  unknown.push({ ...answer("sensory_aroma", []), question_key: "invented" });
  rejects(unknown);
  const injected = request();
  Object.assign(injected.answers[0], {
    semantic_key: "taste.sweetness",
    reaction: "positive",
  });
  let rejected = false;
  try {
    parseCreateTasteCardResultRequest(injected);
  } catch {
    rejected = true;
  }
  check(rejected, "client meaning must not cross the wire boundary");
});

Deno.test("sensory choice limits, exclusivity and reaction parent/conflict checks", () => {
  const six = sensoryOptions().filter((o) =>
    o.section === "aroma" && o.kind === "notice"
  ).slice(0, 6).map((o) => o.option_key);
  validateSensoryAnswers(request({ sensory_aroma: six.slice(0, 5) }).answers);
  rejects(request({ sensory_aroma: six }).answers, "aroma_limit");
  rejects(
    request({ sensory_aroma: ["aroma:unsure", "notice:aroma:apple"] }).answers,
    "exclusive_state",
  );
  rejects(
    request({ sensory_taste: ["taste:nothing_stood_out", "taste:unsure"] })
      .answers,
  );
  rejects(
    request({ sensory_finish: ["finish:unsure", "finish:clean"] }).answers,
  );
  rejects(
    request({
      sensory_aroma: [
        "reaction:aroma:apple:liked",
        "reason:aroma:apple:liked:pronounced",
      ],
    }).answers,
    "reaction_without_notice",
  );
  rejects(
    request({
      sensory_taste: [
        "reaction:taste:acidity:liked",
        "reaction:taste:acidity:disliked",
      ],
    }).answers,
    "reaction_conflict",
  );
});

Deno.test("no section asks a target; reasons sit under the reaction they explain", () => {
  const mixedAroma = [
    "notice:aroma:apple",
    "notice:aroma:pear",
    "reaction:aroma:apple:liked",
    "reaction:aroma:pear:disliked",
  ];
  validateSensoryAnswers(request({ sensory_aroma: mixedAroma }).answers);
  // Stored answers from before the aroma reason page was removed still read.
  validateSensoryAnswers(
    request({
      sensory_aroma: [
        ...mixedAroma,
        "target:aroma:apple:liked",
        "reason:aroma:apple:liked:gentle",
        "reason:aroma:pear:disliked:too_strong",
      ],
    }).answers,
  );
  rejects(
    request({
      sensory_aroma: [...mixedAroma, "reason:aroma:pear:liked:gentle"],
    }).answers,
    "reason_without_parent",
  );
  // Tastes: every liked or burden taste may carry reasons, none must.
  const taste = [
    "reaction:taste:sweetness:liked",
    "reaction:taste:acidity:liked",
    "reaction:taste:bitterness:disliked",
    "reason:taste:sweetness:liked:gentle",
    "reason:taste:acidity:liked:harmony",
    "reason:taste:bitterness:disliked:too_strong",
  ];
  validateSensoryAnswers(request({ sensory_taste: taste }).answers);
  validateSensoryAnswers(
    request({ sensory_taste: ["reaction:taste:acidity:liked"] }).answers,
  );
  // A stored target still reads when it names a reacted taste, one per side.
  validateSensoryAnswers(
    request({ sensory_taste: [...taste, "target:taste:sweetness:liked"] })
      .answers,
  );
  rejects(
    request({
      sensory_taste: [
        ...taste,
        "target:taste:sweetness:liked",
        "target:taste:acidity:liked",
      ],
    }).answers,
    "target_multiple",
  );
  rejects(
    request({ sensory_taste: [...taste, "target:taste:acidity:disliked"] })
      .answers,
    "reason_without_parent",
  );
  rejects(
    request({
      sensory_taste: [...taste, "reason:taste:sweetness:disliked:too_strong"],
    }).answers,
    "reason_without_parent",
  );
  rejects(
    request({
      sensory_taste: [...taste, "reason:taste:sweetness:liked:unspecified"],
    }).answers,
    "reason_exclusive",
  );
  rejects(
    request({ sensory_taste: ["reason:taste:acidity:disliked:too_weak"] })
      .answers,
    "reason_without_parent",
  );
});

Deno.test("every finish carries a side and all six remain selectable", () => {
  const ids = sensoryOptions().filter((o) => o.kind === "finish").map((o) =>
    o.option_key
  );
  equal(ids.length, 6);
  validateSensoryAnswers(request({ sensory_finish: ids }).answers);
  for (const id of ["finish:tooShort", "finish:heavy", "finish:offFlavor"]) {
    equal(sensoryDefinition(id)?.reaction, "burden");
  }
  for (
    const id of ["finish:pleasantLength", "finish:clean", "finish:aromaEcho"]
  ) {
    equal(sensoryDefinition(id)?.reaction, "positive");
  }
  // 적당했어요: tastes and mouthfeel only, an evaluation with no direction.
  const fine = sensoryOptions().filter((o) => o.option_key.endsWith(":fine"));
  equal(fine.length, 9);
  equal(
    fine.every((o) =>
      o.kind === "reaction" && o.reaction === "neutral" && o.side === null
    ),
    true,
  );
  equal(fine.some((o) => o.section === "aroma"), false);
  validateSensoryAnswers(
    request({
      sensory_taste: ["reaction:taste:sweetness:fine"],
      sensory_mouthfeel: [
        "notice:mouthfeel:heavy",
        "reaction:mouthfeel:heavy:fine",
      ],
    }).answers,
  );
  equal(
    sensoryDefinition("finish:pleasantLength")?.value,
    "pleasantPersistence",
  );
});
