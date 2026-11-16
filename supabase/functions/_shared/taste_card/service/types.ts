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
  /**
   * The dictionary term, as `type:key` (aroma:cherry): what 나의 용어 사전
   * keeps when the reader saves the explanation. It came later.
   */
  key?: string;
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
 *   fine   only on a card stored while 적당했어요 was an answer
 */
export type TasteCardTagKind = "liked" | "less" | "burden" | "more" | "fine";
export type TasteCardTag = {
  label: string;
  kind: TasteCardTagKind;
  /** The dictionary's explanation of the tag's sensation; filled when served. */
  term?: TasteCardTerm | null;
};

/**
 * One label word inside a chip, as it is printed and how it is read:
 * Merlot(메를로), Sherry Cask(셰리 캐스크), 생막걸리. A chip of two words
 * ('dry'·'trocken') has two, each opening its own explanation.
 */
export type TasteCardGuideWord = {
  text: string;
  /** The dictionary's explanation of the word; filled when served. */
  term?: TasteCardTerm | null;
};

/** One pick of the 다음 술 가이드: a chip to look for on a label or menu. */
export type TasteCardGuidePick = {
  /** ISO 3166-1 alpha-2 of the country whose flag leads the chip; null when none. */
  country: string | null;
  /** 미국 워싱턴, 아일라섬: where the pick comes from; null when none. */
  place: string | null;
  /** The chip's words in one line, each as 원어(한글): Merlot(메를로), dry · trocken. */
  keyword: string;
  /** The same words one by one, so each can be underlined and explained. It came later; an older stored card has none. */
  words?: TasteCardGuideWord[];
  /** True when the chip is words printed on the label (dry, 山廃), false when it names what the bottle is: a grape, a region, a grade, a cask. The app titles the chips by it. It came with `words`. */
  labelWord?: boolean;
  /** Why this is picked for this reader, under the chip; the word itself is explained by its term. Null when nothing. */
  note: string | null;
  /** The explanation of the chip's first word, for an app that reads one per chip; filled when served. */
  term?: TasteCardTerm | null;
};
/** One gauge: the 1–5 mark to look for, said in a word, and the range in the label's own words. */
export type TasteCardGuideLevel = {
  label: string;
  mark: number;
  range: string;
  /** The mark as a word a shop would use: 드라이, 미디엄 바디. It came later. */
  word?: string | null;
  /** The explanation of the gauge's name (당도, 타닌); filled when served. */
  term?: TasteCardTerm | null;
};
/** 이번 술을 기준으로: keep a liked thing, turn a burden down or up. No longer written; an older stored card has them. */
export type TasteCardGuideDirection = {
  word: string;
  change: "keep" | "lower" | "higher";
};
/** One line of a drink said in words instead of gauges: AROMA 바닐라 · 꿀. */
export type TasteCardGuideProfileLine = {
  /** AROMA, FLAVOR, FINISH. */
  label: string;
  words: string[];
};
/** 다음 술은 이렇게 골라보세요: the head sentence, then the parts the app draws. */
export type TasteCardGuide = {
  head: string;
  picks: TasteCardGuidePick[];
  /** How to use the guide in a shop, at the bottom; null when none. */
  tip: string | null;
  levels: TasteCardGuideLevel[];
  /** Always empty on a card written now; kept for the cards stored before. */
  directions: TasteCardGuideDirection[];
  /** The drink to look for said in words (a whisky: AROMA, FLAVOR, FINISH); absent or null for a kind shown by gauges. It came later. */
  profile?: TasteCardGuideProfileLine[] | null;
};

/**
 * How the reader took one thing of the 테이스팅 노트: the tag kinds, and
 * `noticed` for a thing named without saying whether it was liked.
 */
export type TasteCardNoteFelt = TasteCardTagKind | "noticed";

/** One thing the reader named in a section: 체리 liked, 떫음 less. */
export type TasteCardNoteMark = { label: string; felt: TasteCardNoteFelt };

/** The things of one section taken one way: 좋았어요, then its marks. */
export type TasteCardNoteGroup = { label: string; marks: TasteCardNoteMark[] };

