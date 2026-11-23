/**
 * 글쓰기: the fourth stage of the 술결카드 생성 파이프라인. It says the
 * reasons 결과 선정 chose as the text of one section (잘 맞았던 이유,
 * 아쉬웠던 이유). It finds and chooses nothing.
 *
 * A section is a list (the user's form, 2026-11-22): one line a reason, two
 * at most, and a line that closes on them, a blank line between the lines.
 *
 *   **말벡**은 색소가 진하고 껍질이 두꺼워 **묵직한** 질감이 우러나, 한
 *   모금에도 입안이 든든하게 차요.
 *
 *   이 품종 특유의 **자두 향**이 새콤달콤하게 퍼지면서 무거움을 덜어 줘서
 *   끝까지 경쾌하게 마시기 좋아요.
 *
 *   묵직한 바디감과 자두 향이 균형을 이뤄서 입맛에 **잘 맞으셨던** 것 같아요.
 *
 *   a reason       {ground}, {what the taste does}. The second half is the
 *                  sentence the card has always said (FEEL). The first half
 *                  is a fact of the bottle that makes it easier to believe:
 *                  the cause and why it makes the taste (**말벡**은 … 우러나),
 *                  the cause named by what it is (**산 후안** 지역의 특성상
 *                  떫은맛이 또렷해), what was done (**버번 캐스크**에서
 *                  숙성해), or, with no fact, how it came across (이 와인에서는
 *                  …). The causes are set in ** so that the app opens the
 *                  dictionary's explanation.
 *   in this glass  a row of the table of senses that held (높은 산미가 함께
 *                  있어, …).
 *   an aroma       where it comes from, how it sat in the glass and what
 *                  that did (writing/prose_effects.ts).
 *   the closing    the reasons named again in two words and what they came
 *                  to; when the reader liked at the very end of the gauge
 *                  what sets the bottle apart among its kind, what that tells
 *                  of their taste.
 *
 * Nothing leads from one line to the next. A cause is named once a section.
 * When 결과 선정 chose fewer than two reasons, an answer no cause was found
 * for is told the same way from what was felt alone.
 */
import type { Cause, Evidence, EvidenceResult } from "../evidence/evidence.ts";
import type { FactorKind } from "../evidence/identity.ts";
import type { PerceptionRow } from "../evidence/perception.ts";
import { GAUGE_LEVEL_DIMENSION, type GaugeAxis } from "../facts/facts.ts";
import { terms } from "../dictionary/dictionary.ts";
import { effectRow } from "../findings/knowledge.ts";
import { type Carried, shelfOfKind } from "../facts/kind_place.ts";
import { mostlyOnSide } from "../facts/name_counts.ts";
import type { Prepared } from "../prepare/prepare.ts";
import type { Reason, Section, Selection } from "../selection/selection.ts";
import { howOf, makes, reaches, reasonKindOf } from "../selection/causation.ts";
import { standsOutIn } from "../selection/standing.ts";
import { andJoin, josa } from "./korean.ts";
import { effectProse } from "./prose_effects.ts";
import { explainedBy } from "./terms.ts";
import { KIND_LABEL, short, STYLE_KIND_LABEL } from "./words.ts";

export type WrittenReasons = {
  /** The reasons' names joined: "입안이 꽉 차는 묵직함과 쨍한 산미"; "" when the section says nothing. */
  title: string;
  /** The sentences of the section, the causes and sensations in ** marks. */
  text: string;
  /** How many sentences of reason the text tells. */
  reasons: number;
};

export type ReasonOptions = {
  /** Whether an answer no cause was found for is told from what was felt. */
  unexplained: boolean;
};

/* ---------------------------------------------------------------- words */

type Side = "none" | "low" | "mid" | "high";

/** A trait three ways: 묵직하고 · 묵직한 · 묵직해서. */
type Forms = readonly [go: string, un: string, seo: string];
const ha = (stem: string): Forms => [
  `${stem}하고`,
  `${stem}한`,
  `${stem}해서`,
];

type AxisWords = {
  noun: string;
  /** The step as a thing: 높은 산미. */
  name: Readonly<Partial<Record<Side, string>>>;
  /** The step as what a drink is like: 산미가 높은 (술). */
  trait: Readonly<Partial<Record<Side, Forms>>>;
  /** The words a sentence names the sense by, for the bold mark. */
  marks: readonly string[];
};

const AXIS: Readonly<Record<GaugeAxis, AxisWords>> = {
  sweetness: {
    noun: "단맛",
    name: {
      none: "거의 없는 단맛",
      low: "적은 단맛",
      mid: "적당한 단맛",
      high: "진한 단맛",
    },
    trait: {
      none: ["단맛이 거의 없고", "단맛이 거의 없는", "단맛이 거의 없어서"],
      low: ["단맛이 적고", "단맛이 적은", "단맛이 적어서"],
      mid: ha("단맛이 적당"),
      high: ["단맛이 꽤 있고", "단맛이 꽤 있는", "단맛이 꽤 있어서"],
    },
    marks: ["단맛"],
  },
  acidity: {
    noun: "산미",
    name: { low: "낮은 산미", mid: "적당한 산미", high: "높은 산미" },
    trait: {
      low: ["산미가 낮고", "산미가 낮은", "산미가 낮아서"],
      mid: ha("산미가 적당"),
      high: ["산미가 높고", "산미가 높은", "산미가 높아서"],
    },
    marks: ["산미", "새콤함", "신맛", "새콤한 맛"],
  },
  umami: {
    noun: "감칠맛",
    name: { low: "옅은 감칠맛", mid: "적당한 감칠맛", high: "진한 감칠맛" },
    trait: {
      low: ["감칠맛이 옅고", "감칠맛이 옅은", "감칠맛이 옅어서"],
      mid: ha("감칠맛이 적당"),
      high: ha("감칠맛이 진"),
    },
    marks: ["감칠맛"],
  },
  body: {
    noun: "바디감",
    name: { low: "가벼운 바디감", mid: "적당한 바디감", high: "묵직한 바디감" },
    trait: {
      low: ["질감이 가볍고", "질감이 가벼운", "질감이 가벼워서"],
      mid: ha("무게감이 적당"),
      high: ha("무게감이 묵직"),
    },
    marks: [
      "무게감",
      "바디감",
      "묵직한",
      "묵직하고",
      "묵직해서",
      "질감",
      "가볍게",
    ],
  },
  tannin: {
    // The questionnaire asks it as 타닌, and a level of it is high or low
    // (the user's review, 2026-11-22); what it does in the mouth is 떫은.
    noun: "타닌",
    name: {
      none: "거의 없는 타닌",
      low: "낮은 타닌",
      mid: "적당한 타닌",
      high: "높은 타닌",
    },
    trait: {
      none: [
        "타닌이 거의 없고",
        "타닌이 거의 없는",
        "타닌이 거의 없어서",
      ],
      low: ["타닌이 낮고", "타닌이 낮은", "타닌이 낮아서"],
      mid: ha("타닌이 적당"),
      high: ["타닌이 높고", "타닌이 높은", "타닌이 높아서"],
    },
    marks: ["타닌", "떫은맛", "떫은 맛", "떫은 느낌", "떫은 조임", "떫은 성분"],
  },
  spice: {
    noun: "알싸한 자극",
    name: {
      none: "거의 없는 알싸한 자극",
      low: "약한 알싸한 자극",
      mid: "적당한 알싸한 자극",
      high: "강한 알싸한 자극",
    },
    trait: {
      none: [
        "알싸한 자극이 거의 없고",
        "알싸한 자극이 거의 없는",
        "알싸한 자극이 거의 없어서",
      ],
      low: ha("알싸한 자극이 순"),
      mid: ha("알싸한 자극이 적당"),
      high: ["알싸한 자극이 세고", "알싸한 자극이 센", "알싸한 자극이 세서"],
    },
    marks: ["알싸한 자극", "열감", "온기", "자극"],
  },
  sparkling: {
    noun: "탄산",
    name: {
      none: "거의 없는 탄산",
      low: "약한 탄산",
      mid: "적당한 탄산",
      high: "강한 탄산",
    },
    trait: {
      none: ["탄산이 거의 없고", "탄산이 거의 없는", "탄산이 거의 없어서"],
      low: ha("탄산이 잔잔"),
      mid: ha("탄산이 적당"),
      high: ["탄산이 세고", "탄산이 센", "탄산이 세서"],
    },
    marks: ["탄산", "기포"],
  },
  peat: {
    noun: "피트 향",
    name: {
      none: "거의 없는 피트 향",
      low: "옅은 피트 향",
      mid: "적당한 피트 향",
      high: "짙은 피트 향",
    },
    trait: {
      none: [
        "피트 향이 거의 없고",
        "피트 향이 거의 없는",
        "피트 향이 거의 없어서",
      ],
      low: ["피트 향이 옅고", "피트 향이 옅은", "피트 향이 옅어서"],
      mid: ha("피트 향이 적당"),
      high: ["피트 향이 짙고", "피트 향이 짙은", "피트 향이 짙어서"],
    },
    marks: ["피트·스모키 향", "피트 향", "스모키 향"],
  },
  finish_length: {
    noun: "여운",
    name: { low: "짧은 여운", mid: "적당한 여운", high: "긴 여운" },
    trait: {
      low: ["여운이 짧고", "여운이 짧은", "여운이 짧아서"],
      mid: ha("여운이 적당"),
      high: ["여운이 길고", "여운이 긴", "여운이 길어서"],
    },
    marks: ["여운"],
  },
  finish_character: {
    noun: "끝맛",
    name: { low: "깔끔한 끝맛", mid: "균형 잡힌 끝맛", high: "진한 끝맛" },
    trait: {
      low: ha("끝맛이 깔끔"),
      mid: [
        "끝맛이 균형 잡혀 있고",
        "끝맛이 균형 잡힌",
        "끝맛이 균형 잡혀 있어서",
      ],
      high: ha("끝맛이 진"),
    },
    marks: ["끝맛"],
  },
};

