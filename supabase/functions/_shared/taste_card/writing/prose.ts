/**
 * 쓰기: the sentences behind each explanation a card can give.
 *
 * Two tables, one per section: LIKED_PROSE for 왜 잘 맞았을까요 and
 * BURDEN_PROSE for 왜 부담이었을까요. One entry per knowledge row, plus variants
 * the writer picks by the kind of drink or by what else the card knows
 * (`row@variant`). A section is one subtitle plus one flowing text (the
 * user's model, 2026-11-06): the writer joins the names of the chosen
 * entries with 과/와 into the subtitle ("또렷한 과일 향과 깔끔하게 떨어지는
 * 산미") and the bodies into the text, then adds the closing sentence itself.
 *   name  짧은 이름: the core of the paragraph as a noun phrase, 4–12자.
 *   body  이 술의 특징과, 그래서 입에서 어떻게 느껴지는지, 한 문장.
 *         "이 와인은 향이 짙고 또렷한 특징을 가지고 있어서 여러 풍미가 섞여
 *         있어도 체리 향이 묻히지 않고 선명하게 피어올라요."
 * A body that states a fact of the bottle opens "이 {kind}{은} …", so the
 * writer can say it of the kind instead ("이런 {kind}{은} 보통 …") when every
 * level it stands on was copied from the kind's table, or replace the opening
 * with "또한"/"게다가" when the body follows another. Placeholders are filled
 * by writing/sections.ts. Particles follow the word before them: {은} {이} {을}
 * {과} {예요} {이라} {이나} {으로}.
 */
import { effectProse } from "./prose_effects.ts";
import { RELATION_BURDEN, RELATION_LIKED } from "./prose_relations.ts";
import { STRENGTH_BURDEN, STRENGTH_LIKED } from "./prose_tastes.ts";

export type Prose = {
  /** 짧은 이름: 수식어 하나 + 감각 명사, 4–12자, 조사 없이 명사로 끝. */
  name: string;
  /** 이 술의 특징과 그래서 입에서 어떻게 느껴지는지, 한 문장 (해요체). */
  body: string;
};

const ACIDITY_EFFECT =
  "새콤한 맛이 입안을 깨워서 다음 모금을 더 산뜻하게 받아들이게 해 줘요";
const FINISH_EFFECT =
  "맛이 사라진 뒤에도 코 뒤쪽을 타고 올라오는 향이 여운으로 남아요";

const WARMTH: Prose = {
  name: "은은하게 퍼지는 온기",
  body:
    "이 {kind}{은} {strength} 술이라, 알코올의 온기가 향과 맛을 실어서 입안 가득 퍼뜨려 줘요.",
};
const SMOOTH_RICE = (name: string): Prose => ({
  name,
  body:
    "이 {kind}{은} 쌀로 빚어 입안을 조이는 타닌이 거의 없어서, 떫은 맛 없이 혀에 매끄럽게 그대로 닿아요.",
});
const LIGHT_POLISH = (polish: string, name: string): Prose => ({
  name,
  body:
    `이 {kind}{은} ${polish} 잡맛과 무게를 내는 쌀 겉부분이 많이 빠져서, 한결 가볍고 깨끗하게 넘어가요.`,
});
const CLEAN_FINISH_BODY =
  "이 {kind}{은} 마무리가 깔끔하게 떨어지는 술이라, {flavour}{은} 이어져도 입안을 채우던 무게가 빠지면서 끝이 깔끔하게 느껴져요.";

