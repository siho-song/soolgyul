/**
 * 설명: the eight thinkings read one card's reactions and product facts
 * and apply knowledge rows. Each finding names its row, the reactions and
 * product facts it used, and the sentence frame the writer should fill.
 */
import { termKnowledge } from "../dictionary/dictionary.ts";
import { aromaLine, sameAromaLine } from "../dictionary/aroma_lineage.ts";
import type {
  Condition,
  Finding,
  LevelDimension,
  ProductFact,
  ReactionFact,
  Subject,
  Thinking,
} from "../facts/facts.ts";
import type { CardReading } from "../facts/reading.ts";
import {
  type Band,
  COMBINATION_ROWS,
  DISTINCTION_ROWS,
  EFFECT_ROWS,
  type EffectRow,
  EXPOSURE_ROWS,
  INTENSITY_ROWS,
  type KnowledgeRowId,
  MASKING_ROWS,
  type PairMember,
  PERSISTENCE_ROWS,
  type ProductCondition,
} from "./knowledge.ts";
import {
  mergedStyleProfile,
  type StyleProfile,
  styleTraitLine,
} from "../dictionary/style_lines.ts";

/** Never read from product data: these are not collected per product. */
const IGNORED_LEVELS: ReadonlySet<string> = new Set([
  "bitterness",
  "viscosity",
  "flavour_clarity",
]);

function band(level: 1 | 2 | 3 | 4 | 5): Band {
  return level <= 2 ? "low" : level === 3 ? "mid" : "high";
}

const SCENT_TRAITS = new Map(
  Object.entries(
    (termKnowledge as {
      terms: Record<string, { sensory_trait_keys?: string[] }>;
    }).terms,
  ).map(([key, term]) => [key, term.sensory_trait_keys ?? []]),
);

/** What the product facts say, indexed for the matchers. */
class Product {
  readonly levels = new Map<LevelDimension, { band: Band; id: string }>();
  readonly aromas = new Map<string, string>();
  readonly traits = new Map<string, string>();
  /** The style, process, grape and region lines together, and the fact id behind each entry. */
  readonly style: StyleProfile | null;
  readonly styleIds = new Map<string, string>();

  constructor(facts: readonly ProductFact[]) {
    const styleKeys: string[] = [];
    for (const fact of facts) {
      const f = fact.fact;
      if (f.type === "level" && !IGNORED_LEVELS.has(f.dimension)) {
        this.levels.set(f.dimension, { band: band(f.level), id: fact.id });
      } else if (f.type === "descriptor" && f.section === "aroma") {
        this.aromas.set(f.key, fact.id);
      } else if (f.type === "trait") {
        this.traits.set(f.key, fact.id);
      } else if (f.type === "style" || f.type === "production") {
        styleKeys.push(f.key);
        this.styleIds.set(f.key, fact.id);
      }
    }
    this.style = mergedStyleProfile(styleKeys);
  }

  level(dimension: LevelDimension) {
    return this.levels.get(dimension) ?? null;
  }
  /** Fact ids of product aromas on the same line as the reader's aroma. */
  aromaIds(key: string): string[] {
    return [...this.aromas].filter(([k]) => sameAromaLine(k, key)).map((
      [, id],
    ) => id);
  }
  /** Aroma facts carrying a scent trait. */
  scented(trait: string): { key: string; id: string }[] {
    return [...this.aromas].filter(([key]) =>
      SCENT_TRAITS.get(key)?.includes(trait)
    ).map(([key, id]) => ({ key, id }));
  }
  /** Fact ids and card conditions when a product condition holds, else null. */
  check(
    condition: ProductCondition,
  ): { ids: string[]; given: Condition[] } | null {
    if (condition.type === "level" || condition.type === "level_not") {
      const level = this.level(condition.dimension);
      if (!level) return null;
      const matches = level.band === condition.is;
      if (condition.type === "level" ? !matches : matches) return null;
      return {
        ids: [level.id],
        given: [{
          type: "level",
          dimension: condition.dimension,
          is: level.band,
        }],
      };
    }
    if (condition.type === "trait") {
      const id = this.traits.get(condition.key);
      return id
        ? { ids: [id], given: [{ type: "trait", key: condition.key }] }
        : null;
    }
    const scented = this.scented(condition.trait);
    if (!scented.length) return null;
    return {
      ids: scented.map((s) => s.id),
      given: scented.map((s) => ({
        type: "descriptor",
        key: s.key,
        is: "present",
      })),
    };
  }
  any(conditions: readonly ProductCondition[]) {
    for (const condition of conditions) {
      const hit = this.check(condition);
      if (hit) return hit;
    }
    return null;
  }
  all(conditions: readonly ProductCondition[]) {
    const ids: string[] = [];
    const given: Condition[] = [];
    for (const condition of conditions) {
      const hit = this.check(condition);
      if (!hit) return null;
      ids.push(...hit.ids);
      given.push(...hit.given);
    }
    return { ids, given };
  }
}

