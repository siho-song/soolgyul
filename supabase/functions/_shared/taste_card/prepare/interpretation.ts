/**
 * 준비 · 해석: what the answers of one record say (해석 결과), read once for
 * every part that reads answers.
 *
 * Only the reader's answers are read. Nothing of the bottle enters here (its
 * levels, tags or facts): an answer is not held against the catalog, and what
 * the bottle is belongs to the lookup (bottle.ts) and to the stages that
 * explain or compare.
 *
 * A gauge is read by its scale alone, the same for every kind of drink. The
 * kinds differ in which gauges they are asked and in the words of the steps
 * (catalog/sensory/gauge-definitions.json), not in the reading:
 *
 *   strength    1–2 low, 3 middle, 4–5 high
 *   from_none   1 none, 2 low, 3 middle, 4–5 high (탄산감, 피트: the first
 *               step says there was none of it)
 *   between     1–2 the first end, 3 middle, 4–5 the second end (끝맛의
 *               인상 lies between two characters and has no strength)
 *
 * Every answered step is kept, with the side it names and whether it was
 * liked or marked 아쉬웠어요. The middle step liked is liked as it was; the
 * middle step minded is a burden that names no direction; "none" liked or
 * minded is kept as said.
 *
 * An aroma is one line for each place it was picked (nose, mouth, after
 * swallowing). The lines are not merged, and nothing the reader did not say
 * is added.
 *
 * 다시 마시고 싶은지 never changes what an answer means, only how much it
 * weighs. The weights are provisional: they were set by hand, not counted.
 */
import type { AromaStage, GaugeAxis } from "../facts/facts.ts";
import type { SensoryRecord } from "../record/sensory_record.ts";

type Reaction = "liked" | "burden";
export type Revisit =
  | "want_again"
  | "would_accept_again"
  | "do_not_want_again"
  | "unknown";

export type GaugeScale = "strength" | "from_none" | "between";
export const GAUGE_SCALE: Readonly<Record<GaugeAxis, GaugeScale>> = {
  sweetness: "strength",
  acidity: "strength",
  umami: "strength",
  body: "strength",
  tannin: "strength",
  spice: "strength",
  sparkling: "from_none",
  peat: "from_none",
  finish_length: "strength",
  finish_character: "between",
};

/** The side a step names. On a `between` gauge low is its first end and high its second. */
export type GaugeSide = "none" | "low" | "middle" | "high";

export function gaugeSide(axis: GaugeAxis, level: number): GaugeSide {
  if (level === 1 && GAUGE_SCALE[axis] === "from_none") return "none";
  return level < 3 ? "low" : level > 3 ? "high" : "middle";
}

/** How much an answer weighs by the record's 다시 마시고 싶은지. */
export const REVISIT_WEIGHT: Readonly<
  Record<Revisit, Record<Reaction, number>>
> = {
  want_again: { liked: 1, burden: 0.7 },
  would_accept_again: { liked: 0.8, burden: 0.85 },
  do_not_want_again: { liked: 0.5, burden: 1 },
  unknown: { liked: 0.8, burden: 0.85 },
};

/** A record whose 다시 마시고 싶은지 is not one of the four weighs as 잘 모르겠어요. */
export function answerWeight(revisit: string, reaction: Reaction): number {
  return (REVISIT_WEIGHT[revisit as Revisit] ?? REVISIT_WEIGHT.unknown)[
    reaction
  ];
}

export type GaugeLine = {
  axis: GaugeAxis;
  scale: GaugeScale;
  /** The step as it was set, 1 to 5. */
  level: 1 | 2 | 3 | 4 | 5;
  side: GaugeSide;
  reaction: Reaction;
  weight: number;
  /** The option the reader chose. */
  answer_ref: string;
};

export type AromaLine = {
  stage: AromaStage;
  aroma: string;
  reaction: Reaction;
  weight: number;
  answer_ref: string;
};

/** 해석 결과: what one record's answers say. */
export type Interpretation = {
  revisit: Revisit;
  /** What a liked and a minded answer of this record weigh. */
  weight: Readonly<Record<Reaction, number>>;
  /** One line per answered gauge, in the order of the axes. */
  gauges: readonly GaugeLine[];
  /** One line per aroma and place it was picked: nose, mouth, finish; by name within a place. */
  aromas: readonly AromaLine[];
};

/** Reads the answers of one record. Pure; the bottle is not looked at. */
export function interpretAnswers(
  record: Pick<SensoryRecord, "revisit" | "gauges" | "aromas">,
): Interpretation {
  const revisit = record.revisit.intent ?? "unknown";
  const weight = REVISIT_WEIGHT[revisit];
  return {
    revisit,
    weight,
    gauges: record.gauges.map(({ axis, level, reaction, answerRef }) => ({
      axis,
      scale: GAUGE_SCALE[axis],
      level,
      side: gaugeSide(axis, level),
      reaction,
      weight: weight[reaction],
      answer_ref: answerRef,
    })),
    aromas: record.aromas.map(({ stage, key, reaction, answerRef }) => ({
      stage,
      aroma: key,
      reaction,
      weight: weight[reaction],
      answer_ref: answerRef,
    })),
  };
}
