/**
 * How a still wine's sweetness reads on its card.
 *
 * A sweetness mark says where a wine stands among wines of its own kind, not
 * how sweet it is on an absolute scale: 93 of 100 red wines carry sweetness
 * 1. So every card sentence about a still wine's sweetness is checked here,
 * against the bottle's places within its kind (facts/kind_place.ts), and the
 * reasons a card gives for a wine feeling sweeter or drier are the bottle's
 * own traits: aromas that raise the sweetness a drinker expects, and tannin,
 * acidity and body standing high or low among the kind.
 *
 * Only levels read for this bottle count; a number copied from the kind's
 * table says nothing about where the bottle stands in the kind.
 */
import type { CardFacts, Condition } from "../facts/facts.ts";
import {
  hasFeltSweetness,
  tanninShapesSweetness,
} from "../facts/felt_sweetness.ts";
import {
  type Place,
  placeOfLevel,
  placeOfSweetness,
} from "../facts/kind_place.ts";
import { effectRow } from "./knowledge.ts";

export type Standing = "low" | "mid" | "high";

/** The aroma families that raise the sweetness a drinker expects. */
const SWEET_LEANING_ROWS: ReadonlySet<string> = new Set([
  "effect_ripe_fruit",
  "effect_sweet_scent",
]);

export type WineSweetness = {
  /** The kind, pool or category the bottle's levels were placed among. */
  scope: string | null;
  /** Where the stored sweetness mark stands among the kind's marks. */
  stored: Standing | null;
  /** Where the wine stands by how sweet it feels (facts/felt_sweetness.ts). */
  felt: Standing | null;
  /** The kind's tannin takes part in how sweet it feels (red, orange). */
  tannic: boolean;
  /** null where tannin does not take part, or was not read for the bottle. */
  tannin: Standing | null;
  acidity: Standing | null;
  body: Standing | null;
  /** The bottle's ripe-fruit and sweet-scent aromas. */
  sweetAromas: readonly { key: string; id: string }[];
  /** The product facts behind each level read. */
  ids: Readonly<Partial<Record<LevelKey, string>>>;
};

type LevelKey = "sweetness" | "astringency" | "acidity" | "body";

const third = (position: number): Standing =>
  position < 1 / 3 ? "low" : position > 2 / 3 ? "high" : "mid";

/**
 * Where a level stands among the kind. High is the upper third, as the fit
 * check reads it. Low is the lower third and, besides, a value the kind's
 * middle bottle sits above: acidity 3 is the middle of red wines, and half of
 * them share it, so it is never called low.
 */
function standing(place: Place | null): Standing | null {
  if (!place) return null;
  if (place.position > 2 / 3) return "high";
  const middleIsAbove = place.position + place.share / 2 <= 0.5;
  return place.position < 1 / 3 && middleIsAbove ? "low" : "mid";
}

/** The reading of a still wine's card, or null for any other drink. */
export function readWineSweetness(
  facts: Pick<CardFacts, "record" | "product_facts">,
): WineSweetness | null {
  const { style_key: styleKey, category } = facts.record;
  if (!hasFeltSweetness(styleKey)) return null;
  const levels: Partial<Record<LevelKey, number>> = {};
  const ids: Partial<Record<LevelKey, string>> = {};
  const aromas: { key: string; id: string }[] = [];
  for (const { id, fact } of facts.product_facts) {
    if (fact.type === "level" && !fact.estimated) {
      const key = fact.dimension as LevelKey;
      if (["sweetness", "astringency", "acidity", "body"].includes(key)) {
        levels[key] = fact.level;
        ids[key] = id;
      }
    } else if (fact.type === "descriptor" && fact.section === "aroma") {
      aromas.push({ key: fact.key, id });
    }
  }
  const place = (dimension: Exclude<LevelKey, "sweetness">) =>
    levels[dimension] === undefined
      ? null
      : placeOfLevel(dimension, styleKey, category, levels[dimension]);
  const stored = levels.sweetness === undefined
    ? null
    : placeOfLevel("sweetness", styleKey, category, levels.sweetness);
  const felt = placeOfSweetness({
    style_key: styleKey,
    category_key: category,
    levels,
    aroma_tags: aromas.map((aroma) => aroma.key),
  });
  const acidity = place("acidity");
  const body = place("body");
  const tannic = tanninShapesSweetness(styleKey);
  const tannin = tannic ? place("astringency") : null;
  return {
    tannic,
    scope: (stored ?? acidity ?? tannin ?? body)?.scope ?? null,
    stored: stored && third(stored.position),
    felt: felt && third(felt.position),
    tannin: standing(tannin),
    acidity: standing(acidity),
    body: standing(body),
    sweetAromas: aromas.filter((aroma) =>
      SWEET_LEANING_ROWS.has(effectRow(aroma.key) ?? "")
    ),
    ids,
  };
}

