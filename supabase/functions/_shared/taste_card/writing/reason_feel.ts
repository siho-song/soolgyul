/** How a sense is felt at each side, liked or minded: the half of a reason that says what the taste does in the mouth. */
import { type GaugeAxis } from "../../record_reading/facts/facts.ts";
import type { Section } from "../selection/selection.ts";
import { AXIS, type Side, sideOf } from "./reason_words.ts";

/**
 * How one side of a sense is felt, liked or minded: how it came across, and
 * what it did in the mouth. In the past tense: the reader reads them after
 * the glass.
 */
export type Feel = {
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
        across: "단맛이 또렷하게 다가와서",
        long:
          "혀에 가장 먼저 닿는 그 단맛이 첫 모금을 부드럽고 포근하게 감싸 줘요",
        short: "첫 모금을 부드럽고 포근하게 감싸 줘요",
      },
      "high:burden": {
        across: "단맛이 또렷하게 다가와서",
        long: "혀에 가장 먼저 닿는 단맛이 다른 맛을 누르고 혼자 앞으로 나서요",
        short: "단맛이 다른 맛을 누르고 혼자 앞으로 나서요",
      },
      "mid:liked": {
        across: "단맛이 적당히 감돌아서",
        long: "앞에 나서지 않고 첫 모금만 부드럽게 감싸 줘요",
        short: "첫 모금만 부드럽게 감싸 줘요",
      },
      "low:liked": {
        across: "단맛이 은은하게 감돌아서",
        long:
          "앞에 나서지 않고 혀를 살짝만 감싸 주니 물리지 않고 편안하게 느껴져요",
        short: "물리지 않고 편안하게 느껴져요",
      },
      "none:liked": {
        across: "단맛이 거의 느껴지지 않아서",
        long:
          "혀에 남는 단맛 없이 맛이 깔끔하게 떨어져 다음 모금도 물리지 않아요",
        short: "맛이 깔끔하게 떨어져 다음 모금도 물리지 않아요",
      },
      "low:burden": {
        across: "단맛이 옅게만 다가와서",
        long: "맛의 모서리를 감싸 줄 것이 없어 술이 메마르고 심심하게 느껴져요",
        short: "술이 메마르고 심심하게 느껴져요",
      },
    },
    acidity: {
      "high:liked": {
        across: "산미가 또렷하게 다가와서",
        long: "산미가 입안을 깨워 다음 모금을 더 산뜻하게 받아들이게 해 줘요",
        short: "입안을 깨워 다음 모금을 더 산뜻하게 받아들이게 해 줘요",
      },
      "high:burden": {
        across: "산미가 날카롭게 다가와서",
        // One clause: after 산미가 날카롭게 다가와, three in a row did not
        // read in one go.
        long: "상쾌함을 넘어 혀 옆쪽을 찌르는 자극으로 느껴져요",
        short: "산미가 상쾌함을 넘어 찌르는 자극으로 느껴져요",
      },
      "mid:liked": {
        across: "산미가 적당히 감돌아서",
        long: "앞에 나서지 않으면서도 입안을 산뜻하게 깨워 줘요",
        short: "앞에 나서지 않으면서도 입안을 산뜻하게 깨워 줘요",
      },
      "low:liked": {
        across: "산미가 은은하게 감돌아서",
        long: "입안을 살짝만 깨워 주고 다음 모금을 산뜻하게 받아들이게 해 줘요",
        short: "자극 없이 입안을 살짝만 깨워 줘요",
      },
      "low:burden": {
        across: "산미가 옅게만 느껴져서",
        long: "입안을 깨워 줄 것이 없어 맛이 밋밋하고 둔하게 느껴져요",
        short: "맛이 밋밋하고 둔하게 느껴져요",
      },
    },
    umami: {
      "high:liked": {
        across: "감칠맛이 진하게 느껴져서",
        long: "쌀에서 온 깊은 맛이 입안을 든든하게 채워 줘요",
        short: "깊은 맛이 입안을 든든하게 채워 줘요",
      },
      "high:burden": {
        across: "감칠맛이 진하게 느껴져서",
        long: "농후한 맛이 입안에 오래 머물며 묵직하게 다가와요",
        short: "농후한 맛이 입안에 오래 머물며 묵직하게 다가와요",
      },
      "mid:liked": {
        across: "감칠맛이 넘치지도 모자라지도 않아서",
        long: "맛의 중심이 편안하게 잡혀요",
        short: "맛의 중심이 편안하게 잡혀요",
      },
      "low:liked": {
        across: "감칠맛이 맑고 은은하게 느껴져서",
        long: "잡미 없이 깨끗한 인상이 끝까지 이어져요",
        short: "잡미 없이 깨끗한 인상이 끝까지 이어져요",
      },
      "low:burden": {
        across: "감칠맛이 맑고 옅게 느껴져서",
        long: "맛의 중심을 잡아 줄 깊이가 덜해요",
        short: "맛의 중심을 잡아 줄 깊이가 덜해요",
      },
    },
    body: {
      "high:liked": {
        across: "입안을 채우는 무게감이 또렷해서",
        long: "술이 혀를 두껍게 덮으며 한 모금에도 입안이 든든하게 차요",
        short: "한 모금에도 입안이 든든하게 차요",
      },
      "high:burden": {
        across: "묵직한 무게감이 또렷하게 다가와서",
        long: "술이 혀를 두껍게 덮으며 가볍게 즐길 틈을 주지 않아요",
        short: "가볍게 즐길 틈을 주지 않아요",
      },
      "mid:liked": {
        across: "무게감이 적당히 느껴져서",
        long: "버겁지 않을 만큼만 혀를 덮으며 입안을 편안하게 채워 줘요",
        short: "버겁지 않게 입안을 편안하게 채워 줘요",
      },
      "low:liked": {
        across: "바디감이 가볍게 느껴져서",
        long:
          "술이 혀를 얇게 스치고 지나가며 입안에 머무는 느낌 없이 술술 넘어가요",
        short: "입안에 머무는 느낌 없이 술술 넘어가요",
      },
      "low:burden": {
        across: "바디감이 가볍게만 느껴져서",
        long: "술이 혀를 얇게 스치고 지나가 남는 것 없이 맛이 텅 비어 버려요",
        short: "혀에 남는 것 없이 맛이 텅 비어 버려요",
      },
    },
    tannin: {
      "high:liked": {
        across: "입안을 조이는 타닌이 또렷하게 다가와서",
        long: "침과 엉겨 붙은 그 조임이 술에 묵직한 중심을 잡아 줘요",
        short: "타닌이 입안을 기분 좋게 조이며 묵직한 중심을 잡아 줘요",
      },
      "high:burden": {
        across: "입안을 조이는 타닌이 또렷하게 다가와서",
        long:
          "침과 엉겨 붙은 그 조임이 입안을 마르게 하며 맛보다 먼저 느껴져요",
        short: "타닌이 입안을 떫게 조이고 마르게 하며 맛보다 먼저 느껴져요",
      },
      "mid:liked": {
        across: "타닌이 적당히 느껴져서",
        long: "거슬리지 않을 만큼만 입안을 조이며 맛에 짜임새를 잡아 줘요",
        short: "거슬리지 않을 만큼만 조이며 맛에 짜임새를 잡아 줘요",
      },
      "low:liked": {
        across: "타닌이 낮게 느껴져서",
        long:
          "입안을 조이는 떫은 느낌 없이 그 매끄러운 촉감이 혀에 그대로 전해져요",
        short: "매끄러운 촉감이 혀에 그대로 닿아요",
      },
      "low:burden": {
        across: "타닌이 약하게만 다가와서",
        long:
          "조이거나 톡 쏘는 자극 없이 입안에 걸리는 데가 없어 밋밋하게 느껴져요",
        short: "입안에 걸리는 데가 없어 밋밋하게 느껴져요",
      },
    },
    spice: {
      "high:liked": {
        across: "알싸한 온기가 또렷하게 다가와서",
        long: "그 온기가 향과 맛을 실어서 입안 가득 퍼뜨려 줘요",
        short: "온기가 향과 맛을 실어 입안 가득 퍼뜨려 줘요",
      },
      "high:burden": {
        across: "알싸한 열감이 세게 다가와서",
        long: "그 화끈함이 향과 맛보다 먼저 목을 타고 치고 올라와요",
        short: "화끈한 열감이 향과 맛을 가릴 정도로 강하게 퍼져요",
      },
      "mid:liked": {
        across: "알싸한 온기가 적당히 감돌아서",
        long: "거슬리지 않을 만큼만 입안에 은은하게 퍼져요",
        short: "온기가 거슬리지 않게 입안에 은은하게 퍼져요",
      },
      "low:liked": {
        across: "알싸한 자극이 순하게만 스쳐서",
        long:
          "목을 타고 올라오는 화끈한 열감 없이 술이 순하고 부드럽게 넘어가요",
        short: "화끈한 열감 없이 편안하게 목을 넘어가요",
      },
      "low:burden": {
        across: "알싸한 열감이 순하게만 스쳐서",
        long: "목을 타고 올라오는 힘이 덜해요",
        short: "목을 타고 올라오는 힘이 덜해요",
      },
    },
    sparkling: {
      "high:liked": {
        across: "탄산이 톡톡 또렷하게 느껴져서",
        long:
          "기포가 혀를 두드리는 따끔함이 입안을 깨워 맛을 한결 산뜻하게 만들어 줘요",
        short: "기포가 혀를 톡톡 두드리며 맛을 한결 산뜻하게 만들어 줘요",
      },
      "high:burden": {
        across: "탄산이 세게 올라와서",
        long: "기포가 혀를 톡 쏘는 따끔한 자극이 맛보다 먼저 다가와요",
        short: "따끔한 자극이 맛보다 먼저 다가와요",
      },
      "mid:liked": {
        across: "탄산이 적당히 올라와서",
        long: "따갑지 않을 만큼만 톡톡 터지는 기포가 입안을 깨워 줘요",
        short: "따갑지 않게 톡톡 올라오며 입안을 깨워 줘요",
      },
      "low:liked": {
        across: "탄산이 잔잔하게 올라와서",
        long: "따갑지 않게 톡톡 터지는 기포가 입안을 가볍게 깨워 줘요",
        short: "따갑지 않게 입안을 가볍게 깨워 줘요",
      },
      "none:liked": {
        across: "탄산이 거의 느껴지지 않아서",
        long: "기포의 따가움 없이 술 본래의 맛이 잔잔하고 차분하게 전해져요",
        short: "술 본래의 맛이 잔잔하고 차분하게 전해져요",
      },
      "low:burden": {
        across: "탄산이 잔잔하게만 올라와서",
        long: "입안을 깨워 줄 톡 쏘는 청량함이 덜해요",
        short: "입안을 깨워 줄 톡 쏘는 청량함이 덜해요",
      },
    },
    peat: {
      "high:liked": {
        across: "피트 향이 짙게 다가와서",
        long:
          "잔을 들자마자 코끝을 채우는 스모키 향이 첫 향부터 술의 분위기를 정해 줘요",
        short: "피트·스모키 향이 첫 향부터 술의 분위기를 정해 줘요",
      },
      "high:burden": {
        across: "피트 향이 짙게 다가와서",
        long:
          "코가 먼저 알아채는 스모키 향이 뒤에 올 향과 맛의 자리까지 다 덮어 버려요",
        short: "피트·스모키 향이 뒤에 올 향과 맛까지 다 덮어 버려요",
      },
      "mid:liked": {
        across: "피트 향이 적당히 감돌아서",
        long:
          "스모키 향이 앞에 나서지 않고 바닥에 은은하게 깔려 맛에 깊이를 더해 줘요",
        short: "피트·스모키 향이 은은하게 깔려 맛에 깊이를 더해 줘요",
      },
      "low:liked": {
        across: "피트 향이 옅게만 감돌아서",
        long: "스모키 향이 다른 향을 가리지 않고 깊이만 더해 줘요",
        short: "피트·스모키 향이 다른 향을 가리지 않고 깊이만 더해 줘요",
      },
      "none:liked": {
        across: "피트 향이 거의 느껴지지 않아서",
        long:
          "스모키 향에 가려지는 것 없이 술 본래의 향과 맛이 깨끗하게 전해져요",
        short: "피트 향 없이 술 본래의 향과 맛이 깨끗하게 전해져요",
      },
      "low:burden": {
        across: "피트 향이 옅게만 스쳐서",
        long: "분위기를 잡아 줄 스모키 향이 모자라 향이 심심하게 느껴져요",
        short: "향이 심심하게 느껴져요",
      },
    },
    finish_length: {
      "high:liked": {
        // 향이 은은하게 이어져, … 향이 … 은은하게 올라와요 said it twice.
        across: "여운이 길게 이어져서",
        long: "맛이 사라진 뒤에도 향이 코 뒤쪽으로 은은하게 올라와요",
        short: "삼킨 뒤에도 향이 코 뒤쪽으로 은은하게 올라와요",
      },
      "high:burden": {
        across: "삼킨 뒤에도 맛과 향이 오래 머물러서",
        long: "입안이 정리될 틈 없이 여운이 끝까지 따라와요",
        short: "삼킨 뒤에도 입안이 정리될 틈을 주지 않아요",
      },
      "mid:liked": {
        across: "여운이 적당히 이어져서",
        long: "길게 끌리지도 뚝 끊기지도 않고 알맞게 머물다 사라져요",
        short: "알맞게 머물다 깔끔하게 사라져요",
      },
      "low:liked": {
        across: "삼킨 뒤 맛과 향이 길게 끌리지 않고 깔끔하게 떨어져서",
        long: "입안에 남는 것 없이 끝이 가볍게 정리돼요",
        short: "끝이 가볍고 깔끔하게 정리돼요",
      },
      "low:burden": {
        across: "삼킨 뒤 코 뒤쪽으로 올라오는 향이 가벼워서",
        long: "맛이 사라지는 순간 여운도 함께 뚝 끊겨요",
        short: "맛이 사라지는 순간 뚝 끊겨요",
      },
    },
    finish_character: {
      "high:liked": {
        across: "끝맛이 진하게 남아서",
        long:
          "삼킨 뒤에도 그 맛이 입안에 머물며 한 모금의 끝을 든든하게 채워 줘요",
        short: "한 모금의 끝을 든든하게 채워 줘요",
      },
      "high:burden": {
        across: "끝맛이 진하게 남아서",
        long: "삼킨 뒤에도 그 맛이 입안에 머물며 끝이 개운하게 정리되지 않아요",
        short: "끝이 개운하게 정리되지 않아요",
      },
      "mid:liked": {
        across: "끝맛이 어느 쪽으로도 치우치지 않아서",
        long: "깔끔함과 진함 사이에서 편안하게 마무리돼요",
        short: "어느 쪽으로도 치우치지 않고 편안하게 마무리돼요",
      },
      "low:liked": {
        across: "끝맛이 깔끔하게 떨어져서",
        long: "삼킨 뒤 입안에 남는 것 없이 끝이 개운하게 정리돼요",
        short: "삼킨 뒤 입안이 개운하게 정리돼요",
      },
      "low:burden": {
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
