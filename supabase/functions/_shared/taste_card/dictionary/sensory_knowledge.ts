import { termKnowledge } from "./dictionary.ts";
type SensoryKnowledge = {
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
