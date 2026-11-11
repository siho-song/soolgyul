import type {
  AlcoholCategory,
  AlcoholIdentificationInput,
} from "../../contract.ts";

export const TASTE_CARD_WIRE_SCHEMA_VERSION =
  "taste-card-result-wire-v3" as const;

export type QuestionnaireAnswerInput = {
  question_key: string;
  selected_option_keys: string[];
  free_text: string | null;
};

export type CreateTasteCardResultRequest = {
  idempotency_key: string;
  anonymous_session_id: string | null;
  questionnaire_version: string;
  alcohol_identification: AlcoholIdentificationInput;
  answers: QuestionnaireAnswerInput[];
  q7_free_text: string | null;
  photo_asset_id: string | null;
};

export type AlcoholIdentificationView = {
  mode: "catalog_match";
  alcohol_item_id: string;
  alcohol_name_snapshot: string;
  category: AlcoholCategory | null;
};

/** One paragraph of a reason section: the reader's answer, then the sentences. */
export type TasteCardParagraph = {
  answer: string;
  text: string;
  /**
   * The dictionary's explanation of the words the text sets in bold, for the
   * reader to open (writing/terms.ts). Filled when a card is served; a stored
   * view has none.
   */
  terms?: TasteCardTerm[];
};

/** A word the card uses, the dictionary's name for it, and its explanation. */
export type TasteCardTerm = {
  /** The word as the card writes it: 체리 향, 산미, 떫은 조임, 체리향 (a tag). */
  word: string;
  /** The dictionary's name: 체리, 산미, 떫음. */
  label: string;
  /** 향, 맛, 질감, 여운: what kind of term it is. */
  kind: string;
  description: string;
};

/**
 * The card as the reader sees it: the product, then three parts. 술결 한입
 * (별명 · 핵심 요약 · 다음 술 가이드), 왜 잘 맞았을까요, 왜 부담이었을까요.
 * A section with nothing to say is an empty list; the app shows no heading.
 */
/**
 * One 핵심 요약 tag: the sensation as the reader answered it, and which way.
 *   liked  좋았어요            less    부담, 너무 셌거나 끝에 오래 남았어요
 *   burden 부담, 어울리지 않았어요 등   more    너무 약했어요 / 너무 짧았어요
 *   fine   적당했어요 (the balanced card)
 */
export type TasteCardTagKind = "liked" | "less" | "burden" | "more" | "fine";
export type TasteCardTag = {
  label: string;
  kind: TasteCardTagKind;
  /** The dictionary's explanation of the tag's sensation; filled when served. */
  term?: TasteCardTerm | null;
};

/** One pick of the 다음 술 가이드: a chip to look for on a label or menu. */
export type TasteCardGuidePick = {
  /** ISO 3166-1 alpha-2 of the country whose flag leads the chip; null when none. */
  country: string | null;
  /** 미국 워싱턴, 아일라섬: where the pick comes from; null when none. */
  place: string | null;
  /** 그르나슈·가르나차, 준마이 다이긴조, 피트 처리 맥아(Peated), 생막걸리. */
  keyword: string;
  /** What it brings, under the chip (스모키한 향이 나요); null when nothing. */
  note: string | null;
  /** The dictionary's explanation of a cask or method chip; filled when served. */
  term?: TasteCardTerm | null;
};
/** One gauge: the 1–5 mark to look for, and the range in the label's own words. */
export type TasteCardGuideLevel = {
  label: string;
  mark: number;
  range: string;
};
/** 이번 술을 기준으로: keep a liked thing, turn a burden down or up. */
export type TasteCardGuideDirection = {
  word: string;
  change: "keep" | "lower" | "higher";
};
/** 다음 술은 이렇게 골라보세요: the head sentence, then the parts the app draws. */
export type TasteCardGuide = {
  head: string;
  picks: TasteCardGuidePick[];
  /** 와인 라벨에서 이 특징을 찾아보세요: the caption at the bottom; null when none. */
  tip: string | null;
  levels: TasteCardGuideLevel[];
  directions: TasteCardGuideDirection[];
};

export type TasteCardView = {
  product: {
    drink_name_snapshot: string;
    user_name: string | null;
    image_reference: {
      source: "user_photo" | "catalog" | "category_fallback";
      reference: string;
    } | null;
    category_label: string | null;
    /** 준마이 긴조, 레드 와인; cards made before this was kept have no such key. */
    style_label?: string | null;
    abv_percent?: number | null;
  };
  bite: {
    nickname: string;
    /** 핵심 요약: the tags (흙향 liked, 떫은맛 less …), then the one line under them. */
    tags: TasteCardTag[];
    summary: string;
    /** The summary's sentence with the dressing left off, for the 취향 tab's
     * record cards; null on cards made before it was written. */
    brief: string | null;
    /** 다음 술은 이렇게 골라보세요; null when nothing in the dictionary fits. */
    guide: TasteCardGuide | null;
  };
  positive: TasteCardParagraph[];
  burden: TasteCardParagraph[];
  /** 왜 편안했을까요: the balanced card's paragraphs, else empty. */
  balanced: TasteCardParagraph[];
  metadata: {
    snapshot_ref: string;
    schema_version: 3;
    engine_version: string;
    generated_at: string;
    generated_from_record_ref: string;
  };
};

export type TasteCardResultEnvelope = {
  wire_schema_version: typeof TASTE_CARD_WIRE_SCHEMA_VERSION;
  result_id: string;
  record_id: string | null;
  snapshot_ref: string;
  ownership_state: "anonymous" | "saved";
  alcohol_identification: AlcoholIdentificationView;
  view: TasteCardView;
  conversion: {
    anonymous_session_id: string;
    conversion_token: string;
  } | null;
  created_at: string;
};

export type RetryableErrorCode =
  | "catalog_unavailable"
  | "engine_temporarily_unavailable";

export type CreateTasteCardResultResponse =
  | { state: "final"; result: TasteCardResultEnvelope }
  | {
    state: "retryable";
    idempotency_key: string;
    attempt_ref: string;
    error_code: RetryableErrorCode;
    retry_after_ms: number | null;
  };

export type AnonymousTasteCardConversionRequest = {
  anonymous_session_id: string;
  result_id: string;
  conversion_token: string;
  idempotency_key: string;
};
