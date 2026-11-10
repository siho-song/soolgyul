import { serviceRoleHeaders } from "../supabase.ts";

/**
 * Reads for the fit check, with the service role: the reader's saved cards
 * (their private facts never reach the client) and the candidates' tasting
 * profiles.
 */
export type TasteFitProductRow = {
  id: string;
  abv_percent: number | null;
  style_key: string | null;
  category_key: string | null;
  levels: Record<string, number>;
  aroma_tags: string[];
  producer: {
    key: string | null;
    name_ko: string | null;
    name_en: string | null;
  } | null;
  grape_variety_keys: string[];
  production_process_keys: string[];
  region_key: string | null;
};

export interface TasteFitRepository {
  /** The reader's display name, null before the profile is complete. */
  loadDisplayName(userId: string): Promise<string | null>;
  /** The `facts` of every final card on the reader's live records, as stored. */
  loadUserCardFacts(userId: string): Promise<unknown[]>;
  loadProducts(productIds: readonly string[]): Promise<TasteFitProductRow[]>;
}

class TasteFitRepositoryError extends Error {
  constructor(public readonly code: string, message = code) {
    super(message);
    this.name = "TasteFitRepositoryError";
  }
}

const LEVEL_COLUMNS = [
  "sweetness",
  "acidity",
  "astringency",
  "body",
  "carbonation",
  "finish_length",
  "finish_cleanliness",
  "aroma_intensity",
] as const;

export class SupabaseTasteFitRepository implements TasteFitRepository {
  constructor(
    private readonly supabase_url: string,
    private readonly service_role_key: string,
    private readonly fetch_impl: typeof fetch = fetch,
  ) {
    if (!supabase_url || !service_role_key) {
      throw new Error("supabase_service_configuration_required");
    }
  }

  async loadDisplayName(userId: string): Promise<string | null> {
    const rows = await this.rest<Record<string, unknown>[]>(
      `users?id=eq.${encodeURIComponent(userId)}&select=display_name&limit=1`,
    );
    const name = rows[0]?.display_name;
    return typeof name === "string" && name.trim() ? name.trim() : null;
  }

  async loadUserCardFacts(userId: string): Promise<unknown[]> {
    const rows = await this.rest<Record<string, unknown>[]>(
      `drink_records?user_id=eq.${encodeURIComponent(userId)}` +
        "&deleted_at=is.null&select=id,taste_cards(semantic_snapshot)",
    );
    const facts: unknown[] = [];
    for (const row of rows) {
      const cards = row.taste_cards;
      for (const card of Array.isArray(cards) ? cards : cards ? [cards] : []) {
        const snapshot = (card as Record<string, unknown>).semantic_snapshot;
        const value = snapshot && typeof snapshot === "object"
          ? (snapshot as Record<string, unknown>).facts
          : undefined;
        if (value !== undefined) facts.push(value);
      }
    }
    return facts;
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
          `&select=alcohol_item_id,aroma_tags,${LEVEL_COLUMNS.join(",")}`,
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
    const response = await this.fetch_impl(
      `${this.supabase_url}/rest/v1/${path}`,
      { headers: serviceRoleHeaders(this.service_role_key) },
    );
    const text = await response.text();
    const body = text ? JSON.parse(text) : null;
    if (!response.ok) {
      const code =
        body && typeof body === "object" && typeof body.code === "string"
          ? body.code
          : `http_${response.status}`;
      throw new TasteFitRepositoryError(code, "repository_request_failed");
    }
    return body as T;
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
