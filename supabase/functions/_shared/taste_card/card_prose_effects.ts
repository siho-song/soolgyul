/**
 * 작용 글: what the aroma the reader named does in the nose and mouth.
 *
 * "이 향 자체가 좋았어요" carries no fact of the bottle to explain, so the
 * paragraph explains the aroma itself: not where it comes from, but what it
 * does to the senses. Every entry is a short name plus one body sentence:
 * the name is a noun phrase that names the aroma with the one thing it did
 * ("포근하게 감싸는 {aroma}"), and the body says what kind of smell {aroma}
 * is and what that does in the nose and mouth (cause → action → result).
 * The writer joins the bodies of a section into one text and adds its own
 * closing sentence, so there is no conclusion here.
 *
 * One body pair per effect row, served to the five frames a finding can
 * carry: liked, gentle (은은해서 좋았어요), burden, excessive (너무 강해서),
 * too_weak (더 또렷했으면). The burden and excessive frames share a body that
 * says what goes wrong when the aroma leads; the other three share the plain
 * body. The names differ per frame.
 */
import type { Prose } from "./card_prose.ts";

type EffectText = {
  /** liked / 은은해서 / 더 또렷했으면: what kind of smell {aroma} is and what it does in the nose and mouth, one sentence. */
  body: string;
  /** 부담 / 너무 강해서: the same aroma when it comes forward too much, one sentence. */
  body_burden: string;
};

