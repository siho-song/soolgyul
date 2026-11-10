/**
 * The knowledge table behind card findings: one row per thing the card may
 * say, grouped by the seven ways of thinking. Rows carry the conditions a
 * matcher checks, the sentence parts a template fills, and one example input
 * that must make the row fire (its test).
 *
 * Wording is tuned on finished cards; only the table changes then.
 */
import type { LevelDimension, Subject } from "../facts/facts.ts";

export type Band = "low" | "mid" | "high";
/** A small product fact pattern a row asks for. */
export type ProductCondition =
  | { type: "level"; dimension: LevelDimension; is: Band }
  | { type: "level_not"; dimension: LevelDimension; is: Band }
  | { type: "scent"; trait: string }
  | { type: "trait"; key: string };

export type Example = {
  answers: readonly string[];
  levels?: Partial<Record<LevelDimension, 1 | 2 | 3 | 4 | 5>>;
  aromas?: readonly string[];
  texture?: readonly string[];
  style?: string;
};

const taste = (key: Subject["key"]) => ({ domain: "taste", key }) as Subject;
const mouth = (key: Subject["key"]) =>
  ({ domain: "mouthfeel", key }) as Subject;
const level = (dimension: LevelDimension, is: Band): ProductCondition => ({
  type: "level",
  dimension,
  is,
});

