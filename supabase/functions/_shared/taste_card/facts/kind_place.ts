/**
 * Where a bottle stands among the bottles of its own kind.
 *
 * The same number says different things in different kinds: sweetness 4 is
 * the commonest single malt and the middle of port, and 93 of 100 red wines
 * sit on sweetness 1. So every feature that compares bottles (the fit check,
 * the taste letters, the guide, the card text) reads a level here, as a
 * place between 0 and 1 among the kind's own bottles and as how common that
 * value is there. A value nearly every bottle of the kind has says little
 * about a drinker who met it; a rare one says a lot.
 *
 * The counts are the published catalog's, kept in
 * catalog/dictionary/kind_spreads.json and rebuilt by
 * tools/catalog/build_kind_spreads.ts. A kind with too few bottles on a
 * dimension borrows the pool named below, then its category.
 */
import spreads from "../../../../../catalog/dictionary/kind_spreads.json" with {
  type: "json",
};
import { aromaLine } from "../dictionary/aroma_lineage.ts";
import { terms } from "../dictionary/dictionary.ts";
import { EFFECT_ROWS } from "../findings/knowledge.ts";
import { alcoholLevelFromAbv } from "./abv_levels.ts";
import { feltSweetness, hasFeltSweetness } from "./felt_sweetness.ts";
import { kindOfStyle } from "./kind_of_style.ts";

/** Level dimensions a place can be read on. */
export const PLACE_DIMENSIONS = [
  "sweetness",
  "acidity",
  "bitterness",
  "astringency",
  "body",
  "carbonation",
  "finish_length",
  "finish_cleanliness",
  "aroma_intensity",
] as const;
export type PlaceDimension = typeof PLACE_DIMENSIONS[number];
/** A level dimension, or the strength read from the ABV. */
export type PlaceAxis = PlaceDimension | "alcohol";

/**
 * Small kinds and the larger set they are read among. A large kind stands
 * alone: port is not pooled with sherry (86 of 100 ports sit on sweetness 4
 * or 5, half of sherries on 1 or 2), nor bourbon with rye.
 */
export const POOL_MEMBERS: Readonly<Record<string, readonly string[]>> = {
  wine_still: ["red_wine", "white_wine", "rose_wine", "orange_wine"],
  wine_fortified_other: [
    "fortified_wine",
    "sherry_wine",
    "madeira_wine",
    "vermouth",
  ],
  whisky_malt_blend: [
    "single_malt_whisky",
    "blended_whisky",
    "blended_malt_whisky",
    "grain_whisky",
    "single_pot_still_whisky",
  ],
  whisky_american: [
    "bourbon",
    "rye_whisky",
    "tennessee_whisky",
    "american_whisky",
    "wheat_whisky",
    "corn_whisky",
  ],
  yakju_family: ["yakju", "korean_cheongju", "gwahaju"],
};

const POOL_OF: ReadonlyMap<string, string> = new Map(
  Object.entries(POOL_MEMBERS).flatMap(([pool, styles]) =>
    styles.map((style) => [style, pool] as const)
  ),
);

/**
 * The kinds a drinker's records carry over between. A record of one says
 * nothing checkable about a bottle of another, so the fit check answers only
 * inside a group the drinker has recorded.
 */
const GROUPS: readonly {
  key: string;
  name: string;
  styles?: readonly string[];
  category?: string;
}[] = [
  { key: "wine", name: "와인", styles: POOL_MEMBERS.wine_still },
  { key: "sparkling_wine", name: "스파클링 와인", styles: ["sparkling_wine"] },
  {
    key: "fortified_wine",
    name: "주정강화 와인",
    styles: ["port_wine", ...POOL_MEMBERS.wine_fortified_other],
  },
  { key: "takju", name: "탁주", styles: ["takju"] },
  { key: "yakju", name: "약주·청주", styles: POOL_MEMBERS.yakju_family },
  { key: "korean_fruit_wine", name: "과실주", styles: ["korean_fruit_wine"] },
  {
    key: "distilled_soju",
    name: "증류식 소주",
    styles: ["distilled_soju", "diluted_soju"],
  },
  { key: "whisky", name: "위스키", category: "whisky" },
  { key: "sake", name: "사케", category: "sake" },
];

export type KindGroup = { key: string; name: string };

export function kindGroup(
  styleKey: string | null | undefined,
  category: string | null | undefined,
): KindGroup | null {
  styleKey = kindOfStyle(styleKey);
  const found = GROUPS.find((group) =>
    (styleKey && group.styles?.includes(styleKey)) ||
    (category && group.category === category)
  );
  return found ? { key: found.key, name: found.name } : null;
}