const sameSubject = (a: Subject, b: Subject) =>
  a.domain === b.domain && (a.key === b.key || b.key === "*" || a.key === "*");

function memberMatches(member: PairMember, reaction: ReactionFact): boolean {
  if (member.domain === "scent") {
    return reaction.subject.domain === "aroma" &&
      (SCENT_TRAITS.get(reaction.subject.key) ?? []).includes(member.trait);
  }
  return sameSubject(member, reaction.subject);
}

/** The dimension that says how strong a mouthfeel or taste subject is, and which way. */
const SUBJECT_DIMENSION: Readonly<
  Record<string, { dimension: LevelDimension; reversed: boolean }>
> = {
  sweetness: { dimension: "sweetness", reversed: false },
  acidity: { dimension: "acidity", reversed: false },
  light: { dimension: "body", reversed: true },
  heavy: { dimension: "body", reversed: false },
  smooth: { dimension: "astringency", reversed: true },
  drying: { dimension: "astringency", reversed: false },
  bubbles: { dimension: "carbonation", reversed: false },
  warmth: { dimension: "alcohol_presence", reversed: false },
};
/**
 * The style-table line that explains a sensation. On spirits the table's
 * smoothness line (how the still and the cask round the alcohol off) explains
 * 매끄러움; elsewhere smoothness is the low end of astringency (tannin).
 */
export function styleDimension(
  subject: Subject,
  profile: StyleProfile | null,
): { dimension: string; reversed: boolean } | null {
  if (subject.domain === "taste") {
    return { dimension: subject.key, reversed: false };
  }
  if (subject.key === "smooth" && styleTraitLine(profile, "smoothness")) {
    return { dimension: "smoothness", reversed: false };
  }
  return SUBJECT_DIMENSION[subject.key] ?? null;
}
const flip = (b: Band): Band =>
  b === "low" ? "high" : b === "high" ? "low" : "mid";
/** How strong the subject itself is in the product, if the product says. */
function subjectStrength(subject: Subject, product: Product) {
  const map = subject.domain === "aroma"
    ? { dimension: "aroma_intensity" as LevelDimension, reversed: false }
    : subject.domain === "finish"
    ? { dimension: "finish_length" as LevelDimension, reversed: false }
    : SUBJECT_DIMENSION[subject.key];
  if (!map) return null;
  const level = product.level(map.dimension);
  if (!level) return null;
  return {
    dimension: map.dimension,
    id: level.id,
    band: map.reversed ? flip(level.band) : level.band,
  };
}

type Draft = Omit<Finding, "id">;
const THINKING_ORDER: readonly Thinking[] = [
  "intensity",
  "distinction",
  "exposure",
  "masking",
  "persistence",
  "combination",
  "effect",
  "origin",
];

function draft(
  thinking: Thinking,
  row: KnowledgeRowId,
  frame: string,
  polarity: Finding["polarity"],
  reactions: readonly string[],
  product_facts: readonly string[],
  subjects: readonly Subject[],
  scope: Finding["conclusion"]["scope"],
  given: readonly Condition[],
): Draft {
  return {
    kind: "finding",
    polarity,
    thinking,
    row,
    frame,
    reactions,
    product_facts: [...new Set(product_facts)].sort((a, b) =>
      Number(a.slice(1)) - Number(b.slice(1))
    ),
    conclusion: {
      subjects,
      scope,
      given: [...given].sort((a, b) =>
        JSON.stringify(a).localeCompare(JSON.stringify(b))
      ),
    },
  };
}

