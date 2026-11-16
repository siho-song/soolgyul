/**
 * Structured facts behind one 술결카드.
 *
 * A card stores these facts next to its rendered sections. Card templates read
 * them to write prose. A card never looks at previous records, so every
 * reaction here belongs to this record.
 *
 * Four fact kinds:
 * - gauge: one answered gauge as the reader set it (the step, liked or not).
 * - reaction: one answered sensation (what, when, liked or burden, why), read
 *   from the gauges and the aromas in the engine's own words.
 * - product: one product condition used in an explanation.
 * - finding: one discovery that links reactions and product conditions through
 *   one way of thinking and one knowledge row to a conclusion.
 * The card-level conclusions (nickname, summary, next choice, exploration,
 * recommendations) reference those ids.
 */
import { serviceVocabulary as vocabulary } from "../dictionary/dictionary.ts";
import { styleProfiles } from "../dictionary/dictionary.ts";
import { termKnowledge } from "../dictionary/dictionary.ts";
import { ALCOHOL_CATEGORY_KEYS } from "../../contract.ts";
import { NICKNAME_CATALOG } from "../nickname/catalog.ts";
import { KNOWLEDGE_ROWS, type KnowledgeRowId } from "../findings/knowledge.ts";

export { KNOWLEDGE_ROWS };

export const CARD_FACTS_SCHEMA_VERSION = "card-facts-v3";
/**
 * The facts of a card written before the gauges (2026-11-16). They are never
 * written again; the taste letters and the fit check still read the stored
 * ones (readStoredCardFacts).
 */
export const LEGACY_CARD_FACTS_SCHEMA_VERSION = "card-facts-v2";

export const TASTE_KEYS = ["sweetness", "acidity"] as const;
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
  "umami_acidity",
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
  "finish_cleanliness",
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
const SCOPES = [
  "itself",
  "intensity",
  "persistence",
  "combination",
  "distinction",
] as const;
const ADJUST_DIRECTIONS = [
  "lower", // less of it while drinking
  "higher", // more of it (the user wanted it stronger)
  "shorter", // it may be there, but should not linger
  "softer", // gentler prickle or heat
] as const;

/** The eight ways a finding connects reactions to a conclusion. */
const THINKINGS = [
  "intensity", // 강도: the sensation itself, at the strength the product has
  "distinction", // 구분: two sensations people conflate; one liked, one burden
  "exposure", // 드러남: a low counterpart let this sensation show
  "masking", // 가림: a strong sensation covered or inflated another
  "persistence", // 지속: what stayed after swallowing, and whether that was welcome
  "combination", // 조합: sensations that were good or heavy together
  "effect", // 작용: what the named aroma does in the nose and mouth
  "origin", // 유래: where the kind's production or ingredients put a taste or mouthfeel
] as const;

type TasteKey = typeof TASTE_KEYS[number];
type MouthfeelKey = typeof MOUTHFEEL_KEYS[number];
type FinishKey = typeof FINISH_KEYS[number];
export type GaugeAxis = typeof GAUGE_AXES[number];
export type AromaStage = typeof AROMA_STAGES[number];
export type LevelDimension = typeof LEVEL_DIMENSIONS[number];
export type Qualifier = typeof QUALIFIERS[number];
type Scope = typeof SCOPES[number];
export type Thinking = typeof THINKINGS[number];
type KnowledgeRow = KnowledgeRowId;
type Phase = "drinking" | "finish";

export type Subject =
  | { domain: "aroma"; key: string }
  | { domain: "taste"; key: TasteKey }
  | { domain: "mouthfeel"; key: MouthfeelKey }
  | { domain: "finish"; key: FinishKey };

export type Condition =
  | {
    type: "level";
    dimension: LevelDimension;
    is: "low" | "mid" | "high";
    /** The number checked is the kind's usual value copied into the bottle, not a reading of it. */
    estimated?: true;
  }
  | { type: "with"; subject: Subject; phase?: Phase }
  | { type: "without"; subject: Subject; phase?: Phase }
  | { type: "trait"; key: string }
  | { type: "phase"; phase: Phase }
  | { type: "descriptor"; key: string; is: "present" | "restrained" }
  | { type: "abv"; is: "lower" | "around" | "higher" }
  | { type: "production"; key: string };

/**
 * The catalog level a gauge is compared with. 사케의 산미·감칠맛 is held
 * against the bottle's acidity alone; 스파이시, 피트 and 끝맛의 인상 have no
 * level in the catalog and are never given an estimated one.
 */
export const GAUGE_LEVEL_DIMENSION: Readonly<
  Record<GaugeAxis, LevelDimension | null>
