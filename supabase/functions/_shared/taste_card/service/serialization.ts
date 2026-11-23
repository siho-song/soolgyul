import {
  type AlcoholCategory,
  isAlcoholCategory,
  UUID_PATTERN,
  UUID_V4_PATTERN,
} from "../../contract.ts";
import { isJsonObject } from "../../json.ts";
import {
  type AlcoholIdentificationView,
  type AnonymousTasteCardConversionRequest,
  type CreateTasteCardResultRequest,
  type QuestionnaireAnswerInput,
  TASTE_CARD_WIRE_SCHEMA_VERSION,
  type TasteCardGuide,
  type TasteCardGuideDirection,
  type TasteCardNext,
  type TasteCardNote,
  type TasteCardNoteFelt,
  type TasteCardNoteGauge,
  type TasteCardNoteGroup,
  type TasteCardNoteMark,
  type TasteCardNoteOption,
  type TasteCardNoteWords,
  type TasteCardParagraph,
  type TasteCardResultEnvelope,
  type TasteCardTag,
  type TasteCardTagKind,
  type TasteCardTerm,
  type TasteCardView,
} from "./types.ts";
import { TasteCardContractError } from "./errors.ts";

/** A section never holds more paragraphs than the writer can produce. */
const maxParagraphs = 12;

export function parseCreateTasteCardResultRequest(
  value: unknown,
): CreateTasteCardResultRequest {
  const object = record(value, "$request");
  exactKeys(object, [
    "idempotency_key",
    "anonymous_session_id",
    "questionnaire_version",
    "alcohol_identification",
    "answers",
    "q7_free_text",
    "photo_asset_id",
  ], "$request");
  const answers = array(object.answers, "$request.answers");
  if (answers.length === 0 || answers.length > 64) {
    fail("answer_count_invalid", "$request.answers");
  }
  const q7FreeText = nullableString(
    object.q7_free_text,
    "$request.q7_free_text",
  );
  if (q7FreeText !== null && q7FreeText.length > maximumNoteLength) {
    fail("free_text_too_long", "$request.q7_free_text");
  }
  const anonymousSessionId = nullableString(
    object.anonymous_session_id,
    "$request.anonymous_session_id",
  );
  if (anonymousSessionId !== null && anonymousSessionId.length > 512) {
    fail("anonymous_session_too_long", "$request.anonymous_session_id");
  }
  const alcoholIdentification = parseAlcoholIdentification(
    object.alcohol_identification,
    "$request.alcohol_identification",
  ) as CreateTasteCardResultRequest["alcohol_identification"];
  if (alcoholIdentification.mode === "catalog_match") {
    // The id is interpolated into catalog lookups; reject non-UUIDs before any
    // attempt row exists.
    uuid(
      alcoholIdentification.alcohol_item_id,
      "$request.alcohol_identification.alcohol_item_id",
    );
  }
  return {
    idempotency_key: uuidV4(object.idempotency_key, "$request.idempotency_key"),
    anonymous_session_id: anonymousSessionId,
    questionnaire_version: questionnaireVersion(object.questionnaire_version),
    alcohol_identification: alcoholIdentification,
    answers: answers.map((answer, index) =>
      parseQuestionnaireAnswer(answer, `$request.answers[${index}]`)
    ),
    q7_free_text: q7FreeText,
    photo_asset_id: nullableUuid(
      object.photo_asset_id,
      "$request.photo_asset_id",
    ),
  };
}

/** The questions a member answered anew on a saved record. */
export function parseReviseTasteCardRequest(
  value: unknown,
): QuestionnaireAnswerInput[] {
  const object = record(value, "$request");
  exactKeys(object, ["answers"], "$request");
  const answers = array(object.answers, "$request.answers");
  if (answers.length === 0 || answers.length > 16) {
    fail("answer_count_invalid", "$request.answers");
  }
  return answers.map((answer, index) =>
    parseQuestionnaireAnswer(answer, `$request.answers[${index}]`)
  );
}

