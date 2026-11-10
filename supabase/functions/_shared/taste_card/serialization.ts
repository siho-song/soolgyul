import {
  ALCOHOL_CATEGORY_KEYS,
  type AlcoholCategory,
} from "../soolgyul_contract.ts";
import {
  type AlcoholIdentificationView,
  type AnonymousTasteCardConversionRequest,
  type CreateTasteCardResultRequest,
  TASTE_CARD_WIRE_SCHEMA_VERSION,
  type TasteCardGuide,
  type TasteCardGuideDirection,
  type TasteCardParagraph,
  type TasteCardResultEnvelope,
  type TasteCardTag,
  type TasteCardTagKind,
  type TasteCardTerm,
  type TasteCardView,
} from "./types.ts";

export class TasteCardContractError extends Error {
  constructor(public readonly code: string, public readonly path: string) {
    super(`${code}:${path}`);
    this.name = "TasteCardContractError";
  }
}

const categoryKeys = new Set<string>(ALCOHOL_CATEGORY_KEYS);
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
  exactKeys(
    object,
    ["product", "bite", "positive", "burden", "balanced", "metadata"],
    path,
  );
  const product = record(object.product, `${path}.product`);
  exactKeys(
    product,
    ["drink_name_snapshot", "user_name", "image_reference", "category_label"],
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
    },
    bite: {
      nickname: nonEmpty(bite.nickname, `${path}.bite.nickname`),
      tags: parseTags(bite.tags, `${path}.bite.tags`),
      summary: nonEmpty(bite.summary, `${path}.bite.summary`),
      brief: bite.brief == null
        ? null
        : nonEmpty(bite.brief, `${path}.bite.brief`),
      guide: parseGuide(bite.guide, `${path}.bite.guide`),
    },
    positive: parseParagraphs(object.positive, `${path}.positive`),
    burden: parseParagraphs(object.burden, `${path}.burden`),
    balanced: parseParagraphs(object.balanced, `${path}.balanced`),
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
  exactKeys(term, ["word", "label", "kind", "description"], path);
  return {
    word: nonEmpty(term.word, `${path}.word`),
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
  if (category !== null && !categoryKeys.has(category)) {
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
  if (optionKeys.length > 20) {
    fail("answer_options_invalid", path);
  }
  return {
    question_key: nonEmpty(object.question_key, `${path}.question_key`),
    selected_option_keys: optionKeys,
    free_text: nullableString(object.free_text, `${path}.free_text`),
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
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    fail("object_required", path);
  }
  return value as Record<string, unknown>;
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

function nullableString(value: unknown, path: string): string | null {
  return value === null ? null : nonEmpty(value, path);
}

function uuid(value: unknown, path: string): string {
  const result = nonEmpty(value, path);
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(result)
    ? result
    : fail("uuid_required", path);
}

function uuidV4(value: unknown, path: string): string {
  const result = nonEmpty(value, path);
  return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(result)
    ? result
    : fail("uuid_v4_required", path);
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

function parseGuide(value: unknown, path: string): TasteCardGuide | null {
  if (value === null) return null;
  const guide = record(value, path);
  exactKeys(guide, ["head", "picks", "tip", "levels", "directions"], path);
  return {
    head: nonEmpty(guide.head, `${path}.head`),
    picks: array(guide.picks, `${path}.picks`).map((item, index) => {
      const at = `${path}.picks[${index}]`;
      const pick = record(item, at);
      exactKeys(pick, ["country", "place", "keyword", "note"], at);
      return {
        country: nullableString(pick.country, `${at}.country`),
        place: nullableString(pick.place, `${at}.place`),
        keyword: nonEmpty(pick.keyword, `${at}.keyword`),
        note: nullableString(pick.note, `${at}.note`),
      };
    }),
    tip: nullableString(guide.tip, `${path}.tip`),
    levels: array(guide.levels, `${path}.levels`).map((item, index) => {
      const at = `${path}.levels[${index}]`;
      const level = record(item, at);
      exactKeys(level, ["label", "mark", "range"], at);
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
