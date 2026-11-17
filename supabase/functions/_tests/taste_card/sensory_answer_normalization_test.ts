// From chosen options to what the engine reads: the record's gauges and
// aromas (answer_normalization.ts), then the gauge and reaction facts of the
// card (facts/reading.ts).
import { normalizeSensoryAnswers } from "../../_shared/taste_card/record/answer_normalization.ts";
import {
  GAUGE_AXES,
  type GaugeAxis,
} from "../../_shared/taste_card/facts/facts.ts";
import { readCard } from "../../_shared/taste_card/facts/reading.ts";
import {
  type SensoryOption,
  sensoryOption,
} from "../../_shared/taste_card/record/questionnaire.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
import { assert, same } from "../helpers/assert.ts";
import { recordFrom } from "../helpers/card_fixture_record.ts";

function row(key: string): SensoryOption {
  const option = sensoryOption(key);
  assert(option, `unknown test option: ${key}`);
  return option;
}
const EVERY_AXIS: ReadonlySet<GaugeAxis> = new Set(GAUGE_AXES);

Deno.test("answer normalization: gauges come in the order of the axes, aromas by picker and name, whatever order they were chosen in", () => {
  const rows = [
    "aroma:finish:smoke:disliked",
    "level:finish_length:4:liked",
    "aroma:palate:vanilla:liked",
    "level:tannin:4:disliked",
    "aroma:nose:oak:liked",
    "level:sweetness:2:liked",
    "aroma:nose:cherry:liked",
    "revisit:wantAgain",
  ].map(row);
  const original = JSON.stringify(rows);
  const result = normalizeSensoryAnswers(rows, EVERY_AXIS);
  same(result.gauges, [
    {
      axis: "sweetness",
      level: 2,
      reaction: "liked",
      answerRef: "level:sweetness:2:liked",
    },
    {
      axis: "tannin",
      level: 4,
      reaction: "burden",
      answerRef: "level:tannin:4:disliked",
    },
    {
      axis: "finish_length",
      level: 4,
      reaction: "liked",
      answerRef: "level:finish_length:4:liked",
    },
  ]);
  same(
    result.aromas.map((a) => [a.stage, a.key, a.reaction, a.answerRef]),
    [
      ["nose", "cherry", "liked", "aroma:nose:cherry:liked"],
      ["nose", "oak", "liked", "aroma:nose:oak:liked"],
      ["palate", "vanilla", "liked", "aroma:palate:vanilla:liked"],
      ["finish", "smoke", "burden", "aroma:finish:smoke:disliked"],
    ],
  );
  same(result.revisit, {
    intent: "want_again",
    answerRefs: ["revisit:wantAgain"],
  });
  same(normalizeSensoryAnswers([...rows].reverse(), EVERY_AXIS), result);
  assert(JSON.stringify(rows) === original, "input mutated");
});

Deno.test("answer normalization: a skipped nose and an unanswered revisit are not answers", () => {
  const skipped = normalizeSensoryAnswers(
    [row("nose:unsure"), row("revisit:unsure")],
    EVERY_AXIS,
  );
  same(skipped.gauges, []);
  same(skipped.aromas, []);
  same(skipped.revisit, {
    intent: "unknown",
    answerRefs: ["revisit:unsure"],
  });
  same(normalizeSensoryAnswers([], EVERY_AXIS).revisit, {
    intent: null,
    answerRefs: [],
  });
});

Deno.test("answer normalization: a gauge the drink's kind is not asked is left out", () => {
  const rows = [
    "level:sweetness:4:liked",
    "level:tannin:4:liked",
    "level:peat:5:liked",
  ].map(row);
  same(
    normalizeSensoryAnswers(rows, new Set<GaugeAxis>(["sweetness", "body"]))
      .gauges.map((g) => g.axis),
    ["sweetness"],
  );
});

/* ------------------------------------------------------- the reading table */

const bottle = (
  category: SensoryProduct["category"],
  styleKey: string | null,
): SensoryProduct => ({
  name: "시험 병",
  category,
  styleKey,
  region: null,
  abv: null,
  levels: {},
  levelRefs: {},
  descriptors: [],
});
const RED = bottle("wine", "red_wine");
const SPARKLING = bottle("wine", "sparkling_wine");
const WHISKY = bottle("whisky", "single_malt_whisky");
const SAKE = bottle("sake", "junmai");

