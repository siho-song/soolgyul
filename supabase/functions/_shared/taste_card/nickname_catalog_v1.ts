/**
 * Approved display catalogue: taste_card_best_practice.md, nickname sections
 * A–F plus the neutral fallback; approved new aromas add standalone bases.
 *
 * These groups are names for the user's original positive sensation, not
 * substitute observations or catalogue taxonomy. The selector must retain the
 * exact supporting sensation. Runtime code never parses the source document.
 */
export const NICKNAME_CATALOG_VERSION_V1 = "taste-card-nickname-catalog-v1";

export type NicknameSensoryDomainV1 = "aroma" | "taste" | "mouthfeel";
export type NicknameReasonV1 = "gentle" | "pronounced" | "harmony";
export type NicknameFinishV1 = "clean" | "pleasantLength" | "aromaEcho";
export type NicknameMouthfeelV1 =
  | "light"
  | "heavy"
  | "smooth"
  | "drying"
  | "bubbles"
  | "warmth";
export type NicknameBaseGroupKeyV1 =
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
  | "leathery"
  | "musky"
  | "sweet"
  | "citrus"
  | "bitter"
  | "light"
  | "full_body"
  | "silky"
  | "tannin"
  | "sparkling"
  | "hot";

export type NicknameBaseGroupV1 = Readonly<{
  id: string;
  key: NicknameBaseGroupKeyV1;
  domain: NicknameSensoryDomainV1;
  label: string;
  sensory_keys: readonly string[];
}>;

function baseGroup(
  id: string,
  key: NicknameBaseGroupKeyV1,
  domain: NicknameSensoryDomainV1,
  label: string,
  sensoryKeys: readonly string[],
): NicknameBaseGroupV1 {
  return Object.freeze({
    id,
    key,
    domain,
    label,
    sensory_keys: Object.freeze([...sensoryKeys]),
  });
}

/** Source-document order is also the stable order of the base names. */
export const NICKNAME_BASE_GROUPS_V1: readonly NicknameBaseGroupV1[] = Object
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
    ]),
    baseGroup("A02", "floral", "aroma", "플로럴", [
      "floral",
      "acacia",
      "jasmine",
      "rose",
      "lavender",
      "chamomile",
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
    ]),
    baseGroup("A04", "vegetable", "aroma", "베지터블", [
      "vegetal",
      "bell_pepper",
      "jalapeno",
      "tomato",
      "cucumber",
      "celery",
      "potato",
      "sweet_potato",
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
    ]),
    baseGroup("A07", "nutty", "aroma", "너티", [
      "nutty",
      "almond",
      "walnut",
      "hazelnut",
      "macadamia",
      "cashew",
    ]),
    baseGroup("A08", "mocha", "aroma", "모카", [
      "chocolate",
      "coffee",
      "mocha",
    ]),
    baseGroup("A09", "milky", "aroma", "밀키", [
      "dairy",
      "butter",
      "cream",
      "cheese",
    ]),
    baseGroup("A10", "woody", "aroma", "우디", [
      "wood",
      "aged_aromatic",
      "sherry",
      "oak",
      "incense",
      "cherry_wood",
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
    ]),
    baseGroup("A15", "fermented", "aroma", "발효", [
      "fermentation",
      "nuruk",
      "yeast",
    ]),
    baseGroup("A16", "leathery", "aroma", "레더리", ["leather"]),
    baseGroup("A17", "musky", "aroma", "머스크", ["musk"]),
    baseGroup("T01", "sweet", "taste", "스위트", ["sweetness"]),
    baseGroup("T02", "citrus", "taste", "시트러스", ["acidity"]),
    baseGroup("T03", "bitter", "taste", "비터", ["bitterness"]),
    baseGroup("M01", "light", "mouthfeel", "라이트", ["light"]),
    baseGroup("M02", "full_body", "mouthfeel", "풀바디", ["heavy"]),
    baseGroup("M03", "silky", "mouthfeel", "실키", ["smooth"]),
    baseGroup("M04", "tannin", "mouthfeel", "타닌", ["drying"]),
    baseGroup("M05", "sparkling", "mouthfeel", "스파클링", ["bubbles"]),
    baseGroup("M06", "hot", "mouthfeel", "쏘핫", ["warmth"]),
  ]);