/** The side a step stands on; 거의 없음 where the sense can be absent. */
const sideOf = (axis: GaugeAxis, level: number): Side => {
  const step = Math.max(1, Math.min(5, Math.round(level)));
  if (step === 3) return "mid";
  if (step > 3) return "high";
  return step === 1 && AXIS[axis].name.none ? "none" : "low";
};

const nameOf = (axis: GaugeAxis, level: number) =>
  AXIS[axis].name[sideOf(axis, level)]!;
const traitOf = (axis: GaugeAxis, level: number) =>
  AXIS[axis].trait[sideOf(axis, level)]!;

/** A gauge's taste by its name: 타닌, 바디감. */
export const senseNoun = (axis: GaugeAxis): string => AXIS[axis].noun;

/**
 * A gauge answer as a 핵심 요약 tag names it: the side it was set on (묵직한
 * 바디감, 적은 단맛, 단맛 없음).
 */
export function tagName(axis: GaugeAxis, level: number): string {
  const side = sideOf(axis, level);
  return side === "none" ? `${AXIS[axis].noun} 없음` : AXIS[axis].name[side]!;
}

/** An aroma as a 핵심 요약 tag names it: 쌀 향. */
export const aromaTagName = (key: string) => `${short(key)} 향`;

/** A kind of drink the sentence names more closely than its category: 이 레드 와인은. */
const KIND_NOUN: Readonly<Record<string, string>> = {
  red_wine: "레드 와인",
  white_wine: "화이트 와인",
  rose_wine: "로제 와인",
  orange_wine: "오렌지 와인",
  sparkling_wine: "스파클링 와인",
  port_wine: "포트 와인",
  fortified_wine: "주정강화 와인",
  sherry_wine: "셰리",
  distilled_soju: "소주",
  diluted_soju: "소주",
  korean_fruit_wine: "과실주",
  korean_cheongju: "청주",
};

/** The gauge an axis of the dictionary is asked on. */
const GAUGE_OF: Readonly<Record<string, GaugeAxis>> = {
  astringency: "tannin",
  carbonation: "sparkling",
};
const gaugeOf = (axis: string) => (GAUGE_OF[axis] ?? axis) as GaugeAxis;

/* ---------------------------------------------- how a sense is felt */

/**
 * How one side of a sense is felt, liked or minded: the subtitle's name, how
 * it came across, and what it did in the mouth. The sentences are the ones
 * the card has always said (writing/prose_tastes.ts and prose.ts), in the
 * past tense: the reader reads them after the glass.
 */
type Feel = {
  name: string;
  /** How it came across, when no fact of the bottle stands behind the answer: 단맛이 또렷하게 다가와서. */
  across: string;
  /** What it did in the mouth, with how the sense does it. */
  long: string;
  /** The same in few words, after a ground that is already long. */
  short: string;
};
type FeelKey = `${Side}:${Section}`;

