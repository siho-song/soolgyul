import { parseCreateTasteCardResultRequest } from "../_shared/taste_card/serialization.ts";
import {
  SENSORY_MEANING_VERSION,
  SENSORY_QUESTIONNAIRE_VERSION,
  SENSORY_QUESTIONS,
  sensoryDefinitionV1,
  sensoryOptionsV1,
  validateSensoryAnswersV1,
  verifySensoryRegistryV1,
} from "../_shared/taste_card/sensory_questionnaire_v1.ts";
import type {
  CreateTasteCardResultRequest,
  QuestionnaireAnswerInput,
} from "../_shared/taste_card/types.ts";

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
    validateSensoryAnswersV1(answers);
  } catch (caught) {
    error = caught;
  }
  check(error instanceof Error, "invalid answer accepted");
  if (code) check(error.message.includes(code), error.message);
}

Deno.test("sensory registry is immutable and meanings carry the same version", async () => {
  await verifySensoryRegistryV1();
  const options = sensoryOptionsV1();
  equal(new Set(options.map((item) => item.option_key)).size, options.length);
  check(
    options.length > 1000,
    "exercise the PostgREST nested-row-limit boundary",
  );
  check(!options.some((item) => item.option_key.endsWith(":option_gap")));
  const meanings = await Deno.readTextFile(
    new URL(
      "../../../lib/src/core/sensory/sensory_meanings.dart",
      import.meta.url,
    ),
  );
  check(meanings.includes(SENSORY_MEANING_VERSION));
});

Deno.test("sensory tastes are always answered; the other sections may stay unknown", () => {
  validateSensoryAnswersV1(request().answers);
  validateSensoryAnswersV1(
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
  check(!sensoryDefinitionV1("taste:unsure"));
  check(!sensoryDefinitionV1("taste:nothing_stood_out"));
});

Deno.test("every dictionary aroma and every contextual reason has a valid parent path", () => {
  for (const option of sensoryOptionsV1()) {
    if (option.kind !== "reason") continue;
    const section = option.section as "aroma" | "taste";
    const ids = [
      ...(section === "aroma" ? [`notice:aroma:${option.subject}`] : []),
      `reaction:${section}:${option.subject}:${option.side}`,
      option.option_key,
    ];
    validateSensoryAnswersV1(request({ [`sensory_${section}`]: ids }).answers);
    equal(option.reaction, "none");
    check(option.semantic_key.startsWith("questionnaire.fact."));
  }
  equal(
    sensoryOptionsV1().find((o) =>
      o.option_key === "reason:taste:bitterness:disliked:disharmony"
    )?.meaning,
    "masksOtherSensations",
  );
  equal(
    sensoryDefinitionV1("reason:taste:acidity:disliked:too_weak")?.value,
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
  const six = sensoryOptionsV1().filter((o) =>
    o.section === "aroma" && o.kind === "notice"
  ).slice(0, 6).map((o) => o.option_key);
  validateSensoryAnswersV1(request({ sensory_aroma: six.slice(0, 5) }).answers);
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
  validateSensoryAnswersV1(request({ sensory_aroma: mixedAroma }).answers);
  // Stored answers from before the aroma reason page was removed still read.
  validateSensoryAnswersV1(
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
  validateSensoryAnswersV1(request({ sensory_taste: taste }).answers);
  validateSensoryAnswersV1(
    request({ sensory_taste: ["reaction:taste:acidity:liked"] }).answers,
  );
  // A stored target still reads when it names a reacted taste, one per side.
  validateSensoryAnswersV1(
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
  const ids = sensoryOptionsV1().filter((o) => o.kind === "finish").map((o) =>
    o.option_key
  );
  equal(ids.length, 6);
  validateSensoryAnswersV1(request({ sensory_finish: ids }).answers);
  for (const id of ["finish:tooShort", "finish:heavy", "finish:offFlavor"]) {
    equal(sensoryDefinitionV1(id)?.reaction, "burden");
  }
  for (
    const id of ["finish:pleasantLength", "finish:clean", "finish:aromaEcho"]
  ) {
    equal(sensoryDefinitionV1(id)?.reaction, "positive");
  }
  // 적당했어요: tastes and mouthfeel only, an evaluation with no direction.
  const fine = sensoryOptionsV1().filter((o) => o.option_key.endsWith(":fine"));
  equal(fine.length, 9);
  equal(
    fine.every((o) =>
      o.kind === "reaction" && o.reaction === "neutral" && o.side === null
    ),
    true,
  );
  equal(fine.some((o) => o.section === "aroma"), false);
  validateSensoryAnswersV1(
    request({
      sensory_taste: ["reaction:taste:sweetness:fine"],
      sensory_mouthfeel: [
        "notice:mouthfeel:heavy",
        "reaction:mouthfeel:heavy:fine",
      ],
    }).answers,
  );
  equal(
    sensoryDefinitionV1("finish:pleasantLength")?.value,
    "pleasantPersistence",
  );
});

export function maximumSensoryRequestV1() {
  const aromas = sensoryOptionsV1().filter((o) =>
    o.kind === "notice" && o.section === "aroma"
  ).sort((a, b) => b.option_key.length - a.option_key.length).slice(0, 5).map((
    o,
  ) => o.subject!);
  const tastes = ["sweetness", "acidity", "bitterness"];
  const aromaIds = aromas.flatMap((
    key,
  ) => [`notice:aroma:${key}`, `reaction:aroma:${key}:liked`]);
  const tasteIds = tastes.map((key, index) =>
    `reaction:taste:${key}:${index < 2 ? "liked" : "disliked"}`
  );
  tasteIds.push(
    ...["gentle", "pronounced", "harmony"].map((reason) =>
      `reason:taste:sweetness:liked:${reason}`
    ),
    ...["gentle", "pronounced", "harmony"].map((reason) =>
      `reason:taste:acidity:liked:${reason}`
    ),
    ...["too_strong", "too_weak", "disharmony"].map((reason) =>
      `reason:taste:bitterness:disliked:${reason}`
    ),
  );
  const mouth = sensoryOptionsV1().filter((o) =>
    o.kind === "notice" && o.section === "mouthfeel"
  ).flatMap((o) => [o.option_key, `reaction:mouthfeel:${o.subject}:liked`]);
  const finishes = sensoryOptionsV1().filter((o) => o.kind === "finish").map((
    o,
  ) => o.option_key);
  return request({
    sensory_aroma: aromaIds,
    sensory_taste: tasteIds,
    sensory_mouthfeel: mouth,
    sensory_finish: finishes,
  });
}
