/**
 * The reader's taste ledger: every explanation a saved card found, kept as
 * "in a drink that is like this, this sensation was comfortable / a burden".
 *
 * A card's finding names the knowledge row that explained a reaction and the
 * conditions it held under (the bottle's levels, the aroma family). Only
 * findings whose condition can be read off another bottle's data carry over:
 * a row about a level band, a finish that keeps a strong sensation, a masker
 * strong enough to cover, a pairing of two sensations, or an aroma family.
 * Rows about origin, distinction between two aromas, or a mid band say
 * nothing a search result can be checked against, so they stay out.
 *
 * A 적당했어요 answer is kept too, as a "fine" entry: the band the bottle had
 * on that dimension is one the reader found comfortable. It never outranks a
 * like or a burden on the same dimension; it only speaks when neither does.
 */
import type {
  CardFacts,
  Finding,
  ReactionFact,
} from "../taste_card/facts/facts.ts";
import { EFFECT_ROWS } from "../taste_card/findings/knowledge.ts";

type Band = "low" | "mid" | "high";
/** `mid+` accepts mid or high: the pairing rows only need the sensation present. */
type Want = Band | "mid+";

export type LedgerEntry = {
  /** A knowledge row, or `fine_<dimension>` for a 적당했어요 answer. */
  row: string;
  polarity: "positive" | "burden" | "fine";
  /** Level bands the candidate must sit in, by tasting-profile dimension. */
  cond: Record<string, Want>;
  /** Aroma tree nodes one of the candidate's aroma tags must hang under. */
  aromas: readonly string[] | null;
  /** The dimensions (or aroma row) this entry speaks about; conflicts resolve per subject. */
  subjects: readonly string[];
  /** How many findings across the reader's cards said this. */
  count: number;
};

/** Reaction subject key → tasting-profile dimension it is read on. */
const DIM_OF: Record<string, string> = {
  acidity: "acidity",
  sweetness: "sweetness",
  drying: "astringency",
  heavy: "body",
  light: "body",
  bubbles: "carbonation",
  warmth: "alcohol_presence",
  persistence: "finish_length",
  clean: "finish_cleanliness",
  aroma: "aroma_intensity",
  aroma_echo: "aroma_intensity",
};

/** Dimensions a 적당했어요 answer carries over, in the order the tags show. */
const FINE_DIMENSIONS = [
  "sweetness",
  "acidity",
  "astringency",
  "body",
  "carbonation",
  "alcohol_presence",
  "finish_length",
] as const;
export type FineDimension = typeof FINE_DIMENSIONS[number];

/** Dimensions a candidate bottle can be checked on. */
const LEDGER_DIMENSIONS = [
  "sweetness",
  "acidity",
  "astringency",
  "body",
  "carbonation",
  "alcohol_presence",
  "finish_length",
  "finish_cleanliness",
  "aroma_intensity",
] as const;

const COMBINATION_CONDITIONS: Record<
  string,
  { cond: Record<string, Want>; aromas: readonly string[] | null }
> = {
  combination_sweet_acid: {
    cond: { sweetness: "mid+", acidity: "mid+" },
    aromas: null,
  },
  combination_sweet_heavy: {
    cond: { sweetness: "high", body: "high" },
    aromas: null,
  },
  combination_acid_fizz: {
    cond: { acidity: "high", carbonation: "high" },
    aromas: null,
  },
  combination_acid_fizz_burden: {
    cond: { acidity: "high", carbonation: "high" },
    aromas: null,
  },
  combination_fruit_scent_acidity: {
    cond: { acidity: "mid+" },
    aromas: ["fruit"],
  },
  combination_sweet_scent_sweetness: {
    cond: { sweetness: "mid+" },
    aromas: ["sweet_aromatic"],
  },
};

export function band(level: number): Band {
  return level >= 4 ? "high" : level <= 2 ? "low" : "mid";
}

function cardLevels(facts: CardFacts): Record<string, number> {
  const levels: Record<string, number> = {};
  for (const fact of facts.product_facts) {
    if (fact.fact.type === "level") {
      levels[fact.fact.dimension] = fact.fact.level;
    }
  }
  return levels;
}

