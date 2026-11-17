/**
 * 읽기: one record's gauges and aromas and its product become the gauge,
 * reaction and product facts of a card. No knowledge is applied here; the
 * eight thinkings read these facts later.
 *
 * A gauge is kept as the reader set it and also read into the engine's own
 * words, by its step (2026-11-16):
 *   단맛·산미·감칠맛   taste; liked 4–5 pronounced, 1–2 gentle; minded 4–5
 *                     excessive, 1–2 too_weak; the middle step names no side
 *   바디              1–2 light, 4–5 heavy; the middle step makes no reaction
 *   타닌              1–2 smooth, 4–5 drying; the middle step makes no reaction
 *   탄산 · 스파이시     bubbles, warmth from step 2, with the taste's qualifiers
 *   피트              the 피트 aroma from step 2
 *   여운의 길이        liked 4–5 a long finish, liked 1–2 a clean one; minded
 *                     1–2 too brief, minded 4–5 lingering
 *   끝맛의 인상        its own finish subject at every step
 * The lowest step of 탄산, 스파이시 and 피트 says there was none of it, so it
 * stays a gauge and makes no reaction.
 */
import { styleProfiles } from "../dictionary/dictionary.ts";
import { alcoholLevelFromAbv } from "./abv_levels.ts";
import { type TableDimension, tableLevels } from "./kind_table_levels.ts";
import { isEstimatedLevelSource } from "./level_sources.ts";
import type {
  SensoryGauge,
  SensoryProduct,
  SensoryRecord,
} from "../record/sensory_record.ts";
import {
  AROMA_KEYS,
  AROMA_STAGES,
  type AromaStage,
  type CardFacts,
  LEVEL_DIMENSIONS,
  type LevelDimension,
  MOUTHFEEL_KEYS,
  type ProductFact,
  type Qualifier,
  type ReactionFact,
  type Subject,
  TASTE_KEYS,
} from "./facts.ts";

export type CardReading = Pick<
  CardFacts,
  "record" | "gauges" | "reactions" | "product_facts"
>;

const unique = (values: readonly string[]) => [...new Set(values)].sort();

type Drafted = Omit<ReactionFact, "id"> & { order: number };

/** The side a step names: 4–5 the strong one, 1–2 the mild one, the middle neither. */
function strengthSaid(gauge: SensoryGauge): Qualifier | null {
  if (gauge.level === 3) return null;
  const strong = gauge.level > 3;
  return gauge.reaction === "liked"
    ? (strong ? "pronounced" : "gentle")
    : (strong ? "excessive" : "too_weak");
}

/** What one gauge says in the engine's words, or null for a step that says nothing there. */
function gaugeReaction(
  gauge: SensoryGauge,
): Pick<Drafted, "subject" | "phase" | "qualifier" | "order"> | null {
  const { axis, level, reaction } = gauge;
  const taste = (key: typeof TASTE_KEYS[number]) => ({
    subject: { domain: "taste", key } as Subject,
    phase: "drinking" as const,
    qualifier: strengthSaid(gauge),
    order: 100 + TASTE_KEYS.indexOf(key),
  });
  const mouthfeel = (
    key: typeof MOUTHFEEL_KEYS[number],
    qualifier: Qualifier | null,
  ) => ({
    subject: { domain: "mouthfeel", key } as Subject,
    phase: "drinking" as const,
    qualifier,
    order: 200 + MOUTHFEEL_KEYS.indexOf(key),
  });
  const finish = (
    key: "persistence" | "clean" | "character",
    qualifier: Qualifier | null,
    order: number,
  ) => ({
    subject: { domain: "finish", key } as Subject,
    phase: "finish" as const,
    qualifier,
    order,
  });
  switch (axis) {
    case "sweetness":
      return taste("sweetness");
    case "acidity":
      return taste("acidity");
    case "umami":
      return taste("umami");
    case "body":
      return level === 3
        ? null
        : mouthfeel(level < 3 ? "light" : "heavy", null);
    case "tannin":
      return level === 3
        ? null
        : mouthfeel(level < 3 ? "smooth" : "drying", null);
    case "sparkling":
      return level === 1 ? null : mouthfeel("bubbles", strengthSaid(gauge));
    case "spice":
      return level === 1 ? null : mouthfeel("warmth", strengthSaid(gauge));
    case "peat":
      // Read as the 피트 aroma; an aroma carries no strength.
      return level === 1 ? null : {
        subject: { domain: "aroma", key: "peat" },
        phase: "drinking",
        qualifier: null,
        order: 0,
      };
    case "finish_length":
      if (level === 3) return null;
      if (reaction === "liked") {
        return level > 3
          ? finish("persistence", null, 300)
          : finish("clean", null, 301);
      }
      return finish("persistence", level > 3 ? "lingering" : "too_brief", 300);
    case "finish_character":
      return finish("character", null, 302);
  }
}

