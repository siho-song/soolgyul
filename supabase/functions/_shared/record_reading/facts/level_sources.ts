/**
 * Where a level came from, as the catalog's level_sources column stores it
 * (docs/specs/SENSORY_LEVEL_SOURCE_GRADES.md): 1 read for this bottle, 4
 * copied from its kind (the kind's table, a style or category median, a
 * sibling product, a fill). Rows written before the split was reduced to two
 * may still hold 2 or 3; they read as 1.
 */
type LevelSourceGrade = 1 | 4;

const KIND_ESTIMATE_GRADE: LevelSourceGrade = 4;

/** True when the number was copied from the kind, not read for the bottle. */
export function isEstimatedLevelSource(
  grade: number | null | undefined,
): boolean {
  return grade === KIND_ESTIMATE_GRADE;
}