export function parseAnonymousTasteCardConversionRequest(
  value: unknown,
): AnonymousTasteCardConversionRequest {
  const object = record(value, "$request");
  exactKeys(object, [
    "anonymous_session_id",
    "result_id",
    "conversion_token",
    "idempotency_key",
  ], "$request");
  return {
    anonymous_session_id: nonEmpty(
      object.anonymous_session_id,
      "$request.anonymous_session_id",
    ),
    result_id: uuid(object.result_id, "$request.result_id"),
    conversion_token: nonEmpty(
      object.conversion_token,
      "$request.conversion_token",
    ),
    idempotency_key: uuidV4(object.idempotency_key, "$request.idempotency_key"),
  };
}

/** The public envelope, exactly as the app parses it: unknown keys fail. */
export function parseTasteCardResultEnvelope(
  value: unknown,
): TasteCardResultEnvelope {
  const object = record(value, "$result");
  exactKeys(
    object,
    [
      "wire_schema_version",
      "result_id",
      "record_id",
      "snapshot_ref",
      "ownership_state",
      "alcohol_identification",
      "view",
      "conversion",
      "created_at",
    ],
    "$result",
  );
  if (object.wire_schema_version !== TASTE_CARD_WIRE_SCHEMA_VERSION) {
    fail("unknown_wire_schema_version", "$result.wire_schema_version");
  }
  const ownershipState = string(
    object.ownership_state,
    "$result.ownership_state",
  );
  if (ownershipState !== "anonymous" && ownershipState !== "saved") {
    fail("unknown_ownership_state", "$result.ownership_state");
  }
  const conversion = object.conversion === null
    ? null
    : parseConversion(object.conversion, "$result.conversion");
  if ((ownershipState === "anonymous") !== (conversion !== null)) {
    fail("conversion_ownership_mismatch", "$result.conversion");
  }
  const result: TasteCardResultEnvelope = {
    wire_schema_version: TASTE_CARD_WIRE_SCHEMA_VERSION,
    result_id: nonEmpty(object.result_id, "$result.result_id"),
    record_id: nullableString(object.record_id, "$result.record_id"),
    snapshot_ref: nonEmpty(object.snapshot_ref, "$result.snapshot_ref"),
    ownership_state: ownershipState,
    alcohol_identification: parseAlcoholIdentification(
      object.alcohol_identification,
      "$result.alcohol_identification",
    ),
    view: parseView(object.view, "$result.view"),
    conversion,
    created_at: timestamp(object.created_at, "$result.created_at"),
  };
  if (result.snapshot_ref !== result.view.metadata.snapshot_ref) {
    fail("snapshot_ref_mismatch", "$result.view.metadata.snapshot_ref");
  }
  return result;
}

