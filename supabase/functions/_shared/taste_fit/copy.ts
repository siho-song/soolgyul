/**
 * What the badge says: a headline, one short sentence addressed by name, and
 * the hashtags: up to three that name the rows the bottle met (the reader's
 * likes, burdens or 적당했어요 bands), then up to three of the bottle's aromas.
 * The hashtags carry the specifics; the sentence only says whose they are.
 */
import { terms } from "../taste_card/dictionary.ts";
import type { TasteFitBadge } from "./judge.ts";
import type { FineDimension } from "./ledger.ts";

export type TasteFitCopy = {
  headline: string;
  tags: readonly string[];
  sentence: string;
};

/** Comfort rows and their hashtags: two words at most, the sensation named plainly. */
const GOOD: Record<string, string> = {
  effect_fresh_fruit: "#상큼한_과일향",
  effect_sour_fruit: "#새콤한_과일향",
  effect_ripe_fruit: "#농익은_과일향",
  effect_floral: "#은은한_꽃향",
  effect_sweet_scent: "#달큰한_향",
  effect_wood: "#오크향",
  effect_grain_nut: "#고소한_곡물향",
  effect_green: "#풋풋한_허브향",
  effect_roast: "#로스팅향",
  effect_smoke: "#스모키향",
  effect_vegetal: "#풋풋한_채소향",
  intensity_acidity: "#산뜻한_산미",
  intensity_light: "#가벼운_무게감",
  intensity_smooth: "#부드러운_목넘김",
  intensity_persistence: "#긴_여운",
  persistence_clean: "#깔끔한_끝맛",
  intensity_aroma: "#풍성한_향",
  intensity_warmth: "#또렷한_알코올감",
  persistence_aroma_echo: "#남는_잔향",
  combination_fruit_scent_acidity: "#싱그러운_과일향",
  combination_sweet_acid: "#새콤달콤",
  combination_sweet_scent_sweetness: "#달큰한_향",
  exposure_acidity_by_sweetness: "#드라이한_산미",
  exposure_aroma_by_alcohol: "#또렷한_향",
  exposure_smooth_by_astringency: "#매끈한_질감",
  exposure_warmth_by_sweetness_body: "#또렷한_열감",
  masking_heavy_warmth: "#든든한_무게감",
};

/** Burden rows and their hashtags. */
const BAD: Record<string, string> = {
  intensity_sweetness: "#진한_단맛",
  combination_sweet_heavy: "#달고_묵직함",
  masking_sweetness_acidity: "#묻힌_산미",
  intensity_heavy: "#묵직한_무게감",
  persistence_heavy: "#오래가는_묵직함",
  masking_heavy_warmth: "#센_타격감",
  masking_heavy_acidity: "#묻힌_산미",
  intensity_drying: "#강한_떫은맛",
  exposure_drying_by_sweetness: "#드라이",
  intensity_warmth: "#센_알코올감",
  exposure_warmth_by_sweetness_body: "#또렷한_열감",
  intensity_acidity: "#날카로운_산미",
  intensity_bubbles: "#강한_탄산",
  combination_acid_fizz_burden: "#톡쏘는_탄산",
};

/** 적당했어요 rows: "#적당한_단맛". */
const FINE_LABEL: Record<FineDimension, string> = {
  sweetness: "단맛",
  acidity: "산미",
  astringency: "떫은맛",
  body: "무게감",
  carbonation: "탄산",
  alcohol_presence: "알코올감",
  finish_length: "여운",
};

const AROMA_NAMES = new Map(
  terms("aroma").map((t) => [t.key, t.names?.ko] as const),
);

/** "#체리향", "#레몬_라임향"; an aroma the dictionary cannot name is left out. */
export function aromaTag(key: string): string | null {
  const name = AROMA_NAMES.get(key);
  return name ? `#${name.replace(/[·\s]+/g, "_")}향` : null;
}

export const HEADLINES: Record<TasteFitBadge, string> = {
  star: "딱 맞는 PICK !",
  caution: "아쉬운 PICK !",
  neutral: "무난한 PICK !",
  no_info: "아직 이 술의 정보가 없어요",
};

const NO_INFO_SENTENCE =
  "맛 정보가 아직 채워지지 않은 술이라 취향과 비교해 드리기 어려워요.";

/** "평소 민지님께서" or, for a reader without a display name, "평소". */
const reader = (name: string | null, suffix: string) =>
  name ? `${name}님${suffix}` : "";

function matchSentence(name: string | null): string {
  return `평소 ${
    reader(name, "께서 ")
  }좋아하신 특징들을 갖고 있어서 시도해 보셔도 괜찮아요.`;
}

function cautionSentence(name: string | null): string {
  return `평소 ${
    reader(name, "께서 ")
  }부담을 느끼신 특징들을 갖고 있어서 입에 안 맞을 수 있어요.`;
}

function fineSentence(name: string | null): string {
  return `평소 ${
    reader(name, "께서 ")
  }적당하다고 느끼신 특징들을 갖고 있어서 편하게 드셔도 괜찮아요.`;
}

function neutralSentence(name: string | null): string {
  const who = reader(name, "에게는 ");
  return `${who}특별히 호불호 갈릴 요소 없이, 무난하게 즐기기 좋은 술이에요.`;
}

export function composeCopy(
  badge: TasteFitBadge,
  hits: readonly string[],
  aromas: readonly string[],
  readerName: string | null,
): TasteFitCopy {
  const headline = HEADLINES[badge];
  if (badge === "no_info") {
    return { headline, tags: [], sentence: NO_INFO_SENTENCE };
  }
  const aromaTags = aromas.flatMap((key) => {
    const tag = aromaTag(key);
    return tag ? [tag] : [];
  }).slice(0, 3);
  if (badge === "star" || badge === "caution") {
    const table = badge === "star" ? GOOD : BAD;
    const rowTags = [
      ...new Set(hits.flatMap((row) => table[row] ? [table[row]] : [])),
    ].slice(0, 3);
    return {
      headline,
      tags: [...rowTags, ...aromaTags],
      sentence: rowTags.length === 0
        ? ""
        : badge === "star"
        ? matchSentence(readerName)
        : cautionSentence(readerName),
    };
  }
  const fineTags = hits.flatMap((row) => {
    const label = FINE_LABEL[row.replace(/^fine_/, "") as FineDimension];
    return label ? [`#적당한_${label}`] : [];
  }).slice(0, 3);
  return {
    headline,
    tags: [...fineTags, ...aromaTags],
    sentence: fineTags.length > 0
      ? fineSentence(readerName)
      : neutralSentence(readerName),
  };
}
