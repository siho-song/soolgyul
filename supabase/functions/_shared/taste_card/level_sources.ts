/**
 * The grade of the evidence behind a level, as the catalog's level_sources
 * column stores it (docs/specs/SENSORY_LEVEL_SOURCE_GRADES.md):
 * 1 the maker's own statement, 2 an outside rating of this bottle,
 * 3 aggregated user votes or reader answers, 4 a kind-level estimate
 * (the kind's table, a style or category median, a sibling product, a fill).
 */
export type LevelSourceGrade = 1 | 2 | 3 | 4;

export const KIND_ESTIMATE_GRADE: LevelSourceGrade = 4;

/** True when the number was copied from the kind, not read for the bottle. */
export function isEstimatedLevelSource(
  grade: number | null | undefined,
): boolean {
  return grade === KIND_ESTIMATE_GRADE;
}
