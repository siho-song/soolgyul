import { styleProfiles } from "../../_shared/taste_card/dictionary/dictionary.ts";
import {
  type CardFacts,
  validateCardFacts,
} from "../../_shared/taste_card/facts/facts.ts";
import { normalizeSensoryAnswers } from "../../_shared/taste_card/record/answer_normalization.ts";
import {
  sensoryOptionsV1,
  type SensoryOptionV1,
} from "../../_shared/taste_card/record/questionnaire.ts";
import type {
  SensoryProduct,
  SensoryProductDescriptor,
  SensoryRecord,
} from "../../_shared/taste_card/record/sensory_record.ts";

export const dir = new URL("../fixtures/card_facts/", import.meta.url);
const options = new Map(
  sensoryOptionsV1().map((option) => [option.option_key, option]),
);

/** The questionnaire option behind one answer key. */
export function option(key: string): SensoryOptionV1 {
  const found = options.get(key);
  if (!found) throw new Error(`unknown questionnaire option ${key}`);
  return found;
}

// Fixtures written before 2026-11-06 may still name a finish by its meaning.
const FINISH_OPTIONS: Record<string, string> = {
  pleasantLength: "finish:pleasantLength",
  clean: "finish:clean",
  tooShort: "finish:tooShort",
  heavyResidue: "finish:heavy",
  lingeringAroma: "finish:aromaEcho",
  lingeringOffFlavor: "finish:offFlavor",
};
const REVISIT_OPTIONS: Record<CardFacts["record"]["revisit"], string> = {
  want_again: "revisit:wantAgain",
  would_accept_again: "revisit:wouldAcceptAgain",
  do_not_want_again: "revisit:doNotWantAgain",
  unknown: "revisit:unsure",
};

/** The fixture answer refs name the questionnaire answers behind each reaction. */
export function questionnaireOptions(facts: CardFacts): SensoryOptionV1[] {
  const keys = new Set<string>([REVISIT_OPTIONS[facts.record.revisit]]);
  for (const [section, state] of Object.entries(facts.record.section_states)) {
    if (state === "unknown") keys.add(`${section}:unsure`);
  }
  for (const reaction of facts.reactions) {
    for (const ref of reaction.answer_refs) {
      // Regenerated fixtures carry the questionnaire option keys themselves.
      if (options.has(ref)) {
        keys.add(ref);
        continue;
      }
      const [section, key, value] = ref.split(":");
      if (section === "finish") {
        keys.add(FINISH_OPTIONS[key]);
      } else if (section.endsWith("_reason")) {
        const side = reaction.reaction === "liked" ? "liked" : "disliked";
        keys.add(`reason:${section.slice(0, -7)}:${key}:${side}:${value}`);
      } else {
        if (section !== "taste") keys.add(`notice:${section}:${key}`);
        keys.add(`reaction:${section}:${key}:${value}`);
      }
    }
  }
  return [...keys].map(option);
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

export function fixtureProduct(facts: CardFacts): SensoryProduct {
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

export async function fixtures(): Promise<[string, CardFacts][]> {
  const names: string[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (entry.isFile && /^bp-\d+\.json$/.test(entry.name)) {
      names.push(entry.name);
    }
  }
  names.sort();
  const loaded: [string, CardFacts][] = [];
  for (const name of names) {
    loaded.push([
      name,
      validateCardFacts(
        JSON.parse(await Deno.readTextFile(new URL(name, dir))),
      ),
    ]);
  }
  return loaded;
}

/** A sensory record built from questionnaire option keys and a product. */
export function recordFrom(
  recordRef: string,
  answers: readonly string[],
  product: SensoryProduct,
): SensoryRecord {
  return {
    recordRef,
    product,
    ...normalizeSensoryAnswers(answers.map(option), {}),
  };
}

/** The record behind a fixture: its answers and its product facts. */
export function fixtureRecord(name: string, facts: CardFacts): SensoryRecord {
  return {
    recordRef: name,
    product: fixtureProduct(facts),
    ...normalizeSensoryAnswers(questionnaireOptions(facts), {}),
  };
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
