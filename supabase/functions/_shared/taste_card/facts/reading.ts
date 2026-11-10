/**
 * 읽기: one record's normalized answers and its product become the reaction
 * and product facts of a card. No knowledge is applied here; the seven
 * thinkings read these facts later.
 */
import { styleProfiles } from "../dictionary/dictionary.ts";
import { alcoholLevelFromAbv } from "./abv_levels.ts";
import { type TableDimension, tableLevels } from "./kind_table_levels.ts";
import { isEstimatedLevelSource } from "./level_sources.ts";
import type {
  SensoryAnswer,
  SensoryProduct,
  SensoryRecord,
} from "../record/sensory_record.ts";
import {
  AROMA_KEYS,
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
  "record" | "reactions" | "product_facts"
>;

const MOUTHFEEL_SUBJECTS: Readonly<Record<string, Subject>> = {
  "body.weight_light": { domain: "mouthfeel", key: "light" },
  "body.weight_full": { domain: "mouthfeel", key: "heavy" },
  "texture.smooth": { domain: "mouthfeel", key: "smooth" },
  "texture.astringency": { domain: "mouthfeel", key: "drying" },
  "carbonation.intensity": { domain: "mouthfeel", key: "bubbles" },
  "alcohol.heat": { domain: "mouthfeel", key: "warmth" },
};

/** Finish answers in questionnaire order: what remained, and how the card names it. */
const FINISH_ANSWERS: readonly {
  key: string;
  subject: Subject;
  qualifier: Qualifier | null;
}[] = [
  {
    key: "finish.persistence",
    subject: { domain: "finish", key: "persistence" },
    qualifier: null,
  },
  {
    key: "finish.cleanliness",
    subject: { domain: "finish", key: "clean" },
    qualifier: null,
  },
  {
    key: "finish.length_short",
    subject: { domain: "finish", key: "persistence" },
    qualifier: "too_brief",
  },
  {
    key: "finish.weight",
    subject: { domain: "mouthfeel", key: "heavy" },
    qualifier: "lingering",
  },
  // 2026-11-06: the finish asks only what the drinking pages cannot: the
  // length, whether the mouth cleared, and what came up the nose afterwards.
  {
    key: "finish.aroma_echo",
    subject: { domain: "finish", key: "aroma_echo" },
    qualifier: "lingering",
  },
  {
    key: "finish.off_flavor",
    subject: { domain: "finish", key: "off_flavor" },
    qualifier: "lingering",
  },
];

/** Reason meanings from the questionnaire, in the order one qualifier is chosen. */
const REASON_QUALIFIERS: readonly [string, Qualifier][] = [
  ["distinctIntensityAccepted", "pronounced"],
  ["gentleIntensityAccepted", "gentle"],
  ["harmonious", "harmonious"],
  ["excessiveIntensity", "excessive"],
  ["wantsMoreIntensity", "too_weak"],
  ["masksOtherSensations", "masking"],
  ["disharmonious", "disharmonious"],
];

const unique = (values: readonly string[]) => [...new Set(values)].sort();

type Drafted = Omit<ReactionFact, "id"> & { order: number };

function drinkingReaction(answer: SensoryAnswer): Drafted | null {
  if (
    answer.reaction !== "positive" && answer.reaction !== "burden" &&
    answer.reaction !== "neutral"
  ) {
    return null;
  }
  let subject: Subject;
  let order: number;
  if (answer.key.startsWith("aroma.")) {
    subject = { domain: "aroma", key: answer.key.slice(6) };
    order = 0;
  } else if (answer.key.startsWith("taste.")) {
    const key = answer.key.slice(6) as typeof TASTE_KEYS[number];
    const index = TASTE_KEYS.indexOf(key);
    if (index < 0) return null;
    subject = { domain: "taste", key };
    order = 100 + index;
  } else {
    const mouthfeel = MOUTHFEEL_SUBJECTS[answer.key];
    if (!mouthfeel) return null;
    subject = mouthfeel;
    order = 200 +
      MOUTHFEEL_KEYS.indexOf(mouthfeel.key as typeof MOUTHFEEL_KEYS[number]);
  }
  const qualifier =
    REASON_QUALIFIERS.find(([meaning]) => answer.reasons.includes(meaning))
      ?.[1] ?? null;
  return {
    kind: "reaction",
    subject,
    phase: "drinking",
    reaction: answer.reaction === "positive"
      ? "liked"
      : answer.reaction === "neutral"
      ? "fine"
      : "burden",
    qualifier,
    focus: answer.reasons.length > 0,
    answer_refs: unique([...answer.answerRefs, ...answer.reasonRefs]),
    order,
  };
}

function finishReaction(answer: SensoryAnswer): Drafted | null {
  const index = FINISH_ANSWERS.findIndex((entry) => entry.key === answer.key);
  if (index < 0) return null;
  const entry = FINISH_ANSWERS[index];
  return {
    kind: "reaction",
    subject: entry.subject,
    phase: "finish",
    reaction: answer.reaction === "positive"
      ? "liked"
      : answer.reaction === "burden"
      ? "burden"
      : "unstated",
    qualifier: entry.qualifier,
    focus: false,
    answer_refs: unique(answer.answerRefs),
    // A liked finish answer precedes its burden counterpart on the same axis.
    order: 300 + index * 2 + (answer.reaction === "burden" ? 1 : 0),
  };
}

function readReactions(answers: readonly SensoryAnswer[]): ReactionFact[] {
  const drafted = answers.map((answer) =>
    answer.domain === "finish" || answer.phase === "finish"
      ? finishReaction(answer)
      : drinkingReaction(answer)
  ).filter((entry): entry is Drafted => entry !== null);
  drafted.sort((a, b) =>
    a.order - b.order || a.subject.key.localeCompare(b.subject.key)
  );
  return drafted.map(({ order: _order, ...fact }, i) => ({
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
      section_states: {
        aroma: record.sectionStates.aroma.state,
        taste: record.sectionStates.taste.state,
        mouthfeel: record.sectionStates.mouthfeel.state,
        finish: record.sectionStates.finish.state,
      },
    },
    reactions: readReactions(record.answers),
    product_facts: readProductFacts(product),
  };
}
