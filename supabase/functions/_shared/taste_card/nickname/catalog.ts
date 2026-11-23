/**
 * The names a card can carry (프루티 러버, 클린 피니쉬 드라이 러버). A name is
 * made of words, never written one by one:
 *
 *   a base alone            one thing liked while drinking (프루티 러버)
 *   a strength name         a liked low or high step with a word of its own
 *                           (은은한 우마미 러버)
 *   a finish with a base    클린 피니쉬 프루티 러버
 *   a mouthfeel with a base 실키 프루티 러버
 *   a finish alone          only when nothing liked while drinking has a name
 *
 * What a liked answer is called is the selector's (selector.ts). A pair is
 * listed only where a drink is asked both: no kind is asked 타닌 and 탄산
 * together, so there is no 톡톡 떫음 러버.
 */
type AromaGroupKey =
  | "fruity"
  | "floral"
  | "herbal"
  | "vegetable"
  | "bakery"
  | "sweet_aroma"
  | "nutty"
  | "mocha"
  | "milky"
  | "woody"
  | "smoky"
  | "terroir"
  | "savory"
  | "spice"
  | "fermented"
  | "leathery";
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

/** The bases, in the stable order two names of equal weight are decided by. */
export const NICKNAME_BASE_GROUPS: readonly NicknameBaseGroup[] = Object
  .freeze([
    baseGroup("A01", "fruity", "aroma", "프루티", [
      "apple",
      "pear",
      "peach",
      "plum",
      "ume",
      "cherry",
      "berry",
      "tropical_fruit",
      "orange_tangerine",
      "lemon_lime",
      "yuzu",
      "citrus",
      "grape",
      "green_grape",
      "melon",
      "korean_melon",
      "watermelon",
      "fresh_fig",
      "jammy",
      "fruit_syrup",
      "dried_fruit",
      "banana",
      "coconut",
      "kiwi",
      "mango",
      "pineapple",
      "grapefruit",
      "pomegranate",
      "ginjo_aroma",
      "apricot",
      "blueberry",
      "cranberry",
      "green_apple",
      "lychee",
      "quince",
      "raisin",
      "strawberry",
      "black_cherry",
      "red_cherry",
      "blackberry",
      "raspberry",
      "omija_bokbunja",
      "passion_fruit",
      "orange",
      "tangerine_mandarin",
      "lemon",
      "lime",
      "marmalade",
      "dried_apricot",
      "dried_fig",
      "jujube",
      "prune",
    ]),
    baseGroup("A02", "floral", "aroma", "플로럴", [
      "floral",
      "acacia",
      "jasmine",
      "rose",
      "lavender",
      "chamomile",
      "white_flower",
      "red_flower",
      "violet",
      "cherry_plum_blossom",
    ]),
    baseGroup("A03", "herbal", "aroma", "허브", [
      "mint",
      "herbal",
      "tea",
      "leaf",
      "hay",
      "medicinal_herb",
      "green_tea",
      "matcha",
      "black_tea",
      "earl_grey",
      "hop",
      "eucalyptus",
      "rosemary",
      "mugwort",
      "grass",
    ]),
    baseGroup("A04", "vegetable", "aroma", "베지터블", [
      "vegetal",
      "tomato",
      "agave",
    ]),
    baseGroup("A05", "bakery", "aroma", "베이커리", [
      "bread",
      "cereal",
      "roasted",
      "corn",
      "rice",
      "barley",
      "malt",
      "wheat",
      "toast",
      "brioche",
      "scorched_rice",
    ]),
    baseGroup("A06", "sweet_aroma", "aroma", "스위티", [
      "dessert_aromatic",
      "toffee",
      "vanilla",
      "caramel",
      "brown_sugar",
      "maple_syrup",
      "honey",
      "candy",
      "custard",
      "creme_brulee",
    ]),
    baseGroup("A07", "nutty", "aroma", "너티", [
      "nutty",
      "almond",
      "walnut",
      "hazelnut",
      "macadamia",
      "cashew",
      "pecan",
      "peanut",
      "chestnut",
      "sesame",
    ]),
    baseGroup("A08", "mocha", "aroma", "모카", [
      "chocolate",
      "coffee",
      "mocha",
      "dark_chocolate",
      "milk_chocolate",
      "cocoa",
    ]),
    baseGroup("A09", "milky", "aroma", "밀키", [
      "dairy",
      "butter",
      "cream",
      "cheese",
    ]),
    baseGroup("A10", "woody", "aroma", "우디", [
      "wood",
      "sherry",
      "oak",
      "cherry_wood",
      "cedar",
      "pine",
      "sandalwood",
    ]),
    baseGroup("A11", "smoky", "aroma", "스모키", ["smoke", "tobacco", "peat"]),
    baseGroup("A12", "terroir", "aroma", "떼루아", [
      "earth",
      "mushroom",
      "wet_stone",
      "mineral",
      "saline",
    ]),
    baseGroup("A13", "savory", "aroma", "세이보리", ["savory", "olive"]),
    baseGroup("A14", "spice", "aroma", "향신료", [
      "pepper",
      "spice",
      "cinnamon",
      "ginger",
      "clove",
      "coriander_seed",
      "juniper",
      "nutmeg",
      "liquorice",
    ]),
    baseGroup("A15", "fermented", "aroma", "발효", [
      "fermentation",
      "nuruk",
      "yeast",
    ]),
    baseGroup("A16", "leathery", "aroma", "레더리", ["leather"]),
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

/** The group of every aroma a name can be made of. */
export const AROMA_TO_NICKNAME_GROUP: Readonly<
  Partial<Record<string, AromaGroupKey>>
> = (() => {
  const result: Record<string, AromaGroupKey> = Object.create(null);
  for (const group of NICKNAME_BASE_GROUPS) {
    for (const key of group.sensory_keys) {
      if (Object.hasOwn(result, key)) {
        throw new Error(`nickname_duplicate_sensory_key:${key}`);
      }
      result[key] = group.key as AromaGroupKey;
    }
  }
  return Object.freeze(result);
})();

export type NicknameEntry = Readonly<{
  id: string;
  label: string;
  /** Every one of these was liked. */
  needs: readonly NameUnit[];
  /** A name of two words says more than a base alone and is chosen first. */
  words: 1 | 2;
  /** A finish alone: only when nothing liked while drinking has a name. */
  finish_alone: boolean;
}>;

/** Every answer was marked 아쉬웠어요, or the liked ones name nothing. */
export const NAME_ONLY_MINDED = "취향 유랑자";
/** Nothing that was answered has a name. */
export const NAME_NOTHING_NAMED = "취향 탐색자";

const STRENGTH_NAMES: readonly [StrengthKey, string][] = [
  ["citrus_gentle", "은은한 시트러스"],
  ["umami_gentle", "은은한 우마미"],
  ["umami_heavy", "헤비 우마미"],
  ["sparkling_gentle", "은은한 스파클링"],
  ["spicy_mild", "마일드 스파이시"],
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
    words: 1 | 2,
    finishAlone = false,
  ) => {
    const number = entries.filter((e) => e.id.startsWith(section)).length + 1;
    entries.push(Object.freeze({
      id: `${section}${String(number).padStart(3, "0")}`,
      label,
      needs: Object.freeze([...needs]),
      words,
      finish_alone: finishAlone,
    }));
  };
  // 레더리 is a name alone and goes with no finish or mouthfeel.
  const joined = NICKNAME_BASE_GROUPS.filter((base) => base.key !== "leathery");

  for (const base of NICKNAME_BASE_GROUPS) {
    add("A", `${base.label} 러버`, [base.key], 1);
  }
  for (const [unit, name] of STRENGTH_NAMES) {
    add("B", `${name} 러버`, [unit], 2);
  }
  for (const base of joined) {
    for (const [finish, word] of FINISH_WORDS) {
      add("C", `${word} ${base.label} 러버`, [finish, base.key], 2);
    }
  }
  for (const feel of MOUTHFEEL_WORDS) {
    for (const base of joined) {
      const goes = base.domain === "mouthfeel"
        ? feel.mouthfeels.includes(base.key as MouthfeelKey)
        : !(feel.never ?? []).includes(base.key);
      if (goes) {
        add("D", `${feel.word} ${base.label} 러버`, [feel.key, base.key], 2);
      }
    }
  }
  for (const [finish, label] of FINISH_ALONE) {
    add("E", label, [finish], 1, true);
  }
  if (new Set(entries.map((entry) => entry.label)).size !== entries.length) {
    throw new Error("nickname_catalog_duplicate");
  }
  return Object.freeze(entries);
}

/** In the order a name is chosen by among names of equal weight. */
export const NICKNAME_CATALOG = buildCatalogue();

/** Every name a card built now can carry. */
export const NICKNAMES: ReadonlySet<string> = new Set([
  ...NICKNAME_CATALOG.map((entry) => entry.label),
  NAME_ONLY_MINDED,
  NAME_NOTHING_NAMED,
]);
