/**
 * 준비 · 조회: what the catalog and the dictionary say of the bottle (술의
 * 사실). Nothing is judged or calculated here, and the answers are not
 * looked at.
 *
 * The rows come from the catalog as the store read them (record_builder.ts);
 * the dictionary names the entries the bottle falls in (its grapes, its wine
 * region) and what each of its tags is. Facts are never guessed: a grape, a
 * region or a process the catalog does not state stays empty.
 *
 * Two values have a fallback, used only where the catalog holds none, and
 * marked as the kind's so that a card speaks of the kind (이런 종류는 보통 …)
 * and never of this bottle:
 *   a sensory level  the kind's table (catalog/sensory/style-profiles)
 *   the ABV          the kind's usual strength, its middle band
 */
import { styleProfiles } from "../dictionary/dictionary.ts";
import { abvBandsFor } from "../facts/abv_levels.ts";
import { LEVEL_DIMENSIONS, type LevelDimension } from "../facts/facts.ts";
import {
  type TableDimension,
  tableLevels,
} from "../facts/kind_table_levels.ts";
import { isEstimatedLevelSource } from "../facts/level_sources.ts";
import type {
  SensoryProduct,
  SensoryProductDescriptor,
  SensoryScore,
} from "../record/sensory_record.ts";

export type BottleLevel = {
  level: SensoryScore;
  /** Whose value it is: read for this bottle, or the kind's usual one. */
  of: "bottle" | "kind";
  /**
   * Where it came from: the catalog's source grade (1–4), `catalog` when the
   * catalog states the level without a grade, `kind_table` when the catalog
   * held none and the kind's table filled it.
   */
  source: number | "catalog" | "kind_table";
};

export type BottleAbv =
  | { of: "bottle"; percent: number }
  /** The kind's usual strength: from `low` up to, not including, `high`. */
  | { of: "kind"; low: number; high: number; scope: string };

/** 술의 사실: one bottle as the catalog and the dictionary describe it. */
export type BottleFacts = {
  name: string;
  category: SensoryProduct["category"];
  style_key: string | null;
  /** The catalog's region path: "샹빠뉴(Champagne) > 꼬뜨 데 블랑(Côte des Blancs)". */
  region: string | null;
  /** The dictionary's wine region entry the bottle falls in (샴페인, 보르도 좌안). */
  region_entry: string | null;
  /** The dictionary's grape entries of the wine, main grape first. */
  grapes: readonly string[];
  ingredients: readonly string[];
  processes: readonly string[];
  producer: string | null;
  vintage_year: number | null;
  age_years: number | null;
  abv: BottleAbv | null;
  levels: Readonly<Partial<Record<LevelDimension, BottleLevel>>>;
  /** The catalog's tags by section, each with the dictionary's name, family and traits. */
  tags: readonly SensoryProductDescriptor[];
};

const unique = (values: readonly string[]) => [...new Set(values)].sort();

export function bottleFacts(product: SensoryProduct): BottleFacts {
  return {
    name: product.name,
    category: product.category,
    style_key: product.styleKey,
    region: product.region ?? null,
    region_entry: wineRegionKey(product),
    grapes: wineGrapeKeys(product),
    ingredients: unique(product.ingredients ?? []),
    processes: unique(product.processes ?? []),
    producer: product.producer ?? null,
    vintage_year: product.vintageYear ?? null,
    age_years: product.ageStatementYears ?? null,
    abv: abvOf(product),
    levels: levelsOf(product),
    tags: product.descriptors,
  };
}

function levelsOf(product: SensoryProduct): BottleFacts["levels"] {
  const table = tableLevels(product.styleKey);
  const levels: Partial<Record<LevelDimension, BottleLevel>> = {};
  for (const dimension of LEVEL_DIMENSIONS) {
    const level = product.levels[dimension];
    if (level) {
      const grade = product.levelSources?.[dimension];
      levels[dimension] = {
        level,
        of: isEstimatedLevelSource(grade) ? "kind" : "bottle",
        source: grade ?? "catalog",
      };
      continue;
    }
    const usual = table[dimension as TableDimension];
    if (usual) {
      levels[dimension] = { level: usual, of: "kind", source: "kind_table" };
    }
  }
  return levels;
}