/** The texts, in the order of EFFECT_ROWS. */
const TEXTS: Readonly<Record<string, EffectText>> = {
  effect_ripe_fruit: {
    body:
      "{aroma}{은} 잘 익은 과일을 떠올리게 하는 향이라서, 코로만 맡아도 혀가 단맛을 기다려 달지 않은 술도 한 모금 전부터 포근하게 느껴져요.",
    body_burden:
      "{aroma}{은} 코로만 맡아도 혀가 단맛을 기다리게 하는 향이라서, 뒤를 받아 줄 맛 없이 먼저 앞에 오면 단 음식처럼 금방 물리게 돼요.",
  },
  effect_sour_fruit: {
    body:
      "{aroma}{은} 새콤달콤한 과일을 떠올리게 하는 향이라서, 맡는 순간 그 새콤함까지 떠올라 입안이 깨어나고 한 모금이 다음 모금을 부르듯 경쾌하게 느껴져요.",
    body_burden:
      "{aroma}{은} 맡는 순간 그 과일의 새콤함까지 함께 떠올리게 하는 향이라서, 뒤를 받아 줄 단맛 없이 먼저 앞에 오면 시고 날카롭게만 다가와요.",
  },
  effect_fresh_fruit: {
    body:
      "{aroma}{은} 갓 깎은 과일처럼 가볍고 빨리 퍼지는 향이라서, 잔을 들자마자 코에 닿아 마시기 전부터 시원하고 산뜻하게 느껴져요.",
    body_burden:
      "{aroma}{은} 가볍고 빨리 퍼지는 향이라서, 뒤를 채워 줄 맛 없이 먼저 앞에 오면 겉만 시원하고 속은 허전하게 느껴져요.",
  },
  effect_floral: {
    body:
      "{aroma}{은} 가볍게 피어오르는 꽃 향이라서, 맛보다 먼저 코에 닿아 첫인상을 정하는 만큼 술이 실제보다 화사하고 섬세하게 느껴져요.",
    body_burden:
      "{aroma}{은} 맛보다 먼저 코에 닿아 첫인상을 정하는 향이라서, 물러나지 않고 끝까지 앞에 있으면 술맛보다 향이 향수처럼 겉돌아요.",
  },
  effect_smoke: {
    body:
      "{aroma}{은} 적은 양에도 코가 먼저 알아채는 연기 냄새라서, 다른 향보다 앞서 들어와 첫 향부터 술의 분위기를 정해 줘요.",
    body_burden:
      "{aroma}{은} 적은 양에도 코가 먼저 알아채는 연기 냄새라서, 세게 앞서면 뒤에 올 향과 맛의 자리까지 벽처럼 다 덮어 버려요.",
  },
  effect_sweet_scent: {
    body:
      "{aroma}{은} 혀가 단맛을 느낄 때마다 코로 같이 들어오던 냄새라서, 코로만 맡아도 술이 실제 단맛보다 부드럽고 달큰하게 느껴져요.",
    body_burden:
      "{aroma}{은} 코로만 맡아도 달게 느껴지는 냄새라서, 맛이 받아 주기도 전에 먼저 진하게 앞에 오면 마시기도 전에 물리게 돼요.",
  },
  effect_grain_nut: {
    body:
      "{aroma}{은} 갓 구운 빵이나 갓 지은 밥처럼 매일 먹는 음식에서 맡던 냄새라서, 코가 편하게 받아들여 술이 낯설지 않고 든든하게 느껴져요.",
    body_burden:
      "{aroma}{은} 바탕에 깔려 다른 향을 받쳐 주는 냄새라서, 그 자리를 벗어나 혼자 앞에 나오면 술이 무겁고 텁텁하게만 느껴져요.",
  },
  effect_roast: {
    body:
      "{aroma}{은} 커피처럼 쌉쌀한 맛과 늘 함께 오던 볶은 냄새라서, 혀가 쌉쌀함을 먼저 준비해 술이 달기보다 진하고 묵직하게 느껴져요.",
    body_burden:
      "{aroma}{은} 코로 맡으면 혀가 쌉쌀함을 먼저 준비하게 하는 볶은 냄새라서, 뒤를 받아 줄 단맛 없이 먼저 앞에 오면 탄 듯한 쓴맛만 도드라져요.",
  },
  effect_wood: {
    body:
      "{aroma}{은} 마른 나무처럼 천천히 올라와 오래 머무는 향이라서, 화사한 향들 뒤에서 바닥을 받쳐 줘 술이 흩어지지 않고 차분하게 느껴져요.",
    body_burden:
      "{aroma}{은} 천천히 올라와 오래 머무는 향이라서, 화사한 향 없이 먼저 앞에 오면 다른 향을 덮어 입안이 답답하고 텁텁하게 느껴져요.",
  },
  effect_green: {
    body:
      "{aroma}{은} 갓 뜯은 풀잎처럼 코를 상쾌하게 깨우는 향이라서, 다른 향 사이에서 선을 긋고 입안까지 서늘하게 해 술이 깔끔하고 또렷하게 느껴져요.",
    body_burden:
      "{aroma}{은} 다른 향 사이에서 또렷하게 선을 긋는 향이라서, 물러나지 않고 혼자 앞에 나오면 덜 익은 풀처럼 날카로운 풋내로 거슬려요.",
  },
  effect_vegetal: {
    body:
      "{aroma}{은} 피망이나 오이처럼 날것을 떠올리게 하는 냄새라서, 혀가 단맛보다 서늘한 쪽을 준비해 술이 덜 달고 더 서늘하게 느껴져요.",
    body_burden:
      "{aroma}{은} 날것을 떠올리게 하는 풋풋한 채소 냄새라서, 물러나지 않고 날것 그대로 앞에 나오면 덜 익은 것을 씹는 듯 거친 풋내로 거슬려요.",
  },
  effect_spice: {
    body:
      "{aroma}{은} 계피나 후추처럼 혀의 얼얼한 자극과 함께 오던 냄새라서, 코로만 맡아도 입안이 그 자극을 떠올려 술이 도수보다 더 따뜻하게 느껴져요.",
    body_burden:
      "{aroma}{은} 코로만 맡아도 입안이 얼얼한 자극을 미리 떠올리게 하는 냄새라서, 감싸 줄 단맛 없이 먼저 앞에 오면 맵고 거친 자극만 남아요.",
  },
  effect_mineral: {
    body:
      "{aroma}{은} 젖은 돌이나 바닷바람처럼 서늘하고 짭짤하게 남는 느낌이라서, 뒤에서 맛의 윤곽을 잡아 줘 술이 달기보다 깨끗하고 단단하게 느껴져요.",
    body_burden:
      "{aroma}{은} 코와 입안에 서늘하고 짭짤하게 남는 느낌이라서, 뒤에 머물지 않고 앞에 나오면 입안이 메말라 서늘하다 못해 차갑고 딱딱하게 느껴져요.",
  },
  effect_earth: {
    body:
      "{aroma}{은} 비 온 뒤 숲 바닥처럼 낮고 축축하게 깔리는 냄새라서, 아주 적은 양으로도 분위기를 가라앉혀 술이 밝기보다 깊게 느껴져요.",
    body_burden:
      "{aroma}{은} 아주 적은 양으로도 분위기를 가라앉히는 냄새라서, 밝은 향 없이 먼저 앞에 오면 술이 눅눅하고 퀴퀴하게 가라앉아요.",
  },
  effect_dairy: {
    body:
      "{aroma}{은} 버터와 크림처럼 매끄러운 촉감과 함께 오던 냄새라서, 코로만 맡아도 술이 날카로운 데 없이 부드럽고 둥글게 느껴져요.",
    body_burden:
      "{aroma}{은} 기름진 촉감을 떠올리게 하는 냄새라서, 모서리만 감싸는 데서 그치지 않고 입안을 다 덮어 버리면 무겁고 느끼하게 느껴져요.",
  },
  effect_ferment: {
    body:
      "{aroma}{은} 빵 반죽이나 갓 거른 막걸리처럼 살짝 시큼하고 구수한 냄새라서, 술이 살아 있다는 느낌을 줘 깔끔하기보다 생생하고 풍성하게 느껴져요.",
    body_burden:
      "{aroma}{은} 살짝 시큼하고 구수한 발효 냄새라서, 받아 줄 향과 맛 없이 혼자 앞에 나오면 오래 묵은 반죽처럼 시큼하고 쿰쿰하게 거슬려요.",
  },
  effect_savory: {
    body:
      "{aroma}{은} 간장이나 국물처럼 감칠맛 나는 음식에서 맡던 냄새라서, 입안이 깊은 맛을 기다리게 해 술이 가볍기보다 든든하고 깊게 느껴져요.",
    body_burden:
      "{aroma}{은} 입안이 깊은 맛을 기다리게 하는 냄새라서, 채워 줄 맛 없이 먼저 앞에 오면 술이 아니라 무겁고 짭짤한 음식 냄새처럼 느껴져요.",
  },
  effect_aged: {
    body:
      "{aroma}{은} 담뱃잎이나 가죽처럼 마르고 낮게 깔리는 냄새라서, 화사한 향이 지나간 뒤에 남아 술이 깊고 오래된 느낌으로 다가와요.",
    body_burden:
      "{aroma}{은} 마르고 낮게 깔리는 냄새라서, 화사한 향 없이 먼저 앞에 오면 술이 퀴퀴하고 무겁게 가라앉아 답답하게 느껴져요.",
  },
};

