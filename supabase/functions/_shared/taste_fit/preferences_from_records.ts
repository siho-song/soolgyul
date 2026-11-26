/**
 * What a reader's records say they like and mind, kind by kind, for 나에게
 * 맞는 술 찾기: every record's answers read against the bottle it was said
 * about.
 *
 * - A gauge the catalog has a number for (단맛, 산미, 바디, 타닌, 탄산, 여운의
 *   길이) becomes one line on the catalog's 1 to 5 numbers, counted from the
 *   drunk bottle's own number where the catalog read one, because that is the
 *   scale other bottles are read on; the reader's step stands in where it has
 *   none.
 * - A liked step is a preferred range of one step either side of it.
 * - A step marked 아쉬웠어요 closes a side by the step felt: 4–5 was too much
 *   (that number and higher), 1–2 too little (that number and lower), the
 *   middle only that number. When that side holds nearly the whole kind, it
 *   closes only what lies clearly beyond the drunk bottle.
 * - A like weighs less the commoner the bottle's value is in its kind: nearly
 *   every red wine sits on sweetness 1, so enjoying one says little about
 *   sweetness. A burden keeps its weight whatever the value, because the
 *   reader met it and minded.
 * - 다시 마시고 싶은지 scales the record: a like from a drink the reader would
 *   not have again counts half, a burden from one they would have again a
 *   little less.
 * - 피트 and 스파이시 have no number in the catalog. They are kept as whether
 *   the reader wants the aroma in a bottle or not.
 * - Aromas are kept by family (what the aroma does, aroma_effects.ts) with
 *   where each was picked (nose, mouth, after swallowing), together with
 *   every family the reader has met in the kind, liked or not: a family never
 *   met is what the verdict calls unfamiliar.
 *
 * Preferences carry the group of kinds they were drunk in (와인, 위스키, 탁주
 * …); a bottle is only held against the preferences of its own group.
 */
import { GAUGE_LEVEL_DIMENSION } from "../record_reading/facts/facts.ts";
import {
  type AromaFamily,
  familiesOfAroma,
  familiesOfBottle,
  kindGroup,
  type Place,
  type PlaceAxis,
  type PlaceDimension,
  placeOfLevel,
} from "../record_reading/facts/kind_place.ts";
import type { BottleFacts } from "../record_reading/bottle.ts";
import {
  type Answers,
  answerWeight,
  type GaugeLine,
} from "../record_reading/answers.ts";

/** What the preferences are read from: the answers of one record and its bottle. */
export type RecordForFit = {
  answers: Pick<Answers, "revisit" | "gauges" | "aromas">;
  bottle: Pick<
    BottleFacts,
    "category" | "style_key" | "region_entry" | "levels" | "tags" | "processes"
  >;
};

/** Which places an answer speaks for, seen from the drunk bottle's place. */
type Reach = "near" | "up" | "down";

/** A like or a burden on one taste (단맛, 바디 …), at the drunk bottle's place. */
export type TastePreference = {
  axis: PlaceAxis;
  side: "like" | "burden";
  reach: Reach;
  /**
   * The drunk bottle's number on the catalog's 1 to 5 scale, or the step felt
   * where the catalog read none. A like covers the numbers next to it, a
   * burden the side it named from it on.
   */
  level: number;
  weight: number;
  /** A burden's side holds most of the kind (kind-wide), so it cannot tell the kind's bottles apart at the drunk bottle's own place. */
  kindWide?: true;
};

/** A like or a burden on one aroma family. */
export type AromaPreference = {
  family: AromaFamily;
  side: "like" | "burden";
  weight: number;
};

/**
 * A 피트 or 스파이시 gauge, held against whether a bottle carries the aroma at
 * all. A liked 4–5 wants it there and a liked 1–2 wants it away; a 4–5 marked
 * 아쉬웠어요 wants it away as a burden. The middle step, and too little of it,
 * ask for nothing a tag can show.
 */
export type PeatSpicePreference = {
  tag: "peat" | "spice";
  wants: "present" | "absent";
  side: "like" | "burden";
  weight: number;
};

/** The preferences in one group of kinds. */
export type KindPreferences = {
  /** The group's name as the reader would say it: 위스키, 와인, 탁주. */
  name: string;
  tastes: TastePreference[];
  aromas: AromaPreference[];
  peat_spice: PeatSpicePreference[];
  /** Every aroma family the reader's bottles of this group carried or the reader named. */
  met: Set<AromaFamily>;
};

/** The preferences of every group of kinds the reader has a record in, by the group's key. */
export type Preferences = Map<string, KindPreferences>;

/**
 * A burden whose side holds this much of the kind is about the kind itself
 * (nearly every red wine is dry, and one was too dry): it then speaks only
 * for bottles clearly beyond the drunk one, or every bottle of the kind would
 * read the same.
 */
const KIND_WIDE = 0.8;

