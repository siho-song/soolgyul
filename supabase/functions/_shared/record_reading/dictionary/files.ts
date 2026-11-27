// The dictionary's files as they are written (catalog/dictionary): one file
// per drink, holding all about that drink (its kinds, styles, grapes,
// producers, label words, places and making), and the words for what is
// sensed, which every drink shares. A row holds values and links to other
// rows by key. A place or a making row two drinks share sits in both files
// under one key, with the same names; what it says of each drink is that
// drink's own.
//
// Only the dictionary folder reads the files. Everything else asks
// dictionary.ts, aromas.ts and term_help.ts; the card's evidence, which
// weighs one bottle against its own drink's file, reads a drink's rows
// through drinkFile.
import wine from "../../../../../catalog/dictionary/wine.json" with {
  type: "json",
};
import whisky from "../../../../../catalog/dictionary/whisky.json" with {
  type: "json",
};
import sake from "../../../../../catalog/dictionary/sake.json" with {
  type: "json",
};
import koreanTraditional from "../../../../../catalog/dictionary/korean_traditional.json" with {
  type: "json",
};
import sensesFile from "../../../../../catalog/dictionary/senses.json" with {
  type: "json",
};

export type Level = number | string | null;
export type Taste = Record<string, Level>;
export type Aromas = Record<string, string[]>;

export type Axis = {
  key: string;
  ko: string;
  asked_as?: string;
  only_for?: Record<string, string[]>;
  steps: string[];
};

export type Abv = { bounds?: number[]; range?: number[]; bounds_from?: string };

export type StyleNode = {
  key: string;
  ko: string;
  label?: string;
  summary: string | null;
  place: string | null;
  find?: string[];
  find_not?: string[];
  find_in_places?: string[];
  color?: string;
  also_of_kinds?: string[];
  grapes: string[];
  grapes_by_rule?: boolean;
  making: string[];
  making_by_rule?: boolean;
  taste?: Taste;
  aroma_strength?: Level;
  aromas?: Aromas;
  replaces_aromas?: string[];
};

export type KindNode = {
  key: string;
  ko: string;
  en?: string;
  label?: string;
  /** Other names it goes by. */
  find?: string[];
  /** Words its bottles print that are not its name (demi-sec on a sparkling wine). */
  on_labels?: string[];
  summary: string | null;
  abv?: Abv;
  taste?: Taste;
  aroma_strength?: Level;
  aromas?: Aromas;
  /** Why it tastes so, in a sentence or two. */
  why?: string;
  styles: StyleNode[];
};

export type GrapeNode = {
  key: string;
  ko: string;
  /** Other keys the catalog writes the same grape with (touriga, macabeu). */
  also_keys?: string[];
  label?: string;
  find?: string[];
  on_labels?: string[];
  colors?: string[];
  summary: string | null;
  styles?: string[];
  abv?: Abv;
  taste?: Taste;
  aroma_strength?: Level;
  aromas?: Aromas;
  replaces_aromas?: string[];
  /** Why it tastes so, in a sentence or two. */
  why?: string;
  /** What it is like from a cooler and from a warmer place. */
  by_climate?: {
    cooler: string;
    warmer: string;
    strength: Strength;
    line: string;
    /** The climate its warmer side begins at; "warm" unless said. */
    warmer_from?: string;
  };
};

export type Strength = "strong" | "mid" | "weak";

/**
 * What two things a bottle has do together (two casks, two grapes of a
 * blend, a kind and what it is made of), or what one thing does past an age
 * or a strength, or on some kinds.
 */
export type Relation = {
  /** The rows it is of, by key: making rows, grapes, kinds. */
  of: string[];
  /** support, mask, oppose, contrast. */
  how: string[];
  /** The axes it speaks of. */
  on: string[];
  strength: Strength;
  effect: string;
  when?: string;
  age_from?: number;
  abv_from?: number;
  kinds?: string[];
  line: string;
};

export type ProducerNode = {
  key: string;
  ko: string;
  en?: string;
  kind?: string;
  country?: string;
  region?: string;
  summary: string | null;
  peat?: string | null;
  /** An independent bottler or a blending house: not a cause of a taste. */
  bottler?: boolean;
  house_casks?: string[];
  taste?: Taste;
  aroma_strength?: Level;
  aromas?: Aromas;
  /** Why the maker's bottles taste so: its house style. */
  why?: string;
};