const FEEL: Readonly<Record<GaugeAxis, Partial<Record<FeelKey, Feel>>>> = {
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
      across: "단맛이 또렷하게 다가오는데",
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
      across: "산미가 또렷하게 다가오는데",
      long: "산미가 입안을 깨워 다음 모금을 더 산뜻하게 받아들이게 해 줘요",
      short: "입안을 깨워 다음 모금을 더 산뜻하게 받아들이게 해 줘요",
    },
    "high:burden": {
      name: "날카롭게 찌르는 산미",
      across: "산미가 날카롭게 다가오는데",
      long:
        "혀 옆쪽을 자극해 침이 고이게 하는 산미가 상쾌함을 넘어 찌르는 자극으로 느껴져요",
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
      across: "가볍게 넘어가는 느낌이 또렷해서",
      long:
        "술이 혀를 얇게 스치고 지나가며 입안에 머무는 느낌 없이 술술 넘어가요",
      short: "입안에 머무는 느낌 없이 술술 넘어가요",
    },
    "low:burden": {
      name: "조금 가볍고 밋밋한 질감",
      across: "가벼운 느낌이 앞서서",
      long: "술이 혀를 얇게 스치고 지나가 입안에 남는 것 없이 맛이 비어 버려요",
      short: "입안에 남는 것 없이 맛이 비어 버려요",
    },
  },
  tannin: {
    "high:liked": {
      name: "단단하게 잡아 주는 타닌",
      across: "입안을 조이는 타닌이 또렷하게 다가와서",
      long: "침과 엉겨 붙은 그 조임이 술에 씹히는 듯한 짜임새를 만들어 줘요",
      short: "타닌이 입안을 떫게 조이며 술에 씹히는 듯한 짜임새를 만들어 줘요",
    },
    "high:burden": {
      name: "입안을 마르게 하는 타닌",
      across: "입안을 조이는 타닌이 또렷하게 다가와서",
      long: "침과 엉겨 붙은 그 조임이 입안을 마르게 하며 맛보다 먼저 느껴져요",
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
      long: "목을 타고 올라오는 화끈한 열감 없이 술이 순하고 부드럽게 넘어가요",
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
        "코가 먼저 알아채는 스모키 향이 뒤에 올 향과 맛의 자리까지 벽처럼 다 덮어 버려요",
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
function feelOf(axis: GaugeAxis, level: number, section: Section): Feel {
  const side = sideOf(axis, level);
  const table = FEEL[axis];
  const noun = AXIS[axis].noun;
  return table[`${side}:${section}`] ??
    (side === "none" ? table[`low:${section}`] : undefined) ??
    // A middle step that was minded: nothing of it stood out.
    {
      name: `어중간한 ${noun}`,
      across: `${noun}{이} 어느 쪽으로도 또렷하지 않아서`,
      long: "인상이 흐릿하게 느껴져요",
      short: "인상이 흐릿하게 느껴져요",
    };
}

/** 묵직한 → 유난히 묵직한, 피트 향이 짙은 → 피트 향이 유난히 짙은. */
const notably = (trait: string) =>
  (/이 /.test(trait) ? trait.replace(/이 /, "이 유난히 ") : `유난히 ${trait}`)
    .replace("유난히 꽤 있는", "유난히 진한")
    .replace("유난히 꽤 있어서", "유난히 진해서")
    .replace("유난히 거의", "거의");

/* --------------------------------------------------------------- causes */

type Card = {
  /** The drink as the sentence calls it: 레드 와인, 위스키, 막걸리. */
  kind: string;
  /** Whether the drink is brewed from grain (사케, 전통주): 쌀로 빚은, not 만든. */
  brewed: boolean;
  /** Whether the drink is a wine: what it is made of is a grape. */
  wine: boolean;
  /** The shelf the kind's bottles are counted on. */
  shelf: string | null;
  /** Whether the bottle's strength is one of its causes: its strength is then not said to be low. */
  strong: boolean;
  /** The side on which the bottle stands out among its kind on a gauge, given the causes that speak of it. */
  standsOut: (
    axis: GaugeAxis,
    causes: readonly Cause[],
  ) => "high" | "low" | null;
};

type Gauge = Extract<Evidence["answer"], { kind: "gauge" }>;

/** The name of a cause without what the dictionary adds in brackets. */
const bare = (c: Cause): Cause => ({
  ...c,
  ko: c.ko.replace(/\s*\([^)]*\)/g, ""),
});

const same = (a: Cause, b: { factor: FactorKind; key: string }) =>
  a.factor === b.factor && a.key === b.key;

/** The cause's name as a word the app can open. */
const word = (c: Cause) => `**${c.ko}**`;

/** A making row said as what was done, where "…을 거친" does not say it. */
const MADE: Readonly<Record<string, (k: string) => string>> = {
  peated_malt: (k) => `${k}{을} 쓴`,
  non_chill_filtered: (k) => `${k}{으로} 병에 담은`,
  unpasteurised: (k) => `${k}{으로} 병에 담은`,
  unfiltered_claim: () => "여과하지 않은",
  organic_certified: (k) => `${k}{을} 받은`,
  biodynamic_certified: (k) => `${k}{을} 받은`,
  natural_wine_claim: () => "내추럴 와인을 표방하는",
  rice_water_only_claim: () => "쌀과 물만 쓴",
  noble_rot: (k) => `${k} 포도로 만든`,
};

/** A making row that names a kind of drink of its own: 니고리답게. */
const OWN_KIND = new Set([
  "coarse_filtered",
  "undiluted",
  "cask_strength",
  "small_batch",
]);

/** The cause as the one that gives a taste: **누룩**, 12년 숙성, 41%의 높은 도수. */
function giver(c: Cause): string {
  if (c.factor === "abv") {
    return `${c.ko.replace(/^도수\s*/, "")}의 ${
      c.key === "abv_low" ? "낮은" : "높은"
    } 도수`;
  }
  if (c.factor === "age") {
    return c.ko.includes("없음") ? "짧은 숙성" : `${c.ko} 숙성`;
  }
  return c.factor === "label_word" ? `'${word(c)}'` : word(c);
}

/**
 * Where an aroma comes from, before 향이에요, as the dictionary's row says it
 * comes: of the fruit (**말벡** 포도에서 오는), with age (**피노 누아** 와인이
 * 숙성되면서 생기는), from the cask (**셰리 캐스크**에서 밴). Never 특유의:
 * of the Burgundy reds the catalog holds, one in six carries the earth the
 * row lists, so the name is said as where it comes from and not as what every
 * bottle of it has (the user's review, 2026-11-23). Nothing when the name
 * says it (쌀에서 나는 쌀 향 says 쌀 twice: the user's review, 2026-11-21),
 * or when the row does not say where.
 */
function aromaFrom(c: Cause, aroma: string, card: Card): string {
  if (short(aroma).includes(c.ko) || c.ko.includes(short(aroma))) return "";
  const from = aromaSource(c, card);
  // 오크통에서 밴 오크 향, 누룩에서 오는 누룩·코지 향 say the thing twice.
  return short(aroma).split("·").some((part) => from.includes(part))
    ? ""
    : from;
}

function aromaSource(c: Cause, card: Card): string {
  if (c.factor === "cask") return `${word(c)}에서 밴`;
  if (["ingredient", "making", "label_word", "age"].includes(c.factor)) {
    return `${giver(c)}에서 오는`;
  }
  const place = c.factor === "region_style" && PLACES.has(c.ko);
  // The drink of the name: **부르고뉴** 레드 와인, **피노 누아** 와인, **준마이**.
  const drink = c.factor === "grape"
    ? `${word(c)} 와인`
    : place
    ? `${word(c)} ${card.kind}`
    : c.factor === "producer"
    ? `${what(c)}의 ${card.kind}`
    : word(c);
  switch (c.aroma_source) {
    case "material":
    case "ripeness":
      return c.factor === "grape"
        ? `${word(c)} 포도에서 오는`
        : c.factor === "producer"
        ? `${what(c)}{이} 쓰는 원료에서 오는`
        : `${what(c)}의 ${card.wine ? "포도" : "원료"}에서 오는`;
    case "nuruk":
      return `${drink}의 누룩에서 오는`;
    case "ageing":
      return `${drink}{이} 숙성되면서 생기는`;
    case "cask":
      return c.factor === "producer"
        ? `${what(c)}{이} 쓰는 오크통에서 밴`
        : `${drink}{을} 숙성하는 오크통에서 밴`;
    case "yeast":
      return `${drink}{이} 발효하면서 생기는`;
    case "process":
      return `${drink}{을} 만드는 과정에서 생기는`;
    case "soil":
      return `${what(c)}의 토양에서 온다고 알려진`;
    case "surroundings":
      return `${what(c)}의 주변 환경에서 오는`;
    default:
      return "";
  }
}

/* ----------------------------------------------------- in this glass */

/** What a row of the table of senses names by a making key, as a thing. */
const MADE_THING: Readonly<Record<string, string>> = {
  charred_cask: "안쪽을 태운 오크통",
  kimoto_starter: "기모토 방식",
  yamahai_starter: "야마하이 방식",
  undiluted: "물을 타지 않은 원주",
  unfiltered_claim: "여과하지 않은 술",
  unpasteurised: "살균하지 않은 술",
  coarse_filtered: "성글게 거른 술",
};

/** What made a row hold, as a thing and as the bare sense it is of: ["강한 탄산", "탄산"]. */
type Thing = readonly [thing: string, sense: string];

function thing(said: string): Thing | null {
  const p = said.split(":");
  const ofAxis = (axis: GaugeAxis, level: number): Thing => [
    nameOf(axis, level),
    AXIS[axis].noun,
  ];
  const ofAroma = (key: string): Thing | null =>
    short(key) === key ? null : [`${short(key)} 향`, `${short(key)} 향`];
  if (p[0] === "answer") return ofAxis(p[1] as GaugeAxis, Number(p[2]));
  if (p[0] === "abv") {
    return p[1] === "high"
      ? ["높은 도수", "도수"]
      : [`${p[1]}%의 높은 도수`, "도수"];
  }
  if (p[0] === "kind") return ["탄산", "탄산"];
  if (p[0] === "making" && p.length === 2) {
    return MADE_THING[p[1]] ? [MADE_THING[p[1]], MADE_THING[p[1]]] : null;
  }
  if (p[0] === "aroma") return ofAroma(p[1]);
  if (p[2] === "climate") {
    return ["따뜻한 산지에서 잘 익은 포도", "잘 익은 포도"];
  }
  if (p[2] === "aroma_strength") {
    return p[3] === "high" ? ["진한 향", "향"] : ["옅은 향", "향"];
  }
  if (p.length === 4) {
    const axis = gaugeOf(p[2]);
    if (!AXIS[axis]) return null;
    return ofAxis(axis, p[3] === "high" ? 4 : p[3] === "none" ? 1 : 2);
  }
  return p.length === 3 ? ofAroma(p[2]) : null;
}

/**
 * A row of the table of senses as the two halves of a sentence: what is in
 * the glass (높은 산미가 함께 있어서) and what that does to the sense (신맛이
 * 단맛을 깎아 주는 만큼). What it comes to is the sense's own `felt`.
 */
type RowWords = {
  head: (things: string, senses: string) => string;
  does: string | ((senses: string) => string);
};
const WITH = (things: string) => `${things}{이} 함께 있어서`;
const LESS = (_things: string, senses: string) => `${senses}{이} 적어서`;
const r = (head: RowWords["head"], does: RowWords["does"]): RowWords => ({
  head,
  does,
});

const ROWS: Readonly<Record<string, RowWords>> = {
  "단 향 → 단맛": r(WITH, "단 향이 단맛과 어우러지는 만큼"),
  "익은 과일 향 → 단맛": r(WITH, "익은 과일 향이 단맛을 살려 주는 만큼"),
  "적당히 높은 도수 → 단맛": r(WITH, "알코올이 혀를 둥글게 감싸 주는 만큼"),
  "진득한 질감 → 단맛": r(WITH, "묵직한 질감이 단맛을 돋보이게 하는 만큼"),
  "탄산 → 산미": r(WITH, "기포가 혀를 두드리며 산미를 살리는 만큼"),
  "강한 산미 → 떫음": r(WITH, "선명한 산미가 입안을 조이는 느낌을 거드는 만큼"),
  "단맛·높은 도수 → 묵직함": r(
    WITH,
    "당분과 알코올이 입안에 무게감을 더하는 만큼",
  ),
  "높은 도수·매운 향 → 스파이시": r(
    WITH,
    "알코올과 향신료 기운이 자극을 더하는 만큼",
  ),
  "탄 오크 향 → 피트": r(WITH, "구운 나무 향이 스모키 향과 겹치는 만큼"),
  "진한 향 → 긴 여운": r(WITH, "삼킨 뒤에도 향이 오래 남는 만큼"),
  "묵직한 바디 → 긴 여운": r(WITH, "묵직한 술이 천천히 넘어가는 만큼"),
  "단맛 → 긴 여운": r(WITH, "단맛이 입안에 천천히 머무는 만큼"),
  "떫음 → 긴 여운": r(WITH, "떫은 느낌이 입안에 오래 남는 만큼"),
  "감칠맛 → 긴 여운": r(WITH, "감칠맛이 입안에 천천히 남는 만큼"),
  "높은 도수 → 긴 여운": r(WITH, "알코올 온기가 삼킨 뒤에도 남는 만큼"),
  "높은 산미 → 긴 여운": r(WITH, "산미가 입안의 맛을 이어 주는 만큼"),
  "피트 → 긴 여운": r(WITH, "스모키 향이 삼킨 뒤에도 코에 남는 만큼"),
  "가벼운 바디 → 짧은 여운": r(
    () => "바디감이 가벼워서",
    "입안에 머무는 무게감이 가벼운 만큼",
  ),
  "단맛이 적음 → 짧은 여운": r(LESS, "입안에 남는 맛이 적은 만큼"),
  "떫음이 적음 → 짧은 여운": r(LESS, "입안에 남는 느낌이 적은 만큼"),
  "감칠맛이 적음 → 짧은 여운": r(LESS, "입안에 남는 깊이가 적은 만큼"),
  "옅은 향 → 짧은 여운": r(
    () => "향이 옅어서",
    "삼킨 뒤 올라올 향이 옅은 만큼",
  ),
  "탄산이 입을 씻어 줌 → 짧은 여운": r(
    WITH,
    "기포가 입안에 남은 맛을 씻어 내는 만큼",
  ),
  "탄산·산미 → 가벼움": r(
    WITH,
    (senses) => `${senses}{이} 술의 무게감을 덜어 주는 만큼`,
  ),
  "전통 주모·진한 술 → 감칠맛": r(
    (things) => `${things}{이라}서`,
    "발효로 우러난 성분이 많은 만큼",
  ),
  "단맛이 산미를 감쌈": r(WITH, "단맛이 산미를 부드럽게 감싸는 만큼"),
  "산미·떫음이 단맛을 가림": r(
    WITH,
    (senses) => `${senses}{이} 단맛을 덜 도드라지게 하는 만큼`,
  ),
  "탄산이 단맛을 가림": r(WITH, "기포가 단맛을 산뜻하게 정리하는 만큼"),
  "묵직함이 산미를 덮음": r(WITH, "묵직한 질감이 산미를 차분하게 누르는 만큼"),
  "단맛·진득함이 떫음을 감쌈": r(
    WITH,
    (senses) => `${senses}{이} 타닌을 부드럽게 감싸는 만큼`,
  ),
  "단맛·묵직함이 알코올 자극을 감쌈": r(
    WITH,
    (senses) => `${senses}{이} 알코올 자극을 부드럽게 감싸는 만큼`,
  ),
  "단맛·묵직함이 탄산을 둥글림": r(
    WITH,
    (senses) => `${senses}{이} 탄산의 자극을 순하게 하는 만큼`,
  ),
  "단맛이 없어 산미가 드러남": r(LESS, "산미가 더 또렷해지는 만큼"),
  "산미·떫음이 순해 단맛이 드러남": r(LESS, "단맛을 가리던 맛이 순한 만큼"),
  "단맛이 없어 떫음이 드러남": r(LESS, "타닌이 더 선명한 만큼"),
  "단맛·묵직함이 없어 자극이 드러남": r(
    LESS,
    "자극을 감싸 주던 요소가 적은 만큼",
  ),
  "단맛·묵직함이 없어 탄산이 드러남": r(
    LESS,
    "탄산을 순하게 하던 요소가 적은 만큼",
  ),
};

/** Words too common to show that two clauses say the same thing. */
const COMMON = new Set(["입안", "한 ", "모금", "다음", "술이", "맛이", "향이"]);

/**
 * What a relation in the glass does and what that came to, as one clause:
 * 신맛이 단맛을 깎아 준 덕분에 물리지 않고 편안하게 느껴져요. When the two
 * say the same (입안을 조이는 만큼 입안을 조이고 …) only what it came to is
 * said.
 */
function relation(
  does: string,
  brief: string,
  section: Section,
  head = "",
  marks: readonly string[] = [],
): string {
  const stems = (text: string) =>
    new Set(
      text.split(/\s+/).filter((w) => w.length >= 2).map((w) => w.slice(0, 2))
        .filter((w) => !COMMON.has(w)),
    );
  const said = stems(brief);
  if ([...stems(does)].some((w) => said.has(w))) return brief;
  // 바디감이 가벼워, 입안에 머무는 무게감이 가벼운 덕분에 … says the first
  // half again; a half that names the taste it turned (… 산미를 누르는) stays.
  const first = stems(head);
  if (
    [...stems(does)].some((w) => first.has(w)) &&
    !marks.some((m) => does.includes(m))
  ) return brief;
  return `${
    does.replace(/ 만큼$/, section === "liked" ? " 덕분에" : " 탓에")
  } ${brief}`;
}

/** A row that held as the two halves of its sentence, or null when it names nothing sayable. */
function rowWords(
  rule: PerceptionRow,
): { head: string; does: string } | null {
  const words = ROWS[rule.name];
  if (!words) return null;
  const seen = new Set<string>();
  const things = rule.by.flatMap((b) => {
    const t = thing(b.said);
    return t && !seen.has(t[0]) && seen.add(t[0]) ? [t] : [];
  }).slice(0, 2);
  if (!things.length) return null;
  const named = andJoin(things.map((t) => t[0]));
  const senses = andJoin([...new Set(things.map((t) => t[1]))]);
  const head = words.head(named, senses);
  const does = typeof words.does === "string" ? words.does : words.does(senses);
  // 묵직한 바디감이 함께 있어서, 바디감이 … says the thing twice: what the
  // first half has just named is not the subject of the second again.
  const again = things.every((t) => head.includes(t[1])) &&
      does.startsWith(`${senses}{이} `)
    ? `${senses}{이} `
    : does.match(/^(\S+?)[이가] /)?.[0];
  const repeats = again !== undefined &&
    head.includes(again.replace(/(\{이\}|[이가]) $/, ""));
  return { head, does: repeats ? does.slice(again!.length) : does };
}

/* --------------------------------------------------------------- aromas */

const EFFECT: Readonly<Record<Section, ReturnType<typeof effectProse>>> = {
  liked: effectProse("liked"),
  burden: effectProse("burden"),
};

/**
 * How an aroma sat in this glass and what that did, liked or minded
 * (달큰하게 감돌아, 술을 한결 부드럽게 감싸 줘요). What kind of smell it is
 * in general (단맛과 늘 함께 오던 냄새라서) is not said: the user's review,
 * 2026-11-21, read it as a remark beside the point.
 */
const AROMA_SAID: Readonly<
  Record<string, Readonly<Record<Section, readonly [string, string]>>>
> = {
  effect_ripe_fruit: {
    liked: ["달큰하게 피어오르면서", "술이 한결 포근하게 느껴져요"],
    burden: ["지나치게 앞서 나오면서", "마실수록 금방 물리게 돼요"],
  },
  effect_sour_fruit: {
    liked: ["새콤달콤하게 퍼지면서", "술이 한결 경쾌하게 느껴져요"],
    burden: ["강하게 앞서면서", "술이 시고 날카롭게 다가와요"],
  },
  effect_fresh_fruit: {
    liked: ["가볍고 상쾌하게 퍼지면서", "술이 한결 산뜻하게 느껴져요"],
    burden: ["가볍게만 스치면서", "전체적인 인상이 다소 허전하게 느껴져요"],
  },
  effect_floral: {
    liked: ["은은하게 피어오르면서", "술이 한결 화사하고 섬세하게 느껴져요"],
    burden: ["끝까지 강하게 남아", "맛과 어우러지지 않고 겉돌아요"],
  },
  effect_smoke: {
    liked: ["첫 향부터 깊게 깔리면서", "술의 중심을 잘 잡아 줘요"],
    burden: ["너무 강하게 앞서면서", "다른 향과 맛을 가려 버려요"],
  },
  effect_sweet_scent: {
    liked: ["달큰하게 감돌면서", "술을 한결 부드럽게 감싸 줘요"],
    burden: ["지나치게 진하게 올라와", "마실수록 금방 물리게 돼요"],
  },
  effect_grain_nut: {
    liked: ["구수하게 깔리면서", "술이 편안하고 든든하게 느껴져요"],
    burden: ["지나치게 앞서면서", "술이 무겁고 텁텁하게 느껴져요"],
  },
  effect_roast: {
    liked: ["쌉쌀하고 고소하게 깔리면서", "술이 진하고 묵직하게 느껴져요"],
    burden: ["강하게 앞서면서", "탄 듯한 쓴맛만 도드라져요"],
  },
  effect_wood: {
    liked: ["은은하게 올라와 머물면서", "술이 차분하고 안정감 있게 느껴져요"],
    burden: ["지나치게 강하게 남아", "입안이 답답하고 텁텁하게 느껴져요"],
  },
  effect_green: {
    liked: ["상쾌하게 퍼지면서", "술이 깔끔하고 또렷하게 느껴져요"],
    burden: ["거칠게 앞서면서", "풋내가 강해 거슬려요"],
  },
  effect_vegetal: {
    liked: ["풋풋하게 스치면서", "술이 담백하고 깔끔하게 느껴져요"],
    burden: ["강하게 앞서면서", "거친 풋내로 거슬려요"],
  },
  effect_spice: {
    liked: ["알싸하게 퍼지면서", "술에 기분 좋은 온기와 생기를 더해 줘요"],
    burden: ["강하게 앞서면서", "맵고 거친 자극만 남아요"],
  },
  effect_mineral: {
    liked: ["서늘하고 깔끔하게 남으면서", "술이 단단하고 정돈된 느낌을 줘요"],
    burden: ["강하게 앞서면서", "입안이 차갑고 딱딱하게 느껴져요"],
  },
  effect_earth: {
    liked: ["차분하게 깔리면서", "술에 그윽한 깊이를 더해 줘요"],
    burden: ["강하게 앞서면서", "술이 눅눅하고 퀴퀴하게 느껴져요"],
  },
  effect_dairy: {
    liked: ["매끄럽게 감돌면서", "술이 날카롭지 않고 부드럽게 느껴져요"],
    burden: ["진하게 남으면서", "술이 무겁고 느끼하게 느껴져요"],
  },
  effect_ferment: {
    liked: [
      "살짝 시큼하고 구수하게 올라오면서",
      "술이 생생하고 풍성하게 느껴져요",
    ],
    burden: ["강하게 앞서면서", "시큼하고 쿰쿰하게 거슬려요"],
  },
  effect_savory: {
    liked: ["감칠맛 나게 깔리면서", "술이 든든하고 깊게 느껴져요"],
    burden: ["지나치게 앞서면서", "무겁고 짭짤하게 느껴져요"],
  },
  effect_aged: {
    liked: ["차분하고 낮게 깔리면서", "술에 그윽한 깊이를 더해 줘요"],
    burden: ["강하게 앞서면서", "술이 퀴퀴하고 무겁게 느껴져요"],
  },
};

/** What an aroma does in the nose and mouth, liked or minded (writing/prose_effects.ts). */
function aromaProse(
  key: string,
  section: Section,
): { name: string; body: string } {
  const row = effectRow(key);
  const said = row ? AROMA_SAID[row]?.[section] : undefined;
  if (row && said) {
    return {
      name: EFFECT[section][row].name,
      body: `{aroma}{이} ${said[0]}, ${said[1]}.`,
    };
  }
  if (row) return EFFECT[section][row];
  return section === "liked"
    ? {
      name: "{aroma}",
      body:
        "{aroma}{이} 기분 좋게 올라오면서, 첫인상부터 술을 풍성하게 느끼게 해 줘요.",
    }
    : {
      name: "{aroma}",
      body: "{aroma}{이} 강하게 앞서면서, 다른 향과 맛을 가려 거슬려요.",
    };
}

/* --------------------------------------------------------- one reason */

/** The names the dictionary keeps as places: a style of that name is a place's. */
const PLACES: ReadonlySet<string> = new Set(
  terms("region").map((t) => t.names.ko.replace(/\s*\([^)]*\)/g, "")),
);

