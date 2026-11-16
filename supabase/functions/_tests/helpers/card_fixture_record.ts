import {
  serviceVocabulary as vocabulary,
  styleProfiles,
} from "../../_shared/taste_card/dictionary/dictionary.ts";
import {
  type LegacyCardFacts,
  readStoredCardFacts,
  type StoredCardFacts,
} from "../../_shared/taste_card/facts/facts.ts";
import {
  sensoryOption,
  validateSensoryAnswers,
} from "../../_shared/taste_card/record/questionnaire.ts";
import { buildSensoryRecord } from "../../_shared/taste_card/record/record_builder.ts";
import type {
  SensoryProduct,
  SensoryProductDescriptor,
  SensoryRecord,
} from "../../_shared/taste_card/record/sensory_record.ts";
import type { QuestionnaireAnswerInput } from "../../_shared/taste_card/service/types.ts";

export const dir = new URL("../fixtures/card_facts/", import.meta.url);

/** Option keys as a request carries them: one answer per question, in the order first named. */
export function answersOf(
  keys: readonly string[],
): QuestionnaireAnswerInput[] {
  const byQuestion = new Map<string, string[]>();
  for (const key of keys) {
    const option = sensoryOption(key);
    if (!option) throw new Error(`unknown questionnaire option ${key}`);
    byQuestion.set(option.question_key, [
      ...(byQuestion.get(option.question_key) ?? []),
      key,
    ]);
  }
  return [...byQuestion].map(([question_key, selected_option_keys]) => ({
    question_key,
    selected_option_keys,
    free_text: null,
  }));
}

/**
 * A sensory record from questionnaire option keys and a product, built the
 * way a request is: the answers pass the questionnaire's check first. Keys
 * without a revisit answer get 잘 모르겠어요, which every record carries.
 */
export function recordFrom(
  recordRef: string,
  keys: readonly string[],
  product: SensoryProduct,
): SensoryRecord {
  const answers = answersOf(
    keys.some((key) => key.startsWith("revisit:"))
      ? keys
      : [...keys, "revisit:unsure"],
  );
  validateSensoryAnswers(answers);
  return buildSensoryRecord(recordRef, answers, product);
}

const BASE_STYLE: Readonly<Record<string, string>> = {
  red: "red_wine",
  white: "white_wine",
  sparkling: "sparkling_wine",
  rose: "rose_wine",
};
const WINE_REGIONS = (styleProfiles as unknown as {
  wine_regions: {
    key: string;
    color: string;
    match: { region_labels?: string[] };
  }[];
}).wine_regions;
const WINE_GRAPES = new Set(
  (styleProfiles as unknown as { wine_grapes: { key: string }[] }).wine_grapes
    .map((g) => g.key),
);

/** The bottle a stored card was written about, as the catalog would serve it. */
export function fixtureProduct(facts: StoredCardFacts): SensoryProduct {
  const levels: Record<string, 1 | 2 | 3 | 4 | 5> = {};
  const descriptors: SensoryProductDescriptor[] = [];
  const texture: string[] = [];
  let abv: number | null = null;
  const ingredients: string[] = [];
  const processes: string[] = [];
  const grapes: string[] = [];
  for (const { fact, source } of facts.product_facts) {
    // A level the card read from the kind's table or from the ABV is not a
    // column of the product; the reader derives it again.
    if (
      fact.type === "level" &&
      (source.startsWith("catalog:style_table:") ||
        source.startsWith("catalog:abv_band:"))
    ) {
      continue;
    }
    if (fact.type === "level") levels[fact.dimension] = fact.level;
    // A fixture names the grape entries among its style facts; the catalog
    // states them as the product's grape varieties.
    if (fact.type === "style" && WINE_GRAPES.has(fact.key)) {
      grapes.push(fact.key);
    }
    if (fact.type === "descriptor") {
      descriptors.push({
        key: fact.key,
        label: fact.key,
        section: fact.section,
        family: "test",
        traits: [],
        description: null,
        evidenceRefs: ["test"],
      });
    }
    if (fact.type === "trait") texture.push(fact.key);
    if (fact.type === "abv") abv = fact.value;
    if (fact.type === "ingredient") ingredients.push(fact.key);
    if (fact.type === "production") processes.push(fact.key);
  }
  if (texture.length) {
    descriptors.push({
      key: "soft_texture",
      label: "질감",
      section: "texture",
      family: "test",
      traits: texture,
      description: null,
      evidenceRefs: ["test"],
    });
  }
  // A fixture names its wine region entry (champagne_sparkling) as its style;
  // the catalog stores the base style plus a region label instead.
  const region = WINE_REGIONS.find((r) => r.key === facts.record.style_key);
  return {
    name: facts.record.product_name,
    category: facts.record.category as SensoryProduct["category"],
    styleKey: region ? BASE_STYLE[region.color] : facts.record.style_key,
    region: region?.match.region_labels?.[0] ?? null,
    abv,
    ingredients,
    grapeVarietyKeys: grapes,
    processes,
    levels,
    levelRefs: {},
    descriptors,
  };
}

