// One record as the card engine reads it: the reader's normalized answers and
// the product they were about. record/record_builder.ts builds it from a request and
// the catalog; facts/reading.ts turns it into card facts.
import type { AlcoholCategory } from "../../contract.ts";

export type SensoryDomain = "aroma" | "taste" | "mouthfeel" | "finish";
export type SensoryScore = 1 | 2 | 3 | 4 | 5;
export type SensoryPhase =
  | "opening"
  | "mid"
  | "finish"
  | "overall"
  | "not_applicable";
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

export type SensoryAnswer = {
  key: string;
  label: string;
  domain: SensoryDomain;
  phase: SensoryPhase;
  observations: readonly SensoryObservation[];
  /** neutral: 적당했어요, an evaluation with no direction (2026-10-25). */
  reaction: "positive" | "burden" | "neutral" | "none" | "mixed";
  reasons: readonly string[];
  family: string;
  traits: readonly string[];
  description?: string | null;
  answerRefs: readonly string[];
  reasonRefs: readonly string[];
};

/** Explicit observations, not product attributes or inferred preferences. */
export type SensoryObservation = {
  meaning:
    | "noticed"
    | "gentleIntensity"
    | "pronouncedIntensity"
    | "excessiveIntensity"
    | "wantsMoreIntensity"
    | "harmonious"
    | "masksOtherSensations"
    | "disharmonious"
    | "pleasantPersistence"
    | "quickClearing"
    | "tooBrief"
    | "heavyResidue"
    | "lingeringAroma"
    | "lingeringOffFlavor";
  answerRefs: readonly string[];
};

export type SensoryResponseState = {
  sectionStates: Readonly<
    Record<SensoryDomain, {
      state: "answered" | "unknown" | "unanswered";
      answerRefs: readonly string[];
    }>
  >;
  revisit: {
    intent:
      | "want_again"
      | "would_accept_again"
      | "do_not_want_again"
      | "unknown"
      | null;
    answerRefs: readonly string[];
  };
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

export type SensoryRecord = SensoryResponseState & {
  recordRef: string;
  product: SensoryProduct;
  answers: readonly SensoryAnswer[];
};