function parseView(value: unknown, path: string): TasteCardView {
  const object = record(value, path);
  // Cards made before the 테이스팅 노트 have no such key.
  exactKeys(
    object,
    [
      "product",
      "bite",
      "positive",
      "burden",
      "balanced",
      ...("note" in object ? ["note"] : []),
      "metadata",
    ],
    path,
  );
  const product = record(object.product, `${path}.product`);
  // Cards made before the style and ABV were kept have no such keys.
  const hasFacts = "style_label" in product;
  exactKeys(
    product,
    [
      "drink_name_snapshot",
      "user_name",
      "image_reference",
      "category_label",
      ...(hasFacts ? ["style_label", "abv_percent"] : []),
    ],
    `${path}.product`,
  );
  const bite = record(object.bite, `${path}.bite`);
  // Cards made before the brief was written have no such key.
  exactKeys(
    bite,
    [
      "nickname",
      "tags",
      "summary",
      ...("brief" in bite ? ["brief"] : []),
      "guide",
      ...("next" in bite ? ["next"] : []),
    ],
    `${path}.bite`,
  );
  const metadata = record(object.metadata, `${path}.metadata`);
  exactKeys(
    metadata,
    [
      "snapshot_ref",
      "schema_version",
      "engine_version",
      "generated_at",
      "generated_from_record_ref",
    ],
    `${path}.metadata`,
  );
  if (metadata.schema_version !== 3) {
    fail("schema_version_required", `${path}.metadata.schema_version`);
  }
  return {
    product: {
      drink_name_snapshot: nonEmpty(
        product.drink_name_snapshot,
        `${path}.product.drink_name_snapshot`,
      ),
      user_name: nullableString(
        product.user_name,
        `${path}.product.user_name`,
      ),
      image_reference: product.image_reference === null
        ? null
        : parseImageReference(
          product.image_reference,
          `${path}.product.image_reference`,
        ),
      category_label: nullableString(
        product.category_label,
        `${path}.product.category_label`,
      ),
      ...(hasFacts
        ? {
          style_label: nullableString(
            product.style_label,
            `${path}.product.style_label`,
          ),
          abv_percent: nullableAbv(
            product.abv_percent,
            `${path}.product.abv_percent`,
          ),
        }
        : {}),
    },
    bite: {
      nickname: nonEmpty(bite.nickname, `${path}.bite.nickname`),
      tags: parseTags(bite.tags, `${path}.bite.tags`),
      summary: nonEmpty(bite.summary, `${path}.bite.summary`),
      brief: bite.brief == null
        ? null
        : nonEmpty(bite.brief, `${path}.bite.brief`),
      guide: parseGuide(bite.guide, `${path}.bite.guide`),
      ...("next" in bite
        ? { next: parseNext(bite.next, `${path}.bite.next`) }
        : {}),
    },
    positive: parseParagraphs(object.positive, `${path}.positive`),
    burden: parseParagraphs(object.burden, `${path}.burden`),
    balanced: parseParagraphs(object.balanced, `${path}.balanced`),
    ...("note" in object
      ? { note: parseNote(object.note, `${path}.note`) }
      : {}),
    metadata: {
      snapshot_ref: nonEmpty(
        metadata.snapshot_ref,
        `${path}.metadata.snapshot_ref`,
      ),
      schema_version: 3,
      engine_version: nonEmpty(
        metadata.engine_version,
        `${path}.metadata.engine_version`,
      ),
      generated_at: timestamp(
        metadata.generated_at,
        `${path}.metadata.generated_at`,
      ),
      generated_from_record_ref: nonEmpty(
        metadata.generated_from_record_ref,
        `${path}.metadata.generated_from_record_ref`,
      ),
    },
  };
}

const NOTE_FELT: readonly TasteCardNoteFelt[] = [
  "liked",
  "less",
  "burden",
  "more",
  "fine",
  "noticed",
];

function parseNoteFelt(value: unknown, path: string): TasteCardNoteFelt {
  const felt = NOTE_FELT.find((known) => known === value);
  return felt ?? fail("note_felt_unknown", path);
}

function parseNoteMarks(value: unknown, path: string): TasteCardNoteMark[] {
  return array(value, path).map((item, index) => {
    const at = `${path}[${index}]`;
    const mark = record(item, at);
    exactKeys(mark, ["label", "felt"], at);
    return {
      label: nonEmpty(mark.label, `${at}.label`),
      felt: parseNoteFelt(mark.felt, `${at}.felt`),
    };
  });
}

function parseNoteGroups(value: unknown, path: string): TasteCardNoteGroup[] {
  return array(value, path).map((item, index) => {
    const at = `${path}[${index}]`;
    const group = record(item, at);
    exactKeys(group, ["label", "marks"], at);
    return {
      label: nonEmpty(group.label, `${at}.label`),
      marks: parseNoteMarks(group.marks, `${at}.marks`),
    };
  });
}

