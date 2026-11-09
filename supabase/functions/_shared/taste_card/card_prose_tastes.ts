/**
 * 쓰기: the sentences for a taste, mouthfeel or finish answer explained by
 * its strength (강도) or by what stayed after swallowing (지속).
 *
 * Same shape as card_prose.ts (the user's model, 2026-11-06 night): name 짧은
 * 이름 (a noun phrase the writer joins with 과/와 into the section subtitle),
 * body 이 술의 특징과 그래서 입에서 어떻게 느껴지는지 (한 문장; the writer
 * strings the bodies of a section together and adds the closing sentence).
 * Variants: `row@mid` for a middle level, `row@little` when the catalog says
 * little of what the reader found strong (then only what was felt, no
 * number), `row@no_level` when the catalog has no number, `row@gentle` when
 * the reader said 은은해서, and for the finish `row@liked_after_burden` and
 * `row@burden_alone`.
 */
import type { Prose } from "./card_prose.ts";

/* ================================================================ 강도 */

const SWEET_LIKED: Prose = {
  name: "부드럽게 감싸는 단맛",
  body:
    "이 {kind}{은} {level} 술이라서, 혀에 가장 먼저 닿는 단맛이 첫 모금의 인상을 부드럽고 포근하게 감싸 줘요.",
};
const BITTER_LIKED: Prose = {
  name: "단맛을 눌러 주는 쌉쌀함",
  body:
    "이 {kind}에서는 쌉쌀함이 또렷하게 다가와서, 혀 뒤쪽에서 늦고 길게 느껴지는 그 쓴맛이 단맛을 눌러 뒷맛을 드라이하게 정리해 줘요.",
};
const LIGHT_LIKED: Prose = {
  name: "술술 넘어가는 가벼움",
  body:
    "이 {kind}{은} {level} 술이라서, 녹아 있는 성분이 적은 만큼 혀를 얇게 스치고 지나가며 입안에 머무는 느낌 없이 술술 넘어가요.",
};
const LIGHT_BURDEN: Prose = {
  name: "물처럼 밋밋한 가벼움",
  body:
    "이 {kind}{은} 가볍게 넘어가는 술이라서, 밀도가 낮은 만큼 혀를 얇게 스치고 지나가 입안에 남는 것 없이 맛이 비어 버려요.",
};
const HEAVY_LIKED: Prose = {
  name: "든든하게 채우는 무게감",
  body:
    "이 {kind}{은} {level} 술이라서, 녹아 있는 성분이 많은 만큼 술이 혀를 두껍게 덮으며 한 모금에도 입안이 든든하게 차요.",
};
const HEAVY_BURDEN_NO_LEVEL: Prose = {
  name: "무겁게 누르는 무게감",
  body:
    "이 {kind}에서는 묵직한 무게감이 또렷하게 다가와서, 술이 혀를 두껍게 덮으며 가볍게 즐길 틈을 주지 않아요.",
};
const DRYING_LIKED: Prose = {
  name: "기분 좋게 조이는 떫은맛",
  body:
    "이 {kind}{은} {level} 술이라서, 침과 엉겨 붙은 떫은 성분이 입안을 조이며 술에 씹히는 듯한 짜임새를 만들어 줘요.",
};
const DRYING_BURDEN: Prose = {
  name: "맛보다 먼저 조이는 떫은맛",
  body:
    "이 {kind}{은} {level} 술이라서, 침과 엉겨 붙은 떫은 성분이 입안을 조이고 마르게 하며 맛보다 먼저 느껴져요.",
};
const SMOOTH_LIKED: Prose = {
  name: "걸리는 것 없는 매끄러움",
  body:
    "이 {kind}{은} {level} 술이라서, 입안을 조이는 떫은 맛 없이 본래의 매끄러운 촉감이 혀에 그대로 닿아요.",
};
const SMOOTH_BURDEN: Prose = {
  name: "특징 없이 밋밋한 매끄러움",
  body:
    "이 {kind}{은} 매끄럽게 넘어가는 술이라서, 조이거나 톡 쏘는 자극이 없는 만큼 입안에 걸리는 데가 없어 밋밋하게 느껴져요.",
};
const BUBBLES_LIKED: Prose = {
  name: "톡 쏘는 청량한 탄산",
  body:
    "이 {kind}{은} {level} 술이라서, 기포가 혀를 톡톡 두드리는 따끔함이 입안을 깨워 맛을 한결 산뜻하게 만들어 줘요.",
};
const TOO_SHORT: Prose = {
  name: "너무 짧은 여운",
  body:
    "이 {kind}에서는 삼킨 뒤 코 뒤쪽으로 올라오는 향이 가벼워서, 맛이 사라지는 순간 여운도 함께 뚝 끊겨요.",
};

