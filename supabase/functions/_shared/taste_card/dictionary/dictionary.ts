// The dictionary (catalog/dictionary): one file per drink, holding all about
// that drink (its kinds, styles, grapes, producers, label words, places and
// making), and the words for what is sensed, which every drink shares. A row
// holds values and links to other rows by key. A place or a making row two
// drinks share sits in both files under one key, with the same names; what it
// says of each drink is that drink's own.
//
// Read a place or a making row through placeOf / makingOf, which take the
// drink. The older card code still reads rows as one flat list of typed terms
// and a few tables built from them (style table, aroma catalog, offered
// aromas); there a shared row appears once, as the first drink file holds it.
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

/* -------------------------------------------------------------- the tree */

export type Level = number | string | null;
export type Taste = Record<string, Level>;
export type Aromas = Record<string, string[]>;

type Axis = {
  key: string;
  ko: string;
  asked_as?: string;
  only_for?: Record<string, string[]>;
  steps: string[];
};

type Abv = { bounds?: number[]; range?: number[]; bounds_from?: string };

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

type Pending = { label: string; reason: string };

type Choice = {
  label: string;
  order: number;
  group: string;
  said_of?: string[];
  found_by?: string[];
};

type WordNode = {
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

type FamilyNode = {
  key: string;
  ko: string;
  of: "descriptor" | "texture" | "finish_character";
  kind?: string;
  summary: string | null;
  traits?: string[];
  pending?: Pending;
  words: WordNode[];
};

type SensesFile = {
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

const DRINKS = [
  wine,
  whisky,
  sake,
  koreanTraditional,
] as unknown as DrinkFile[];
const SENSES = sensesFile as unknown as SensesFile;

/** A drink's file as it is: its kinds, styles, grapes, producers, label words, places and making. */
export function drinkFile(key: string): DrinkFile | null {
  return DRINKS.find((d) => d.key === key) ?? null;
}

/* ------------------------------------------------------------- the terms */

/**
 * The dictionary no longer writes why a row has a level or an aroma (reason).
 * The guide still asks for it until it is rewritten on the tree; it finds none.
 */
type Unwritten = { reason?: undefined };

type TermTrait = Unwritten & {
  basis?: undefined;
  /** low, mid or high (none for a drink with no bubbles): the word the file's level stands under. */
  level: string;
  /** The file's level where it states a step from 1 to 5. */
  step?: number;
};

type TermAroma = Unwritten & {
  key: string;
  /** "production": the making always leaves it (피트 처리 맥아 -> 연기), not only often. */
  basis?: "production";
  /** Where the aroma comes from, in the words the card was written with (원료, 통 ...). */
  source_kind?: string;
};

export type Term = {
  key: string;
  type: string;
  parent?: string | null;
  categories?: string[] | string;
  names: {
    ko: string;
    en?: string;
    /** The spelling a bottle label prints (Merlot, 純米大吟醸); a term printed in Korean has none. */
    label?: string;
    aliases?: string[];
    label_patterns?: string[];
  };
  summary?: string;
  taste?: Record<string, TermTrait>;
  aromas?: TermAroma[];
  hints?: Record<string, unknown>;
  traits?: string[];
  extra?: Record<string, unknown>;
};

const ORIGIN_WORD: Record<string, string> = {
  material: "원료",
  ripeness: "익힘",
  cask: "통",
  yeast: "효모",
  process: "공정",
  ageing: "숙성",
  added: "첨가",
  nuruk: "누룩",
  surroundings: "환경",
  soil: "땅",
};

/**
 * A level is a step from 1 to 5 where it was collected, and the word for
 * where it stands where it was not. What reads the lines compares by word,
 * so a step is read as its word and kept beside it. Sweetness counts from
 * none (1 is dry), so its second step already says some sweetness is there;
 * every other axis has little of itself at 2.
 */
function levelWord(axis: string, step: number): string {
  if (axis === "sweetness") {
    return step === 1 ? "low" : step <= 3 ? "mid" : "high";
  }
  return step <= 2 ? "low" : step === 3 ? "mid" : "high";
}

function lineOf(axis: string, level: Level): TermTrait | null {
  if (level === null || level === undefined) return null;
  return typeof level === "number"
    ? { level: levelWord(axis, level), step: level }
    : { level };
}

/** A row's taste: its stated levels, its aroma strength among them. */
function tasteOf(
  row: { taste?: Taste; aroma_strength?: Level },
): Record<string, TermTrait> | undefined {
  const out: Record<string, TermTrait> = {};
  for (const [axis, level] of Object.entries(row.taste ?? {})) {
    const line = lineOf(axis, level);
    if (line) out[axis] = line;
  }
  const strength = lineOf("aroma_intensity", row.aroma_strength ?? null);
  if (strength) out.aroma_intensity = strength;
  return Object.keys(out).length ? out : undefined;
}

function aromasOf(
  row: { aromas?: Aromas; always?: string[] },
): TermAroma[] | undefined {
  const out: TermAroma[] = [];
  for (const [origin, keys] of Object.entries(row.aromas ?? {})) {
    for (const key of keys) {
      const aroma: TermAroma = { key };
      if (ORIGIN_WORD[origin]) aroma.source_kind = ORIGIN_WORD[origin];
      if (row.always?.includes(key)) aroma.basis = "production";
      out.push(aroma);
    }
  }
  return out.length ? out : undefined;
}

/** Drops the fields with no value, so a term carries only what it states. */
function stated<T extends Record<string, unknown>>(obj: T): T {
  return Object.fromEntries(
    Object.entries(obj).filter(([, v]) =>
      v !== undefined && v !== null &&
      !(Array.isArray(v) && v.length === 0) &&
      !(typeof v === "object" && !Array.isArray(v) &&
        Object.keys(v as object).length === 0)
    ),
  ) as T;
}

const COLOR_OF_KIND: Record<string, string> = {
  red_wine: "red",
  white_wine: "white",
  rose_wine: "rose",
  sparkling_wine: "sparkling",
};

function linkHint(keys: string[], byRule?: boolean) {
  return keys.length ? { keys, by: byRule ? "rule" : "typical" } : undefined;
}

function abvHints(abv: Abv | undefined) {
  return {
    abv_bounds: abv?.bounds,
    abv_source: abv?.bounds_from,
    abv_range: abv?.range,
  };
}

function drinkTerms(drink: DrinkFile): Term[] {
  const out: Term[] = [];
  const of = [drink.key];
  out.push(stated({
    key: drink.key,
    type: "category",
    names: { ko: drink.ko, en: drink.en },
    hints: stated(abvHints(drink.abv)),
  }) as Term);
  for (const kind of drink.kinds) {
    out.push(stated({
      key: kind.key,
      type: "kind",
      parent: drink.key,
      categories: of,
      names: stated({
        ko: kind.ko,
        en: kind.en,
        label: kind.label,
        aliases: kind.find,
      }),
      summary: kind.summary ?? undefined,
      taste: tasteOf(kind),
      aromas: aromasOf(kind),
      hints: stated({ label_words: kind.on_labels, ...abvHints(kind.abv) }),
    }) as Term);
    for (const style of kind.styles) {
      out.push(stated({
        key: style.key,
        type: "regional_style",
        categories: of,
        names: stated({
          ko: style.ko,
          label: style.label,
          label_patterns: style.find,
        }),
        summary: style.summary ?? undefined,
        taste: tasteOf(style),
        aromas: aromasOf(style),
        hints: {
          ...stated({
            color: style.color ?? COLOR_OF_KIND[kind.key],
            grapes: linkHint(style.grapes, style.grapes_by_rule),
            making: linkHint(style.making, style.making_by_rule),
            not_named: style.find_not,
            style_keys: style.also_of_kinds
              ? [kind.key, ...style.also_of_kinds]
              : undefined,
          }),
          // An empty list is a statement: the style is read from its name alone.
          ...(style.find_in_places ? { regions: style.find_in_places } : {}),
        },
        extra: stated({
          region_key: style.place ?? undefined,
          replaces_aromas: style.replaces_aromas,
        }),
      }) as Term);
    }
  }
  for (const grape of drink.grapes ?? []) {
    out.push(stated({
      key: grape.key,
      type: "grape",
      categories: of,
      names: stated({
        ko: grape.ko,
        label: grape.label,
        label_patterns: grape.find,
      }),
      summary: grape.summary ?? undefined,
      taste: tasteOf(grape),
      aromas: aromasOf(grape),
      hints: stated({
        colors: grape.colors,
        label_words: grape.on_labels,
        regions: grape.styles,
        abv_range: grape.abv?.range,
      }),
      extra: stated({ replaces_aromas: grape.replaces_aromas }),
    }) as Term);
  }
  for (const producer of drink.producers) {
    out.push(stated({
      key: producer.key,
      type: "producer",
      categories: of,
      names: stated({ ko: producer.ko, en: producer.en }),
      summary: producer.summary ?? undefined,
      taste: tasteOf(producer),
      aromas: aromasOf(producer),
      hints: stated({ peat: producer.peat, house_casks: producer.house_casks }),
      extra: stated({
        kind: producer.kind,
        country: producer.country,
        region: producer.region,
      }),
    }) as Term);
  }
  for (const word of drink.label_words) {
    out.push(stated({
      key: word.key,
      type: "label_word",
      categories: of,
      names: stated({ ko: word.ko, label: word.label, aliases: word.find }),
      summary: word.summary ?? undefined,
      extra: stated({ explained_by: word.explained_by }),
    }) as Term);
  }
  return out;
}

const MAKING_PARTS = [
  ["ingredients", "ingredient_type", "ingredient"],
  ["processes", "process_kind", "process"],
  ["maturations", "maturation_kind", "maturation"],
] as const;

function hasEffect(item: TagNode): boolean {
  return item.taste !== undefined || item.aromas !== undefined ||
    item.aroma_strength !== undefined || item.always !== undefined;
}

function makingTerm(
  item: TagNode,
  group: TagGroup,
  itemType: string,
  categories: string[],
  effect: TagNode | undefined,
): Term {
  return stated({
    key: item.key,
    type: itemType,
    parent: group.key,
    categories,
    names: stated({
      ko: item.ko,
      en: item.en,
      label: item.label,
      aliases: item.find,
    }),
    summary: item.summary ?? undefined,
    taste: effect ? tasteOf(effect) : undefined,
    aromas: effect ? aromasOf(effect) : undefined,
    hints: stated({ label_words: item.on_labels }),
  }) as Term;
}

function groupTerm(group: TagGroup, groupType: string): Term {
  return stated({
    key: group.key,
    type: groupType,
    names: stated({ ko: group.ko, en: group.en, aliases: group.find }),
  }) as Term;
}

/**
 * Each making row once: names and summary as the first drink file holds it,
 * what it does as the first drink file that says. The flat list the older
 * card code reads.
 */
function tagTerms(part: string, groupType: string, itemType: string): Term[] {
  const groups = new Map<string, TagGroup>();
  const items = new Map<string, { item: TagNode; group: TagGroup }>();
  const drinksOf = new Map<string, string[]>();
  const effectOf = new Map<string, TagNode>();
  for (const drink of DRINKS) {
    for (const group of drink.making[part] ?? []) {
      if (!groups.has(group.key)) groups.set(group.key, group);
      for (const item of group.items) {
        if (!items.has(item.key)) items.set(item.key, { item, group });
        drinksOf.set(item.key, [...(drinksOf.get(item.key) ?? []), drink.key]);
        if (!effectOf.has(item.key) && hasEffect(item)) {
          effectOf.set(item.key, item);
        }
      }
    }
  }
  const out: Term[] = [];
  for (const group of groups.values()) {
    out.push(groupTerm(group, groupType));
    for (const { item, group: home } of items.values()) {
      if (home.key !== group.key) continue;
      out.push(makingTerm(
        item,
        home,
        itemType,
        drinksOf.get(item.key)!,
        effectOf.get(item.key),
      ));
    }
  }
  return out;
}

function placeTerm(
  node: PlaceNode,
  above: string | null,
  categories: string[],
): Term {
  const term = stated({
    key: node.key,
    type: "region",
    parent: above,
    categories,
    names: stated({ ko: node.ko, en: node.en, aliases: node.aliases }),
    summary: node.summary ?? undefined,
    hints: stated({ climate: node.climate }),
  }) as Term;
  // A country's parent is stated as none, the way every reader expects it.
  if (term.parent === undefined) term.parent = null;
  return term;
}

/** Every place of a drink with the key of the place above it. */
function walkPlaces(
  nodes: PlaceNode[],
  above: string | null,
  visit: (node: PlaceNode, above: string | null) => void,
) {
  for (const node of nodes) {
    visit(node, above);
    walkPlaces(node.places ?? [], node.key, visit);
  }
}

/** Each place once, as the first drink file holds it: the flat list. */
function placeTerms(): Term[] {
  const first = new Map<string, { node: PlaceNode; above: string | null }>();
  const drinksOf = new Map<string, string[]>();
  for (const drink of DRINKS) {
    walkPlaces(drink.places, null, (node, above) => {
      if (!first.has(node.key)) first.set(node.key, { node, above });
      drinksOf.set(node.key, [...(drinksOf.get(node.key) ?? []), drink.key]);
    });
  }
  return [...first.values()].map(({ node, above }) =>
    placeTerm(node, above, drinksOf.get(node.key)!)
  );
}

/** One drink's places and making rows by key, as its file holds them. */
const DRINK_ROWS: ReadonlyMap<
  string,
  { places: Map<string, Term>; making: Map<string, Term> }
> = new Map(DRINKS.map((drink) => {
  const places = new Map<string, Term>();
  walkPlaces(drink.places, null, (node, above) => {
    places.set(node.key, placeTerm(node, above, [drink.key]));
  });
  const making = new Map<string, Term>();
  for (const [part, , itemType] of MAKING_PARTS) {
    for (const group of drink.making[part] ?? []) {
      for (const item of group.items) {
        making.set(
          item.key,
          makingTerm(
            item,
            group,
            itemType,
            [drink.key],
            hasEffect(item) ? item : undefined,
          ),
        );
      }
    }
  }
  return [drink.key, { places, making }];
}));

/**
 * A place as a drink's file holds it: its names, the place above it, and
 * what it says of this drink. Null when the drink has no such place.
 */
export function placeOf(drink: string, key: string): Term | null {
  return DRINK_ROWS.get(drink)?.places.get(key) ?? null;
}

/**
 * An ingredient, process or maturation as a drink's file holds it, with what
 * it does to this drink. Null when the drink has no such row.
 */
export function makingOf(drink: string, key: string): Term | null {
  return DRINK_ROWS.get(drink)?.making.get(key) ?? null;
}

/** Every word for what is sensed, with its type, family and the word above it. */
type SenseRow = {
  word: WordNode;
  type: string;
  family: FamilyNode | null;
  above: string | null;
};

const SENSE_TYPE: Record<string, string> = {
  descriptor: "aroma",
  texture: "texture",
  finish_character: "finish_character",
};

const SENSE_ROWS: SenseRow[] = (() => {
  const out: SenseRow[] = [];
  const walk = (
    words: WordNode[],
    type: string,
    family: FamilyNode | null,
    above: string | null,
  ) => {
    for (const word of words) {
      out.push({ word, type, family, above });
      walk(word.words ?? [], type, family, word.key);
    }
  };
  for (const family of SENSES.families) {
    walk(family.words, SENSE_TYPE[family.of], family, null);
  }
  for (const [type, words] of Object.entries(SENSES.words_of_no_family)) {
    walk(words, type, null, null);
  }
  return out;
})();

const SENSE_BY_KEY = new Map(SENSE_ROWS.map((row) => [row.word.key, row]));

/**
 * The impressions an aroma word gives (sweet_scent, fruit_scent, …): its own
 * and its family's. A narrower word that states none takes the word above it.
 */
export function aromaTraits(key: string): readonly string[] {
  for (
    let row = SENSE_BY_KEY.get(key);
    row;
    row = SENSE_BY_KEY.get(row.above ?? "")
  ) {
    if (row.word.traits?.length) {
      return [...new Set([...row.word.traits, ...(row.family?.traits ?? [])])];
    }
    if (!row.above) return row.family?.traits ?? [];
  }
  return [];
}

function senseTerms(): Term[] {
  const out: Term[] = [];
  for (const family of SENSES.families) {
    out.push(stated({
      key: family.key,
      type: "aroma_family",
      names: { ko: family.ko },
      summary: family.summary ?? undefined,
      traits: family.traits,
      extra: { domain: family.of, kind: family.kind ?? "sensory" },
    }) as Term);
  }
  for (const { word, type, family, above } of SENSE_ROWS) {
    out.push(stated({
      key: word.key,
      type,
      parent: above ?? undefined,
      names: stated({ ko: word.ko, en: word.en, aliases: word.aliases }),
      summary: word.summary ?? undefined,
      traits: word.traits,
      extra: stated({ family_key: family?.key }),
    }) as Term);
  }
  for (const trait of SENSES.traits) {
    out.push({
      key: trait.key,
      type: "trait",
      names: { ko: trait.ko },
      summary: trait.summary,
    });
  }
  return out;
}

/** The senses the taste axes are of. */
function axisTerms(): Term[] {
  return SENSES.axes.map((axis) =>
    stated({
      key: axis.key,
      type: "axis",
      names: stated({ ko: axis.ko, en: axis.en }),
      summary: axis.summary ?? undefined,
      traits: axis.traits,
    }) as Term
  );
}

const TERMS: Term[] = [
  ...DRINKS.flatMap(drinkTerms),
  ...placeTerms(),
  ...MAKING_PARTS.flatMap(([part, groupType, itemType]) =>
    tagTerms(part, groupType, itemType)
  ),
  ...axisTerms(),
  ...senseTerms(),
];

export function terms(...types: string[]): Term[] {
  return TERMS.filter((t) => types.includes(t.type));
}

/* ---------------------------------------------------------- regions */

/** Every region row by its key. */
export const regionByKey: ReadonlyMap<string, Term> = new Map(
  terms("region").map((t) => [t.key, t]),
);

/** The region line the card engine reads, rebuilt from the region tree:
 * '부르고뉴(Bourgogne) > 샤블리(Chablis)'. The country row is left out, as the
 * item carries its country code. */
export function regionPath(key: unknown): string | null {
  if (typeof key !== "string") return null;
  const parts: string[] = [];
  for (
    let term = regionByKey.get(key);
    term && term.parent;
    term = regionByKey.get(term.parent)
  ) {
    const { ko, en } = term.names;
    parts.unshift(en ? `${ko}(${en})` : ko);
  }
  return parts.length ? parts.join(" > ") : null;
}

/**
 * A region as a bottle's region line names it. A country is named by
 * itself: no region line starts with a country, so a style of a whole
 * country (젝트) is read only from the name on a bottle that states no region.
 */
function regionLabel(key: string): string {
  const { ko, en } = regionByKey.get(key)!.names;
  return regionPath(key) ?? (en ? `${ko}(${en})` : ko);
}

/**
 * The regions whose bottles read as a regional style without the label
 * naming it: the region the style sits under, unless hints.regions says
 * otherwise (only some places inside it, more than one region, or none, when
 * the style is read from the name on the label alone).
 */
export function styleRegions(style: Term): string[] {
  const regions = style.hints?.regions as string[] | undefined;
  if (regions) return regions;
  const home = style.extra?.region_key as string | undefined;
  return home ? [home] : [];
}

/** The Korean name of a drink (와인, 한국 전통주). */
export function drinkName(key: string): string | null {
  return DRINKS.find((d) => d.key === key)?.ko ?? null;
}

/* ---------------------------------------------------------- style table */

type StyleTrait = { level: string };
type StyleAroma = { key: string; source_kind?: string };

type StyleEntry = {
  key: string;
  name_ko: string;
  intro_ko: string;
  traits: Record<string, StyleTrait>;
  aromas: StyleAroma[];
  [extra: string]: unknown;
};

type GrapeEntry = StyleEntry & {
  colors: string[];
  match: { patterns: string[] };
};

type RegionEntry = StyleEntry & {
  color: string;
  match: {
    region_labels: string[];
    name_patterns: string[];
    style_keys?: string[];
    not_named?: string[];
  };
};

type StyleProfiles = {
  styles: StyleEntry[];
  wine_grapes: GrapeEntry[];
  wine_regions: RegionEntry[];
  /**
   * The old table's ten cask and process entries. The dictionary states what
   * every process and maturation does per drink (`effects`) instead; the
   * engine reads those when it reads the tree, so none is listed here.
   */
  processes: StyleEntry[];
};

const styleTraits = (t: Term): Record<string, StyleTrait> =>
  Object.fromEntries(
    Object.entries(t.taste ?? {}).map((
      [axis, v],
    ) => [axis, { level: v.level }]),
  );
const styleAromas = (t: Term): StyleAroma[] => t.aromas ?? [];

function buildStyleProfiles(): StyleProfiles {
  const styles = terms("kind").filter((t) => t.summary !== undefined).map((
    t,
  ): StyleEntry => ({
    key: t.key,
    name_ko: t.names.ko,
    intro_ko: t.summary!,
    traits: styleTraits(t),
    aromas: styleAromas(t),
  }));
  const wine_grapes = terms("grape").map((t): GrapeEntry => ({
    key: t.key,
    name_ko: t.names.ko,
    intro_ko: t.summary!,
    colors: (t.hints?.colors as string[]) ?? [],
    match: { patterns: t.names.label_patterns ?? [] },
    traits: styleTraits(t),
    aromas: styleAromas(t),
    ...(t.extra ?? {}),
  }));
  const wine_regions = terms("regional_style").map((t): RegionEntry => {
    const match: RegionEntry["match"] = {
      region_labels: styleRegions(t).map(regionLabel),
      name_patterns: t.names.label_patterns ?? [],
    };
    if (t.hints?.style_keys) match.style_keys = t.hints.style_keys as string[];
    if (t.hints?.not_named) match.not_named = t.hints.not_named as string[];
    return {
      key: t.key,
      name_ko: t.names.ko,
      color: t.hints?.color as string,
      intro_ko: t.summary!,
      match,
      traits: styleTraits(t),
      aromas: styleAromas(t),
      ...(t.extra ?? {}),
    };
  });
  return { styles, wine_grapes, wine_regions, processes: [] };
}

/* ------------------------------------------------------- sensory catalog */

type SensoryEntry = {
  key: string;
  label_ko: string;
  label_en?: string;
  aliases: string[];
  parent_key: string | null;
  /** A word the reader is offered to pick. */
  onboarding_selectable?: true;
  phases: string[];
  family_key?: string;
};

type FinishCharacterEntry = {
  key: string;
  label_ko: string;
  label_en?: string;
  family_key?: string;
};

type SensoryCatalog = {
  families: { key: string; label_ko: string; domain: string; kind: string }[];
  descriptors: SensoryEntry[];
  finish_characters: FinishCharacterEntry[];
  textures: SensoryEntry[];
};

/** The words a bottle can be tagged with: every word but the ones kept for meaning only. */
const SOURCE_ROWS = SENSE_ROWS.filter((r) => !r.word.meaning_only);

function buildSensoryCatalog(): SensoryCatalog {
  const entry = ({ word, family, above }: SenseRow): SensoryEntry => {
    const out: SensoryEntry = {
      key: word.key,
      label_ko: word.ko,
      aliases: word.aliases ?? [],
      parent_key: above,
      phases: word.said_of ?? [],
    };
    if (word.en !== undefined) out.label_en = word.en;
    if (word.choice) out.onboarding_selectable = true;
    if (family) out.family_key = family.key;
    return out;
  };
  return {
    families: SENSES.families.map((f) => ({
      key: f.key,
      label_ko: f.ko,
      domain: f.of,
      kind: f.kind ?? "sensory",
    })),
    descriptors: SOURCE_ROWS.filter((r) => r.type === "aroma").map(entry),
    finish_characters: SOURCE_ROWS.filter((r) => r.type === "finish_character")
      .map(({ word, family }) =>
        stated({
          key: word.key,
          label_ko: word.ko,
          label_en: word.en,
          family_key: family?.key,
        }) as FinishCharacterEntry
      ),
    textures: SOURCE_ROWS.filter((r) => r.type === "texture").map(entry),
  };
}

/* --------------------------------------------------- service vocabulary */

type VocabularyGroup = {
  key: string;
  label_ko: string;
  category_key: string;
  domain: string;
  source_keys: string[];
  user_source_labels: string[];
  phases: string[];
};

type ServiceVocabulary = {
  schema_version: string;
  taxonomy_version: string;
  categories: { key: string; label_ko: string }[];
  groups: VocabularyGroup[];
  hidden: { reason: string; source_keys: string[] }[];
  pending: { key: string; label_ko: string; reason: string }[];
  legacy_aliases: Record<string, string>;
};

const DOMAIN: Record<string, string> = {
  aroma: "descriptor",
  texture: "texture",
  finish_character: "finish_character",
};

/** The offered word each word folds into: the one it names, else the nearest offered word at or above it. */
const FOLD_TARGET: ReadonlyMap<string, string | null> = (() => {
  const shown = new Set(
    SENSE_ROWS.filter((r) => r.word.choice).map((r) => r.word.key),
  );
  const above = new Map(SENSE_ROWS.map((r) => [r.word.key, r.above]));
  const out = new Map<string, string | null>();
  for (const { word } of SENSE_ROWS) {
    if (word.shown_as !== undefined) {
      out.set(word.key, word.shown_as);
      continue;
    }
    let key: string | null = word.key;
    while (key !== null && !shown.has(key)) key = above.get(key) ?? null;
    out.set(word.key, key);
  }
  return out;
})();

function buildServiceVocabulary(): ServiceVocabulary {
  const sources = new Set(SOURCE_ROWS.map((r) => r.word.key));
  const shown = SENSE_ROWS.filter((r) => r.word.choice)
    .sort((a, b) => a.word.choice!.order - b.word.choice!.order);
  const groups = shown.map(({ word, type }): VocabularyGroup => ({
    key: word.key,
    label_ko: word.choice!.label,
    category_key: word.choice!.group,
    domain: DOMAIN[type],
    source_keys: [...FOLD_TARGET].filter(([k, t]) =>
      t === word.key && sources.has(k)
    ).map(([k]) => k),
    user_source_labels: word.choice!.found_by ?? [],
    phases: word.choice!.said_of ?? word.said_of ?? [],
  }));
  const pending = [
    ...SENSES.families.filter((f) => f.pending).map((f) => ({
      key: f.key,
      label_ko: f.pending!.label,
      reason: f.pending!.reason,
    })),
    ...SENSE_ROWS.filter((r) => r.word.pending).map(({ word }) => ({
      key: word.key,
      label_ko: word.pending!.label,
      reason: word.pending!.reason,
    })),
  ];
  const offered = new Set(shown.map((r) => r.word.key));
  const held = new Set(pending.map((p) => p.key));
  const hidden = SENSE_ROWS.map((r) => r.word.key).filter((k) =>
    !offered.has(k) && !held.has(k) && !offered.has(FOLD_TARGET.get(k) ?? "")
  );
  const legacy_aliases: Record<string, string> = {};
  for (const { word } of SENSE_ROWS) {
    for (const old of word.old_keys ?? []) legacy_aliases[old] = word.key;
  }
  return {
    schema_version: SENSES.choice.version,
    taxonomy_version: SENSES.choice.taxonomy_version,
    categories: SENSES.choice.groups.map((g) => ({
      key: g.key,
      label_ko: g.ko,
    })),
    groups,
    hidden: hidden.length
      ? [{ reason: "not offered", source_keys: hidden }]
      : [],
    pending,
    legacy_aliases,
  };
}

/* ------------------------------------------------------- term knowledge */

type TermKnowledgeEntry = {
  sensory_description: string;
  sensory_trait_keys: string[];
};

type TermKnowledge = {
  traits: Record<string, string>;
  terms: Record<string, TermKnowledgeEntry>;
  dimensions: Record<string, TermKnowledgeEntry>;
};

/** What the card may say of a word a bottle or an answer names: the offered, hidden and pending words. */
function buildTermKnowledge(vocabulary: ServiceVocabulary): TermKnowledge {
  const named = new Set([
    ...vocabulary.groups.map((g) => g.key),
    ...vocabulary.hidden.flatMap((h) => h.source_keys),
    ...vocabulary.pending.map((p) => p.key),
  ]);
  const entries: Record<string, TermKnowledgeEntry> = {};
  for (
    const t of terms("aroma_family", "aroma", "texture", "finish_character")
  ) {
    if (!named.has(t.key) || t.summary === undefined) continue;
    entries[t.key] = {
      sensory_description: t.summary,
      sensory_trait_keys: t.traits ?? [],
    };
  }
  const dimensions: TermKnowledge["dimensions"] = {};
  for (const t of terms("axis")) {
    if (t.summary === undefined) continue;
    dimensions[t.key] = {
      sensory_description: t.summary,
      sensory_trait_keys: t.traits ?? [],
    };
  }
  return {
    traits: Object.fromEntries(
      terms("trait").map((t) => [t.key, t.summary!]),
    ),
    terms: entries,
    dimensions,
  };
}

/* ------------------------------------------------------------ ABV bands */

type AbvBand = { bounds: number[]; source: string };

type AbvBands = {
  categories: Record<string, AbvBand>;
  styles: Record<string, AbvBand>;
};

function buildAbvBands(): AbvBands {
  const bands = (type: string): Record<string, AbvBand> =>
    Object.fromEntries(
      terms(type).filter((t) => t.hints?.abv_bounds).map((t) => [t.key, {
        bounds: t.hints!.abv_bounds as number[],
        source: t.hints!.abv_source as string,
      }]),
    );
  return { categories: bands("category"), styles: bands("kind") };
}

/* ---------------------------------------------------------------- views */

export const styleProfiles: StyleProfiles = buildStyleProfiles();
export const sensoryCatalog: SensoryCatalog = buildSensoryCatalog();
export const serviceVocabulary: ServiceVocabulary = buildServiceVocabulary();
export const termKnowledge: TermKnowledge = buildTermKnowledge(
  serviceVocabulary,
);
export const abvBands: AbvBands = buildAbvBands();
