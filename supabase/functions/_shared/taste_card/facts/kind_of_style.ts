/**
 * The kind a style key belongs to. A catalog bottle carries a kind
 * (red_wine, junmai), but a card may carry a regional style read off the
 * bottle's region (barolo_red, champagne_sparkling) or an older spelling the
 * dictionary redirects. Counts are kept by kind, so both are read as theirs.
 */
import dictionary from "../../../../../catalog/dictionary/terms.json" with {
  type: "json",
};
import { terms } from "../dictionary/dictionary.ts";

const REDIRECTS =
  (dictionary as unknown as { style_redirects: Record<string, string> })
    .style_redirects;

const KIND_OF_COLOR: Readonly<Record<string, string>> = {
  red: "red_wine",
  white: "white_wine",
  rose: "rose_wine",
  sparkling: "sparkling_wine",
};

/** A regional style names its colour, or (the Douro's port) the kinds it covers, the narrowest last. */
const KIND_OF_REGIONAL: ReadonlyMap<string, string> = new Map(
  terms("regional_style").flatMap((term) => {
    const kinds = term.hints?.style_keys;
    const kind = Array.isArray(kinds) && kinds.length > 0
      ? kinds[kinds.length - 1]
      : KIND_OF_COLOR[String(term.hints?.color)];
    return typeof kind === "string" ? [[term.key, kind] as const] : [];
  }),
);

export function kindOfStyle(
  styleKey: string | null | undefined,
): string | null {
  if (!styleKey) return null;
  return KIND_OF_REGIONAL.get(styleKey) ?? REDIRECTS[styleKey] ?? styleKey;
}