function readReactions(record: SensoryRecord): ReactionFact[] {
  const drafted: Drafted[] = [];
  for (const gauge of record.gauges) {
    const said = gaugeReaction(gauge);
    if (said) {
      drafted.push({
        kind: "reaction",
        ...said,
        reaction: gauge.reaction,
        answer_refs: [gauge.answerRef],
      });
    }
  }
  for (const aroma of record.aromas) {
    const finish = aroma.stage === "finish";
    drafted.push({
      kind: "reaction",
      subject: { domain: "aroma", key: aroma.key },
      phase: finish ? "finish" : "drinking",
      reaction: aroma.reaction,
      qualifier: null,
      stages: [aroma.stage],
      answer_refs: [aroma.answerRef],
      order: finish ? 310 : 0,
    });
  }
  // What stayed in the nose after swallowing, as one answer of the finish: the
  // liked finish aromas are the 잔향, the minded ones what bothered there.
  for (
    const [reaction, key, order] of [
      ["liked", "aroma_echo", 320],
      ["burden", "off_flavor", 321],
    ] as const
  ) {
    const stayed = record.aromas.filter((aroma) =>
      aroma.stage === "finish" && aroma.reaction === reaction
    );
    if (stayed.length) {
      drafted.push({
        kind: "reaction",
        subject: { domain: "finish", key },
        phase: "finish",
        reaction,
        qualifier: "lingering",
        answer_refs: unique(stayed.map((aroma) => aroma.answerRef)),
        order,
      });
    }
  }
  // One aroma taken one way while drinking is one reaction, whichever of the
  // nose, the mouth and the 피트 gauge named it.
  const merged: Drafted[] = [];
  for (const draft of drafted) {
    const same = draft.subject.domain === "aroma"
      ? merged.find((other) =>
        other.subject.domain === "aroma" &&
        other.subject.key === draft.subject.key &&
        other.phase === draft.phase && other.reaction === draft.reaction
      )
      : undefined;
    if (!same) {
      merged.push({ ...draft });
      continue;
    }
    same.answer_refs = unique([...same.answer_refs, ...draft.answer_refs]);
    const stages = [...(same.stages ?? []), ...(draft.stages ?? [])];
    if (stages.length) {
      same.stages = AROMA_STAGES.filter((stage: AromaStage) =>
        stages.includes(stage)
      );
    }
  }
  merged.sort((a, b) =>
    a.order - b.order || a.subject.key.localeCompare(b.subject.key) ||
    // A liked answer precedes the minded one of the same sensation.
    b.reaction.localeCompare(a.reaction)
  );
  return merged.map(({ order: _order, ...fact }, i) => ({
    id: `r${i + 1}`,
    ...fact,
  }));
}

