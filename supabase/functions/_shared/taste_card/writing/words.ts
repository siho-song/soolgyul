/**
 * The words a card is written in: what each sensation, kind and aroma is
 * called in running text, the level and lack phrases, and the words set in
 * bold. writing/reasons.ts decides which to use.
 */
import { serviceVocabulary as vocabulary } from "../dictionary/dictionary.ts";

/** The words a body may call a sensation by; the first one the text uses is set in bold. */
export const EMPHASIS_WORDS: Readonly<Record<string, readonly string[]>> = {
  sweetness: ["단맛"],
  acidity: ["산미", "신맛", "새콤함"],
  umami: ["감칠맛"],
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
  drying: [
    "타닌",
    "떫은 조임",
    "떫은맛",
    "떫은 맛",
    "떫은 느낌",
    "떫음",
    "떫은 성분",
  ],
  bubbles: ["탄산"],
  warmth: ["열감", "온기", "알코올 기운", "화끈하게"],
  persistence: ["여운"],
  aroma_echo: ["여운", "코로 올라오는 향"],
  clean: ["깔끔하게", "깔끔한", "마무리"],
  character: ["끝맛"],
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
  umami: "감칠맛",
  light: "가벼움",
  heavy: "무게감",
  smooth: "부드러움",
  drying: "떫음",
  bubbles: "탄산",
  warmth: "열감",
  persistence: "긴 여운",
  clean: "깔끔한 마무리",
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
  smoke: "스모키",
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
  white_flower: "bright",
  red_flower: "bright",
  violet: "bright",
  cherry_plum_blossom: "bright",
  pear: "bright",
  apple: "bright",
  citrus: "bright",
  peach: "bright",
  cherry: "bright",
  black_cherry: "bright",
  red_cherry: "bright",
  orange_tangerine: "bright",
  orange: "bright",
  tangerine_mandarin: "bright",
  berry: "bright",
  blackberry: "bright",
  raspberry: "bright",
  omija_bokbunja: "bright",
  watermelon: "bright",
  tropical_fruit: "rich",
  passion_fruit: "rich",
  jammy: "rich",
  marmalade: "rich",
  dried_fruit: "rich",
  dried_apricot: "rich",
  dried_fig: "rich",
  jujube: "rich",
  prune: "rich",
  fruit_syrup: "rich",
  ginjo_aroma: "bright",
  vanilla: "sweet",
  coconut: "sweet",
  chocolate: "sweet",
  dark_chocolate: "sweet",
  milk_chocolate: "sweet",
  cocoa: "sweet",
  caramel: "toasty",
  malt: "toasty",
  nutty: "toasty",
  pecan: "toasty",
  peanut: "toasty",
  chestnut: "toasty",
  sesame: "toasty",
  roasted: "toasty",
  bread: "toasty",
  brioche: "toasty",
  cereal: "toasty",
  rice: "toasty",
  scorched_rice: "toasty",
  barley: "toasty",
  wheat: "toasty",
  corn: "toasty",
  almond: "toasty",
  walnut: "toasty",
  hazelnut: "toasty",
  coffee: "toasty",
  nuruk: "toasty",
  wood: "oak",
  cedar: "oak",
  pine: "oak",
  sandalwood: "oak",
  oak: "oak",
  cherry_wood: "oak",
  peat: "smoke",
  smoke: "smoke",
  herbal: "green",
  rosemary: "green",
  mugwort: "green",
  juniper: "green",
  mint: "green",
  eucalyptus: "green",
  leaf: "green",
  grass: "green",
  medicinal_herb: "green",
};

const CATEGORY_FAMILY: Readonly<Record<string, Family>> = {
  fruit: "bright",
  botanical: "bright",
  bakery_sweets_nuts: "sweet",
};

export const short = (key: string) =>
  SHORT_LABEL[key] ?? AROMA_LABEL.get(key) ?? key;

/** The word running text calls an aroma by (writing/terms.ts looks the words up). */
export const aromaShort = short;

export const familyOf = (key: string): Family =>
  AROMA_FAMILY[key] ?? CATEGORY_FAMILY[AROMA_CATEGORY.get(key) ?? ""] ??
    "calm";

export function families(keys: readonly string[]): Family[] {
  const out: Family[] = [];
  for (const key of keys) {
    if (!out.includes(familyOf(key))) out.push(familyOf(key));
  }
  return out;
}

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
