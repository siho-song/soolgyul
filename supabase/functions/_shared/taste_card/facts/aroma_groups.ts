/**
 * The sixteen groups the aromas a reader can pick fall in: 사과 and 체리 are
 * fruit, 누룩 and 요거트 fermentation. A fact about the aroma, read by every
 * part that speaks of aromas by group (the card's name, the taste letters, a
 * bottle's tags).
 */
export const AROMA_GROUPS = [
  {
    key: "fruity",
    aromas: [
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
    ],
  },
  {
    key: "floral",
    aromas: [
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
    ],
  },
  {
    key: "herbal",
    aromas: [
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
    ],
  },
  {
    key: "vegetable",
    aromas: [
      "vegetal",
      "tomato",
      "agave",
    ],
  },
  {
    key: "bakery",
    aromas: [
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
    ],
  },
  {
    key: "sweet_aroma",
    aromas: [
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
    ],
  },
  {
    key: "nutty",
    aromas: [
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
    ],
  },
  {
    key: "mocha",
    aromas: [
      "chocolate",
      "coffee",
      "mocha",
      "dark_chocolate",
      "milk_chocolate",
      "cocoa",
    ],
  },
  {
    key: "milky",
    aromas: [
      "dairy",
      "butter",
      "cream",
      "cheese",
    ],
  },
  {
    key: "woody",
    aromas: [
      "wood",
      "sherry",
      "oak",
      "cherry_wood",
      "cedar",
      "pine",
      "sandalwood",
    ],
  },
  {
    key: "smoky",
    aromas: [
      "smoke",
      "tobacco",
      "peat",
    ],
  },
  {
    key: "terroir",
    aromas: [
      "earth",
      "mushroom",
      "wet_stone",
      "mineral",
      "saline",
    ],
  },
  {
    key: "savory",
    aromas: [
      "savory",
      "olive",
    ],
  },
  {
    key: "spice",
    aromas: [
      "pepper",
      "spice",
      "cinnamon",
      "ginger",
      "clove",
      "coriander_seed",
      "juniper",
      "nutmeg",
      "liquorice",
    ],
  },
  {
    key: "fermented",
    aromas: [
      "fermentation",
      "nuruk",
      "yeast",
      "lactic",
    ],
  },
  {
    key: "leathery",
    aromas: [
      "leather",
    ],
  },
] as const satisfies readonly { key: string; aromas: readonly string[] }[];

export type AromaGroupKey = typeof AROMA_GROUPS[number]["key"];

const GROUP_OF: Readonly<Partial<Record<string, AromaGroupKey>>> = (() => {
  const result: Record<string, AromaGroupKey> = Object.create(null);
  for (const group of AROMA_GROUPS) {
    for (const aroma of group.aromas) {
      if (Object.hasOwn(result, aroma)) {
        throw new Error(`aroma_in_two_groups:${aroma}`);
      }
      result[aroma] = group.key;
    }
  }
  return Object.freeze(result);
})();

/** The group of an aroma, or null for one that belongs to none. */
export function groupOfAroma(aroma: string): AromaGroupKey | null {
  return GROUP_OF[aroma] ?? null;
}