/** The rows of 맛 밸런스 or 여운 밸런스. */
function parseNoteGauges(value: unknown, path: string): TasteCardNoteGauge[] {
  return array(value, path).map((item, index) => {
    const at = `${path}[${index}]`;
    const row = record(item, at);
    optionalKeys(
      row,
      ["key", "label", "mark", "word", "felt", "said"],
      ["level", "ends"],
      at,
    );
    const step = (value: unknown) =>
      Number.isInteger(value) && (value as number) >= 1 &&
      (value as number) <= 5;
    if (row.mark !== null && !step(row.mark)) {
      fail("note_mark_invalid", `${at}.mark`);
    }
    if ("level" in row && !step(row.level)) {
      fail("note_level_invalid", `${at}.level`);
    }
    const ends = "ends" in row ? array(row.ends, `${at}.ends`) : null;
    if (ends && ends.length !== 2) fail("note_ends_invalid", `${at}.ends`);
    return {
      key: nonEmpty(row.key, `${at}.key`),
      label: nonEmpty(row.label, `${at}.label`),
      mark: row.mark as number | null,
      word: row.word === null ? null : nonEmpty(row.word, `${at}.word`),
      felt: row.felt === null ? null : parseNoteFelt(row.felt, `${at}.felt`),
      said: row.said === null ? null : nonEmpty(row.said, `${at}.said`),
      ...("level" in row ? { level: row.level as number } : {}),
      ...(ends
        ? {
          ends: [
            nonEmpty(ends[0], `${at}.ends[0]`),
            nonEmpty(ends[1], `${at}.ends[1]`),
          ] as [string, string],
        }
        : {}),
    };
  });
}

function parseNote(value: unknown, path: string): TasteCardNote | null {
  if (value === null) return null;
  const note = record(value, path);
  exactKeys(
    note,
    [
      "original_name",
      "facts",
      "nose",
      "balance",
      // A card written since the gauges (2026-11-16) has the palate aromas.
      ...("flavor" in note ? ["flavor"] : []),
      "texture",
      // The 여운 gauges as rows came after the palate aromas.
      ...("finish_balance" in note ? ["finish_balance"] : []),
      "finish",
      "revisit",
      "appearance",
      "serving",
      ...("words" in note ? ["words"] : []),
    ],
    path,
  );
  return {
    original_name: note.original_name === null
      ? null
      : nonEmpty(note.original_name, `${path}.original_name`),
    facts: array(note.facts, `${path}.facts`).map((item, index) => {
      const at = `${path}.facts[${index}]`;
      const fact = record(item, at);
      exactKeys(fact, ["label", "value"], at);
      return {
        label: nonEmpty(fact.label, `${at}.label`),
        value: nonEmpty(fact.value, `${at}.value`),
      };
    }),
    nose: parseNoteGroups(note.nose, `${path}.nose`),
    balance: parseNoteGauges(note.balance, `${path}.balance`),
    ...("flavor" in note
      ? { flavor: parseNoteGroups(note.flavor, `${path}.flavor`) }
      : {}),
    texture: parseNoteGroups(note.texture, `${path}.texture`),
    ...("finish_balance" in note
      ? {
        finish_balance: parseNoteGauges(
          note.finish_balance,
          `${path}.finish_balance`,
        ),
      }
      : {}),
    finish: parseNoteGroups(note.finish, `${path}.finish`),
    revisit: note.revisit === null
      ? null
      : nonEmpty(note.revisit, `${path}.revisit`),
    appearance: note.appearance === null
      ? null
      : parseNoteAppearance(note.appearance, `${path}.appearance`),
    serving: note.serving === null
      ? null
      : parseNoteServing(note.serving, `${path}.serving`),
    ...("words" in note
      ? { words: parseNoteWords(note.words, `${path}.words`) }
      : {}),
  };
}

const NOTE_GROUP_FELT = ["liked", "missed"] as const;

