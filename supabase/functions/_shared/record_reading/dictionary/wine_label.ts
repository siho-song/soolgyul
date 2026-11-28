/**
 * What a wine's name and region line say of it: the grapes it is made of and
 * the regional style it falls in (a 바롤로, a 샤블리), as the dictionary's
 * rows are matched to a bottle.
 */
import {
  COLOR_OF_KIND,
  regionPathsOfStyle,
  type Term,
  terms,
} from "./dictionary.ts";

/** A wine as the catalog holds it. */
export type WineBottle = {
  name: string;
  /** red_wine, white_wine … */
  kind_key: string | null;
  /** '부르고뉴(Bourgogne) > 샤블리(Chablis)', or null. */
  region_path: string | null;
  /** The grapes the catalog states for it. */
  grape_keys?: readonly string[];
};

const GRAPES: readonly Term[] = terms("grape");
const GRAPE_BY_KEY = new Map(GRAPES.map((grape) => [grape.key, grape]));
const GRAPE_SPELLINGS = GRAPES.flatMap((g) => g.names.label_patterns ?? []);
const STYLES = terms("regional_style").map((style) => ({
  style,
  region_paths: regionPathsOfStyle(style),
}));

/**
 * The grapes a wine is made of: the grapes the catalog states for it, or
 * else every grape its name spells. Only grapes of the wine's colour count;
 * a bottle that is no wine has none.
 */
export function grapesOfWine(wine: WineBottle): string[] {
  const color = COLOR_OF_KIND[wine.kind_key ?? ""];
  if (!color) return [];
  const stated = [...new Set(wine.grape_keys ?? [])];
  if (stated.length) {
    return stated.filter((key) =>
      GRAPE_BY_KEY.get(key)?.colors?.includes(color)
    );
  }
  const name = wine.name.toLowerCase();
  return GRAPES.filter((g) =>
    g.colors?.includes(color) &&
    (g.names.label_patterns ?? []).some((p) => name.includes(p))
  ).map((g) => g.key);
}

/** Every place a word starts in a text. */
function occurrences(text: string, word: string): number[] {
  const out: number[] = [];
  for (let i = text.indexOf(word); i >= 0; i = text.indexOf(word, i + 1)) {
    out.push(i);
  }
  return out;
}

/**
 * True when the name holds the appellation somewhere other than inside a
 * grape's name: "melon de bourgogne" does not name 부르고뉴, while "moscato
 * d'asti" names 모스카토 다스티 although it holds the grape 모스카토.
 */
function namesOutsideGrapes(name: string, pattern: string): boolean {
  const found = occurrences(name, pattern);
  if (!found.length) return false;
  const grapes = GRAPE_SPELLINGS.flatMap((g) =>
    occurrences(name, g).map((i) => [i, i + g.length])
  );
  return found.some((i) =>
    !grapes.some(([s, e]) => s <= i && i + pattern.length <= e)
  );
}

/**
 * The narrowest regional style a wine falls in: one whose place its region
 * line is in, or one its name spells unless its region is elsewhere. A style
 * spelled inside a grape's name is not read ("melon de bourgogne").
 */
export function regionalStyleOfWine(wine: WineBottle): string | null {
  const kind = wine.kind_key ?? "";
  const color = COLOR_OF_KIND[kind];
  const region = wine.region_path ?? "";
  const label = wine.name.toLowerCase();
  let best: { depth: number; key: string } | null = null;
  for (const { style, region_paths } of STYLES) {
    if (style.kind_keys) {
      if (!style.kind_keys.includes(kind)) continue;
    } else if (!color || (style.color !== color && style.color !== "any")) {
      continue;
    }
    // A word on the label that says the bottle is another kind of wine of
    // the same place (a Frizzante is no Sekt).
    if ((style.not_named ?? []).some((word) => label.includes(word))) continue;
    let depth = Math.max(
      0,
      ...region_paths.filter((l) =>
        region === l || region.startsWith(`${l} > `)
      )
        .map((l) => l.split(" > ").length),
    );
    const top = region.split(" > ")[0];
    const elsewhere = region !== "" && region_paths.length > 0 &&
      region_paths.every((l) => l.split(" > ")[0] !== top);
    if (
      !elsewhere &&
      (style.names.label_patterns ?? []).some((p) =>
        namesOutsideGrapes(label, p)
      )
    ) depth = Math.max(depth, 2);
    if (depth && (!best || depth >= best.depth)) {
      best = { depth, key: style.key };
    }
  }
  return best?.key ?? null;
}
