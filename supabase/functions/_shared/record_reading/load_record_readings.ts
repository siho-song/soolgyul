/**
 * The account's records as they were answered, for the parts that count
 * across records (the taste letters, the fit).
 *
 * They are read from the answers and from the catalog as it is now, never
 * from what a card stored. A card is the text of its day: it may be reshaped
 * or rewritten without reaching the letters or the fit, and a change to how
 * answers are read reaches every record at once.
 */
import { readAllPages } from "../supabase.ts";
import { readRecord, type RecordReading } from "./read_record.ts";
import { SENSORY_QUESTIONNAIRE_VERSION } from "./record/questionnaire.ts";
import { buildSensoryRecord, catalogProduct } from "./record/record_builder.ts";
import type { QuestionnaireAnswerInput } from "./record/questionnaire.ts";

/** The columns of an item and of its tasting profile that describe a bottle to the engine. */
export const CATALOG_ITEM_COLUMNS =
  "id,name_ko,name_en,abv_percent,region_key,style_key," +
  "ingredient_keys,production_process_keys,grape_variety_keys," +
  "vintage_year,age_statement_years," +
  "category:alcohol_categories(category_key)," +
  "producer:producers(name_ko,name_en)";
export const TASTING_PROFILE_COLUMNS =
  "alcohol_item_id,aroma_tags,palate_tags,finish_tags," +
  "sweetness,acidity,bitterness,astringency,body," +
  "carbonation,aroma_intensity,finish_length,finish_character," +
  "level_sources";

export type LoadedRecord = {
  record_id: string;
  /** ISO timestamp of the record. */
  recorded_at: string;
  /**
   * What the record was read to: its answers and its bottle. Null when the
   * record cannot be read: it was answered under a questionnaire that is no
   * longer read, or its bottle is not published.
   */
  reading: RecordReading | null;
};

type Rest = <T>(path: string) => Promise<T>;
type Row = Record<string, unknown>;

/** How many ids one `in.(…)` filter carries, so the address stays short. */
const IDS_PER_QUERY = 100;

/** Every record of the account that has a card, oldest first. */
export async function loadRecordReadings(
  rest: Rest,
  userId: string,
): Promise<LoadedRecord[]> {
  const rows = await readAllPages((page) =>
    rest<Row[]>(
      `drink_records?user_id=eq.${encodeURIComponent(userId)}` +
        "&select=id,created_at,questionnaire_version,alcohol_item_id," +
        "answers:drink_record_answers(question_key,selected_option_keys)," +
        "taste_cards!inner(lifecycle)" +
        "&taste_cards.lifecycle=eq.final" +
        "&order=created_at.asc,id.asc" + page,
    )
  );
  const products = await loadProducts(
    rest,
    rows.flatMap((row) =>
      row.questionnaire_version === SENSORY_QUESTIONNAIRE_VERSION &&
        typeof row.alcohol_item_id === "string"
        ? [row.alcohol_item_id]
        : []
    ),
  );
  const records: LoadedRecord[] = [];
  for (const row of rows) {
    if (typeof row.id !== "string" || typeof row.created_at !== "string") {
      continue;
    }
    const product = products.get(row.alcohol_item_id as string);
    const reading = product
      ? readRecord(buildSensoryRecord(row.id, answersOf(row), product))
      : null;
    records.push({
      record_id: row.id,
      recorded_at: row.created_at,
      reading,
    });
  }
  return records;
}

function answersOf(row: Row): QuestionnaireAnswerInput[] {
  const answers = Array.isArray(row.answers) ? row.answers as Row[] : [];
  return answers.flatMap((answer) =>
    typeof answer.question_key === "string"
      ? [{
        question_key: answer.question_key,
        selected_option_keys: Array.isArray(answer.selected_option_keys)
          ? answer.selected_option_keys.filter((key): key is string =>
            typeof key === "string"
          )
          : [],
        free_text: null,
      }]
      : []
  );
}

/** The published bottles of these ids as the engine reads them, by id. */
async function loadProducts(rest: Rest, itemIds: readonly string[]) {
  const ids = [...new Set(itemIds)];
  const products = new Map<string, ReturnType<typeof catalogProduct>>();
  for (let from = 0; from < ids.length; from += IDS_PER_QUERY) {
    const list = `in.(${
      ids.slice(from, from + IDS_PER_QUERY).map(encodeURIComponent).join(",")
    })`;
    const [items, profiles] = await Promise.all([
      rest<Row[]>(
        `alcohol_items?id=${list}&publish_status=eq.published` +
          `&select=${CATALOG_ITEM_COLUMNS}`,
      ),
      rest<Row[]>(
        `alcohol_tasting_profiles?alcohol_item_id=${list}` +
          `&select=${TASTING_PROFILE_COLUMNS}`,
      ),
    ]);
    for (const item of items) {
      if (typeof item.id !== "string") continue;
      const profile = profiles.find((row) => row.alcohol_item_id === item.id);
      products.set(
        item.id,
        catalogProduct(item, profile ?? null),
      );
    }
  }
  return products;
}
