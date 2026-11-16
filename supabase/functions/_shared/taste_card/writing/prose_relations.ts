/**
 * 쓰기: the paragraphs for an answer explained by another sensation of the
 * same drink: 드러남 (a weak partner let it show), 가림 (a strong one covered
 * it, or it covered others), 구분 (what was felt came from something else),
 * 조합 (two sensations together).
 *
 * Each entry is a short `name` plus one `body` (decided 2026-11-06). The name
 * is a noun phrase that the writer joins with 과/와 into the section subtitle
 * ("단맛을 씻어 낸 신맛과 짜임새를 흐린 단맛"); the body says the drink's trait
 * and how the two sensations act on each other in the mouth. The writer runs
 * the bodies of a section into one text and adds the closing sentence itself.
 *
 * Variants are chosen by the finding's frame (`row@strong_burden`,
 * `row@gentle_liked`, `row@liked_swap`, `row@burden_swap`) and, for a support
 * pair, by the sensation that burdened (`row@acidity`).
 */
import type { Prose } from "./prose.ts";

/* ================================================================ 구분 */
// What the reader felt came from another sensation the drink has more of.
// The same relation holds whether it was welcome or not, so liked and burden
// share the body and differ only in the name.

const DISTINCTION_BODY = {
  bubbles_acid_alcohol:
    "이 {kind}{은} 탄산은 약하지만 새콤함이나 알코올 기운이 또렷해서, 날카로운 신맛과 알코올의 자극이 혀를 따끔하게 두드리며 탄산처럼 느껴져요.",
  drying_acidity:
    "이 {kind}{은} 떫은 맛은 적지만 신맛이 또렷해서, 센 신맛이 침을 왈칵 돌게 하는 만큼 떫은 성분 없이도 입안이 조이는 것처럼 느껴져요.",
  heavy_sugar_alcohol:
    "이 {kind}{은} 질감 자체는 가볍지만 단맛이나 알코올 기운이 또렷해서, 당분과 알코올이 혀를 두툼하게 덮는 만큼 술이 묵직하게 느껴져요.",
  light_fizz_acid:
    "이 {kind}{은} 몸은 묵직하지만 탄산이나 새콤함이 또렷해서, 톡 쏘는 기포와 산뜻한 신맛이 묵직한 술도 경쾌하게 넘어가게 해 줘요.",
  // A still wine made heavy by its alcohol alone: no sugar is claimed.
  heavy_alcohol:
    "이 {kind}{은} 질감 자체는 가볍지만 알코올 기운이 또렷해서, 알코올이 혀를 두툼하게 덮는 만큼 술이 묵직하게 느껴져요.",
} as const;

/* ====================================================== 와인의 단맛 인상 */
// Why a still wine whose sweetness mark does not stand high in its kind felt
// sweet: the bottle's own aromas, and its tannin, acidity and body as places
// within the kind ({in_kind}: "레드 와인 가운데"). The writer picks the text
// by the causes the bottle has (findings/wine_sweetness.ts); with none, the
// row does not fire and nothing is said.

const WINE_SWEETNESS_BODY = {
  aroma:
    "이 {kind}{은} {given_aromas}{을} 지니고 있어서, 코로 들어온 달콤한 향이 단맛과 하나로 묶여 실제보다 더 달게 느껴져요.",
  aroma_soft:
    "이 {kind}{은} {given_aromas}{을} 지닌 데다 {in_kind} {soft_traits}이라서, 코로 들어온 달콤한 향이 단맛처럼 느껴지고 그 단맛을 누르는 맛도 적어요.",
  soft:
    "이 {kind}{은} {in_kind} {soft_traits}이라서, 단맛을 누르는 맛이 적은 만큼 단맛이 가려지지 않고 또렷하게 드러나요.",
  body:
    "이 {kind}{은} {in_kind} 묵직한 편이라서, 입안을 둥글게 채우는 무게감이 단맛처럼 느껴져요.",
} as const;

/* ================================================================ 가림 (부담) */
// The stronger sensation covered the other.