function abvOf(product: SensoryProduct): BottleAbv | null {
  if (typeof product.abv === "number" && Number.isFinite(product.abv)) {
    return { of: "bottle", percent: product.abv };
  }
  const found = abvBandsFor(product.styleKey, product.category);
  if (!found) return null;
  // The middle band of the kind: what is neither weak nor strong for it.
  const { bounds } = found.bands;
  const middle = Math.floor(bounds.length / 2);
  const low = bounds[middle - 1];
  const high = bounds[middle];
  return low === undefined || high === undefined
    ? null
    : { of: "kind", low, high, scope: found.scope };
}

/* ------------------------------------------ the dictionary's wine entries */

const WINE_COLORS: Readonly<Record<string, string>> = {
  red_wine: "red",
  white_wine: "white",
  sparkling_wine: "sparkling",
  rose_wine: "rose",
  orange_wine: "orange",
};
type WineRegion = {
  key: string;
  color: string;
  match: {
    region_labels?: readonly string[];
    name_patterns?: readonly string[];
    style_keys?: readonly string[];
    not_named?: readonly string[];
  };
};
type WineGrape = {
  key: string;
  colors: readonly string[];
  match: { patterns: readonly string[] };
};
const WINE_REGIONS =
  (styleProfiles as unknown as { wine_regions: WineRegion[] }).wine_regions;
const WINE_GRAPES =
  (styleProfiles as unknown as { wine_grapes: WineGrape[] }).wine_grapes;
const GRAPE_PATTERNS = WINE_GRAPES.flatMap((g) => g.match.patterns);

/**
 * The grape entries a wine falls in, as the catalog tools resolve them: the
 * grapes the catalog states for the product, or else every grape named in the
 * product name. Only grapes of the wine's colour count; a non-wine style has
 * none.
 */
function wineGrapeKeys(product: SensoryProduct): string[] {
  const color = WINE_COLORS[product.styleKey ?? ""];
  if (!color) return [];
  const stated = [...new Set(product.grapeVarietyKeys ?? [])];
  const byKey = new Map(WINE_GRAPES.map((g) => [g.key, g]));
  if (stated.length) {
    return stated.filter((key) => byKey.get(key)?.colors.includes(color));
  }
  const name = product.name.toLowerCase();
  return WINE_GRAPES.filter((g) =>
    g.colors.includes(color) && g.match.patterns.some((p) => name.includes(p))
  ).map((g) => g.key);
}

/**
 * The deepest wine region entry the product falls in: a region label or a
 * sub-label of it, or an appellation in the name unless the region is
 * elsewhere. Grape names never read as regions ("melon de bourgogne").
 */
export function wineRegionKey(product: SensoryProduct): string | null {
  const styleKey = product.styleKey ?? "";
  const color = WINE_COLORS[styleKey];
  const region = product.region ?? "";
  const label = product.name.toLowerCase();
  let name = label;
  for (const pattern of GRAPE_PATTERNS) name = name.replaceAll(pattern, " ");
  let best: { depth: number; key: string } | null = null;
  for (const entry of WINE_REGIONS) {
    const { match } = entry;
    if (match.style_keys) {
      if (!match.style_keys.includes(styleKey)) continue;
    } else if (!color || (entry.color !== color && entry.color !== "any")) {
      continue;
    }
    // A word on the label that says the bottle is another kind of wine of
    // the same place (a Frizzante is no Sekt).
    if ((match.not_named ?? []).some((word) => label.includes(word))) continue;
    const labels = match.region_labels ?? [];
    let depth = Math.max(
      0,
      ...labels.filter((l) => region === l || region.startsWith(`${l} > `))
        .map((l) => l.split(" > ").length),
    );
    const top = region.split(" > ")[0];
    const elsewhere = region !== "" && labels.length > 0 &&
      labels.every((l) => l.split(" > ")[0] !== top);
    if (
      !elsewhere && (match.name_patterns ?? []).some((p) => name.includes(p))
    ) depth = Math.max(depth, 2);
    if (depth && (!best || depth >= best.depth)) {
      best = { depth, key: entry.key };
    }
  }
  return best?.key ?? null;
}
