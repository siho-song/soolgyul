/**
 * The fit check as the client sees it: for each requested product, a badge,
 * what it says, and the levels the detail screen draws.
 */
import {
  type CardFacts,
  validateCardFacts,
} from "../taste_card/facts/facts.ts";
import { composeCopy } from "./copy.ts";
import { productFacts, type TasteFitFact } from "./facts.ts";
import { judgeProduct, type TasteFitBadge, type Verdict } from "./judge.ts";
import { buildLedger } from "./ledger.ts";
import { SoolgyulHttpError } from "../http.ts";
import type { TasteFitProductRow, TasteFitRepository } from "./repository.ts";

const TASTE_FIT_SCHEMA_VERSION = "taste-fit-v1";
export const TASTE_FIT_MAX_PRODUCTS = 20;

type TasteFitProductVerdict = {
  product_id: string;
  badge: TasteFitBadge;
  headline: string;
  tags: readonly string[];
  sentence: string;
  levels: Record<string, number>;
  facts: TasteFitFact[];
};

type TasteFitResponse = {
  schema_version: typeof TASTE_FIT_SCHEMA_VERSION;
  has_cards: boolean;
  products: TasteFitProductVerdict[];
};

/** The dimensions the detail screen shows, in display order. */
const SHOWN_LEVELS = [
  "sweetness",
  "acidity",
  "astringency",
  "body",
  "carbonation",
  "finish_length",
] as const;

/** Cards whose facts no longer parse (an older engine) are left out rather than failing the check. */
function parseCards(values: readonly unknown[]): CardFacts[] {
  const cards: CardFacts[] = [];
  for (const value of values) {
    try {
      cards.push(validateCardFacts(value));
    } catch {
      // skipped
    }
  }
  return cards;
}

/**
 * The gauges the detail screen draws: the bottle's stored levels, the same
 * numbers a shop's shelf tag or a back label gives, so a reader can hold the
 * screen against the bottle in front of them. How sweet a wine feels among
 * its own kind is said by the verdict's hashtags and sentence, not here.
 *
 * A whisky shows no sweetness gauge. No sugar is left after distilling, and
 * what tastes sweet is the cask's vanilla and dried fruit; the stored
 * numbers come from sources that disagree on which of the two they mean, so
 * a gauge would state more than is known.
 */
export function shownLevels(
  product: TasteFitProductRow,
): Record<string, number> {
  const levels: Record<string, number> = {};
  for (const dim of SHOWN_LEVELS) {
    if (typeof product.levels[dim] === "number") {
      levels[dim] = product.levels[dim];
    }
  }
  if (product.category_key === "whisky") delete levels.sweetness;
  return levels;
}

export async function judgeProductsForUser(
  repository: TasteFitRepository,
  userId: string,
  productIds: readonly string[],
): Promise<TasteFitResponse> {
  const [reader, facts, rows] = await Promise.all([
    repository.loadReader(userId),
    repository.loadUserCardFacts(userId),
    repository.loadProducts(productIds),
  ]);
  // Like every signed-in endpoint, only an active account is answered.
  if (!reader.active) {
    throw new SoolgyulHttpError(403, "active_account_required");
  }
  const readerName = reader.display_name;
  const cards = parseCards(facts);
  const ledger = buildLedger(cards);
  const byId = new Map(rows.map((row) => [row.id, row]));
  const products = productIds.map((id): TasteFitProductVerdict => {
    const row = byId.get(id);
    if (!row) {
      const missing: Verdict = {
        badge: "no_info",
        unjudged: "no_data",
        group: null,
        reasons: [],
        aromas: [],
      };
      return {
        product_id: id,
        ...composeCopy(missing, readerName),
        badge: "no_info",
        levels: {},
        facts: [],
      };
    }
    const verdict = judgeProduct(row, ledger);
    return {
      product_id: id,
      badge: verdict.badge,
      ...composeCopy(verdict, readerName),
      levels: shownLevels(row),
      facts: productFacts(row),
    };
  });
  return {
    schema_version: TASTE_FIT_SCHEMA_VERSION,
    has_cards: cards.length > 0,
    products,
  };
}