const MASKING_BODY = {
  acidity_sweetness:
    "이 {kind}{은} 단맛도 갖췄지만 신맛이 더 앞에 나서서, 혀 옆쪽을 자극해 침을 돌게 하는 신맛이 센 만큼 단맛을 씻어 내듯 덮어 버려요.",
  sweetness_acidity:
    "이 {kind}{은} 새콤함도 갖췄지만 단맛이 더 앞에 나서서, 혀에 가장 먼저 닿는 단맛이 진한 만큼 뒤에 오는 새콤함을 감싸다 못해 덮어 버려요.",
  sweetness_warmth:
    "이 {kind}{은} 도수가 낮지 않지만 단맛이 더 앞에 나서서, 알코올의 자극을 감싸 주던 단맛이 진한 만큼 온기까지 덮어 술의 다른 결이 흐려져요.",
  sweetness_drying:
    "이 {kind}{은} 떫은 맛도 갖췄지만 단맛이 더 앞에 나서서, 혀에 가장 먼저 닿는 단맛이 진한 만큼 뒤에 오는 떫은 조임까지 덮어 짜임새가 흐려져요.",
} as const;

export const RELATION_LIKED: Readonly<Record<string, Prose>> = {
  /* ------------------------------------------------------------ 드러남 */
  exposure_sweetness_by_acidity: {
    name: "포근하게 남는 단맛",
    body:
      "이 {kind}{은} 신맛이 거의 없어서, 원래 단맛을 깎아 산뜻하게 만들던 신맛이 빠진 만큼 단맛이 그대로 둥글고 포근하게 남아요.",
  },
  exposure_drying_by_sweetness: {
    name: "또렷하게 드러나는 짜임새",
    body:
      "이 {kind}{은} 단맛이 거의 없어서, 원래 떫은 느낌을 감싸 주던 단맛이 빠진 만큼 그 조임이 그대로 드러나 짜임새가 또렷해져요.",
  },
  exposure_bubbles_by_sweetness_body: {
    name: "청량하게 톡톡 쏘는 탄산",
    body:
      "이 {kind}{은} 단맛이나 무게감이 적어서, 원래 탄산의 따가움을 눅여 주던 것이 빠진 만큼 기포의 자극이 그대로 드러나 더 청량하게 느껴져요.",
  },

  /* -------------------------------------------------------------- 가림 */
  "masking_acidity_sweetness@gentle_liked": {
    name: "산미가 잡아 준 은은한 단맛",
    body:
      "이 {kind}{은} 새콤함이 또렷해서, 신맛이 단맛을 깎아 주는 만큼 단맛이 물리지 않고 은은하게 느껴져요.",
  },
  "masking_sweetness_warmth@gentle_liked": {
    name: "단맛이 감싸 준 은은한 온기",
    body:
      "이 {kind}{은} 단맛이 꽤 있어서, 단맛이 알코올의 자극을 감싸 주는 만큼 열감이 화끈함 대신 포근한 온기로 느껴져요.",
  },
  "masking_heavy_bubbles@gentle_liked": {
    name: "무게감이 눅여 준 은은한 탄산",
    body:
      "이 {kind}{은} 무게감이 있어서, 몸이 탄산의 따끔함을 눅여 주는 만큼 기포가 쏘는 대신 부드럽게 톡톡 느껴져요.",
  },
  "masking_heavy_warmth@gentle_liked": {
    name: "무게감이 감싸 준 은은한 온기",
    body:
      "이 {kind}{은} 무게감이 있어서, 몸이 알코올의 자극을 감싸 주는 만큼 열감이 화끈함 대신 든든한 온기로 느껴져요.",
  },
  "masking_bubbles_sweetness@gentle_liked": {
    name: "탄산이 씻어 준 은은한 단맛",
    body:
      "이 {kind}{은} 탄산이 또렷해서, 기포가 혀에 남는 단맛을 씻어 주는 만큼 단맛이 물리지 않고 산뜻하게 느껴져요.",
  },
  "masking_sweetness_drying@gentle_liked": {
    name: "단맛이 달래 준 은은한 떫은맛",
    body:
      "이 {kind}{은} 단맛이 꽤 있어서, 단맛이 떫은 조임을 감싸 주는 만큼 떫음이 거슬림 대신 부드러운 짜임새로 느껴져요.",
  },
  "masking_drying_smooth@gentle_liked": {
    name: "떫은맛을 받쳐 주는 고운 질감",
    body:
      "이 {kind}{은} 떫은 맛이 또렷하지만 질감은 매끄러워서, 떫은 조임 사이로 결이 고운 질감이 받쳐 주는 만큼 거칠지 않고 단단하게 느껴져요.",
  },

  /* -------------------------------------------------------------- 구분 */
  "distinction_sweetness_sweet_scent@liked_swap": {
    name: "달콤한 향이 채워 준 단맛",
    body:
      "이 {kind}{은} 단맛은 적지만 {given_aromas}{을} 지니고 있어서, 코로 들어온 달콤한 향이 단맛과 하나로 묶여 실제보다 더 달게 느껴져요.",
  },
  "wine_sweetness_raised@aroma": {
    name: "달콤한 향이 채워 준 단맛",
    body: WINE_SWEETNESS_BODY.aroma,
  },
  "wine_sweetness_raised@aroma_soft": {
    name: "달콤한 향이 채워 준 단맛",
    body: WINE_SWEETNESS_BODY.aroma_soft,
  },
  "wine_sweetness_raised@soft": {
    name: "가려지지 않고 드러난 단맛",
    body: WINE_SWEETNESS_BODY.soft,
  },
  "wine_sweetness_raised@body": {
    name: "둥근 무게감이 채워 준 단맛",
    body: WINE_SWEETNESS_BODY.body,
  },
  "distinction_bubbles_acid_alcohol@liked_swap": {
    name: "톡 쏘며 입안을 깨우는 자극",
    body: DISTINCTION_BODY.bubbles_acid_alcohol,
  },
  "distinction_drying_acidity@liked_swap": {
    name: "입안을 기분 좋게 조이는 신맛",
    body: DISTINCTION_BODY.drying_acidity,
  },
  "distinction_heavy_sugar_alcohol@liked_swap": {
    name: "단맛과 도수가 만든 무게감",
    body: DISTINCTION_BODY.heavy_sugar_alcohol,
  },
  "distinction_heavy_sugar_alcohol@liked_swap|alcohol": {
    name: "도수가 만든 무게감",
    body: DISTINCTION_BODY.heavy_alcohol,
  },
  "distinction_light_fizz_acid@liked_swap": {
    name: "탄산과 산미의 경쾌한 목넘김",
    body: DISTINCTION_BODY.light_fizz_acid,
  },

  /* -------------------------------------------------------------- 조합 */
  combination_sweet_scent_sweetness: {
    name: "달콤한 향과 단맛의 풍성함",
    body:
      "이 {kind}{은} {aroma}{과} 단맛을 함께 지니고 있어서, 코로 먼저 만든 단 기대를 혀가 채워 주는 만큼 단맛이 더 풍성하게 느껴져요.",
  },
  combination_acid_fizz: {
    name: "산미와 탄산의 청량감",
    body:
      "이 {kind}{은} 새콤함과 탄산을 함께 지니고 있어서, 신맛이 침을 돌게 하고 기포가 혀를 두드리며 입안이 두 배로 깨어나요.",
  },
  combination_warmth_sweetness: {
    name: "단맛과 온기의 포근함",
    body:
      "이 {kind}{은} 알코올의 온기와 단맛을 함께 지니고 있어서, 단맛이 열감의 날을 감싸고 온기가 단맛을 몸으로 퍼뜨려 주며 포근하게 느껴져요.",
  },
  combination_warmth_heavy: {
    name: "온기와 무게감의 든든함",
    body:
      "이 {kind}{은} 알코올의 온기와 묵직한 무게감을 함께 지니고 있어서, 무게감이 열감을 감싸고 온기가 그 무게를 든든함으로 바꿔 줘요.",
  },
};

