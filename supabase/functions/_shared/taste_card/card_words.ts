/**
 * The words a card is written in: what each sensation, kind and aroma is
 * called in running text, the level and lack phrases, and the words set in
 * bold. card_writing.ts decides which to use.
 */
import { serviceVocabulary as vocabulary, terms } from "./dictionary.ts";
import { andJoin } from "./korean.ts";

/** The words a body may call a sensation by; the first one the text uses is set in bold. */
export const EMPHASIS_WORDS: Readonly<Record<string, readonly string[]>> = {
  sweetness: ["단맛"],
  acidity: ["산미", "신맛", "새콤함"],
  bitterness: ["쌉쌀함", "쓴맛"],
  light: ["가벼움", "가볍게", "가벼운 느낌", "가벼운", "가볍고", "경쾌하게"],
  heavy: ["무게감", "묵직함", "무게", "무겁게", "묵직하게", "묵직한"],
  smooth: [
    "부드러움",
    "매끄러운 질감",
    "매끄러운 촉감",
    "질감",
    "밋밋하게",
    "매끄럽게",
    "매끄럽다",
  ],
  drying: ["떫은 조임", "떫은맛", "떫은 맛", "떫은 느낌", "떫음", "떫은 성분"],
  bubbles: ["탄산"],
  warmth: ["열감", "온기", "알코올 기운", "화끈하게"],
  persistence: ["여운"],
  aroma_echo: ["여운", "코로 올라오는 향"],
  clean: ["깔끔하게", "깔끔한", "마무리"],
  off_flavor: ["잡내"],
};

/** The bottle's word for a sensation, set in bold only when the text never names the sensation itself. */
export const EMPHASIS_FALLBACK: Readonly<Record<string, readonly string[]>> = {
  drying: ["타닌"],
};

/* ---------------------------------------------------- subject words */

/** Where the summary names a sensation differently from the paragraphs. */
export const SUMMARY_LABEL: Readonly<Record<string, string>> = {
  drying: "떫은 맛",
  warmth: "알코올 열감",
};

export const KIND_LABEL: Readonly<Record<string, string>> = {
  wine: "와인",
  sake: "사케",
  whisky: "위스키",
  takju: "막걸리",
  yakju: "약주",
  traditional: "전통주",
};

/** Styles people name as a kind of their own (샴페인). */
export const STYLE_KIND_LABEL: Readonly<Record<string, string>> = {
  champagne_sparkling: "샴페인",
};

export const SUBJECT_LABEL: Readonly<Record<string, string>> = {
  sweetness: "단맛",
  acidity: "산미",
  bitterness: "쓴맛",
  light: "가벼움",
  heavy: "무게감",
  smooth: "부드러움",
  drying: "떫음",
  bubbles: "탄산",
  warmth: "열감",
  persistence: "긴 여운",
  clean: "깔끔한 마무리",
  aroma_echo: "향",
  off_flavor: "잡내",
};

/* ----------------------------------------------------- placeholders */

const AROMA_LABEL = new Map(
  (vocabulary as { groups: { key: string; label_ko: string }[] }).groups.map((
    g,
  ) => [g.key, g.label_ko]),
);

const AROMA_CATEGORY = new Map(
  (vocabulary as { groups: { key: string; category_key?: string }[] }).groups
    .map((g) => [g.key, g.category_key ?? ""]),
);

/** Shorter words than the vocabulary labels for running text. */
const SHORT_LABEL: Readonly<Record<string, string>> = {
  floral: "꽃",
  fermentation: "발효",
  aged_aromatic: "진한 양주",
  smoke: "스모키",
  orange_tangerine: "오렌지",
  berry: "베리",
  nutty: "견과",
  juniper: "주니퍼",
};

export type Family =
  | "bright"
  | "rich"
  | "sweet"
  | "toasty"
  | "oak"
  | "calm"
  | "smoke"
  | "green";

