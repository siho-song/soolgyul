/** In this glass: a row of the table of senses that held, said as what was together in the glass and what that did. */
import { aromaEffect } from "../../record_reading/facts/aroma_effects.ts";
import type { PerceptionRow } from "../evidence/perception.ts";
import { type GaugeAxis } from "../../record_reading/facts/facts.ts";
import { andJoin } from "../../korean.ts";
import { short } from "./words.ts";
import { AXIS, gaugeOf, nameOf } from "./reason_words.ts";

/** What a row of the table of senses names by a making key, as a thing. */
export const MADE_THING: Readonly<Record<string, string>> = {
  charred_cask: "안쪽을 태운 오크통",
  kimoto_starter: "기모토 방식",
  yamahai_starter: "야마하이 방식",
  undiluted: "물을 타지 않은 원주",
  unfiltered_claim: "여과하지 않은 술",
  unpasteurised: "살균하지 않은 술",
  coarse_filtered: "성글게 거른 술",
};

/** What made a row hold, as a thing and as the bare sense it is of: ["강한 탄산", "탄산"]. */
export type Thing = readonly [thing: string, sense: string];

export function thing(said: string): Thing | null {
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
      : [`비교적 높은 ${p[1]}% 도수`, "도수"];
  }
  // A sparkling kind as a fact of the bottle (kind:sparkling_wine). A kind's
  // tendency on a gauge (kind:whisky:sweetness:low) or its aroma
  // (kind:bourbon:vanilla) is read below like any other cause's.
  if (p[0] === "kind" && p.length === 2) return ["탄산", "탄산"];
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
 * A row of the table of senses as the first half of a sentence: what was in
 * the glass and what it did to the sense (진한 단맛이 산미를 부드럽게
 * 감싸서). The things are the subject and nothing is said to help or to
 * blame: what it came to, liked or minded, is the sense's own second half
 * (… 자극 없이 입안을 살짝만 깨워 줘요).
 */
export type RowWords = (things: string, senses: string) => string;

export const ROWS: Readonly<Record<string, RowWords>> = {
  // 어우러져 is praise: a minded line then says … 단맛이 혼자 앞으로 나서요.
  "단 향 → 단맛": (t) => `${t}의 달콤한 내음이 단맛을 한층 크게 느끼게 해서`,
  // A ripe grape beside the aromas is no 내음: the things then do it themselves.
  "익은 과일 향 → 단맛": (t) =>
    /향$/.test(t)
      ? `${t}의 잘 익은 과일 내음이 단맛을 한층 돋보이게 해서`
      : `${t}{이} 단맛을 한층 돋보이게 해서`,
  "적당히 높은 도수 → 단맛": (t) =>
    `${t}{으로} 알코올의 묵직한 기운이 더해져서`,
  "진득한 질감 → 단맛": () =>
    "입안을 묵직하게 감싸는 질감이 단맛을 한층 돋보이게 해서",
  "탄산 → 산미": (t) =>
    `${t}의 기포가 혀를 톡톡 두드리며 신맛을 더욱 도드라지게 만들어서`,
  "강한 산미 → 떫음": (t) => `${t}{이} 입안을 조이는 느낌을 거들어서`,
  "단맛·높은 도수 → 묵직함": (t) => `${t}{이} 입안에 무게감을 더해서`,
  "높은 도수·매운 향 → 스파이시": (t) => `${t}{이} 알싸한 자극을 더해서`,
  "탄 오크 향 → 피트": (t) => `${t}{이} 스모키 향과 겹쳐서`,
  "진한 향 → 긴 여운": (t) => `${t}{이} 입안에 오래 남아서`,
  "묵직한 바디 → 긴 여운": (t) => `${t}{으로} 술이 천천히 넘어가서`,
  "단맛 → 긴 여운": (t) => `${t}{이} 입안에 오래 머물러서`,
  "떫음 → 긴 여운": (t) => `${t}{이} 입안에 오래 남아서`,
  "감칠맛 → 긴 여운": (t) => `${t}{이} 입안에 오래 남아서`,
  "높은 도수 → 긴 여운": (t) => `${t}의 온기가 오래 남아서`,
  "높은 산미 → 긴 여운": (t) => `${t}{이} 입안의 풍미를 오래 붙잡아 두어서`,
  "피트 → 긴 여운": (t) => `${t}{이} 코에 오래 남아서`,
  "가벼운 바디 → 짧은 여운": (t) => `${t}{이라} 입안에 머무는 것이 적어서`,
  "단맛이 적음 → 짧은 여운": (_t, s) => `${s}{이} 적어 입안에 오래 남지 않아서`,
  "떫음이 적음 → 짧은 여운": (_t, s) => `${s}{이} 적어 입안에 오래 남지 않아서`,
  "감칠맛이 적음 → 짧은 여운": (_t, s) =>
    `${s}{이} 적어 입안에 오래 남지 않아서`,
  "옅은 향 → 짧은 여운": () => "향이 옅어 삼킨 뒤에 남는 것이 적어서",
  "탄산이 입을 씻어 줌 → 짧은 여운": (t) =>
    `${t}{이} 입안에 남은 맛을 씻어 내서`,
  "탄산·산미 → 가벼움": (t) => `${t}{이} 술의 무게감을 덜어 내서`,
  "전통 주모·진한 술 → 감칠맛": (t) =>
    // 기모토 방식이라 says what the drink is; a picked aroma is beside it.
    /향$/.test(t)
      ? `${t}{이} 깊은 맛을 거들어서`
      : `${t}{이라} 발효로 우러난 맛이 많아서`,
  "단맛이 산미를 감쌈": (t) => `${t}{이} 산미를 부드럽게 감싸서`,
  "산미·떫음이 단맛을 가림": (t) => `${t}{이} 단맛을 덜 도드라지게 해서`,
  "탄산이 단맛을 가림": (t) => `${t}{이} 단맛을 덜 느끼게 해서`,
  "묵직함이 산미를 덮음": (t) => `${t}{이} 산미를 차분하게 눌러서`,
  "단맛·진득함이 떫음을 감쌈": (t) => `${t}{이} 타닌을 부드럽게 감싸서`,
  "단맛·묵직함이 알코올 자극을 감쌈": (t) =>
    `${t}{이} 알싸한 자극을 부드럽게 감싸서`,
  "단맛·묵직함이 탄산을 둥글림": (t) => `${t}{이} 탄산의 자극을 순하게 해서`,
  "단맛이 없어 산미가 드러남": (_t, s) => `${s}{이} 적어 산미가 더 또렷해져서`,
  "산미·떫음이 순해 단맛이 드러남": (_t, s) =>
    `${s}{이} 순해 단맛을 가리지 않아서`,
  "단맛이 없어 떫음이 드러남": (_t, s) => `${s}{이} 적어 타닌이 더 선명해져서`,
  // 바디감이 적어 is not said of a weight: the answer was a light body.
  "단맛·묵직함이 없어 자극이 드러남": (_t, s) =>
    `${
      /^(바디감|무게감|질감)$/.test(s) ? "질감이 가벼워" : `${s}{이} 적어`
    } 알코올 자극을 감싸 줄 것이 없어서`,
  "단맛·묵직함이 없어 탄산이 드러남": (_t, s) =>
    `${s}{이} 적어 기포의 자극이 그대로 드러나서`,
};