type Spread = {
  bottles: number;
  levels: Record<string, number[]>;
  abv?: number[];
  felt_sweetness?: number[];
  /** Per grape: single-variety bottles, the part that feels sweeter than two thirds of the kind, the part drier than two thirds. */
  grapes?: Record<string, [number, number, number]>;
  families: Record<string, number>;
};
const KINDS = (spreads as unknown as { kinds: Record<string, Spread> }).kinds;

/** The kind itself, then the pool it borrows from, then its category. */
function scopes(
  styleKey: string | null | undefined,
  category: string | null | undefined,
): string[] {
  const chain: string[] = [];
  styleKey = kindOfStyle(styleKey);
  if (styleKey) {
    chain.push(styleKey);
    const pool = POOL_OF.get(styleKey);
    if (pool) chain.push(pool);
  }
  if (category) chain.push(category);
  return chain.filter((key) => KINDS[key]);
}

export type Place = {
  /** 0 at the kind's lowest bottle, 1 at its highest; the middle of the bottles that share the value. */
  position: number;
  /** The part of the kind's bottles that share the value. */
  share: number;
  /**
   * Where the bottle stands for comparing it with another, 0 to 1: half its
   * place among the kind and half the number on the 1 to 5 scale. Place
   * alone overstates a step between two crowded neighbours (single malts on
   * sweetness 3 and 4 hold three quarters of the kind, so they sit 40 places
   * in 100 apart), and the number alone ignores the kind.
   */
  standing: number;
  /** The number on the 1 to 5 scale: the stored level, a still wine's felt sweetness, the ABV's band. Null where an ABV has no band. */
  level: number | null;
  /** The kind, pool or category the bottle was read among. */
  scope: string;
};

const standing = (position: number, level: number) =>
  (position + Math.min(1, Math.max(0, (level - 1) / 4))) / 2;

function placeInCounts(counts: readonly number[], level: number) {
  const same = counts[level - 1];
  if (same === undefined) return null;
  const total = counts.reduce((sum, count) => sum + count, 0);
  const below = counts.slice(0, level - 1).reduce((sum, c) => sum + c, 0);
  return { position: (below + same / 2) / total, share: same / total };
}

/** `sorted` holds evenly spaced quantiles of the kind's values. */
function placeInQuantiles(sorted: readonly number[], value: number) {
  let below = 0;
  let upTo = 0;
  for (const edge of sorted) {
    if (edge < value - 1e-9) below++;
    if (edge <= value + 1e-9) upTo++;
  }
  return {
    position: (below + upTo) / 2 / sorted.length,
    share: (upTo - below) / sorted.length,
  };
}

/** The place of a 1 to 5 level, or null where the kind keeps no counts for the dimension. */
export function placeOfLevel(
  dimension: PlaceDimension,
  styleKey: string | null | undefined,
  category: string | null | undefined,
  level: number,
): Place | null {
  for (const scope of scopes(styleKey, category)) {
    const counts = KINDS[scope].levels[dimension];
    const found = counts && placeInCounts(counts, Math.round(level));
    if (found) {
      return {
        ...found,
        standing: standing(found.position, level),
        level,
        scope,
      };
    }
  }
  return null;
}

/**
 * Strength is the same quantity across the kinds one group compares, so an
 * ABV is placed among the whole group where the group is one family of
 * drinks: 40% is the floor of single malts and the commonest blend, and it
 * is the same 40% in both.
 */
const ABV_SCOPE_OF_CATEGORY: Readonly<Record<string, string>> = {
  whisky: "whisky",
  sake: "sake",
};

/** The place of an ABV among the kind's bottles; its number is the kind's ABV band (abv_levels.ts). */
export function placeOfAbv(
  styleKey: string | null | undefined,
  category: string | null | undefined,
  abv: number | null | undefined,
): Place | null {
  if (typeof abv !== "number" || !Number.isFinite(abv)) return null;
  const wide = category ? ABV_SCOPE_OF_CATEGORY[category] : undefined;
  const chain = wide && KINDS[wide] ? [wide] : scopes(styleKey, category);
  for (const scope of chain) {
    const sorted = KINDS[scope].abv;
    if (!sorted) continue;
    const found = placeInQuantiles(sorted, abv);
    const band = alcoholLevelFromAbv(abv, kindOfStyle(styleKey), category);
    return {
      ...found,
      standing: band ? standing(found.position, band.level) : found.position,
      level: band ? band.level : null,
      scope,
    };
  }
  return null;
}

export type PlacedBottle = {
  style_key: string | null | undefined;
  category_key: string | null | undefined;
  abv_percent?: number | null;
  /** Levels read off the bottle, 1 to 5. A kind's usual value copied in is not one. */
  levels: Readonly<Record<string, number | undefined>>;
  aroma_tags: readonly string[];
  production_process_keys?: readonly string[];
};