export const STRENGTH_LIKED: Readonly<Record<string, Prose>> = {
  /* ------------------------------------------------------------ 단맛 */
  intensity_sweetness: SWEET_LIKED,
  "intensity_sweetness@mid": {
    name: "적당히 감도는 단맛",
    body:
      "이 {kind}{은} 단맛이 적당히 감도는 술이라서, 단맛이 앞에 나서지 않고 첫 모금의 인상만 부드럽게 감싸 줘요.",
  },
  // The catalog says little sweetness, yet the reader liked it: only what was felt.
  "intensity_sweetness@little": {
    ...SWEET_LIKED,
    body:
      "이 {kind}에서는 단맛이 또렷하게 다가와서, 혀에 가장 먼저 닿는 그 단맛이 첫 모금의 인상을 부드럽고 포근하게 감싸 줘요.",
  },
  "intensity_sweetness@gentle": {
    name: "은은하게 감도는 단맛",
    body:
      "이 {kind}에서는 단맛이 은은하게 감돌아서, 앞에 나서지 않고 혀를 살짝만 감싸 주니 물리지 않고 편안하게 느껴져요.",
  },
  /* ------------------------------------------------------------ 신맛 */
  "intensity_acidity@gentle": {
    name: "은은하게 깨워 주는 산미",
    body:
      "이 {kind}에서는 새콤함이 은은하게 감돌아서, 입안을 살짝만 깨워 주고 다음 모금을 산뜻하게 받아들이게 해 줘요.",
  },
  /* ------------------------------------------------------------ 쓴맛 */
  "intensity_bitterness@no_level": BITTER_LIKED,
  "intensity_bitterness@gentle": {
    name: "은은하게 받쳐 주는 쌉쌀함",
    body:
      "이 {kind}에서는 쌉쌀함이 은은하게 감돌아서, 앞에 나서지 않고 뒤에서 맛에 깊이만 더해 줘요.",
  },
  /* ---------------------------------------------------------- 가벼움 */
  intensity_light: LIGHT_LIKED,
  "intensity_light@no_level": {
    ...LIGHT_LIKED,
    body:
      "이 {kind}에서는 가볍게 넘어가는 느낌이 또렷해서, 술이 혀를 얇게 스치고 지나가며 입안에 머무는 느낌 없이 술술 넘어가요.",
  },
  /* ---------------------------------------------------------- 무게감 */
  intensity_heavy: HEAVY_LIKED,
  "intensity_heavy@mid": {
    name: "버겁지 않게 채워 주는 무게감",
    body:
      "이 {kind}{은} 무게감이 적당히 있는 술이라서, 버겁지 않을 만큼만 혀를 덮으며 입안을 편안하게 채워 줘요.",
  },
  "intensity_heavy@no_level": {
    ...HEAVY_LIKED,
    body:
      "이 {kind}에서는 입안을 채우는 무게감이 또렷해서, 술이 혀를 두껍게 덮으며 한 모금에도 입안이 든든하게 차요.",
  },
  /* ------------------------------------------------------------ 떫음 */
  intensity_drying: DRYING_LIKED,
  "intensity_drying@little": {
    ...DRYING_LIKED,
    body:
      "이 {kind}에서는 입안을 조이는 떫은 맛이 또렷하게 다가와서, 침과 엉겨 붙은 그 조임이 술에 씹히는 듯한 짜임새를 만들어 줘요.",
  },
  /* ---------------------------------------------------------- 부드러움 */
  intensity_smooth: SMOOTH_LIKED,
  "intensity_smooth@no_level": {
    ...SMOOTH_LIKED,
    body:
      "이 {kind}에서는 혀에 닿는 매끄러움이 또렷해서, 입안을 조이는 떫은 맛 없이 그 매끄러운 촉감이 혀에 그대로 전해져요.",
  },
  /* ------------------------------------------------------------ 탄산 */
  intensity_bubbles: BUBBLES_LIKED,
  "intensity_bubbles@mid": {
    name: "따갑지 않게 깨워 주는 탄산",
    body:
      "이 {kind}{은} 탄산이 적당히 있는 술이라서, 따갑지 않을 만큼만 톡톡 올라오는 기포가 입안을 깨워 줘요.",
  },
  "intensity_bubbles@little": {
    ...BUBBLES_LIKED,
    body:
      "이 {kind}에서는 탄산이 톡톡 또렷하게 느껴져서, 기포가 혀를 두드리는 따끔함이 입안을 깨워 맛을 한결 산뜻하게 만들어 줘요.",
  },

  /* ================================================================ 지속 */
  // 2026-11-06: only 텁텁함 is still asked as a lingering mouthfeel.
  persistence_heavy: {
    name: "삼킨 뒤까지 남는 묵직한 여운",
    body:
      "이 {kind}{은} 묵직한 질감이 삼킨 뒤까지 이어지는 술이라서, 진한 술이 입안에 얇은 막을 남긴 것처럼 한 모금의 무게가 여운으로 이어져요.",
  },
};