/** The user said this sensation covered other sensations. */
const saysMasks = (r: ReactionFact) =>
  r.qualifier === "masking" || r.qualifier === "disharmonious";
const polarityOf = (r: ReactionFact): Finding["polarity"] =>
  r.reaction === "burden" ? "burden" : "positive";
/** Drinking answers that took a side; 적당했어요 (fine) explains nothing. */
const drinking = (reactions: readonly ReactionFact[]) =>
  reactions.filter((r) =>
    r.phase === "drinking" &&
    (r.reaction === "liked" || r.reaction === "burden")
  );

function distinction(
  reactions: readonly ReactionFact[],
  product: Product,
): Draft[] {
  const out: Draft[] = [];
  for (const r of drinking(reactions)) {
    for (const [id, row] of Object.entries(DISTINCTION_ROWS)) {
      if (!sameSubject(r.subject, row.felt)) continue;
      if (row.qualifier && row.qualifier !== r.qualifier) continue;
      const low = product.all(row.felt_low);
      const actual = low && product.any(row.actual);
      if (!low || !actual) continue;
      const frame = `${r.reaction}_${row.frame}`;
      out.push(draft(
        "distinction",
        id as KnowledgeRowId,
        frame,
        polarityOf(r),
        [r.id],
        [...low.ids, ...actual.ids],
        [r.subject],
        "distinction",
        [...low.given, ...actual.given],
      ));
    }
  }
  return out;
}

function exposure(
  reactions: readonly ReactionFact[],
  product: Product,
): Draft[] {
  const out: Draft[] = [];
  for (const r of drinking(reactions)) {
    if (["gentle", "too_weak"].includes(r.qualifier ?? "") || saysMasks(r)) {
      continue;
    }
    const own = subjectStrength(r.subject, product);
    if (own?.band === "low") continue;
    for (const [id, row] of Object.entries(EXPOSURE_ROWS)) {
      if (!sameSubject(r.subject, row.subject)) continue;
      const hit = product.any(
        row.low.map((dimension) => ({ type: "level", dimension, is: "low" })),
      );
      if (!hit) continue;
      out.push(draft(
        "exposure",
        id as KnowledgeRowId,
        r.reaction,
        polarityOf(r),
        [r.id],
        [...hit.ids, ...(own ? [own.id] : [])],
        [r.subject],
        "itself",
        hit.given,
      ));
    }
  }
  return out;
}

function masking(
  reactions: readonly ReactionFact[],
  product: Product,
): Draft[] {
  const out: Draft[] = [];
  const rows = Object.entries(MASKING_ROWS);
  for (const r of drinking(reactions)) {
    const q = r.qualifier;
    if (
      r.reaction === "burden" &&
      (q === "excessive" || q === null || saysMasks(r))
    ) {
      // A: the strong sensation was the burden. C: the user said it masked others.
      let matched = false;
      for (const [id, row] of rows) {
        if (!sameSubject(r.subject, row.masker)) continue;
        const present = row.masked_present.length
          ? product.any(row.masked_present)
          : { ids: [], given: [] };
        if (!present) continue;
        matched = true;
        const subjects = row.masked.domain === "scent" || row.masked.key === "*"
          ? [r.subject]
          : [r.subject, row.masked];
        out.push(draft(
          "masking",
          id as KnowledgeRowId,
          saysMasks(r) ? "masks_others" : "strong_burden",
          "burden",
          [r.id],
          present.ids,
          subjects,
          "intensity",
          present.given,
        ));
      }
      if (!matched && saysMasks(r)) {
        out.push(
          draft(
            "masking",
            "masking_general",
            "masks_others_general",
            "burden",
            [r.id],
            [],
            [r.subject],
            "intensity",
            [],
          ),
        );
      }
    }
    const gentle = r.reaction === "liked" &&
      (q === "gentle" || (q === null && r.subject.domain === "mouthfeel"));
    if ((r.reaction === "burden" && q === "too_weak") || gentle) {
      // B: it felt weak because something strong covered it. D: something strong softened it.
      for (const [id, row] of rows) {
        const masked = row.masked.domain === "scent"
          ? r.subject.domain === "aroma" &&
            (SCENT_TRAITS.get(r.subject.key) ?? []).includes(row.masked.trait)
          : sameSubject(r.subject, row.masked);
        if (!masked) continue;
        const strength = subjectStrength(row.masker, product);
        if (strength?.band !== "high") continue;
        out.push(draft(
          "masking",
          id as KnowledgeRowId,
          gentle ? "gentle_liked" : "too_weak",
          gentle ? "positive" : "burden",
          [r.id],
          [strength.id],
          [r.subject, row.masker],
          "intensity",
          [{
            type: "level",
            dimension: strength.dimension,
            is: product.level(strength.dimension)!.band,
          }],
        ));
      }
    }
  }
  return out;
}

