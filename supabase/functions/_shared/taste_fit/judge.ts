/**
 * Does this bottle sit where the reader's ledger says a sensation was
 * comfortable or a burden? The bottle's levels (and its ABV read as alcohol
 * presence on its kind's bands) and aroma tags are checked against every
 * ledger entry. When one dimension collects both sides, the more specific
 * explanation wins unless the other side has more cards behind it; an even
 * split drops that dimension, and a like or burden on a dimension silences
 * the reader's 적당했어요 on it. Any remaining burden makes the bottle a
 * caution; otherwise any comfort makes it a match; otherwise a met 적당했어요
 * band makes it plain with that said; a bottle with data that meets no entry
 * is plain; a bottle without data cannot be judged. Each verdict also names
 * up to three of the bottle's aroma tags, the ones under a family the
 * reader liked (match) or minded (caution) first, then the bottle's own
 * leading tags.
 */
import { alcoholLevelFromAbv } from "../taste_card/abv_levels.ts";
import { aromaLine } from "../taste_card/aroma_lineage.ts";
import { band, type LedgerEntry } from "./ledger.ts";

export type TasteFitBadge = "star" | "caution" | "neutral" | "no_info";

export type CandidateProduct = {
  abv_percent: number | null;
  style_key: string | null;
  category_key: string | null;
  /** Tasting-profile levels present on the bottle, 1–5. */
  levels: Readonly<Record<string, number>>;
  aroma_tags: readonly string[];
};

export type Verdict = {
  badge: TasteFitBadge;
  /** Rows shown, most cards first: burden rows for a caution, comfort rows for a match, fine rows for a plain bottle. */
  hits: readonly string[];
  /** Up to three of the bottle's aroma tags, the reader's own families first. */
  aromas: readonly string[];
};

const PROFILE_DIMENSIONS = [
  "sweetness",
  "acidity",
  "astringency",
  "body",
  "carbonation",
  "finish_length",
  "finish_cleanliness",
  "aroma_intensity",
] as const;

/** The bottle's state on every dimension the ledger can ask about. */
export function candidateState(
  product: CandidateProduct,
): Record<string, number> {
  const state: Record<string, number> = {};
  for (const dim of PROFILE_DIMENSIONS) {
    const value = product.levels[dim];
    if (typeof value === "number") state[dim] = value;
  }
  const alcohol = alcoholLevelFromAbv(
    product.abv_percent,
    product.style_key,
    product.category_key,
  );
  if (alcohol) state.alcohol_presence = alcohol.level;
  return state;
}

function matches(
  entry: LedgerEntry,
  state: Record<string, number>,
  tags: readonly string[],
): boolean {
  for (const [dim, want] of Object.entries(entry.cond)) {
    const value = state[dim];
    if (value === undefined) return false;
    if (want === "mid+" ? value < 3 : band(value) !== want) return false;
  }
  if (entry.aromas !== null) {
    const nodes = entry.aromas;
    if (
      !tags.some((tag) => aromaLine(tag).some((name) => nodes.includes(name)))
    ) {
      return false;
    }
  }
  return true;
}

const specificity = (entry: LedgerEntry): number =>
  Object.keys(entry.cond).length + (entry.aromas ? 1 : 0);

const cardsBehind = (
  entries: readonly LedgerEntry[],
  polarity: LedgerEntry["polarity"],
) =>
  entries.filter((e) => e.polarity === polarity).reduce(
    (sum, e) => sum + e.count,
    0,
  );

/** Which side wins a dimension, or null for an even split. */
function winningSide(
  entries: readonly LedgerEntry[],
): LedgerEntry["polarity"] | null {
  const top = Math.max(...entries.map(specificity));
  const specific = entries.filter((e) => specificity(e) === top);
  const positiveTop = cardsBehind(specific, "positive");
  const burdenTop = cardsBehind(specific, "burden");
  const positiveAll = cardsBehind(entries, "positive");
  const burdenAll = cardsBehind(entries, "burden");
  if (positiveTop !== burdenTop) {
    const leader = positiveTop > burdenTop ? "positive" : "burden";
    const opposing = leader === "positive" ? burdenAll : positiveAll;
    if (Math.max(positiveTop, burdenTop) >= opposing) return leader;
  }
  if (positiveAll !== burdenAll) {
    return positiveAll > burdenAll ? "positive" : "burden";
  }
  return null;
}

/** The bottle's aroma tags with those under the entries' families first, at most three. */
function aromasFor(
  tags: readonly string[],
  entries: readonly LedgerEntry[],
): string[] {
  const nodes = entries.flatMap((e) => e.aromas ?? []);
  const own = tags.filter((tag) =>
    aromaLine(tag).some((name) => nodes.includes(name))
  );
  const rest = tags.filter((tag) => !own.includes(tag));
  return [...own, ...rest].slice(0, 3);
}

export function judgeProduct(
  product: CandidateProduct,
  ledger: readonly LedgerEntry[],
): Verdict {
  const state = candidateState(product);
  const tags = product.aroma_tags;
  if (Object.keys(state).length === 0 && tags.length === 0) {
    return { badge: "no_info", hits: [], aromas: [] };
  }
  const hit = ledger.filter((entry) => matches(entry, state, tags));
  const bySubject = new Map<string, LedgerEntry[]>();
  for (const entry of hit) {
    for (const subject of entry.subjects) {
      bySubject.set(subject, [...(bySubject.get(subject) ?? []), entry]);
    }
  }
  const kept = new Set<LedgerEntry>();
  for (const entries of bySubject.values()) {
    const sided = entries.filter((e) => e.polarity !== "fine");
    const winner = sided.length === 0 ? "fine" : winningSide(sided);
    if (winner === null) continue;
    for (const entry of entries) if (entry.polarity === winner) kept.add(entry);
  }
  const byCount = (a: LedgerEntry, b: LedgerEntry) => b.count - a.count;
  const side = (polarity: LedgerEntry["polarity"]) =>
    hit.filter((e) => kept.has(e) && e.polarity === polarity).sort(byCount);
  const burden = side("burden");
  const comfort = side("positive");
  const fine = side("fine");
  const rows = (entries: readonly LedgerEntry[]) =>
    entries.slice(0, 3).map((e) => e.row);
  if (burden.length > 0) {
    return {
      badge: "caution",
      hits: rows(burden),
      aromas: aromasFor(tags, burden),
    };
  }
  if (comfort.length > 0) {
    return {
      badge: "star",
      hits: rows(comfort),
      aromas: aromasFor(tags, comfort),
    };
  }
  return { badge: "neutral", hits: rows(fine), aromas: aromasFor(tags, []) };
}
