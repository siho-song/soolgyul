/**
 * The bottle's own facts for the detail screen: who makes it, the grape, where
 * it is from, how it is made. Each carries the dictionary's short explanation
 * when the dictionary has one, so a term the reader does not know can be
 * opened.
 */
import { regionPath, terms } from "../taste_card/dictionary/dictionary.ts";
import type { TasteFitProductRow } from "./repository.ts";

export type TasteFitFact = {
  kind: "producer" | "grape" | "region" | "process";
  label: string;
  /** The dictionary's summary, or null when the term has no explanation. */
  description: string | null;
};

const byKey = (...types: string[]) =>
  new Map(terms(...types).map((t) => [t.key, t]));
const PRODUCERS = byKey("producer");
const GRAPES = byKey("grape");
const PROCESSES = byKey("process", "maturation");
const REGIONS = byKey("region");

function summary(term: { summary?: string } | undefined): string | null {
  return term?.summary?.trim() ? term.summary.trim() : null;
}

export function productFacts(row: TasteFitProductRow): TasteFitFact[] {
  const facts: TasteFitFact[] = [];
  if (row.producer) {
    const term = row.producer.key ? PRODUCERS.get(row.producer.key) : undefined;
    const label = term?.names.ko ?? row.producer.name_ko ??
      row.producer.name_en;
    if (label) {
      facts.push({ kind: "producer", label, description: summary(term) });
    }
  }
  for (const key of row.grape_variety_keys) {
    const term = GRAPES.get(key);
    if (term) {
      facts.push({
        kind: "grape",
        label: term.names.ko,
        description: summary(term),
      });
    }
  }
  if (row.region_key) {
    const term = REGIONS.get(row.region_key);
    const path = regionPath(row.region_key);
    if (term) {
      facts.push({
        kind: "region",
        label: term.names.ko,
        description: summary(term) ?? path,
      });
    }
  }
  for (const key of row.production_process_keys) {
    const term = PROCESSES.get(key);
    if (term) {
      facts.push({
        kind: "process",
        label: term.names.ko,
        description: summary(term),
      });
    }
  }
  return facts;
}