/** A catalog product sampled for the tests: its kind, levels and the aroma keys the catalog lists. */
export type CatalogSample = {
  id: string;
  name: string;
  category: string;
  style_key: string | null;
  abv: number | null;
  ingredients: readonly string[];
  processes: readonly string[];
  levels: SensoryProduct["levels"];
  level_sources?: SensoryProduct["levelSources"];
  aromas: readonly string[];
  texture: readonly string[];
};

/** The sampled catalog products (one file, six categories). */
export async function catalogSamples(): Promise<CatalogSample[]> {
  return JSON.parse(
    await Deno.readTextFile(new URL("products.json", dir)),
  ) as CatalogSample[];
}

const aromaOfWord = new Map<string, string>();
for (const group of vocabulary.groups) {
  if (group.domain !== "descriptor") continue;
  for (const word of [group.key, ...group.source_keys]) {
    aromaOfWord.set(word, group.key);
  }
}

/** A sampled catalog product as the bottle being recorded, its aromas under their current names. */
export function sampleProduct(
  sample: CatalogSample,
  aromas: readonly string[] = sample.aromas,
): SensoryProduct {
  const descriptors: SensoryProductDescriptor[] = [];
  for (const raw of aromas) {
    const key = aromaOfWord.get(raw);
    if (!key || descriptors.some((d) => d.key === key)) continue;
    descriptors.push({
      key,
      label: key,
      section: "aroma",
      family: "test",
      traits: [],
      description: null,
      evidenceRefs: ["test"],
    });
  }
  return {
    name: sample.name,
    category: sample.category as SensoryProduct["category"],
    styleKey: sample.style_key,
    region: null,
    abv: sample.abv,
    ingredients: [...sample.ingredients],
    processes: [...sample.processes],
    grapeVarietyKeys: [],
    levels: sample.levels,
    levelSources: sample.level_sources ?? {},
    levelRefs: {},
    descriptors,
  };
}

/**
 * The BP cards as they were stored before the gauges (card-facts-v2). They
 * are never written again: the taste letters and the fit check still read
 * them, and a test of today's engine takes only their bottles
 * (fixtureProduct).
 */
export async function fixtures(): Promise<[string, LegacyCardFacts][]> {
  const names: string[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (entry.isFile && /^bp-\d+\.json$/.test(entry.name)) {
      names.push(entry.name);
    }
  }
  names.sort();
  const loaded: [string, LegacyCardFacts][] = [];
  for (const name of names) {
    const facts = readStoredCardFacts(
      JSON.parse(await Deno.readTextFile(new URL(name, dir))),
    );
    if (facts?.schema_version !== "card-facts-v2") {
      throw new Error(`${name} is not a stored card-facts-v2 card`);
    }
    loaded.push([name, facts]);
  }
  return loaded;
}

/**
 * The BP bottles answered on today's questionnaire: what each stored card
 * said of its bottle, set on the gauges and pickers its kind is asked.
 */
