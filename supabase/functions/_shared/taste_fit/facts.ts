/**
 * The bottle's own facts for the detail screen: who makes it, the grape, where
 * it is from, how it is made. Each carries the dictionary's short explanation
 * when the dictionary has one, so a term the reader does not know can be
 * opened.
 */
import {
  caskOrMethodByKey,
  grapeByKey,
  producerByKey,
  regionByKey,
  regionPath,
  type Term,
} from "../record_reading/dictionary/dictionary.ts";
import { termHelp } from "../record_reading/dictionary/term_help.ts";
import type { TasteFitProductRow } from "./repository.ts";

export type TasteFitFact = {
  kind: "producer" | "grape" | "region" | "process";
  label: string;
  /** The dictionary's summary, or null when the term has no explanation. */
  description: string | null;
  /** The dictionary term the reader can save from the explanation, if any. */
  key: string | null;
};

/** A term of the dictionary as a fact of the bottle. */
function factOf(kind: TasteFitFact["kind"], term: Term): TasteFitFact {
  const help = termHelp(term);
  return {
    kind,
    label: term.names.ko,
    description: help?.description ?? null,
    key: help?.key ?? null,
  };
}

export function productFacts(row: TasteFitProductRow): TasteFitFact[] {
  const facts: TasteFitFact[] = [];
  if (row.producer) {
    const term = producerByKey(row.producer.key);
    const label = term?.names.ko ?? row.producer.name_ko ??
      row.producer.name_en;
    if (label) {
      facts.push(
        term
          ? factOf("producer", term)
          : { kind: "producer", label, description: null, key: null },
      );
    }
  }
  for (const key of row.grape_variety_keys) {
    const term = grapeByKey(key);
    if (term) facts.push(factOf("grape", term));
  }
  const region = regionByKey(row.region_key);
  if (region) {
    const fact = factOf("region", region);
    // A place the dictionary does not explain is told by where it is.
    facts.push({
      ...fact,
      description: fact.description ?? regionPath(row.region_key),
    });
  }
  for (const key of row.production_process_keys) {
    const term = caskOrMethodByKey(key);
    if (term) facts.push(factOf("process", term));
  }
  return facts;
}
