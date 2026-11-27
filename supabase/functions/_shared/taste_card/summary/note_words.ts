/**
 * The words of the 테이스팅 노트 (summary/note.ts), in one place for the
 * owner to rewrite. Drafts.
 */

/**
 * 향 · 풍미 · 여운 are listed by how each thing was taken, in this order
 * (the owner's words). A thing was liked or it was not: there is no middle
 * group. A burden is 부담됐어요 whether it was too much, too little or out
 * of place. The gauges' own words are the gauge sheet's
 * (catalog/sensory/gauge-definitions.json).
 */
import appearance from "../../../../../catalog/sensory/appearance.json" with {
  type: "json",
};

export const FELT_GROUPS: readonly (readonly [string, string])[] = [
  ["liked", "마음에 들었어요"],
  ["missed", "부담됐어요"],
];

/** The head rows' names. */
export const FACT_LABEL = {
  producer: "생산자",
  grape: "품종",
  region: "산지",
  vintage: "빈티지",
  age: "숙성",
  cask: "캐스크",
  ingredient: "주원료",
  making: "증류·숙성",
} as const;
export const AGE_VALUE = "{N}년";

/**
 * 재음용 의사: the reader's own answer, in the sheet's words. The middle
 * answer (무난하게 괜찮았어요) is neither a yes nor a no. A question skipped
 * reads as the record's own middle choice, 애매해요: the question offers no
 * "don't know", so the sheet shows none.
 */
export const REVISIT_SAID: Readonly<Record<string, string>> = {
  want_again: "있음",
  would_accept_again: "무난",
  do_not_want_again: "없음",
  unknown: "애매해요",
};

/**
 * What a skipped 재음용 의사 was written as before it read 애매해요. The word
 * is stored with the card, so a card written then is served with today's.
 */
export const REVISIT_SAID_BEFORE: Readonly<Record<string, string>> = {
  "모르겠음": REVISIT_SAID.unknown,
};

/* ------------------------------------------- what the member fills in */

/** [key, name, colour]: one colour of a palette. */
type Colour = readonly [key: string, label: string, swatch: string];
/** [key, name, drawing]: one state of the liquid, shown by a small drawing. */
type State = readonly [key: string, label: string, icon: string];

/**
 * 외관: what a member may note of how the drink looked. The words and the
 * colours live in catalog/sensory/appearance.json, which the app's
 * questions read too.
 */
export const APPEARANCE_LABEL: string = appearance.label;
export const COLOR_GROUP: string = appearance.color.label;
export const COLOR_PROMPT: string = appearance.color.prompt;

/**
 * The colour spectrum of each kind, from young or pale to aged or dark (the
 * owner's lists and colour values). A sparkling wine is read on the white one.
 */
export const COLOR_CHOICES: Readonly<Record<string, readonly Colour[]>> =
  appearance.color.palettes as unknown as Record<string, readonly Colour[]>;

/** 점성: how the liquid clings to the glass, asked of a wine and a whisky. */
export const VISCOSITY_GROUP: string = appearance.viscosity.label;
export const VISCOSITY_PROMPT: string = appearance.viscosity.prompt;
export const VISCOSITY_CHOICES: readonly State[] = appearance.viscosity
  .choices as unknown as readonly State[];

/** 탁도: how much sediment clouds the cup, asked of a 탁주. */
export const TURBIDITY_GROUP: string = appearance.turbidity.label;
export const TURBIDITY_PROMPT: string = appearance.turbidity.prompt;
export const TURBIDITY_CHOICES: readonly State[] = appearance.turbidity
  .choices as unknown as readonly State[];

/**
 * 음용 방식 · 음용 온도: how it was served, by sheet (the owner's lists).
 * [key, the choice in plain words with its term, the term the head writes].
 */
type Serving = readonly [key: string, label: string, short: string];
const WINE_SERVING = {
  label: "음용 방식",
  prompt: "마신 방식을 모두 골라주세요",
  choices: [
    ["open_now", "바로 오픈", "바로 오픈"],
    ["breathing", "미리 열어둠(브리딩)", "브리딩"],
    ["aeration", "공기 주입(에어링)", "에어링"],
    ["decanting", "디캔터 사용(디캔팅)", "디캔팅"],
    ["chilled", "차갑게(칠링)", "칠링"],
  ],
} as const;
export const SERVING: Readonly<
  Record<
    string,
    { label: string; prompt: string; choices: readonly Serving[] }
  >
> = {
  wine: WINE_SERVING,
  sparkling: WINE_SERVING,
  whisky: {
    label: "음용 방식",
    prompt: "마신 방식을 모두 골라주세요",
    choices: [
      ["neat", "원액 그대로(니트)", "니트"],
      ["rocks", "얼음과 함께(온더락)", "온더락"],
      ["highball", "탄산수 믹스(하이볼)", "하이볼"],
      ["water", "물 몇 방울", "물 몇 방울"],
    ],
  },
  distilled: {
    label: "음용 방식",
    prompt: "마신 방식을 모두 골라주세요",
    choices: [
      ["neat", "원액 그대로(스트레이트)", "스트레이트"],
      ["rocks", "얼음과 함께(온더락)", "온더락"],
      ["highball", "하이볼·토닉", "하이볼·토닉"],
      ["mizuwari", "물과 섞어서(미즈와리)", "미즈와리"],
    ],
  },
  sake: {
    label: "음용 온도",
    prompt: "마신 온도를 모두 골라주세요",
    choices: [
      ["chilled", "차갑게(레이슈)", "레이슈"],
      ["room", "상온", "상온"],
      ["lukewarm", "미지근하게(누루칸)", "누루칸"],
      ["warm", "따뜻하게(아쓰캉)", "아쓰캉"],
    ],
  },
  brewed: {
    label: "음용 온도",
    prompt: "마신 온도를 모두 골라주세요",
    choices: [
      ["chilled", "차갑게", "차갑게"],
      ["room", "상온", "상온"],
      ["warm", "따뜻하게(온주)", "온주"],
    ],
  },
};
