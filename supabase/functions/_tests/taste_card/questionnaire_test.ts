// The questionnaire a record is answered under: its published registry, what
// one record's answers may hold, and the gauges a drink is asked.
import { parseCreateTasteCardResultRequest } from "../../_shared/taste_card/service/serialization.ts";
import {
  gaugeSheet,
  SENSORY_QUESTIONNAIRE_VERSION,
  sensoryOption,
  sensoryOptions,
  validateSensoryAnswers,
  verifySensoryRegistry,
} from "../../_shared/record_reading/record/questionnaire.ts";
import type { QuestionnaireAnswerInput } from "../../_shared/taste_card/service/types.ts";
import flutterWire from "../fixtures/sensory_flutter_wire_v2.json" with {
  type: "json",
};
import { assert as check, same as equal } from "../helpers/assert.ts";
import { answersOf } from "../helpers/card_fixture_record.ts";
import { tasteCardRequest } from "../helpers/taste_card_service.ts";

const answer = (
  question_key: string,
  selected_option_keys: string[],
): QuestionnaireAnswerInput => ({
  question_key,
  selected_option_keys,
  free_text: null,
});
const REVISIT = answer("sensory_revisit", ["revisit:wantAgain"]);

function rejects(answers: QuestionnaireAnswerInput[], code: string) {
  let error: unknown;
  try {
    validateSensoryAnswers(answers);
  } catch (caught) {
    error = caught;
  }
  check(error instanceof Error, `invalid answers accepted, expected ${code}`);
  check(error.message.includes(code), error.message);
}

Deno.test("sensory registry is the published one, and the app sends its version", async () => {
  await verifySensoryRegistry();
  const options = sensoryOptions();
  equal(new Set(options.map((item) => item.option_key)).size, options.length);
  check(options.length > 800, "every aroma and gauge step is an option");
  // Six questions: 재음용, three aroma pickers and two gauge pages.
  equal([...new Set(options.map((item) => item.question_key))].sort(), [
    "sensory_finish_aroma",
    "sensory_finish_level",
    "sensory_nose_aroma",
    "sensory_palate_aroma",
    "sensory_palate_level",
    "sensory_revisit",
  ]);
  // Every aroma is offered in each of the three pickers, liked or not.
  const aromas = options.filter((item) => item.kind === "aroma");
  const names = new Set(aromas.map((item) => item.aroma));
  check(names.size > 100, "the whole aroma dictionary is offered");
  equal(aromas.length, names.size * 3 * 2);
  // Ten gauges of five steps, each liked or not.
  equal(options.filter((item) => item.kind === "level").length, 10 * 5 * 2);
  equal(options.filter((item) => item.kind === "revisit").length, 4);
  const submission = await Deno.readTextFile(
    new URL(
      "../../../../lib/src/features/taste_card/data/sensory_submission.dart",
      import.meta.url,
    ),
  );
  check(submission.includes(`'${SENSORY_QUESTIONNAIRE_VERSION}'`));
  equal(SENSORY_QUESTIONNAIRE_VERSION, "sensory-questionnaire-v2");
});

Deno.test("an option says everything itself: its question, its gauge or aroma, and how it was taken", () => {
  equal(sensoryOption("level:tannin:4:disliked"), {
    question_key: "sensory_palate_level",
    option_key: "level:tannin:4:disliked",
    kind: "level",
    axis: "tannin",
    level: 4,
    reaction: "burden",
  });
  equal(sensoryOption("aroma:finish:smoke:liked"), {
    question_key: "sensory_finish_aroma",
    option_key: "aroma:finish:smoke:liked",
    kind: "aroma",
    stage: "finish",
    aroma: "smoke",
    reaction: "liked",
  });
  equal(
    sensoryOption("level:finish_character:3:liked")?.question_key,
    "sensory_finish_level",
  );
  equal(sensoryOption("revisit:wouldAcceptAgain"), {
    question_key: "sensory_revisit",
    option_key: "revisit:wouldAcceptAgain",
    kind: "revisit",
    intent: "would_accept_again",
  });
  equal(sensoryOption("nose:unsure")?.kind, "unsure");
  // The questions before the gauges are no longer known.
  for (
    const key of [
      "notice:aroma:apple",
      "reaction:taste:sweetness:liked",
      "reason:taste:sweetness:liked:gentle",
      "notice:mouthfeel:heavy",
      "finish:clean",
      "aroma:unsure",
      "level:bitterness:3:liked",
      "level:sweetness:6:liked",
      "aroma:nose:not_a_dictionary_key:liked",
    ]
  ) check(!sensoryOption(key), key);
});

