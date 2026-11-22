/**
 * 나의 용어 사전: the explanations a reader saved from a help balloon. A save
 * keeps only the term's dictionary key; its name, kind, drinks and
 * explanation are read from the dictionary when the list is served, so a
 * saved term always reads as the dictionary stands.
 */
import { type Term, terms } from "../taste_card/dictionary/dictionary.ts";
import {
  sensationKind,
  termKey,
  wordKind,
} from "../taste_card/writing/terms.ts";

export type GlossaryTerm = {
  key: string;
  /** The dictionary's name: 체리, 셰리 캐스크, 스페이사이드. */
  label: string;
  /** 향, 맛, 질감, 여운, 제조·숙성, 품종, 산지, 생산자. */
  kind: string;
  /**
   * The drinks the term belongs to, for the list's filter: `common` alone
   * for a term of every drink, else some of wine, whisky, sake and
   * korean_traditional. Empty when the dictionary does not say.
   */
  categories: string[];
  description: string;
};

export const COMMON = "common";
const DRINKS = ["wine", "whisky", "sake", "korean_traditional"] as const;

/** Sensations are tasted in every drink. */
const SENSORY_KIND: Readonly<Record<string, string>> = {
  aroma: "향",
  aroma_family: "향",
  texture: "질감",
};
const FACT_KIND: Readonly<Record<string, string>> = {
  process: "제조·숙성",
  maturation: "제조·숙성",
  grape: "품종",
  region: "산지",
  producer: "생산자",
};
/** The dictionary's makers are profiled by what they make. */
const PRODUCER_DRINK: Readonly<Record<string, string>> = {
  distillery: "whisky",
  blend_brand: "whisky",
};

function kindOf(term: Term): string | null {
  // A place's style is filed as the balloon heads it: 산지 스타일 · 레드.
  if (term.type === "regional_style") return wordKind(term);
  return sensationKind(term.type, term.key) ?? SENSORY_KIND[term.type] ??
    FACT_KIND[term.type] ?? null;
}

function categoriesOf(term: Term): string[] {
  if (term.type === "axis" || term.type in SENSORY_KIND) return [COMMON];
  if (term.type === "producer") {
    const drink = PRODUCER_DRINK[String(term.extra?.kind)];
    return drink ? [drink] : [];
  }
  if (term.categories === "all") return [COMMON];
  const named = new Set(term.categories ?? []);
  const drinks = DRINKS.filter((drink) => named.has(drink));
  return drinks.length === DRINKS.length ? [COMMON] : drinks;
}

/** Every term a balloon can explain, by its key. */
const GLOSSARY: ReadonlyMap<string, GlossaryTerm> = new Map(
  terms(
    "axis",
    ...Object.keys(SENSORY_KIND),
    ...Object.keys(FACT_KIND),
    "regional_style",
  )
    .flatMap((term): [string, GlossaryTerm][] => {
      const kind = kindOf(term);
      const description = term.summary?.trim();
      if (!kind || !description) return [];
      const key = termKey(term);
      return [[key, {
        key,
        label: term.names.ko,
        kind,
        categories: categoriesOf(term),
        description,
      }]];
    }),
);

/** The term a key names, or null when no balloon explains it. */
export function glossaryTerm(key: string): GlossaryTerm | null {
  return GLOSSARY.get(key) ?? null;
}

/** A term's key when the reader can save it, else null. */
export function savableKey(term: Term | undefined): string | null {
  return term && GLOSSARY.has(termKey(term)) ? termKey(term) : null;
}
