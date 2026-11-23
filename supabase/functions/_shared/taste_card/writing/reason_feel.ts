/** How a sense is felt at each side, liked or minded: the half of a reason that says what the taste does in the mouth. */
import { type GaugeAxis } from "../../record_reading/facts/facts.ts";
import type { Section } from "../selection/selection.ts";
import { AXIS, mindedName, type Side, sideOf } from "./reason_words.ts";

/**
 * How one side of a sense is felt, liked or minded: the subtitle's name, how
 * it came across, and what it did in the mouth. The sentences are the ones
 * the card has always said (writing/prose_tastes.ts and prose.ts), in the
 * past tense: the reader reads them after the glass.
 */
export type Feel = {
  name: string;
  /** How it came across, when no fact of the bottle stands behind the answer: 단맛이 또렷하게 다가와서. */
  across: string;
  /** What it did in the mouth, with how the sense does it. */
  long: string;
  /** The same in few words, after a ground that is already long. */
  short: string;
};

export type FeelKey = `${Side}:${Section}`;

export const FEEL: Readonly<Record<GaugeAxis, Partial<Record<FeelKey, Feel>>>> =
  {
    sweetness: {
      "high:liked": {
        name: "포근하게 감도는 단맛",
        across: "단맛이 또렷하게 다가와서",
        long:
          "혀에 가장 먼저 닿는 그 단맛이 첫 모금의 인상을 부드럽고 포근하게 감싸 줘요",
        short: "첫 모금의 인상을 부드럽고 포근하게 감싸 줘요",
      },
      "high:burden": {
        name: "혼자 앞서 도드라진 단맛",
        across: "단맛이 또렷하게 다가와서",
        long: "혀에 가장 먼저 닿는 단맛이 다른 맛을 누르고 혼자 앞으로 나서요",
        short: "단맛이 다른 맛을 누르고 혼자 앞으로 나서요",
      },
      "mid:liked": {
        name: "적당히 감도는 단맛",
        across: "단맛이 적당히 감돌아서",
        long: "앞에 나서지 않고 첫 모금의 인상만 부드럽게 감싸 줘요",
        short: "첫 모금의 인상만 부드럽게 감싸 줘요",
      },
      "low:liked": {
        name: "은은하게 감도는 단맛",
        across: "단맛이 은은하게 감돌아서",
        long:
          "앞에 나서지 않고 혀를 살짝만 감싸 주니 물리지 않고 편안하게 느껴져요",
        short: "물리지 않고 편안하게 느껴져요",
      },
      "none:liked": {
        name: "단맛 없는 깔끔함",
        across: "단맛이 거의 느껴지지 않아서",
        long:
          "혀에 남는 단맛 없이 맛이 깔끔하게 떨어져 다음 모금도 물리지 않아요",
        short: "맛이 깔끔하게 떨어져 다음 모금도 물리지 않아요",
      },
      "low:burden": {
        name: "조금 옅었던 단맛",
        across: "단맛이 옅게만 느껴져서",
        long: "맛의 모서리를 감싸 줄 것이 없어 술이 메마르고 심심하게 느껴져요",
        short: "술이 메마르고 심심하게 느껴져요",
      },
    },
    acidity: {
      "high:liked": {
        name: "산뜻하게 살아난 산미",
        across: "산미가 또렷하게 다가와서",
        long: "산미가 입안을 깨워 다음 모금을 더 산뜻하게 받아들이게 해 줘요",
        short: "입안을 깨워 다음 모금을 더 산뜻하게 받아들이게 해 줘요",
      },
      "high:burden": {
        name: "날카롭게 찌르는 산미",
        across: "산미가 날카롭게 다가와서",
        long:
          "혀 옆쪽을 자극해 침이 고이게 하며 상쾌함을 넘어 찌르는 자극으로 느껴져요",
        short: "산미가 상쾌함을 넘어 찌르는 자극으로 느껴져요",
      },
      "mid:liked": {
        name: "부담 없이 감도는 산미",
        across: "산미가 적당히 감돌아서",
        long: "앞에 나서지 않으면서도 입안을 산뜻하게 깨워 줘요",
        short: "앞에 나서지 않으면서도 입안을 산뜻하게 깨워 줘요",
      },
      "low:liked": {
        name: "은은하게 감도는 산미",
        across: "산미가 은은하게 감돌아서",
        long: "입안을 살짝만 깨워 주고 다음 모금을 산뜻하게 받아들이게 해 줘요",
        short: "자극 없이 입안을 살짝만 깨워 줘요",
      },
      "low:burden": {
        name: "조금 심심했던 산미",
        across: "산미가 옅게만 느껴져서",
        long: "입안을 깨워 줄 것이 없어 맛이 밋밋하고 둔하게 느껴져요",
        short: "맛이 밋밋하고 둔하게 느껴져요",
      },
    },
    umami: {
      "high:liked": {
        name: "입안을 채우는 감칠맛",
        across: "감칠맛이 진하게 느껴져서",
        long: "쌀에서 온 깊은 맛이 입안을 든든하게 채워 줘요",
        short: "깊은 맛이 입안을 든든하게 채워 줘요",
      },
      "high:burden": {
        name: "조금 무거웠던 감칠맛",
        across: "감칠맛이 진하게 느껴져서",
        long: "농후한 맛이 입안에 오래 머물며 묵직하게 다가와요",
        short: "농후한 맛이 입안에 오래 머물며 묵직하게 다가와요",
      },
      "mid:liked": {
        name: "편안하게 감도는 감칠맛",
        across: "감칠맛이 넘치지도 모자라지도 않아서",
        long: "맛의 중심이 편안하게 잡혀요",
        short: "맛의 중심이 편안하게 잡혀요",
      },
      "low:liked": {
        name: "맑고 은은한 감칠맛",
        across: "감칠맛이 맑고 은은하게 느껴져서",
        long: "잡미 없이 깨끗한 인상이 끝까지 이어져요",
        short: "잡미 없이 깨끗한 인상이 끝까지 이어져요",
      },
      "low:burden": {
        name: "조금 옅었던 감칠맛",
        across: "감칠맛이 맑고 옅게 느껴져서",
        long: "맛의 중심을 잡아 줄 깊이가 덜해요",
        short: "맛의 중심을 잡아 줄 깊이가 덜해요",
      },
    },
    body: {
      "high:liked": {
        name: "입안을 채우는 묵직함",
        across: "입안을 채우는 무게감이 또렷해서",
        long: "술이 혀를 두껍게 덮으며 한 모금에도 입안이 든든하게 차요",
        short: "한 모금에도 입안이 든든하게 차요",
      },
      "high:burden": {
        name: "다소 무거웠던 바디감",
        across: "묵직한 무게감이 또렷하게 다가와서",
        long: "술이 혀를 두껍게 덮으며 가볍게 즐길 틈을 주지 않아요",
        short: "가볍게 즐길 틈을 주지 않아요",
      },
      "mid:liked": {
        name: "적당히 채워 주는 무게감",
        across: "무게감이 적당히 느껴져서",
        long: "버겁지 않을 만큼만 혀를 덮으며 입안을 편안하게 채워 줘요",
        short: "버겁지 않게 입안을 편안하게 채워 줘요",
      },
      "low:liked": {
        name: "가볍게 넘어가는 질감",
        across: "바디감이 가볍게 느껴져서",
        long:
          "술이 혀를 얇게 스치고 지나가며 입안에 머무는 느낌 없이 술술 넘어가요",
        short: "입안에 머무는 느낌 없이 술술 넘어가요",
      },
      "low:burden": {
        name: "조금 가볍고 밋밋한 질감",
        across: "바디감이 가볍게만 느껴져서",
        long:
          "술이 혀를 얇게 스치고 지나가 입안에 남는 것 없이 맛이 비어 버려요",
        short: "입안에 남는 것 없이 맛이 비어 버려요",
      },
    },
    tannin: {
      "high:liked": {
        name: "단단하게 잡아 주는 타닌",
        across: "입안을 조이는 타닌이 또렷하게 다가와서",
        long: "침과 엉겨 붙은 그 조임이 술에 씹히는 듯한 짜임새를 만들어 줘요",
        short:
          "타닌이 입안을 떫게 조이며 술에 씹히는 듯한 짜임새를 만들어 줘요",
      },
      "high:burden": {
        name: "입안을 마르게 하는 타닌",
        across: "입안을 조이는 타닌이 또렷하게 다가와서",
        long:
          "침과 엉겨 붙은 그 조임이 입안을 마르게 하며 맛보다 먼저 느껴져요",
        short: "타닌이 입안을 떫게 조이고 마르게 하며 맛보다 먼저 느껴져요",
      },
      "mid:liked": {
        name: "적당히 잡아 주는 타닌",
        across: "타닌이 적당히 느껴져서",
        long: "거슬리지 않을 만큼만 입안을 조이며 맛에 짜임새를 잡아 줘요",
        short: "거슬리지 않을 만큼만 조이며 맛에 짜임새를 잡아 줘요",
      },
      "low:liked": {
        name: "매끄럽게 넘어가는 질감",
        across: "타닌이 낮게 느껴져서",
        long:
          "입안을 조이는 떫은 느낌 없이 그 매끄러운 촉감이 혀에 그대로 전해져요",
        short: "매끄러운 촉감이 혀에 그대로 닿아요",
      },
      "low:burden": {
        name: "조금 밋밋했던 매끄러움",
        across: "타닌이 낮게 느껴져서",
        long:
          "조이거나 톡 쏘는 자극 없이 입안에 걸리는 데가 없어 밋밋하게 느껴져요",
        short: "입안에 걸리는 데가 없어 밋밋하게 느껴져요",
      },
    },
    spice: {
      "high:liked": {
        name: "알싸하게 퍼지는 온기",
        across: "알싸한 온기가 또렷하게 다가와서",
        long: "그 온기가 향과 맛을 실어서 입안 가득 퍼뜨려 줘요",
        short: "온기가 향과 맛을 실어 입안 가득 퍼뜨려 줘요",
      },
      "high:burden": {
        name: "강하게 치고 올라온 열감",
        across: "알싸한 열감이 세게 다가와서",
        long: "그 화끈함이 향과 맛보다 먼저 목을 타고 치고 올라와요",
        short: "화끈한 열감이 향과 맛보다 먼저 치고 올라와요",
      },
      "mid:liked": {
        name: "은은하게 퍼지는 온기",
        across: "알싸한 온기가 적당히 감돌아서",
        long: "거슬리지 않을 만큼만 입안에 은은하게 퍼져요",
        short: "온기가 거슬리지 않게 입안에 은은하게 퍼져요",
      },
      "low:liked": {
        name: "자극 없이 순한 목넘김",
        across: "알싸한 자극이 순하게만 스쳐서",
        long:
          "목을 타고 올라오는 화끈한 열감 없이 술이 순하고 부드럽게 넘어가요",
        short: "화끈한 열감 없이 순하고 부드럽게 넘어가요",
      },
      "low:burden": {
        name: "힘이 덜했던 목넘김",
        across: "알싸한 열감이 순하게만 스쳐서",
        long: "목을 타고 올라오는 힘이 덜해요",
        short: "목을 타고 올라오는 힘이 덜해요",
      },
    },
    sparkling: {
      "high:liked": {
        name: "톡 쏘는 탄산감",
        across: "탄산이 톡톡 또렷하게 느껴져서",
        long:
          "기포가 혀를 두드리는 따끔함이 입안을 깨워 맛을 한결 산뜻하게 만들어 줘요",
        short: "기포가 혀를 톡톡 두드리며 맛을 한결 산뜻하게 만들어 줘요",
      },
      "high:burden": {
        name: "따끔하게 올라온 탄산",
        across: "탄산이 세게 올라와서",
        long: "기포가 혀를 톡 쏘는 따끔한 자극이 맛보다 먼저 다가와요",
        short: "따끔한 자극이 맛보다 먼저 다가와요",
      },
      "mid:liked": {
        name: "부드럽게 올라오는 탄산",
        across: "탄산이 적당히 올라와서",
        long: "따갑지 않을 만큼만 톡톡 터지는 기포가 입안을 깨워 줘요",
        short: "따갑지 않게 톡톡 올라오며 입안을 깨워 줘요",
      },
      "low:liked": {
        name: "잔잔하게 올라오는 탄산",
        across: "탄산이 잔잔하게 올라와서",
        long: "따갑지 않게 톡톡 터지는 기포가 입안을 가볍게 깨워 줘요",
        short: "따갑지 않게 입안을 가볍게 깨워 줘요",
      },
      "none:liked": {
        name: "탄산 없는 잔잔함",
        across: "탄산이 거의 느껴지지 않아서",
        long: "기포의 따가움 없이 술 본래의 맛이 잔잔하고 차분하게 전해져요",
        short: "술 본래의 맛이 잔잔하고 차분하게 전해져요",
      },
      "low:burden": {
        name: "청량감이 덜했던 탄산",
        across: "탄산이 잔잔하게만 올라와서",
        long: "입안을 깨워 줄 톡 쏘는 청량함이 덜해요",
        short: "입안을 깨워 줄 톡 쏘는 청량함이 덜해요",
      },
    },
    peat: {
      "high:liked": {
        name: "짙고 선명한 피트 향",
        across: "피트 향이 짙게 다가와서",
        long:
          "적은 양에도 코가 먼저 알아채는 스모키 향이 첫 향부터 술의 분위기를 정해 줘요",
        short: "피트·스모키 향이 첫 향부터 술의 분위기를 정해 줘요",
      },
      "high:burden": {
        name: "다른 향을 덮는 피트 향",
        across: "피트 향이 짙게 다가와서",
        long:
          "코가 먼저 알아채는 스모키 향이 뒤에 올 향과 맛의 자리까지 다 덮어 버려요",
        short: "피트·스모키 향이 뒤에 올 향과 맛까지 다 덮어 버려요",
      },
      "mid:liked": {
        name: "은은하게 깔리는 피트 향",
        across: "피트 향이 적당히 감돌아서",
        long:
          "스모키 향이 앞에 나서지 않고 바닥에 은은하게 깔려 맛에 깊이를 더해 줘요",
        short: "피트·스모키 향이 은은하게 깔려 맛에 깊이를 더해 줘요",
      },
      "low:liked": {
        name: "은은하게 스치는 피트 향",
        across: "피트 향이 옅게만 감돌아서",
        long: "스모키 향이 다른 향을 가리지 않고 깊이만 더해 줘요",
        short: "피트·스모키 향이 다른 향을 가리지 않고 깊이만 더해 줘요",
      },
      "none:liked": {
        name: "피트 없는 깔끔함",
        across: "피트 향이 거의 느껴지지 않아서",
        long:
          "스모키 향에 가려지는 것 없이 술 본래의 향과 맛이 깨끗하게 전해져요",
        short: "피트 향 없이 술 본래의 향과 맛이 깨끗하게 전해져요",
      },
      "low:burden": {
        name: "조금 옅었던 피트 향",
        across: "피트 향이 옅게만 스쳐서",
        long: "분위기를 잡아 줄 스모키 향이 모자라 향이 심심하게 느껴져요",
        short: "향이 심심하게 느껴져요",
      },
    },
    finish_length: {
      "high:liked": {
        name: "은은하게 이어지는 여운",
        across: "삼킨 뒤에도 향이 은은하게 이어져서",
        long: "맛이 사라진 뒤에도 향이 코 뒤쪽으로 은은하게 올라와요",
        short: "삼킨 뒤에도 향이 코 뒤쪽으로 은은하게 올라와요",
      },
      "high:burden": {
        name: "오래 남아 무거웠던 여운",
        across: "삼킨 뒤에도 맛과 향이 오래 머물러서",
        long: "입안이 정리될 틈 없이 여운이 끝까지 따라와요",
        short: "삼킨 뒤에도 입안이 정리될 틈을 주지 않아요",
      },
      "mid:liked": {
        name: "적당히 머무는 여운",
        across: "여운이 적당히 이어져서",
        long: "길게 끌리지도 뚝 끊기지도 않고 알맞게 머물다 사라져요",
        short: "알맞게 머물다 깔끔하게 사라져요",
      },
      "low:liked": {
        name: "깔끔하게 떨어지는 여운",
        across: "삼킨 뒤 맛과 향이 길게 끌리지 않고 깔끔하게 떨어져서",
        long: "입안에 남는 것 없이 끝이 가볍게 정리돼요",
        short: "끝이 가볍고 깔끔하게 정리돼요",
      },
      "low:burden": {
        name: "금방 끊기는 짧은 여운",
        across: "삼킨 뒤 코 뒤쪽으로 올라오는 향이 가벼워서",
        long: "맛이 사라지는 순간 여운도 함께 뚝 끊겨요",
        short: "맛이 사라지는 순간 뚝 끊겨요",
      },
    },
    finish_character: {
      "high:liked": {
        name: "진하게 남는 끝맛",
        across: "끝맛이 진하게 남아서",
        long:
          "삼킨 뒤에도 그 맛이 입안에 머물며 한 모금의 끝을 든든하게 채워 줘요",
        short: "한 모금의 끝을 든든하게 채워 줘요",
      },
      "high:burden": {
        name: "무겁게 남는 끝맛",
        across: "끝맛이 진하게 남아서",
        long: "삼킨 뒤에도 그 맛이 입안에 머물며 끝이 개운하게 정리되지 않아요",
        short: "끝이 개운하게 정리되지 않아요",
      },
      "mid:liked": {
        name: "균형 잡힌 끝맛",
        across: "끝맛이 어느 쪽으로도 치우치지 않아서",
        long: "깔끔함과 진함 사이에서 편안하게 마무리돼요",
        short: "어느 쪽으로도 치우치지 않고 편안하게 마무리돼요",
      },
      "low:liked": {
        name: "깔끔하게 떨어지는 끝맛",
        across: "끝맛이 깔끔하게 떨어져서",
        long: "삼킨 뒤 입안에 남는 것 없이 끝이 개운하게 정리돼요",
        short: "삼킨 뒤 입안이 개운하게 정리돼요",
      },
      "low:burden": {
        name: "조금 옅게 끝나는 끝맛",
        across: "끝맛이 옅게만 지나가서",
        long: "삼킨 뒤 입안에 남는 맛이 없어 끝이 싱겁고 허전하게 느껴져요",
        short: "끝이 싱겁고 허전하게 느껴져요",
      },
    },
  };

/** How an answered step is felt on its section's side. */
export function feelOf(axis: GaugeAxis, level: number, section: Section): Feel {
  const side = sideOf(axis, level);
  const table = FEEL[axis];
  const noun = AXIS[axis].noun;
  return table[`${side}:${section}`] ??
    (side === "none" ? table[`low:${section}`] : undefined) ??
    // A middle step that was minded: nothing of it stood out.
    {
      name: mindedName(axis, level),
      across: `${noun}{이} 뚜렷하지 않아서`,
      long: "인상이 흐릿하게 느껴져요",
      short: "인상이 흐릿하게 느껴져요",
    };
}

/** 묵직한 → 유난히 묵직한, 피트 향이 짙은 → 피트 향이 유난히 짙은. */
export const notably = (trait: string) =>
  (/이 /.test(trait) ? trait.replace(/이 /, "이 유난히 ") : `유난히 ${trait}`)
    .replace("유난히 꽤 있는", "유난히 진한")
    .replace("유난히 꽤 있어서", "유난히 진해서")
    .replace("유난히 거의", "거의");