/** Whether an aroma smells sweet of itself: 바닐라, 꿀, 캐러멜; not 장미 or 계피. */
export const sweetScent = (key: string): boolean =>
  aromaEffect(key) === "effect_sweet_scent";

/** Whether an aroma is of a sweet ripe fruit: 복숭아, 망고, 건포도, 자두; not 레몬 or 청사과. */
export const sweetFruit = (key: string): boolean =>
  aromaEffect(key) === "effect_ripe_fruit" || key === "plum";

/**
 * The rows that say an aroma raised the sweetness, with the aromas that can:
 * 장미 향이 단맛을 더 달게 and 레몬 향이 단맛을 살려 set a reason of one kind
 * against a result of another (the returned review, 2026-11-27).
 */
const SWEET_ONLY: Readonly<Record<string, (key: string) => boolean>> = {
  "단 향 → 단맛": sweetScent,
  "익은 과일 향 → 단맛": sweetFruit,
};

/**
 * A row that held as the first half of its sentence, or null when it names
 * nothing sayable.
 */
export function rowWords(rule: PerceptionRow): string | null {
  const words = ROWS[rule.name];
  if (!words) return null;
  const seen = new Set<string>();
  const sweet = SWEET_ONLY[rule.name];
  const things = rule.by.filter((b) => {
    const p = b.said.split(":");
    const aroma = p[0] === "aroma" ? p[1] : p.length === 3 ? p[2] : null;
    return !sweet || !aroma || p[2] === "climate" || sweet(aroma);
  }).flatMap((b) => {
    const t = thing(b.said);
    return t && !seen.has(t[0]) && seen.add(t[0]) ? [t] : [];
  }).slice(0, 2);
  if (!things.length) return null;
  return words(
    andJoin(things.map((t) => t[0])),
    andJoin([...new Set(things.map((t) => t[1]))]),
  );
}

/**
 * What the row did and what that came to, as one sentence. The second half
 * goes on without its subject when the first half has just named it as its
 * own (… 단맛이 가려지지 않아, 다른 맛을 누르고 혼자 앞으로 나서요).
 */
export function rowSentence(
  first: string,
  came_to: string,
  marks: readonly string[],
): string {
  const again = marks.flatMap((m) => [`${m}이 `, `${m}가 `]).find((open) =>
    came_to.startsWith(open) && first.includes(open)
  );
  return `${first}, ${again ? came_to.slice(again.length) : came_to}`;
}
