/**
 * The words of the 다음 술 가이드: what the reader liked or found a burden
 * in their own words, each head sentence, the tips under the picks, the
 * label marks by kind, the 결 words and the sake bands. card_guide.ts
 * decides which to use.
 */
import type { Band } from "./card_knowledge.ts";

/** What the reader liked, in the words of their answer. */
export const LIKED: Readonly<Record<string, string>> = {
  "taste.sweetness": "단맛",
  "taste.acidity": "산미",
  "taste.bitterness": "쓴맛",
  "mouthfeel.light": "가벼운 질감",
  "mouthfeel.heavy": "묵직한 질감",
  "mouthfeel.smooth": "부드러운 목넘김",
  "mouthfeel.drying": "떫은맛",
  "mouthfeel.bubbles": "탄산",
  "mouthfeel.warmth": "알코올 열감",
  "finish.persistence": "긴 여운",
  "finish.clean": "깔끔한 마무리",
  "finish.aroma_echo": "코끝에 남는 잔향",
};

/** What the reader found a burden. */
export const BURDENED: Readonly<Record<string, string>> = {
  "taste.sweetness": "단맛",
  "taste.acidity": "산미",
  "taste.bitterness": "쓴맛",
  "mouthfeel.drying": "떫은맛",
  "mouthfeel.heavy": "묵직함",
  "mouthfeel.light": "가벼움",
  "mouthfeel.bubbles": "탄산",
  "mouthfeel.warmth": "알코올 열감",
  "finish.persistence": "여운",
  "finish.off_flavor": "삼킨 뒤 올라오는 잡내",
};

/** The first row whose levels all hold names the style's 결. */
export const GYEOL: readonly {
  when: Readonly<Record<string, readonly Band[]>>;
  word: string;
}[] = [
  { when: { carbonation: ["high"] }, word: "기포가 톡 쏘는" },
  { when: { sweetness: ["high"] }, word: "달콤한" },
  { when: { astringency: ["high"], body: ["high"] }, word: "단단하고 묵직한" },
  { when: { body: ["high"] }, word: "묵직한" },
  { when: { acidity: ["high"], body: ["low", "mid"] }, word: "산뜻한" },
  { when: { finish_cleanliness: ["high"] }, word: "깔끔한" },
  { when: { smoothness: ["high"] }, word: "부드러운" },
  { when: { body: ["low"] }, word: "가벼운" },
  { when: { astringency: ["low"], body: ["mid"] }, word: "부드러운" },
  { when: { aroma_intensity: ["high"] }, word: "향이 진한" },
  { when: { aroma_intensity: ["low"] }, word: "향이 은은한" },
];

/**
 * The head names no sensation: the chips under it do. One sentence for every
 * kind (the user's wording, 2026-11-06): "좋았던 매력은 살리고 부담은 줄인 싱글
 * 몰트 위스키의 추천 키워드예요". Slots: {NB} what was turned, {K} kind.
 */
export const HEAD_BURDEN = "좋았던 매력은 살리고 {NB} {K}의 추천 키워드예요.";

export const HEAD_POSITIVE = "좋았던 매력을 이어갈 {K}의 추천 키워드예요.";

/** The balanced card (every taste 적당했어요): nothing to call liked. */
export const HEAD_BALANCED =
  "이번 잔의 균형이 편안하셨다면, 그 균형 그대로 이어갈 {K}의 추천 키워드예요.";

/** Nothing liked, only burdens: "부담은 줄인 싱글 몰트 위스키의 추천 키워드예요". */
export const HEAD_ONLY_BURDEN = "{NB} {K}의 추천 키워드예요.";

export const WINE_TIP =
  "와인 라벨(앞·뒷면)이나 매장 설명 카드에서 이 특징을 찾아보세요!";

export const SAKE_TIP =
  "이자카야 메뉴판이나 바틀 뒷면(라벨)에서 이 키워드를 찾아보세요!";

export const CASK_TIP =
  "바(Bar) 메뉴판이나 바틀 라벨에서 위 단어를 찾아보세요!";

/** Traditional bottle shops print the same four bars under every product, and the label its 도수. */
export const LABEL_TIP =
  "바틀 뒷면의 원재료 표기나 상품 맛 그래프를 확인해보세요!";

export const WINE_SPEC: readonly [string, string][] = [
  ["sweetness", "당도"],
  ["acidity", "산도"],
  ["astringency", "타닌"],
  ["body", "바디"],
];

export const SPARKLING_SPEC: readonly [string, string][] = [
  ["sweetness", "당도"],
  ["acidity", "산도"],
  ["carbonation", "탄산"],
  ["body", "바디"],
];

export const TRADITIONAL_SPEC: readonly [string, string][] = [
  ["sweetness", "단맛"],
  ["acidity", "산미"],
  ["carbonation", "탄산"],
  ["body", "바디"],
];

/**
 * Sake shelves and back labels carry no 1–5 marks: they print 일본주도 (plus
 * is dry) and 산도. The bands our five sweetness levels sit in, from the 985
 * bottles that carry both (medians +6, +3.5, +1, −2.8, −15), named as the
 * Japanese trade names the bands (±1.4, ±3.4, ±6) go by; and the 산도 range
 * our five acidity levels sit in (839 bottles: medians 1.05, 1.3, 1.5, 1.6, 2.5).
 */
export const SMV_BANDS: readonly string[] = [
  "아주 드라이한 카라구치 (+6 이상)",
  "카라구치 (+3.5~+5.9)",
  "보통 (±1.4)",
  "살짝 단 아마구치 (-1.5~-3.4)",
  "단 아마구치 (-6 이하)",
];

export const ACIDITY_BANDS: readonly string[] = [
  "1.1 이하",
  "1.2~1.4",
  "1.4~1.6",
  "1.6~1.9",
  "2.0 이상",
];
