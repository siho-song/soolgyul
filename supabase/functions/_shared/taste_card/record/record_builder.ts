// Builds the record the card engine reads: the reader's answers, normalized,
// and the product as the catalog describes it.
import {
  AssignmentTarget,
  catalogAssignments,
} from "../../catalog/assignment.ts";
import { ALCOHOL_CATEGORY_KEYS, type AlcoholCategory } from "../../contract.ts";
import {
  regionPath,
  serviceVocabulary as vocabulary,
  taxonomy,
} from "../dictionary/dictionary.ts";
import { AROMA_TO_NICKNAME_GROUP_V1 } from "../nickname/catalog.ts";
import { normalizeSensoryAnswers } from "./answer_normalization.ts";
import type { SensoryKnowledgeRegistry } from "../dictionary/sensory_knowledge.ts";
import { sensoryOptionsV1, type SensoryOptionV1 } from "./questionnaire.ts";
import type {
  SensoryDimension,
  SensoryProduct,
  SensoryProductDescriptor,
  SensoryRecord,
  SensoryScore,
} from "./sensory_record.ts";
import type { QuestionnaireAnswerInput } from "../service/types.ts";

const options = new Map(
  sensoryOptionsV1().map((option) => [option.option_key, option]),
);
const groups = new Map(vocabulary.groups.map((group) => [group.key, group]));
const aliases = new Map(
  vocabulary.groups.flatMap((group) =>
    [group.key, ...group.source_keys].map((key) => [key, group.key] as const)
  ),
);
/** Texture words the tags spell differently from the dictionary. */
const TEXTURE_ALIASES: Readonly<Record<string, string>> = {
  smooth: "soft_texture",
  tannin_smooth: "soft_texture",
};

/** The level columns of alcohol_tasting_profiles, every value a 1–5 integer. */
const LEVEL_COLUMNS = [
  "sweetness",
  "acidity",
  "bitterness",
  "astringency",
  "body",
  "carbonation",
  "aroma_intensity",
  "finish_length",
  "finish_cleanliness",
] as const satisfies readonly SensoryDimension[];

const TAG_SECTIONS = [
  ["aroma_tags", "aroma"],
  ["palate_tags", "palate"],
  ["finish_tags", "finish"],
] as const;
const NOTE_SECTIONS = [
  ["aroma_note", "aroma"],
  ["palate_note", "palate"],
] as const;

// Product notes can retain a concrete descriptor that the questionnaire groups.
// This does not split the questionnaire dictionary or infer details from a group.
const noteNames = vocabulary.groups.filter((group) =>
  group.domain === "descriptor"
).flatMap((group) =>
  [...new Set([group.label_ko, ...group.user_source_labels])].map((label) => ({
    key: group.key,
    phases: group.phases,
    pattern: new RegExp(
      `(?:^|[\\s·,/()])${label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}${
        group.key === "musk" ? "(?![\\s(（-]*(?:멜론|메론))" : ""
      }(?=$|[\\s·,/()]|향|풍미|은|는|이|가|와|과|을|를|의)`,
    ),
  }))
);

type NoteDescriptor = { key: string; label?: string; traits?: string[] };

/** Descriptors a catalog note states outright; comparisons and negations are skipped. */
function explicitNoteDescriptors(
  note: string,
  section: string,
): NoteDescriptor[] {
  // Deliberately do not interpret comparative, negated or hypothetical prose.
  const clauses = note.split(/[.!?。;\n]+/).filter((clause) =>
    !/없|아니(?!스)|않|못|무향|보다|대신|라면|같다면|\b(?:no|not|without|rather|if)\b/i
      .test(clause)
  );
  const matches: NoteDescriptor[] = [];
  for (const clause of clauses) {
    for (const name of noteNames) {
      if (name.phases.includes(section) && name.pattern.test(clause)) {
        matches.push({ key: name.key });
      }
    }
    if (
      /(?:^|[\s·,/()])(?:요거트|요구르트)(?=$|[\s·,/()]|향|풍미|은|는|이|가|와|과|을|를|의)/
        .test(clause)
    ) {
      matches.push({
        key: "lactic",
        label: "요거트",
        traits: ["lactic_scent"],
      });
    }
  }
  return matches;
}

/**
 * The product as one catalog item row and its tasting profile describe it.
 * Rows come straight from PostgREST (`alcohol_items` with its category,
 * `alcohol_tasting_profiles`); knowledge is the bundled sensory dictionary.
 */
export function catalogProduct(
  item: Record<string, unknown>,
  profile: Record<string, unknown> | null,
  knowledge: SensoryKnowledgeRegistry,
): SensoryProduct {
  const abv = typeof item.abv_percent === "number" &&
      Number.isFinite(item.abv_percent)
    ? item.abv_percent
    : null;
  const taxonomyKeys = validTaxonomyKeys(item);
  const levels: Partial<Record<SensoryDimension, SensoryScore>> = {};
  const levelSources: Partial<Record<SensoryDimension, number>> = {};
  const sources = profile?.level_sources;
  for (const column of LEVEL_COLUMNS) {
    const level = profile?.[column];
    if (
      typeof level !== "number" || !Number.isInteger(level) || level < 1 ||
      level > 5
    ) continue;
    levels[column] = level as SensoryScore;
    const grade = sources && typeof sources === "object"
      ? (sources as Record<string, unknown>)[column]
      : undefined;
    if (typeof grade === "number" && Number.isInteger(grade)) {
      levelSources[column] = grade;
    }
  }
  return {
    name: firstNonEmptyString(item.name_ko, item.name_en),
    category: alcoholCategory(relatedRecord(item.category).category_key),
    styleKey: optionalNonEmptyString(item.style_key),
    region: regionPath(item.region_key),
    abv,
    ingredients: taxonomyKeys.ingredient_keys,
    grapeVarietyKeys: stringArray(item.grape_variety_keys),
    processes: taxonomyKeys.production_process_keys,
    levels,
    levelSources,
    descriptors: profile ? profileDescriptors(profile, knowledge) : [],
  };
}

