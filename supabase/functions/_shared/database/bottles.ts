/**
 * The catalog's rows of a published bottle: its item and its tasting profile.
 * The card, the records read for 취향 조각 and 나에게 맞는 술 찾기, and the
 * bottles 맞는 술 찾기 is asked about all read a bottle here, so they read the
 * same columns of the same rows.
 */
import type { ServiceRest } from "./service_rest.ts";

/** The nine 1–5 level columns of a tasting profile. */
export const TASTING_LEVEL_COLUMNS = [
  "sweetness",
  "acidity",
  "bitterness",
  "astringency",
  "body",
  "carbonation",
  "aroma_intensity",
  "finish_length",
  "finish_character",
] as const;

const ITEM_COLUMNS = "id,name_ko,name_en,abv_percent,region_key,style_key," +
  "ingredient_keys,production_process_keys,grape_variety_keys," +
  "vintage_year,age_statement_years," +
  "category:alcohol_categories(category_key)," +
  "producer:producers(producer_key,name_ko,name_en)";
const PROFILE_COLUMNS = "alcohol_item_id,aroma_tags,palate_tags,finish_tags," +
  TASTING_LEVEL_COLUMNS.join(",") + ",level_sources";

type Row = Record<string, unknown>;

export type BottleRows = {
  /** The `alcohol_items` row with its category and producer. */
  item: Row;
  /** The `alcohol_tasting_profiles` row, or null for a bottle nobody profiled. */
  profile: Row | null;
};

/** How many ids one `in.(…)` filter carries, so the address stays short. */
const IDS_PER_QUERY = 100;

/** The published bottles among these ids, by id. An unpublished or unknown id is left out. */
export async function readPublishedBottles(
  rest: ServiceRest,
  itemIds: readonly string[],
): Promise<Map<string, BottleRows>> {
  const ids = [...new Set(itemIds)];
  const bottles = new Map<string, BottleRows>();
  for (let from = 0; from < ids.length; from += IDS_PER_QUERY) {
    const list = `in.(${
      ids.slice(from, from + IDS_PER_QUERY).map(encodeURIComponent).join(",")
    })`;
    const [items, profiles] = await Promise.all([
      rest<Row[]>(
        `alcohol_items?id=${list}&publish_status=eq.published` +
          `&select=${ITEM_COLUMNS}`,
      ),
      rest<Row[]>(
        `alcohol_tasting_profiles?alcohol_item_id=${list}` +
          `&select=${PROFILE_COLUMNS}`,
      ),
    ]);
    const profileOf = new Map<unknown, Row>();
    for (const row of profiles) {
      if (!profileOf.has(row.alcohol_item_id)) {
        profileOf.set(row.alcohol_item_id, row);
      }
    }
    for (const item of items) {
      if (typeof item.id !== "string") continue;
      bottles.set(item.id, { item, profile: profileOf.get(item.id) ?? null });
    }
  }
  return bottles;
}
