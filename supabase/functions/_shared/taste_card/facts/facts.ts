/**
 * The words the stages before the rebuild still read a record in: one
 * answered gauge, one answered sensation (reaction) and one product
 * condition. The taste letters and the fit read them; a card does not.
 */
import { serviceVocabulary as vocabulary } from "../dictionary/dictionary.ts";

export const CARD_FACTS_SCHEMA_VERSION = "card-facts-v3";
/**
 * The facts of a card written before the gauges (2026-11-16). They are never
 * written again; the taste letters and the fit check still read the stored
 * ones (readStoredCardFacts).
 */
export const LEGACY_CARD_FACTS_SCHEMA_VERSION = "card-facts-v2";

export const TASTE_KEYS = ["sweetness", "acidity", "umami"] as const;
export const MOUTHFEEL_KEYS = [
  "light",
  "heavy",
  "smooth",
  "drying",
  "bubbles",
  "warmth",
] as const;
/**
 * 여운 길이, 깔끔함, 삼킨 뒤 남은 향, 삼킨 뒤 거슬린 향, 끝맛의 인상. The first
 * two are read from the 여운의 길이 gauge, the next two from the finish
 * aromas, the last from its own gauge (2026-11-16).
 */
const FINISH_KEYS = [
  "persistence",
  "clean",
  "aroma_echo",
  "off_flavor",
  "character",
] as const;
/**
 * The gauges of the questionnaire, by the axis each one asks. Which of them a
 * drink is asked, and under which name, is the gauge sheet's
 * (catalog/sensory/gauge-definitions.json).
 */
export const GAUGE_AXES = [
  "sweetness",
  "acidity",
  "umami",
  "body",
  "tannin",
  "sparkling",
  "spice",
  "peat",
  "finish_length",
  "finish_character",
] as const;
/** Where an aroma was picked: by the nose, in the mouth, after swallowing. */
export const AROMA_STAGES = ["nose", "palate", "finish"] as const;
export const LEVEL_DIMENSIONS = [
  "sweetness",
  "acidity",
  "bitterness",
  "body",
  "astringency",
  "viscosity",
  "carbonation",
  "alcohol_presence",
  "aroma_intensity",
  "flavour_clarity",
  "finish_length",
  "finish_character",
] as const;
/**
 * How a gauge answer names its strength: a liked step 1–2 is gentle and 4–5
 * pronounced, a minded step 4–5 excessive and 1–2 too_weak. A long finish
 * minded is lingering, a short one too_brief.
 */
const QUALIFIERS = [
  "gentle",
  "pronounced",
  "excessive",
  "too_weak",
  "lingering",
  "too_brief",
] as const;
type TasteKey = typeof TASTE_KEYS[number];
type MouthfeelKey = typeof MOUTHFEEL_KEYS[number];
type FinishKey = typeof FINISH_KEYS[number];
export type GaugeAxis = typeof GAUGE_AXES[number];
export type AromaStage = typeof AROMA_STAGES[number];
export type LevelDimension = typeof LEVEL_DIMENSIONS[number];
export type Qualifier = typeof QUALIFIERS[number];
type Phase = "drinking" | "finish";

export type Subject =
  | { domain: "aroma"; key: string }
  | { domain: "taste"; key: TasteKey }
  | { domain: "mouthfeel"; key: MouthfeelKey }
  | { domain: "finish"; key: FinishKey };

/**
 * The catalog level a gauge is compared with. 감칠맛, 스파이시 and 피트 have
 * no level in the catalog and are never given an estimated one. 끝맛의 인상
 * has one (finish_character), but nearly every bottle that carries it sits on
 * the same step, so the gauge is not compared with it.
 */
export const GAUGE_LEVEL_DIMENSION: Readonly<
  Record<GaugeAxis, LevelDimension | null>
> = {
  sweetness: "sweetness",
  acidity: "acidity",
  umami: null,
  body: "body",
  tannin: "astringency",
  sparkling: "carbonation",
  spice: null,
  peat: null,
  finish_length: "finish_length",
  finish_character: null,
};

/**
 * One answered gauge as the reader set it: the step felt, and whether it was
 * liked or marked 아쉬웠어요 on the review page. Every answered gauge the
 * drink is asked is kept, the middle step included, though a middle step of
 * 바디 or 타닌 makes no reaction.
 */
export type GaugeFact = {
  axis: GaugeAxis;
  level: 1 | 2 | 3 | 4 | 5;
  reaction: "liked" | "burden";
  answer_ref: string;
};

export type ReactionFact = {
  id: string;
  kind: "reaction";
  subject: Subject;
  phase: Phase;
  reaction: "liked" | "burden";
  qualifier: Qualifier | null;
  /** An aroma only: the pickers it was chosen in (the nose and the mouth read as one aroma). */
  stages?: readonly AromaStage[];
  answer_refs: readonly string[];
};

export type ProductFact = {
  id: string;
  kind: "product";
  fact:
    | {
      type: "level";
      dimension: LevelDimension;
      level: 1 | 2 | 3 | 4 | 5;
      /** The number is the kind's usual value copied into this bottle, not a reading of it. */
      estimated?: true;
    }
    | {
      type: "descriptor";
      key: string;
      section: "aroma" | "palate" | "texture" | "finish";
    }
    | { type: "trait"; key: string }
    | { type: "abv"; value: number }
    | { type: "ingredient"; key: string }
    | { type: "style"; key: string }
    | { type: "production"; key: string };
  source: string;
};

