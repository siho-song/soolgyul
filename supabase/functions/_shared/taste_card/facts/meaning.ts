/**
 * 해석: what the answers of one record say, read once for every part that
 * reads answers (the card, the taste letters, the fit, the guide).
 *
 * Only the reader's answers are read. Nothing of the bottle enters here (its
 * levels, tags or facts): an answer is not held against the catalog, and what
 * the bottle is belongs to the part that explains or compares.
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
 * swallowing). The lines are not merged here; a reader that counts a liking
 * counts one aroma once (aromasOnce).
 *
 * 다시 마시고 싶은지 never changes what an answer means, only how much it
 * weighs. The weights are provisional: they were set by hand, not counted.
 */
import {
  AROMA_STAGES,
  type AromaStage,
  type CardFacts,
  type GaugeAxis,
} from "./facts.ts";

type Reaction = "liked" | "burden";
export type Revisit = CardFacts["record"]["revisit"];

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
};

export type AromaLine = {
  stage: AromaStage;
  aroma: string;
  reaction: Reaction;
  weight: number;
};

export type AnswerMeaning = {
  /** null when the reader named the drink without saying what kind it is. */
  category: string | null;
  style_key: string | null;
  revisit: Revisit;
  /** What a liked and a minded answer of this record weigh. */
  weight: Readonly<Record<Reaction, number>>;
  /** One line per answered gauge, in the order of the card. */
  gauges: readonly GaugeLine[];
  /** One line per aroma and place it was picked: nose, mouth, finish; by name within a place. */
  aromas: readonly AromaLine[];
};

/** What a card answered on the gauges says. */
export function readMeaning(
  card: Pick<CardFacts, "record" | "gauges" | "reactions">,
): AnswerMeaning {
  const { category, style_key, revisit } = card.record;
  const weight = REVISIT_WEIGHT[revisit] ?? REVISIT_WEIGHT.unknown;
  const aromas: AromaLine[] = [];
  for (const { subject, reaction, stages } of card.reactions) {
    // An aroma reaction without a place is the 피트 gauge, read as a gauge.
    if (subject.domain !== "aroma") continue;
    for (const stage of stages ?? []) {
      aromas.push({
        stage,
        aroma: subject.key,
        reaction,
        weight: weight[reaction],
      });
    }
  }
  aromas.sort((a, b) =>
    AROMA_STAGES.indexOf(a.stage) - AROMA_STAGES.indexOf(b.stage) ||
    a.aroma.localeCompare(b.aroma)
  );
  return {
    category,
    style_key,
    revisit,
    weight,
    gauges: card.gauges.map(({ axis, level, reaction }) => ({
      axis,
      scale: GAUGE_SCALE[axis],
      level,
      side: gaugeSide(axis, level),
      reaction,
      weight: weight[reaction],
    })),
    aromas,
  };
}

/**
 * Each aroma once for each way it was taken, with every place it was picked:
 * 오크 liked by the nose and in the mouth is one liking of 오크, and 오크 liked
 * by the nose but minded after swallowing is one liking and one burden.
 */
export function aromasOnce(
  aromas: readonly AromaLine[],
): {
  aroma: string;
  reaction: Reaction;
  weight: number;
  stages: AromaStage[];
}[] {
  const once = new Map<
    string,
    { aroma: string; reaction: Reaction; weight: number; stages: AromaStage[] }
  >();
  for (const { aroma, reaction, weight, stage } of aromas) {
    const id = `${aroma}:${reaction}`;
    const same = once.get(id) ?? { aroma, reaction, weight, stages: [] };
    if (!same.stages.includes(stage)) same.stages.push(stage);
    once.set(id, same);
  }
  return [...once.values()];
}
