import { readAccount } from "../database/accounts.ts";
import {
  readPublishedBottles,
  TASTING_LEVEL_COLUMNS,
} from "../database/bottles.ts";
import {
  type ServiceRest,
  serviceRest,
  stringsOf,
} from "../database/service_rest.ts";
import { boundedFetch } from "../supabase.ts";
import { loadRecordReadings } from "../record_reading/load_record_readings.ts";
import type { RecordForFit } from "./preferences_from_records.ts";

/**
 * Reads for the fit check, with the service role: the reader's records as
 * they were answered (never what a card stored) and the candidates' tasting
 * profiles.
 */
export type TasteFitProductRow = {
  id: string;
  abv_percent: number | null;
  style_key: string | null;
  category_key: string | null;
  levels: Record<string, number>;
  aroma_tags: string[];
  palate_tags: string[];
  finish_tags: string[];
  producer: {
    key: string | null;
    name_ko: string | null;
    name_en: string | null;
  } | null;
  grape_variety_keys: string[];
  production_process_keys: string[];
  region_key: string | null;
};

/** Whether the reader's account is active, and their display name (null before the profile is complete). */
export type TasteFitReader = { active: boolean; display_name: string | null };

export interface TasteFitRepository {
  loadReader(userId: string): Promise<TasteFitReader>;
  /** The reader's records as answered, read from the answers and today's catalog. */
  loadRecords(userId: string): Promise<RecordForFit[]>;
  loadProducts(productIds: readonly string[]): Promise<TasteFitProductRow[]>;
}

export class SupabaseTasteFitRepository implements TasteFitRepository {
  private readonly rest: ServiceRest;

  constructor(
    supabaseUrl: string,
    serviceRoleKey: string,
    fetchImpl: typeof fetch = boundedFetch,
  ) {
    this.rest = serviceRest(supabaseUrl, serviceRoleKey, fetchImpl);
  }

  loadReader(userId: string): Promise<TasteFitReader> {
    return readAccount(this.rest, userId);
  }

  async loadRecords(userId: string): Promise<RecordForFit[]> {
    const records = await loadRecordReadings(this.rest, userId);
    // A record that cannot be read says nothing.
    return records.flatMap(({ reading }) => reading ? [reading] : []);
  }

  async loadProducts(
    productIds: readonly string[],
  ): Promise<TasteFitProductRow[]> {
    const bottles = await readPublishedBottles(this.rest, productIds);
    return [...bottles.values()].map(({ item, profile }) => {
      const levels: Record<string, number> = {};
      for (const column of TASTING_LEVEL_COLUMNS) {
        const value = profile?.[column];
        if (typeof value === "number") levels[column] = value;
      }
      const category = item.category as Record<string, unknown> | null;
      return {
        id: String(item.id),
        abv_percent: typeof item.abv_percent === "number"
          ? item.abv_percent
          : typeof item.abv_percent === "string"
          ? Number(item.abv_percent)
          : null,
        style_key: typeof item.style_key === "string" ? item.style_key : null,
        category_key: typeof category?.category_key === "string"
          ? category.category_key
          : null,
        levels,
        aroma_tags: stringsOf(profile?.aroma_tags),
        palate_tags: stringsOf(profile?.palate_tags),
        finish_tags: stringsOf(profile?.finish_tags),
        producer: producerOf(item.producer),
        grape_variety_keys: stringsOf(item.grape_variety_keys),
        production_process_keys: stringsOf(item.production_process_keys),
        region_key: typeof item.region_key === "string"
          ? item.region_key
          : null,
      };
    });
  }
}

function producerOf(value: unknown): TasteFitProductRow["producer"] {
  if (!value || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  const text = (v: unknown) => typeof v === "string" ? v : null;
  return {
    key: text(row.producer_key),
    name_ko: text(row.name_ko),
    name_en: text(row.name_en),
  };
}
