/**
 * The words of the 다음 술 가이드: what the reader liked or found a burden
 * in their own words, each head sentence, the tip under the picks, the
 * label marks by kind and the word each mark goes by in a shop, the sake
 * bands, the sentences a chip's reason is built from, and the words of a
 * whisky's profile. summary/guide.ts decides which to use.
 */
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

/** 묵직함 minded only after swallowing: what stays in the mouth, not the weight. */
export const RESIDUE = "텁텁함";

/** The reason a liked level was liked, said before its word: 은은한 단맛, 또렷한 산미. */
export const LIKED_SIDE = { low: "은은한", high: "또렷한" } as const;

/**
 * The head names no sensation: the chips under it do. One sentence for every
 * kind (the user's wording, 2026-11-06): "좋았던 매력은 살리고 부담은 줄인 싱글
 * 몰트 위스키의 추천 키워드예요". Slots: {NB} what was turned, {K} kind.
 */
export const HEAD_BURDEN = "좋았던 매력은 살리고 {NB} {K}의 추천 키워드예요.";

export const HEAD_POSITIVE = "좋았던 매력을 이어갈 {K}의 추천 키워드예요.";

/** Nothing liked, only burdens: "부담은 줄인 싱글 몰트 위스키의 추천 키워드예요". */
export const HEAD_ONLY_BURDEN = "{NB} {K}의 추천 키워드예요.";

/**
 * How to use the guide in a shop, by kind (the owner's wording, 2026-11-15):
 * alone at the shelf the reader checks the label, and with staff the screen
 * is shown as it is.
 */
export const WINE_TIP =
  "혼자 고를 땐 라벨·설명 카드를 확인하고, 보틀샵·식당에선 이 화면을 그대로 보여주세요.";

export const WHISKY_TIP =
  "혼자 고를 땐 라벨·메뉴판을 확인하고, 바에서는 바텐더에게 이 화면을 그대로 보여주세요.";

export const SAKE_TIP =
  "혼자 고를 땐 뒷면 라벨을 확인하고, 이자카야에선 직원에게 이 화면을 그대로 보여주세요.";

export const TRADITIONAL_TIP =
  "혼자 고를 땐 뒷면 원재료·맛 그래프를 보고, 보틀샵·주점에선 이 화면을 그대로 보여주세요.";

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

/** A 증류식 소주 carries no bubbles, and nearly every one sits at the same 산미. */
export const SOJU_SPEC: readonly [string, string][] = [
  ["sweetness", "단맛"],
  ["body", "바디"],
];

export const TRADITIONAL_SPEC: readonly [string, string][] = [
  ["sweetness", "단맛"],
  ["acidity", "산미"],
  ["carbonation", "탄산"],
  ["body", "바디"],
];

/**
 * A mark said as a shop says it, 1 to 5. A wine shelf uses the trade's own
 * words (드라이, 미디엄 바디); a traditional drink's graph is read in plain
 * Korean. A draft for the owner to edit.
 */
export const WINE_LEVEL_WORDS: Readonly<Record<string, readonly string[]>> = {
  sweetness: ["드라이", "세미 드라이", "미디엄", "세미 스위트", "스위트"],
  acidity: [
    "낮은 산도",
    "조금 낮은 산도",
    "중간 산도",
    "조금 높은 산도",
    "높은 산도",
  ],
  astringency: [
    "아주 부드러운 타닌",
    "부드러운 타닌",
    "중간 타닌",
    "탄탄한 타닌",
    "강한 타닌",
  ],
  body: [
    "라이트 바디",
    "라이트-미디엄 바디",
    "미디엄 바디",
    "미디엄-풀 바디",
    "풀 바디",
  ],
  carbonation: [
    "잔잔한 탄산",
    "조금 잔잔한 탄산",
    "중간 탄산",
    "조금 강한 탄산",
    "강한 탄산",
  ],
};

export const TRADITIONAL_LEVEL_WORDS: Readonly<
  Record<string, readonly string[]>
> = {
  sweetness: [
    "달지 않은 편",
    "살짝 단 편",
    "적당히 단 편",
    "단 편",
    "아주 단 편",
  ],
  acidity: [
    "산미가 거의 없는 편",
    "산미가 은은한 편",
    "산미가 적당한 편",
    "산미가 또렷한 편",
    "산미가 강한 편",
  ],
  carbonation: [
    "탄산이 거의 없는 편",
    "탄산이 잔잔한 편",
    "탄산이 적당한 편",
    "탄산이 톡 쏘는 편",
    "탄산이 강한 편",
  ],
  body: [
    "가벼운 편",
    "조금 가벼운 편",
    "중간 무게",
    "조금 묵직한 편",
    "묵직한 편",
  ],
};

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

/* ------------------------------------------------ why a chip is picked */

