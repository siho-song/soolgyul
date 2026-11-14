/**
 * What the verdict says: a headline, one short sentence addressed by name,
 * and the hashtags: up to three that name what the verdict rests on, then up
 * to three of the bottle's aromas. A dimension is named by where the bottle
 * stands among its own kind ("#묵직한_무게감" is heavy for a red wine, not
 * heavy among all drinks). The hashtags carry the specifics; the sentence
 * says how they relate to the reader's records.
 *
 * A bottle that is not judged gets a headline and a sentence that say why,
 * and no face: its kind is one the reader has no record of, it shares no
 * measured dimension with their records, or it has no data.
 */
import { terms } from "../taste_card/dictionary/dictionary.ts";
import type { AromaFamily, PlaceAxis } from "../taste_card/facts/kind_place.ts";
import { EFFECT_ROWS } from "../taste_card/findings/knowledge.ts";
import { josa } from "../taste_card/writing/korean.ts";
import type { Reason, TasteFitBadge, Verdict } from "./judge.ts";

type TasteFitCopy = {
  headline: string;
  tags: readonly string[];
  sentence: string;
};

/** A dimension at the low, middle and high third of the bottle's kind. */
const AXIS_TAGS: Record<PlaceAxis, readonly [string, string, string]> = {
  sweetness: ["#은은한_단맛", "#적당한_단맛", "#또렷한_단맛"],
  acidity: ["#부드러운_산미", "#적당한_산미", "#산뜻한_산미"],
  bitterness: ["#옅은_쌉쌀함", "#적당한_쌉쌀함", "#또렷한_쌉쌀함"],
  astringency: ["#매끈한_질감", "#적당한_떫은맛", "#또렷한_떫은맛"],
  body: ["#가벼운_무게감", "#적당한_무게감", "#묵직한_무게감"],
  carbonation: ["#잔잔한_탄산", "#적당한_탄산", "#톡쏘는_탄산"],
  alcohol: ["#순한_알코올감", "#적당한_알코올감", "#또렷한_알코올감"],
  finish_length: ["#짧은_여운", "#적당한_여운", "#긴_여운"],
  finish_cleanliness: ["#진한_끝맛", "#적당한_끝맛", "#깔끔한_끝맛"],
  aroma_intensity: ["#은은한_향", "#적당한_향", "#풍성한_향"],
};

/** The same places said as what the reader minded: too little, or too much. */
const BURDEN_TAGS: Partial<
  Record<PlaceAxis, readonly [string | null, string | null]>
> = {
  sweetness: ["#옅은_단맛", "#진한_단맛"],
  acidity: ["#약한_산미", "#날카로운_산미"],
  bitterness: [null, "#강한_쌉쌀함"],
  astringency: [null, "#강한_떫은맛"],
  carbonation: ["#약한_탄산", "#강한_탄산"],
  alcohol: [null, "#센_알코올감"],
};

const FAMILY_TAGS: Partial<Record<AromaFamily, string>> = {
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
};

const LEVEL_INDEX = { low: 0, mid: 1, high: 2 } as const;

function reasonTag(reason: Reason, badge: TasteFitBadge): string {
  if ("family" in reason) {
    return FAMILY_TAGS[reason.family] ??
      `#${EFFECT_ROWS[reason.family].noun.replace(/\s+/g, "_")}`;
  }
  const minded = badge === "caution" && reason.level !== "mid"
    ? BURDEN_TAGS[reason.axis]?.[reason.level === "low" ? 0 : 1]
    : null;
  return minded ?? AXIS_TAGS[reason.axis][LEVEL_INDEX[reason.level]];
}

const AROMA_NAMES = new Map(
  terms("aroma").map((t) => [t.key, t.names?.ko] as const),
);

/** "#체리향", "#레몬_라임향"; an aroma the dictionary cannot name is left out. */
function aromaTag(key: string): string | null {
  const name = AROMA_NAMES.get(key);
  return name ? `#${name.replace(/[·\s]+/g, "_")}향` : null;
}

const HEADLINES: Record<TasteFitBadge, string> = {
  star: "딱 맞는 PICK",
  neutral: "무난한 PICK",
  unfamiliar: "낯선 PICK",
  caution: "아쉬운 PICK",
  no_info: "아직 이 술의 정보가 없어요",
};

/** "민지님께서 " or, for a reader without a display name, nothing. */
const reader = (name: string | null, suffix: string) =>
  name ? `${name}님${suffix}` : "";

function unjudged(verdict: Verdict): TasteFitCopy {
  switch (verdict.unjudged) {
    case "no_record": {
      const kind = verdict.group ?? "이 종류";
      return {
        headline: `아직 ${kind} 기록이 없어요`,
        tags: [],
        // Said as getting to know the reader, and tied to a day they drink
        // one anyway: the copy never asks anyone to drink this bottle.
        sentence:
          `아직 마셔본 ${kind} 기록이 없어서, 평소 입맛과 잘 맞을지 알아가는 단계예요. ` +
          `${
            josa(`${kind}{을}`)
          } 드신 날 가벼운 감상이라도 남겨 주시면, 다음부턴 취향 궁합을 콕 짚어 드릴게요!`,
      };
    }
    case "nothing_shared":
      return {
        headline: "비교할 정보가 부족해요",
        tags: [],
        sentence:
          "이 술에 채워진 맛 정보가 기록하신 내용과 겹치지 않아 비교하지 못했어요.",
      };
    default:
      return {
        headline: HEADLINES.no_info,
        tags: [],
        sentence:
          "맛 정보가 아직 채워지지 않은 술이라 취향과 비교해 드리기 어려워요.",
      };
  }
}

function sentence(verdict: Verdict, name: string | null): string {
  const kind = verdict.group ?? "술";
  switch (verdict.badge) {
    case "star":
      return `평소 ${
        reader(name, "께서 ")
      }좋아하신 특징들을 갖고 있어서 시도해 보셔도 괜찮아요.`;
    case "caution":
      return `평소 ${
        reader(name, "께서 ")
      }부담을 느끼신 특징들을 갖고 있어서 입에 안 맞을 수 있어요.`;
    case "unfamiliar":
      return josa(
        `평소 ${
          reader(name, "께서 ")
        }좋아하신 ${kind}{과}는 꽤 다른 특징이 있어요. 부담이라고 하신 적은 없는, 아직 기록에 없는 쪽이에요.`,
      );
    default:
      return verdict.reasons.length > 0
        ? josa(
          `평소 ${
            reader(name, "께서 ")
          }좋아하신 ${kind}{과} 크게 다르지 않아서, 무난하게 즐기기 좋은 술이에요.`,
        )
        : josa(
          `${
            reader(name, "께서 ")
          }기록하신 ${kind}{과} 견주어 눈에 띄게 다른 점도, 부담이라고 하신 특징도 없는 술이에요.`,
        );
  }
}

export function composeCopy(
  verdict: Verdict,
  readerName: string | null,
): TasteFitCopy {
  if (verdict.badge === "no_info") return unjudged(verdict);
  const reasonTags = [
    ...new Set(verdict.reasons.map((r) => reasonTag(r, verdict.badge))),
  ].slice(0, 3);
  const aromaTags = verdict.aromas.flatMap((key) => {
    const tag = aromaTag(key);
    return tag ? [tag] : [];
  }).slice(0, 3);
  return {
    headline: HEADLINES[verdict.badge],
    tags: [...new Set([...reasonTags, ...aromaTags])],
    sentence: sentence(verdict, readerName),
  };
}
