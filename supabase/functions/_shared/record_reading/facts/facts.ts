/**
 * The words every part that reads a record shares: the gauges a drink can be
 * asked, the places an aroma is picked, and the levels the catalog keeps.
 */
import { GAUGE_AXIS_NAMES } from "../dictionary/gauges.ts";
/** The version a card is stored under. */
export const CARD_ENGINE_VERSION = "card-facts-v3";

/**
 * The gauges of the questionnaire, by the axis each one asks, in the order a
 * record keeps its answers. Which of them a drink is asked, and under which
 * name, is the gauge sheet's (catalog/sensory/gauge-definitions.json), which
 * lists the axes too: the type is written here for the compiler, and a test
 * holds it to the sheet.
 */
export type GaugeAxis =
  | "sweetness"
  | "acidity"
  | "umami"
  | "body"
  | "tannin"
  | "sparkling"
  | "spice"
  | "peat"
  | "finish_length"
  | "finish_character";
export const GAUGE_AXES: readonly GaugeAxis[] = GAUGE_AXIS_NAMES.map((a) =>
  a.axis
);
/** Where an aroma was picked: by the nose, in the mouth, after swallowing. */
export const AROMA_STAGES = ["nose", "palate", "finish"] as const;
export const LEVEL_DIMENSIONS = [
  "sweetness",
  "acidity",
  "bitterness",
  "body",
  "astringency",
  "viscosity",
  "carbonation",
  "alcohol_presence",
  "aroma_intensity",
  "flavour_clarity",
  "finish_length",
  "finish_character",
] as const;
export type AromaStage = typeof AROMA_STAGES[number];
export type LevelDimension = typeof LEVEL_DIMENSIONS[number];

const CATALOG_NAME: ReadonlyMap<GaugeAxis, string> = new Map(
  GAUGE_AXIS_NAMES.map((a) => [a.axis, a.catalog]),
);
const GAUGE_OF_NAME: ReadonlyMap<string, GaugeAxis> = new Map(
  GAUGE_AXIS_NAMES.map((a) => [a.catalog, a.axis]),
);

/** A gauge's axis as the catalog and the dictionary name it: tannin is astringency there. */
export function catalogAxis(axis: GaugeAxis): string {
  return CATALOG_NAME.get(axis) ?? axis;
}

/** The gauge an axis of the catalog or the dictionary is asked on; a name no gauge is drawn from stays as it is. */
export function gaugeOf(catalogName: string): GaugeAxis {
  return GAUGE_OF_NAME.get(catalogName) ?? catalogName as GaugeAxis;
}

/** The level the catalog keeps of a gauge's axis; null for 감칠맛, 스파이시 and 피트, which it keeps none of. */
export function catalogLevelOf(axis: GaugeAxis): LevelDimension | null {
  const name = catalogAxis(axis);
  return LEVEL_DIMENSIONS.find((dimension) => dimension === name) ?? null;
}

/**
 * The catalog level a gauge is compared with. 감칠맛, 스파이시 and 피트 have
 * no level in the catalog and are never given an estimated one. 끝맛의 인상
 * has one (finish_character), but nearly every bottle that carries it sits on
 * the same step, so the gauge is not compared with it.
 */
export const GAUGE_LEVEL_DIMENSION: Readonly<
  Record<GaugeAxis, LevelDimension | null>
> = Object.fromEntries(
  GAUGE_AXES.map((axis) => [
    axis,
    axis === "finish_character" ? null : catalogLevelOf(axis),
  ]),
) as Record<GaugeAxis, LevelDimension | null>;
