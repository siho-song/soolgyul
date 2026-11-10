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
import { judgeProduct, type TasteFitBadge } from "./judge.ts";
import { buildLedger } from "./ledger.ts";
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

function shownLevels(product: TasteFitProductRow): Record<string, number> {
  const levels: Record<string, number> = {};
  for (const dim of SHOWN_LEVELS) {
    if (typeof product.levels[dim] === "number") {
      levels[dim] = product.levels[dim];
    }
  }
  return levels;
}

export async function judgeProductsForUser(
  repository: TasteFitRepository,
  userId: string,
  productIds: readonly string[],
): Promise<TasteFitResponse> {
  const [readerName, facts, rows] = await Promise.all([
    repository.loadDisplayName(userId),
    repository.loadUserCardFacts(userId),
    repository.loadProducts(productIds),
  ]);
  const cards = parseCards(facts);
  const ledger = buildLedger(cards);
  const byId = new Map(rows.map((row) => [row.id, row]));
  const products = productIds.map((id): TasteFitProductVerdict => {
    const row = byId.get(id);
    if (!row) {
      return {
        product_id: id,
        ...composeCopy("no_info", [], [], readerName),
        badge: "no_info",
        levels: {},
        facts: [],
      };
    }
    const verdict = judgeProduct(row, ledger);
    return {
      product_id: id,
      badge: verdict.badge,
      ...composeCopy(verdict.badge, verdict.hits, verdict.aromas, readerName),
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