/**
 * The note under a chip says why it is picked for this reader, never what
 * the word means (the word's own balloon does that). It is one frame
 * sentence, by what the pick answers, and where enough bottles were counted,
 * one sentence of that count after it.
 *
 * Slots of every frame: {L} what the reader liked that the pick keeps, {X}
 * what they found a burden or lacking that it turns, {A} an aroma the pick
 * brings. Every note is also given what was counted, for the owner to use:
 * {N} the bottles on our shelf of the kind that carry the chip's word, {T}
 * the bottles on that shelf, {K} the shelf's name.
 */

/** Only liked answers: what was liked carries on. */
export const NOTE_CARRY = "좋아하신 {L}{이} 이어지는 쪽이에요.";

/** A liked aroma's neighbour, not the aroma itself: 바닐라 liked, 코코넛 brought. */
export const NOTE_CARRY_KIN =
  "좋아하신 {L}{과} 결이 가까운 {A}{이} 나는 쪽이에요.";

/** Liked and burden: the burden eased, a liked thing shown to stay. */
export const NOTE_EASE_KEEP =
  "{X}{은} 덜고, 좋아하신 {L}{은} 이어지는 쪽이에요.";

/** Liked and lack: what was too little filled, a liked thing shown to stay. */
export const NOTE_FILL_KEEP =
  "아쉬웠던 {X}{은} 채우고, 좋아하신 {L}{은} 이어지는 쪽이에요.";

/**
 * Burden only, said from this bottle and not from a claimed taste. The first
 * pair is used when the dictionary shows the pick near the bottle on every
 * level the reader did not mention; the second claims nothing about the rest.
 */
export const NOTE_ONLY_EASE_ALIKE =
  "이번 술과 결은 비슷하고, {X}만 덜한 쪽이에요.";
export const NOTE_ONLY_FILL_ALIKE =
  "이번 술과 결은 비슷하고, {X}만 더한 쪽이에요.";
export const NOTE_ONLY_EASE = "이번 술에서 {X}만 덜어낸 쪽이에요.";
export const NOTE_ONLY_FILL = "이번 술에서 {X}만 더한 쪽이에요.";

/** A word to pass over: the bottle's own aroma came from it, or bottles with it are made to carry the aroma. */
export const NOTE_PASS_OWN = "이번 술의 {X}{은} 이 표기에서 온 향이에요.";
export const NOTE_PASS = "이 표기가 있는 술은 {X}{이} 배도록 만들어요.";

/**
 * Only liked answers and no chip the rules could give: what the bottle
 * itself is, to find again. A wine's grape, a sake's grade, a kind or its
 * own label word.
 */
export const NOTE_SAME_GRAPE = "이번 술과 같은 품종이에요.";
export const NOTE_SAME_GRADE = "이번 술과 같은 등급이에요.";
export const NOTE_SAME_KIND = "이번 술과 같은 종류예요.";

/** The ingredient the bottle itself was made from, named when something in it was liked. */
export const NOTE_SAME_INGREDIENT = "이번 술과 같은 원료예요.";

/** Which of two bottles a word is printed on is meant: {W} the word, {Q} 갓 나온, 오래된. */
export const NOTE_WHICH = "{W}{은} {Q} 것으로 보세요.";

/**
 * How sweet a grape's bottles feel, counted from our single-variety bottles.
 * {N} those bottles, {P} the percent of them on the asked side, {S} the side
 * (달게, 덜 달게), {M} how strongly the count speaks.
 */
export const EVIDENCE_LEAN =
  "저희가 모은 {N}병 중 {P}%가 {S} 느껴지는 쪽으로, {M}이에요.";
export const LEAN_SIDE = { sweeter: "달게", drier: "덜 달게" } as const;

/** The wording a counted share earns, the first row it reaches: 40% is 많은 편, never a flat claim. */
export const SHARE_SAID: readonly (readonly [number, string])[] = [
  [0.67, "대부분"],
  [0.5, "절반 이상"],
  [0, "많은 편"],
];

/** The level is the middle value of our own bottles of the grape, grade, cask or method. {N} how many. */
export const EVIDENCE_COUNTED = "저희가 모은 {N}병이 대체로 그랬어요.";

/** An aroma to turn down: the label word that brings it, to pass over. {W} the chip's words. */
export const WITHOUT_WORD = "{W} 없는 것";

/* --------------------------------------------------- a whisky in words */

/** The lines of a whisky's profile, as a shop's own card names them. */
export const PROFILE_LABELS = {
  aroma: "AROMA",
  flavor: "FLAVOR",
  finish: "FINISH",
} as const;

/** A burden said as its absence or its turn. {X} the aroma or the burden. */
export const PROFILE_WITHOUT = "{X} 없이";
export const PROFILE_LESS = "{X} 덜하게";
export const PROFILE_MORE = "{X} 더";
/** It may be there, but should not stay after swallowing. */
export const PROFILE_NOT_LINGERING = "{X} 남지 않게";

/** A burden's short name in a profile line, where the reader's own is a phrase. */
export const PROFILE_BURDENED: Readonly<Record<string, string>> = {
  "finish.off_flavor": "잡내",
};
