/**
 * The kind's table, read at card time for a level nobody read off the bottle.
 *
 * The catalog keeps only levels that were read for the bottle (a retailer
 * scale, a tasting note, the reader's own answer). Where a bottle has no such
 * value, the style table (catalog/sensory/style-profiles.json) still says what
 * the kind is usually like, and that is what the card may speak of as the
 * kind ("이런 종류는 보통 …"), never as a fact about this bottle. The source
 * word `table` marks every level filled here, so card_reading treats it as an
 * estimate.
 */
import { styleProfiles } from "../dictionary/dictionary.ts";
/**
 * Dimensions the style table describes and the card asks about. Alcohol
 * presence is not among them: the card reads it from the bottle's ABV
 * (abv_levels.ts).
 */
const TABLE_DIMENSIONS = [
  "sweetness",
  "acidity",
  "bitterness",
  "astringency",
  "body",
  "carbonation",
  "aroma_intensity",
  "finish_length",
  "finish_cleanliness",
] as const;
export type TableDimension = (typeof TABLE_DIMENSIONS)[number];
type TableLevel = 1 | 2 | 3 | 4;

const LEVEL_OF_TRAIT: Readonly<Record<string, TableLevel>> = {
  none: 1,
  low: 2,
  mid: 3,
  high: 4,
};

type StyleRow = {
  key: string;
  traits?: Record<string, { level?: string } | undefined>;
};

const TABLE: ReadonlyMap<string, Partial<Record<TableDimension, TableLevel>>> =
  new Map(
    (styleProfiles as unknown as { styles: StyleRow[] }).styles.map((style) => {
      const levels: Partial<Record<TableDimension, TableLevel>> = {};
      for (const dimension of TABLE_DIMENSIONS) {
        const level = LEVEL_OF_TRAIT[style.traits?.[dimension]?.level ?? ""];
        if (level) levels[dimension] = level;
      }
      return [style.key, levels];
    }),
  );

/** What the table says about a style, or nothing for an unknown style. */
export function tableLevels(
  styleKey: string | null | undefined,
): Partial<Record<TableDimension, TableLevel>> {
  return (styleKey && TABLE.get(styleKey)) || {};
}