> = {
  sweetness: "sweetness",
  acidity: "acidity",
  umami_acidity: "acidity",
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

export type Finding = {
  id: string;
  kind: "finding";
  polarity: "positive" | "burden";
  thinking: Thinking;
  row: KnowledgeRow;
  /** Which sentence frame of the row the writer fills. */
  frame: string;
  reactions: readonly string[];
  product_facts: readonly string[];
  conclusion: {
    subjects: readonly Subject[];
    scope: Scope;
    given: readonly Condition[];
  };
};

export type NextChoice = {
  keep: readonly Subject[];
  adjust: readonly {
    subject: Subject;
    direction: typeof ADJUST_DIRECTIONS[number];
  }[];
  avoid_combinations: readonly (readonly Subject[])[];
};

export type CardFacts = {
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
  findings: readonly Finding[];
  nickname: string;
  summary: { preference: readonly string[]; next_choice: NextChoice };
  sections: {
    positive: readonly string[];
    burden: readonly string[];
  };
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
  record: CardFacts["record"];
  reactions: readonly LegacyReactionFact[];
  product_facts: readonly ProductFact[];
};

export type StoredCardFacts = CardFacts | LegacyCardFacts;

/**
 * The facts a card was stored with, for the readers that go over every card
 * of an account (the taste letters, the fit check). Only the shape is
 * checked, so a card of either version keeps counting after the vocabularies
 * move on; aromas are read under their current names. Null for anything else.
 * A caller that needs every id and key checked runs validateCardFacts on the
 * current version.
 */
export function readStoredCardFacts(value: unknown): StoredCardFacts | null {
  const facts = value as Partial<CardFacts> | null;
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
const STYLE_KEYS = new Set([
  ...(styleProfiles as { styles: { key: string }[] }).styles.map((s) => s.key),
  ...(styleProfiles as { wine_grapes: { key: string }[] }).wine_grapes.map((
    s,
  ) => s.key),
  ...(styleProfiles as { wine_regions: { key: string }[] }).wine_regions.map(
    (s) => s.key,
  ),
]);
const NICKNAMES = new Set(
  NICKNAME_CATALOG.flatMap((entry) =>
    entry.label_without_tannin
      ? [entry.label, entry.label_without_tannin]
      : [entry.label]
  ),
);
const TRAIT_KEYS = new Set(
  Object.keys((termKnowledge as { traits: Record<string, unknown> }).traits),
);

class CardFactsError extends Error {
  constructor(readonly path: string, detail: string) {
    super(`${path}: ${detail}`);
  }
}

/** Checks ids, references and vocabularies; returns the typed facts. */
export function validateCardFacts(value: unknown): CardFacts {
  const facts = value as CardFacts;
  const fail = (path: string, detail: string): never => {
    throw new CardFactsError(path, detail);
  };
  if (facts.schema_version !== CARD_FACTS_SCHEMA_VERSION) {
    fail("schema_version", "unknown");
  }
  if (
    facts.record.category !== null &&
    !(ALCOHOL_CATEGORY_KEYS as readonly string[]).includes(
      facts.record.category,
    )
  ) {
    fail("record.category", `unknown ${facts.record.category}`);
  }
  const ids = new Set<string>();
  const register = (id: string, path: string) => {
    if (ids.has(id)) fail(path, `duplicate id ${id}`);
    ids.add(id);
  };
  const subject = (s: Subject, path: string) => {
    if (s.domain === "aroma" && !AROMA_KEYS.has(s.key)) {
      fail(path, `unknown aroma ${s.key}`);
    }
    if (
      s.domain === "taste" && !(TASTE_KEYS as readonly string[]).includes(s.key)
    ) fail(path, `unknown taste ${s.key}`);
    if (
      s.domain === "mouthfeel" &&
      !(MOUTHFEEL_KEYS as readonly string[]).includes(s.key)
    ) fail(path, `unknown mouthfeel ${s.key}`);
    if (
      s.domain === "finish" &&
      !(FINISH_KEYS as readonly string[]).includes(s.key)
    ) fail(path, `unknown finish ${s.key}`);
  };
  const condition = (c: Condition, path: string) => {
    if (c.type === "level") {
      if (!(LEVEL_DIMENSIONS as readonly string[]).includes(c.dimension)) {
        fail(path, `unknown dimension ${c.dimension}`);
      }
    } else if (c.type === "with" || c.type === "without") {
      subject(c.subject, path);
    } else if (c.type === "descriptor") {
      if (!AROMA_KEYS.has(c.key)) fail(path, `unknown descriptor ${c.key}`);
    } else if (c.type === "trait") {
      if (!TRAIT_KEYS.has(c.key)) fail(path, `unknown trait ${c.key}`);
    }
  };
  const ref = (
    id: string,
    kind: ReactionFact["kind"] | ProductFact["kind"] | Finding["kind"],
    path: string,
  ) => {
    const pool = kind === "reaction"
      ? facts.reactions
      : kind === "product"
      ? facts.product_facts
      : facts.findings;
    if (!pool.some((item) => item.id === id)) {
      fail(path, `unknown ${kind} ${id}`);
    }
  };

  facts.gauges.forEach((g, i) => {
    const path = `gauges[${i}]`;
    if (!(GAUGE_AXES as readonly string[]).includes(g.axis)) {
      fail(path, `unknown axis ${g.axis}`);
    }
    if (facts.gauges.findIndex((other) => other.axis === g.axis) !== i) {
      fail(path, `axis ${g.axis} answered twice`);
    }
    if (!Number.isInteger(g.level) || g.level < 1 || g.level > 5) {
      fail(path, `level ${g.level}`);
    }
    if (g.reaction !== "liked" && g.reaction !== "burden") {
      fail(path, `unknown reaction ${g.reaction}`);
    }
    if (!g.answer_ref) fail(path, "answer_ref empty");
  });
  facts.reactions.forEach((r, i) => {
    const path = `reactions[${i}]`;
    register(r.id, path);
    subject(r.subject, path);
    if (r.reaction !== "liked" && r.reaction !== "burden") {
      fail(path, `unknown reaction ${r.reaction}`);
    }
    if (
      r.stages &&
      (r.subject.domain !== "aroma" || r.stages.length === 0 ||
        r.stages.some((stage) => !AROMA_STAGES.includes(stage)))
    ) fail(path, "stages invalid");
    if (
      r.qualifier !== null &&
      !(QUALIFIERS as readonly string[]).includes(r.qualifier)
    ) {
      fail(path, `unknown qualifier ${r.qualifier}`);
    }
    if (r.answer_refs.length === 0) fail(path, "answer_refs empty");
  });
  facts.product_facts.forEach((p, i) => {
    const path = `product_facts[${i}]`;
    register(p.id, path);
    if (
      p.fact.type === "level" &&
      !(LEVEL_DIMENSIONS as readonly string[]).includes(p.fact.dimension)
    ) {
      fail(path, `unknown dimension ${p.fact.dimension}`);
    }
    if (p.fact.type === "descriptor" && !AROMA_KEYS.has(p.fact.key)) {
      fail(path, `unknown descriptor ${p.fact.key}`);
    }
    if (p.fact.type === "trait" && !TRAIT_KEYS.has(p.fact.key)) {
      fail(path, `unknown trait ${p.fact.key}`);
    }
    if (p.fact.type === "style" && !STYLE_KEYS.has(p.fact.key)) {
      fail(path, `unknown style ${p.fact.key}`);
    }
  });
  facts.findings.forEach((d, i) => {
    const path = `findings[${i}]`;
    register(d.id, path);
    if (!(THINKINGS as readonly string[]).includes(d.thinking)) {
      fail(path, `unknown thinking ${d.thinking}`);
    }
    const row = (KNOWLEDGE_ROWS as Record<string, { thinking: Thinking }>)[
      d.row
    ];
    if (typeof d.frame !== "string" || !d.frame) fail(path, "frame missing");
    if (!row) fail(path, `unknown knowledge row ${d.row}`);
    if (row.thinking !== d.thinking) {
      fail(path, `row ${d.row} belongs to ${row.thinking}`);
    }
    if (d.reactions.length === 0) fail(path, "reactions empty");
    d.reactions.forEach((id) => ref(id, "reaction", path));
    d.product_facts.forEach((id) => ref(id, "product", path));
    if (d.conclusion.subjects.length === 0) {
      fail(path, "conclusion subjects empty");
    }
    d.conclusion.subjects.forEach((s) => subject(s, path));
    if (!(SCOPES as readonly string[]).includes(d.conclusion.scope)) {
      fail(path, `unknown scope ${d.conclusion.scope}`);
    }
    d.conclusion.given.forEach((c) => condition(c, path));
  });

  if (!NICKNAMES.has(facts.nickname)) {
    fail("nickname", `unknown ${facts.nickname}`);
  }
  facts.summary.preference.forEach((id) =>
    ref(id, "finding", "summary.preference")
  );
  const next = facts.summary.next_choice;
  next.keep.forEach((s) => subject(s, "summary.next_choice.keep"));
  next.adjust.forEach((a) => {
    subject(a.subject, "summary.next_choice.adjust");
    if (!(ADJUST_DIRECTIONS as readonly string[]).includes(a.direction)) {
      fail("summary.next_choice.adjust", `unknown direction ${a.direction}`);
    }
  });
  next.avoid_combinations.forEach((combo) => {
    if (combo.length < 2) {
      fail("summary.next_choice.avoid_combinations", "needs two subjects");
    }
    combo.forEach((s) => subject(s, "summary.next_choice.avoid_combinations"));
  });

  const sections = facts.sections;
  sections.positive.forEach((id) => {
    ref(id, "finding", "sections.positive");
    if (facts.findings.find((d) => d.id === id)?.polarity !== "positive") {
      fail("sections.positive", `${id} is not positive`);
    }
  });
  sections.burden.forEach((id) => {
    ref(id, "finding", "sections.burden");
    if (facts.findings.find((d) => d.id === id)?.polarity !== "burden") {
      fail("sections.burden", `${id} is not burden`);
    }
  });
  if (sections.positive.length > 2 || sections.burden.length > 2) {
    fail("sections", "more than two findings in a section");
  }
  return facts;
}