/** The ledger entry one finding contributes, or null when its row carries no checkable condition. */
function ledgerEntryFor(
  finding: Finding,
  facts: CardFacts,
): Omit<LedgerEntry, "count"> | null {
  const { row, polarity, thinking } = finding;
  const levels = cardLevels(facts);
  const cond: Record<string, Want> = {};
  let aromas: readonly string[] | null = null;
  for (const given of finding.conclusion.given) {
    if (
      given.type === "level" &&
      (LEDGER_DIMENSIONS as readonly string[]).includes(given.dimension)
    ) {
      cond[given.dimension] = given.is;
    }
  }
  for (const subject of finding.conclusion.subjects) {
    if (subject.domain === "aroma") continue;
    const dim = DIM_OF[subject.key];
    if (dim && !(dim in cond) && levels[dim] !== undefined) {
      cond[dim] = band(levels[dim]);
    }
  }
  const first = Object.keys(cond)[0];
  let subjects: readonly string[];
  switch (thinking) {
    case "effect": {
      const effect =
        (EFFECT_ROWS as Record<string, { nodes: readonly string[] }>)[row];
      if (!effect) return null;
      aromas = effect.nodes;
      subjects = [row];
      break;
    }
    case "intensity": {
      if (
        !first || cond[first] === "mid" ||
        !["liked_much", "burden_much"].includes(finding.frame)
      ) return null;
      subjects = [first];
      break;
    }
    case "exposure": {
      const shown = row.split("_by_")[0].replace("exposure_", "");
      const dim = DIM_OF[shown];
      if (
        shown.endsWith("bitterness") || !first || (dim && cond[dim] === "mid")
      ) {
        return null;
      }
      subjects = [dim ?? row];
      break;
    }
    case "masking": {
      const masker = row.split("_")[1];
      const dim = DIM_OF[masker];
      if (Object.keys(cond).length < 2 || (dim && cond[dim] !== "high")) {
        return null;
      }
      subjects = [dim ?? row];
      break;
    }
    case "combination": {
      const fixed = COMBINATION_CONDITIONS[row];
      if (!fixed) return null;
      for (const key of Object.keys(cond)) delete cond[key];
      Object.assign(cond, fixed.cond);
      aromas = fixed.aromas;
      subjects = Object.keys(cond);
      break;
    }
    case "persistence": {
      for (const key of Object.keys(cond)) delete cond[key];
      if (row === "persistence_clean") {
        cond.finish_cleanliness = "high";
        subjects = ["finish_cleanliness"];
        break;
      }
      const dim = DIM_OF[row.replace("persistence_", "")];
      if (!dim || levels[dim] === undefined || band(levels[dim]) !== "high") {
        return null;
      }
      cond[dim] = "high";
      cond.finish_length = "high";
      subjects = [dim];
      break;
    }
    default:
      return null;
  }
  return { row, polarity, cond, aromas, subjects };
}

function entryKey(entry: Omit<LedgerEntry, "count">): string {
  const cond = Object.keys(entry.cond).sort().map((k) =>
    `${k}=${entry.cond[k]}`
  );
  return [
    entry.row,
    entry.polarity,
    cond.join(","),
    entry.aromas?.join("|") ?? "",
  ]
    .join("#");
}

/** The fine entries of one card: each 적당했어요 answer whose dimension the bottle has a level for. */
function fineEntriesFor(
  facts: CardFacts,
): Omit<LedgerEntry, "count">[] {
  const levels = cardLevels(facts);
  const seen = new Set<string>();
  const out: Omit<LedgerEntry, "count">[] = [];
  const isFine = (r: ReactionFact) => r.reaction === "fine";
  for (const reaction of facts.reactions.filter(isFine)) {
    if (reaction.subject.domain === "aroma") continue;
    const dim = DIM_OF[reaction.subject.key];
    if (
      !dim || seen.has(dim) || levels[dim] === undefined ||
      !(FINE_DIMENSIONS as readonly string[]).includes(dim)
    ) continue;
    seen.add(dim);
    out.push({
      row: `fine_${dim}`,
      polarity: "fine",
      cond: { [dim]: band(levels[dim]) },
      aromas: null,
      subjects: [dim],
    });
  }
  return out;
}

function cardEntries(card: CardFacts): Omit<LedgerEntry, "count">[] {
  return [
    ...card.findings.flatMap((finding) => {
      const entry = ledgerEntryFor(finding, card);
      return entry ? [entry] : [];
    }),
    ...fineEntriesFor(card),
  ];
}

/** Every card's findings and 적당했어요 answers folded into one ledger; equal entries add up. */
export function buildLedger(cards: readonly CardFacts[]): LedgerEntry[] {
  const ledger = new Map<string, LedgerEntry>();
  for (const card of cards) {
    for (const entry of cardEntries(card)) {
      const key = entryKey(entry);
      const existing = ledger.get(key);
      if (existing) existing.count += 1;
      else ledger.set(key, { ...entry, count: 1 });
    }
  }
  return [...ledger.values()];
}