export type LabelWordNode = {
  key: string;
  ko: string;
  label?: string;
  find?: string[];
  summary?: string | null;
  explained_by?: string;
  /** The kinds the word means this in (섹 is dry on a still wine, off-dry on a sparkling one). */
  kinds?: string[];
  /** A grade of the grapes' ripeness at harvest (Kabinett), not of the wine's sugar. */
  ripeness_grade?: boolean;
  /**
   * Where the sweetness a wine's word tells of comes from: the grapes' sugar
   * was concentrated (late harvest, noble rot, frozen or dried grapes), the
   * word is a term for how much sugar is left, sugar was added at bottling
   * (a sparkling wine's dosage), or spirit stopped the fermentation.
   */
  sweetness_from?: "concentration" | "term" | "dosage" | "fortification";
  taste?: Taste;
  aromas?: Aromas;
  /** Why a bottle with the word tastes so. */
  why?: string;
};

/** A whisky's age band and what the years change against its kind. */
export type AgeNode = {
  key: string;
  ko: string;
  kinds: string[];
  years: [number | null, number | null];
  summary?: string;
  taste_change?: Record<string, "up" | "down" | "same">;
  aromas_more?: string[];
  aromas_less?: string[];
};

export type DrinkFile = {
  key: string;
  ko: string;
  en: string;
  abv: Abv;
  axes: Axis[];
  kinds: KindNode[];
  grapes?: GrapeNode[];
  producers: ProducerNode[];
  label_words: LabelWordNode[];
  ages?: AgeNode[];
  /** The places its bottles come from, with the places above them. */
  places: PlaceNode[];
  /** Its ingredients, processes and maturations, by part. */
  making: Record<string, TagGroup[]>;
  relations?: Relation[];
};

export type PlaceNode = {
  key: string;
  ko: string;
  en?: string;
  aliases?: string[];
  summary: string | null;
  climate?: string | null;
  places?: PlaceNode[];
};

export type TagNode = {
  key: string;
  ko: string;
  en?: string;
  label?: string;
  find?: string[];
  on_labels?: string[];
  summary: string | null;
  stage?: string;
  /** What it does to this drink. */
  taste?: Taste;
  aroma_strength?: Level;
  aromas?: Aromas;
  /** The aromas the making always leaves, among its aromas. */
  always?: string[];
  /** Every bottle of the drink is made so: it tells no bottle from another. */
  given?: boolean;
  /** Why it tastes so, in a sentence or two. */
  why?: string;
};

export type TagGroup = {
  key: string;
  ko: string;
  en?: string;
  find?: string[];
  items: TagNode[];
};

export type Pending = { label: string; reason: string };

export type Choice = {
  order: number;
  group: string;
  said_of?: string[];
  found_by?: string[];
};

export type WordNode = {
  key: string;
  ko: string;
  en?: string;
  aliases?: string[];
  summary: string | null;
  traits?: string[];
  said_of?: string[];
  choice?: Choice;
  search?: string[];
  search_related?: string[];
  shown_as?: string | null;
  pending?: Pending;
  old_keys?: string[];
  meaning_only?: boolean;
  words?: WordNode[];
};

export type FamilyNode = {
  key: string;
  ko: string;
  of: "descriptor" | "texture" | "finish_character";
  kind?: string;
  summary: string | null;
  traits?: string[];
  pending?: Pending;
  words: WordNode[];
};

export type SensesFile = {
  choice: {
    version: string;
    taxonomy_version: string;
    groups: { key: string; ko: string }[];
  };
  /** The senses a drink's taste axes are of: their own name and what they are. */
  axes: {
    key: string;
    ko: string;
    en?: string;
    summary: string | null;
    traits?: string[];
  }[];
  families: FamilyNode[];
  words_of_no_family: Record<string, WordNode[]>;
  traits: { key: string; ko: string; summary: string }[];
};

export const DRINKS = [
  wine,
  whisky,
  sake,
  koreanTraditional,
] as unknown as DrinkFile[];
export const SENSES = sensesFile as unknown as SensesFile;

/** A drink's file as it is: its kinds, styles, grapes, producers, label words, places and making. */
export function drinkFile(key: string): DrinkFile | null {
  return DRINKS.find((d) => d.key === key) ?? null;
}
