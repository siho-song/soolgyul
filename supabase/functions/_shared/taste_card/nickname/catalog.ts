/**
 * The names a card can carry (프루티 러버, 클린 피니쉬 드라이 러버). A name is
 * made of words, never written one by one:
 *
 *   a finish with a base    클린 피니쉬 프루티 러버
 *   a mouthfeel with a base 실키 프루티 러버
 *   a base alone            one thing liked while drinking (프루티 러버)
 *   a strength name         a liked low or high step with a word of its own
 *                           (은은한 우마미 러버); it joins no other word
 *   a finish alone          only when nothing liked while drinking has a name
 *
 * What a liked answer is called is the selector's (selector.ts). A pair is
 * listed only where a drink is asked both: no kind is asked 타닌 and 탄산
 * together, so there is no 톡톡 떫음 러버.
 */
import { AROMA_GROUPS, type AromaGroupKey } from "../facts/aroma_groups.ts";

type TasteKey = "sweet" | "dry" | "citrus";
type MouthfeelKey =
  | "light"
  | "full_body"
  | "silky"
  | "tannin"
  | "sparkling"
  | "spicy";
type BaseKey = AromaGroupKey | TasteKey | MouthfeelKey;
/** A liked step that is a whole name and joins no other word. */
type StrengthKey =
  | "citrus_gentle"
  | "umami_gentle"
  | "umami_heavy"
  | "sparkling_gentle"
  | "spicy_mild";
type FinishKey = "finish_clean" | "finish_long" | "finish_aroma";
/** What one liked answer is, for naming. */
export type NameUnit = BaseKey | StrengthKey | FinishKey;

type NicknameBaseGroup = Readonly<{
  id: string;
  key: BaseKey;
  domain: "aroma" | "taste" | "mouthfeel";
  label: string;
  /** The aromas of an aroma group; empty for a taste or a mouthfeel. */
  sensory_keys: readonly string[];
}>;

function baseGroup(
  id: string,
  key: BaseKey,
  domain: NicknameBaseGroup["domain"],
  label: string,
  sensoryKeys: readonly string[] = [],
): NicknameBaseGroup {
  return Object.freeze({
    id,
    key,
    domain,
    label,
    sensory_keys: Object.freeze([...sensoryKeys]),
  });
}

/** The word of each aroma group in a name. */
const AROMA_WORDS: Readonly<Record<AromaGroupKey, string>> = {
  fruity: "프루티",
  floral: "플로럴",
  herbal: "허브",
  vegetable: "베지터블",
  bakery: "베이커리",
  sweet_aroma: "스위티",
  nutty: "너티",
  mocha: "모카",
  milky: "밀키",
  woody: "우디",
  smoky: "스모키",
  terroir: "떼루아",
  savory: "세이보리",
  spice: "향신료",
  fermented: "발효",
  leathery: "레더리",
};

/** The bases, in the stable order two names of equal weight are decided by. */
export const NICKNAME_BASE_GROUPS: readonly NicknameBaseGroup[] = Object
  .freeze([
    ...AROMA_GROUPS.map((group, i) =>
      baseGroup(
        `A${String(i + 1).padStart(2, "0")}`,
        group.key,
        "aroma",
        AROMA_WORDS[group.key],
        group.aromas,
      )
    ),
    baseGroup("T01", "sweet", "taste", "스위트"),
    baseGroup("T02", "dry", "taste", "드라이"),
    baseGroup("T03", "citrus", "taste", "시트러스"),
    baseGroup("M01", "light", "mouthfeel", "라이트"),
    baseGroup("M02", "full_body", "mouthfeel", "풀바디"),
    baseGroup("M03", "silky", "mouthfeel", "실키"),
    baseGroup("M04", "tannin", "mouthfeel", "떫음"),
    baseGroup("M05", "sparkling", "mouthfeel", "스파클링"),
    baseGroup("M06", "spicy", "mouthfeel", "스파이시"),
  ]);

export type NicknameEntry = Readonly<{
  id: string;
  label: string;
  /** Every one of these was liked: one answer, or two for a base with its word. */
  needs: readonly NameUnit[];
  /** A finish alone: only when nothing liked while drinking has a name. */
  finish_alone: boolean;
}>;

/** Every answer was marked 아쉬웠어요, or the liked ones name nothing. */
export const NAME_ONLY_MINDED = "취향 유랑자";
/** Nothing that was answered has a name. */
export const NAME_NOTHING_NAMED = "취향 탐색자";

