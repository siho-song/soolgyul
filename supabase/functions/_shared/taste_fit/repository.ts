import {
  boundedFetch,
  postgrestJson,
  serviceRoleHeaders,
} from "../supabase.ts";
import { loadAnsweredRecords } from "../taste_card/service/answered_records.ts";
import type { LedgerCard } from "./ledger.ts";

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
  loadAnsweredCards(userId: string): Promise<LedgerCard[]>;
  loadProducts(productIds: readonly string[]): Promise<TasteFitProductRow[]>;
}

class TasteFitRepositoryError extends Error {
  constructor(
    public readonly code: string,
    message = code,
    public readonly transient = false,
  ) {
    super(message);
    this.name = "TasteFitRepositoryError";
  }
}

const LEVEL_COLUMNS = [
  "sweetness",
  "acidity",
  "bitterness",
  "astringency",
  "body",
  "carbonation",
  "finish_length",
  "finish_character",
  "aroma_intensity",
] as const;

export class SupabaseTasteFitRepository implements TasteFitRepository {
  constructor(
    private readonly supabase_url: string,
    private readonly service_role_key: string,
    private readonly fetch_impl: typeof fetch = boundedFetch,
  ) {
    if (!supabase_url || !service_role_key) {
      throw new Error("supabase_service_configuration_required");
    }
  }

  async loadReader(userId: string): Promise<TasteFitReader> {
    const rows = await this.rest<Record<string, unknown>[]>(
      `users?id=eq.${encodeURIComponent(userId)}` +
        "&select=display_name,account_status&limit=1",
    );
    const name = rows[0]?.display_name;
    return {
      active: rows[0]?.account_status === "active",
      display_name: typeof name === "string" && name.trim()
        ? name.trim()
        : null,
    };
  }

  async loadAnsweredCards(userId: string): Promise<LedgerCard[]> {
    const records = await loadAnsweredRecords(
      (path) => this.rest(path),
      userId,
    );
    // A record that cannot be read says nothing.
    return records.flatMap((record) => record.card ? [record.card] : []);
  }

  async loadProducts(
    productIds: readonly string[],
  ): Promise<TasteFitProductRow[]> {
    if (productIds.length === 0) return [];
    const list = `in.(${productIds.map(encodeURIComponent).join(",")})`;
    const [items, profiles] = await Promise.all([
      this.rest<Record<string, unknown>[]>(
        `alcohol_items?id=${list}&publish_status=eq.published` +
          "&select=id,abv_percent,style_key,region_key,grape_variety_keys," +
          "production_process_keys,category:alcohol_categories(category_key)," +
          "producer:producers(producer_key,name_ko,name_en)",
      ),
      this.rest<Record<string, unknown>[]>(
        `alcohol_tasting_profiles?alcohol_item_id=${list}` +
          "&select=alcohol_item_id,aroma_tags,palate_tags,finish_tags," +
          LEVEL_COLUMNS.join(","),
      ),
    ]);
    const profileById = new Map(
      profiles.map((row) => [String(row.alcohol_item_id), row]),
    );
    return items.map((item) => {
      const profile = profileById.get(String(item.id)) ?? {};
      const levels: Record<string, number> = {};
      for (const column of LEVEL_COLUMNS) {
        const value = profile[column];
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
        aroma_tags: strings(profile.aroma_tags),
        palate_tags: strings(profile.palate_tags),
        finish_tags: strings(profile.finish_tags),
        producer: producerOf(item.producer),
        grape_variety_keys: strings(item.grape_variety_keys),
        production_process_keys: strings(item.production_process_keys),
        region_key: typeof item.region_key === "string"
          ? item.region_key
          : null,
      };
    });
  }

  private async rest<T>(path: string): Promise<T> {
    return await postgrestJson<T>(
      this.fetch_impl,
      `${this.supabase_url}/rest/v1/${path}`,
      { headers: serviceRoleHeaders(this.service_role_key) },
      (code, message, transient) =>
        new TasteFitRepositoryError(code, message, transient),
    );
  }
}

function strings(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((v): v is string => typeof v === "string")
    : [];
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