export const STRENGTH_BURDEN: Readonly<Record<string, Prose>> = {
  /* ------------------------------------------------------------ 쓴맛 */
  "intensity_bitterness@no_level": {
    name: "또렷하게 다가오는 쓴맛",
    body:
      "이 {kind}에서는 쓴맛이 또렷하게 다가와서, 혀 뒤쪽에서 늦게 느껴지고 가장 오래 남는 그 쓴맛이 다른 맛이 끝난 뒤까지 혼자 남아요.",
  },
  /* ---------------------------------------------------------- 가벼움 */
  intensity_light: LIGHT_BURDEN,
  "intensity_light@no_level": {
    ...LIGHT_BURDEN,
    body:
      "이 {kind}에서는 가벼운 느낌이 앞서서, 술이 혀를 얇게 스치고 지나가 입안에 남는 것 없이 맛이 비어 버려요.",
  },
  /* ---------------------------------------------------------- 무게감 */
  "intensity_heavy@no_level": HEAVY_BURDEN_NO_LEVEL,
  /* ------------------------------------------------------------ 떫음 */
  intensity_drying: DRYING_BURDEN,
  // The catalog says little astringency, yet it burdened the reader: only what was felt.
  "intensity_drying@little": {
    ...DRYING_BURDEN,
    body:
      "이 {kind}에서는 입안을 조이는 떫은 느낌이 또렷하게 다가와서, 침과 엉겨 붙은 그 조임이 입안을 마르게 하며 맛보다 먼저 느껴져요.",
  },
  /* ---------------------------------------------------------- 부드러움 */
  intensity_smooth: SMOOTH_BURDEN,
  "intensity_smooth@no_level": {
    ...SMOOTH_BURDEN,
    body:
      "이 {kind}에서는 매끄러운 촉감이 앞서서, 조이거나 톡 쏘는 자극 없이 입안에 걸리는 데가 없어 밋밋하게 느껴져요.",
  },
  /* ------------------------------------------------------------ 여운 */
  intensity_persistence: TOO_SHORT,
  "intensity_persistence@little": {
    ...TOO_SHORT,
    body:
      "이 {kind}{은} 여운이 짧게 끊어지는 술이라서, 삼킨 뒤 코 뒤쪽으로 올라오는 향이 적은 만큼 맛이 사라지는 순간 여운도 함께 끊겨요.",
  },
  "intensity_persistence@no_level": TOO_SHORT,
};
