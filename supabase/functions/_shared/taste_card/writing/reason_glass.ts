/** In this glass: a row of the table of senses that held, said as what was together in the glass and what that did. */
import type { PerceptionRow } from "../evidence/perception.ts";
import { type GaugeAxis } from "../../record_reading/facts/facts.ts";
import type { Section } from "../selection/selection.ts";
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
export type RowWords = {
  head: (things: string, senses: string) => string;
  does: string | ((senses: string) => string);
};

export const WITH = (things: string) => `${things}{이} 함께 있어서`;

export const LESS = (_things: string, senses: string) => `${senses}{이} 적어서`;

export const r = (
  head: RowWords["head"],
  does: RowWords["does"],
): RowWords => ({
  head,
  does,
});

export const ROWS: Readonly<Record<string, RowWords>> = {
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
export const COMMON = new Set([
  "입안",
  "한 ",
  "모금",
  "다음",
  "술이",
  "맛이",
  "향이",
]);

/**
 * What a relation in the glass does and what that came to, as one clause:
 * 신맛이 단맛을 깎아 준 덕분에 물리지 않고 편안하게 느껴져요. When the two
 * say the same (입안을 조이는 만큼 입안을 조이고 …) only what it came to is
 * said.
 */
export function relation(
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
export function rowWords(
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
