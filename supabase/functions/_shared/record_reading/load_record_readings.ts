/**
 * The account's records as they were answered, for the parts that count
 * across records (the taste letters, the fit).
 *
 * They are read from the answers and from the catalog as it is now, never
 * from what a card stored. A card is the text of its day: it may be reshaped
 * or rewritten without reaching the letters or the fit, and a change to how
 * answers are read reaches every record at once.
 */
import { readPublishedBottles } from "../database/bottles.ts";
import type { ServiceRest } from "../database/service_rest.ts";
import { stringsOf } from "../json.ts";
import { readAllPages } from "../supabase.ts";
import { readRecord, type RecordReading } from "./read_record.ts";
import { SENSORY_QUESTIONNAIRE_VERSION } from "./record/questionnaire.ts";
import { buildSensoryRecord, catalogProduct } from "./record/record_builder.ts";
import type { QuestionnaireAnswerInput } from "./record/questionnaire.ts";

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

type Row = Record<string, unknown>;

/** A record's answers, embedded in its `drink_records` row. */
export const RECORD_ANSWERS_COLUMN =
  "answers:drink_record_answers(question_key,selected_option_keys)";

/** Every record of the account that has a card, oldest first. */
export async function loadRecordReadings(
  rest: ServiceRest,
  userId: string,
): Promise<LoadedRecord[]> {
  const rows = await readAllPages((page) =>
    rest<Row[]>(
      `drink_records?user_id=eq.${encodeURIComponent(userId)}` +
        "&select=id,created_at,questionnaire_version,alcohol_item_id," +
        `${RECORD_ANSWERS_COLUMN},taste_cards!inner(lifecycle)` +
        "&taste_cards.lifecycle=eq.final" +
        "&order=created_at.asc,id.asc" + page,
    )
  );
  const bottles = await readPublishedBottles(
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
    const bottle = bottles.get(row.alcohol_item_id as string);
    const reading = bottle
      ? readRecord(
        buildSensoryRecord(
          row.id,
          answersOfRecordRow(row),
          catalogProduct(bottle.item, bottle.profile),
        ),
      )
      : null;
    records.push({
      record_id: row.id,
      recorded_at: row.created_at,
      reading,
    });
  }
  return records;
}

/** The answers of a `drink_records` row read with RECORD_ANSWERS_COLUMN, as the engine takes them. */
export function answersOfRecordRow(row: Row): QuestionnaireAnswerInput[] {
  const answers = Array.isArray(row.answers) ? row.answers as Row[] : [];
  return answers.flatMap((answer) =>
    typeof answer.question_key === "string"
      ? [{
        question_key: answer.question_key,
        selected_option_keys: stringsOf(answer.selected_option_keys),
        free_text: null,
      }]
      : []
  );
}
