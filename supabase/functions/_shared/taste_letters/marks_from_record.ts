/**
 * The marks one record puts on the four rulers of 취향 조각 (향, 단맛, 무게,
 * 여운), from what the record's answers say and what its bottle is.
 *
 * A mark is an answer read against the bottle it was said about: liking the
 * sweetness of a very sweet bottle marks far to the sweet side, and finding
 * an ordinary one too sweet marks the dry side. The bottle stands at its
 * level, read half as the number and half as where that number sits among
 * bottles of its kind. An answer that names its own side (a step of 4–5 or
 * 1–2) is never moved off that side by the catalog.
 *
 * Marks do not weigh the same. An answer about the ruler's own sensation
 * counts fully, and an answer about something next to it (스파이시, an aroma
 * that bothered, what stayed after swallowing) a little; the record's answer
 * to 다시 마시고 싶은지 moves each a quarter up or down.
 */
import type { BottleFacts } from "../taste_card/prepare/bottle.ts";
import type {
  GaugeLine,
  Interpretation,
} from "../taste_card/prepare/interpretation.ts";
import { groupOfAroma } from "../taste_card/facts/aroma_groups.ts";
import {
  placeOfLevel,
  placeOfSweetness,
} from "../taste_card/facts/kind_place.ts";
import {
  LEFT,
  type LetterMark,
  type LetterMarks,
  RIGHT,
} from "./letters_from_marks.ts";

/** What the marks are read from: the answers of one record and its bottle. */
export type RecordForLetters = {
  answers: Pick<Interpretation, "revisit" | "gauges" | "aromas">;
  bottle: Pick<
    BottleFacts,
    "category" | "style_key" | "region_entry" | "levels" | "tags"
  >;
};

/** Where an answer that names its side stands at least, and stands when the bottle has no level. */
const LOW_SIDE = 2;
const HIGH_SIDE = 4;
/**
 * The catalog's finish lengths nearly all read 4, so they tell bottles apart
 * too little to stand on: a finish answer stands half a step inside its end.
 */
const CLEAN_FINISH = 1.5;
const LONG_FINISH = 4.5;

const ANSWER_WEIGHT = 1;
const NEIGHBOUR_WEIGHT = 0.3;
/** 코끝 잔향 is about what stayed in the nose, a little beside the length itself. */
const AROMA_ECHO_WEIGHT = 0.7;
/** 다시 마시고 싶은지 moves a mark's weight this far up or down. */
const VERDICT_SHIFT = 0.25;

// 향: fresh groups lift, rich ones settle. 떼루아·세이보리 are neither and put no mark.
const FRESH_GROUPS = new Set(["fruity", "floral", "herbal", "vegetable"]);
const RICH_GROUPS = new Set([
  "bakery",
  "sweet_aroma",
  "nutty",
  "mocha",
  "milky",
  "woody",
  "smoky",
  "spice",
  "fermented",
  "leathery",
]);

function aromaSide(aroma: string): "fresh" | "rich" | null {
  const group = groupOfAroma(aroma);
  if (group && FRESH_GROUPS.has(group)) return "fresh";
  if (group && RICH_GROUPS.has(group)) return "rich";
  return null;
}

/** A mark before the record's 다시 마시고 싶은지 is weighed in. */
type Toned = LetterMark & { tone: "liked" | "burden" };

/**
 * Where the bottle stands on a ruler: half its level and half its place
 * among its own kind (kind_place.ts, the reading the fit check uses too). A
 * still wine's sweetness is read as how sweet it feels. Only a level read
 * for this bottle counts, never the kind's usual one.
 */
function bottlePlace(
  bottle: RecordForLetters["bottle"],
  dimension: "sweetness" | "body",
): number | null {
  const read = bottle.levels[dimension];
  if (read?.of !== "bottle") return null;
  // A wine of a place the dictionary knows is counted among that place's wines.
  const kind = bottle.region_entry ?? bottle.style_key;
  const place = dimension === "body"
    ? placeOfLevel("body", kind, bottle.category, read.level)
    : placeOfSweetness({
      style_key: kind,
      category_key: bottle.category,
      levels: Object.fromEntries(
        Object.entries(bottle.levels).flatMap(([name, level]) =>
          level.of === "bottle" ? [[name, level.level]] : []
        ),
      ),
      aroma_tags: [
        ...new Set(
          bottle.tags.filter((tag) => tag.section === "aroma").map((tag) =>
            tag.key
          ),
        ),
      ].sort(),
    });
  return place === null ? read.level : 1 + 4 * place.standing;
}

/** Too much at this place: the middle of what lies a step or more below it. */
const lessThan = (place: number) => Math.max(LEFT, place / 2);
/** Too little at this place: the middle of what lies a step or more above it. */
const moreThan = (place: number) => Math.min(RIGHT, (place + RIGHT + 1) / 2);

const neighbour = (place: number, tone: Toned["tone"]): Toned => ({
  place,
  weight: NEIGHBOUR_WEIGHT,
  from: "neighbour",
  tone,
});

/**
 * A gauge of the ruler's own sensation (단맛, 바디). Its step names the side:
 * the high side liked stands no lower than 4 and the low side liked no
 * higher than 2, wherever the bottle is; too much wants less than the bottle
 * has and too little more. The middle step liked stands where the bottle
 * does, and says nothing when the bottle has no level or when it was minded.
 */
