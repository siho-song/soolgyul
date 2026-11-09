/**
 * 종류별 공통 지식: the lines a product's style entries bring to one card.
 *
 * A product can carry several entries of the style table: its base style
 * (레드 와인), the casks and processes it went through (셰리 캐스크), the grape
 * varieties it is made from (까베르네 소비뇽), and a wine region (보르도 좌안).
 * The narrower entry refines the broader one where both speak: a region over
 * a grape, a grape or a process over the base style. The grapes
 * of a blend speak about a level only where they agree with each other; every
 * grape's aroma lines stay, because a card only ever explains an aroma the
 * reader named. The result does not depend on the order of the entries. (The
 * catalog tool that fills product levels, tools/catalog/sensory/style_profiles.py,
 * applies the same level rule.)
 */
import { styleProfiles } from "./dictionary.ts";
import { sameAromaLine } from "./aroma_lineage.ts";

export type StyleEntryKind = "style" | "process" | "grape" | "region";
export type StyleTrait = { level?: string; reason_ko?: string };
/** An aroma line: the reason, and where that aroma comes from in this kind (원료·익힘·효모·누룩·통·숙성·첨가·공정 and a short noun). */
export type StyleAroma = {
  key: string;
  reason_ko?: string;
  source_kind?: string;
  source_ko?: string;
};
export type StyleEntry = {
  key: string;
  name_ko: string;
  kind: StyleEntryKind;
  /** A process entry's term before the kind: "셰리 캐스크" (위스키). */
  fact_ko?: string;
  traits: Readonly<Record<string, StyleTrait | undefined>>;
  aromas: readonly StyleAroma[];
  replaces_aromas?: readonly string[];
};
/** One line of the merged profile and the entry it came from. */
export type StyleTraitLine = StyleTrait & { source: string };
export type StyleAromaLine = StyleAroma & { source: string };
export type StyleProfile = {
  traits: Readonly<Record<string, StyleTraitLine>>;
  aromas: readonly StyleAromaLine[];
  /** The grape entries among the product's entries, by key. */
  grapes: readonly string[];
};

const DEPTH: Readonly<Record<StyleEntryKind, number>> = {
  style: 0,
  process: 1,
  grape: 2,
  region: 3,
};
const entries = new Map<string, StyleEntry>();
for (
  const [collection, kind] of [
    ["styles", "style"],
    ["processes", "process"],
    ["wine_grapes", "grape"],
    ["wine_regions", "region"],
  ] as const
) {
  for (
    const entry of (styleProfiles as unknown as Record<
      string,
      Omit<StyleEntry, "kind">[]
    >)[collection]
  ) {
    entries.set(entry.key, { ...entry, kind });
  }
}
/** Every style, grape and region entry of the table by key. */
export const STYLE_ENTRIES: ReadonlyMap<string, StyleEntry> = entries;

/** The profile the given entries make together. Unknown keys are ignored; null when none is known. */
export function mergedStyleProfile(
  keys: readonly string[],
): StyleProfile | null {
  const known = [...new Set(keys)].map((key) => entries.get(key)).filter((
    entry,
  ): entry is StyleEntry => entry !== undefined);
  if (known.length === 0) return null;
  const ordered = [...known].sort((a, b) =>
    DEPTH[a.kind] - DEPTH[b.kind] || a.key.localeCompare(b.key)
  );
  const traits: Record<string, StyleTraitLine> = {};
  const grapeClaims = new Map<string, StyleTraitLine[]>();
  for (const entry of ordered) {
    for (const [dimension, trait] of Object.entries(entry.traits)) {
      if (!trait) continue;
      const line = { ...trait, source: entry.key };
      if (entry.kind === "grape") {
        grapeClaims.set(dimension, [
          ...(grapeClaims.get(dimension) ?? []),
          line,
        ]);
      } else {
        traits[dimension] = line;
      }
    }
  }
  // Grapes sit between the base style and the region: they refine the style
  // where they agree; where they disagree the blend says nothing.
  for (const [dimension, claims] of grapeClaims) {
    const current = traits[dimension];
    const fromStyle = !current ||
      entries.get(current.source)?.kind === "style";
    if (!fromStyle) continue;
    if (new Set(claims.map((c) => c.level)).size === 1) {
      traits[dimension] = claims[0];
    } else {
      delete traits[dimension];
    }
  }
  const replaced = new Set(ordered.flatMap((e) => e.replaces_aromas ?? []));
  const aromas: StyleAromaLine[] = [];
  const seen = new Set<string>();
  for (const entry of [...ordered].reverse()) {
    for (const aroma of entry.aromas) {
      if (seen.has(aroma.key) || replaced.has(aroma.key)) continue;
      seen.add(aroma.key);
      aromas.push({ ...aroma, source: entry.key });
    }
  }
  return {
    traits,
    aromas,
    grapes: ordered.filter((e) => e.kind === "grape").map((e) => e.key),
  };
}

/** The first aroma line on the same line of the catalog tree as the given aroma, with a reason. */
export function styleAromaLine(
  profile: StyleProfile | null,
  aromaKey: string,
): StyleAromaLine | null {
  return profile?.aromas.find((a) =>
    sameAromaLine(a.key, aromaKey) && a.reason_ko
  ) ?? null;
}

/** The merged trait line of a level dimension, when it has a level and a reason. */
export function styleTraitLine(
  profile: StyleProfile | null,
  dimension: string,
): StyleTraitLine | null {
  const line = profile?.traits[dimension];
  return line?.level && line.reason_ko ? line : null;
}
