/**
 * Alcohol presence read from the bottle's ABV. The heat a drink leaves is its
 * strength, and every kind has its own usual strength: 40% is ordinary for a
 * whisky and far above any wine. So the level places the ABV on the kind's
 * five bands on the dictionary's category and kind rows (매우 낮음 1 · 낮음 2 · 중간 3 ·
 * 높음 4 · 매우 높음 5), whose edges come from legal minimums and trade
 * conventions, by style when the table has the style and by category
 * otherwise. The number is a reading of this bottle, never a copy from the
 * kind, so it is never marked estimated.
 */
import { abvBands } from "../dictionary/dictionary.ts";

// The ABV is the maker's own statement: grade 1 evidence for alcohol presence.
type AbvLevel = 1 | 2 | 3 | 4 | 5;
type Bands = { bounds: readonly number[]; verified: boolean; source: string };
const TABLE = abvBands as unknown as {
  styles: Record<string, Bands>;
  categories: Record<string, Bands>;
};

/** The bands the bottle is placed on, and whose they are. */
export function abvBandsFor(
  styleKey: string | null | undefined,
  category: string | null | undefined,
): { scope: string; bands: Bands } | null {
  if (styleKey && TABLE.styles[styleKey]) {
    return { scope: styleKey, bands: TABLE.styles[styleKey] };
  }
  if (category && TABLE.categories[category]) {
    return { scope: category, bands: TABLE.categories[category] };
  }
  return null;
}

export function alcoholLevelFromAbv(
  abv: number | null | undefined,
  styleKey: string | null | undefined,
  category: string | null | undefined,
): { level: AbvLevel; scope: string } | null {
  if (typeof abv !== "number" || !Number.isFinite(abv)) return null;
  const found = abvBandsFor(styleKey, category);
  if (!found) return null;
  let level = 1;
  for (const edge of found.bands.bounds) if (abv >= edge) level++;
  return { level: level as AbvLevel, scope: found.scope };
}
