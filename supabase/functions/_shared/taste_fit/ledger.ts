/**
 * The reader's taste ledger: what each saved card says about where, among the
 * bottles of a kind, a sensation was welcome or a burden.
 *
 * Every answer about a sensation the catalog measures becomes one line: the
 * place the drunk bottle had on that dimension among its own kind
 * (kind_place.ts), which way the answer reaches from there, and how much it
 * weighs.
 *
 * - 좋았어요 reaches the way the answer named: "또렷해서" covers that place and
 *   everything stronger, "은은해서" that place and everything milder, and an
 *   answer without a reason the places near it.
 * - A burden closes the side it named: "너무 강해서" that place and stronger,
 *   "약해서" that place and weaker. When that side is nearly the whole kind,
 *   it closes only what lies clearly beyond the drunk bottle.
 * - A like weighs less the commoner the bottle's value is in its kind: nearly
 *   every red wine sits on sweetness 1, so enjoying one says little about
 *   sweetness. A burden keeps its weight whatever the value, because the
 *   reader met it and minded.
 * - 다시 마시고 싶은지 scales the record: a like from a drink the reader would
 *   not have again counts half, a burden from one they would have again a
 *   little less.
 *
 * Aromas are kept by family (the effect rows), together with every family
 * the reader has met in the kind, liked or not: a family never met is what
 * the judge calls unfamiliar.
 *
 * A card answered on the gauges (2026-11-16) is read from them instead:
 *
 * - A line is counted on the catalog's 1 to 5 numbers, from the drunk
 *   bottle's own number where the catalog read one, because that is the
 *   scale other bottles are read on; the reader's step stands in where it
 *   has none.
 * - A liked step is a preferred range of one step either side of it.
 * - A step marked 아쉬웠어요 closes a side by the step felt: 4–5 was too much
 *   (that number and higher), 1–2 too little (that number and lower), the
 *   middle only that number.
 * - 피트 and 스파이시 have no number in the catalog. They are kept as whether
 *   the reader wants the aroma in a bottle or not (TagLine).
 * - An aroma keeps where it was picked (nose, mouth, after swallowing), and
 *   one aroma picked in several places is one line.
 *
 * Lines carry the group of kinds they were drunk in (와인, 위스키, 탁주 …); the
 * judge only compares inside a group.
 */
import {
  type AromaStage,
  CARD_FACTS_SCHEMA_VERSION,
  type CardFacts,
  GAUGE_LEVEL_DIMENSION,
  type GaugeFact,
  type LegacyCardFacts,
  type LegacyReactionFact,
  type StoredCardFacts,
} from "../taste_card/facts/facts.ts";
import {
  type AromaFamily,
  familiesOfAroma,
  familiesOfBottle,
  kindGroup,
  type Place,
  type PlaceAxis,
  type PlaceDimension,
  placeOfAbv,
  placeOfLevel,
  placeOfSweetness,
} from "../taste_card/facts/kind_place.ts";

/** Which places an answer speaks for, seen from the drunk bottle's place. */
type Reach = "near" | "up" | "down";

export type AxisLine = {
  axis: PlaceAxis;
  side: "like" | "burden";
  reach: Reach;
  /** Where the drunk bottle stands among its kind (Place.standing), 0 to 1. */
  position: number;
  /** The drunk bottle's number on the 1 to 5 scale (Place.level); absent where the reader's own word moved the line off the stored number. */
  level?: number;
  weight: number;
  /** A burden's side holds most of the kind (kind-wide), so it cannot tell the kind's bottles apart at the drunk bottle's own place. */
  kindWide?: true;
  /**
   * A gauge step, held on the catalog's numbers and not on a distance among
   * the kind: a like covers the numbers next to `level`, a burden the side it
   * named from `level` on.
   */
  byStep?: true;
};

export type FamilyLine = {
  family: AromaFamily;
  side: "like" | "burden";
  weight: number;
  /** Where the aroma was picked. Absent on a card from before the three pickers, which is held against the bottle's nose. */
  stages?: readonly AromaStage[];
};