/* ---------------------------------------------------------------- 강도 */
type IntensityRow = {
  thinking: "intensity";
  subject: Subject;
  dimension: LevelDimension | null;
  /** The subject is strong when its dimension is low (가벼움, 매끄러움). */
  reversed: boolean;
  words: { much: string; little: string };
  example: Example;
};
export const INTENSITY_ROWS = {
  intensity_aroma: {
    thinking: "intensity",
    subject: { domain: "aroma", key: "*" },
    dimension: "aroma_intensity",
    reversed: false,
    words: { much: "향이 진한", little: "향이 은은한" },
    example: {
      answers: [
        "notice:aroma:cherry",
        "reaction:aroma:cherry:liked",
        "reason:aroma:cherry:liked:pronounced",
      ],
      levels: { aroma_intensity: 4 },
    },
  },
  intensity_sweetness: {
    thinking: "intensity",
    subject: taste("sweetness"),
    dimension: "sweetness",
    reversed: false,
    words: { much: "단맛이 꽤 있는", little: "단맛이 적은" },
    example: {
      answers: [
        "reaction:taste:sweetness:disliked",
        "reason:taste:sweetness:disliked:too_strong",
      ],
      levels: { sweetness: 4 },
    },
  },
  intensity_acidity: {
    thinking: "intensity",
    subject: taste("acidity"),
    dimension: "acidity",
    reversed: false,
    words: { much: "새콤함이 또렷한", little: "새콤함이 적은" },
    example: {
      answers: [
        "reaction:taste:acidity:liked",
      ],
      levels: { acidity: 4 },
    },
  },
  intensity_bitterness: {
    thinking: "intensity",
    subject: taste("bitterness"),
    dimension: null,
    reversed: false,
    words: { much: "쌉쌀함이 또렷한", little: "쌉쌀함이 적은" },
    example: {
      answers: [
        "reaction:taste:bitterness:liked",
      ],
    },
  },
  intensity_light: {
    thinking: "intensity",
    subject: mouth("light"),
    dimension: "body",
    reversed: true,
    words: { much: "가볍게 넘어가는", little: "묵직한" },
    example: {
      answers: ["notice:mouthfeel:light", "reaction:mouthfeel:light:liked"],
      levels: { body: 2 },
    },
  },
  intensity_heavy: {
    thinking: "intensity",
    subject: mouth("heavy"),
    dimension: "body",
    reversed: false,
    words: { much: "묵직한", little: "가벼운" },
    example: {
      answers: ["notice:mouthfeel:heavy", "reaction:mouthfeel:heavy:disliked"],
      levels: { body: 4 },
    },
  },
  intensity_smooth: {
    thinking: "intensity",
    subject: mouth("smooth"),
    dimension: "astringency",
    reversed: true,
    words: { much: "매끄럽게 넘어가는", little: "떫은" },
    example: {
      answers: ["notice:mouthfeel:smooth", "reaction:mouthfeel:smooth:liked"],
      levels: { astringency: 1 },
    },
  },
  intensity_drying: {
    thinking: "intensity",
    subject: mouth("drying"),
    dimension: "astringency",
    reversed: false,
    words: { much: "떫은", little: "떫은 느낌이 적은" },
    example: {
      answers: [
        "notice:mouthfeel:drying",
        "reaction:mouthfeel:drying:disliked",
      ],
      levels: { astringency: 2 },
    },
  },
  intensity_bubbles: {
    thinking: "intensity",
    subject: mouth("bubbles"),
    dimension: "carbonation",
    reversed: false,
    words: { much: "탄산이 강한", little: "탄산이 약한" },
    example: {
      answers: [
        "notice:mouthfeel:bubbles",
        "reaction:mouthfeel:bubbles:disliked",
      ],
      levels: { carbonation: 5 },
    },
  },
  intensity_warmth: {
    thinking: "intensity",
    subject: mouth("warmth"),
    dimension: "alcohol_presence",
    reversed: false,
    words: { much: "도수가 세게 느껴지는", little: "순한" },
    example: {
      answers: [
        "notice:mouthfeel:warmth",
        "reaction:mouthfeel:warmth:disliked",
      ],
      levels: { alcohol_presence: 2 },
    },
  },
  intensity_persistence: {
    thinking: "intensity",
    subject: { domain: "finish", key: "persistence" },
    dimension: "finish_length",
    reversed: false,
    words: { much: "여운이 긴", little: "여운이 짧은" },
    example: {
      answers: ["finish:pleasantLength"],
      levels: { finish_length: 4 },
    },
  },
} as const satisfies Record<string, IntensityRow>;
/* ---------------------------------------------------------------- 지속 */
type PersistenceRow = {
  thinking: "persistence";
  subject: Subject;
  /** Levers that make it linger; the sentence names them when the product has them. */
  levers: readonly LevelDimension[];
  why: string;
  clears: string;
  example: Example;
};
// 2026-11-06: the finish asks only the length, whether the mouth cleared and
// what came up the nose, so the rows for a taste, warmth or 떫음 that stayed
// are gone with their answers.
export const PERSISTENCE_ROWS = {
  persistence_heavy: {
    thinking: "persistence",
    subject: mouth("heavy"),
    levers: ["body", "carbonation", "acidity"],
    why: "걸쭉하거나 탁한 술은 삼킨 뒤 입안에 막이 남은 느낌을 줘요",
    clears: "탄산, 새콤함, 맑게 거른 술",
    example: {
      answers: [
        "notice:mouthfeel:heavy",
        "reaction:mouthfeel:heavy:disliked",
        "finish:heavy",
      ],
      levels: { body: 4 },
    },
  },
  persistence_clean: {
    thinking: "persistence",
    subject: { domain: "finish", key: "clean" },
    levers: ["sweetness", "acidity", "carbonation"],
    why: "당분이 적고 새콤함이나 탄산이 있으면 입안이 금방 정리돼요",
    clears: "마무리가 깔끔한 술",
    example: {
      answers: ["finish:clean"],
      levels: { sweetness: 1, acidity: 4 },
    },
  },
  // 코끝으로 올라오는 잔향: the aromas liked while drinking came back after
  // swallowing (retro-nasal).
  persistence_aroma_echo: {
    thinking: "persistence",
    subject: { domain: "finish", key: "aroma_echo" },
    levers: ["aroma_intensity", "finish_length"],
    why:
      "향 성분은 삼킨 뒤 목 뒤쪽을 타고 코로 올라와, 맛이 사라진 뒤에도 늦게까지 느껴져요",
    clears: "향이 약하거나 여운이 짧은 술",
    example: {
      answers: [
        "notice:aroma:cherry",
        "reaction:aroma:cherry:liked",
        "finish:aromaEcho",
      ],
      levels: { aroma_intensity: 4 },
    },
  },
  // 잡미나 거슬리는 냄새: an off note came up the nose after swallowing.
  persistence_off_flavor: {
    thinking: "persistence",
    subject: { domain: "finish", key: "off_flavor" },
    levers: ["flavour_clarity"],
    why:
      "발효나 숙성에서 생긴 잡내는 삼킨 뒤 목 뒤로 올라와 코에서 더 두드러져요",
    clears: "맑게 거른 술, 숙성이 잘 된 술",
    example: { answers: ["finish:offFlavor"] },
  },
} as const satisfies Record<string, PersistenceRow>;
/* ---------------------------------------------------------------- 구분 */
type DistinctionRow = {
  thinking: "distinction";
  felt: Subject;
  qualifier: string | null;
  /** The felt sensation is weak in the data, and the other one is there. */
  felt_low: readonly ProductCondition[];
  actual: readonly ProductCondition[];
  actual_ko: string;
  frame: "swap" | "apart";
  why: string;
  example: Example;
};
export const DISTINCTION_ROWS = {
  distinction_sweetness_sweet_scent: {
    thinking: "distinction",
    felt: taste("sweetness"),
    qualifier: null,
    felt_low: [level("sweetness", "low")],
    actual: [{ type: "scent", trait: "sweet_scent" }],
    actual_ko: "단 향",
    frame: "swap",
    why: "코로 느낀 달콤함을 혀의 단맛으로 느끼기 쉬워요",
    example: {
      answers: [
        "reaction:taste:sweetness:liked",
      ],
      levels: { sweetness: 1 },
      aromas: ["vanilla"],
    },
  },
  distinction_sweetness_coating: {
    thinking: "distinction",
    felt: taste("sweetness"),
    qualifier: null,
    felt_low: [level("sweetness", "low")],
    actual: [{ type: "trait", key: "mouth_coating" }, {
      type: "trait",
      key: "thick_consistency",
    }],
    actual_ko: "진득함",
    frame: "swap",
    why: "입안을 꽉 채우는 진한 느낌이 달게 느껴져요",
    example: {
      answers: [
        "reaction:taste:sweetness:liked",
      ],
      levels: { sweetness: 2 },
      texture: ["mouth_coating"],
    },
  },
  distinction_bitterness_astringency: {
    thinking: "distinction",
    felt: taste("bitterness"),
    qualifier: null,
    felt_low: [],
    actual: [level("astringency", "high")],
    actual_ko: "떫음",
    frame: "swap",
    why: "쓴맛은 혀 뒤에서, 떫음은 입안 전체가 조여요. 둘 다 불편해서 섞여요",
    example: {
      answers: [
        "reaction:taste:bitterness:disliked",
        "reason:taste:bitterness:disliked:too_strong",
      ],
      levels: { astringency: 5 },
    },
  },
  distinction_drying_acidity: {
    thinking: "distinction",
    felt: mouth("drying"),
    qualifier: null,
    felt_low: [level("astringency", "low")],
    actual: [level("acidity", "high")],
    actual_ko: "강한 신맛",
    frame: "swap",
    why: "신맛이 침을 돌게 해서 입안이 조이는 것처럼 느껴져요",
    example: {
      answers: [
        "notice:mouthfeel:drying",
        "reaction:mouthfeel:drying:disliked",
      ],
      levels: { astringency: 1, acidity: 5 },
    },
  },
  distinction_acidity_carbonation: {
    thinking: "distinction",
    felt: taste("acidity"),
    qualifier: null,
    felt_low: [level("acidity", "low")],
    actual: [level("carbonation", "high")],
    actual_ko: "탄산",
    frame: "swap",
    why: "탄산의 톡 쏘는 자극이 신맛처럼 느껴져요",
    example: {
      answers: [
        "reaction:taste:acidity:liked",
        "reason:taste:acidity:liked:pronounced",
      ],
      levels: { acidity: 1, carbonation: 5 },
    },
  },
  distinction_aroma_alcohol: {
    thinking: "distinction",
    felt: { domain: "aroma", key: "*" },
    qualifier: "excessive",
    felt_low: [],
    actual: [level("alcohol_presence", "high")],
    actual_ko: "알코올",
    frame: "swap",
    why: "코를 찌르는 알코올 기운이 향이 센 것처럼 느껴져요",
    example: {
      answers: [
        "notice:aroma:oak",
        "reaction:aroma:oak:disliked",
        "reason:aroma:oak:disliked:too_strong",
      ],
      levels: { alcohol_presence: 5 },
    },
  },
  distinction_warmth_spice: {
    thinking: "distinction",
    felt: mouth("warmth"),
    qualifier: null,
    felt_low: [level("alcohol_presence", "low")],
    actual: [{ type: "scent", trait: "sharp_scent" }, {
      type: "scent",
      trait: "warm_scent",
    }],
    actual_ko: "매운 향",
    frame: "swap",
    why: "매운 향이 알코올 열감처럼 느껴져요",
    example: {
      answers: [
        "notice:mouthfeel:warmth",
        "reaction:mouthfeel:warmth:disliked",
      ],
      levels: { alcohol_presence: 1 },
      aromas: ["ginger"],
    },
  },
  distinction_heavy_sugar_alcohol: {
    thinking: "distinction",
    felt: mouth("heavy"),
    qualifier: null,
    felt_low: [level("body", "low")],
    actual: [level("sweetness", "high"), level("alcohol_presence", "high")],
    actual_ko: "단맛이나 알코올",
    frame: "swap",
    why: "당분과 알코올도 입안을 무겁게 해요",
    example: {
      answers: ["notice:mouthfeel:heavy", "reaction:mouthfeel:heavy:disliked"],
      levels: { body: 1, sweetness: 5 },
    },
  },
  distinction_light_fizz_acid: {
    thinking: "distinction",
    felt: mouth("light"),
    qualifier: null,
    felt_low: [level("body", "high")],
    actual: [level("carbonation", "high"), level("acidity", "high")],
    actual_ko: "탄산이나 새콤함",
    frame: "swap",
    why: "톡 쏘고 새콤하면 묵직한 술도 가볍게 느껴져요",
    example: {
      answers: ["notice:mouthfeel:light", "reaction:mouthfeel:light:liked"],
      levels: { body: 5, carbonation: 5 },
    },
  },
  distinction_heavy_vs_smooth: {
    thinking: "distinction",
    felt: mouth("heavy"),
    qualifier: null,
    felt_low: [{ type: "trait", key: "surface_smooth" }],
    actual: [{ type: "trait", key: "full_volume" }, level("body", "high")],
    actual_ko: "부드러움",
    frame: "apart",
    why: "부드러운 것과 양이 많은 것은 다른 느낌이에요",
    example: {
      answers: ["notice:mouthfeel:heavy", "reaction:mouthfeel:heavy:disliked"],
      texture: ["surface_smooth", "full_volume"],
    },
  },
  distinction_smooth_vs_heavy: {
    thinking: "distinction",
    felt: mouth("smooth"),
    qualifier: null,
    felt_low: [{ type: "trait", key: "surface_smooth" }],
    actual: [{ type: "trait", key: "full_volume" }, level("body", "high")],
    actual_ko: "묵직함",
    frame: "apart",
    why: "부드러운 것과 양이 많은 것은 다른 느낌이에요",
    example: {
      answers: ["notice:mouthfeel:smooth", "reaction:mouthfeel:smooth:liked"],
      texture: ["surface_smooth"],
      levels: { body: 5 },
    },
  },
  distinction_smooth_coating: {
    thinking: "distinction",
    felt: mouth("smooth"),
    qualifier: null,
    felt_low: [level("astringency", "high")],
    actual: [{ type: "trait", key: "mouth_coating" }, {
      type: "trait",
      key: "thick_consistency",
    }],
    actual_ko: "진득함",
    frame: "swap",
    why: "입안을 감싸는 진득함이 매끄러움으로 느껴져요",
    example: {
      answers: ["notice:mouthfeel:smooth", "reaction:mouthfeel:smooth:liked"],
      levels: { astringency: 5 },
      texture: ["mouth_coating"],
    },
  },
  distinction_bubbles_acid_alcohol: {
    thinking: "distinction",
    felt: mouth("bubbles"),
    qualifier: null,
    felt_low: [level("carbonation", "low")],
    actual: [level("acidity", "high"), level("alcohol_presence", "high")],
    actual_ko: "신맛이나 알코올 자극",
    frame: "swap",
    why: "톡 쏘는 신맛이나 알코올 자극이 탄산처럼 느껴져요",
    example: {
      answers: [
        "notice:mouthfeel:bubbles",
        "reaction:mouthfeel:bubbles:disliked",
      ],
      levels: { carbonation: 1, acidity: 5 },
    },
  },
} as const satisfies Record<string, DistinctionRow>;
/* ---------------------------------------------------------------- 드러남 */
type ExposureRow = {
  thinking: "exposure";
  subject: Subject;
  /** Any of these being low exposes the subject. */
  low: readonly LevelDimension[];
  principle: string;
  example: Example;
};
export const EXPOSURE_ROWS = {
  exposure_acidity_by_sweetness: {
    thinking: "exposure",
    subject: taste("acidity"),
    low: ["sweetness"],
    principle: "단맛은 새콤함을 감싸 부드럽게 하는 편이에요",
    example: {
      answers: [
        "reaction:taste:acidity:liked",
        "reason:taste:acidity:liked:pronounced",
      ],
      levels: { sweetness: 1, acidity: 4 },
    },
  },
  exposure_bitterness_by_sweetness: {
    thinking: "exposure",
    subject: taste("bitterness"),
    low: ["sweetness"],
    principle: "단맛은 쌉쌀함을 둥글게 하는 편이에요",
    example: {
      answers: [
        "reaction:taste:bitterness:disliked",
        "reason:taste:bitterness:disliked:too_strong",
      ],
      levels: { sweetness: 1 },
    },
  },
  exposure_drying_by_sweetness: {
    thinking: "exposure",
    subject: mouth("drying"),
    low: ["sweetness"],
    principle: "단맛은 떫은 느낌을 감싸는 편이에요",
    example: {
      answers: [
        "notice:mouthfeel:drying",
        "reaction:mouthfeel:drying:disliked",
      ],
      levels: { sweetness: 1, astringency: 4 },
    },
  },
  exposure_warmth_by_sweetness_body: {
    thinking: "exposure",
    subject: mouth("warmth"),
    low: ["sweetness", "body"],
    principle: "단맛과 무게감은 알코올 기운을 감싸는 편이에요",
    example: {
      answers: [
        "notice:mouthfeel:warmth",
        "reaction:mouthfeel:warmth:disliked",
      ],
      levels: { sweetness: 1, body: 2, alcohol_presence: 4 },
    },
  },
  exposure_smooth_by_astringency: {
    thinking: "exposure",
    subject: mouth("smooth"),
    low: ["astringency"],
    principle: "떫은 느낌은 매끄러움을 거칠게 덮는 편이에요",
    example: {
      answers: ["notice:mouthfeel:smooth", "reaction:mouthfeel:smooth:liked"],
      levels: { astringency: 1 },
    },
  },
  exposure_aroma_by_alcohol: {
    thinking: "exposure",
    subject: { domain: "aroma", key: "*" },
    low: ["alcohol_presence"],
    principle: "알코올 기운은 향을 가리는 편이에요",
    example: {
      answers: [
        "notice:aroma:pear",
        "reaction:aroma:pear:liked",
        "reason:aroma:pear:liked:pronounced",
      ],
      levels: { alcohol_presence: 1 },
    },
  },
  exposure_sweetness_by_acidity: {
    thinking: "exposure",
    subject: taste("sweetness"),
    low: ["acidity"],
    principle: "새콤함은 단맛이 물리지 않게 받쳐주는 편이에요",
    example: {
      answers: [
        "reaction:taste:sweetness:disliked",
        "reason:taste:sweetness:disliked:too_strong",
      ],
      levels: { acidity: 1, sweetness: 4 },
    },
  },
  exposure_bubbles_by_sweetness_body: {
    thinking: "exposure",
    subject: mouth("bubbles"),
    low: ["sweetness", "body"],
    principle: "단맛과 무게감은 탄산의 따가움을 눅이는 편이에요",
    example: {
      answers: [
        "notice:mouthfeel:bubbles",
        "reaction:mouthfeel:bubbles:disliked",
      ],
      levels: { sweetness: 1, carbonation: 4 },
    },
  },
} as const satisfies Record<string, ExposureRow>;
/* ---------------------------------------------------------------- 가림 */
type MaskingRow = {
  thinking: "masking";
  masker: Subject;
  masked: Subject | { domain: "scent"; trait: string };
  masked_ko: string;
  /** Product evidence that the masked sensation is there at all. */
  masked_present: readonly ProductCondition[];
  principle: string;
  example: Example;
};
export const MASKING_ROWS = {
  masking_drying_smooth: {
    thinking: "masking",
    masker: mouth("drying"),
    masked: mouth("smooth"),
    masked_ko: "부드러운 질감",
    masked_present: [{ type: "trait", key: "surface_smooth" }],
    principle: "떫은 느낌은 부드러운 질감을 덮는 편이에요",
    example: {
      answers: [
        "notice:mouthfeel:drying",
        "reaction:mouthfeel:drying:disliked",
      ],
      levels: { astringency: 4 },
      texture: ["surface_smooth"],
    },
  },
  masking_drying_fruit: {
    thinking: "masking",
    masker: mouth("drying"),
    masked: { domain: "scent", trait: "fruit_scent" },
    masked_ko: "과일 향",
    masked_present: [{ type: "scent", trait: "fruit_scent" }],
    principle: "떫은 느낌은 과일 향을 가리는 편이에요",
    example: {
      answers: [
        "notice:aroma:berry",
        "reaction:aroma:berry:disliked",
        "reason:aroma:berry:disliked:too_weak",
      ],
      levels: { astringency: 5 },
      aromas: ["berry"],
    },
  },
  masking_sweetness_acidity: {
    thinking: "masking",
    masker: taste("sweetness"),
    masked: taste("acidity"),
    masked_ko: "새콤함",
    masked_present: [level("acidity", "mid"), level("acidity", "high")],
    principle: "단맛은 새콤함을 가리는 편이에요",
    example: {
      answers: [
        "reaction:taste:sweetness:disliked",
        "reason:taste:sweetness:disliked:disharmony",
      ],
      levels: { sweetness: 5, acidity: 3 },
    },
  },
  masking_sweetness_bitterness: {
    thinking: "masking",
    masker: taste("sweetness"),
    masked: taste("bitterness"),
    masked_ko: "쌉쌀함",
    masked_present: [],
    principle: "단맛은 쌉쌀함을 감싸 부드럽게 하는 편이에요",
    example: {
      answers: [
        "reaction:taste:bitterness:liked",
        "reason:taste:bitterness:liked:gentle",
      ],
      levels: { sweetness: 4 },
    },
  },
  masking_sweetness_drying: {
    thinking: "masking",
    masker: taste("sweetness"),
    masked: mouth("drying"),
    masked_ko: "떫은 느낌",
    masked_present: [level("astringency", "mid"), level("astringency", "high")],
    principle: "단맛은 떫은 느낌을 감싸는 편이에요",
    example: {
      answers: [
        "reaction:taste:sweetness:disliked",
        "reason:taste:sweetness:disliked:too_strong",
      ],
      levels: { sweetness: 5, astringency: 3 },
    },
  },
  masking_sweetness_warmth: {
    thinking: "masking",
    masker: taste("sweetness"),
    masked: mouth("warmth"),
    masked_ko: "알코올 기운",
    masked_present: [
      level("alcohol_presence", "mid"),
      level("alcohol_presence", "high"),
    ],
    principle: "단맛은 알코올 기운을 감싸 부드럽게 하는 편이에요",
    example: {
      answers: ["notice:mouthfeel:warmth", "reaction:mouthfeel:warmth:liked"],
      levels: { sweetness: 4, alcohol_presence: 4 },
    },
  },
  masking_warmth_aroma: {
    thinking: "masking",
    masker: mouth("warmth"),
    masked: { domain: "aroma", key: "*" },
    masked_ko: "향",
    masked_present: [],
    principle: "알코올 기운은 섬세한 향을 가리는 편이에요",
    example: {
      answers: [
        "notice:aroma:floral",
        "reaction:aroma:floral:disliked",
        "reason:aroma:floral:disliked:too_weak",
      ],
      levels: { alcohol_presence: 5 },
    },
  },
  masking_bitterness_sweetness: {
    thinking: "masking",
    masker: taste("bitterness"),
    masked: taste("sweetness"),
    masked_ko: "단맛",
    masked_present: [level("sweetness", "mid"), level("sweetness", "high")],
    principle: "쌉쌀함은 단맛을 눌러 버리는 편이에요",
    example: {
      answers: [
        "reaction:taste:bitterness:disliked",
        "reason:taste:bitterness:disliked:too_strong",
      ],
      levels: { sweetness: 3 },
    },
  },
  masking_bitterness_fruit: {
    thinking: "masking",
    masker: taste("bitterness"),
    masked: { domain: "scent", trait: "fruit_scent" },
    masked_ko: "과일 향",
    masked_present: [{ type: "scent", trait: "fruit_scent" }],
    principle: "쌉쌀함은 과일 향을 가리는 편이에요",
    example: {
      answers: [
        "reaction:taste:bitterness:disliked",
        "reason:taste:bitterness:disliked:disharmony",
      ],
      aromas: ["citrus"],
    },
  },
  masking_bubbles_sweetness: {
    thinking: "masking",
    masker: mouth("bubbles"),
    masked: taste("sweetness"),
    masked_ko: "단맛",
    masked_present: [level("sweetness", "mid"), level("sweetness", "high")],
    principle: "탄산은 단맛을 덜 느끼게 하는 편이에요",
    example: {
      answers: [
        "notice:mouthfeel:bubbles",
        "reaction:mouthfeel:bubbles:disliked",
      ],
      levels: { carbonation: 5, sweetness: 3 },
    },
  },
  masking_acidity_sweetness: {
    thinking: "masking",
    masker: taste("acidity"),
    masked: taste("sweetness"),
    masked_ko: "단맛",
    masked_present: [level("sweetness", "mid"), level("sweetness", "high")],
    principle: "새콤함은 단맛을 가리는 편이에요",
    example: {
      answers: [
        "reaction:taste:acidity:disliked",
        "reason:taste:acidity:disliked:too_strong",
      ],
      levels: { acidity: 5, sweetness: 3 },
    },
  },
  masking_heavy_acidity: {
    thinking: "masking",
    masker: mouth("heavy"),
    masked: taste("acidity"),
    masked_ko: "새콤함",
    masked_present: [level("acidity", "mid"), level("acidity", "high")],
    principle: "무게감은 새콤함의 산뜻함을 덮는 편이에요",
    example: {
      answers: ["notice:mouthfeel:heavy", "reaction:mouthfeel:heavy:disliked"],
      levels: { body: 5, acidity: 3 },
    },
  },
  masking_heavy_bubbles: {
    thinking: "masking",
    masker: mouth("heavy"),
    masked: mouth("bubbles"),
    masked_ko: "탄산",
    masked_present: [level("carbonation", "mid"), level("carbonation", "high")],
    principle: "무게감은 탄산의 청량함을 덮는 편이에요",
    example: {
      answers: ["notice:mouthfeel:heavy", "reaction:mouthfeel:heavy:disliked"],
      levels: { body: 5, carbonation: 3 },
    },
  },
  masking_heavy_warmth: {
    thinking: "masking",
    masker: mouth("heavy"),
    masked: mouth("warmth"),
    masked_ko: "알코올 기운",
    masked_present: [
      level("alcohol_presence", "mid"),
      level("alcohol_presence", "high"),
    ],
    principle: "무게감은 알코올 기운을 감싸는 편이에요",
    example: {
      answers: ["notice:mouthfeel:warmth", "reaction:mouthfeel:warmth:liked"],
      levels: { body: 5, alcohol_presence: 4 },
    },
  },
} as const satisfies Record<string, MaskingRow>;
/* ---------------------------------------------------------------- 조합 */
export type PairMember = Subject | { domain: "scent"; trait: string };
type CombinationRow = {
  thinking: "combination";
  kind: "good" | "burden" | "support";
  pair: readonly [PairMember, PairMember];
  principle: string;
  example: Example;
};
export const COMBINATION_ROWS = {
  combination_sweet_acid: {
    thinking: "combination",
    kind: "good",
    pair: [taste("sweetness"), taste("acidity")],
    principle:
      "단맛과 새콤함은 서로 받쳐주는 짝이에요. 둘이 같이 있어서 달기만 하지 않고 산뜻했을 거예요",
    example: {
      answers: [
        "reaction:taste:sweetness:liked",
        "reaction:taste:acidity:liked",
        "target:taste:sweetness:liked",
      ],
    },
  },
  combination_sweet_bitter: {
    thinking: "combination",
    kind: "good",
    pair: [taste("sweetness"), taste("bitterness")],
    principle: "단맛과 쌉쌀함은 서로를 받쳐 깊은 맛을 만드는 짝이에요",
    example: {
      answers: [
        "reaction:taste:sweetness:liked",
        "reaction:taste:bitterness:liked",
        "target:taste:sweetness:liked",
      ],
    },
  },
  combination_acid_fizz: {
    thinking: "combination",
    kind: "good",
    pair: [taste("acidity"), mouth("bubbles")],
    principle: "새콤함과 탄산은 같이 있을 때 가장 산뜻한 짝이에요",
    example: {
      answers: [
        "reaction:taste:acidity:liked",
        "notice:mouthfeel:bubbles",
        "reaction:mouthfeel:bubbles:liked",
      ],
    },
  },
  combination_sweet_scent_sweetness: {
    thinking: "combination",
    kind: "good",
    pair: [{ domain: "scent", trait: "sweet_scent" }, taste("sweetness")],
    principle: "단 향과 단맛은 서로를 키워 디저트 같은 인상을 만드는 짝이에요",
    example: {
      answers: [
        "notice:aroma:vanilla",
        "reaction:aroma:vanilla:liked",
        "reaction:taste:sweetness:liked",
      ],
    },
  },
  combination_fruit_scent_acidity: {
    thinking: "combination",
    kind: "good",
    pair: [{ domain: "scent", trait: "fruit_scent" }, taste("acidity")],
    principle: "과일 향과 새콤함은 갓 딴 과일 같은 인상을 만드는 짝이에요",
    example: {
      answers: [
        "notice:aroma:apple",
        "reaction:aroma:apple:liked",
        "reaction:taste:acidity:liked",
      ],
    },
  },
  combination_warmth_sweetness: {
    thinking: "combination",
    kind: "good",
    pair: [mouth("warmth"), taste("sweetness")],
    principle:
      "따뜻한 알코올 기운은 단맛과 함께일 때 포근하게 느껴지는 짝이에요",
    example: {
      answers: [
        "notice:mouthfeel:warmth",
        "reaction:mouthfeel:warmth:liked",
        "reaction:taste:sweetness:liked",
      ],
    },
  },
  combination_warmth_heavy: {
    thinking: "combination",
    kind: "good",
    pair: [mouth("warmth"), mouth("heavy")],
    principle:
      "따뜻한 알코올 기운은 묵직함과 함께일 때 풍성하게 느껴지는 짝이에요",
    example: {
      answers: [
        "notice:mouthfeel:warmth",
        "reaction:mouthfeel:warmth:liked",
        "notice:mouthfeel:heavy",
        "reaction:mouthfeel:heavy:liked",
      ],
    },
  },
  combination_aroma_pair: {
    thinking: "combination",
    kind: "good",
    pair: [{ domain: "aroma", key: "*" }, { domain: "aroma", key: "*" }],
    principle: "같이 있는 향들은 서로 겹쳐 하나의 인상이 돼요",
    example: {
      answers: [
        "notice:aroma:cherry",
        "reaction:aroma:cherry:liked",
        "notice:aroma:floral",
        "reaction:aroma:floral:liked",
        "target:aroma:cherry:liked",
      ],
    },
  },
  combination_bitter_drying: {
    thinking: "combination",
    kind: "burden",
    pair: [taste("bitterness"), mouth("drying")],
    principle: "쌉쌀함과 떫은 느낌은 겹치면 입안이 더 거칠게 느껴지는 짝이에요",
    example: {
      answers: [
        "reaction:taste:bitterness:disliked",
        "reason:taste:bitterness:disliked:too_strong",
        "notice:mouthfeel:drying",
        "reaction:mouthfeel:drying:disliked",
      ],
    },
  },
  combination_drying_warmth: {
    thinking: "combination",
    kind: "burden",
    pair: [mouth("drying"), mouth("warmth")],
    principle:
      "떫은 느낌과 알코올 기운은 겹치면 입안이 더 거칠게 느껴지는 짝이에요",
    example: {
      answers: [
        "notice:mouthfeel:drying",
        "reaction:mouthfeel:drying:disliked",
        "notice:mouthfeel:warmth",
        "reaction:mouthfeel:warmth:disliked",
      ],
    },
  },
  combination_sweet_heavy: {
    thinking: "combination",
    kind: "burden",
    pair: [taste("sweetness"), mouth("heavy")],
    principle: "단맛과 묵직함은 겹치면 금방 물리는 짝이에요",
    example: {
      answers: [
        "reaction:taste:sweetness:disliked",
        "reason:taste:sweetness:disliked:too_strong",
        "notice:mouthfeel:heavy",
        "reaction:mouthfeel:heavy:disliked",
      ],
    },
  },
  combination_warmth_bitter: {
    thinking: "combination",
    kind: "burden",
    pair: [mouth("warmth"), taste("bitterness")],
    principle: "알코올 기운과 쌉쌀함은 겹치면 목이 더 쓰게 느껴지는 짝이에요",
    example: {
      answers: [
        "notice:mouthfeel:warmth",
        "reaction:mouthfeel:warmth:disliked",
        "reaction:taste:bitterness:disliked",
        "reason:taste:bitterness:disliked:too_strong",
      ],
    },
  },
  combination_acid_fizz_burden: {
    thinking: "combination",
    kind: "burden",
    pair: [taste("acidity"), mouth("bubbles")],
    principle: "새콤함과 탄산은 겹치면 자극이 더 날카로워지는 짝이에요",
    example: {
      answers: [
        "reaction:taste:acidity:disliked",
        "reason:taste:acidity:disliked:too_strong",
        "notice:mouthfeel:bubbles",
        "reaction:mouthfeel:bubbles:disliked",
      ],
    },
  },
  combination_strong_aroma_warmth: {
    thinking: "combination",
    kind: "burden",
    pair: [{ domain: "aroma", key: "*" }, mouth("warmth")],
    principle: "센 향과 알코올 기운은 겹치면 코와 목이 같이 자극받는 짝이에요",
    example: {
      answers: [
        "notice:aroma:oak",
        "reaction:aroma:oak:disliked",
        "reason:aroma:oak:disliked:too_strong",
        "notice:mouthfeel:warmth",
        "reaction:mouthfeel:warmth:disliked",
      ],
    },
  },
  combination_support_sweet_acid: {
    thinking: "combination",
    kind: "support",
    pair: [taste("sweetness"), taste("acidity")],
    principle: "단맛과 새콤함은 서로가 물리지 않게 받쳐주는 짝이에요",
    example: {
      answers: [
        "reaction:taste:sweetness:liked",
        "reaction:taste:acidity:disliked",
        "reason:taste:acidity:disliked:too_strong",
      ],
    },
  },
  combination_support_sweet_bitter: {
    thinking: "combination",
    kind: "support",
    pair: [taste("sweetness"), taste("bitterness")],
    principle:
      "단맛과 쌉쌀함은 서로가 밋밋하거나 물리지 않게 받쳐주는 짝이에요",
    example: {
      answers: [
        "reaction:taste:bitterness:liked",
        "reaction:taste:sweetness:disliked",
        "reason:taste:sweetness:disliked:too_strong",
      ],
    },
  },
  combination_support_warmth_sweet: {
    thinking: "combination",
    kind: "support",
    pair: [mouth("warmth"), taste("sweetness")],
    principle: "단맛은 알코올 기운을 감싸 주는 짝이에요",
    example: {
      answers: [
        "reaction:taste:sweetness:liked",
        "notice:mouthfeel:warmth",
        "reaction:mouthfeel:warmth:disliked",
      ],
    },
  },
} as const satisfies Record<string, CombinationRow>;
/* ---------------------------------------------------------------- 유래 */
/**
 * Where a taste or mouthfeel comes from, by the 종류 표: every style explains
 * its levels (니고리의 무게감, 페일 에일의 쓴맛). Aromas are not explained by
 * their origin but by what they do to the senses (작용 below).
 */