/** The reactions one record reads to: "taste.sweetness/drinking/liked/pronounced". */
function read(keys: string[], product: SensoryProduct = RED) {
  const reading = readCard(recordFrom("reading", keys, product));
  return {
    gauges: reading.gauges.map((g) => `${g.axis}:${g.level}:${g.reaction}`),
    reactions: reading.reactions.map((r) =>
      [
        `${r.subject.domain}.${r.subject.key}`,
        r.phase,
        r.reaction,
        r.qualifier ?? "-",
        ...(r.stages ? [r.stages.join("+")] : []),
      ].join("/")
    ),
    reading,
  };
}
const one = (key: string, product: SensoryProduct = RED) =>
  read([key], product).reactions;

Deno.test("reading: 단맛, 산미 and 감칠맛 name their strength by the step and how it was taken", () => {
  for (
    const [key, expected] of [
      ["level:sweetness:5:liked", "taste.sweetness/drinking/liked/pronounced"],
      ["level:sweetness:4:liked", "taste.sweetness/drinking/liked/pronounced"],
      ["level:sweetness:2:liked", "taste.sweetness/drinking/liked/gentle"],
      ["level:sweetness:1:liked", "taste.sweetness/drinking/liked/gentle"],
      ["level:acidity:4:disliked", "taste.acidity/drinking/burden/excessive"],
      ["level:acidity:5:disliked", "taste.acidity/drinking/burden/excessive"],
      ["level:acidity:2:disliked", "taste.acidity/drinking/burden/too_weak"],
      ["level:acidity:1:disliked", "taste.acidity/drinking/burden/too_weak"],
      // The middle step names no side: liked, or a burden with no reason.
      ["level:sweetness:3:liked", "taste.sweetness/drinking/liked/-"],
      ["level:sweetness:3:disliked", "taste.sweetness/drinking/burden/-"],
    ] as const
  ) same(one(key), [expected], key);
  // 사케의 감칠맛 is a taste of its own.
  same(one("level:umami:4:liked", SAKE), [
    "taste.umami/drinking/liked/pronounced",
  ]);
  same(one("level:umami:2:disliked", SAKE), [
    "taste.umami/drinking/burden/too_weak",
  ]);
});

Deno.test("reading: 바디, 타닌, 탄산, 스파이시 and 피트 become the sensation their step names", () => {
  for (
    const [key, product, expected] of [
      ["level:body:1:liked", RED, ["mouthfeel.light/drinking/liked/-"]],
      ["level:body:2:disliked", RED, ["mouthfeel.light/drinking/burden/-"]],
      ["level:body:4:liked", RED, ["mouthfeel.heavy/drinking/liked/-"]],
      ["level:body:5:disliked", RED, ["mouthfeel.heavy/drinking/burden/-"]],
      ["level:tannin:2:liked", RED, ["mouthfeel.smooth/drinking/liked/-"]],
      ["level:tannin:4:disliked", RED, ["mouthfeel.drying/drinking/burden/-"]],
      // The middle step of 바디 and 타닌 is kept as a gauge and says nothing.
      ["level:body:3:liked", RED, []],
      ["level:tannin:3:disliked", RED, []],
      // The lowest step of 탄산, 스파이시 and 피트 says there was none.
      ["level:sparkling:1:liked", SPARKLING, []],
      [
        "level:sparkling:2:liked",
        SPARKLING,
        ["mouthfeel.bubbles/drinking/liked/gentle"],
      ],
      [
        "level:sparkling:5:disliked",
        SPARKLING,
        ["mouthfeel.bubbles/drinking/burden/excessive"],
      ],
      ["level:spice:1:liked", WHISKY, []],
      ["level:spice:3:liked", WHISKY, ["mouthfeel.warmth/drinking/liked/-"]],
      [
        "level:spice:5:disliked",
        WHISKY,
        ["mouthfeel.warmth/drinking/burden/excessive"],
      ],
      ["level:peat:1:liked", WHISKY, []],
      ["level:peat:2:liked", WHISKY, ["aroma.peat/drinking/liked/-"]],
      ["level:peat:5:disliked", WHISKY, ["aroma.peat/drinking/burden/-"]],
    ] as const
  ) same(one(key, product), expected, key);
});