/**
 * A 피트 or 스파이시 gauge, held against whether a bottle carries the aroma at
 * all. A liked 4–5 wants it there and a liked 1–2 wants it away; a 4–5 marked
 * 아쉬웠어요 wants it away as a burden. The middle step, and too little of it,
 * ask for nothing a tag can show.
 */
export type TagLine = {
  tag: "peat" | "spice";
  wants: "present" | "absent";
  side: "like" | "burden";
  weight: number;
};

export type GroupLedger = {
  /** The group's name as the reader would say it: 위스키, 와인, 탁주. */
  name: string;
  axes: AxisLine[];
  families: FamilyLine[];
  tags: TagLine[];
  /** Every aroma family the reader's bottles of this group carried or the reader named. */
  met: Set<AromaFamily>;
};

/** One ledger per group of kinds the reader has a record in. */
export type Ledger = Map<string, GroupLedger>;

/** Reaction subject → the axis it is read on, and whether the sensation is the axis's low end. */
const AXIS_OF: Readonly<
  Record<string, { axis: PlaceAxis; lowEnd?: true; reaches?: Reach }>
> = {
  sweetness: { axis: "sweetness" },
  acidity: { axis: "acidity" },
  bitterness: { axis: "bitterness" },
  drying: { axis: "astringency" },
  smooth: { axis: "astringency", lowEnd: true },
  heavy: { axis: "body", reaches: "up" },
  light: { axis: "body", lowEnd: true },
  bubbles: { axis: "carbonation" },
  warmth: { axis: "alcohol" },
  persistence: { axis: "finish_length", reaches: "up" },
  clean: { axis: "finish_cleanliness", reaches: "up" },
};

type LegacyQualifier = LegacyReactionFact["qualifier"];
const WEAK: readonly LegacyQualifier[] = ["too_weak", "too_brief"];
const STRONGER: readonly LegacyQualifier[] = ["pronounced", "lingering"];
const MILDER: readonly LegacyQualifier[] = ["gentle", "quick_clearing"];

const LIKE_BY_REVISIT: Readonly<Record<string, number>> = {
  want_again: 1,
  would_accept_again: 0.8,
  do_not_want_again: 0.5,
  unknown: 0.8,
};
const BURDEN_BY_REVISIT: Readonly<Record<string, number>> = {
  want_again: 0.7,
  would_accept_again: 0.85,
  do_not_want_again: 1,
  unknown: 0.85,
};
/**
 * A burden whose side holds this much of the kind is about the kind itself
 * (a 40% whisky felt hot, and no whisky is weaker): it then speaks only for
 * bottles clearly beyond the drunk one, or every bottle of the kind would
 * read the same.
 */
const KIND_WIDE = 0.8;

const flip = (reach: Reach): Reach =>
  reach === "up" ? "down" : reach === "down" ? "up" : "near";

/** The bottle a card was written about, as the place reader takes it. */
function cardBottle(card: StoredCardFacts) {
  const levels: Record<string, number> = {};
  const aromas: string[] = [];
  const processes: string[] = [];
  let abv: number | null = null;
  for (const { fact } of card.product_facts) {
    // A kind's usual value copied into the bottle is not a reading of it.
    if (fact.type === "level" && !fact.estimated) {
      levels[fact.dimension] = fact.level;
    } else if (fact.type === "descriptor" && fact.section === "aroma") {
      aromas.push(fact.key);
    } else if (fact.type === "production") processes.push(fact.key);
    else if (fact.type === "abv") abv = fact.value;
  }
  return {
    style_key: card.record.style_key,
    category_key: card.record.category,
    abv_percent: abv,
    levels,
    aroma_tags: aromas,
    production_process_keys: processes,
  };
}

/**
 * A burden on the side it named, seen from the drunk bottle's place. One
 * without a side speaks for that place alone, and makes no line where most of
 * the kind shares it.
 */
