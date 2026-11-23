/**
 * 나의 용어 사전: the explanations a reader saved from a help balloon. A save
 * keeps only the term's dictionary key; its name, kind, drinks and
 * explanation are read from the dictionary when the list is served, so a
 * saved term always reads as the dictionary stands.
 */
import type { Term } from "../record_reading/dictionary/dictionary.ts";
import {
  savedTermHelp,
  type TermHelp,
} from "../record_reading/dictionary/term_help.ts";

export type GlossaryTerm = Required<TermHelp> & {
  /**
   * The drinks the term belongs to, for the list's filter: `common` alone
   * for a term of every drink, else some of wine, whisky, sake and
   * korean_traditional. Empty when the dictionary does not say.
   */
  categories: string[];
};

export const COMMON = "common";
const DRINKS = ["wine", "whisky", "sake", "korean_traditional"] as const;

/** Sensations are tasted in every drink. */
const SENSED: ReadonlySet<string> = new Set([
  "axis",
  "aroma",
  "aroma_family",
  "texture",
]);
/** The dictionary's makers are filed by what they make. */
const PRODUCER_DRINK: Readonly<Record<string, string>> = {
  distillery: "whisky",
  blend_brand: "whisky",
};

function categoriesOf(term: Term): string[] {
  if (SENSED.has(term.type)) return [COMMON];
  if (term.type === "producer") {
    const drink = PRODUCER_DRINK[term.house ?? ""];
    return drink ? [drink] : [];
  }
  const named = new Set(term.categories ?? []);
  const drinks = DRINKS.filter((drink) => named.has(drink));
  return drinks.length === DRINKS.length ? [COMMON] : drinks;
}

/** The term a saved key names, or null when it cannot be saved. */
export function glossaryTerm(key: string): GlossaryTerm | null {
  const found = savedTermHelp(key);
  return found ? { ...found.help, categories: categoriesOf(found.term) } : null;
}