Deno.test("reading: 여운의 길이 is a long finish, a clean one, too brief or lingering; 끝맛의 인상 is its own subject at every step", () => {
  for (
    const [key, expected] of [
      ["level:finish_length:4:liked", ["finish.persistence/finish/liked/-"]],
      ["level:finish_length:5:liked", ["finish.persistence/finish/liked/-"]],
      ["level:finish_length:2:liked", ["finish.clean/finish/liked/-"]],
      [
        "level:finish_length:1:disliked",
        ["finish.persistence/finish/burden/too_brief"],
      ],
      [
        "level:finish_length:5:disliked",
        ["finish.persistence/finish/burden/lingering"],
      ],
      ["level:finish_length:3:liked", []],
      ["level:finish_length:3:disliked", []],
      ["level:finish_character:1:liked", ["finish.character/finish/liked/-"]],
      ["level:finish_character:3:liked", ["finish.character/finish/liked/-"]],
      [
        "level:finish_character:5:disliked",
        ["finish.character/finish/burden/-"],
      ],
    ] as const
  ) same(one(key), expected, key);
});

Deno.test("reading: every answered gauge is kept as the reader set it, the silent steps included", () => {
  const { gauges, reactions } = read([
    "level:body:3:liked",
    "level:tannin:3:disliked",
    "level:finish_length:3:liked",
    "level:sweetness:3:liked",
  ]);
  same(gauges, [
    "sweetness:3:liked",
    "body:3:liked",
    "tannin:3:burden",
    "finish_length:3:liked",
  ]);
  same(reactions, ["taste.sweetness/drinking/liked/-"]);
});

Deno.test("reading: a gauge the kind is not asked is dropped, gauge and reaction both", () => {
  // A white wine has no 타닌, a red no 탄산감, a wine no 스파이시, 피트 or
  // 감칠맛.
  const white = read([
    "level:sweetness:2:liked",
    "level:tannin:4:disliked",
    "level:sparkling:4:liked",
    "level:spice:4:liked",
    "level:peat:4:liked",
    "level:umami:4:liked",
  ], bottle("wine", "white_wine"));
  same(white.gauges, ["sweetness:2:liked"]);
  same(white.reactions, ["taste.sweetness/drinking/liked/gentle"]);
  // A whisky is not asked 산미.
  same(read(["level:acidity:4:liked", "level:peat:4:liked"], WHISKY).gauges, [
    "peat:4:liked",
  ]);
  // A drink of no known kind is asked the wine's three plain gauges.
  same(
    read(
      ["level:body:4:liked", "level:tannin:4:liked", "level:spice:4:liked"],
      bottle(null, null),
    ).gauges,
    ["body:4:liked"],
  );
});

Deno.test("reading: an aroma named by the nose and in the mouth is one reaction with its stages; the finish is its own", () => {
  const { reactions } = read([
    "aroma:nose:vanilla:liked",
    "aroma:palate:vanilla:liked",
    "aroma:palate:oak:disliked",
    "aroma:nose:cherry:liked",
    "aroma:palate:cherry:disliked",
  ]);
  same(reactions, [
    // One aroma liked by the nose and minded in the mouth stays two answers.
    "aroma.cherry/drinking/liked/-/nose",
    "aroma.cherry/drinking/burden/-/palate",
    "aroma.oak/drinking/burden/-/palate",
    "aroma.vanilla/drinking/liked/-/nose+palate",
  ]);
  // What stayed after swallowing: each aroma, and one answer of the finish
  // for the liked ones (잔향) and one for the minded ones.
  const finish = read([
    "aroma:finish:vanilla:liked",
    "aroma:finish:oak:liked",
    "aroma:finish:smoke:disliked",
  ]);
  same(finish.reactions, [
    "aroma.oak/finish/liked/-/finish",
    "aroma.smoke/finish/burden/-/finish",
    "aroma.vanilla/finish/liked/-/finish",
    "finish.aroma_echo/finish/liked/lingering",
    "finish.off_flavor/finish/burden/lingering",
  ]);
  same(
    finish.reading.reactions.find((r) => r.subject.key === "aroma_echo")
      ?.answer_refs,
    ["aroma:finish:oak:liked", "aroma:finish:vanilla:liked"],
  );
  // The 피트 gauge and a 피트 aroma taken the same way are one reaction.
  const peat = read(
    ["level:peat:4:liked", "aroma:nose:peat:liked"],
    WHISKY,
  );
  same(peat.reactions, ["aroma.peat/drinking/liked/-/nose"]);
  same(peat.reading.reactions[0].answer_refs, [
    "aroma:nose:peat:liked",
    "level:peat:4:liked",
  ]);
});

Deno.test("reading: the revisit answer is kept apart from the sensations, and a skipped nose is no aroma", () => {
  const middle = read(["revisit:wouldAcceptAgain", "level:body:3:liked"]);
  same([middle.gauges.length, middle.reactions], [1, []]);
  same(middle.reading.record.revisit, "would_accept_again");
  same(read(["nose:unsure", "level:body:3:liked"]).reactions, []);
});
