import { serviceVocabulary as vocabulary } from "../../_shared/record_reading/dictionary/dictionary.ts";
import {
  sensoryOption,
  validateSensoryAnswers,
} from "../../_shared/record_reading/record/questionnaire.ts";
import { buildSensoryRecord } from "../../_shared/record_reading/record/record_builder.ts";
import type {
  SensoryProduct,
  SensoryProductDescriptor,
  SensoryRecord,
} from "../../_shared/record_reading/record/sensory_record.ts";
import type { QuestionnaireAnswerInput } from "../../_shared/taste_card/service/types.ts";

/** Option keys as a request carries them: one answer per question, in the order first named. */
export function answersOf(
  keys: readonly string[],
): QuestionnaireAnswerInput[] {
  const byQuestion = new Map<string, string[]>();
  for (const key of keys) {
    const option = sensoryOption(key);
    if (!option) throw new Error(`unknown questionnaire option ${key}`);
    byQuestion.set(option.question_key, [
      ...(byQuestion.get(option.question_key) ?? []),
      key,
    ]);
  }
  return [...byQuestion].map(([question_key, selected_option_keys]) => ({
    question_key,
    selected_option_keys,
    free_text: null,
  }));
}

/**
 * A sensory record from questionnaire option keys and a product, built the
 * way a request is: the answers pass the questionnaire's check first. Keys
 * without a revisit answer get 잘 모르겠어요, which every record carries.
 */
export function recordFrom(
  recordRef: string,
  keys: readonly string[],
  product: SensoryProduct,
): SensoryRecord {
  const answers = answersOf(
    keys.some((key) => key.startsWith("revisit:"))
      ? keys
      : [...keys, "revisit:unsure"],
  );
  validateSensoryAnswers(answers);
  return buildSensoryRecord(recordRef, answers, product);
}

/** A catalog product sampled for the tests: its kind, levels and the aroma keys the catalog lists. */
export type CatalogSample = {
  id: string;
  name: string;
  category: string;
  style_key: string | null;
  abv: number | null;
  ingredients: readonly string[];
  processes: readonly string[];
  levels: SensoryProduct["levels"];
  level_sources?: SensoryProduct["levelSources"];
  aromas: readonly string[];
  texture: readonly string[];
};

/** The sampled catalog products (one file, six categories). */
export async function catalogSamples(): Promise<CatalogSample[]> {
  return JSON.parse(
    await Deno.readTextFile(
      new URL("../fixtures/sampled_products.json", import.meta.url),
    ),
  ) as CatalogSample[];
}

const aromaOfWord = new Map<string, string>();
for (const group of vocabulary.groups) {
  if (group.domain !== "descriptor") continue;
  for (const word of [group.key, ...group.source_keys]) {
    aromaOfWord.set(word, group.key);
  }
}

/** A sampled catalog product as the bottle being recorded, its aromas under their current names. */
export function sampleProduct(
  sample: CatalogSample,
  aromas: readonly string[] = sample.aromas,
): SensoryProduct {
  const descriptors: SensoryProductDescriptor[] = [];
  for (const raw of aromas) {
    const key = aromaOfWord.get(raw);
    if (!key || descriptors.some((d) => d.key === key)) continue;
    descriptors.push({
      key,
      label: key,
      section: "aroma",
      family: "test",
      traits: [],
      description: null,
      evidenceRefs: ["test"],
    });
  }
  return {
    name: sample.name,
    category: sample.category as SensoryProduct["category"],
    styleKey: sample.style_key,
    region: null,
    abv: sample.abv,
    ingredients: [...sample.ingredients],
    processes: [...sample.processes],
    grapeVarietyKeys: [],
    levels: sample.levels,
    levelSources: sample.level_sources ?? {},
    levelRefs: {},
    descriptors,
  };
}
