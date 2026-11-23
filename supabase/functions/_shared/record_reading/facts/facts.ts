/**
 * The words every part that reads a record shares: the gauges a drink can be
 * asked, the places an aroma is picked, and the levels the catalog keeps.
 */
/** The version a card is stored under. */
export const CARD_ENGINE_VERSION = "card-facts-v3";

/**
 * The gauges of the questionnaire, by the axis each one asks. Which of them a
 * drink is asked, and under which name, is the gauge sheet's
 * (catalog/sensory/gauge-definitions.json).
 */
export const GAUGE_AXES = [
  "sweetness",
  "acidity",
  "umami",
  "body",
  "tannin",
  "sparkling",
  "spice",
  "peat",
  "finish_length",
  "finish_character",
] as const;
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
export type GaugeAxis = typeof GAUGE_AXES[number];
export type AromaStage = typeof AROMA_STAGES[number];
export type LevelDimension = typeof LEVEL_DIMENSIONS[number];

/**
 * The catalog level a gauge is compared with. 감칠맛, 스파이시 and 피트 have
 * no level in the catalog and are never given an estimated one. 끝맛의 인상
 * has one (finish_character), but nearly every bottle that carries it sits on
 * the same step, so the gauge is not compared with it.
 */
export const GAUGE_LEVEL_DIMENSION: Readonly<
  Record<GaugeAxis, LevelDimension | null>
> = {
  sweetness: "sweetness",
  acidity: "acidity",
  umami: null,
  body: "body",
  tannin: "astringency",
  sparkling: "carbonation",
  spice: null,
  peat: null,
  finish_length: "finish_length",
  finish_character: null,
};