function persistence(
  reactions: readonly ReactionFact[],
  product: Product,
): Draft[] {
  const finish = reactions.filter((r) =>
    r.phase === "finish" && r.subject.key !== "persistence"
  );
  const out: Draft[] = [];
  for (const r of finish) {
    const entry = Object.entries(PERSISTENCE_ROWS).find(([, row]) =>
      sameSubject(r.subject, row.subject)
    );
    if (!entry) continue;
    const [id, row] = entry;
    // 깔끔했어요 stands even when one sensation lingered as a burden: the
    // weight left the mouth while that one taste stayed (the writer says so).
    if (r.subject.key === "clean") {
      out.push(
        draft(
          "persistence",
          id as KnowledgeRowId,
          "clean",
          "positive",
          [r.id],
          leverIds(row.levers, product),
          [r.subject],
          "persistence",
          [{ type: "phase", phase: "finish" }],
        ),
      );
      continue;
    }
    // 잔향 and 잡내 (2026-11-06): what came up the nose after swallowing pairs
    // with the aromas the reader liked or minded while drinking, if any.
    if (r.subject.domain === "finish") {
      const side = r.reaction === "liked" ? "liked" : "burden";
      const aromas = reactions.filter((o) =>
        o.phase === "drinking" && o.subject.domain === "aroma" &&
        o.reaction === side
      );
      out.push(draft(
        "persistence",
        id as KnowledgeRowId,
        side === "liked"
          ? "liked"
          : aromas.length
          ? "burden_after_burden"
          : "burden_alone",
        side === "liked" ? "positive" : "burden",
        [...aromas.map((o) => o.id), r.id],
        leverIds(row.levers, product),
        [r.subject],
        "persistence",
        [{ type: "phase", phase: "finish" }],
      ));
      continue;
    }
    // Same sensation both welcome and a burden after swallowing: only the burden speaks.
    if (
      r.reaction === "liked" &&
      finish.some((o) =>
        o !== r && o.reaction === "burden" && sameSubject(o.subject, r.subject)
      )
    ) continue;
    const during = reactions.find((o) =>
      o.phase === "drinking" && sameSubject(o.subject, r.subject) &&
      (o.reaction === "liked" || o.reaction === "burden") &&
      o.qualifier !== "too_weak"
    );
    const side = r.reaction === "unstated"
      ? during?.reaction ?? null
      : r.reaction;
    if (!side) continue;
    const frame = side === "liked"
      ? (during?.reaction === "burden" ? "liked_after_burden" : "liked")
      : during?.reaction === "liked"
      ? "burden_after_liked"
      : during?.reaction === "burden"
      ? "burden_after_burden"
      : "burden_alone";
    const paired = frame !== "liked" && frame !== "burden_alone" && during
      ? [during.id]
      : [];
    out.push(draft(
      "persistence",
      id as KnowledgeRowId,
      frame,
      side === "liked" ? "positive" : "burden",
      [...paired, r.id],
      leverIds(row.levers, product),
      [r.subject],
      "persistence",
      [{ type: "phase", phase: "finish" }],
    ));
  }
  return out;
}
function leverIds(levers: readonly LevelDimension[], product: Product) {
  return levers.map((d) => product.level(d)?.id).filter((id): id is string =>
    !!id
  );
}