function gaugeMarks(
  gauge: GaugeLine | undefined,
  bottle: number | null,
): Toned[] {
  if (!gauge) return [];
  const { side, reaction: tone } = gauge;
  let place: number | null;
  if (tone === "liked") {
    place = side === "high"
      ? Math.max(bottle ?? HIGH_SIDE, HIGH_SIDE)
      : side === "low"
      ? Math.min(bottle ?? LOW_SIDE, LOW_SIDE)
      : bottle;
  } else {
    place = side === "high"
      ? lessThan(bottle ?? HIGH_SIDE)
      : side === "low"
      ? moreThan(bottle ?? LOW_SIDE)
      : null;
  }
  return place === null
    ? []
    : [{ place, weight: ANSWER_WEIGHT, from: "answer", tone }];
}

/** 스파이시 sits next to weight: welcome leans heavy, too much leans light, too little says nothing. */
function spiceMarks(gauge: GaugeLine | undefined): Toned[] {
  if (!gauge || (gauge.reaction === "burden" && gauge.side === "low")) {
    return [];
  }
  return [
    neighbour(
      gauge.reaction === "liked" ? HIGH_SIDE : LOW_SIDE,
      gauge.reaction,
    ),
  ];
}

/**
 * The aromas named while drinking, by the nose and in the mouth, each once;
 * a 피트 gauge that says there was some is the 피트 aroma.
 */
function aromaMarks(answers: RecordForLetters["answers"]): Toned[] {
  const named = new Set(
    answers.aromas.filter((line) => line.stage !== "finish").map((line) =>
      `${line.aroma}:${line.reaction}`
    ),
  );
  const peat = answers.gauges.find((gauge) => gauge.axis === "peat");
  if (peat && peat.side !== "none") named.add(`peat:${peat.reaction}`);
  // What was liked decides, as the mix it was: two fresh aromas and a rich
  // one lean fresh a little, three rich ones lean rich more than one does.
  const liked = { fresh: 0, rich: 0 };
  const minded = { fresh: 0, rich: 0 };
  for (const entry of named) {
    const [aroma, reaction] = entry.split(":");
    const side = aromaSide(aroma);
    if (!side) continue;
    if (reaction === "liked") liked[side]++;
    else minded[side]++;
  }
  const marks: Toned[] = [];
  const count = liked.fresh + liked.rich;
  if (count > 0) {
    marks.push({
      place: LEFT + (RIGHT - LEFT) * (liked.rich + 0.5) / (count + 1),
      weight: ANSWER_WEIGHT,
      from: "answer",
      tone: "liked",
    });
  }
  // An aroma that bothered leans away from its side.
  if (minded.rich > 0) marks.push(neighbour(LOW_SIDE, "burden"));
  if (minded.fresh > 0) marks.push(neighbour(HIGH_SIDE, "burden"));
  return marks;
}

/** 여운의 길이 and what stayed in the nose after swallowing. */
function finishMarks(answers: RecordForLetters["answers"]): Toned[] {
  const marks: Toned[] = [];
  const length = answers.gauges.find((gauge) => gauge.axis === "finish_length");
  if (length && length.side !== "middle") {
    const long = length.side === "high";
    // A long finish liked and a short one minded both want it to stay; a
    // short one liked and a long one minded both want it to clear.
    marks.push({
      place: long === (length.reaction === "liked")
        ? LONG_FINISH
        : CLEAN_FINISH,
      weight: ANSWER_WEIGHT,
      from: "answer",
      tone: length.reaction,
    });
  }
  const stayed = answers.aromas.filter((line) => line.stage === "finish");
  // A liked aroma that stayed is about the nose, a little beside the length
  // itself; one that bothered only leans.
  if (stayed.some((line) => line.reaction === "liked")) {
    marks.push({
      place: LONG_FINISH,
      weight: AROMA_ECHO_WEIGHT,
      from: "answer",
      tone: "liked",
    });
  }
  if (stayed.some((line) => line.reaction === "burden")) {
    marks.push(neighbour(LOW_SIDE, "burden"));
  }
  return marks;
}

/**
 * The record's own verdict weighs its marks: what was liked in a drink wanted
 * again counts more and what was minded in it less, the other way round in a
 * drink not wanted again.
 */
function weighByVerdict(
  marks: readonly Toned[],
  revisit: RecordForLetters["answers"]["revisit"],
): LetterMark[] {
  return marks.map(({ tone, ...mark }) => {
    let weight = mark.weight;
    if (revisit === "want_again") {
      weight *= tone === "burden" ? 1 - VERDICT_SHIFT : 1 + VERDICT_SHIFT;
    } else if (revisit === "do_not_want_again") {
      weight *= tone === "burden" ? 1 + VERDICT_SHIFT : 1 - VERDICT_SHIFT;
    }
    return { ...mark, weight };
  });
}

/** One record's marks on each ruler. */
export function marksFromRecord(
  { answers, bottle }: RecordForLetters,
): LetterMarks {
  const gauge = (axis: GaugeLine["axis"]) =>
    answers.gauges.find((line) => line.axis === axis);
  const weigh = (marks: readonly Toned[]) =>
    weighByVerdict(marks, answers.revisit);
  return {
    aroma: weigh(aromaMarks(answers)),
    sweetness: weigh(
      gaugeMarks(gauge("sweetness"), bottlePlace(bottle, "sweetness")),
    ),
    weight: weigh([
      ...gaugeMarks(gauge("body"), bottlePlace(bottle, "body")),
      ...spiceMarks(gauge("spice")),
    ]),
    finish: weigh(finishMarks(answers)),
  };
}