/** One 맛 밸런스 row: the bottle's own level, and what the reader said of it. */
export type TasteCardNoteGauge = {
  /** The row's axis: sweetness, acidity, bitterness, body, ... */
  key: string;
  label: string;
  /** The level the catalog read for this bottle, 1 to 5; null when it read none. */
  mark: number | null;
  /** The level in a shop's word (드라이); null without a mark or a word for it. */
  word: string | null;
  felt: TasteCardNoteFelt | null;
  /** The reader's answer in a few words: 은은해서 좋았어요. */
  said: string | null;
};

/**
 * 테이스팅 노트: the record as a tasting sheet of its kind of drink. Only
 * what the reader answered and what the catalog states of the bottle; a
 * section nobody answered is an empty list.
 */
export type TasteCardNote = {
  /** The drink's name in its own language, under the name shown; null when the catalog has none. */
  original_name: string | null;
  /** 생산자 · 품종 · 산지 · 빈티지 …: the rows the catalog can fill. The kind and the ABV are the product's own. */
  facts: { label: string; value: string }[];
  /** 향: the aromas the reader named, by the questionnaire's own groups. */
  nose: TasteCardNoteGroup[];
  /** 맛 밸런스: the kind's rows. */
  balance: TasteCardNoteGauge[];
  /** 질감: what the mouth felt while drinking. */
  texture: TasteCardNoteGroup[];
  /** 마무리와 여운: what stayed after swallowing. */
  finish: TasteCardNoteGroup[];
  /** 재음용 의사: the reader's answer; null when none. */
  revisit: string | null;
  /**
   * 외관: what the member may note of how the drink looked, by its kind (a
   * wine's 색 and 점성, a 탁주's 탁도); null for a kind with none. The
   * choice itself is the member's own, kept with the record, not in the card.
   */
  appearance: {
    label: string;
    groups: {
      /** The field of the record's note the choice is kept under. */
      key: "appearance" | "appearance_texture";
      label: string;
      /** What an unfilled group asks: 색상을 선택해주세요. */
      prompt: string;
      options: TasteCardNoteOption[];
    }[];
  } | null;
  /** 음용 방식 or 음용 온도: how it was served, by kind; null for a kind with none. */
  serving: {
    label: string;
    /** What the slot's sheet asks: 마신 방식을 모두 골라주세요. */
    prompt: string;
    options: TasteCardNoteOption[];
  } | null;
  /** Attached when the card is sent, never stored: see TasteCardNoteWords. */
  words?: TasteCardNoteWords;
};

/** One choice of a slot the member fills in: its stored key and its name. */
/**
 * What the app needs to redraw a section the owner has just re-answered,
 * before the card is written again: the words the server would write for
 * each answer, by the answer's option id. An aroma's name is the app's own.
 */
export type TasteCardNoteWords = {
  /** The groups a section's marks stand under, in the sheet's order. */
  groups: { felt: "liked" | "missed"; label: string }[];
  /** A 질감 or 마무리 answer: the mark it puts on the sheet. */
  marks: Record<string, TasteCardNoteMark>;
  /**
   * The 질감 sensations (their notice option ids) and the 마무리 answers in
   * the order a section lists their marks, whatever order they were chosen in.
   */
  order: string[];
  /** A taste's reaction, or its reason: what the taste's row says. */
  taste: Record<string, { felt: TasteCardNoteFelt; said: string }>;
  /** 재음용 의사, by the answer. */
  revisit: Record<string, string>;
};

export type TasteCardNoteOption = {
  key: string;
  label: string;
  /** The colour a palette shows beside the name, #RRGGBB; null or absent for none. */
  swatch?: string | null;
  /** The small drawing that shows a state of the liquid (sediment_low, legs_heavy); absent for none. */
  icon?: string;
  /** The term alone, written where the choice is shown once made (니트 for 원액 그대로(니트)); absent when the label is it. */
  short?: string;
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
  /** 왜 편안했을까요: filled only on a card stored while 적당했어요 was an answer. */
  balanced: TasteCardParagraph[];
  /** 테이스팅 노트, the card's second tab. It came later; a card stored before it has no such key. */
  note?: TasteCardNote | null;
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