/** The redraw words: the section groups, and 재음용 의사 by its option key. */
function parseNoteWords(value: unknown, path: string): TasteCardNoteWords {
  const words = record(value, path);
  exactKeys(words, ["groups", "revisit"], path);
  return {
    groups: array(words.groups, `${path}.groups`).map((item, index) => {
      const at = `${path}.groups[${index}]`;
      const group = record(item, at);
      exactKeys(group, ["felt", "label"], at);
      return {
        felt: NOTE_GROUP_FELT.find((felt) => felt === group.felt) ??
          fail("note_group_felt_unknown", `${at}.felt`),
        label: nonEmpty(group.label, `${at}.label`),
      };
    }),
    revisit: Object.fromEntries(
      Object.entries(record(words.revisit, `${path}.revisit`)).map((
        [id, item],
      ) => [id, nonEmpty(item, `${path}.revisit.${id}`)]),
    ),
  };
}

function parseNoteOptions(value: unknown, path: string): TasteCardNoteOption[] {
  return array(value, path).map((item, index) => {
    const at = `${path}[${index}]`;
    const option = record(item, at);
    const key = nonEmpty(option.key, `${at}.key`);
    if (!/^[a-z][a-z0-9_]{0,39}$/.test(key)) fail("note_option_key", at);
    const swatch = option.swatch ?? null;
    if (swatch !== null && !/^#[0-9A-Fa-f]{6}$/.test(string(swatch, at))) {
      fail("note_option_swatch", at);
    }
    return {
      key,
      label: nonEmpty(option.label, `${at}.label`),
      ...("swatch" in option ? { swatch: swatch as string | null } : {}),
      ...("icon" in option
        ? { icon: nonEmpty(option.icon, `${at}.icon`) }
        : {}),
      ...("short" in option
        ? { short: nonEmpty(option.short, `${at}.short`) }
        : {}),
    };
  });
}

function parseNoteAppearance(
  value: unknown,
  path: string,
): NonNullable<TasteCardNote["appearance"]> {
  const slot = record(value, path);
  exactKeys(slot, ["label", "groups"], path);
  return {
    label: nonEmpty(slot.label, `${path}.label`),
    groups: array(slot.groups, `${path}.groups`).map((item, index) => {
      const at = `${path}.groups[${index}]`;
      const group = record(item, at);
      exactKeys(group, ["key", "label", "prompt", "options"], at);
      if (group.key !== "appearance" && group.key !== "appearance_texture") {
        fail("note_group_key", `${at}.key`);
      }
      return {
        key: group.key,
        label: nonEmpty(group.label, `${at}.label`),
        prompt: nonEmpty(group.prompt, `${at}.prompt`),
        options: parseNoteOptions(group.options, `${at}.options`),
      };
    }),
  };
}

function parseNoteServing(
  value: unknown,
  path: string,
): NonNullable<TasteCardNote["serving"]> {
  const slot = record(value, path);
  exactKeys(slot, ["label", "prompt", "options"], path);
  return {
    label: nonEmpty(slot.label, `${path}.label`),
    prompt: nonEmpty(slot.prompt, `${path}.prompt`),
    options: parseNoteOptions(slot.options, `${path}.options`),
  };
}

function parseParagraphs(value: unknown, path: string): TasteCardParagraph[] {
  const items = array(value, path);
  if (items.length > maxParagraphs) fail("paragraph_count_invalid", path);
  return items.map((item, index) => {
    const object = record(item, `${path}[${index}]`);
    const explained = "terms" in object;
    exactKeys(
      object,
      explained ? ["answer", "text", "terms"] : ["answer", "text"],
      `${path}[${index}]`,
    );
    return {
      answer: nonEmpty(object.answer, `${path}[${index}].answer`),
      text: nonEmpty(object.text, `${path}[${index}].text`),
      ...(explained
        ? {
          terms: array(object.terms, `${path}[${index}].terms`).map((t, i) =>
            parseTerm(t, `${path}[${index}].terms[${i}]`)
          ),
        }
        : {}),
    };
  });
}

/** A served card's explanation of one word; a stored view carries none. */
function parseTerm(value: unknown, path: string): TasteCardTerm {
  const term = record(value, path);
  const keyed = "key" in term;
  exactKeys(
    term,
    ["word", "label", "kind", "description", ...(keyed ? ["key"] : [])],
    path,
  );
  return {
    word: nonEmpty(term.word, `${path}.word`),
    ...(keyed ? { key: nonEmpty(term.key, `${path}.key`) } : {}),
    label: nonEmpty(term.label, `${path}.label`),
    kind: nonEmpty(term.kind, `${path}.kind`),
    description: nonEmpty(term.description, `${path}.description`),
  };
}