/** What a producer is, where the dictionary says: a distillery, a winery. */
const HOUSE: Readonly<Record<string, string>> = {
  distillery: "증류소",
  winery: "와이너리",
};
const HOUSE_OF: ReadonlyMap<string, string> = new Map(
  terms("producer").flatMap((t) => {
    const house = HOUSE[String(t.extra?.kind)];
    return house ? [[t.key, house] as const] : [];
  }),
);

/**
 * The cause with what it is: **산 후안** 지역, **말벡** 품종, **라프로익**
 * 증류소, '**브뤼**' 표기, 41%의 높은 도수 (the user's word, 2026-11-22: say
 * whether it is a place or a grape). A style that is not a place's name
 * (샴페인, 모스카토 다스티) and a producer the dictionary does not say the
 * kind of are named alone.
 */
function what(c: Cause): string {
  switch (c.factor) {
    case "region_style":
      return PLACES.has(c.ko) ? `${word(c)} 지역` : word(c);
    case "grape":
      return `${word(c)} 품종`;
    case "label_word":
      return `'${word(c)}' 표기`;
    case "producer": {
      const house = HOUSE_OF.get(c.key);
      return house ? `${word(c)} ${house}` : word(c);
    }
    case "abv":
    case "age":
      return giver(c);
    default:
      return word(c);
  }
}

