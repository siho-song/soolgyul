/**
 * A still wine's sweetness for the old stages: the reading of
 * facts/wine_sweetness.ts taken from the card's product facts, with the
 * facts each part of it stands on.
 */
import type { CardFacts, Condition } from "../facts/facts.ts";
import {
  raisedBy,
  readWineSweetness as readBottle,
  type Standing,
  WINE_LEVELS,
  type WineLevel,
  type WineSweetness as Reading,
} from "../facts/wine_sweetness.ts";

export { raisedBy, readsSweet } from "../facts/wine_sweetness.ts";

export type WineSweetness = Reading & {
  /** The product facts behind the bottle's aromas and each level read. */
  found: {
    aromas: ReadonlyMap<string, string>;
    levels: Readonly<Partial<Record<WineLevel, string>>>;
  };
};

/** The reading of a still wine's card, or null for any other drink. */
export function readWineSweetness(
  facts: Pick<CardFacts, "record" | "product_facts">,
): WineSweetness | null {
  const levels: Partial<Record<WineLevel, number>> = {};
  const ids: Partial<Record<WineLevel, string>> = {};
  const aromas = new Map<string, string>();
  for (const { id, fact } of facts.product_facts) {
    if (fact.type === "level" && !fact.estimated) {
      const key = fact.dimension as WineLevel;
      if (WINE_LEVELS.includes(key)) {
        levels[key] = fact.level;
        ids[key] = id;
      }
    } else if (fact.type === "descriptor" && fact.section === "aroma") {
      aromas.set(fact.key, id);
    }
  }
  const reading = readBottle({
    style_key: facts.record.style_key,
    category: facts.record.category,
    levels,
    aromas: [...aromas.keys()],
  });
  return reading && { ...reading, found: { aromas, levels: ids } };
}

/** A sentence names two aromas at most. */
const MAX_AROMAS = 2;

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
    const id = wine.found.levels[dimension];
    if (id) ids.push(id);
    given.push({ type: "level", dimension, is });
  };
  for (const cause of raisedBy(wine)) {
    if (cause === "aroma") {
      for (const key of wine.sweetAromas.slice(0, MAX_AROMAS)) {
        ids.push(wine.found.aromas.get(key)!);
        given.push({ type: "descriptor", key, is: "present" });
      }
    } else if (cause === "soft_tannin") level("astringency", "low");
    else if (cause === "low_acidity") level("acidity", "low");
    else level("body", "high");
  }
  return { ids, given };
}
