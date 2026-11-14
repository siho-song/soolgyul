/**
 * Rebuilds catalog/dictionary/kind_spreads.json: for every kind of drink, how
 * many published bottles sit on each level, the spread of their ABV, how sweet
 * the still wines feel, and what part of them carries each aroma family.
 * supabase/functions/_shared/taste_card/facts/kind_place.ts reads the file.
 *
 * Input: a JSON array of the published bottles, one object each with
 *   style_key, category_key, abv_percent, sweetness, acidity, bitterness,
 *   astringency, body, carbonation, finish_length, finish_cleanliness,
 *   aroma_intensity, aroma_tags, processes (production_process_keys),
 *   grapes (grape_variety_keys)
 * read from alcohol_items joined to alcohol_tasting_profiles where
 * publish_status = 'published'.
 *
 *   deno run --allow-read --allow-write tools/catalog/build_kind_spreads.ts <bottles.json> <YYYY-MM-DD>
 *
 * A kind is written when it has MIN_BOTTLES bottles, and a dimension when
 * MIN_BOTTLES of them and MIN_COVERAGE of the kind carry it; below that the
 * reader borrows the kind's pool or category, so a dimension only a handful
 * of bottles carry never decides anything.
 */
import { feltSweetness } from "../../supabase/functions/_shared/taste_card/facts/felt_sweetness.ts";
import {
  familiesOfBottle,
  PLACE_DIMENSIONS,
  POOL_MEMBERS,
} from "../../supabase/functions/_shared/taste_card/facts/kind_place.ts";

const MIN_BOTTLES = 100;
const MIN_COVERAGE = 0.3;
const QUANTILES = 101;
/** A grape is listed for a wine kind from this many single-variety bottles. */
const MIN_GRAPE_BOTTLES = 50;

type Bottle = Record<string, unknown> & {
  style_key: string | null;
  category_key: string | null;
};

const [input, readOn] = Deno.args;
if (!input || !readOn) {
  console.error("usage: build_kind_spreads.ts <bottles.json> <YYYY-MM-DD>");
  Deno.exit(1);
}
const bottles = JSON.parse(await Deno.readTextFile(input)) as Bottle[];

const sets = new Map<string, Bottle[]>();
const add = (key: string | null | undefined, bottle: Bottle) => {
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
    ...(felt.length === set.length ? { felt_sweetness: quantiles(felt) } : {}),
    ...(Object.keys(grapes).length > 0 ? { grapes } : {}),
    families: Object.fromEntries(
      Object.entries(families).sort().map((
        [family, count],
      ) => [family, Math.round(1000 * count / set.length) / 1000]),
    ),
  };
}

const out = { read_on: readOn, bottles: bottles.length, kinds };
const lines = Object.entries(kinds).map(([key, value]) =>
  `    ${JSON.stringify(key)}: ${JSON.stringify(value)}`
);
await Deno.writeTextFile(
  new URL("../../catalog/dictionary/kind_spreads.json", import.meta.url),
  `{\n  "read_on": ${
    JSON.stringify(readOn)
  },\n  "bottles": ${bottles.length},\n  "kinds": {\n${
    lines.join(",\n")
  }\n  }\n}\n`,
);
console.log(`${Object.keys(kinds).length} kinds from ${out.bottles} bottles`);