export const LIKED_PROSE: Readonly<Record<string, Prose>> = {
  // 작용 글: what the named aroma does to the senses, in writing/prose_effects.ts.
  ...effectProse("liked"),
  // 강도·지속 of tastes, mouthfeel and the finish, in writing/prose_tastes.ts.
  ...STRENGTH_LIKED,
  // 드러남·가림·구분·조합, in writing/prose_relations.ts.
  ...RELATION_LIKED,
  /* ------------------------------------------------------------ 드러남 */
  exposure_acidity_by_sweetness: {
    name: "깔끔하게 떨어지는 산미",
    body:
      "이 {kind}{은} 단맛이 거의 없어서, 원래 신맛을 감싸 주던 단맛이 빠진 만큼 산미 특유의 산뜻함이 그대로 드러나요.",
  },
  exposure_smooth_by_astringency: {
    name: "떫은 맛 없는 매끄러움",
    body:
      "이 {kind}{은} 떫은 맛이 거의 없어서, 혀와 입안을 조이는 것 없이 매끄러운 촉감이 그대로 전해져요.",
  },

  /* -------------------------------------------------------------- 조합 */
  combination_sweet_acid: {
    name: "단맛과 신맛의 균형",
    body:
      "이 {kind}{은} 단맛과 산미를 함께 갖추고 있어서, 단맛이 신맛의 날카로움을 감싸고 산미가 단맛이 물리지 않게 잡아 줘요.",
  },
  combination_fruit_scent_acidity: {
    name: "향을 살리는 산뜻한 산미",
    body:
      "이 {kind}{은} {aroma}{과} 산뜻한 산미를 함께 지니고 있어서, 향과 새콤함이 같이 밀려오며 서로를 더 산뜻하게 살려 줘요.",
  },
  // Liked aromas of one family.
  combination_aroma_pair: {
    name: "향이 겹쳐 또렷해진 {family_noun}",
    body:
      "이 {kind}에서는 {aromas_short_and} 향이 함께 피어오르는데, 결이 비슷한 향들이 겹치면 하나만 있을 때보다 인상이 훨씬 또렷하고 풍성하게 다가와요.",
  },
  "combination_aroma_pair@smoke": {
    name: "한층 또렷해진 스모키함",
    body:
      "이 {kind}에서는 피트 향과 연기 향이 함께 짙게 깔리는데, 둘 다 연기 계열이라 겹칠수록 스모키함이 한층 분명해져요.",
  },
  // Liked aromas of two families.
  "combination_aroma_pair@mixed": {
    name: "서로 다른 향의 조화",
    body:
      "이 {kind}에서는 {family_groups}{이} 함께 어우러지는데, 결이 다른 향들이 한 잔에 담기면 한 가지 향일 때보다 훨씬 입체적이고 다채롭게 다가와요.",
  },
  // Liked aromas of three or more families.
  "combination_aroma_pair@many": {
    name: "다양한 향의 풍성함",
    body:
      "이 {kind}에서는 {family_groups}{이} 함께 어우러지는데, 성격이 다른 향이 여러 겹으로 쌓이면 한 가지 향일 때보다 훨씬 풍성하게 다가와요.",
  },

  /* -------------------------------------------------------------- 강도 */
  intensity_aroma: {
    name: "또렷한 {aroma_kind}",
    body:
      "이 {kind}{은} 향이 짙고 또렷한 특징을 가지고 있어서, 여러 풍미가 섞여 있어도 {aroma}{이} 묻히지 않고 선명하게 피어올라요.",
  },
  intensity_acidity: {
    name: "입안을 깨우는 산미",
    body: `이 {kind}{은} {level} 술이라, ${ACIDITY_EFFECT}.`,
  },
  // The catalog says little acidity, yet the reader found it 또렷. The number
  // is doubtful and the reader is not: only what was felt, no level.
  "intensity_acidity@little": {
    name: "입안을 깨우는 산미",
    body: `이 {kind}에서는 새콤함이 또렷하게 다가왔는데, ${ACIDITY_EFFECT}.`,
  },
  "intensity_acidity@mid": {
    name: "부담 없이 감도는 산미",
    body:
      "이 {kind}{은} 새콤함이 적당히 감도는 술이라, 앞에 나서지 않으면서도 입안을 산뜻하게 깨워 줘요.",
  },
  intensity_warmth: WARMTH,
  "intensity_warmth@with_aromas": {
    name: "향을 실어 퍼지는 온기",
    body:
      "이 {kind}{은} {strength_and} {liked_aromas}{이} 또렷한 술이라, 알코올의 온기가 {liked_aromas}{을} 실어서 입안 가득 퍼뜨려 줘요.",
  },

  /* -------------------------------------------------------------- 지속 */
  intensity_persistence: {
    name: "길게 남는 은은한 여운",
    body:
      `이 {kind}{은} 삼킨 뒤에도 향이 길게 이어지는 술이라, ${FINISH_EFFECT}.`,
  },
  "intensity_persistence@no_level": {
    name: "길게 남는 은은한 여운",
    body:
      `이 {kind}{은} 삼킨 뒤에도 향이 은은하게 이어지는 술이라, ${FINISH_EFFECT}.`,
  },
  // 삼킨 뒤 코끝으로 향이 올라와서 좋았어요 (2026-11-06).
  persistence_aroma_echo: {
    name: "코끝으로 올라오는 잔향",
    body:
      "이 {kind}{은} 삼킨 뒤에도 향이 코 뒤쪽으로 이어지는 술이라, {liked_aromas}{이} 맛이 사라진 뒤에 코끝으로 다시 올라와 여운으로 남아요.",
  },
  // The same answer when no aroma was named while drinking: what comes up the
  // nose after swallowing reads differently from what the nose met first, so
  // the paragraph is not the finish's length told twice (2026-11-06).
  "persistence_aroma_echo@no_aroma": {
    name: "코끝으로 올라오는 잔향",
    body:
      "이 {kind}{은} 삼킨 뒤 목 뒤를 타고 코로 올라오는 향이 마실 때 코로 맡은 향과 결이 조금 달라서, 같은 술이 삼킨 뒤에 한 번 더 새롭게 느껴져요.",
  },
  persistence_clean: {
    name: "잡미 없이 깔끔한 마무리",
    body: CLEAN_FINISH_BODY,
  },
  // One sensation stayed after swallowing as a burden, yet the mouth cleared.
  "persistence_clean@with_burden": {
    name: "{lingering_burden}{은} 남아도 깔끔한 마무리",
    body:
      "이 {kind}{은} 마무리가 깔끔하게 떨어지는 술이라, {lingering_burden}{은} 남아도 입안을 채우던 무게가 빠지면서 끝이 금방 정리돼요.",
  },

  /* -------------------------------------------- 유래: 술 종류가 설명하는 것 */
  "origin_style@smooth|sake": SMOOTH_RICE("매끄러운 목넘김"),
  "origin_style@smooth|yakju": SMOOTH_RICE("잡미 없이 매끄러운 목넘김"),
  "origin_style@smooth|takju": {
    name: "혀를 감싸는 부드러운 질감",
    body:
      "이 {kind}{은} 맑게 거르지 않아 쌀 성분이 그대로 남아 있어서, 그 고운 입자가 혀를 감싸며 부드러운 질감을 만들어 줘요.",
  },
  "origin_style@light|junmai_ginjo": LIGHT_POLISH(
    "쌀을 40% 넘게 깎아 낸 준마이 긴조라",
    "잡맛 없이 깔끔한 목넘김",
  ),
  "origin_style@light|junmai_daiginjo": LIGHT_POLISH(
    "쌀을 절반 이상 깎아 낸 준마이 다이긴조라",
    "잡맛 없이 깔끔한 목넘김",
  ),
  "origin_style@light|sake": LIGHT_POLISH(
    "쌀을 많이 깎아 낸 사케라",
    "가볍고 깔끔한 목넘김",
  ),

  /* ------------------------- 유래: 종류 표의 줄이 그대로 원리가 되는 것 */
  // No prose written for this sensation and style: the matched line of the
  // style table (까베르네 소비뇽의 떫음) is the reason, and the body names the
  // entry it came from.
  origin_style: {
    name: "{subject_anchor}",
    body: "{style_fact}{은} 본래 {subject_noun}{이} 특징인데, {style_reason}.",
  },
};

