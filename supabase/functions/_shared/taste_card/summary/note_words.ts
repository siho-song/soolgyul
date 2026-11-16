/**
 * The words of the 테이스팅 노트 (summary/note.ts), in one place for the
 * owner to rewrite. Drafts.
 */

/**
 * 향 · 질감 · 마무리 are listed by how each thing was taken, in this order
 * (the owner's words). A thing was liked or it was not: there is no middle
 * group. A burden is 부담됐어요 whether it was too much, too little or out
 * of place.
 */
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
 * 맛 밸런스 rows by sheet: the three tastes every reader answers, then the
 * levels the kind's shelf speaks of. A row past the tastes shows only where
 * the catalog read the level for the bottle.
 */
export const BALANCE_ROWS: Readonly<
  Record<string, readonly (readonly [string, string])[]>
> = {
  wine: [
    ["sweetness", "당도"],
    ["acidity", "산도"],
    ["bitterness", "쓴맛"],
    ["astringency", "타닌"],
    ["body", "바디"],
  ],
  sparkling: [
    ["sweetness", "당도"],
    ["acidity", "산도"],
    ["bitterness", "쓴맛"],
    ["carbonation", "탄산"],
    ["body", "바디"],
  ],
  whisky: [
    ["sweetness", "단맛"],
    ["acidity", "산미"],
    ["bitterness", "쓴맛"],
    ["body", "바디"],
  ],
  sake: [
    ["sweetness", "단맛"],
    ["acidity", "산미"],
    ["bitterness", "쓴맛"],
    ["body", "바디"],
    ["carbonation", "탄산"],
  ],
  brewed: [
    ["sweetness", "단맛"],
    ["acidity", "산미"],
    ["bitterness", "쓴맛"],
    ["carbonation", "탄산"],
    ["body", "바디"],
  ],
  distilled: [
    ["sweetness", "단맛"],
    ["acidity", "산미"],
    ["bitterness", "쓴맛"],
    ["body", "바디"],
  ],
};

/** What the reader said of a taste, by the answer and its reason. */
export const TASTE_SAID: Readonly<Record<string, string>> = {
  liked: "좋았어요",
  "liked:gentle": "은은해서 좋았어요",
  "liked:pronounced": "또렷해서 좋았어요",
  "liked:harmonious": "다른 맛과 잘 어울렸어요",
  burden: "아쉬웠어요",
  "burden:excessive": "너무 강해서 부담스러웠어요",
  "burden:too_weak": "조금 더 느껴졌으면 했어요",
  "burden:masking": "다른 맛을 가려서 아쉬웠어요",
  "burden:disharmonious": "어울리지 않아 아쉬웠어요",
};

/** 질감: what the mouth felt while drinking, as the sheet names it. */
export const TEXTURE_LABEL: Readonly<Record<string, string>> = {
  light: "가벼움",
  heavy: "묵직함",
  smooth: "매끄러움",
  drying: "떫음",
  bubbles: "탄산감",
  warmth: "열감",
};

/** 마무리와 여운: each finish answer as a line of the sheet. */
export const FINISH_LABEL: Readonly<Record<string, string>> = {
  "persistence:liked": "기분 좋게 이어지는 여운",
  "persistence:burden": "너무 빨리 사라지는 여운",
  "clean:liked": "금방 깔끔해지는 마무리",
  "heavy:burden": "텁텁하고 무겁게 남는 느낌",
  "aroma_echo:liked": "코끝으로 올라오는 잔향",
  "off_flavor:burden": "삼킨 뒤 올라오는 잡내",
};

/**
 * 재음용 의사: the reader's own answer, in the sheet's three words. One who
 * would drink it again given the chance has it too.
 */
export const REVISIT_SAID: Readonly<Record<string, string>> = {
  want_again: "있음",
  would_accept_again: "있음",
  do_not_want_again: "없음",
  unknown: "모르겠음",
};

/* ------------------------------------------- what the member fills in */

/** [key, name, colour]: one colour of a palette. */
type Colour = readonly [key: string, label: string, swatch: string];
/** [key, name, drawing]: one state of the liquid, shown by a small drawing. */
type State = readonly [key: string, label: string, icon: string];

/** 외관: what a member may note of how the drink looked. */
export const APPEARANCE_LABEL = "외관(Appearance)";
export const COLOR_GROUP = "색";
export const COLOR_PROMPT = "색상을 선택해주세요";

/**
 * The colour spectrum of each kind, from young or pale to aged or dark (the
 * owner's lists and colour values). A sparkling wine is read on the white one.
 */
export const COLOR_CHOICES: Readonly<Record<string, readonly Colour[]>> = {
  red_wine: [
    ["purple", "보랏빛", "#4E1D3B"],
    ["ruby", "자줏빛", "#6E1528"],
    ["deep_ruby", "짙은 루비", "#801323"],
    ["garnet", "석류석빛", "#932C2A"],
    ["deep_garnet", "짙은 가넷", "#741F1A"],
    ["tawny", "벽돌빛", "#8A3C1F"],
    ["red_brown", "붉은 갈색", "#6E331A"],
    ["brown", "갈색", "#55351E"],
  ],
  white_wine: [
    ["water", "물빛", "#F9F9F0"],
    ["green_yellow", "연한 녹황색", "#E6EBB2"],
    ["lemon", "레몬색", "#EFDB68"],
    ["straw", "짚색", "#E2C75E"],
    ["pale_gold", "연한 금빛", "#D8B43C"],
    ["gold", "황금색", "#C79E2E"],
    ["deep_gold", "짙은 골드", "#B28325"],
    ["amber", "호박색", "#AA6F1E"],
    ["tawny", "황갈색", "#8E561F"],
    ["brown", "갈색", "#6A3C16"],
  ],
  rose_wine: [
    ["pale_pink", "아주 연한 연홍빛", "#FAECE6"],
    ["pink", "분홍", "#F2B2B3"],
    ["salmon", "연어색", "#EDA184"],
    ["orange", "주황빛 로제", "#E58D60"],
    ["coral", "산호빛", "#DC725E"],
    ["rose", "장밋빛", "#CE5362"],
    ["ruby", "루비 로제", "#AF364B"],
    ["garnet", "가넷 로제", "#91312E"],
  ],
  whisky: [
    ["clear", "맑은 은빛", "#F4EFEB"],
    ["pale_straw", "옅은 짚색", "#EAD8A7"],
    ["gold", "밝은 금빛", "#D8B35B"],
    ["amber", "호박색", "#BA7F33"],
    ["copper", "구리색", "#9C5824"],
    ["mahogany", "짙은 마호가니", "#76341C"],
    ["dark_brown", "어두운 갈색", "#4E2114"],
  ],
};

/** 점성: how the liquid clings to the glass, asked of a wine and a whisky. */
export const VISCOSITY_GROUP = "점성";
export const VISCOSITY_PROMPT = "점성을 선택해주세요";
export const VISCOSITY_CHOICES: readonly State[] = [
  ["light", "가볍고 산뜻함", "legs_light"],
  ["medium", "매끄럽고 적당함", "legs_medium"],
  ["heavy", "진득하고 오일리함", "legs_heavy"],
];

/** 탁도: how much sediment clouds the cup, asked of a 탁주. */
export const TURBIDITY_GROUP = "탁도";
export const TURBIDITY_PROMPT = "탁도를 선택해주세요";
export const TURBIDITY_CHOICES: readonly State[] = [
  ["clear", "맑고 가벼움", "sediment_low"],
  ["milky", "뽀얗고 부드러움", "sediment_mid"],
  ["thick", "걸쭉하고 묵직함", "sediment_high"],
];

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