Deno.test("다시 마시고 싶은지 and one sensation must be answered: any other question may be left out or empty", () => {
  // One aroma or one gauge step is enough, at any stage.
  for (
    const sensed of [
      answer("sensory_nose_aroma", ["aroma:nose:apple:liked"]),
      answer("sensory_palate_level", ["level:sweetness:3:liked"]),
      answer("sensory_palate_aroma", ["aroma:palate:apple:disliked"]),
      answer("sensory_finish_level", ["level:finish_length:1:disliked"]),
      answer("sensory_finish_aroma", ["aroma:finish:apple:liked"]),
    ]
  ) validateSensoryAnswers([REVISIT, sensed]);
  // 향을 건너뛴 기록: nose:unsure stands alone, and the rest may be empty.
  validateSensoryAnswers([
    REVISIT,
    answer("sensory_nose_aroma", ["nose:unsure"]),
    answer("sensory_palate_level", []),
    answer("sensory_palate_aroma", []),
    answer("sensory_finish_level", ["level:finish_character:3:liked"]),
    answer("sensory_finish_aroma", []),
  ]);
  // 다시 마시고 싶은지 alone, or with a skipped nose, is no record.
  rejects([REVISIT], "sensation_required");
  rejects(
    [
      REVISIT,
      answer("sensory_nose_aroma", ["nose:unsure"]),
      answer("sensory_palate_level", []),
      answer("sensory_palate_aroma", []),
      answer("sensory_finish_level", []),
      answer("sensory_finish_aroma", []),
    ],
    "sensation_required",
  );
  rejects([], "revisit_required");
  rejects([answer("sensory_revisit", [])], "revisit_required");
  rejects(
    [answer("sensory_revisit", ["revisit:wantAgain", "revisit:unsure"])],
    "revisit_required",
  );
  rejects(
    [
      REVISIT,
      answer("sensory_nose_aroma", ["nose:unsure", "aroma:nose:apple:liked"]),
    ],
    "exclusive_state",
  );
});

Deno.test("a record of every question passes, and so does every aroma at once", () => {
  validateSensoryAnswers(
    answersOf([
      "revisit:wantAgain",
      "aroma:nose:black_cherry:liked",
      "aroma:nose:oak:disliked",
      "level:sweetness:2:liked",
      "level:tannin:4:disliked",
      "aroma:palate:vanilla:liked",
      "level:finish_length:4:liked",
      "level:finish_character:3:liked",
      "aroma:finish:smoke:disliked",
    ]),
  );
  // The same aroma may be named by the nose, in the mouth and after swallowing.
  validateSensoryAnswers(
    answersOf([
      "revisit:unsure",
      "aroma:nose:vanilla:liked",
      "aroma:palate:vanilla:disliked",
      "aroma:finish:vanilla:liked",
    ]),
  );
  // Every aroma noticed is taken: the question has no count to stay under.
  const every = sensoryOptions().filter((o) =>
    o.kind === "aroma" && o.stage === "nose" && o.reaction === "liked"
  ).map((o) => o.option_key);
  validateSensoryAnswers([REVISIT, answer("sensory_nose_aroma", every)]);
});