/** The names the catalog counts the bottles of, by the cause that names them. */
const COUNTED_AS: Readonly<Partial<Record<FactorKind, Carried>>> = {
  kind: "kinds",
  grape: "grapes",
  region_style: "styles",
};

/** The causes that are what the drink is: a taste is a mark of them, not something that comes out of them. */
const IS = new Set<FactorKind>([
  "region_style",
  "kind",
  "label_word",
  "producer",
]);

/**
 * Where a taste comes from, as the end of a point's first sentence. A grape
 * the point tells no why of is named as having the taste, not as making it.
 */
const source = (c: Cause, told: boolean) =>
  IS.has(c.factor) || (c.factor === "grape" && !told) ||
    ((c.factor === "making" || c.factor === "cask") && OWN_KIND.has(c.key))
    ? `${what(c)}의 특징이에요`
    : `${what(c)}에서 나와요`;

/**
 * One point of a section (the user's standard, 2026-11-22): the taste and
 * what it comes from, then why and what it does in the mouth.
 *
 *   묵직한 바디감은 **말벡** 품종에서 나와요. 색소가 진하고 껍질이 두꺼워
 *   묵직한 질감이 우러나, 한 모금에도 입안이 든든하게 차요.
 *
 * With no cause to name, one sentence says it (이 와인에서는 단맛이 적당히
 * 감돌아, …).
 */
type Point = {
  /** The cause it names, if any. */
  cause: Cause | null;
  /** The first sentence, without the particle after the taste; null when one sentence says it all. */
  open: { taste: string; from: string } | null;
  /** Why, before what it does: 색소가 진하고 껍질이 두꺼워 묵직한 질감이 우러나서. "" when the name says enough. */
  why: string;
  /** What the taste does in the mouth. */
  act: string;
  /** What stands between the two: ", " but for an aroma (퍼지면서 술이 …). */
  glue?: string;
};

/**
 * A cause as the first sentence of a point and the why of its second. With
 * `link`, the clause the dictionary's research wrote for the cause and the
 * taste; without, what sets the bottle apart among its kind (`apart`), or
 * nothing: the name is then the whole of the reason.
 */
function pointOf(
  c: Cause,
  taste: string,
  trait: string,
  link: string | null,
  apart: string | null,
  axis: GaugeAxis,
  card: Card,
  side: Side = "mid",
): Omit<Point, "act"> {
  // 질감을 묵직하게 채워서 has reached the taste: it is not named after it.
  const after = link === null
    ? ""
    : reaches(axis, link)
    ? link
    : `${link.replace(/서$/, "")} ${trait}`;
  // 이 레드 와인은 레드 와인의 특징이에요 says nothing: the drink is the subject.
  if (c.ko === card.kind) {
    return {
      cause: null,
      open: null,
      why: `이 ${card.kind}{은} ${after || apart || trait}`,
    };
  }
  // A taste is a name's mark when most of the name's bottles have it, as
  // the catalog counts them: of the 준마이 다이긴조 a third are light, of
  // the 산지오베제 reds a quarter are high in tannin. Where they do not, the
  // taste in the glass is told as this bottle's, not as what the name is.
  const what = COUNTED_AS[c.factor];
  const borne = what && side !== "mid"
    ? mostlyOnSide(
      { what, key: c.key },
      card.shelf,
      GAUGE_LEVEL_DIMENSION[axis],
      side === "high" ? "high" : "low",
    )
    : "uncounted";
  if (borne === "no" && (after || apart)) {
    const drink = c.factor === "kind" ||
        (c.factor === "region_style" && !PLACES.has(c.ko))
      ? word(c)
      : `${word(c)} ${card.kind}`;
    return {
      cause: c,
      open: null,
      why: `이 ${drink}{은} ${after || apart}`,
    };
  }
  // 여과하지 않은 술이라: what was done is not a thing a taste comes out of.
  if (link === null && MADE[c.key]) {
    return {
      cause: c,
      open: null,
      why: `${MADE[c.key](word(c))} 술이라 ${apart ?? trait}`,
    };
  }
  return {
    cause: c,
    open: { taste, from: source(c, after !== "") },
    why: after || apart || "",
  };
}

/**
 * What the taste did, after its ground. The ground has just named the taste,
 * so a sentence that opens on it again (떫은맛이 입안을 조이며 …) goes on
 * without it.
 */
function actAfter(
  ground: string,
  act: string,
  marks: readonly string[],
): string {
  const again = [...marks].sort((x, y) => y.length - x.length)
    // 새콤함이 또렷해서, 새콤한 맛이 … is the same word; 피트 불길에 말려
    // has not named the 피트 향.
    .filter((m) =>
      marks.some((k) => k.slice(0, 2) === m.slice(0, 2) && ground.includes(k))
    )
    // 피트 향이 거의 없어서, 피트 향 없이 … says it twice too.
    .flatMap((m) =>
      ["이 ", "가 ", "은 ", "는 ", " 없이 "].map((p) => `${m}${p}`)
    )
    .find((open) => act.startsWith(open));
  // … 오크의 떫은맛이 또렷하게 우러나, 입안을 떫게 조이고 … says 떫 twice.
  const rest = (again ? act.slice(again.length) : act).replace(
    ground.includes("떫") ? "떫게 " : "\u0000",
    "",
  );
  // … 여운이 삼킨 뒤에도 길게 이어져서, 삼킨 뒤에도 … says when twice.
  const when = "삼킨 뒤에도 ";
  return ground.includes(when.trim()) && rest.startsWith(when)
    ? rest.slice(when.length)
    : rest;
}