/**
 * The short names of the single-aroma rows, one per frame: liked, 은은해서
 * 좋았어요, 부담. Each names the aroma with the one thing it did in that row's
 * body, so a section subtitle can join them with 과/와 ("포근하게 감싸는 체리
 * 향과 깔끔하게 떨어지는 산미").
 */
const EFFECT_NAMES: Readonly<
  Record<string, { liked: string; gentle: string; burden: string }>
> = {
  effect_ripe_fruit: {
    liked: "포근하게 감싸는 {aroma}",
    gentle: "은은하게 감도는 {aroma}",
    burden: "금방 물리게 앞서는 {aroma}",
  },
  effect_sour_fruit: {
    liked: "새콤하게 입안을 깨우는 {aroma}",
    gentle: "은은하게 맴도는 {aroma}",
    burden: "시고 날카롭게만 앞서는 {aroma}",
  },
  effect_fresh_fruit: {
    liked: "산뜻하게 코를 여는 {aroma}",
    gentle: "은은하게 스치는 {aroma}",
    burden: "겉만 시원한 {aroma}",
  },
  effect_floral: {
    liked: "화사하게 피어오르는 {aroma}",
    gentle: "은은하게 번지는 {aroma}",
    burden: "향수처럼 겉도는 {aroma}",
  },
  effect_smoke: {
    liked: "첫 향부터 분위기를 잡는 {aroma}",
    gentle: "은은하게 배어 있는 {aroma}",
    burden: "벽처럼 다 덮는 {aroma}",
  },
  effect_sweet_scent: {
    liked: "달큰하게 감도는 {aroma}",
    gentle: "은은하게 달큰한 {aroma}",
    burden: "마시기 전부터 물리는 {aroma}",
  },
  effect_grain_nut: {
    liked: "편안하고 든든한 {aroma}",
    gentle: "은은하게 깔리는 {aroma}",
    burden: "무겁고 텁텁한 {aroma}",
  },
  effect_roast: {
    liked: "쌉쌀하고 묵직한 {aroma}",
    gentle: "은은하게 밴 {aroma}",
    burden: "탄 듯 쓰게만 남는 {aroma}",
  },
  effect_wood: {
    liked: "차분하게 받쳐 주는 {aroma}",
    gentle: "은은하게 가라앉는 {aroma}",
    burden: "다른 향을 덮어 답답한 {aroma}",
  },
  effect_green: {
    liked: "상쾌하게 선을 긋는 {aroma}",
    gentle: "은은하게 서늘한 {aroma}",
    burden: "날카로운 풋내의 {aroma}",
  },
  effect_vegetal: {
    liked: "서늘하고 담백한 {aroma}",
    gentle: "은은하게 풋풋한 {aroma}",
    burden: "거친 풋내를 남기는 {aroma}",
  },
  effect_spice: {
    liked: "입안까지 데워 주는 {aroma}",
    gentle: "은은하게 알싸한 {aroma}",
    burden: "맵고 거친 자극만 남는 {aroma}",
  },
  effect_mineral: {
    liked: "맛의 윤곽을 잡아 주는 {aroma}",
    gentle: "은은하게 깔끔한 {aroma}",
    burden: "차갑고 딱딱한 {aroma}",
  },
  effect_earth: {
    liked: "차분하게 깊이를 더하는 {aroma}",
    gentle: "은은하게 깊이 밴 {aroma}",
    burden: "눅눅하고 퀴퀴한 {aroma}",
  },
  effect_dairy: {
    liked: "부드럽고 둥글게 감싸는 {aroma}",
    gentle: "은은하게 부드러운 {aroma}",
    burden: "무겁고 느끼한 {aroma}",
  },
  effect_ferment: {
    liked: "생생하게 살아 있는 {aroma}",
    gentle: "은은하게 생생한 {aroma}",
    burden: "시큼하고 쿰쿰한 {aroma}",
  },
  effect_savory: {
    liked: "든든하게 속을 채우는 {aroma}",
    gentle: "은은하게 든든한 {aroma}",
    burden: "음식 냄새처럼 무거운 {aroma}",
  },
  effect_aged: {
    liked: "깊고 그윽하게 남는 {aroma}",
    gentle: "은은하게 낮게 깔리는 {aroma}",
    burden: "무겁게 가라앉는 {aroma}",
  },
};