function parseAlcoholIdentification(
  value: unknown,
  path: string,
): AlcoholIdentificationView {
  const object = record(value, path);
  // Drinks entered by name no longer exist; the old key and mode fail closed.
  if ("entered_alcohol_name" in object) {
    fail("entered_alcohol_name_removed", `${path}.entered_alcohol_name`);
  }
  if (object.mode === "direct_input") {
    fail("direct_input_removed", `${path}.mode`);
  }
  exactKeys(
    object,
    ["mode", "alcohol_item_id", "alcohol_name_snapshot", "category"],
    path,
  );
  if (string(object.mode, `${path}.mode`) !== "catalog_match") {
    fail("unknown_identification_mode", `${path}.mode`);
  }
  const category = object.category === null
    ? null
    : string(object.category, `${path}.category`);
  if (category !== null && !isAlcoholCategory(category)) {
    fail("unknown_alcohol_category", `${path}.category`);
  }
  return {
    mode: "catalog_match",
    alcohol_item_id: nonEmpty(
      object.alcohol_item_id,
      `${path}.alcohol_item_id`,
    ),
    alcohol_name_snapshot: nonEmpty(
      object.alcohol_name_snapshot,
      `${path}.alcohol_name_snapshot`,
    ),
    category: category as AlcoholCategory | null,
  };
}

/**
 * More than any one question has options: the aroma question takes as many
 * aromas as the reader noticed, so only a list no questionnaire could hold
 * is turned away before the options are looked up.
 */
const maximumAnswerOptions = 2000;

function parseQuestionnaireAnswer(value: unknown, path: string) {
  const object = record(value, path);
  exactKeys(
    object,
    ["question_key", "selected_option_keys", "free_text"],
    path,
  );
  const optionKeys = stringArray(
    object.selected_option_keys,
    `${path}.selected_option_keys`,
  );
  if (optionKeys.length > maximumAnswerOptions) {
    fail("answer_options_invalid", path);
  }
  const freeText = nullableString(object.free_text, `${path}.free_text`);
  if (freeText !== null && freeText.length > maximumNoteLength) {
    fail("free_text_too_long", `${path}.free_text`);
  }
  return {
    question_key: nonEmpty(object.question_key, `${path}.question_key`),
    selected_option_keys: optionKeys,
    free_text: freeText,
  };
}

function parseImageReference(value: unknown, path: string) {
  const object = record(value, path);
  exactKeys(object, ["source", "reference"], path);
  const source = string(object.source, `${path}.source`);
  if (
    source !== "user_photo" && source !== "catalog" &&
    source !== "category_fallback"
  ) {
    fail("unknown_image_source", `${path}.source`);
  }
  return {
    source,
    reference: nonEmpty(object.reference, `${path}.reference`),
  } as TasteCardView["product"]["image_reference"] & object;
}

function parseConversion(value: unknown, path: string) {
  const object = record(value, path);
  exactKeys(object, ["anonymous_session_id", "conversion_token"], path);
  return {
    anonymous_session_id: nonEmpty(
      object.anonymous_session_id,
      `${path}.anonymous_session_id`,
    ),
    conversion_token: nonEmpty(
      object.conversion_token,
      `${path}.conversion_token`,
    ),
  };
}

function questionnaireVersion(value: unknown): string {
  const version = nonEmpty(value, "$request.questionnaire_version");
  if (version.length > 64) {
    fail("questionnaire_version_invalid", "$request.questionnaire_version");
  }
  return version;
}

function record(value: unknown, path: string): Record<string, unknown> {
  if (!isJsonObject(value)) fail("object_required", path);
  return value;
}

function array(value: unknown, path: string): unknown[] {
  return Array.isArray(value) ? value : fail("array_required", path);
}