type Told = {
  /** The reason as the subtitle names it: 든든하게 채우는 무게감. */
  name: string;
  /** The reason in two words, as its point opens on it: 묵직한 바디감, 자두 향. */
  brief: string;
  /** What is said of the drink, after whatever opens the sentence, without its period. */
  body: string;
  /** A sentence that names its own subject (**말벡**은 보통 …, **자두 향**은 …) and takes no opening. */
  whole: boolean;
  /**
   * The cause a whole sentence opens on (**병내 2차 발효**는 …) and, for a
   * place, the word its climate is called by (서늘한 **샤블리**는 …).
   */
  subject?: { cause: Cause; climate?: string };
  /** The body without 같은 종류 가운데서도 유난히, for when the closing says it. */
  plain?: string;
  /** The causes the sentence stands on, the one it was told by first. */
  causes: readonly Cause[];
  /** The words of the sense the sentence is about, for the bold mark. */
  marks: readonly string[];
  /** Whether a burden is something the reader wanted more of (적은 단맛, 짧은 여운). */
  lack: boolean;
  /** 이번 잔에서 alone: the gauge it speaks of and the gauges it is explained by. */
  glass?: { of: GaugeAxis; by: readonly string[] };
  /** A point the section puts together: the taste, where it comes from, why and what it does. */
  point?: Point;
  /** What the sentence is about, for how two reasons stand to each other. */
  of?: { axis?: GaugeAxis; side?: string; aroma?: string };
};

/**
 * A taste in two words. One the reader wanted more of is named as thin (옅은
 * 끝맛: 깔끔한 끝맛 would praise what they minded), and a middle step that
 * was minded has only its own name (어중간한 단맛).
 */
function briefOf(
  g: { axis: GaugeAxis; level: number; side: string },
  section: Section,
  feel: Feel,
): string {
  if (section === "burden" && g.side === "low") {
    return g.axis === "tannin" ? "낮은 타닌" : `옅은 ${AXIS[g.axis].noun}`;
  }
  return section === "burden" && sideOf(g.axis, g.level) === "mid"
    ? feel.name
    : nameOf(g.axis, g.level);
}

const causeKey = (c: { factor: FactorKind; key: string }) =>
  `${c.factor}:${c.key}`;

/**
 * The cause an aroma is told by. A place that carries it gives way to the
 * bottle's grape when the grape carries it too: the earth of a Burgundy is
 * as common in a Pinot Noir from elsewhere, so it is the grape's.
 */
const aromaCause = (
  told: Cause | null,
  causes: readonly Cause[],
): Cause | null =>
  told?.factor === "region_style"
    ? causes.find((c) => c.factor === "grape") ?? told
    : told;

/** An aroma: where it comes from, how it sat in the glass and what that did. */
function tellAroma(
  key: string,
  cause: Cause | null,
  section: Section,
  card: Card,
): Told {
  const prose = aromaProse(key, section);
  const aroma = `**${short(key)} 향**`;
  // 이 레드 와인은 레드 와인 특유의 … says the kind twice.
  const from = cause && cause.ko !== card.kind
    ? aromaFrom(cause, key, card)
    : "";
  // How it sat in the glass, and what that did.
  const said = prose.body.match(/^\{aroma\}\{이\} (.+?), (.+)\.$/);
  const base = {
    name: prose.name.replaceAll("{aroma}", `${short(key)} 향`),
    brief: `${short(key)} 향`,
    whole: true,
    causes: [],
    marks: [],
    lack: false,
    of: { aroma: effectRow(key) ?? undefined, side: "high" },
  };
  if (!said) {
    return {
      ...base,
      body: prose.body.replaceAll("{aroma}", aroma).replace(/\.$/, ""),
    };
  }
  return {
    ...base,
    body: "",
    point: cause && from
      // 자두 향은 말벡 포도에서 오는 향이에요. 새콤달콤하게 퍼지면서 술이 …
      ? {
        cause,
        open: { taste: aroma, from: `${from} 향이에요` },
        why: said[1],
        act: said[2],
        glue: " ",
      }
      : {
        cause: null,
        open: null,
        why: `${aroma}{이} ${said[1]}`,
        act: said[2],
      },
  };
}

function tellReason(
  reason: Reason,
  byId: ReadonlyMap<string, Evidence>,
  prepared: Prepared,
  card: Card,
): Told | null {
  const section = reason.section;
  // Nothing explains the answer: it is told as it was felt.
  if (!reason.evidence.length) {
    return tellFelt(reason.answers[0], section, prepared, card);
  }
  const all = reason.evidence.flatMap((id) => byId.get(id) ?? []).map((e) => ({
    ...e,
    causes: e.causes.map(bare),
  }));
  const first = all[0];
  if (!first) return null;
  const told = reason.told_by
    ? first.causes.find((c) => same(c, reason.told_by!)) ?? first.causes[0]
    : null;
  const rulesOf = (e: Evidence) => e.perception?.rules ?? [];

  if (first.answer.kind === "aroma") {
    const key = first.answer.aroma;
    if (first.type !== "aroma_effect") {
      return tellAroma(key, aromaCause(told, first.causes), section, card);
    }
    // What in the glass let the aroma through.
    const rule = rulesOf(first)[0];
    const abv = rule?.by.find((b) => b.said.startsWith("abv:"))?.said
      .split(":")[1];
    const aroma = `**${short(key)} 향**`;
    const body = rule?.name.startsWith("떫음이 적어")
      ? `타닌이 낮은 덕분에, ${aroma}{이} 가려지지 않고 또렷하게 피어올라요`
      : rule?.name.startsWith("도수가 높지 않아") && abv && !card.strong
      ? `도수가 ${abv}%로 높지 않은 덕분에, ${aroma}{이} 알코올에 묻히지 않고 또렷하게 피어올라요`
      : null;
    return body
      ? {
        name: aromaProse(key, section).name.replaceAll(
          "{aroma}",
          `${short(key)} 향`,
        ),
        brief: `${short(key)} 향`,
        body,
        whole: false,
        causes: [],
        marks: [],
        lack: false,
        of: { aroma: effectRow(key) ?? undefined, side: "high" },
      }
      : null;
  }

  const gauges = all.filter((e) => e.answer.kind === "gauge");
  const g = first.answer as Gauge;
  const feel = feelOf(g.axis, g.level, section);
  const marks = AXIS[g.axis].marks;
  const base = {
    name: feel.name,
    brief: briefOf(g, section, feel),
    marks,
    lack: section === "burden" && g.side === "low",
    of: { axis: g.axis, side: g.side as string },
  };
  /** The told cause's step on a gauge answer, as that answer's evidence holds it. */
  const stepOn = (e: Evidence, cause: Cause) =>
    e.causes.find((c) => same(c, cause))?.tendency?.step ??
      (e.answer as Gauge).level;
  // A row that only says one of the reason's own answers again adds nothing.
  const own = new Set(gauges.map((e) => `answer:${(e.answer as Gauge).axis}`));
  const row = rulesOf(first).flatMap((rule) => {
    const said = rule.by.filter((b) =>
      !own.has(b.said.split(":").slice(0, 2).join(":"))
    );
    const words = said.length ? rowWords({ ...rule, by: said }) : null;
    return words ? [{ rule, ...words }] : [];
  })[0];

  // What held in this glass (탄산이 함께 있어서, …).
  const inGlass: Told | null = row
    ? {
      ...base,
      body: `${row.head}, ${
        relation(row.does, feel.short, section, row.head, marks)
      }`,
      whole: false,
      causes: [],
      glass: {
        of: g.axis,
        by: row.rule.by.flatMap((b) =>
          b.said.startsWith("answer:") ? [b.said.split(":")[1]] : []
        ),
      },
    }
    : null;
  if (first.type === "in_this_glass" || !told) return inGlass;
  // The cause is usually unlike what the reader felt: it is not brought in
  // to stand against the answer (the user's review, 2026-11-22: "억지로
  // 품종이나 산지 근거를 끌어다 붙이지 않고 이번 잔의 실제 인상으로"). What in
  // this glass turned the taste is told, or the taste as it was felt.
  if (first.type === "felt_differently") {
    return inGlass ?? tellFelt(reason.answers[0], section, prepared, card);
  }
  if (first.type === "bottle_trait" && first.support) {
    return tellFelt(reason.answers[0], section, prepared, card);
  }
  // The same where only the kind says what the reader said and a way the
  // bottle was made makes the opposite (a peated blended malt that came
  // across faint): the kind's own reason would not be true of this bottle.
  const turned = first.type === "split" && told.factor === "kind" &&
    g.side !== "middle" &&
    (first.against ?? []).map(bare).some((c) =>
      (c.factor === "making" || c.factor === "cask") &&
      c.tendency !== undefined && howOf(c, g.axis) !== null
    );
  if (turned) return tellFelt(reason.answers[0], section, prepared, card);

  // 설명 · 엇갈림 · 종류 경향: what the cause makes the drink, and what that
  // did in the mouth.
  const says = (c: Cause) =>
    !same(c, told) && c.tendency !== undefined && makes(c, g.axis) &&
    sideOf(g.axis, c.tendency.step) === sideOf(g.axis, stepOn(first, told));
  const causes = [told, ...first.causes.filter((c) => says(c))];
  const out = card.standsOut(g.axis, causes);
  const stands_out = out && out === g.side ? out : null;
  // Why the cause makes the taste: the clause the dictionary's research
  // wrote for this cause and this taste (나무통에서 우러난 풍미가 질감을 둥글고
  // 묵직하게 채워서), one line of it (the user's standard, 2026-11-22: the
  // taste, what it comes from, then the principle in a line). A pair whose
  // clause only says the taste again is named and no more.
  const side = g.level > 3 ? "high" : "low";
  const kindOfReason = reasonKindOf(told, g.axis, side);
  const link = told.factor !== "abv" && g.level !== 3 &&
      kindOfReason !== null && kindOfReason !== "style_only"
    ? howOf(told, g.axis, side)
    : null;
  const trait = traitOf(g.axis, stepOn(first, told));
  // A middle step that was minded: nothing of it stood out.
  const vague = section === "burden" && sideOf(g.axis, g.level) === "mid";
  const point = pointOf(
    told,
    base.brief,
    vague ? feel.across : trait[2],
    link,
    stands_out && !link
      ? `같은 종류 가운데서도 ${notably(trait[1])} 편이라`
      : null,
    g.axis,
    card,
    sideOf(g.axis, g.level),
  );
  return {
    ...base,
    body: "",
    whole: true,
    point: {
      ...point,
      // A point that told why is long already: what it does is said in few words.
      act: actAfter(
        `${point.open?.taste ?? ""} ${point.why}`,
        link ? feel.short : feel.long,
        marks,
      ),
    },
    causes,
  };
}

