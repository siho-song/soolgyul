/**
 * How much a card says: every cap on what is chosen and written, in one
 * place. What a card may say of a name by the catalog's bottles is another
 * matter and is kept in facts/name_counts.ts.
 */

/** A reason section tells this many reasons at most, a line each. */
export const LINES_PER_SECTION = 2;

/** A card carries this many tags at most. */
export const TAGS_PER_CARD = 3;

/** 다음 방향 names this many things to look for again at most … */
export const NEXT_NAMES_KEPT = 3;
/** … this many of them causes of the liked reasons … */
export const NEXT_CAUSES_KEPT = 2;
/** … and this many of the bottle's own names as what gave the minded taste. */
export const NEXT_OWN_NAMES = 2;