function burdenLine(
  axis: PlaceAxis,
  reach: Reach,
  place: Place,
  revisit: string,
): AxisLine | null {
  const held = reach === "up"
    ? 1 - (place.position - place.share / 2)
    : reach === "down"
    ? place.position + place.share / 2
    : place.share;
  if (reach === "near" && held >= KIND_WIDE) return null;
  return {
    axis,
    side: "burden",
    reach,
    position: place.standing,
    ...(place.level === null ? {} : { level: place.level }),
    weight: BURDEN_BY_REVISIT[revisit] ?? 0.85,
    ...(held >= KIND_WIDE ? { kindWide: true as const } : {}),
  };
}

/** A line from an answer of a card stored before the gauges. */
function axisLine(
  reaction: LegacyReactionFact,
  bottle: ReturnType<typeof cardBottle>,
  revisit: string,
): AxisLine | null {
  const read = AXIS_OF[reaction.subject.key];
  // Only a liked or a minded answer makes a line.
  if (
    !read || (reaction.reaction !== "liked" && reaction.reaction !== "burden")
  ) return null;
  const { axis } = read;
  const place = axis === "alcohol"
    ? placeOfAbv(bottle.style_key, bottle.category_key, bottle.abv_percent)
    : axis === "sweetness"
    ? placeOfSweetness(bottle)
    : bottle.levels[axis] === undefined
    ? null
    : placeOfLevel(
      axis,
      bottle.style_key,
      bottle.category_key,
      bottle.levels[axis],
    );
  if (!place) return null;
  const q = reaction.qualifier;
  if (reaction.reaction === "burden") {
    // The sensation was too much unless the answer says it fell short.
    const sensation: Reach = WEAK.includes(q) ? "down" : "up";
    const reach = read.lowEnd ? flip(sensation) : sensation;
    return burdenLine(axis, reach, place, revisit);
  }
  const sensation: Reach = STRONGER.includes(q)
    ? "up"
    : MILDER.includes(q)
    ? "down"
    : read.lowEnd
    ? "up"
    : read.reaches ?? "near";
  const reach = read.lowEnd ? flip(sensation) : sensation;
  // The reader's own word for the strength outranks the stored number: what
  // they called 또렷하다 is read no lower than the kind's middle, what they
  // called 은은하다 no higher.
  const position = q === null
    ? place.standing
    : reach === "up" && STRONGER.includes(q)
    ? Math.max(place.standing, 0.5)
    : reach === "down" && MILDER.includes(q)
    ? Math.min(place.standing, 0.5)
    : place.standing;
  return {
    axis,
    side: "like",
    reach,
    position,
    ...(place.level === null || position !== place.standing
      ? {}
      : { level: place.level }),
    weight: (1 - place.share) * (LIKE_BY_REVISIT[revisit] ?? 0.8),
  };
}

/** A line from a gauge the catalog has a level for. */
function gaugeLine(
  gauge: GaugeFact,
  bottle: ReturnType<typeof cardBottle>,
  revisit: string,
): AxisLine | null {
  const axis = GAUGE_LEVEL_DIMENSION[gauge.axis] as PlaceDimension | null;
  if (!axis) return null;
  // The bottle's own number where the catalog read one, else the step felt.
  const level = bottle.levels[axis] ?? gauge.level;
  const place = placeOfLevel(
    axis,
    bottle.style_key,
    bottle.category_key,
    level,
  );
  if (!place) return null;
  if (gauge.reaction === "liked") {
    return {
      axis,
      side: "like",
      reach: "near",
      position: place.standing,
      level,
      weight: (1 - place.share) * (LIKE_BY_REVISIT[revisit] ?? 0.8),
      byStep: true,
    };
  }
  const reach = gauge.level > 3 ? "up" : gauge.level < 3 ? "down" : "near";
  const line = burdenLine(axis, reach, place, revisit);
  return line && { ...line, byStep: true };
}

