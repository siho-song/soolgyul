/** How a cause is named in a sentence: the word the app opens, and what it is (지역, 품종, 증류소, a strength, an age). */
import type { Cause } from "../evidence/evidence.ts";
import type { FactorKind } from "../evidence/identity.ts";
import {
  isRegionName,
  plainName,
  producerByKey,
  regionalStyleByKey,
} from "../../record_reading/dictionary/dictionary.ts";

/** The name of a cause without what the dictionary adds in brackets. */
export const bare = (c: Cause): Cause => ({ ...c, ko: plainName(c.ko) });

export const same = (a: Cause, b: { factor: FactorKind; key: string }) =>
  a.factor === b.factor && a.key === b.key;

/** The cause's name as a word the app can open. */
export const word = (c: Cause) => `**${c.ko}**`;

/** A making row said as what was done, where "…을 거친" does not say it. */
export const MADE: Readonly<Record<string, (k: string) => string>> = {
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
export const OWN_KIND = new Set([
  "coarse_filtered",
  "undiluted",
  "cask_strength",
  "small_batch",
]);

/** The cause as the one that gives a taste: **누룩**, 12년 숙성, 41%의 높은 도수. */
export function giver(c: Cause): string {
  if (c.factor === "abv") {
    // 11%의 높은 도수 reads as a mistake: it is high for its kind. 같은 종류
    // 가운데 높은 편인 was too long before a noun (the returned review,
    // 2026-11-24).
    return `비교적 ${c.key === "abv_low" ? "낮은" : "높은"} ${
      c.ko.replace(/^도수\s*/, "")
    } 도수`;
  }
  if (c.factor === "age") {
    return c.ko.includes("없음") ? "짧은 숙성" : `${c.ko} 숙성`;
  }
  return c.factor === "label_word" ? `'${word(c)}'` : word(c);
}

/** What a producer is, where the dictionary says: a distillery, a winery. */
export const HOUSE: Readonly<Record<string, string>> = {
  distillery: "증류소",
  winery: "와이너리",
};

/**
 * Whether a regional style is named by where it is from (토스카나, 남프랑스,
 * 보르도 좌안). As a drink it is then that place's wine (이 **남프랑스** 레드
 * 와인은): the place itself does not ripen, age or get made.
 */
export const namedByPlace = (c: Cause): boolean =>
  c.factor === "region_style" &&
  (isRegionName(c.ko) || Boolean(regionalStyleByKey(c.key)?.region_key));

/** Whether a regional style has a place of its own in the dictionary. */
export const placed = (c: Cause): boolean =>
  c.factor === "region_style" &&
  Boolean(regionalStyleByKey(c.key)?.region_key);

/**
 * The cause with what it is: **산 후안** 지역, **말벡** 품종, **라프로익**
 * 증류소, '**브뤼**' 표기, 41%의 높은 도수 (the user's word, 2026-11-22: say
 * whether it is a place or a grape). A style that is not a place's name
 * (샴페인, 모스카토 다스티) and a producer the dictionary does not say the
 * kind of are named alone.
 */
export function what(c: Cause): string {
  switch (c.factor) {
    case "region_style":
      // A style named as the dictionary names a place is that place's.
      return isRegionName(c.ko) ? `${word(c)} 지역` : word(c);
    case "grape":
      return `${word(c)} 품종`;
    case "label_word":
      return `'${word(c)}' 표기`;
    case "producer": {
      const house = HOUSE[producerByKey(c.key)?.house ?? ""];
      return house ? `${word(c)} ${house}` : word(c);
    }
    case "abv":
    case "age":
      return giver(c);
    default:
      return word(c);
  }
}

/**
 * The cause as the drink a taste is the mark of: **루아르** 지역 화이트
 * 와인, **짐빔** 증류소 위스키, **피노 누아** 와인, '**브뤼**' 스파클링
 * 와인. 루아르 지역의 특징이에요 read as a remark on the land (the returned
 * review, 2026-11-27).
 */
export function whose(c: Cause, kind: string): string {
  switch (c.factor) {
    case "region_style":
      return namedByPlace(c) ? `${what(c)} ${kind}` : what(c);
    case "grape":
      return `${word(c)} 와인`;
    case "label_word":
      return `'${word(c)}' ${kind}`;
    case "producer":
      return `${what(c)} ${kind}`;
    default:
      return what(c);
  }
}

export const causeKey = (c: { factor: FactorKind; key: string }) =>
  `${c.factor}:${c.key}`;