function combination(reactions: readonly ReactionFact[]): Draft[] {
  const out: Draft[] = [];
  const list = drinking(reactions);
  // All liked aromas of one record form one impression together.
  const likedAromas = list.filter((r) =>
    r.subject.domain === "aroma" && r.reaction === "liked"
  );
  if (likedAromas.length >= 2) {
    out.push(draft(
      "combination",
      "combination_aroma_pair",
      "good",
      "positive",
      likedAromas.map((r) => r.id),
      [],
      likedAromas.map((r) => r.subject),
      "combination",
      [],
    ));
  }
  for (let i = 0; i < list.length; i++) {
    for (let j = i + 1; j < list.length; j++) {
      const a = list[i], b = list[j];
      for (const [id, row] of Object.entries(COMBINATION_ROWS)) {
        const strongAroma = (r: ReactionFact) =>
          r.subject.domain !== "aroma" || r.qualifier === "excessive";
        const orders: [ReactionFact, ReactionFact][] = [[a, b], [b, a]];
        const placed = orders.find(([x, y]) =>
          memberMatches(row.pair[0], x) && memberMatches(row.pair[1], y)
        );
        if (!placed) continue;
        const reactionsOf = placed.map((r) => r.reaction);
        const ok = row.kind === "good"
          ? reactionsOf.every((v) => v === "liked")
          : row.kind === "burden"
          ? reactionsOf.every((v) => v === "burden") &&
            placed.every(strongAroma)
          : reactionsOf.includes("liked") && reactionsOf.includes("burden");
        if (!ok) continue;
        // A support pair names the liked member first.
        const [x, y] = row.kind === "support" && placed[0].reaction !== "liked"
          ? [placed[1], placed[0]]
          : placed;
        if (id === "combination_aroma_pair") continue;
        out.push(draft(
          "combination",
          id as KnowledgeRowId,
          row.kind,
          row.kind === "good" ? "positive" : "burden",
          [x.id, y.id],
          [],
          [x.subject, y.subject],
          "combination",
          [],
        ));
        break;
      }
    }
  }
  return out;
}

/**
 * The effect row for an aroma: the nearest node of its line in the catalog
 * tree that a row covers. Exported for the writer and the coverage test.
 */
export function effectRow(subjectKey: string): KnowledgeRowId | null {
  const rows = Object.entries(EFFECT_ROWS) as [string, EffectRow][];
  for (const node of aromaLine(subjectKey)) {
    const hit = rows.find(([, row]) => row.nodes.includes(node));
    if (hit) return hit[0] as KnowledgeRowId;
  }
  return null;
}

/**
 * 작용: every aroma the reader named gets what its family does to the senses,
 * so no aroma answer is left without an explanation. The frame carries the
 * reader's reason (은은해서, 너무 강해서, 더 또렷했으면); masking reasons go
 * to the masking thinking instead.
 */
function effect(reactions: readonly ReactionFact[], product: Product): Draft[] {
  const out: Draft[] = [];
  for (const r of drinking(reactions)) {
    if (r.subject.domain !== "aroma" || saysMasks(r)) continue;
    const row = effectRow(r.subject.key);
    if (!row) continue;
    const frame = r.reaction === "liked"
      ? (r.qualifier === "gentle" ? "gentle" : "liked")
      : r.qualifier === "excessive"
      ? "excessive"
      : r.qualifier === "too_weak"
      ? "too_weak"
      : "burden";
    out.push(
      draft(
        "effect",
        row,
        frame,
        polarityOf(r),
        [r.id],
        product.aromaIds(r.subject.key),
        [r.subject],
        "itself",
        [],
      ),
    );
  }
  return out;
}

