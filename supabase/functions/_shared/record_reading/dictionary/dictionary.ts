// The dictionary, as the code outside this folder asks it: one row (a term)
// for each kind of drink, style, grape, producer, label word, place, way of
// making and word for what is sensed, and the questions asked of them (a
// grape by its key, a place's path, the bands of a kind's strength).
//
// The files themselves are read in files.ts, and only by this folder. A place
// or a making row two drinks share appears here once, as the first drink
// file holds it; placeOf and makingOf give it as one drink's file says it.
import {
  SENSE_AXES,
  SENSE_FAMILIES,
  SENSE_ROWS,
  SENSE_TRAITS,
} from "./aromas.ts";
import {
  type Abv,
  type Aromas,
  type DrinkFile,
  DRINKS,
  type Level,
  type PlaceNode,
  type TagGroup,
  type TagNode,
  type Taste,
} from "./files.ts";

/* ------------------------------------------------------------- the terms */

type TermTrait = {
  /** low, mid or high (none for a drink with no bubbles): the word the file's level stands under. */
  level: string;
  /** The file's level where it states a step from 1 to 5. */
  step?: number;
};

type TermAroma = {
  key: string;
  /** "production": the making always leaves it (피트 처리 맥아 -> 연기), not only often. */
  basis?: "production";
  /** Where the aroma comes from, in the words the card was written with (원료, 통 ...). */
  source_kind?: string;
};

/** A drink's or a kind's five bands of strength: the four edges between them, and where they are from. */
export type AbvBands = { bounds: number[]; source: string };

/**
 * One row of the dictionary. Every row has a key, a type and its names; the
 * rest is there where the row states it, and the fields after `traits` only
 * on the type named beside each.
 */
export type Term = {
  key: string;
  /**
   * category, kind, regional_style, grape, producer, label_word, region,
   * ingredient, process, maturation (and the group each of those three sits
   * in: ingredient_type, process_kind, maturation_kind), axis, aroma_family,
   * aroma, texture, finish_character, trait.
   */
  type: string;
  /** The row above it: a place's wider place (null for a country), a word's wider word, a making row's group. */
  parent?: string | null;
  /** The drinks it belongs to (wine, whisky, sake, korean_traditional). */
  categories?: string[];
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
  /** The impressions a word for what is sensed gives. */
  traits?: string[];
  /** A category or a kind: its bands of strength. */
  abv_bands?: AbvBands;
  /** A kind, a grape, a cask or a method: other words a label prints for it. */
  label_words?: string[];
  /** A grape: the colours of wine it makes. */
  colors?: string[];
  /** A regional style: its colour (red, white, rose, sparkling, orange, any). */
  color?: string;
  /** A regional style: the kind it is filed under (red_wine). */
  kind_key?: string;
  /** A regional style whose colour does not say its kind: the kinds its bottles are, the narrowest last. */
  kind_keys?: string[];
  /** A regional style: the place it is of. */
  region_key?: string;
  /**
   * A regional style: the places whose bottles are read as it, where that is
   * not simply its own place. An empty list says it is read from the name on
   * the label alone.
   */
  read_in_regions?: string[];
  /** A regional style: words on a label that say the bottle is another style of the same place. */
  not_named?: string[];
  /** A regional style: the grapes it is made of. */
  grape_keys?: string[];
  /** A producer: what it is (distillery, winery, blend_brand …). */
  house?: string;
  /** A label word: the row that explains it (생막걸리 → 비살균). */
  explained_by?: string;
  /** A place: its climate. */
  climate?: string;
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
  orange_wine: "orange",
};

function abvBands(abv: Abv | undefined): AbvBands | undefined {
  return abv?.bounds?.length
    ? { bounds: abv.bounds, source: abv.bounds_from as string }
    : undefined;
}