const AROMA_FAMILY: Readonly<Record<string, Family>> = {
  floral: "bright",
  pear: "bright",
  apple: "bright",
  citrus: "bright",
  peach: "bright",
  cherry: "bright",
  orange_tangerine: "bright",
  berry: "bright",
  watermelon: "bright",
  tropical_fruit: "rich",
  jammy: "rich",
  dried_fruit: "rich",
  fruit_syrup: "rich",
  ginjo_aroma: "bright",
  vanilla: "sweet",
  coconut: "sweet",
  chocolate: "sweet",
  caramel: "toasty",
  malt: "toasty",
  nutty: "toasty",
  roasted: "toasty",
  bread: "toasty",
  cereal: "toasty",
  rice: "toasty",
  barley: "toasty",
  wheat: "toasty",
  corn: "toasty",
  almond: "toasty",
  walnut: "toasty",
  hazelnut: "toasty",
  coffee: "toasty",
  nuruk: "toasty",
  wood: "oak",
  oak: "oak",
  cherry_wood: "oak",
  peat: "smoke",
  smoke: "smoke",
  herbal: "green",
  juniper: "green",
  mint: "green",
  leaf: "green",
  medicinal_herb: "green",
};

const CATEGORY_FAMILY: Readonly<Record<string, Family>> = {
  fruit: "bright",
  botanical: "bright",
  bakery_sweets_nuts: "sweet",
};

/** How each family reads in running text ("꽃과 배의 화사함"). */
export const FAMILY_WORDS: Readonly<
  Record<Family, { adj: string; noun: string }>
> = {
  bright: { adj: "화사한", noun: "화사함" },
  rich: { adj: "잘 익은 과일", noun: "농익은 풍성함" },
  sweet: { adj: "달큰한", noun: "달큰함" },
  toasty: { adj: "구수한", noun: "구수함" },
  oak: { adj: "차분한", noun: "차분함" },
  calm: { adj: "차분한", noun: "차분함" },
  smoke: { adj: "스모키한", noun: "스모키함" },
  green: { adj: "싱그러운", noun: "싱그러움" },
};

export const short = (key: string) =>
  SHORT_LABEL[key] ?? AROMA_LABEL.get(key) ?? key;

/** The word running text calls an aroma by (card_terms.ts looks the words up). */
export const aromaShort = short;

export const familyOf = (key: string): Family =>
  AROMA_FAMILY[key] ?? CATEGORY_FAMILY[AROMA_CATEGORY.get(key) ?? ""] ??
    "calm";

/** The aroma's kind for a subtitle: "과일 향" for a fruit, else its family ("화사한 향"). */
export const aromaKind = (key: string) =>
  AROMA_CATEGORY.get(key) === "fruit"
    ? "과일 향"
    : `${FAMILY_WORDS[familyOf(key)].adj} 향`;

export function families(keys: readonly string[]): Family[] {
  const out: Family[] = [];
  for (const key of keys) {
    if (!out.includes(familyOf(key))) out.push(familyOf(key));
  }
  return out;
}

export const shorts = (keys: readonly string[]) => keys.map(short).join("·");

export const shortsAnd = (keys: readonly string[]) => andJoin(keys.map(short));

export const shortsComma = (keys: readonly string[]) =>
  keys.map(short).join(", ");

/** Two groups joined by 과/와, more as a comma list. */
export const familyGroups = (groups: readonly string[]) =>
  groups.length === 2 ? andJoin(groups) : groups.join(", ");

export const aromaList = (keys: readonly string[]) =>
  keys.length ? `${shorts(keys)} 향` : "";

/** "A 향과 B 향", "A·B 향과 C 향". */
export const aromaPairList = (keys: readonly string[]) =>
  keys.length < 2
    ? aromaList(keys)
    : `${shorts(keys.slice(0, -1))} 향과 ${short(keys[keys.length - 1])} 향`;

/** Words for a product level in the 사실 sentence, by dimension. */
type LevelWords = {
  most?: string;
  much: string;
  mid: string;
  little: string;
  none: string;
};

export const LEVEL_WORDS: Readonly<Record<string, LevelWords>> = {
  acidity: {
    most: "새콤함이 아주 또렷한",
    much: "새콤함이 또렷한",
    mid: "새콤함이 적당히 있는",
    little: "새콤함이 적은",
    none: "새콤함이 있는",
  },
  sweetness: {
    most: "단맛이 아주 진한",
    much: "단맛이 꽤 있는",
    mid: "단맛이 적당히 있는",
    little: "단맛이 적은",
    none: "단맛이 있는",
  },
  astringency: {
    most: "떫은 맛이 아주 센",
    much: "떫은 맛이 센",
    mid: "떫은 맛이 적당히 있는",
    little: "떫은 맛이 적은",
    none: "떫은 맛이 있는",
  },
};

export function levelWord(
  dimension: string,
  level: number | undefined,
): string {
  const words = LEVEL_WORDS[dimension];
  if (!words) return "";
  if (level === undefined) return words.none;
  if (level >= 5 && words.most) return words.most;
  return level >= 4 ? words.much : level <= 2 ? words.little : words.mid;
}

