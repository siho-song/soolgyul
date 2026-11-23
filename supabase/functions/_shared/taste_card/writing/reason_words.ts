/** The words of a sense: its noun, what each step of it is called, and the forms a sentence takes of them. */
import { type GaugeAxis } from "../../record_reading/facts/facts.ts";
import { short } from "./words.ts";

export type Side = "none" | "low" | "mid" | "high";

/** A trait three ways: 묵직하고 · 묵직한 · 묵직해서. */
export type Forms = readonly [go: string, un: string, seo: string];

export const ha = (stem: string): Forms => [
  `${stem}하고`,
  `${stem}한`,
  `${stem}해서`,
];

export type AxisWords = {
  noun: string;
  /** The step as a thing: 높은 산미. */
  name: Readonly<Partial<Record<Side, string>>>;
  /** The step as what a drink is like: 산미가 높은 (술). */
  trait: Readonly<Partial<Record<Side, Forms>>>;
  /** The words a sentence names the sense by, for the bold mark. */
  marks: readonly string[];
};

export const AXIS: Readonly<Record<GaugeAxis, AxisWords>> = {
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
    marks: ["무게감", "바디감", "질감"],
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
    // 강한 알싸한 자극 stacks two words before the noun: a step is 알싸함.
    name: {
      none: "거의 없는 알싸함",
      low: "약한 알싸함",
      mid: "적당한 알싸함",
      high: "강한 알싸함",
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
    marks: ["알싸한 자극", "알싸함", "열감", "온기", "자극"],
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
export const sideOf = (axis: GaugeAxis, level: number): Side => {
  const step = Math.max(1, Math.min(5, Math.round(level)));
  if (step === 3) return "mid";
  if (step > 3) return "high";
  return step === 1 && AXIS[axis].name.none ? "none" : "low";
};

export const nameOf = (axis: GaugeAxis, level: number) =>
  AXIS[axis].name[sideOf(axis, level)]!;

export const traitOf = (axis: GaugeAxis, level: number) =>
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

/**
 * A minded step in two words, the same in the tags, the one line under them
 * and the section's own text. It is the step's name (짧은 여운, 높은 산미)
 * but where that name praises what the reader minded: a finish they found
 * too thin is 옅은 끝맛, not 깔끔한 끝맛, and a middle step nothing stood out
 * of is 어중간한, not 적당한 or 균형 잡힌.
 */
export function mindedName(axis: GaugeAxis, level: number): string {
  const side = sideOf(axis, level);
  if (side === "mid") {
    return AXIS[axis].name.mid!.replace(/^(적당한|균형 잡힌)/, "어중간한");
  }
  if (axis === "finish_character" && side === "low") return "옅은 끝맛";
  return AXIS[axis].name[side]!;
}

/** An aroma as a 핵심 요약 tag names it: 쌀 향. */
export const aromaTagName = (key: string) => `${short(key)} 향`;

/** A kind of drink the sentence names more closely than its category: 이 레드 와인은. */
export const KIND_NOUN: Readonly<Record<string, string>> = {
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
export const GAUGE_OF: Readonly<Record<string, GaugeAxis>> = {
  astringency: "tannin",
  carbonation: "sparkling",
};

export const gaugeOf = (axis: string) => (GAUGE_OF[axis] ?? axis) as GaugeAxis;