/** 너무 강해서: the reader's own words, the same for every row. */
const EXCESSIVE_NAME = "너무 강하게 치고 나온 {aroma}";
/** 더 또렷했으면: what was missing was the aroma's clarity, the same for every row. */
const TOO_WEAK_NAME = "흐릿해서 아쉬운 {aroma}";

/**
 * 더 또렷했으면: the plain body with its effect made conditional (…이라서,
 * 또렷하게 올라오면 …) and the wish after it. Every body has one "라서, ".
 */
function wishBody(body: string): string {
  return `${
    body.replace("라서, ", "라서, 또렷하게 올라오면 ")
  } 이번에는 그 향이 흐릿해서 그 몫을 다하지 못했어요.`;
}

/** The prose entries of every effect row for one side of the card. */
export function effectProse(side: "liked" | "burden"): Record<string, Prose> {
  const out: Record<string, Prose> = {};
  for (const [row, t] of Object.entries(TEXTS)) {
    const names = EFFECT_NAMES[row];
    if (side === "liked") {
      out[row] = { name: names.liked, body: t.body };
      // 은은해서 좋았어요: the same effect, felt without excess.
      out[`${row}@gentle`] = { name: names.gentle, body: t.body };
      continue;
    }
    out[row] = { name: names.burden, body: t.body_burden };
    // 너무 강해서: the reader's own words in the name; the effect explains
    // the excess without a strength number the card does not trust.
    out[`${row}@excessive`] = { name: EXCESSIVE_NAME, body: t.body_burden };
    // 더 또렷했으면: what the aroma gives when it comes through, and that this
    // time it stayed faint; the writer runs the last sentence into its closing.
    out[`${row}@too_weak`] = { name: TOO_WEAK_NAME, body: wishBody(t.body) };
  }
  return out;
}