/** An answer no cause was found for, told from what was felt alone. */
function tellFelt(
  ref: string,
  section: Section,
  prepared: Prepared,
  card: Card,
): Told | null {
  const { gauges, aromas } = prepared.interpretation;
  const g = gauges.find((x) => x.answer_ref === ref);
  if (g) {
    // A middle step alone says too little to be a reason.
    if (g.side === "middle") return null;
    const feel = feelOf(g.axis, g.level, section);
    const marks = AXIS[g.axis].marks;
    const base = {
      name: feel.name,
      brief: briefOf(g, section, feel),
      body: "",
      whole: true,
      causes: [],
      marks,
      lack: section === "burden" && g.side === "low",
      of: { axis: g.axis, side: g.side as string },
    };
    // The bottle's own level, read for it, on the side the reader set: the
    // drink is such a drink, as the card has always said of it (이 와인은
    // 묵직해서, …).
    const dimension = GAUGE_LEVEL_DIMENSION[g.axis];
    const own = dimension ? prepared.bottle.levels[dimension] : undefined;
    const side = g.level > 3 ? "high" : "low";
    const drink = `이 ${card.kind}{은}`;
    if (
      own?.of === "bottle" && own.level !== 3 &&
      (own.level > 3 ? "high" : "low") === side
    ) {
      const apart = card.standsOut(g.axis, []) === side;
      const trait = traitOf(g.axis, g.level);
      const why = `${drink} ${
        apart ? `같은 종류 가운데서도 ${notably(trait[1])} 편이라` : trait[2]
      }`;
      return {
        ...base,
        point: {
          cause: null,
          open: null,
          why,
          act: actAfter(why, feel.long, marks),
        },
      };
    }
    const act = actAfter(feel.across, feel.long, marks);
    // The level read for the bottle stands two steps or more the other way:
    // that it came across so in this glass is what there is to tell.
    if (
      own?.of === "bottle" && own.level !== 3 &&
      (own.level > 3 ? "high" : "low") !== side &&
      Math.abs(own.level - g.level) >= 2
    ) {
      return {
        ...base,
        body: `표기된 스타일은 ${
          traitOf(g.axis, own.level)[1]
        } 편이지만 이번 잔에서는 ${feel.across}, ${act}`,
      };
    }
    // No fact of the bottle stands behind it: 이 와인에서는 단맛이 적당히
    // 감돌아서, …
    return {
      ...base,
      point: {
        cause: null,
        open: null,
        why: `이 ${card.kind}에서는 ${feel.across}`,
        act,
      },
    };
  }
  const a = aromas.find((x) => x.answer_ref === ref);
  return a ? tellAroma(a.aroma, null, section, card) : null;
}

/* ------------------------------------------------- the explained words */

/** Names the card's own sentences use as plain words: 물리지 않고, 오렌지 와인, 포르투갈. */
const NOT_A_NAME: ReadonlySet<string> = new Set([
  "물리",
  "오렌지",
  "포르투",
  "피노",
  "포도",
  "허브",
]);
/** The grains and ferments a clause names; a fruit in a clause is an aroma, not what the drink is made of. */
const MADE_OF: ReadonlySet<string> = new Set([
  "효모",
  "유산균",
  "코지",
  "백국",
  "황국",
  "누룩",
  "보리",
  "맥아",
  "옥수수",
  "호밀",
  "귀리",
  "찹쌀",
  "오마치 쌀",
  "수수",
  "메밀",
  "고구마",
  "홉",
]);
const KIND_NAMES: ReadonlySet<string> = new Set(
  terms("kind").map((t) => t.names.ko),
);

/**
 * The words a line may hold that the dictionary explains, longest first: the
 * tastes by their names, and the grapes, places, casks, ways of making,
 * grains and label words by theirs. A maker is marked only on its own
 * bottle (마시 is also 마시기 좋아요).
 */
const EXPLAINED: readonly string[] = (() => {
  const plain = (name: string) => name.replace(/\s*\([^)]*\)/g, "").trim();
  const names = new Set<string>([
    ...Object.values(AXIS).map((a) => a.noun),
    "신맛",
  ]);
  for (
    const t of terms(
      "grape",
      "regional_style",
      "region",
      "process",
      "maturation",
      "label_word",
      "kind",
      "ingredient",
    )
  ) {
    const name = plain(t.names.ko);
    if (t.type === "ingredient" && !MADE_OF.has(name)) continue;
    // A country (미국산 참나무, 일본 물참나무) is no word to look up.
    if (t.type === "region" && !t.parent) continue;
    names.add(name);
    if (t.type === "grape") {
      for (const part of name.split("·")) names.add(part);
    }
  }
  return [...names].filter((n) =>
    n.replace(/\s/g, "").length >= 2 && !NOT_A_NAME.has(n) &&
    explainedBy(n) !== null
  ).sort((a, b) => b.length - a.length);
})();

/** The line with each explained word marked once, where a word begins. */
function explainedWords(line: string, own: readonly string[]): string {
  const had = new Set(
    [...line.matchAll(/\*\*(.+?)\*\*/g)].flatMap(([, w]) =>
      explainedBy(w) ?? []
    ),
  );
  let text = line;
  const names = [
    ...own.filter((n) => n.length >= 2 && !EXPLAINED.includes(n)),
    ...EXPLAINED,
  ];
  for (const name of names) {
    if (!text.includes(name)) continue;
    const by = explainedBy(name);
    if (!by || had.has(by)) continue;
    // 유러피언 오크 has just been opened: the 오크 after it is the same wood.
    if (
      [...text.matchAll(/\*\*(.+?)\*\*/g)].some(([, w]) => w.includes(name))
    ) {
      continue;
    }
    const parts = text.split(/(\*\*.+?\*\*)/);
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].startsWith("**")) continue;
      let at = parts[i].indexOf(name);
      while (at >= 0) {
        const before = parts[i].slice(0, at);
        const begins = at === 0 || /[\s'"(·,‘“]$/.test(before);
        // 이 레드 와인은 …, 이 **키안티** 레드 와인은 … is the drink itself,
        // not a word to open.
        const itself = KIND_NAMES.has(name) &&
          (/(^|\s)이 $/.test(before) ||
            (before === " " && i >= 2 && /(^|\s)이 $/.test(parts[i - 2])));
        if (begins && !itself) break;
        at = parts[i].indexOf(name, at + 1);
      }
      if (at < 0) continue;
      parts[i] = `${parts[i].slice(0, at)}**${name}**${
        parts[i].slice(at + name.length)
      }`;
      had.add(by);
      break;
    }
    text = parts.join("");
  }
  return text;
}

