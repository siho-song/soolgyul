/**
 * The fit check as the client sees it: for each requested product, a badge,
 * what it says, and the levels the detail screen draws.
 */
import {
  type CardFacts,
  validateCardFacts,
} from "../taste_card/facts/facts.ts";
import { hasFeltSweetness } from "../taste_card/facts/felt_sweetness.ts";
import { placeOfSweetness } from "../taste_card/facts/kind_place.ts";
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
 * The gauges the detail screen draws. They are the bottle's stored levels,
 * with two exceptions about sweetness:
 *
 * - a whisky shows none. No sugar is left after distilling, and what tastes
 *   sweet is the cask's vanilla and dried fruit; the stored numbers come
 *   from sources that disagree on which of the two they mean, so a gauge
 *   would state more than is known. The verdict's hashtags still say how
 *   sweet the bottle feels among whiskies.
 * - a still wine shows how sweet it feels among its own kind
 *   (Place.standing on the 1 to 5 scale), because the stored number is 1
 *   for nine red wines in ten and tells them apart no further. A wine stored
 *   as sweet still stands above every dry one.
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
  if (product.category_key === "whisky") {
    delete levels.sweetness;
  } else if (hasFeltSweetness(product.style_key)) {
    const place = placeOfSweetness(product);
    if (place) {
      levels.sweetness = Math.min(
        5,
        Math.max(1, Math.round(1 + 4 * place.standing)),
      );
    }
  }
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