/**
 * The bottle's sweetness among its kind. A still wine is placed by how sweet
 * it feels (felt_sweetness.ts), every other drink by the stored level.
 */
export function placeOfSweetness(bottle: PlacedBottle): Place | null {
  const stored = bottle.levels.sweetness;
  if (typeof stored !== "number") return null;
  if (hasFeltSweetness(bottle.style_key)) {
    const felt = feltSweetness(bottle);
    for (const scope of scopes(bottle.style_key, bottle.category_key)) {
      const sorted = KINDS[scope].felt_sweetness;
      if (felt !== null && sorted) {
        const found = placeInQuantiles(sorted, felt);
        return {
          ...found,
          standing: standing(found.position, felt),
          level: felt,
          scope,
        };
      }
    }
  }
  return placeOfLevel(
    "sweetness",
    bottle.style_key,
    bottle.category_key,
    stored,
  );
}

/** Every axis the bottle can be placed on. */
export function placesOf(
  bottle: PlacedBottle,
): Partial<Record<PlaceAxis, Place>> {
  const places: Partial<Record<PlaceAxis, Place>> = {};
  for (const dimension of PLACE_DIMENSIONS) {
    const level = bottle.levels[dimension];
    if (typeof level !== "number") continue;
    const place = dimension === "sweetness"
      ? placeOfSweetness(bottle)
      : placeOfLevel(dimension, bottle.style_key, bottle.category_key, level);
    if (place) places[dimension] = place;
  }
  const alcohol = placeOfAbv(
    bottle.style_key,
    bottle.category_key,
    bottle.abv_percent,
  );
  if (alcohol) places.alcohol = alcohol;
  return places;
}

/* ------------------------------------------------------- aroma families */

export type AromaFamily = keyof typeof EFFECT_ROWS;
const FAMILIES = Object.entries(EFFECT_ROWS) as [
  AromaFamily,
  { nodes: readonly string[] },
][];

/** The families one aroma name belongs to: the name or any ancestor is a family node. */
export function familiesOfAroma(key: string): AromaFamily[] {
  const line = aromaLine(key);
  return FAMILIES.filter(([, row]) =>
    line.some((name) => row.nodes.includes(name))
  ).map(([family]) => family);
}

const PROCESS_AROMAS: ReadonlyMap<string, readonly string[]> = new Map(
  terms("process", "maturation").map((term) => [
    term.key,
    (term.aromas ?? []).filter((aroma) => aroma.basis === "production").map((
      aroma,
    ) => aroma.key),
  ]),
);

/**
 * The aroma families a bottle carries: its aroma tags, and the aromas its
 * making is sure to leave (a peated malt smells of smoke whether or not a
 * taster's note said so). Only the dictionary's production-based aromas of a
 * process count; its typical ones are not certain for this bottle.
 */
export function familiesOfBottle(
  aromaTags: readonly string[],
  processKeys: readonly string[] = [],
): Set<AromaFamily> {
  const names = [
    ...aromaTags,
    ...processKeys.flatMap((key) => PROCESS_AROMAS.get(key) ?? []),
  ];
  return new Set(names.flatMap(familiesOfAroma));
}

/** The part of the kind's bottles that carry the family, or null for an unknown kind. */
export function shareOfFamily(
  family: AromaFamily,
  styleKey: string | null | undefined,
  category: string | null | undefined,
): number | null {
  const scope = scopes(styleKey, category)[0];
  return scope ? KINDS[scope].families[family] ?? 0 : null;
}

/* ----------------------------------------------------------------- grapes */

export type GrapeLean = {
  grape: string;
  /** Single-variety bottles of the grape in the kind. */
  bottles: number;
  /** The part of them that feels sweeter than two thirds of the kind. */
  sweeter: number;
  /** The part of them that feels drier than two thirds of the kind. */
  drier: number;
};

/**
 * How a still wine kind's grapes lean in felt sweetness, counted from the
 * catalog's single-variety bottles. A guide that names grapes ranks by these
 * parts, never by how many bottles a grape has: Cabernet Sauvignon has the
 * most bottles on either side simply because it has the most bottles.
 */
export function grapeLeans(styleKey: string | null | undefined): GrapeLean[] {
  const kind = kindOfStyle(styleKey);
  const grapes = kind ? KINDS[kind]?.grapes : undefined;
  return Object.entries(grapes ?? {}).map((
    [grape, [bottles, sweeter, drier]],
  ) => ({
    grape,
    bottles,
    sweeter,
    drier,
  }));
}
