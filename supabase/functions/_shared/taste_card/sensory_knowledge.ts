import {
  serviceVocabulary as vocabulary,
  termKnowledge,
} from "./dictionary.ts";

/** Card copy only; questionnaire labels and interpretation keys are unchanged. */
export function sensoryCardLabel(
  key: string,
  knowledge: SensoryKnowledgeRegistry = {},
): string | null {
  return sensoryKnowledgeFor(key, knowledge)?.card_label_ko ?? null;
}

export type SensoryKnowledge = {
  card_label_ko: string | null;
  sensory_description: string;
  sensory_trait_keys: readonly string[];
};

export type SensoryKnowledgeRegistry = Readonly<
  Record<string, SensoryKnowledge>
>;

/**
 * Every sensory definition the card may cite, read once from the bundled
 * dictionary (catalog/dictionary/terms.json). The bundle is the only source
 * of this prose; the database carries keys, not descriptions.
 */
export const bundledSensoryKnowledge: SensoryKnowledgeRegistry =
  buildBundledSensoryKnowledge();

function buildBundledSensoryKnowledge(): SensoryKnowledgeRegistry {
  const result: Record<string, SensoryKnowledge> = {};
  for (const [key, entry] of Object.entries(termKnowledge.terms)) {
    result[`sensory_descriptor:${key}`] = {
      card_label_ko: null,
      sensory_description: entry.sensory_description,
      sensory_trait_keys: [...entry.sensory_trait_keys],
    };
  }
  for (const [key, entry] of Object.entries(termKnowledge.dimensions)) {
    result[`sensory_dimension:${key}`] = {
      card_label_ko: null,
      sensory_description: entry.sensory_description,
      sensory_trait_keys: [...entry.sensory_trait_keys],
    };
  }
  return result;
}

/** Keep only referenced definitions in each saved card, not the entire dictionary. */
export function selectSensoryKnowledge(
  knowledge: SensoryKnowledgeRegistry,
  references: readonly { semantic_key: string; value: unknown }[],
): SensoryKnowledgeRegistry {
  const selected: Record<string, SensoryKnowledge> = {};
  const text = references.map((item) => JSON.stringify(item)).join(" ");
  for (const [identity, definition] of Object.entries(knowledge)) {
    const key = identity.split(":")[1];
    const group = vocabulary.groups.find((item) => item.key === key);
    const aliases = [
      key,
      ...(group?.source_keys ?? []),
      ...(group?.user_source_labels ?? []),
    ];
    if (
      references.some((item) =>
        sensoryKnowledgeFor(item.semantic_key, knowledge) === definition
      ) ||
      aliases.some((alias) => text.includes(alias))
    ) {
      selected[identity] = definition;
    }
  }
  return selected;
}

/** Describes a sensation, not a product measurement or a user's preference. */
export function sensoryKnowledgeFor(
  key: string,
  knowledge: SensoryKnowledgeRegistry = {},
): SensoryKnowledge | null {
  const type = key.endsWith(".level")
    ? "sensory_dimension"
    : "sensory_descriptor";
  const parts = key.split(".");
  key = key.endsWith(".level")
    ? (dimensionKeys[key] ?? parts.at(-2)!)
    : parts.at(-1)!;
  return knowledge[`${type}:${key}`] ?? null;
}

const dimensionKeys: Record<string, string> = {
  "catalog.alcohol.presence.level": "alcohol_presence",
  "catalog.aroma.intensity.level": "aroma_intensity",
  "catalog.flavour.clarity.level": "flavour_clarity",
  "catalog.finish.length.level": "finish_length",
  "catalog.finish.cleanliness.level": "finish_cleanliness",
};