/** The bottle a record was about, as the kind counts take it. */
function bottleOf({ bottle }: RecordForFit) {
  return {
    // A wine of a place the dictionary knows is counted among that place's wines.
    style_key: bottle.region_entry ?? bottle.style_key,
    category_key: bottle.category,
    // A kind's usual value copied into the bottle is not a reading of it.
    levels: Object.fromEntries(
      Object.entries(bottle.levels).flatMap(([name, read]) =>
        read.of === "bottle" ? [[name, read.level]] : []
      ),
    ) as Record<string, number>,
    aroma_tags: [
      ...new Set(
        bottle.tags.filter((tag) => tag.section === "aroma").map((tag) =>
          tag.key
        ),
      ),
    ].sort(),
    production_process_keys: bottle.processes,
  };
}

/**
 * A burden on the side it named, seen from the drunk bottle's place. One
 * without a side speaks for that place alone, and makes no line where most of
 * the kind shares it.
 */
function burdenOn(
  axis: PlaceAxis,
  reach: Reach,
  level: number,
  place: Place,
  revisit: string,
): TastePreference | null {
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
    level,
    weight: answerWeight(revisit, "burden"),
    ...(held >= KIND_WIDE ? { kindWide: true as const } : {}),
  };
}

/** The preference a gauge the catalog has a level for says. */
function tastePreference(
  gauge: GaugeLine,
  bottle: ReturnType<typeof bottleOf>,
  revisit: string,
): TastePreference | null {
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
      level,
      weight: (1 - place.share) * (answerWeight(revisit, "liked")),
    };
  }
  const reach = gauge.level > 3 ? "up" : gauge.level < 3 ? "down" : "near";
  return burdenOn(axis, reach, level, place, revisit);
}

function peatSpicePreference(
  gauge: GaugeLine,
  revisit: string,
): PeatSpicePreference | null {
  if ((gauge.axis !== "peat" && gauge.axis !== "spice") || gauge.level === 3) {
    return null;
  }
  const strong = gauge.level > 3;
  if (gauge.reaction === "liked") {
    return {
      tag: gauge.axis,
      wants: strong ? "present" : "absent",
      side: "like",
      weight: answerWeight(revisit, "liked"),
    };
  }
  return strong
    ? {
      tag: gauge.axis,
      wants: "absent",
      side: "burden",
      weight: answerWeight(revisit, "burden"),
    }
    : null;
}

type Picked = {
  aroma: string;
  reaction: "liked" | "burden";
  /** Named by the 피트 gauge, not picked as an aroma. */
  byGauge?: true;
};
const byName = (a: Picked, b: Picked) =>
  a.aroma.localeCompare(b.aroma) ||
  // A liked answer before the minded one of the same aroma.
  b.reaction.localeCompare(a.reaction);

/**
 * The aromas a record names, each taken one way once, at whichever moment it
 * was picked. A 피트 gauge that says there was some names the 피트 aroma.
 */
function aromasNamed(answers: RecordForFit["answers"]): Picked[] {
  const found: Picked[] = [];
  const has = (aroma: string, reaction: Picked["reaction"]) =>
    found.some((p) => p.aroma === aroma && p.reaction === reaction);
  for (const line of answers.aromas) {
    if (!has(line.aroma, line.reaction)) {
      found.push({ aroma: line.aroma, reaction: line.reaction });
    }
  }
  const peat = answers.gauges.find((gauge) => gauge.axis === "peat");
  if (peat && peat.side !== "none" && !has("peat", peat.reaction)) {
    found.push({ aroma: "peat", reaction: peat.reaction, byGauge: true });
  }
  return found.sort(byName);
}

function readRecord(mine: KindPreferences, record: RecordForFit) {
  const { answers } = record;
  const bottle = bottleOf(record);
  for (
    const family of familiesOfBottle(
      bottle.aroma_tags,
      bottle.production_process_keys,
    )
  ) mine.met.add(family);
  for (const gauge of answers.gauges) {
    const taste = tastePreference(gauge, bottle, answers.revisit);
    if (taste) mine.tastes.push(taste);
    const peatSpice = peatSpicePreference(gauge, answers.revisit);
    if (peatSpice) mine.peat_spice.push(peatSpice);
  }
  // One aroma taken one way is one preference, wherever it was picked.
  for (const { aroma, reaction, byGauge } of aromasNamed(answers)) {
    for (const family of familiesOfAroma(aroma)) mine.met.add(family);
    // Named by the 피트 gauge alone: met, and kept as a peat preference above.
    if (byGauge) continue;
    for (const family of familiesOfAroma(aroma)) {
      mine.aromas.push({
        family,
        side: reaction === "liked" ? "like" : "burden",
        weight: answerWeight(answers.revisit, reaction),
      });
    }
  }
}

/** What the reader's records say, by the group of kinds each was drunk in. */
export function preferencesFromRecords(
  records: readonly RecordForFit[],
): Preferences {
  const preferences: Preferences = new Map();
  for (const record of records) {
    const { bottle } = record;
    const group = kindGroup(
      bottle.region_entry ?? bottle.style_key,
      bottle.category,
    );
    if (!group) continue;
    if (!preferences.has(group.key)) {
      preferences.set(group.key, {
        name: group.name,
        tastes: [],
        aromas: [],
        peat_spice: [],
        met: new Set(),
      });
    }
    readRecord(preferences.get(group.key)!, record);
  }
  return preferences;
}