type OriginRow = {
  thinking: "origin";
  trait: string;
  source_ko: string;
  principle: string;
  example: Example;
};
/* ---------------------------------------------------------------- 작용 */
/**
 * What an aroma does in the nose and mouth. An answer that names an aroma
 * without an experience of the drink ("이 향 자체가 좋았어요") is explained by
 * this: the effect of the aroma's family on the senses, staged in the reader's
 * nose and mouth, never where the aroma comes from. Each row covers nodes of
 * the catalog's aroma tree; an aroma takes the row of the nearest node on its
 * line (체리 hangs under 핵과 but is sour fruit, 수박 under 멜론 but fresh).
 */
export type EffectRow = {
  thinking: "effect";
  /** Nodes of catalog.json whose aromas this row explains. */
  nodes: readonly string[];
  /** The 취향어 noun: "'{noun}이 또렷한 {kind}'". */
  noun: string;
  /** A kind's own word for the same thing, when it has one (사케의 쌀의 구수함). */
  kind_nouns?: Readonly<Record<string, string>>;
  principle: string;
  /**
   * What the principle stands on: studies for the claims about the nose and
   * mouth (learned odor–taste links, detection thresholds, trigeminal
   * receptors), or a note when it is general aroma chemistry.
   */
  sources: readonly string[];
  example: Example;
};
const effectExample = (key: string): Example => ({
  answers: [
    `notice:aroma:${key}`,
    `reaction:aroma:${key}:liked`,
  ],
  aromas: [key],
});
export const EFFECT_ROWS = {
  effect_ripe_fruit: {
    thinking: "effect",
    nodes: [
      "stone_fruit",
      "tropical_fruit",
      "melon",
      "fresh_fig",
      "dried_fruit",
      "cooked_preserved_fruit",
      "ripe_fresh_fruit",
      "sweet_fresh_fruit",
      "yellow_fruit",
      "white_fruit",
      "ginjo_aroma",
    ],
    noun: "잘 익은 과일 향",
    principle:
      "잘 익은 과일 향은 코로만 맡아도 혀가 단맛을 기다리게 해서, 달지 않은 술도 포근하게 느껴져요",
    sources: [
      "learned odor sweetness: Stevenson, Boakes & Prescott 1999 https://researchers.mq.edu.au/en/publications/changes-in-odor-sweetness-resulting-from-implicit-learning-of-a-s/",
      "odor-induced taste enhancement review https://pmc.ncbi.nlm.nih.gov/articles/PMC8130510",
    ],
    example: effectExample("peach"),
  },
  effect_sour_fruit: {
    thinking: "effect",
    nodes: [
      "cherry",
      "plum",
      "berry",
      "red_fruit",
      "black_fruit",
      "pomegranate",
      "rhubarb",
      "wild_fruit",
      "lingonberry",
      "black_mulberry",
      "hawthorn",
    ],
    noun: "새콤달콤한 과일 향",
    principle:
      "새콤달콤한 과일 향은 그 과일의 새콤함까지 떠올리게 해서 입안이 깨어나고, 술이 경쾌하게 느껴져요",
    sources: [
      "food odors raise saliva flow, lemon among the strongest: INRA https://prodinra.inra.fr/record/332499",
      "sour-signalling odors and salivation: Morquecho-Campos et al. 2019 https://research.wur.nl/en/publications/impact-of-food-odors-signaling-specific-taste-qualities-and-macro/",
    ],
    example: effectExample("cherry"),
  },
  effect_fresh_fruit: {
    thinking: "effect",
    nodes: [
      "orchard_fruit",
      "citrus",
      "grape",
      "watermelon",
      "unripe_fruit",
      "fresh_fresh_fruit",
    ],
    noun: "상큼한 과일 향",
    principle:
      "상큼한 과일 향은 가볍고 빨리 퍼져 코에 먼저 닿고, 술이 마시기 전부터 산뜻하게 느껴져요",
    sources: [
      "general: light esters and aldehydes are the most volatile notes and reach the nose first; no single study",
    ],
    example: effectExample("pear"),
  },
  effect_floral: {
    thinking: "effect",
    nodes: ["floral"],
    noun: "꽃 향",
    principle:
      "꽃 향은 가볍게 피어올라 맛보다 먼저 첫인상을 정하고, 술이 실제보다 화사하게 느껴져요",
    sources: [
      "general: floral terpenes and esters are light, early notes; no single study",
    ],
    example: effectExample("floral"),
  },
  effect_smoke: {
    thinking: "effect",
    nodes: ["peat", "smoke"],
    noun: "스모키한 향",
    principle:
      "연기 냄새는 아주 적은 양에도 코가 먼저 알아채서 첫 향부터 분위기를 정하고, 반기는 쪽과 밀어내는 쪽이 갈려요",
    sources: [
      "guaiacol odor threshold about 23 µg/L in red wine (AWRI) https://www.awri.com.au/files/attachment/jan-feb-2013-awri-report",
      "smoke taint detection thresholds https://asev.org/abstract/olfactory-detection-thresholds-smoke-taint-red-wine",
    ],
    example: effectExample("peat"),
  },
  effect_sweet_scent: {
    thinking: "effect",
    nodes: ["sweet_aromatic", "chocolate", "coconut", "beeswax", "wax"],
    noun: "달큰한 향",
    principle:
      "바닐라나 캐러멜 냄새는 단맛과 함께 익힌 냄새라 코로만 맡아도 달게 느껴지고, 술이 실제 단맛보다 부드럽게 다가와요",
    sources: [
      "vanilla and caramel odors smell sweet and enhance sweetness by co-exposure: odor-induced taste enhancement review https://pmc.ncbi.nlm.nih.gov/articles/PMC8130510",
      "Stevenson, Boakes & Prescott 1999 https://researchers.mq.edu.au/en/publications/changes-in-odor-sweetness-resulting-from-implicit-learning-of-a-s/",
    ],
    example: effectExample("vanilla"),
  },
  effect_grain_nut: {
    thinking: "effect",
    nodes: ["cereal", "bread", "nutty", "toast"],
    noun: "구수한 향",
    kind_nouns: {
      sake: "쌀의 구수함",
      whisky: "구수한 맥아 향",
      takju: "곡물의 구수함",
      yakju: "곡물의 구수함",
      traditional: "곡물의 구수함",
    },
    principle:
      "곡물과 견과의 구수한 냄새는 매일 먹는 음식의 냄새라 코가 경계하지 않고, 술이 든든하게 느껴져요",
    sources: [
      "familiar odors are rated pleasant: Delplanque et al. 2008 https://www.unige.ch/fapse/e3lab/application/files/3017/7739/3067/2008-Delplanque_Grandjean_Chrea_Aymard_Cayeux_LeCalve_Velazco_Scherer__Sander-Chemical_Senses.pdf",
      "odor norms, familiarity–pleasantness R²=0.53 https://pmc.ncbi.nlm.nih.gov/articles/PMC4977894",
    ],
    example: effectExample("malt"),
  },
  effect_roast: {
    thinking: "effect",
    nodes: ["roasted"],
    noun: "볶은 향",
    principle:
      "볶은 냄새는 쌉쌀한 맛과 함께 다니던 냄새라 혀가 쌉쌀함을 준비하고, 술이 진하고 묵직하게 느껴져요",
    sources: [
      "odors take on the taste they were eaten with (learned congruency) https://pmc.ncbi.nlm.nih.gov/articles/PMC8130510",
    ],
    example: effectExample("coffee"),
  },
  effect_wood: {
    thinking: "effect",
    nodes: ["wood"],
    noun: "나무 향",
    kind_nouns: { wine: "오크 숙성 향", whisky: "오크 향" },
    principle:
      "나무 향은 천천히 올라와 오래 머물며 화사한 향 뒤를 받쳐서, 술이 차분하고 묵직하게 느껴져요",
    sources: [
      "general: oak lactones, vanillin and phenols are heavier, slower notes; no single study",
    ],
    example: effectExample("oak"),
  },
  effect_green: {
    thinking: "effect",
    nodes: ["herbal", "leaf", "tea", "essential_oil", "juniper"],
    noun: "허브 향",
    principle:
      "허브와 풀 냄새는 코를 상쾌하게 깨우고 입안까지 서늘한 느낌을 남겨서, 술이 깔끔하고 또렷하게 느껴져요",
    sources: [
      "menthol cooling through TRPM8 in trigeminal neurons https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9580369/",
    ],
    example: effectExample("herbal"),
  },
  effect_vegetal: {
    thinking: "effect",
    nodes: ["vegetal"],
    noun: "풋풋한 채소 향",
    principle:
      "풋풋한 채소 냄새는 날것을 떠올리게 해서 혀가 단맛보다 서늘한 쪽을 준비하고, 술이 덜 달게 느껴져요",
    sources: [
      "bell pepper pyrazine (IBMP) threshold 1–16 ng/L https://waterhouse.ucdavis.edu/node/586",
      "IBMP perception in wine https://oeno-one.eu/article/view/4492",
    ],
    example: effectExample("bell_pepper"),
  },
  effect_spice: {
    thinking: "effect",
    nodes: ["spice"],
    noun: "향신료 향",
    principle:
      "향신료 냄새는 혀의 따뜻한 자극과 함께 오던 냄새라 입안이 그 자극을 미리 떠올리고, 술이 도수보다 따뜻하게 느껴져요",
    sources: [
      "cinnamaldehyde acts on TRPA1 with menthol/capsaicin convergence in the trigeminal system https://pmc.ncbi.nlm.nih.gov/articles/PMC2254210",
      "odors take on the sensation they were eaten with (learned congruency) https://pmc.ncbi.nlm.nih.gov/articles/PMC8130510",
    ],
    example: effectExample("cinnamon"),
  },
  effect_mineral: {
    thinking: "effect",
    nodes: ["mineral"],
    noun: "미네랄 느낌",
    principle:
      "미네랄 느낌은 앞에 나서지 않고 뒤에서 선을 긋듯 남아서, 술이 깨끗하고 단단하게 느껴져요",
    sources: [
      "minerality is a perceptual construct (flint, fresh/acid, sea/shellfish clusters), not mineral uptake: Parr, Maltman, Easton & Ballester 2018 https://hal.inrae.fr/hal-02624486",
    ],
    example: effectExample("mineral"),
  },
  effect_earth: {
    thinking: "effect",
    nodes: ["earth", "mushroom"],
    noun: "흙 내음",
    principle:
      "흙과 버섯 냄새는 아주 적은 양으로도 느껴지고 분위기를 가라앉혀서, 술이 밝기보다 깊게 느껴져요",
    sources: [
      "geosmin detection threshold about 4–15 ng/L https://pmc.ncbi.nlm.nih.gov/articles/PMC11261619/",
      "https://halifaxwater.ca/geosmin",
    ],
    example: effectExample("earth"),
  },
  effect_dairy: {
    thinking: "effect",
    nodes: ["dairy"],
    noun: "크림 같은 향",
    principle:
      "유제품 냄새는 입안을 감싸는 촉감과 함께 익힌 냄새라, 코로만 맡아도 술이 부드럽고 둥글게 느껴져요",
    sources: [
      "retronasal cream odor raises creaminess and thickness: Bult et al. 2007 https://fis.tu-dresden.de/portal/en/publications/investigations-on-multimodal-sensory-integration(88cdf41c-92c0-4c53-9276-9408a55937a2).html",
      "butter odor and cheese creaminess https://fis.tu-dresden.de/portal/en/publications/modulation-of-sensory-perception-of-cheese-attributes-intensity-and-texture-liking-via-ortho-and-retronasal-odors(d16286ed-44b4-456a-a5ed-6bf4087016d1).html",
    ],
    example: effectExample("butter"),
  },
  effect_ferment: {
    thinking: "effect",
    nodes: ["fermentation"],
    noun: "발효 향",
    principle:
      "효모와 발효 냄새는 익숙하면서도 술이 살아 있다는 느낌을 줘서, 술이 깔끔하기보다 생생하게 느껴져요",
    sources: [
      "familiar odors are rated pleasant: Delplanque et al. 2008 https://www.unige.ch/fapse/e3lab/application/files/3017/7739/3067/2008-Delplanque_Grandjean_Chrea_Aymard_Cayeux_LeCalve_Velazco_Scherer__Sander-Chemical_Senses.pdf",
    ],
    example: effectExample("yeast"),
  },
  effect_savory: {
    thinking: "effect",
    nodes: ["savory"],
    noun: "감칠맛 나는 향",
    principle:
      "감칠맛 나는 음식의 냄새는 입안이 그 깊은 맛을 기다리게 해서, 술이 든든하고 깊게 느껴져요",
    sources: [
      "soy sauce odor induces and enhances saltiness: Chokumnoyporn et al. 2015 https://experts.illinois.edu/en/publications/soy-sauce-odour-induces-and-enhances-saltiness-perception/",
      "savory odorants enhancing saltiness and umami https://pmc.ncbi.nlm.nih.gov/articles/PMC6870243",
    ],
    example: effectExample("savory"),
  },
  effect_aged: {
    thinking: "effect",
    nodes: ["tobacco", "animalic", "incense", "aged_aromatic"],
    noun: "묵직한 향",
    principle:
      "담뱃잎이나 가죽처럼 마르고 낮은 냄새는 화사한 향 뒤에 남아 깊이를 더해서, 술이 깊고 오래된 느낌으로 다가와요",
    sources: [
      "general: leather and tobacco notes are low-volatility, late notes; no single study",
    ],
    example: effectExample("leather"),
  },
} as const satisfies Record<string, EffectRow>;
/** Row ids by thinking, for the validator and for the coverage test. */
export const KNOWLEDGE_ROWS = {
  ...INTENSITY_ROWS,
  ...PERSISTENCE_ROWS,
  ...DISTINCTION_ROWS,
  ...EXPOSURE_ROWS,
  ...MASKING_ROWS,
  masking_general: {
    thinking: "masking",
    masker: { domain: "aroma", key: "*" },
    masked: { domain: "aroma", key: "*" },
    masked_ko: "",
    masked_present: [],
    principle: "",
    example: {
      answers: [
        "notice:aroma:oak",
        "reaction:aroma:oak:disliked",
        "reason:aroma:oak:disliked:disharmony",
      ],
    },
  } as MaskingRow,
  ...COMBINATION_ROWS,
  ...EFFECT_ROWS,
  origin_style: {
    thinking: "origin",
    trait: "",
    source_ko: "",
    principle: "",
    example: {
      answers: [
        "reaction:taste:bitterness:liked",
      ],
      style: "orange_wine",
    },
  } as OriginRow,
} as const;

export type KnowledgeRowId = keyof typeof KNOWLEDGE_ROWS;
