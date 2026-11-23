import { aromaLine } from "../dictionary/aroma_lineage.ts";

/**
 * What an aroma does in the nose and mouth, by family: the effect of the
 * aroma's family on the senses, never where the aroma comes from. Each row
 * covers nodes of the catalog's aroma tree; an aroma takes the row of the
 * nearest node on its line (체리 hangs under 핵과 but is sour fruit, 수박
 * under 멜론 but fresh). The rows are also the aroma families the fit and
 * the kind counts go by.
 */
export type AromaEffect = {
  /** Nodes of catalog.json whose aromas this row explains. */
  nodes: readonly string[];
  /** The 취향어 noun: "'{noun}이 또렷한 {kind}'". */
  noun: string;
  /** A kind's own word for the same thing, when it has one (사케의 쌀의 구수함). */
  kind_nouns?: Readonly<Record<string, string>>;
  principle: string;
  /**
   * What the principle stands on: studies for the claims about the nose and
   * mouth (learned odor–taste links, detection thresholds, trigeminal
   * receptors), or a note when it is general aroma chemistry.
   */
  sources: readonly string[];
};
export const AROMA_EFFECTS = {
  effect_ripe_fruit: {
    nodes: [
      "stone_fruit",
      "tropical_fruit",
      "melon",
      "fresh_fig",
      "dried_fruit",
      "cooked_preserved_fruit",
      "ripe_fresh_fruit",
      "sweet_fresh_fruit",
      "yellow_fruit",
      "white_fruit",
      "ginjo_aroma",
    ],
    noun: "잘 익은 과일 향",
    principle:
      "잘 익은 과일 향은 코로만 맡아도 혀가 단맛을 기다리게 해서, 달지 않은 술도 포근하게 느껴져요",
    sources: [
      "learned odor sweetness: Stevenson, Boakes & Prescott 1999 https://researchers.mq.edu.au/en/publications/changes-in-odor-sweetness-resulting-from-implicit-learning-of-a-s/",
      "odor-induced taste enhancement review https://pmc.ncbi.nlm.nih.gov/articles/PMC8130510",
    ],
  },
  effect_sour_fruit: {
    nodes: [
      "cherry",
      "plum",
      "berry",
      "red_fruit",
      "black_fruit",
      "pomegranate",
      "rhubarb",
      "wild_fruit",
      "lingonberry",
      "black_mulberry",
      "hawthorn",
    ],
    noun: "새콤달콤한 과일 향",
    principle:
      "새콤달콤한 과일 향은 그 과일의 새콤함까지 떠올리게 해서 입안이 깨어나고, 술이 경쾌하게 느껴져요",
    sources: [
      "food odors raise saliva flow, lemon among the strongest: INRA https://prodinra.inra.fr/record/332499",
      "sour-signalling odors and salivation: Morquecho-Campos et al. 2019 https://research.wur.nl/en/publications/impact-of-food-odors-signaling-specific-taste-qualities-and-macro/",
    ],
  },
  effect_fresh_fruit: {
    nodes: [
      "orchard_fruit",
      "citrus",
      "grape",
      "watermelon",
      "unripe_fruit",
      "fresh_fresh_fruit",
    ],
    noun: "상큼한 과일 향",
    principle:
      "상큼한 과일 향은 가볍고 빨리 퍼져 코에 먼저 닿고, 술이 마시기 전부터 산뜻하게 느껴져요",
    sources: [
      "general: light esters and aldehydes are the most volatile notes and reach the nose first; no single study",
    ],
  },
  effect_floral: {
    nodes: ["floral"],
    noun: "꽃 향",
    principle:
      "꽃 향은 가볍게 피어올라 맛보다 먼저 첫인상을 정하고, 술이 실제보다 화사하게 느껴져요",
    sources: [
      "general: floral terpenes and esters are light, early notes; no single study",
    ],
  },
  effect_smoke: {
    nodes: ["peat", "smoke"],
    noun: "스모키한 향",
    principle:
      "연기 냄새는 아주 적은 양에도 코가 먼저 알아채서 첫 향부터 분위기를 정하고, 반기는 쪽과 밀어내는 쪽이 갈려요",
    sources: [
      "guaiacol odor threshold about 23 µg/L in red wine (AWRI) https://www.awri.com.au/files/attachment/jan-feb-2013-awri-report",
      "smoke taint detection thresholds https://asev.org/abstract/olfactory-detection-thresholds-smoke-taint-red-wine",
    ],
  },
  effect_sweet_scent: {
    nodes: ["sweet_aromatic", "chocolate", "coconut", "beeswax", "wax"],
    noun: "달큰한 향",
    principle:
      "바닐라나 캐러멜 냄새는 단맛과 함께 익힌 냄새라 코로만 맡아도 달게 느껴지고, 술이 실제 단맛보다 부드럽게 다가와요",
    sources: [
      "vanilla and caramel odors smell sweet and enhance sweetness by co-exposure: odor-induced taste enhancement review https://pmc.ncbi.nlm.nih.gov/articles/PMC8130510",
      "Stevenson, Boakes & Prescott 1999 https://researchers.mq.edu.au/en/publications/changes-in-odor-sweetness-resulting-from-implicit-learning-of-a-s/",
    ],
  },
  effect_grain_nut: {
    nodes: ["cereal", "bread", "nutty", "toast"],
    noun: "구수한 향",
    kind_nouns: {
      sake: "쌀의 구수함",
      whisky: "구수한 맥아 향",
      takju: "곡물의 구수함",
      yakju: "곡물의 구수함",
      traditional: "곡물의 구수함",
    },
    principle:
      "곡물과 견과의 구수한 냄새는 매일 먹는 음식의 냄새라 코가 경계하지 않고, 술이 든든하게 느껴져요",
    sources: [
      "familiar odors are rated pleasant: Delplanque et al. 2008 https://www.unige.ch/fapse/e3lab/application/files/3017/7739/3067/2008-Delplanque_Grandjean_Chrea_Aymard_Cayeux_LeCalve_Velazco_Scherer__Sander-Chemical_Senses.pdf",
      "odor norms, familiarity–pleasantness R²=0.53 https://pmc.ncbi.nlm.nih.gov/articles/PMC4977894",
    ],
  },
  effect_roast: {
    nodes: ["roasted"],
    noun: "볶은 향",
    principle:
      "볶은 냄새는 쌉쌀한 맛과 함께 다니던 냄새라 혀가 쌉쌀함을 준비하고, 술이 진하고 묵직하게 느껴져요",
    sources: [
      "odors take on the taste they were eaten with (learned congruency) https://pmc.ncbi.nlm.nih.gov/articles/PMC8130510",
    ],
  },
  effect_wood: {
    nodes: ["wood"],
    noun: "나무 향",
    kind_nouns: { wine: "오크 숙성 향", whisky: "오크 향" },
    principle:
      "나무 향은 천천히 올라와 오래 머물며 화사한 향 뒤를 받쳐서, 술이 차분하고 묵직하게 느껴져요",
    sources: [
      "general: oak lactones, vanillin and phenols are heavier, slower notes; no single study",
    ],
  },
  effect_green: {
    nodes: ["herbal", "leaf", "tea", "essential_oil", "juniper"],
    noun: "허브 향",
    principle:
      "허브와 풀 냄새는 코를 상쾌하게 깨우고 입안까지 서늘한 느낌을 남겨서, 술이 깔끔하고 또렷하게 느껴져요",
    sources: [
      "menthol cooling through TRPM8 in trigeminal neurons https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9580369/",
    ],
  },
  effect_vegetal: {
    nodes: ["vegetal"],
    noun: "풋풋한 채소 향",
    principle:
      "풋풋한 채소 냄새는 날것을 떠올리게 해서 혀가 단맛보다 서늘한 쪽을 준비하고, 술이 덜 달게 느껴져요",
    sources: [
      "bell pepper pyrazine (IBMP) threshold 1–16 ng/L https://waterhouse.ucdavis.edu/node/586",
      "IBMP perception in wine https://oeno-one.eu/article/view/4492",
    ],
  },
  effect_spice: {
    nodes: ["spice"],
    noun: "향신료 향",
    principle:
      "향신료 냄새는 혀의 따뜻한 자극과 함께 오던 냄새라 입안이 그 자극을 미리 떠올리고, 술이 도수보다 따뜻하게 느껴져요",
    sources: [
      "cinnamaldehyde acts on TRPA1 with menthol/capsaicin convergence in the trigeminal system https://pmc.ncbi.nlm.nih.gov/articles/PMC2254210",
      "odors take on the sensation they were eaten with (learned congruency) https://pmc.ncbi.nlm.nih.gov/articles/PMC8130510",
    ],
  },
  effect_mineral: {
    nodes: ["mineral"],
    noun: "미네랄 느낌",
    principle:
      "미네랄 느낌은 앞에 나서지 않고 뒤에서 선을 긋듯 남아서, 술이 깨끗하고 단단하게 느껴져요",
    sources: [
      "minerality is a perceptual construct (flint, fresh/acid, sea/shellfish clusters), not mineral uptake: Parr, Maltman, Easton & Ballester 2018 https://hal.inrae.fr/hal-02624486",
    ],
  },
  effect_earth: {
    nodes: ["earth", "mushroom"],
    noun: "흙 내음",
    principle:
      "흙과 버섯 냄새는 아주 적은 양으로도 느껴지고 분위기를 가라앉혀서, 술이 밝기보다 깊게 느껴져요",
    sources: [
      "geosmin detection threshold about 4–15 ng/L https://pmc.ncbi.nlm.nih.gov/articles/PMC11261619/",
      "https://halifaxwater.ca/geosmin",
    ],
  },
  effect_dairy: {
    nodes: ["dairy"],
    noun: "크림 같은 향",
    principle:
      "유제품 냄새는 입안을 감싸는 촉감과 함께 익힌 냄새라, 코로만 맡아도 술이 부드럽고 둥글게 느껴져요",
    sources: [
      "retronasal cream odor raises creaminess and thickness: Bult et al. 2007 https://fis.tu-dresden.de/portal/en/publications/investigations-on-multimodal-sensory-integration(88cdf41c-92c0-4c53-9276-9408a55937a2).html",
      "butter odor and cheese creaminess https://fis.tu-dresden.de/portal/en/publications/modulation-of-sensory-perception-of-cheese-attributes-intensity-and-texture-liking-via-ortho-and-retronasal-odors(d16286ed-44b4-456a-a5ed-6bf4087016d1).html",
    ],
  },
  effect_ferment: {
    nodes: ["fermentation"],
    noun: "발효 향",
    principle:
      "효모와 발효 냄새는 익숙하면서도 술이 살아 있다는 느낌을 줘서, 술이 깔끔하기보다 생생하게 느껴져요",
    sources: [
      "familiar odors are rated pleasant: Delplanque et al. 2008 https://www.unige.ch/fapse/e3lab/application/files/3017/7739/3067/2008-Delplanque_Grandjean_Chrea_Aymard_Cayeux_LeCalve_Velazco_Scherer__Sander-Chemical_Senses.pdf",
    ],
  },
  effect_savory: {
    nodes: ["savory"],
    noun: "감칠맛 나는 향",
    principle:
      "감칠맛 나는 음식의 냄새는 입안이 그 깊은 맛을 기다리게 해서, 술이 든든하고 깊게 느껴져요",
    sources: [
      "soy sauce odor induces and enhances saltiness: Chokumnoyporn et al. 2015 https://experts.illinois.edu/en/publications/soy-sauce-odour-induces-and-enhances-saltiness-perception/",
      "savory odorants enhancing saltiness and umami https://pmc.ncbi.nlm.nih.gov/articles/PMC6870243",
    ],
  },
  effect_aged: {
    nodes: ["tobacco", "animalic", "aged_aromatic"],
    noun: "묵직한 향",
    principle:
      "담뱃잎이나 가죽처럼 마르고 낮은 냄새는 화사한 향 뒤에 남아 깊이를 더해서, 술이 깊고 오래된 느낌으로 다가와요",
    sources: [
      "general: leather and tobacco notes are low-volatility, late notes; no single study",
    ],
  },
} as const satisfies Record<string, AromaEffect>;

/**
 * The effect row of an aroma: the nearest node of its line in the catalog
 * tree that a row covers.
 */
export function aromaEffect(
  aromaKey: string,
): keyof typeof AROMA_EFFECTS | null {
  const rows = Object.entries(AROMA_EFFECTS) as [
    keyof typeof AROMA_EFFECTS,
    AromaEffect,
  ][];
  for (const node of aromaLine(aromaKey)) {
    const hit = rows.find(([, row]) => row.nodes.includes(node));
    if (hit) return hit[0];
  }
  return null;
}