function readProductFacts(product: SensoryProduct): ProductFact[] {
  const facts: { fact: ProductFact["fact"]; source: string }[] = [];
  // A level nobody read for this bottle is the kind's usual one from the
  // style table, spoken of as the kind, never as this bottle (estimated).
  const table = tableLevels(product.styleKey);
  // Alcohol presence is the bottle's strength against its kind's usual one,
  // read from the ABV whenever the catalog states it.
  const fromAbv = alcoholLevelFromAbv(
    product.abv,
    product.styleKey,
    product.category,
  );
  for (const dimension of LEVEL_DIMENSIONS) {
    const level = product.levels[dimension as LevelDimension];
    if (dimension === "alcohol_presence" && fromAbv !== null) {
      facts.push({
        fact: { type: "level", dimension, level: fromAbv.level },
        source: `catalog:abv_band:${fromAbv.scope}`,
      });
    } else if (level) {
      const origin = product.levelSources?.[dimension as LevelDimension];
      const estimated = isEstimatedLevelSource(origin);
      facts.push({
        fact: estimated
          ? { type: "level", dimension, level, estimated: true }
          : { type: "level", dimension, level },
        source: origin ? `catalog:levels:${origin}` : "catalog:levels",
      });
    } else if (table[dimension as TableDimension]) {
      facts.push({
        fact: {
          type: "level",
          dimension,
          level: table[dimension as TableDimension]!,
          estimated: true,
        },
        source: `catalog:style_table:${product.styleKey}`,
      });
    }
  }
  const sectionOrder = ["aroma", "palate", "finish", "texture"] as const;
  for (const section of sectionOrder) {
    const descriptors = product.descriptors.filter((d) => d.section === section)
      .sort((a, b) => a.key.localeCompare(b.key));
    for (const descriptor of descriptors) {
      // A texture word among the palate or finish tags (smooth_texture,
      // firm_structure) is no flavour; it counts by its traits, as the texture
      // section does.
      if (section === "texture" || !AROMA_KEYS.has(descriptor.key)) {
        for (const trait of unique(descriptor.traits)) {
          facts.push({
            fact: { type: "trait", key: trait },
            source: "catalog:texture_text",
          });
        }
      } else {
        facts.push({
          fact: { type: "descriptor", key: descriptor.key, section },
          source: section === "aroma" ? "catalog:aromas" : `catalog:${section}`,
        });
      }
    }
  }
  if (product.abv !== null) {
    facts.push({
      fact: { type: "abv", value: product.abv },
      source: "catalog:abv",
    });
  }
  if (product.styleKey) {
    facts.push({
      fact: { type: "style", key: product.styleKey },
      source: "catalog:style",
    });
  }
  // Grape entries (까베르네 소비뇽) and a wine region entry (샴페인, 보르도
  // 좌안) refine the base style; they come after it so the narrower entry
  // wins where both speak.
  for (const key of wineGrapeKeys(product)) {
    facts.push({
      fact: { type: "style", key },
      source: "catalog:grape",
    });
  }
  const region = wineRegionKey(product);
  if (region) {
    facts.push({
      fact: { type: "style", key: region },
      source: "catalog:region",
    });
  }
  for (const key of unique(product.ingredients ?? [])) {
    facts.push({
      fact: { type: "ingredient", key },
      source: "catalog:ingredients",
    });
  }
  for (const key of unique(product.processes ?? [])) {
    facts.push({
      fact: { type: "production", key },
      source: "catalog:production",
    });
  }
  const seen = new Set<string>();
  return facts.filter(({ fact }) => {
    const signature = JSON.stringify(fact);
    if (seen.has(signature)) return false;
    seen.add(signature);
    return true;
  }).map((entry, i) => ({ id: `p${i + 1}`, kind: "product", ...entry }));
}

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
 * The deepest wine region entry the product falls in, as the catalog tools
 * resolve it (tools/catalog/sensory/style_profiles.py): a region label or a
 * sub-label of it, or an appellation in the name unless the region is
 * elsewhere. Grape names never read as regions ("melon de bourgogne").
 */
export function wineRegionKey(product: SensoryProduct): string | null {
  const styleKey = product.styleKey ?? "";
  const color = WINE_COLORS[styleKey];
  const region = product.region ?? "";
  let name = product.name.toLowerCase();
  for (const pattern of GRAPE_PATTERNS) name = name.replaceAll(pattern, " ");
  let best: { depth: number; key: string } | null = null;
  for (const entry of WINE_REGIONS) {
    const { match } = entry;
    if (match.style_keys) {
      if (!match.style_keys.includes(styleKey)) continue;
    } else if (!color || (entry.color !== color && entry.color !== "any")) {
      continue;
    }
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

/** Reads one record into card facts. Pure; the same record always reads the same. */
export function readCard(record: SensoryRecord): CardReading {
  const { product } = record;
  return {
    record: {
      product_name: product.name,
      category: product.category,
      style_key: wineRegionKey(product) ?? product.styleKey,
      revisit: record.revisit.intent ?? "unknown",
    },
    gauges: record.gauges.map((gauge) => ({
      axis: gauge.axis,
      level: gauge.level,
      reaction: gauge.reaction,
      answer_ref: gauge.answerRef,
    })),
    reactions: readReactions(record),
    product_facts: readProductFacts(product),
  };
}