function string(value: unknown, path: string): string {
  return typeof value === "string" ? value : fail("string_required", path);
}

function nonEmpty(value: unknown, path: string): string {
  const result = string(value, path).trim();
  return result.length > 0 ? result : fail("non_empty_string_required", path);
}

/** The longest note a record keeps; the database holds the same limit. */
const maximumNoteLength = 2000;

function nullableString(value: unknown, path: string): string | null {
  return value === null ? null : nonEmpty(value, path);
}

function nullableAbv(value: unknown, path: string): number | null {
  if (value === null) return null;
  return typeof value === "number" && value >= 0 && value <= 100
    ? value
    : fail("abv_percent_required", path);
}

function uuid(value: unknown, path: string): string {
  const result = nonEmpty(value, path);
  return UUID_PATTERN.test(result) ? result : fail("uuid_required", path);
}

function uuidV4(value: unknown, path: string): string {
  const result = nonEmpty(value, path);
  return UUID_V4_PATTERN.test(result) ? result : fail("uuid_v4_required", path);
}

function nullableUuid(value: unknown, path: string): string | null {
  return value === null ? null : uuid(value, path);
}

const TAG_KINDS: readonly TasteCardTagKind[] = [
  "liked",
  "less",
  "burden",
  "more",
  "fine",
];

function parseNext(value: unknown, path: string): TasteCardNext | null {
  if (value === null) return null;
  const next = record(value, path);
  exactKeys(next, ["lines"], path);
  return {
    lines: array(next.lines, `${path}.lines`).map((item, index) => {
      const at = `${path}.lines[${index}]`;
      const line = record(item, at);
      const explained = "terms" in line;
      exactKeys(line, ["text", ...(explained ? ["terms"] : [])], at);
      return {
        text: nonEmpty(line.text, `${at}.text`),
        ...(explained
          ? {
            terms: array(line.terms, `${at}.terms`).map((t, i) =>
              parseTerm(t, `${at}.terms[${i}]`)
            ),
          }
          : {}),
      };
    }),
  };
}

function parseTags(value: unknown, path: string): TasteCardTag[] {
  return array(value, path).map((item, index) => {
    const tag = record(item, `${path}[${index}]`);
    const explained = "term" in tag;
    exactKeys(
      tag,
      explained ? ["label", "kind", "term"] : ["label", "kind"],
      `${path}[${index}]`,
    );
    const kind = tag.kind;
    if (!TAG_KINDS.includes(kind as TasteCardTagKind)) {
      fail("tag_kind_invalid", `${path}[${index}].kind`);
    }
    return {
      label: nonEmpty(tag.label, `${path}[${index}].label`),
      kind: kind as TasteCardTagKind,
      ...(explained
        ? {
          term: tag.term === null
            ? null
            : parseTerm(tag.term, `${path}[${index}].term`),
        }
        : {}),
    };
  });
}

const GUIDE_CHANGES: readonly TasteCardGuideDirection["change"][] = [
  "keep",
  "lower",
  "higher",
];

/** A key that came later is allowed, never required: a stored card has none. */
function optionalKeys(
  object: Record<string, unknown>,
  required: readonly string[],
  optional: readonly string[],
  path: string,
): void {
  exactKeys(
    object,
    [...required, ...optional.filter((key) => key in object)],
    path,
  );
}

const nullableTerm = (value: unknown, path: string) =>
  value === null ? null : parseTerm(value, path);

