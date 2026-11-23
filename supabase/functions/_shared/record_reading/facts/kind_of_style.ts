/**
 * The kind a style key belongs to. A catalog bottle carries a kind
 * (red_wine, junmai), but a card may carry a regional style read off the
 * bottle's region (barolo_red, champagne_sparkling) or an older spelling the
 * dictionary redirects. Counts are kept by kind, so both are read as theirs.
 */
import contract from "../../../../../config/catalog/enrichment_taxonomy_v2.json" with {
  type: "json",
};
import { terms } from "../dictionary/dictionary.ts";

/** Older kind keys the DB term contract still accepts, and the kind each now means. */
const REDIRECTS =
  (contract as unknown as { style_redirects: Record<string, string> })
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
    const kind = term.kind_keys?.at(-1) ?? KIND_OF_COLOR[term.color ?? ""];
    return kind ? [[term.key, kind] as const] : [];
  }),
);

export function kindOfStyle(
  styleKey: string | null | undefined,
): string | null {
  if (!styleKey) return null;
  return KIND_OF_REGIONAL.get(styleKey) ?? REDIRECTS[styleKey] ?? styleKey;
}