function origin(reactions: readonly ReactionFact[], product: Product): Draft[] {
  const out: Draft[] = [];
  for (const r of drinking(reactions)) {
    if (saysMasks(r)) continue;
    // 더 있었으면 is written from the bottle's own levels (intensity); a kind
    // line could say the opposite of this bottle (a sweet 증류식 소주).
    if (r.qualifier === "too_weak") continue;
    const frame = r.reaction;
    // Aromas are explained by their effect, not their origin.
    if (r.subject.domain === "aroma") continue;
    const map = styleDimension(r.subject, product.style);
    if (!map) continue;
    const trait = styleTraitLine(product.style, map.dimension);
    if (!trait) continue;
    const styleBand = trait.level === "none" ? "low" : trait.level as Band;
    const strength = map.reversed ? flip(styleBand) : styleBand;
    // A line that says the kind has little of what the reader felt would deny
    // the reader. A reversed subject (가벼움 on body, 매끄러움 on astringency)
    // is explained only by a line that says the kind has little of the
    // dimension: a "mid" line is written as having some of it ("가벼운
    // 술보다는 무게감이 느껴져요") and would deny the reader too.
    const agrees = map.reversed ? strength === "high" : strength !== "low";
    if (!agrees) continue;
    out.push(
      draft(
        "origin",
        "origin_style",
        frame,
        polarityOf(r),
        [r.id],
        [product.styleIds.get(trait.source)!],
        [r.subject],
        "itself",
        [],
      ),
    );
  }
  return out;
}

function intensity(
  reactions: readonly ReactionFact[],
  product: Product,
  others: readonly Draft[],
): Draft[] {
  const out: Draft[] = [];
  const explained = new Set(others.flatMap((d) => d.reactions));
  const candidates = reactions.filter((r) =>
    (r.reaction === "liked" || r.reaction === "burden") && !saysMasks(r) &&
    (r.phase === "drinking" || r.subject.key === "persistence")
  );
  for (const r of candidates) {
    const entry = Object.entries(INTENSITY_ROWS).find(([, row]) =>
      sameSubject(r.subject, row.subject)
    );
    if (!entry) continue;
    const [id] = entry;
    const strength = subjectStrength(r.subject, product);
    // An aroma's strength is said only when the reader said 또렷해서 and the
    // catalog agrees (high). A middle value is usually the kind's default
    // copied into the bottle, and every aroma has its effect to carry it.
    if (
      r.subject.domain === "aroma" &&
      !(r.qualifier === "pronounced" && strength?.band === "high")
    ) continue;
    const opposite = strength?.band === "low" &&
      ["light", "heavy", "smooth"].includes(r.subject.key);
    if (strength && !opposite) {
      const much = strength.band !== "low";
      // 너무 약했어요 has its own frames: the level agrees (little) or not (much).
      const frame = r.qualifier === "too_weak"
        ? `too_weak_${much ? "much" : "little"}`
        : `${r.reaction}_${much ? "much" : "little"}`;
      out.push(draft(
        "intensity",
        id as KnowledgeRowId,
        frame,
        polarityOf(r),
        [r.id],
        [strength.id],
        [r.subject],
        "intensity",
        [{
          type: "level",
          dimension: strength.dimension,
          is: product.level(strength.dimension)!.band,
        }],
      ));
    } else if (!explained.has(r.id) || r.qualifier === "too_weak") {
      // 너무 약했어요 is offered even when another thinking covers the answer:
      // a style line or a masking written for a burden says the opposite.
      out.push(draft(
        "intensity",
        id as KnowledgeRowId,
        r.qualifier === "too_weak" ? "too_weak" : "no_level",
        polarityOf(r),
        [r.id],
        [],
        [r.subject],
        "intensity",
        [],
      ));
    }
  }
  return out;
}

/** Applies the eight thinkings to one reading. Pure and order-independent. */
export function findCard(reading: CardReading): Finding[] {
  const product = new Product(reading.product_facts);
  const reactions = reading.reactions;
  const others = [
    ...distinction(reactions, product),
    ...exposure(reactions, product),
    ...masking(reactions, product),
    ...persistence(reactions, product),
    ...combination(reactions),
    ...effect(reactions, product),
    ...origin(reactions, product),
  ];
  const all = [...others, ...intensity(reactions, product, others)];
  const index = (id: string) => reactions.findIndex((r) => r.id === id);
  all.sort((a, b) =>
    Math.min(...a.reactions.map(index)) - Math.min(...b.reactions.map(index)) ||
    THINKING_ORDER.indexOf(a.thinking) - THINKING_ORDER.indexOf(b.thinking) ||
    a.row.localeCompare(b.row)
  );
  return all.map((d, i) => ({ id: `d${i + 1}`, ...d }));
}