function parseGuide(value: unknown, path: string): TasteCardGuide | null {
  if (value === null) return null;
  const guide = record(value, path);
  optionalKeys(
    guide,
    ["head", "picks", "tip", "levels", "directions"],
    ["profile"],
    path,
  );
  return {
    head: nonEmpty(guide.head, `${path}.head`),
    picks: array(guide.picks, `${path}.picks`).map((item, index) => {
      const at = `${path}.picks[${index}]`;
      const pick = record(item, at);
      optionalKeys(
        pick,
        ["country", "place", "keyword", "note"],
        ["words", "labelWord", "term"],
        at,
      );
      if ("labelWord" in pick && typeof pick.labelWord !== "boolean") {
        fail("label_word_invalid", `${at}.labelWord`);
      }
      return {
        country: nullableString(pick.country, `${at}.country`),
        place: nullableString(pick.place, `${at}.place`),
        keyword: nonEmpty(pick.keyword, `${at}.keyword`),
        ...("words" in pick
          ? {
            words: array(pick.words, `${at}.words`).map((entry, i) => {
              const wordAt = `${at}.words[${i}]`;
              const word = record(entry, wordAt);
              optionalKeys(word, ["text"], ["term"], wordAt);
              return {
                text: nonEmpty(word.text, `${wordAt}.text`),
                ...("term" in word
                  ? { term: nullableTerm(word.term, `${wordAt}.term`) }
                  : {}),
              };
            }),
          }
          : {}),
        ...("labelWord" in pick
          ? { labelWord: pick.labelWord as boolean }
          : {}),
        note: nullableString(pick.note, `${at}.note`),
        ...("term" in pick
          ? { term: nullableTerm(pick.term, `${at}.term`) }
          : {}),
      };
    }),
    tip: nullableString(guide.tip, `${path}.tip`),
    levels: array(guide.levels, `${path}.levels`).map((item, index) => {
      const at = `${path}.levels[${index}]`;
      const level = record(item, at);
      optionalKeys(level, ["label", "mark", "range"], ["word", "term"], at);
      const mark = level.mark;
      if (
        typeof mark !== "number" || !Number.isInteger(mark) || mark < 1 ||
        mark > 5
      ) {
        fail("level_mark_invalid", `${at}.mark`);
      }
      return {
        label: nonEmpty(level.label, `${at}.label`),
        mark: mark as number,
        range: nonEmpty(level.range, `${at}.range`),
        ...("word" in level
          ? { word: nullableString(level.word, `${at}.word`) }
          : {}),
        ...("term" in level
          ? { term: nullableTerm(level.term, `${at}.term`) }
          : {}),
      };
    }),
    directions: array(guide.directions, `${path}.directions`).map(
      (item, index) => {
        const at = `${path}.directions[${index}]`;
        const direction = record(item, at);
        exactKeys(direction, ["word", "change"], at);
        const change = direction.change;
        if (
          !GUIDE_CHANGES.includes(change as TasteCardGuideDirection["change"])
        ) {
          fail("direction_change_invalid", `${at}.change`);
        }
        return {
          word: nonEmpty(direction.word, `${at}.word`),
          change: change as TasteCardGuideDirection["change"],
        };
      },
    ),
    ...("profile" in guide
      ? {
        profile: guide.profile === null
          ? null
          : array(guide.profile, `${path}.profile`).map((item, index) => {
            const at = `${path}.profile[${index}]`;
            const line = record(item, at);
            exactKeys(line, ["label", "words"], at);
            return {
              label: nonEmpty(line.label, `${at}.label`),
              words: array(line.words, `${at}.words`).map((word, i) =>
                nonEmpty(word, `${at}.words[${i}]`)
              ),
            };
          }),
      }
      : {}),
  };
}

function stringArray(value: unknown, path: string): string[] {
  return array(value, path).map((item, index) =>
    nonEmpty(item, `${path}[${index}]`)
  );
}

function timestamp(value: unknown, path: string): string {
  const result = nonEmpty(value, path);
  return Number.isNaN(Date.parse(result))
    ? fail("timestamp_required", path)
    : result;
}

function exactKeys(
  object: Record<string, unknown>,
  expected: readonly string[],
  path: string,
): void {
  const actual = Object.keys(object).sort();
  const wanted = [...expected].sort();
  if (
    actual.length !== wanted.length ||
    actual.some((key, i) => key !== wanted[i])
  ) {
    fail("wire_keys_mismatch", path);
  }
}

function fail(code: string, path: string): never {
  throw new TasteCardContractError(code, path);
}
