/**
 * What the published catalog holds, counted by kind of drink: how many
 * bottles sit on each level, the spread of their ABV, how sweet the still
 * wines feel, what part of them carries each aroma family, and how many of
 * them carry each cask or method, ingredient, grape and regional style (what
 * a shelf of the kind holds, for the card to name). ./kind_place.ts reads the
 * result.
 *
 * A bottle is one object with
 *   style_key, category_key, abv_percent, sweetness, acidity, bitterness,
 *   astringency, body, carbonation, finish_length, finish_character,
 *   aroma_intensity, aroma_tags, processes (production_process_keys),
 *   grapes (grape_variety_keys), ingredients (ingredient_keys), region_key,
 *   name_ko
 * read from alcohol_items joined to alcohol_tasting_profiles where
 * publish_status = 'published'.
 *
 * A kind is written when it has MIN_BOTTLES bottles, and a dimension when
 * MIN_BOTTLES of them and MIN_COVERAGE of the kind carry it; below that the
 * reader borrows the kind's pool or category, so a dimension only a handful
 * of bottles carry never decides anything.
 *
 * The count runs every night against the catalog itself
 * (catalog-kind-spreads) and is kept in catalog_kind_spreads, so a place the
 * dictionary came to tell apart, or a batch of new bottles, is counted by the
 * next morning. tools/catalog/build_kind_spreads.ts writes the same count to
 * catalog/dictionary/kind_spreads.json, the copy a function starts with.
 */
import { regionPath } from "../dictionary/dictionary.ts";
import { wineRegionKey } from "../prepare/bottle.ts";
import type { SensoryProduct } from "../record/sensory_record.ts";
import { feltSweetness } from "./felt_sweetness.ts";
import {
  familiesOfBottle,
  MIN_GRAPE_BOTTLES,
  PLACE_DIMENSIONS,
  POOL_MEMBERS,
} from "./kind_place.ts";

const MIN_BOTTLES = 100;
const MIN_COVERAGE = 0.3;
const QUANTILES = 101;

export type CountedBottle = Record<string, unknown> & {
  style_key: string | null;
  category_key: string | null;
};

const number = (value: unknown): number | null =>
  typeof value === "number"
    ? value
    : typeof value === "string" && value.trim() !== "" &&
        Number.isFinite(Number(value))
    ? Number(value)
    : null;
const strings = (value: unknown): string[] =>
  Array.isArray(value)
    ? value.filter((v): v is string => typeof v === "string")
    : [];

function quantiles(values: number[]): number[] {
  const sorted = [...values].sort((a, b) => a - b);
  return Array.from({ length: QUANTILES }, (_, i) => {
    const at = sorted[Math.round(i * (sorted.length - 1) / (QUANTILES - 1))];
    return Math.round(at * 1000) / 1000;
  });
}

