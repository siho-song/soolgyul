// From chosen options to what the pipeline works from: the record's gauges
// and aromas (answer_normalization.ts), then 준비: what the answers say
// (prepare/interpretation.ts) and what the bottle is (prepare/bottle.ts).
import { normalizeSensoryAnswers } from "../../_shared/taste_card/record/answer_normalization.ts";
import {
  GAUGE_AXES,
  type GaugeAxis,
} from "../../_shared/taste_card/facts/facts.ts";
import { prepareCard } from "../../_shared/taste_card/prepare/prepare.ts";
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

/* ------------------------------------------------------------- the bottles */

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

/* ------------------------------------------------- what the answers say */

/** 해석 결과 of one record: "sweetness:2:low:liked", "nose:oak:liked". */
function meaning(keys: string[], product: SensoryProduct = RED) {
  const said = prepareCard(recordFrom("meaning", keys, product)).interpretation;
  return {
    said,
    gauges: said.gauges.map((g) =>
      `${g.axis}:${g.level}:${g.side}:${g.reaction}`
    ),
    aromas: said.aromas.map((a) => `${a.stage}:${a.aroma}:${a.reaction}`),
  };
}

Deno.test("해석: a step names its side by the gauge's scale, the same for every kind of drink, and every answered step is kept", () => {
  // A strength: 1–2 low, 3 middle, 4–5 high. The middle step is kept, liked
  // or minded, on the gauges the card makes no reaction of (바디, 타닌, 여운).
  same(
    meaning([
      "level:sweetness:1:liked",
      "level:acidity:2:disliked",
      "level:body:3:liked",
      "level:tannin:3:disliked",
      "level:finish_length:5:liked",
    ]).gauges,
    [
      "sweetness:1:low:liked",
      "acidity:2:low:burden",
      "body:3:middle:liked",
      "tannin:3:middle:burden",
      "finish_length:5:high:liked",
    ],
  );
  // The words differ by kind, the reading does not.
  same(
    meaning(
      ["level:sweetness:4:liked", "level:umami:2:disliked"],
      SAKE,
    ).gauges,
    ["sweetness:4:high:liked", "umami:2:low:burden"],
  );
  // The first step of 탄산감 and 피트 says there was none, and stays an
  // answer; 마일드 of 스파이시 is a low step.
  same(meaning(["level:sparkling:1:disliked"], SPARKLING).gauges, [
    "sparkling:1:none:burden",
  ]);
  same(
    meaning(
      ["level:spice:1:liked", "level:peat:1:liked"],
      WHISKY,
    ).gauges,
    ["spice:1:low:liked", "peat:1:none:liked"],
  );
  // 끝맛의 인상 lies between two characters: its ends, not a strength.
  const character = meaning([
    "level:finish_character:2:liked",
  ]).said.gauges[0];
  same([character.scale, character.side], ["between", "low"]);
  same(
    meaning(["level:finish_character:3:disliked"]).gauges,
    ["finish_character:3:middle:burden"],
  );
});

Deno.test("해석: an aroma is one line for each place it was picked, and nothing the reader did not say is added", () => {
  const { said, aromas } = meaning([
    "aroma:nose:oak:liked",
    "aroma:palate:oak:liked",
    "aroma:finish:oak:disliked",
    "aroma:nose:cherry:liked",
  ]);
  same(aromas, [
    "nose:cherry:liked",
    "nose:oak:liked",
    "palate:oak:liked",
    "finish:oak:burden",
  ]);
  same(said.aromas.map((a) => a.answer_ref), [
    "aroma:nose:cherry:liked",
    "aroma:nose:oak:liked",
    "aroma:palate:oak:liked",
    "aroma:finish:oak:disliked",
  ]);
  // The 피트 gauge is a gauge line, not an aroma picked somewhere.
  const peat = meaning(["level:peat:4:liked"], WHISKY);
  same([peat.gauges, peat.aromas], [["peat:4:high:liked"], []]);
});

Deno.test("해석: 다시 마시고 싶은지 changes how much an answer weighs, never what it says", () => {
  const answers = ["level:body:4:liked", "aroma:nose:oak:disliked"];
  const weights = (revisit: string) => {
    const { said, gauges, aromas } = meaning([revisit, ...answers]);
    return {
      lines: [...gauges, ...aromas],
      weight: [said.gauges[0].weight, said.aromas[0].weight],
      head: said.weight,
    };
  };
  const again = weights("revisit:wantAgain");
  const never = weights("revisit:doNotWantAgain");
  same(again.lines, ["body:4:high:liked", "nose:oak:burden"]);
  same(never.lines, again.lines);
  same(again.weight, [1, 0.7]);
  same(never.weight, [0.5, 1]);
  same(again.head, { liked: 1, burden: 0.7 });
  same(weights("revisit:wouldAcceptAgain").weight, [0.8, 0.85]);
  same(weights("revisit:unsure").weight, [0.8, 0.85]);
});

/* ----------------------------------------------------- what the bottle is */

Deno.test("조회: the bottle's facts are carried as the catalog states them, and nothing is worked out", () => {
  const { bottle: facts } = prepareCard(
    recordFrom("bottle", ["level:body:4:liked"], {
      ...bottle("wine", "red_wine"),
      name: "시험 레드 2019",
      abv: 14,
      grapeVarietyKeys: ["cabernet_sauvignon"],
      processes: ["oak_wood"],
      producer: "시험 양조장",
      vintageYear: 2019,
      levels: { sweetness: 1, body: 4 },
      levelSources: { sweetness: 2, body: 4 },
    }),
  );
  same(
    [facts.grapes, facts.processes, facts.producer, facts.vintage_year],
    [["cabernet_sauvignon"], ["oak_wood"], "시험 양조장", 2019],
  );
  same(facts.abv, { of: "bottle", percent: 14 });
  // A level read for the bottle is the bottle's; one the catalog marks as a
  // kind estimate (grade 4) is the kind's.
  same(facts.levels.sweetness, { level: 1, of: "bottle", source: 2 });
  same(facts.levels.body, { level: 4, of: "kind", source: 4 });
  // No strength level is worked out from the ABV here.
  same(facts.levels.alcohol_presence, undefined);
});

Deno.test("조회: an empty level or ABV falls back to the kind's and says so; an empty fact stays empty", () => {
  const { bottle: empty } = prepareCard(
    recordFrom("bottle", ["level:body:4:liked"], bottle("wine", "red_wine")),
  );
  // A red wine is usually dry and has tannin: the kind's table, not this bottle.
  const { sweetness, astringency } = empty.levels;
  same([sweetness?.of, sweetness?.source], ["kind", "kind_table"]);
  same([astringency?.of, astringency?.source], ["kind", "kind_table"]);
  assert(
    empty.abv?.of === "kind" && empty.abv.low < empty.abv.high,
    "the kind's usual strength",
  );
  // Grapes, region, process and maker are never guessed.
  same(
    [empty.grapes, empty.region, empty.processes, empty.producer],
    [[], null, [], null],
  );
  // A drink of no known kind has nothing to fall back to.
  const { bottle: unknown } = prepareCard(
    recordFrom("bottle", ["level:body:4:liked"], bottle(null, null)),
  );
  same([unknown.levels, unknown.abv], [{}, null]);
});
