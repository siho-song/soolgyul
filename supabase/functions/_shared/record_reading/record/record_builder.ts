// Builds the record the card engine reads: the reader's answers, normalized,
// and the product as the catalog describes it.
import {
  AssignmentTarget,
  catalogAssignments,
} from "../../catalog/assignment.ts";
import { type AlcoholCategory, isAlcoholCategory } from "../../contract.ts";
import { TASTING_LEVEL_COLUMNS } from "../../database/bottles.ts";
import { senseChoiceByKey, senseChoiceOfTag } from "../dictionary/aromas.ts";
import { drinkName, regionPath } from "../dictionary/dictionary.ts";
import { groupOfAroma } from "../facts/aroma_groups.ts";
import { normalizeSensoryAnswers } from "./answer_normalization.ts";
import {
  gaugeSheet,
  type SensoryOption,
  sensoryOption,
} from "./questionnaire.ts";
import type {
  SensoryDimension,
  SensoryProduct,
  SensoryProductDescriptor,
  SensoryRecord,
  SensoryScore,
} from "./sensory_record.ts";
import type { QuestionnaireAnswerInput } from "./questionnaire.ts";

/** Texture words the tags spell differently from the dictionary. */
const TEXTURE_ALIASES: Readonly<Record<string, string>> = {
  smooth: "soft_texture",
  tannin_smooth: "soft_texture",
};

const TAG_SECTIONS = [
  ["aroma_tags", "aroma"],
  ["palate_tags", "palate"],
  ["finish_tags", "finish"],
] as const;
/**
 * The product as one catalog item row and its tasting profile describe it.
 * Rows come straight from PostgREST (`alcohol_items` with its category,
 * `alcohol_tasting_profiles`).
 */
export function catalogProduct(
  item: Record<string, unknown>,
  profile: Record<string, unknown> | null,
): SensoryProduct {
  const abv = typeof item.abv_percent === "number" &&
      Number.isFinite(item.abv_percent)
    ? item.abv_percent
    : null;
  const taxonomyKeys = validTaxonomyKeys(item);
  const levels: Partial<Record<SensoryDimension, SensoryScore>> = {};
  const levelSources: Partial<Record<SensoryDimension, number>> = {};
  const sources = profile?.level_sources;
  for (const column of TASTING_LEVEL_COLUMNS) {
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
    producer: producerName(item.producer),
    vintageYear: wholeNumber(item.vintage_year),
    ageStatementYears: wholeNumber(item.age_statement_years),
    levels,
    levelSources,
    descriptors: profile ? profileDescriptors(profile) : [],
  };
}

function producerName(value: unknown): string | null {
  const producer = relatedRecord(value);
  return optionalNonEmptyString(producer.name_ko) ??
    optionalNonEmptyString(producer.name_en);
}

function wholeNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

/**
 * The reader's answers as the engine reads them, with the product they were
 * about: the card's input. An option the registry does not hold says nothing.
 */
export function buildSensoryRecord(
  recordRef: string,
  answers: readonly QuestionnaireAnswerInput[],
  product: SensoryProduct,
): SensoryRecord {
  const selected: SensoryOption[] = [];
  for (const answer of answers) {
    for (const key of answer.selected_option_keys) {
      const option = sensoryOption(key);
      if (option) selected.push(option);
    }
  }
  const sheet = gaugeSheet(product.category, product.styleKey);
  const asked = new Set(
    [...sheet.palate, ...sheet.finish].map((row) => row.axis),
  );
  return {
    recordRef,
    product,
    ...normalizeSensoryAnswers(selected, asked),
  };
}

/** The category's Korean name for the card header. */
export function categoryLabel(category: AlcoholCategory | null): string | null {
  if (!category) return null;
  return drinkName(category);
}

function profileDescriptors(
  profile: Record<string, unknown>,
): SensoryProductDescriptor[] {
  const descriptors = new Map<string, SensoryProductDescriptor>();
  // A bottle's aromas are its tags alone; no note text is read for more.
  for (const [column, section] of TAG_SECTIONS) {
    for (const tag of stringArray(profile[column])) {
      const choice = senseChoiceByKey(
        senseChoiceOfTag(tag) ?? TEXTURE_ALIASES[tag] ?? "",
      );
      if (!choice) continue;
      descriptors.set(`${section}:${choice.key}`, {
        key: choice.key,
        section,
        label: choice.label,
        family: groupOfAroma(choice.key) ?? choice.group ?? "fermented",
        traits: choice.traits,
        // Only the name's own dictionary entry explains it.
        description: choice.description,
        evidenceRefs: [column],
      });
    }
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

/** The strings of a list column in the order the catalog keeps them: a wine's grapes are listed main grape first. */
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
    ].slice(0, 64)
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

function alcoholCategory(value: unknown): AlcoholCategory | null {
  return isAlcoholCategory(value) ? value : null;
}