function tagLine(gauge: GaugeFact, revisit: string): TagLine | null {
  if ((gauge.axis !== "peat" && gauge.axis !== "spice") || gauge.level === 3) {
    return null;
  }
  const strong = gauge.level > 3;
  if (gauge.reaction === "liked") {
    return {
      tag: gauge.axis,
      wants: strong ? "present" : "absent",
      side: "like",
      weight: LIKE_BY_REVISIT[revisit] ?? 0.8,
    };
  }
  return strong
    ? {
      tag: gauge.axis,
      wants: "absent",
      side: "burden",
      weight: BURDEN_BY_REVISIT[revisit] ?? 0.85,
    }
    : null;
}

function readLegacyCard(
  mine: GroupLedger,
  card: LegacyCardFacts,
  bottle: ReturnType<typeof cardBottle>,
) {
  const revisit = card.record.revisit;
  for (const reaction of card.reactions) {
    if (reaction.subject.domain === "aroma") {
      for (const family of familiesOfAroma(reaction.subject.key)) {
        mine.met.add(family);
        if (reaction.reaction === "liked") {
          mine.families.push({
            family,
            side: "like",
            weight: LIKE_BY_REVISIT[revisit] ?? 0.8,
          });
        } else if (reaction.reaction === "burden") {
          mine.families.push({
            family,
            side: "burden",
            weight: BURDEN_BY_REVISIT[revisit] ?? 0.85,
          });
        }
      }
      continue;
    }
    const line = axisLine(reaction, bottle, revisit);
    if (line) mine.axes.push(line);
  }
}

function readGaugeCard(
  mine: GroupLedger,
  card: CardFacts,
  bottle: ReturnType<typeof cardBottle>,
) {
  const revisit = card.record.revisit;
  for (const gauge of card.gauges) {
    const line = gaugeLine(gauge, bottle, revisit);
    if (line) mine.axes.push(line);
    const tag = tagLine(gauge, revisit);
    if (tag) mine.tags.push(tag);
  }
  // One aroma taken one way is one line, wherever it was picked: the card
  // keeps the finish apart from the nose and the mouth.
  const picked = new Map<
    string,
    { key: string; side: "like" | "burden"; stages: Set<AromaStage> }
  >();
  for (const reaction of card.reactions) {
    if (reaction.subject.domain !== "aroma") continue;
    const { key } = reaction.subject;
    for (const family of familiesOfAroma(key)) mine.met.add(family);
    // Named by the 피트 gauge alone: met, and read as a tag line above.
    if (!reaction.stages?.length) continue;
    const id = `${key}:${reaction.reaction}`;
    const same = picked.get(id) ?? {
      key,
      side: reaction.reaction === "liked" ? "like" : "burden",
      stages: new Set(),
    };
    for (const stage of reaction.stages) same.stages.add(stage);
    picked.set(id, same);
  }
  for (const { key, side, stages } of picked.values()) {
    for (const family of familiesOfAroma(key)) {
      mine.families.push({
        family,
        side,
        weight: side === "like"
          ? LIKE_BY_REVISIT[revisit] ?? 0.8
          : BURDEN_BY_REVISIT[revisit] ?? 0.85,
        stages: [...stages],
      });
    }
  }
}

export function buildLedger(cards: readonly StoredCardFacts[]): Ledger {
  const ledger: Ledger = new Map();
  for (const card of cards) {
    const group = kindGroup(card.record.style_key, card.record.category);
    if (!group) continue;
    if (!ledger.has(group.key)) {
      ledger.set(group.key, {
        name: group.name,
        axes: [],
        families: [],
        tags: [],
        met: new Set(),
      });
    }
    const mine = ledger.get(group.key)!;
    const bottle = cardBottle(card);
    for (
      const family of familiesOfBottle(
        bottle.aroma_tags,
        bottle.production_process_keys,
      )
    ) mine.met.add(family);
    if (card.schema_version === CARD_FACTS_SCHEMA_VERSION) {
      readGaugeCard(mine, card, bottle);
    } else readLegacyCard(mine, card, bottle);
  }
  return ledger;
}