/** The strength names, and the bases each stands after in the stable order. */
const STRENGTH_NAMES: readonly [
  StrengthKey,
  string,
  NicknameBaseGroup["domain"],
][] = [
  ["citrus_gentle", "은은한 시트러스", "taste"],
  ["umami_gentle", "은은한 우마미", "taste"],
  ["umami_heavy", "헤비 우마미", "taste"],
  ["sparkling_gentle", "은은한 스파클링", "mouthfeel"],
  ["spicy_mild", "마일드 스파이시", "mouthfeel"],
];
const FINISH_WORDS: readonly [FinishKey, string][] = [
  ["finish_clean", "클린 피니쉬"],
  ["finish_long", "롱 피니쉬"],
];
/**
 * The mouthfeels that go before a base, the mouthfeel bases each goes with
 * (one order of a pair, and only gauges asked together), and the other bases
 * it is never asked with.
 */
const MOUTHFEEL_WORDS: readonly {
  key: MouthfeelKey;
  word: string;
  mouthfeels: readonly MouthfeelKey[];
  never?: readonly BaseKey[];
}[] = [
  {
    key: "light",
    word: "라이트",
    mouthfeels: ["silky", "tannin", "sparkling", "spicy"],
  },
  {
    key: "full_body",
    word: "풀바디",
    mouthfeels: ["silky", "tannin", "sparkling", "spicy"],
  },
  { key: "silky", word: "실키", mouthfeels: [] },
  { key: "sparkling", word: "톡톡", mouthfeels: [] },
  // 스파이시 is asked of a whisky and a distilled soju, 산미 of neither.
  { key: "spicy", word: "스파이시", mouthfeels: [], never: ["citrus"] },
];
const FINISH_ALONE: readonly [FinishKey, string][] = [
  ["finish_clean", "클린 피니쉬 러버"],
  ["finish_long", "피니쉬 러버"],
  ["finish_aroma", "아로마 피니쉬 러버"],
];

function buildCatalogue(): readonly NicknameEntry[] {
  const entries: NicknameEntry[] = [];
  const add = (
    section: string,
    label: string,
    needs: readonly NameUnit[],
    finishAlone = false,
  ) => {
    const number = entries.filter((e) => e.id.startsWith(section)).length + 1;
    entries.push(Object.freeze({
      id: `${section}${String(number).padStart(3, "0")}`,
      label,
      needs: Object.freeze([...needs]),
      finish_alone: finishAlone,
    }));
  };
  // 레더리 is a name alone and goes with no finish or mouthfeel.
  const joined = NICKNAME_BASE_GROUPS.filter((base) => base.key !== "leathery");

  // The names of two answers, a finish before a mouthfeel.
  for (const base of joined) {
    for (const [finish, word] of FINISH_WORDS) {
      add("C", `${word} ${base.label} 러버`, [finish, base.key]);
    }
  }
  for (const feel of MOUTHFEEL_WORDS) {
    for (const base of joined) {
      const goes = base.domain === "mouthfeel"
        ? feel.mouthfeels.includes(base.key as MouthfeelKey)
        : !(feel.never ?? []).includes(base.key);
      if (goes) {
        add("D", `${feel.word} ${base.label} 러버`, [feel.key, base.key]);
      }
    }
  }
  // The names of one answer: 향, then 맛, then 질감.
  for (const domain of ["aroma", "taste", "mouthfeel"] as const) {
    for (const base of NICKNAME_BASE_GROUPS) {
      if (base.domain === domain) add("A", `${base.label} 러버`, [base.key]);
    }
    for (const [unit, name, after] of STRENGTH_NAMES) {
      if (after === domain) add("B", `${name} 러버`, [unit]);
    }
  }
  for (const [finish, label] of FINISH_ALONE) {
    add("E", label, [finish], true);
  }
  if (new Set(entries.map((entry) => entry.label)).size !== entries.length) {
    throw new Error("nickname_catalog_duplicate");
  }
  return Object.freeze(entries);
}

/** In the order a name is chosen by: the first whose every word was liked. */
export const NICKNAME_CATALOG = buildCatalogue();

/** Every name a card built now can carry. */
export const NICKNAMES: ReadonlySet<string> = new Set([
  ...NICKNAME_CATALOG.map((entry) => entry.label),
  NAME_ONLY_MINDED,
  NAME_NOTHING_NAMED,
]);