const BP_ANSWERS: Readonly<Record<string, readonly string[]>> = {
  // 샤또 마고: cherry, a bright acidity, and tannin that gripped.
  "bp-01": [
    "revisit:wouldAcceptAgain",
    "aroma:nose:cherry:liked",
    "level:acidity:4:liked",
    "level:tannin:4:disliked",
  ],
  // 해창 12도: its sweetness and acidity liked, too heavy and it stayed.
  "bp-02": [
    "level:sweetness:3:liked",
    "level:acidity:3:liked",
    "level:body:4:disliked",
    "level:finish_length:4:disliked",
  ],
  "bp-03": [
    "aroma:nose:floral:liked",
    "aroma:nose:pear:liked",
    "aroma:palate:vanilla:liked",
    "aroma:palate:wood:liked",
    "level:finish_length:4:liked",
  ],
  "bp-04": [
    "aroma:nose:floral:liked",
    "aroma:nose:peach:liked",
    "level:acidity:4:liked",
    "level:finish_length:2:liked",
  ],
  // 라프로익 쿼터 캐스크 (48%): peat liked, its heat a burden.
  "bp-05": [
    "aroma:nose:coconut:liked",
    "aroma:nose:peat:liked",
    "level:spice:4:disliked",
    "level:finish_length:4:liked",
  ],
  "bp-06": [
    "aroma:nose:apple:liked",
    "aroma:nose:citrus:liked",
    "level:acidity:4:liked",
    "level:sparkling:5:disliked",
    "level:finish_length:2:liked",
  ],
  "bp-07": [
    "aroma:nose:cherry:liked",
    "aroma:nose:chocolate:liked",
    "aroma:palate:orange_tangerine:liked",
    "level:spice:4:liked",
  ],
  "bp-09": [
    "aroma:nose:berry:liked",
    "aroma:nose:roasted:liked",
    "aroma:palate:vanilla:liked",
    "level:tannin:4:disliked",
  ],
  "bp-10": [
    "aroma:nose:berry:liked",
    "aroma:nose:floral:liked",
    "aroma:palate:nutty:liked",
    "level:body:2:liked",
    "level:finish_length:4:liked",
  ],
  "bp-11": ["aroma:nose:pear:liked", "level:body:4:disliked"],
  // 아드벡 우거다일 (54.2%): smoke liked, too sweet, too heavy, too long.
  "bp-12": [
    "aroma:nose:smoke:liked",
    "level:peat:5:liked",
    "level:sweetness:4:disliked",
    "level:body:4:disliked",
    "level:finish_length:5:disliked",
  ],
  "bp-13": [
    "aroma:nose:jammy:liked",
    "aroma:nose:tropical_fruit:liked",
    "level:sweetness:5:disliked",
    "level:body:4:disliked",
    "level:finish_length:5:disliked",
  ],
  "bp-15": [
    "level:sweetness:3:liked",
    "level:acidity:3:liked",
    "level:finish_length:2:liked",
  ],
  "bp-18": [
    "revisit:wantAgain",
    "aroma:nose:floral:liked",
    "aroma:nose:pear:liked",
    "level:body:2:liked",
    "level:finish_length:2:liked",
  ],
  "bp-19": [
    "revisit:wouldAcceptAgain",
    "level:acidity:3:liked",
    "level:finish_length:2:liked",
  ],
  "bp-20": ["level:body:2:liked", "aroma:finish:plum:liked"],
};

/** One record per BP bottle, as today's questionnaire would hold it. */
export async function bpRecords(): Promise<[string, SensoryRecord][]> {
  return (await fixtures()).map(([file, stored]) => {
    const name = file.replace(/\.json$/, "");
    const answers = BP_ANSWERS[name];
    if (!answers) throw new Error(`${name} has no answers`);
    return [name, recordFrom(name, answers, fixtureProduct(stored))];
  });
}

/** Korean display names for fixture products whose catalog name is not Korean. */
export const FIXTURE_DISPLAY_NAMES: Readonly<Record<string, string>> = {
  "Château Margaux": "샤또 마고",
  "Trimbach Riesling": "트림바크 리슬링",
  "Moët & Chandon Brut Impérial": "모엣 임페리얼",
  "Aberlour A’Bunadh": "아벨라워 아부나흐",
  "Marqués de Riscal Reserva 2021": "마르케스 데 리스칼 레세르바",
  "Tanqueray London Dry Gin": "탱커레이",
  "이니스킬린 골드 비달 아이스와인 오크 에이지드": "이니스킬린 아이스와인",
  "우고노츠키 준마이 긴죠 료우후": "료우후",
  "센킨 유키다루마 시보리타테 니고리": "센킨 유키다루마",
  "그레이트 노션 탑 다운": "탑 다운",
};