/** A sentence names two aromas at most. */
const MAX_AROMAS = 2;

/** What makes the wine feel drier than its mark. */
export type DrierCause = "tannin" | "acidity";

export function drierCauses(wine: WineSweetness): DrierCause[] {
  const causes: DrierCause[] = [];
  if (wine.tannin === "high") causes.push("tannin");
  if (wine.acidity === "high") causes.push("acidity");
  return causes;
}

/** A red or orange wine whose tannin was not read: nothing can be said of its grip. */
export const tanninUnread = (wine: WineSweetness) =>
  wine.tannic && wine.tannin === null;

/** What makes the wine feel sweeter than its mark. */
export type SweeterCause = "aroma" | "soft_tannin" | "low_acidity" | "body";

/**
 * The causes one explanation names: the aromas with whatever is soft beside
 * them, else what is soft, else a full body alone. Soft tannin, low acidity
 * and a full body explain nothing while tannin or acidity stands high and
 * pulls the wine dry, nor on a red whose tannin nobody read, so there only
 * the aromas are named. Empty when the bottle has none, and then the card
 * says nothing rather than invent a reason.
 */
export function raisedBy(wine: WineSweetness): SweeterCause[] {
  const aroma: SweeterCause[] = wine.sweetAromas.length ? ["aroma"] : [];
  if (drierCauses(wine).length || tanninUnread(wine)) return aroma;
  const soft: SweeterCause[] = [
    ...(wine.tannin === "low" ? ["soft_tannin" as const] : []),
    ...(wine.acidity === "low" ? ["low_acidity" as const] : []),
  ];
  if (aroma.length || soft.length) return [...aroma, ...soft];
  return wine.body === "high" ? ["body"] : [];
}

/**
 * True when no sentence may call the wine's sweetness little: its mark stands
 * high among the kind, or it feels sweeter than two thirds of the kind for
 * reasons the card can name while neither its tannin nor its acidity stands
 * high (a tannic, brisk red with cherry and vanilla is still a dry wine).
 */
export function readsSweet(wine: WineSweetness): boolean {
  return wine.stored === "high" ||
    (wine.felt === "high" && raisedBy(wine).length > 0 &&
      drierCauses(wine).length === 0);
}

/** The product facts and conditions the named causes stand on, for a finding. */
export function raisedEvidence(
  wine: WineSweetness,
): { ids: string[]; given: Condition[] } {
  const ids: string[] = [];
  const given: Condition[] = [];
  const level = (
    dimension: "astringency" | "acidity" | "body",
    is: Standing,
  ) => {
    if (wine.ids[dimension]) ids.push(wine.ids[dimension]);
    given.push({ type: "level", dimension, is });
  };
  for (const cause of raisedBy(wine)) {
    if (cause === "aroma") {
      for (const aroma of wine.sweetAromas.slice(0, MAX_AROMAS)) {
        ids.push(aroma.id);
        given.push({ type: "descriptor", key: aroma.key, is: "present" });
      }
    } else if (cause === "soft_tannin") level("astringency", "low");
    else if (cause === "low_acidity") level("acidity", "low");
    else level("body", "high");
  }
  return { ids, given };
}
