// One record as the card engine reads it: the reader's gauges and aromas and
// the product they were about. record/record_builder.ts builds it from a request and
// the catalog; facts/reading.ts turns it into card facts.
import type { AlcoholCategory } from "../../contract.ts";
import type { AromaStage, GaugeAxis } from "../facts/facts.ts";

export type SensoryScore = 1 | 2 | 3 | 4 | 5;
export type SensoryDimension =
  | "sweetness"
  | "acidity"
  | "bitterness"
  | "body"
  | "viscosity"
  | "astringency"
  | "carbonation"
  | "alcohol_presence"
  | "aroma_intensity"
  | "flavour_clarity"
  | "finish_length"
  | "finish_cleanliness";

/** One gauge the reader set: the step felt, and how it was taken. */
export type SensoryGauge = {
  axis: GaugeAxis;
  level: SensoryScore;
  reaction: "liked" | "burden";
  answerRef: string;
};

/** One aroma picked in one of the three pickers, and how it was taken. */
export type SensoryAroma = {
  stage: AromaStage;
  key: string;
  reaction: "liked" | "burden";
  answerRef: string;
};

export type SensoryProductDescriptor = {
  key: string;
  label: string;
  section: "aroma" | "palate" | "texture" | "finish";
  family: string;
  traits: readonly string[];
  description: string | null;
  evidenceRefs: readonly string[];
};

export type SensoryProduct = {
  name: string;
  /** null when the catalog item carries no category key. */
  category: AlcoholCategory | null;
  styleKey: string | null;
  /** The catalog region path, e.g. "샹빠뉴(Champagne) > 꼬뜨 데 블랑(Côte des Blancs)". */
  region?: string | null;
  abv: number | null;
  ingredients?: readonly string[];
  /** Grape varieties the catalog states for a wine, main grape first. */
  grapeVarietyKeys?: readonly string[];
  /** Production process keys of the product, when the catalog states them. */
  processes?: readonly string[];
  levels: Readonly<Partial<Record<SensoryDimension, SensoryScore>>>;
  levelRefs?: Readonly<Partial<Record<SensoryDimension, readonly string[]>>>;
  /**
   * Where each level came from (the catalog's level_sources grades): a value
   * read for this bottle or one copied from the kind's table.
   */
  levelSources?: Readonly<Partial<Record<SensoryDimension, number>>>;
  descriptors: readonly SensoryProductDescriptor[];
};

export type SensoryRecord = {
  recordRef: string;
  product: SensoryProduct;
  revisit: {
    intent:
      | "want_again"
      | "would_accept_again"
      | "do_not_want_again"
      | "unknown"
      | null;
    answerRefs: readonly string[];
  };
  /** The answered gauges the drink is asked, in the order of the axes. */
  gauges: readonly SensoryGauge[];
  /** The picked aromas: nose, palate, finish, each in key order. */
  aromas: readonly SensoryAroma[];
};