/** The reader's answers normalized against the product: the card's input. */
export function buildSensoryRecord(
  recordRef: string,
  answers: readonly QuestionnaireAnswerInput[],
  product: SensoryProduct,
  knowledge: SensoryKnowledgeRegistry = {},
): SensoryRecord {
  const selected: SensoryOptionV1[] = [];
  for (const answer of answers) {
    for (const key of answer.selected_option_keys) {
      const option = options.get(key);
      if (option) selected.push(option);
    }
  }
  return {
    recordRef,
    product,
    ...normalizeSensoryAnswers(selected, knowledge),
  };
}

/** The category's Korean name for the card header. */
export function categoryLabel(category: AlcoholCategory | null): string | null {
  if (!category) return null;
  return taxonomy.categories.find((entry) =>
    (entry as { category_key?: string }).category_key === category
  )?.name_ko ?? null;
}

function profileDescriptors(
  profile: Record<string, unknown>,
  knowledge: SensoryKnowledgeRegistry,
): SensoryProductDescriptor[] {
  const descriptors = new Map<string, SensoryProductDescriptor>();
  const add = (
    section: SensoryProductDescriptor["section"],
    candidates: readonly NoteDescriptor[],
    ref: string,
  ) => {
    for (const candidate of candidates) {
      const specificNote = "label" in candidate ? candidate : null;
      const key = specificNote?.key ?? aliases.get(candidate.key) ??
        TEXTURE_ALIASES[candidate.key];
      const group = key ? groups.get(key) : null;
      if (!key || (!group && !specificNote)) continue;
      const definition = knowledge[`sensory_descriptor:${key}`];
      const id = `${section}:${key}`;
      const previous = descriptors.get(id);
      descriptors.set(id, {
        key,
        section,
        label: specificNote?.label ?? definition?.card_label_ko ??
          group!.label_ko,
        family: AROMA_TO_NICKNAME_GROUP_V1[group?.key ?? "fermentation"] ??
          group?.category_key ?? "fermented",
        traits: specificNote?.traits ?? definition?.sensory_trait_keys ?? [],
        // Notes prove a feature is present; only its exact dictionary entry
        // explains it. A broad group definition cannot explain a specific note.
        description: definition?.sensory_description ?? null,
        evidenceRefs: [...new Set([...(previous?.evidenceRefs ?? []), ref])]
          .sort(),
      });
    }
  };
  for (const [column, section] of TAG_SECTIONS) {
    add(section, stringArray(profile[column]).map((key) => ({ key })), column);
  }
  for (const [column, section] of NOTE_SECTIONS) {
    const note = boundedCatalogText(profile[column]);
    if (note) add(section, explicitNoteDescriptors(note, section), column);
  }
  return [...descriptors.values()].sort((a, b) =>
    `${a.section}:${a.key}`.localeCompare(`${b.section}:${b.key}`)
  );
}

/** Ingredient and process keys the taxonomy accepts for the item; invalid rows yield none. */
function validTaxonomyKeys(
  item: Record<string, unknown>,
): Record<"ingredient_keys" | "production_process_keys", string[]> {
  const columns = ["ingredient_keys", "production_process_keys"] as const;
  const validation = catalogAssignments.validate({
    category_key: relatedRecord(item.category).category_key,
    style_key: item.style_key ?? null,
    target: AssignmentTarget.Product,
    ...Object.fromEntries(columns.map((column) => [
      column,
      Object.hasOwn(item, column) ? item[column] : [],
    ])),
  });
  // Invalid taxonomy is not evidence; never repair saved keys at card time.
  if (!validation.value) {
    return { ingredient_keys: [], production_process_keys: [] };
  }
  return {
    ingredient_keys: [...validation.value.values.ingredient_keys],
    production_process_keys: [
      ...validation.value.values.production_process_keys,
    ],
  };
}

function boundedCatalogText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.normalize("NFC").trim();
  return normalized.length > 0 && normalized.length <= 1_200
    ? normalized
    : null;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? [
      ...new Set(value.flatMap((item) => {
        if (typeof item !== "string") return [];
        const normalized = item.normalize("NFC").trim().toLowerCase();
        return normalized.length > 0 && normalized.length <= 120
          ? [normalized]
          : [];
      })),
    ].sort().slice(0, 64)
    : [];
}

function relatedRecord(value: unknown): Record<string, unknown> {
  const record = Array.isArray(value) ? value[0] : value;
  return record !== null && typeof record === "object"
    ? record as Record<string, unknown>
    : {};
}

function optionalNonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function firstNonEmptyString(...values: readonly unknown[]): string {
  for (const value of values) {
    const text = optionalNonEmptyString(value);
    if (text !== null) return text;
  }
  return "";
}

const categoryKeys = new Set<string>(ALCOHOL_CATEGORY_KEYS);

function alcoholCategory(value: unknown): AlcoholCategory | null {
  return typeof value === "string" && categoryKeys.has(value)
    ? value as AlcoholCategory
    : null;
}