/**
 * What one record's answers and its bottle read to. The parts that count
 * across records (the taste letters, the fit) read this, built from the
 * answers each time.
 */
export type AnsweredCardFacts = {
  schema_version: typeof CARD_FACTS_SCHEMA_VERSION;
  record: {
    product_name: string;
    /** null when the reader named the drink without saying what kind it is. */
    category: string | null;
    style_key: string | null;
    revisit:
      | "want_again"
      | "would_accept_again"
      | "do_not_want_again"
      | "unknown";
  };
  gauges: readonly GaugeFact[];
  reactions: readonly ReactionFact[];
  product_facts: readonly ProductFact[];
};

/** The vocabulary groups a descriptor fact may name (the aroma and flavour groups). */
export const AROMA_KEYS: ReadonlySet<string> = new Set(
  (vocabulary as { groups: { key: string; domain: string }[] }).groups
    .filter((group) => group.domain === "descriptor")
    .map((group) => group.key),
);
/** The name each word of the vocabulary is read as: the group it sits in. */
const AROMA_OF_WORD: ReadonlyMap<string, string> = new Map(
  (vocabulary as {
    groups: { key: string; domain: string; source_keys: string[] }[];
  }).groups
    .filter((group) => group.domain === "descriptor")
    .flatMap((group) =>
      group.source_keys.map((word) => [word, group.key] as const)
    ),
);
/** 묵은 양주 was a name until 2026-11-16 and joined none; most of what it held went to 오크. */
const RETIRED_AROMAS: Readonly<Record<string, string>> = {
  aged_aromatic: "oak",
};

/**
 * Facts stored before a name stopped being offered still say that name (피망
 * before it joined 채소). They are read as the name it joined, so a card
 * written then keeps counting. Returns a copy.
 */
export function withCurrentAromas<T>(value: T): T {
  const current = (key: string) =>
    AROMA_KEYS.has(key)
      ? key
      : AROMA_OF_WORD.get(key) ?? RETIRED_AROMAS[key] ?? key;
  const walk = (node: unknown): unknown => {
    if (Array.isArray(node)) return node.map(walk);
    if (node === null || typeof node !== "object") return node;
    const copy: Record<string, unknown> = Object.fromEntries(
      Object.entries(node).map(([name, child]) => [name, walk(child)]),
    );
    if (
      typeof copy.key === "string" &&
      (copy.domain === "aroma" || copy.type === "descriptor")
    ) copy.key = current(copy.key);
    return copy;
  };
  return walk(value) as T;
}

/** A reaction as a card stored before the gauges holds it. */
export type LegacyReactionFact = {
  id: string;
  kind: "reaction";
  /** Includes 쓴맛 (taste:bitterness), which is no longer asked. */
  subject: { domain: Subject["domain"]; key: string };
  phase: Phase;
  reaction: "liked" | "burden" | "unstated";
  qualifier:
    | Qualifier
    | "harmonious"
    | "masking"
    | "disharmonious"
    | "quick_clearing"
    | null;
  focus: boolean;
  answer_refs: readonly string[];
};

/** What is still read of a card stored before the gauges: its drink, its answers and its bottle. */
export type LegacyCardFacts = {
  schema_version: typeof LEGACY_CARD_FACTS_SCHEMA_VERSION;
  record: AnsweredCardFacts["record"];
  reactions: readonly LegacyReactionFact[];
  product_facts: readonly ProductFact[];
};

export type StoredCardFacts = AnsweredCardFacts | LegacyCardFacts;

/**
 * The facts a card was stored with, for the readers that go over every card
 * of an account (the taste letters, the fit check). Only the shape is
 * checked, so a card of either version keeps counting after the vocabularies
 * move on; aromas are read under their current names. Null for anything else.
 */
export function readStoredCardFacts(value: unknown): StoredCardFacts | null {
  const facts = value as Partial<AnsweredCardFacts> | null;
  const listed = <T>(items: unknown, check: (item: T) => boolean) =>
    Array.isArray(items) &&
    items.every((item) => item && typeof item === "object" && check(item));
  if (
    !facts || typeof facts !== "object" ||
    (facts.schema_version !== CARD_FACTS_SCHEMA_VERSION &&
      facts.schema_version !== LEGACY_CARD_FACTS_SCHEMA_VERSION) ||
    !facts.record || typeof facts.record !== "object" ||
    typeof facts.record.product_name !== "string" ||
    typeof facts.record.revisit !== "string" ||
    !listed(
      facts.reactions,
      (r: ReactionFact) =>
        typeof r.id === "string" && typeof r.subject?.domain === "string" &&
        typeof r.subject.key === "string" && typeof r.phase === "string" &&
        typeof r.reaction === "string",
    ) ||
    !listed(
      facts.product_facts,
      (p: ProductFact) => typeof p.fact?.type === "string",
    ) ||
    (facts.schema_version === CARD_FACTS_SCHEMA_VERSION &&
      !listed(
        facts.gauges,
        (g: GaugeFact) =>
          typeof g.axis === "string" && typeof g.level === "number" &&
          typeof g.reaction === "string",
      ))
  ) return null;
  return withCurrentAromas(facts as StoredCardFacts);
}
