/**
 * The kind's table, read at card time for a level nobody read off the bottle.
 *
 * The catalog keeps only levels that were read for the bottle (a retailer
 * scale, a tasting note, the reader's own answer). Where a bottle has no such
 * value, the dictionary's row of its kind still says what the kind is
 * usually like, and that is what the card may speak of as the
 * kind ("이런 종류는 보통 …"), never as a fact about this bottle. The source
 * word `table` marks every level filled here, so the card treats it as an
 * estimate.
 */
import { TASTING_LEVEL_COLUMNS } from "../../database/bottles.ts";
import { kindByKey } from "../dictionary/dictionary.ts";
/**
 * The levels a kind is described by: the level columns of a tasting profile.
 * Alcohol presence is not among them: the card reads it from the bottle's
 * ABV (abv_levels.ts).
 */
export type TableDimension = (typeof TASTING_LEVEL_COLUMNS)[number];
type TableLevel = 1 | 2 | 3 | 4;

const LEVEL_OF_TRAIT: Readonly<Record<string, TableLevel>> = {
  none: 1,
  low: 2,
  mid: 3,
  high: 4,
};

/** What the dictionary says a kind is usually like, or nothing for an unknown kind. */
export function tableLevels(
  styleKey: string | null | undefined,
): Partial<Record<TableDimension, TableLevel>> {
  const levels: Partial<Record<TableDimension, TableLevel>> = {};
  const taste = kindByKey(styleKey)?.taste ?? {};
  for (const dimension of TASTING_LEVEL_COLUMNS) {
    const level = LEVEL_OF_TRAIT[taste[dimension]?.level ?? ""];
    if (level) levels[dimension] = level;
  }
  return levels;
}