/** How many of the bottles carry each key; a key under [floor] bottles is left out. */
function carriedBy(
  set: readonly CountedBottle[],
  keysOf: (bottle: CountedBottle) => readonly string[],
  floor = 1,
): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const bottle of set) {
    for (const key of new Set(keysOf(bottle))) {
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  return Object.fromEntries(
    Object.entries(counts).filter(([, count]) => count >= floor).sort(),
  );
}

/** The regional style a wine falls in, read as the card engine reads it. */
function regionalStyleOf(bottle: CountedBottle): string[] {
  if (bottle.category_key !== "wine") return [];
  const style = wineRegionKey({
    name: typeof bottle.name_ko === "string" ? bottle.name_ko : "",
    styleKey: bottle.style_key,
    region: regionPath(bottle.region_key),
  } as SensoryProduct);
  return style ? [style] : [];
}

export type KindSpreads = {
  read_on: string;
  bottles: number;
  kinds: Record<string, unknown>;
};

/** The count of [bottles], read on [readOn] (YYYY-MM-DD). */
export function buildKindSpreads(
  bottles: readonly CountedBottle[],
  readOn: string,
): KindSpreads {
  const sets = new Map<string, CountedBottle[]>();
  const add = (key: string | null | undefined, bottle: CountedBottle) => {
    if (!key) return;
    if (!sets.has(key)) sets.set(key, []);
    sets.get(key)!.push(bottle);
  };
  const poolOf = new Map(
    Object.entries(POOL_MEMBERS).flatMap(([pool, styles]) =>
      styles.map((style) => [style, pool] as const)
    ),
  );
  for (const bottle of bottles) {
    add(bottle.style_key, bottle);
    add(bottle.style_key ? poolOf.get(bottle.style_key) : null, bottle);
    add(bottle.category_key, bottle);
  }

  const kinds: Record<string, unknown> = {};
  for (const key of [...sets.keys()].sort()) {
    const set = sets.get(key)!;
    if (set.length < MIN_BOTTLES) continue;
    const levels: Record<string, number[]> = {};
    for (const dimension of PLACE_DIMENSIONS) {
      const counts = [0, 0, 0, 0, 0];
      let carried = 0;
      for (const bottle of set) {
        const level = number(bottle[dimension]);
        if (level === null) continue;
        const rounded = Math.round(level);
        if (rounded >= 1 && rounded <= 5) {
          counts[rounded - 1]++;
          carried++;
        }
      }
      if (carried >= MIN_BOTTLES && carried >= MIN_COVERAGE * set.length) {
        levels[dimension] = counts;
      }
    }
    const abv = set.flatMap((bottle) => {
      const value = number(bottle.abv_percent);
      return value === null ? [] : [value];
    });
    const felt = set.flatMap((bottle) => {
      const value = feltSweetness({
        style_key: bottle.style_key,
        levels: Object.fromEntries(
          PLACE_DIMENSIONS.map((d) => [d, number(bottle[d]) ?? undefined]),
        ),
        aroma_tags: strings(bottle.aroma_tags),
      });
      return value === null ? [] : [value];
    });
    const families: Record<string, number> = {};
    for (const bottle of set) {
      for (
        const family of familiesOfBottle(
          strings(bottle.aroma_tags),
          strings(bottle.processes),
        )
      ) families[family] = (families[family] ?? 0) + 1;
    }
    // For a still wine: of each grape's single-variety bottles, the part in
    // the sweeter-feeling third of the kind and the part in the drier third.
    const grapes: Record<string, [number, number, number]> = {};
    if (felt.length === set.length && sets.has(key) && !POOL_MEMBERS[key]) {
      const sorted = quantiles(felt);
      const [low, high] = [sorted[33], sorted[67]];
      const byGrape = new Map<string, number[]>();
      set.forEach((bottle, i) => {
        const own = strings(bottle.grapes);
        if (own.length !== 1) return;
        if (!byGrape.has(own[0])) byGrape.set(own[0], []);
        byGrape.get(own[0])!.push(felt[i]);
      });
      for (const [grape, values] of [...byGrape].sort()) {
        if (values.length < MIN_GRAPE_BOTTLES) continue;
        const part = (test: (v: number) => boolean) =>
          Math.round(1000 * values.filter(test).length / values.length) / 1000;
        grapes[grape] = [
          values.length,
          part((v) => v > high),
          part((v) => v < low),
        ];
      }
    }
    kinds[key] = {
      bottles: set.length,
      levels,
      ...(abv.length >= MIN_BOTTLES ? { abv: quantiles(abv) } : {}),
      // Only where every bottle of the set is a still wine.
      ...(felt.length === set.length
        ? { felt_sweetness: quantiles(felt) }
        : {}),
      ...(Object.keys(grapes).length > 0 ? { grapes } : {}),
      families: Object.fromEntries(
        Object.entries(families).sort().map((
          [family, count],
        ) => [family, Math.round(1000 * count / set.length) / 1000]),
      ),
      // What a shelf of the kind holds. A grape is listed from the same count
      // as above; a category also lists its kinds, however few bottles.
      carried: {
        made: carriedBy(set, (bottle) => strings(bottle.processes)),
        ingredients: carriedBy(set, (bottle) => strings(bottle.ingredients)),
        grapes: carriedBy(
          set,
          (bottle) => strings(bottle.grapes),
          MIN_GRAPE_BOTTLES,
        ),
        styles: carriedBy(set, regionalStyleOf),
        ...(set.every((bottle) => bottle.category_key === key)
          ? {
            kinds: carriedBy(
              set,
              (bottle) => bottle.style_key ? [bottle.style_key] : [],
            ),
          }
          : {}),
      },
    };
  }

  return { read_on: readOn, bottles: bottles.length, kinds };
}