Deno.test("sensory wire rejects unknown and duplicate ids, another question's option, two answers for one gauge or aroma, and injected meaning", () => {
  rejects(
    [REVISIT, answer("invented", [])],
    "question_unknown_or_duplicate",
  );
  rejects(
    [REVISIT, answer("sensory_taste", ["reaction:taste:sweetness:liked"])],
    "question_unknown_or_duplicate",
  );
  rejects([REVISIT, REVISIT], "question_unknown_or_duplicate");
  rejects(
    [
      REVISIT,
      answer("sensory_nose_aroma", ["aroma:nose:not_a_dictionary_key:liked"]),
    ],
    "option_unknown_or_wrong_question",
  );
  // An option of another question: a palate aroma among the nose's, a finish
  // gauge on the palate page.
  rejects(
    [REVISIT, answer("sensory_nose_aroma", ["aroma:palate:apple:liked"])],
    "option_unknown_or_wrong_question",
  );
  rejects(
    [REVISIT, answer("sensory_palate_level", ["level:finish_length:4:liked"])],
    "option_unknown_or_wrong_question",
  );
  rejects(
    [
      REVISIT,
      answer("sensory_nose_aroma", [
        "aroma:nose:apple:liked",
        "aroma:nose:apple:liked",
      ]),
    ],
    "option_duplicate",
  );
  // One step per gauge, and one of liked or 아쉬웠어요.
  rejects(
    [
      REVISIT,
      answer("sensory_palate_level", [
        "level:acidity:2:liked",
        "level:acidity:4:liked",
      ]),
    ],
    "level_conflict",
  );
  rejects(
    [
      REVISIT,
      answer("sensory_palate_level", [
        "level:acidity:4:liked",
        "level:acidity:4:disliked",
      ]),
    ],
    "level_conflict",
  );
  rejects(
    [
      REVISIT,
      answer("sensory_palate_aroma", [
        "aroma:palate:apple:liked",
        "aroma:palate:apple:disliked",
      ]),
    ],
    "aroma_conflict",
  );
  rejects(
    [REVISIT, { ...answer("sensory_nose_aroma", []), free_text: "사과" }],
    "structured_answer_free_text",
  );
  const injected = tasteCardRequest(["aroma:nose:apple:liked"]);
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

Deno.test("the request the app sends, shared with the Flutter suite, passes the parser and the registry", () => {
  const parsed = parseCreateTasteCardResultRequest(flutterWire);
  equal(parsed.questionnaire_version, SENSORY_QUESTIONNAIRE_VERSION);
  validateSensoryAnswers(parsed.answers);
  equal(parsed.answers.map((a) => a.question_key), [
    "sensory_revisit",
    "sensory_nose_aroma",
    "sensory_palate_level",
    "sensory_palate_aroma",
    "sensory_finish_level",
    "sensory_finish_aroma",
  ]);
});

Deno.test("the gauge sheet: each kind is asked its own gauges, a conditional one only for its styles", () => {
  const axes = (category: string | null, style: string | null) => {
    const sheet = gaugeSheet(category, style);
    return [
      sheet.palate.map((row) => row.axis).join(),
      sheet.finish.map((row) => row.axis).join(),
    ];
  };
  const finish = "finish_length,finish_character";
  equal(axes("wine", "white_wine"), ["sweetness,acidity,body", finish]);
  equal(axes("wine", "red_wine"), ["sweetness,acidity,body,tannin", finish]);
  equal(axes("wine", "sparkling_wine"), [
    "sweetness,acidity,body,sparkling",
    finish,
  ]);
  // A wine of no known style is asked neither 타닌 nor 탄산감.
  equal(axes("wine", null), ["sweetness,acidity,body", finish]);
  equal(axes("whisky", "single_malt_whisky"), [
    "sweetness,body,spice,peat",
    finish,
  ]);
  equal(axes("sake", "junmai"), ["sweetness,acidity,umami,body", finish]);
  equal(axes("korean_traditional", "takju"), [
    "sweetness,acidity,body,sparkling",
    finish,
  ]);
  // A distilled soju is asked as a spirit, under names of its own.
  equal(axes("korean_traditional", "distilled_soju"), [
    "sweetness,body,spice",
    finish,
  ]);
  equal(
    gaugeSheet("korean_traditional", "distilled_soju").palate.map((row) =>
      row.label
    ).join(),
    "단맛,바디,자극",
  );
  equal(
    gaugeSheet("korean_traditional", "yakju").palate.map((row) => row.label)
      .join(),
    "단맛,산미,질감",
  );
  // 종류를 모르는 전통주 is still asked 탄산감.
  equal(axes("korean_traditional", null), [
    "sweetness,acidity,body,sparkling",
    finish,
  ]);
  // A kind without a sheet, or no kind at all: the wine's three plain gauges.
  equal(axes("beer", "ipa"), ["sweetness,acidity,body", finish]);
  equal(axes(null, null), ["sweetness,acidity,body", finish]);
  // Every gauge has a name, five steps and the words of its two ends.
  for (const category of ["wine", "whisky", "sake", "korean_traditional"]) {
    const sheet = gaugeSheet(category, null);
    for (const row of [...sheet.palate, ...sheet.finish]) {
      check(row.label.length > 0 && row.terms.length === 5, row.axis);
      check(row.terms.every((term) => term.length > 0), row.axis);
      equal(row.ends?.length, 2, row.axis);
    }
  }
});