/* ================================================================ 부담 */

export const RELATION_BURDEN: Readonly<Record<string, Prose>> = {
  /* ------------------------------------------------------------ 드러남 */
  exposure_sweetness_by_acidity: {
    name: "신맛 없이 물리는 단맛",
    body:
      "이 {kind}{은} 신맛이 거의 없어서, 원래 단맛을 깎아 산뜻하게 만들던 신맛이 빠진 만큼 단맛이 그대로 남아 물리기 쉬워요.",
  },
  exposure_drying_by_sweetness: {
    name: "단맛 없이 드러난 떫은 조임",
    body:
      "이 {kind}{은} 단맛이 거의 없어서, 원래 떫은 느낌을 감싸 주던 단맛이 빠진 만큼 그 조임이 그대로 드러나요.",
  },
  // The reader wanted structure under the smoothness.
  exposure_smooth_by_astringency: {
    name: "짜임새 없이 밋밋한 매끄러움",
    body:
      "이 {kind}{은} 떫은 맛이 거의 없어서, 입안에 걸리는 짜임새를 만들어 줄 조임이 빠진 만큼 술이 혀를 스치기만 해 매끄럽다 못해 밋밋하게 느껴져요.",
  },
  exposure_bubbles_by_sweetness_body: {
    name: "그대로 쏘는 따끔한 탄산",
    body:
      "이 {kind}{은} 단맛이나 무게감이 적어서, 원래 탄산의 따가움을 눅여 주던 것이 빠진 만큼 기포의 자극이 그대로 드러나요.",
  },

  /* -------------------------------------------------------------- 가림 */
  // 신맛 over 단맛
  "masking_acidity_sweetness@strong_burden": {
    name: "단맛을 씻어 낸 신맛",
    body: MASKING_BODY.acidity_sweetness,
  },
  // 단맛 over 새콤함
  "masking_sweetness_acidity@strong_burden": {
    name: "새콤함을 덮은 단맛",
    body: MASKING_BODY.sweetness_acidity,
  },
  // 단맛 over 열감
  "masking_sweetness_warmth@strong_burden": {
    name: "온기까지 덮은 단맛",
    body: MASKING_BODY.sweetness_warmth,
  },
  // 단맛 over 떫음
  "masking_sweetness_drying@strong_burden": {
    name: "짜임새를 흐린 단맛",
    body: MASKING_BODY.sweetness_drying,
  },
  // 떫음 over 과일 향 (kinds other than wine; the wine text is in writing/prose.ts)
  masking_drying_fruit: {
    name: "{given_aroma}{을} 가로막은 떫은맛",
    body:
      "이 {kind}{은} {given_aroma}{을} 지녔지만 떫은 맛이 또렷해서, 입안을 조이는 떫음이 과일 향이 퍼지는 걸 가로막아 향보다 조임이 먼저 느껴져요.",
  },
  // 무게감 over 탄산·새콤함·열감
  "masking_heavy_bubbles@strong_burden": {
    name: "청량함을 누른 무게감",
    body:
      "이 {kind}{은} 탄산도 있지만 무게감이 더 앞에 나서서, 입안을 채우는 밀도가 높은 만큼 기포의 청량함까지 눌러 답답하게 느껴져요.",
  },
  "masking_heavy_acidity@strong_burden": {
    name: "산뜻함을 누른 무게감",
    body:
      "이 {kind}{은} 새콤함도 갖췄지만 무게감이 더 앞에 나서서, 입안을 채우는 밀도가 높은 만큼 새콤함의 산뜻함까지 눌러 답답하게 느껴져요.",
  },
  "masking_heavy_warmth@strong_burden": {
    name: "입안을 꽉 채우는 무게감",
    body:
      "이 {kind}{은} 도수도 낮지 않지만 무게감이 더 앞에 나서서, 알코올 기운을 감싸 주던 밀도가 너무 높은 만큼 포근함을 넘어 입안이 꽉 차게 느껴져요.",
  },
  // 탄산 over 단맛
  "masking_bubbles_sweetness@strong_burden": {
    name: "단맛을 씻어 낸 탄산",
    body:
      "이 {kind}{은} 단맛도 갖췄지만 탄산이 더 앞에 나서서, 혀를 따끔하게 두드리는 기포가 센 만큼 단맛이 느껴지기도 전에 자극이 먼저 와요.",
  },

  /* -------------------------------------------------------------- 구분 */
  // The same reasons when the sweetness was too much.
  ...Object.fromEntries(
    Object.entries(WINE_SWEETNESS_BODY).map(([variant, body]) => [
      `wine_sweetness_raised@${variant}`,
      { name: "생각보다 달게 느껴진 단맛", body },
    ]),
  ),
  "wine_sweetness_raised@aroma": {
    name: "생각보다 달게 느껴진 단맛",
    body:
      "이 {kind}{은} {given_aromas}{을} 지니고 있어서, 코로 들어온 달콤한 향이 혀의 단맛과 하나로 묶여 실제보다 훨씬 달게 느껴져요.",
  },
  "distinction_bubbles_acid_alcohol@burden_swap": {
    name: "혀를 따끔하게 두드리는 자극",
    body: DISTINCTION_BODY.bubbles_acid_alcohol,
  },
  "distinction_drying_acidity@burden_swap": {
    name: "입안을 바짝 조이는 신맛",
    body: DISTINCTION_BODY.drying_acidity,
  },
  "distinction_heavy_sugar_alcohol@burden_swap": {
    name: "단맛과 알코올이 덮는 무게",
    body: DISTINCTION_BODY.heavy_sugar_alcohol,
  },
  "distinction_heavy_sugar_alcohol@burden_swap|alcohol": {
    name: "알코올이 덮는 무게",
    body: DISTINCTION_BODY.heavy_alcohol,
  },
  // The reader wished the drink had stayed heavier.
  "distinction_light_fizz_acid@burden_swap": {
    name: "너무 가볍게 흩어진 무게감",
    body: DISTINCTION_BODY.light_fizz_acid,
  },

  /* -------------------------------------------------------------- 조합 */
  combination_acid_fizz_burden: {
    name: "신맛과 탄산의 날카로운 자극",
    body:
      "이 {kind}{은} 신맛과 탄산을 함께 지니고 있어서, 둘 다 혀를 따끔하게 자극하는 감각인 만큼 겹치면 상쾌함을 넘어 날카로운 자극이 돼요.",
  },
  combination_sweet_heavy: {
    name: "무겁게 가라앉는 단맛",
    body:
      "이 {kind}{은} 단맛과 묵직한 무게감을 함께 지니고 있어서, 혀에 오래 남는 단맛과 입안을 채우는 무게감이 겹쳐 한 모금이 무겁게 가라앉아 금방 물려요.",
  },
  // A support pair: the burdensome one also keeps the liked one from cloying.
  // The variant names the sensation that burdened.
  "combination_support_sweet_acid@acidity": {
    name: "단맛보다 먼저 오는 새콤함",
    body:
      "이 {kind}{은} 단맛과 새콤함을 함께 지니고 있어서, 새콤함이 단맛을 깎아 물리지 않게 받쳐 주지만 그 몫을 넘어서면 좋아하신 단맛보다 신맛이 먼저 다가와요.",
  },
  "combination_support_sweet_acid@sweetness": {
    name: "새콤함보다 먼저 오는 단맛",
    body:
      "이 {kind}{은} 단맛과 새콤함을 함께 지니고 있어서, 단맛이 신맛의 날을 감싸 주지만 그 몫을 넘어서면 좋아하신 새콤함보다 단맛이 먼저 다가와요.",
  },
  "combination_support_warmth_sweet@warmth": {
    name: "단맛보다 먼저 오는 열감",
    body:
      "이 {kind}{은} 단맛과 알코올의 온기를 함께 지니고 있어서, 온기가 단맛이 밋밋하지 않게 받쳐 주지만 그 몫을 넘어서면 좋아하신 단맛보다 열감이 먼저 다가와요.",
  },
  "combination_support_warmth_sweet@sweetness": {
    name: "온기보다 먼저 오는 단맛",
    body:
      "이 {kind}{은} 단맛과 알코올의 온기를 함께 지니고 있어서, 단맛이 열감을 감싸 주지만 그 몫을 넘어서면 좋아하신 온기보다 단맛이 먼저 다가와요.",
  },
};