function groupsForDomain(
  domain: NicknameSensoryDomainV1,
): Readonly<Partial<Record<string, NicknameBaseGroupKeyV1>>> {
  const result: Record<string, NicknameBaseGroupKeyV1> = Object.create(null);
  for (const group of NICKNAME_BASE_GROUPS_V1) {
    if (group.domain !== domain) continue;
    for (const key of group.sensory_keys) {
      if (Object.hasOwn(result, key)) {
        throw new Error(`nickname_duplicate_sensory_key:${key}`);
      }
      result[key] = group.key;
    }
  }
  return Object.freeze(result);
}

/** All current aroma-capable service keys map to exactly one display group. */
export const AROMA_TO_NICKNAME_GROUP_V1 = groupsForDomain("aroma");
export const TASTE_TO_NICKNAME_GROUP_V1 = groupsForDomain("taste");
export const MOUTHFEEL_TO_NICKNAME_GROUP_V1 = groupsForDomain("mouthfeel");

export type NicknameCatalogEntryV1 = Readonly<{
  id: string;
  section: "A" | "B" | "C" | "D" | "E" | "F" | "neutral";
  label: string;
  /** Same entry, not another type: never call unexplained drying "tannin". */
  label_without_tannin: string | null;
  base_group: NicknameBaseGroupKeyV1 | null;
  related_sensory:
    | Readonly<{
      domain: NicknameSensoryDomainV1;
      keys: readonly string[];
    }>
    | null;
  modifier_kind:
    | "none"
    | "reason"
    | "finish"
    | "mouthfeel"
    | "finish_only"
    | "negative_only"
    | "neutral";
  /** Must belong to the same original positively evaluated aroma/taste. */
  reason: NicknameReasonV1 | null;
  finish: NicknameFinishV1 | null;
  mouthfeel: NicknameMouthfeelV1 | null;
  /** Only the 20 "드라이" entries require confirmed product tannin. */
  requires_tannin: boolean;
  /** E requires no positive base; F/N test all four sensory sections. */
  eligibility:
    | "positive_base"
    | "positive_finish_without_base"
    | "negative_without_positive"
    | "no_sensory_reaction";
  /** One-based document row/column order; never depends on answer order. */
  stable_priority: number;
}>;