/* ------------------------------------------------------- the section */

/** A section tells at most this many reasons. */
const MOST = 2;

/** The first place one of the words stands outside a mark, as [at, word]. */
function firstOf(
  text: string,
  words: readonly string[],
): [number, string] | null {
  let best: [number, string] | null = null;
  for (const w of words) {
    for (let at = text.indexOf(w); at >= 0; at = text.indexOf(w, at + 1)) {
      const inMark = (text.slice(0, at).split("**").length - 1) % 2 === 1;
      if (inMark) continue;
      if (
        !best || at < best[0] || (at === best[0] && w.length > best[1].length)
      ) {
        best = [at, w];
      }
      break;
    }
  }
  return best;
}

/**
 * A sentence with its sense in ** marks, once. Where the sentence names the
 * sense itself, that name is the word (묵직한 **바디감**은 …), not a word
 * that describes it (the user's review, 2026-11-22).
 */
function marked(
  text: string,
  marks: readonly string[],
  noun?: string,
): string {
  const hit = (noun ? firstOf(text, [noun]) : null) ?? firstOf(text, marks);
  if (!hit) return text;
  const [at, w] = hit;
  return `${text.slice(0, at)}**${w}**${text.slice(at + w.length)}`;
}

/**
 * 묵직해서, → 묵직해,: a line of the list says its first half in fewer words.
 * 퍼지면서 and 통에서 are other words, and a one-letter stem (세서) keeps it.
 */
const clipped = (text: string) =>
  text.replace(
    /(\S+)서, /g,
    (all, stem: string) =>
      stem.length >= 2 && !/[면에]$/.test(stem) ? `${stem}, ` : all,
  );

/* ------------------------------------------- two reasons, one to the other */

/** What a sentence is about, as one word: body:high, effect_sour_fruit. */
const about = (t: Told) =>
  t.of?.axis ? `${t.of.axis}:${t.of.side}` : t.of?.aroma ?? "";

const HEAVY = new Set(["body:high", "finish_character:high", "umami:high"]);
const DEEP = new Set([
  "body:high",
  "finish_character:high",
  "finish_length:high",
  "umami:high",
  "peat:high",
  "effect_grain_nut",
  "effect_roast",
  "effect_wood",
  "effect_smoke",
  "effect_earth",
  "effect_savory",
  "effect_aged",
]);
const LIFTS = new Set([
  "acidity:high",
  "sparkling:high",
  "effect_sour_fruit",
  "effect_fresh_fruit",
  "effect_floral",
  "effect_green",
  "effect_mineral",
]);

/**
 * What a section's second reason did to its first, where the two pull apart
 * (the user's example, 2026-11-22: … 새콤달콤하게 퍼지면서 무거움을 덜어 줘서
 * 끝까지 경쾌하게 마시기 좋아요), said in place of what the second did alone.
 * Which tastes weigh, lift or deepen is read here from the kind of taste.
 * Null for any other pair: each then says what it did itself.
 */
function linkOf(a: Told, b: Told, section: Section): string | null {
  const x = about(a);
  const y = about(b);
  if (section !== "liked" || !x || !y) return null;
  if (HEAVY.has(x) && LIFTS.has(y)) {
    return "무거움을 덜어 줘서 끝까지 경쾌하게 마시기 좋아요";
  }
  if (x === "body:low" && DEEP.has(y)) {
    return "가벼운 질감에 깊이를 더해 줘요";
  }
  return null;
}

/**
 * 글쓰기: the reasons 결과 선정 chose, as one subtitle and one text for each
 * section. Pure.
 */
export function writeReasons(
  prepared: Prepared,
  found: EvidenceResult,
  selection: Selection,
  options: ReasonOptions = { unexplained: true },
): Record<Section, WrittenReasons> {
  const { category, style_key } = prepared.bottle;
  const kind = STYLE_KIND_LABEL[style_key ?? ""] ??
    KIND_NOUN[style_key ?? ""] ?? KIND_LABEL[style_key ?? ""] ??
    KIND_LABEL[category ?? ""] ??
    (category === "korean_traditional" ? "전통주" : "술");
  const card: Card = {
    kind,
    brewed: category === "sake" || category === "korean_traditional",
    wine: category === "wine",
    shelf: shelfOfKind(style_key, category),
    strong: found.identity.causes.some((c) => c.key === "abv_high"),
    standsOut: standsOutIn(prepared.bottle),
  };
  const write = (section: Section) =>
    writeSection(section, prepared, found, selection, options, card);
  return { liked: write("liked"), burden: write("burden") };
}

function writeSection(
  section: Section,
  prepared: Prepared,
  found: EvidenceResult,
  selection: Selection,
  options: ReasonOptions,
  card: Card,
): WrittenReasons {
  const byId = new Map(found.evidence.map((e) => [e.id, e]));
  const chosen = selection[section];
  const told: Told[] = [];
  const add = (t: Told | null) => {
    if (t && told.length < MOST && !told.some((x) => x.name === t.name)) {
      told.push(t);
    }
  };
  for (const reason of chosen.reasons) {
    const t = tellReason(reason, byId, prepared, card);
    // 단맛이 적어서 산미가, 산미가 높아서 단맛이: said one way round only.
    const circular = t?.glass &&
      told.some((x) =>
        x.glass && x.glass.by.includes(t.glass!.of) &&
        t.glass!.by.includes(x.glass.of)
      );
    // A reason the sentence cannot say (or would say in a circle) is still
    // an answer the reader felt: it is told as it was felt.
    add(
      t && !circular ? t : tellFelt(reason.answers[0], section, prepared, card),
    );
  }
  const reasons = told.length;
  // An aroma a reason explains beside its taste is a sentence of its own
  // while there is room.
  for (const reason of chosen.reasons) {
    for (const id of reason.evidence.slice(1)) {
      const e = byId.get(id);
      if (e?.answer.kind !== "aroma" || e.type === "aroma_effect") continue;
      const causes = e.causes.map(bare);
      const cause = (reason.told_by &&
        causes.find((c) => same(c, reason.told_by!))) ?? causes[0] ?? null;
      add(
        tellAroma(e.answer.aroma, aromaCause(cause, causes), section, card),
      );
    }
  }
  if (options.unexplained) {
    for (const ref of chosen.untold) {
      add(tellFelt(ref, section, prepared, card));
    }
  }
  if (!told.length) return { title: "", text: "", reasons: 0 };

  // A cause is named once a section. The next section may name it again for
  // another taste: the grape that gave the weight the reader liked is also
  // what gave the tannin they minded.
  const named = new Set<string>();
  // What the section's sentences have said so far: a cause one of them has
  // spoken of is not named as new again.
  let spoken = "";
  const told_of = (c: Cause) => named.has(causeKey(c)) || spoken.includes(c.ko);
  const sentences = told.map((t, i) => {
    const text = sentence(t, i);
    spoken += ` ${text}`;
    return text;
  });

  // Each reason is a line of its own: nothing leads from one to the next.
  function sentence(t: Told, i: number): string {
    const link = i === 1 ? linkOf(told[0], t, section) : null;

    if (t.point) {
      // The taste and what it comes from, then why and what it does. What
      // the two reasons do together (무거움을 덜어 줘서 …) is said in place
      // of what this one does alone. A cause the section has told of already
      // gives this taste too (높은 산미도 …).
      const p = t.point;
      const again = p.cause !== null && told_of(p.cause);
      if (p.cause) named.add(causeKey(p.cause));
      const rest = [p.why, link ?? p.act].filter(Boolean).join(p.glue ?? ", ");
      return p.open
        ? `${p.open.taste}${again ? "도" : "{은}"} ${p.open.from}. ${rest}.`
        : `${rest}.`;
    }
    if (t.whole) {
      for (const c of t.causes) named.add(causeKey(c));
      return `${t.body}.`;
    }
    // What held in this glass (탄산이 함께 있어서, …).
    return `${t.body}.`;
  }

  // Every word of a line the dictionary explains is marked, the cause it is
  // told by or not (네비올로 껍질과 씨에서 …, 높은 산미가 함께 있어 …): the
  // reader can open it wherever it stands (the user's review, 2026-11-22).
  const own = found.evidence.flatMap((e) => e.causes).filter((c) =>
    c.factor !== "abv" && c.factor !== "age" && c.factor !== "kind"
  ).map((c) => bare(c).ko);
  const lines = sentences.map((text, i) =>
    explainedWords(
      marked(
        josa(clipped(text)),
        told[i].marks,
        told[i].of?.axis ? AXIS[told[i].of!.axis!].noun : undefined,
      ),
      own,
    )
  );

  const names = told.map((t) => t.name);
  return {
    title: names.some((n) => /[과와] /.test(n))
      ? names.join(", ")
      : andJoin(names),
    // A point a reason, a blank line between two.
    text: lines.map((line) => `• ${line}`).join("\n\n"),
    reasons,
  };
}