function drinkTerms(drink: DrinkFile): Term[] {
  const out: Term[] = [];
  const of = [drink.key];
  out.push(stated({
    key: drink.key,
    type: "category",
    names: { ko: drink.ko, en: drink.en },
    abv_bands: abvBands(drink.abv),
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
      label_words: kind.on_labels,
      abv_bands: abvBands(kind.abv),
    }) as Term);
    for (const style of kind.styles) {
      out.push({
        ...stated({
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
          color: style.color ?? COLOR_OF_KIND[kind.key],
          // The kind the style is a drink of: a place makes a red and a white
          // under one name, and a card's help opens the one it is about.
          kind_key: kind.key,
          // A fortified wine has no colour to be matched by: its kind is.
          kind_keys: style.also_of_kinds
            ? [kind.key, ...style.also_of_kinds]
            : kind.key === "fortified_wine"
            ? [kind.key]
            : undefined,
          region_key: style.place ?? undefined,
          not_named: style.find_not,
          grape_keys: style.grapes,
        }) as Term,
        // An empty list is a statement: the style is read from its name alone.
        ...(style.find_in_places
          ? { read_in_regions: style.find_in_places }
          : {}),
      });
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
      colors: grape.colors,
      label_words: grape.on_labels,
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
      house: producer.kind,
    }) as Term);
  }
  for (const word of drink.label_words) {
    out.push(stated({
      key: word.key,
      type: "label_word",
      categories: of,
      names: stated({ ko: word.ko, label: word.label, aliases: word.find }),
      summary: word.summary ?? undefined,
      explained_by: word.explained_by,
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
    label_words: item.on_labels,
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
    climate: node.climate ?? undefined,
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

function senseTerms(): Term[] {
  const out: Term[] = [];
  for (const family of SENSE_FAMILIES) {
    out.push(stated({
      key: family.key,
      type: "aroma_family",
      names: { ko: family.ko },
      summary: family.summary ?? undefined,
      traits: family.traits,
    }) as Term);
  }
  for (const { word, type, above } of SENSE_ROWS) {
    out.push(stated({
      key: word.key,
      type,
      parent: above ?? undefined,
      names: stated({ ko: word.ko, en: word.en, aliases: word.aliases }),
      summary: word.summary ?? undefined,
      traits: word.traits,
    }) as Term);
  }
  for (const trait of SENSE_TRAITS) {
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
  return SENSE_AXES.map((axis) =>
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

/** Every row of the given types, in the dictionary's order. */
export function terms(...types: string[]): Term[] {
  return TERMS.filter((t) => types.includes(t.type));
}

/** A row's name across the dictionary: its type and its key (grape:merlot). */
export const termKey = (term: Pick<Term, "type" | "key">): string =>
  `${term.type}:${term.key}`;

/** Where two rows of one type share a key, the later one is the row. */
const TERM_BY_KEY: ReadonlyMap<string, Term> = new Map(
  TERMS.map((term) => [termKey(term), term]),
);

/** The row of a type and a key, or null. */
export function termByKey(
  type: string,
  key: string | null | undefined,
): Term | null {
  return (key && TERM_BY_KEY.get(`${type}:${key}`)) || null;
}

/** A kind of drink by its key (red_wine, junmai). */
export function kindByKey(key: string | null | undefined): Term | null {
  return termByKey("kind", key);
}

/** A place's style of a drink by its key (barolo_red). */
export function regionalStyleByKey(
  key: string | null | undefined,
): Term | null {
  return termByKey("regional_style", key);
}

/** A grape by its key (merlot). */
export function grapeByKey(key: string | null | undefined): Term | null {
  return termByKey("grape", key);
}

/** A producer by its key (laphroaig). */
export function producerByKey(key: string | null | undefined): Term | null {
  return termByKey("producer", key);
}

/** A place by its key (fr_bourgogne). */
export function regionByKey(key: string | null | undefined): Term | null {
  return termByKey("region", key);
}

/** An ingredient by its key (glutinous_rice). */
export function ingredientByKey(key: string | null | undefined): Term | null {
  return termByKey("ingredient", key);
}

/** A cask or a way of making by its key (sherry_cask, pot_still). */
export function caskOrMethodByKey(
  key: string | null | undefined,
): Term | null {
  return termByKey("maturation", key) ?? termByKey("process", key);
}

/** The Korean name of a drink (와인, 한국 전통주). */
export function drinkName(key: string): string | null {
  return DRINKS.find((d) => d.key === key)?.ko ?? null;
}

/** A name without what the dictionary adds in brackets: 산지오베제(키안티·브루넬로) is 산지오베제. */
export function plainName(name: string): string {
  return name.replace(/\s*\([^)]*\)/g, "").trim();
}

const KIND_KEY_BY_NAME: ReadonlyMap<string, string> = new Map(
  terms("kind").map((t) => [t.names.ko, t.key]),
);

/** The key of the kind a Korean name names (레드 와인 → red_wine), or null. */
export function kindKeyByName(name: string | null | undefined): string | null {
  return (name && KIND_KEY_BY_NAME.get(name)) || null;
}

/** The aromas a cask or a way of making always leaves (피트 처리 맥아 → 연기), not only often. */
export function sureAromasOf(caskOrMethodKey: string): string[] {
  return (caskOrMethodByKey(caskOrMethodKey)?.aromas ?? [])
    .filter((aroma) => aroma.basis === "production").map((aroma) => aroma.key);
}

/* ---------------------------------------------------------------- places */

/** A place, then each place above it, up to its country. Empty for an unknown key. */
export function regionsUpFrom(key: string | null | undefined): Term[] {
  const out: Term[] = [];
  for (
    let term = regionByKey(key);
    term && !out.includes(term);
    term = regionByKey(term.parent)
  ) out.push(term);
  return out;
}

/** A drink's place as its own file holds it, then each place above it, up to its country. */
export function placesUpFrom(drink: string, key: string | null): Term[] {
  const out: Term[] = [];
  for (
    let term = key ? placeOf(drink, key) : null;
    term && !out.includes(term);
    term = term.parent ? placeOf(drink, term.parent) : null
  ) out.push(term);
  return out;
}

const nameWithLatin = ({ ko, en }: Term["names"]) => en ? `${ko}(${en})` : ko;

/**
 * A bottle's region line, from below its country down to the place:
 * '부르고뉴(Bourgogne) > 샤블리(Chablis)'. The country is left out, as the
 * bottle carries its country code; a country's own key has no line.
 */
export function regionPath(key: unknown): string | null {
  if (typeof key !== "string") return null;
  const below = regionsUpFrom(key).filter((term) => term.parent);
  return below.length
    ? below.reverse().map((term) => nameWithLatin(term.names)).join(" > ")
    : null;
}

/**
 * The region lines of the bottles that are read as a regional style without
 * the label naming it: those of its own place, unless the style says other
 * places or none. A country is named by itself: no region line starts with a
 * country, so a style of a whole country (젝트) is read only from the name on
 * a bottle that states no region.
 */
export function regionPathsOfStyle(style: Term): string[] {
  const keys = style.read_in_regions ??
    (style.region_key ? [style.region_key] : []);
  return keys.map((key) =>
    regionPath(key) ?? nameWithLatin(regionByKey(key)!.names)
  );
}

const REGION_NAMES: ReadonlySet<string> = new Set(
  terms("region").map((t) => plainName(t.names.ko)),
);

/** Whether the dictionary keeps a place of that name (보르도, 스페이사이드). */
export function isRegionName(name: string): boolean {
  return REGION_NAMES.has(name);
}

/* -------------------------------------------------------------- strength */

/** The usual strength of a kind, lowest to highest, or of its drink where the kind states none. */
export function usualAbvRange(
  drink: string,
  kindKey: string | null,
): number[] | null {
  const file = DRINKS.find((d) => d.key === drink);
  const kind = file?.kinds.find((k) => k.key === kindKey);
  return kind?.abv?.range ?? file?.abv?.range ?? null;
}