/* ================================================================ 부담 */

/**
 * 왜 부담이었을까요: the same shape, but the name says what about the
 * sensation weighed on the reader (떫은 조임, 길게 이어지는 텁텁함) and a wish
 * (@too_weak) says what was missing; never a bottle or a style pick.
 */
export const BURDEN_PROSE: Readonly<Record<string, Prose>> = {
  ...effectProse("burden"),
  ...STRENGTH_BURDEN,
  ...RELATION_BURDEN,
  /* -------------------------------------------------------------- 강도 */
  intensity_sweetness: {
    name: "도드라지게 튀는 단맛",
    body:
      "이 {kind}{은} {level_sweetness} 술이라, 혀에 가장 먼저 닿는 단맛이 다른 맛을 누르고 혼자 앞으로 나서요.",
  },
  // The catalog says little of it, yet it burdened the reader. The number is
  // doubtful and the reader is not, so these say only what was felt: no level,
  // no "you are sensitive".
  "intensity_sweetness@little": {
    name: "도드라지게 튀는 단맛",
    body:
      "이 {kind}에서는 단맛이 또렷하게 다가왔는데, 단맛은 혀에 가장 먼저 닿는 맛이라 조금만 두드러져도 다른 맛보다 앞서 느껴져요.",
  },
  /* ------------------------------------------- 더 있었으면 (너무 약했어요) */
  // The reader wanted more of it. The writer composes the name and the body
  // from the bottle's levels (lackVars): how little the drink has of the taste
  // and how it sits against the other tastes. On a drink that has plenty, no
  // level is said against the reader.
  "intensity_sweetness@too_weak": {
    name: "{lack_name}",
    body: "{lack_body}",
  },
  "intensity_acidity@too_weak": {
    name: "{lack_name}",
    body: "{lack_body}",
  },
  "intensity_bitterness@too_weak": {
    name: "{lack_name}",
    body: "{lack_body}",
  },
  intensity_acidity: {
    name: "혀를 찌르는 신맛",
    body:
      "이 {kind}{은} {level_acidity} 술이라, 혀 옆쪽을 자극해 침이 고이게 하는 신맛이 상쾌함을 넘어 찌르는 자극으로 느껴져요.",
  },
  "intensity_acidity@little": {
    name: "혀를 찌르는 신맛",
    body:
      "이 {kind}에서는 신맛이 날카롭게 다가왔는데, 신맛은 혀 옆쪽을 자극하는 맛이라 조금만 두드러져도 찌르는 자극으로 먼저 느껴져요.",
  },
  intensity_heavy: {
    name: "입안을 누르는 무게감",
    body:
      "이 {kind}{은} {level} 술이라, 녹아 있는 성분이 혀를 두껍게 덮어서 가볍게 즐길 틈 없이 묵직하게 느껴져요.",
  },
  intensity_warmth: {
    name: "확 치고 올라오는 열감",
    body:
      "이 {kind}{은} {strength} 술이라, 알코올의 화끈한 열감이 향과 맛보다 먼저 목을 타고 치고 올라와요.",
  },
  intensity_bubbles: {
    name: "따끔하게 쏘는 탄산",
    body:
      "이 {kind}{은} {level} 술이라, 기포가 혀를 톡 쏘는 따끔한 자극이 맛보다 먼저 다가와요.",
  },
  // Every champagne is strongly sparkling, so no line can be drawn inside it;
  // the paragraph says so of champagne as a whole.
  "intensity_bubbles@champagne_sparkling": {
    name: "샴페인의 센 탄산",
    body:
      "샴페인은 병 안에서 발효를 한 번 더 해서 탄산을 가두는 술이라, 어느 샴페인이든 탄산이 세게 쏘아요.",
  },

  /* -------------------------------------------------------------- 가림 */
  "masking_drying_smooth@wine": {
    name: "떫은 조임",
    body:
      "이 {kind}{은} 질감은 매끄럽지만 타닌이 많아서, 떫은 조임이 혀와 입안을 붙들며 본래의 매끄러운 촉감을 가려 버려요.",
  },
  "masking_drying_fruit@wine": {
    name: "과일 향을 덮은 떫은맛",
    body:
      "이 {kind}{은} {given_aroma}{을} 지녔지만 타닌이 많아서, 떫은 조임이 입안을 붙들며 과일 향이 퍼지는 걸 가로막아요.",
  },

  /* -------------------------------------------------------------- 구분 */
  // Sweet-smelling aromas read as sweetness on the tongue.
  distinction_sweetness_sweet_scent: {
    name: "생각보다 달게 느껴진 단맛",
    body:
      "이 {kind}{은} {given_aromas}{을} 지니고 있어서, 코로 들어온 달콤한 향이 혀의 단맛과 하나로 묶여 실제보다 훨씬 달게 느껴져요.",
  },
  distinction_heavy_vs_smooth: {
    name: "입안 가득 채우는 걸쭉함",
    body:
      "이 {kind}{은} 결은 고와도 입안을 가득 채우는 술이라, 혀에 닿는 질감은 부드러워도 채우는 양이 많아 무겁게 느껴져요.",
  },

  /* -------------------------------------------------------------- 지속 */
  // 삼킨 뒤 잡미나 거슬리는 냄새가 올라왔어요 (2026-11-06), after an aroma
  // that bothered the reader while drinking, or on its own (@alone).
  persistence_off_flavor: {
    name: "삼킨 뒤 올라오는 잡내",
    body:
      "이 {kind}{은} 삼킨 뒤에 {burden_aromas}{이} 코 뒤쪽으로 다시 올라오는 술이라, 마실 때 거슬렸던 향이 맛이 사라진 뒤에 더 도드라져요.",
  },
  "persistence_off_flavor@alone": {
    name: "삼킨 뒤 올라오는 잡내",
    body:
      "이 {kind}{은} 삼킨 뒤에 잡내가 코 뒤쪽으로 올라오는 술이라, 마실 땐 다른 향에 가려졌던 발효·숙성의 잡내가 맛이 사라진 뒤에 더 도드라져요.",
  },
  persistence_heavy: {
    name: "삼킨 뒤에도 남는 무게",
    body:
      "이 {kind}{은} 걸쭉한 질감이 삼킨 뒤까지 남는 술이라, 탄산이나 새콤함이 걷어 주지 않으면 입안에 얇은 막처럼 무게가 오래 머물러요.",
  },

  /* -------------------------------------------- 유래: 술 종류가 설명하는 것 */
  "origin_style@heavy|nigori": {
    name: "걸쭉하게 남는 묵직함",
    body:
      "이 {kind}{은} 쌀 앙금을 일부러 거르지 않고 남겨 둔 니고리 사케라, 그 앙금이 질감을 걸쭉하게 만들어 입안에 무겁게 남아요.",
  },
  /* ------------------------- 유래: 종류 표의 줄이 그대로 원리가 되는 것 */
  origin_style: {
    name: "{subject_anchor}",
    body: "{style_fact}{은} 본래 {subject_noun}{이} 특징인데, {style_reason}.",
  },
};
