/**
 * Where a bottle's level sits among the bottles of its own kind.
 *
 * The same number says different things in different kinds: sweetness 4 is
 * the commonest whisky and one of the sweetest twentieth of wines, and 86 of
 * 100 wines sit on sweetness 1. The counts are the published catalog's
 * bottles on each level, 1 to 5, read on 2026-11-12 with
 *   select category_key, round(sweetness), count(*) ... group by 1, 2
 * and the same for body. They move slowly; read them again when a kind's
 * mix has changed.
 */
const SPREAD: Readonly<
  Record<string, Readonly<Record<string, readonly number[]>>>
> = {
  sweetness: {
    wine: [37359, 2909, 1024, 1488, 652],
    whisky: [237, 390, 987, 1208, 77],
    sake: [190, 437, 935, 302, 137],
    korean_traditional: [73, 527, 467, 305, 18],
  },
  body: {
    wine: [681, 7335, 16623, 13970, 3960],
    whisky: [13, 437, 903, 1366, 180],
    sake: [43, 774, 658, 451, 75],
    korean_traditional: [38, 310, 425, 467, 150],
  },
};

/**
 * The level's place among its kind on the same 1 to 5 ruler: the middle of
 * the bottles that share the level, counted from the lowest. Null where no
 * counts are kept for the dimension or the kind.
 */
export function placeWithinKind(
  dimension: string,
  category: string | null,
  level: number,
): number | null {
  const counts = category ? SPREAD[dimension]?.[category] : undefined;
  const same = counts?.[level - 1];
  if (!counts || same === undefined) return null;
  const total = counts.reduce((sum, count) => sum + count, 0);
  const below = counts.slice(0, level - 1).reduce(
    (sum, count) => sum + count,
    0,
  );
  return 1 + 4 * (below + same / 2) / total;
}