function buildCatalogue(): readonly NicknameCatalogEntryV1[] {
  const entries: NicknameCatalogEntryV1[] = [];
  function add(
    input:
      & Pick<
        NicknameCatalogEntryV1,
        "id" | "section" | "label" | "modifier_kind"
      >
      & Partial<
        Pick<
          NicknameCatalogEntryV1,
          "reason" | "finish" | "mouthfeel" | "requires_tannin" | "eligibility"
        >
      >,
    base: NicknameBaseGroupV1 | null = null,
  ) {
    entries.push(Object.freeze({
      ...input,
      label_without_tannin: base?.key === "tannin"
        ? input.label.replace("타닌 러버", "떫음 러버")
        : null,
      base_group: base?.key ?? null,
      related_sensory: base
        ? Object.freeze({ domain: base.domain, keys: base.sensory_keys })
        : null,
      reason: input.reason ?? null,
      finish: input.finish ?? null,
      mouthfeel: input.mouthfeel ?? null,
      requires_tannin: input.requires_tannin ?? false,
      eligibility: input.eligibility ?? "positive_base",
      stable_priority: entries.length + 1,
    }));
  }
  // A: direct positive base only (a catalogue fact or a notice is insufficient).
  for (const base of NICKNAME_BASE_GROUPS_V1) {
    add({
      id: base.id,
      section: "A",
      label: `${base.label} 러버`,
      modifier_kind: "none",
    }, base);
  }

  // B: all three reasons are distinct and bound to that exact positive answer.
  const reasons: readonly [NicknameReasonV1, string][] = [
    ["gentle", "은은한"],
    ["pronounced", "선명한"],
    ["harmony", "균형잡힌"],
  ];
  let sequence = 0;
  for (
    const base of NICKNAME_BASE_GROUPS_V1.filter((item) =>
      item.domain !== "mouthfeel" &&
      item.key !== "leathery" && item.key !== "musky"
    )
  ) {
    for (const [reason, prefix] of reasons) {
      add({
        id: `B${String(++sequence).padStart(2, "0")}`,
        section: "B",
        label: `${prefix} ${base.label} 러버`,
        modifier_kind: "reason",
        reason,
      }, base);
    }
  }

  // C: only these two explicitly positive finishes can modify a base name.
  const finishes: readonly [NicknameFinishV1, string][] = [
    ["clean", "클린 피니쉬"],
    ["pleasantLength", "롱 피니쉬"],
  ];
  sequence = 0;
  for (const base of NICKNAME_BASE_GROUPS_V1) {
    // New aroma bases must not shift already published variant IDs.
    if (base.key === "leathery" || base.key === "musky") continue;
    for (const [finish, prefix] of finishes) {
      add({
        id: `C${String(++sequence).padStart(2, "0")}`,
        section: "C",
        label: `${prefix} ${base.label} 러버`,
        modifier_kind: "finish",
        finish,
      }, base);
    }
  }

  // D: 23 + 22 + 21 + 18 + 20 + 19. The explicit retained mouthfeel pairs
  // avoid order duplicates and keep drying as the base for its "떫음" fallback.
  const modifiers: readonly {
    key: NicknameMouthfeelV1;
    prefix: string;
    retained_mouthfeel_bases: readonly NicknameBaseGroupKeyV1[];
  }[] = [
    {
      key: "light",
      prefix: "라이트",
      retained_mouthfeel_bases: [
        "full_body",
        "silky",
        "tannin",
        "sparkling",
        "hot",
      ],
    },
    {
      key: "heavy",
      prefix: "풀바디",
      retained_mouthfeel_bases: ["silky", "tannin", "sparkling", "hot"],
    },
    {
      key: "smooth",
      prefix: "실키",
      retained_mouthfeel_bases: ["tannin", "sparkling", "hot"],
    },
    { key: "drying", prefix: "드라이", retained_mouthfeel_bases: [] },
    {
      key: "bubbles",
      prefix: "톡톡",
      retained_mouthfeel_bases: ["tannin", "hot"],
    },
    { key: "warmth", prefix: "쏘핫", retained_mouthfeel_bases: ["tannin"] },
  ];
  sequence = 0;
  for (const modifier of modifiers) {
    for (const base of NICKNAME_BASE_GROUPS_V1) {
      if (base.key === "leathery" || base.key === "musky") continue;
      if (
        base.domain === "mouthfeel" &&
        !modifier.retained_mouthfeel_bases.includes(base.key)
      ) continue;
      add({
        id: `D${String(++sequence).padStart(3, "0")}`,
        section: "D",
        label: `${modifier.prefix} ${base.label} 러버`,
        modifier_kind: "mouthfeel",
        mouthfeel: modifier.key,
        requires_tannin: modifier.key === "drying",
      }, base);
    }
  }

  // E: positive finish only when no positively evaluated base is available.
  // 2026-11-06: the lingering taste and mouthfeel finishes left the
  // questionnaire; 잔향 joined.
  const finishOnly: readonly [NicknameFinishV1, string][] = [
    ["clean", "클린 피니쉬 러버"],
    ["pleasantLength", "피니쉬 러버"],
    ["aromaEcho", "아로마 피니쉬 러버"],
  ];
  sequence = 0;
  for (const [finish, label] of finishOnly) {
    add({
      id: `E${String(++sequence).padStart(2, "0")}`,
      section: "E",
      label,
      modifier_kind: "finish_only",
      finish,
      eligibility: "positive_finish_without_base",
    });
  }
  add({
    id: "F01",
    section: "F",
    label: "취향 유랑자",
    modifier_kind: "negative_only",
    eligibility: "negative_without_positive",
  });
  add({
    id: "N01",
    section: "neutral",
    label: "취향 탐색자",
    modifier_kind: "neutral",
    eligibility: "no_sensory_reaction",
  });

  const expected = { A: 26, B: 54, C: 48, D: 123, E: 3, F: 1, neutral: 1 };
  for (const [section, count] of Object.entries(expected)) {
    if (entries.filter((item) => item.section === section).length !== count) {
      throw new Error(`nickname_catalog_count:${section}`);
    }
  }
  if (
    new Set(entries.map((item) => item.id)).size !== entries.length ||
    new Set(entries.map((item) => item.label)).size !== entries.length
  ) {
    throw new Error("nickname_catalog_duplicate");
  }
  return Object.freeze(entries);
}

export const NICKNAME_CATALOG_V1 = buildCatalogue();