/* ------------------------------------------------- 더 있었으면 (the lack) */

export const LACK_WORDS: Readonly<
  Record<string, { noun: string; rich: string }>
> = {
  sweetness: { noun: "단맛", rich: "단" },
  acidity: { noun: "산미", rich: "새콤한" },
  bitterness: { noun: "쓴맛", rich: "쌉쌀한" },
};

/**
 * The lack beside another taste (c). `cause` is why a higher c makes the
 * subject taste feel weaker (the covering direction, c → subject).
 */
type LackRole = {
  cause: (c: string, coverKeys: readonly string[]) => string;
  coveredEffect: string;
  heldEffect: string;
};

export const LACK_ROLES: Readonly<Record<string, LackRole>> = {
  sweetness: {
    cause: (c) => `단맛은 ${c}{과} 균형을 이루기 때문에`,
    coveredEffect: "실제 당도가 같아도 단맛이 훨씬 적게 느껴져요",
    heldEffect: "실제 당도보다 단맛이 덜 느껴져요",
  },
  acidity: {
    cause: (c, keys) =>
      keys.length > 1
        ? `${c}{은} 둘 다 산미의 산뜻함을 덮는 맛이기 때문에`
        : keys[0] === "sweetness"
        ? "단맛은 산미의 신 자극을 둥글게 감싸기 때문에"
        : "쓴맛은 끝에 오래 남아 산미의 산뜻함을 덮기 때문에",
    coveredEffect: "실제 양이 같아도 산미가 훨씬 적게 느껴져요",
    heldEffect: "실제 양보다 산미가 덜 느껴져요",
  },
  bitterness: {
    cause: (c, keys) =>
      keys.length > 1
        ? `${c}{은} 둘 다 쓴맛을 앞에서 가리는 맛이기 때문에`
        : keys[0] === "sweetness"
        ? "단맛은 쓴맛을 둥글게 감싸 눌러 주기 때문에"
        : "산미는 입안을 먼저 치고 들어와 쓴맛을 뒤로 밀어내기 때문에",
    coveredEffect: "실제 양이 같아도 쓴맛이 훨씬 적게 느껴져요",
    heldEffect: "실제 양보다 쓴맛이 덜 느껴져요",
  },
};

/** How the drink was distilled, named in the fact (a glossary tip explains the term). */
export const DISTILLATION_NAMES: ReadonlyMap<string, string> = new Map(
  terms("process").filter((t) =>
    [
      "pot_distillation",
      "column_distillation",
      "atmospheric_distillation",
      "vacuum_distillation",
    ].includes(t.key)
  ).map((t) => [t.key, t.names.ko]),
);

/** How a paragraph names each taste or mouthfeel subject the 종류 표 explains. */
export const SUBJECT_WORDS: Readonly<
  Record<string, {
    noun: string;
    liked: string;
    burden: string;
  }>
> = {
  sweetness: {
    noun: "단맛",
    liked: "입안을 감싸는 단맛",
    burden: "도드라지게 튀는 단맛",
  },
  acidity: {
    noun: "신맛",
    liked: "입안을 깨우는 산뜻한 산미",
    burden: "혀를 찌르는 강한 신맛",
  },
  bitterness: {
    noun: "쓴맛",
    liked: "끝맛을 정리하는 쌉쌀함",
    burden: "끝까지 입안에 남는 쓴맛",
  },
  light: {
    noun: "가벼움",
    liked: "가볍고 깔끔한 목넘김",
    burden: "물처럼 밋밋한 가벼움",
  },
  heavy: {
    noun: "무게감",
    liked: "입안을 채우는 든든한 무게감",
    burden: "입안을 짓누르는 무게감",
  },
  smooth: {
    noun: "부드러움",
    liked: "걸리는 것 없는 매끄러운 질감",
    burden: "포인트 없이 밋밋한 질감",
  },
  drying: {
    noun: "떫은 맛",
    liked: "입안을 기분 좋게 조이는 떫은맛",
    burden: "향과 맛을 가로막는 떫은맛",
  },
  bubbles: {
    noun: "탄산",
    liked: "기분 좋게 톡 쏘는 탄산",
    burden: "맛을 가릴 만큼 쏘는 탄산",
  },
  warmth: {
    noun: "열감",
    liked: "은은하게 퍼지는 따뜻한 온기",
    burden: "목을 타고 확 치고 올라오는 열감",
  },
};
