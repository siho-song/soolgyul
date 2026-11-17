import { assert, assertEquals } from "jsr:@std/assert@1";
import type {
  CardFacts,
  LegacyCardFacts,
} from "../../_shared/taste_card/facts/facts.ts";
import { buildCardFacts } from "../../_shared/taste_card/findings/conclusions.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
import {
  fixtures as bpFixtures,
  recordFrom,
} from "../helpers/card_fixture_record.ts";
import { buildLedger } from "../../_shared/taste_fit/ledger.ts";
import { judgeProduct } from "../../_shared/taste_fit/judge.ts";
import { composeCopy } from "../../_shared/taste_fit/copy.ts";
import { productFacts } from "../../_shared/taste_fit/facts.ts";
import {
  judgeProductsForUser,
  shownLevels,
} from "../../_shared/taste_fit/service.ts";
import {
  SupabaseTasteFitRepository,
  type TasteFitProductRow,
  type TasteFitReader,
  type TasteFitRepository,
} from "../../_shared/taste_fit/repository.ts";
import { handleTasteFitRequest } from "../../taste-fit/index.ts";

const fixtures = new URL("../fixtures/", import.meta.url);

/** A copy sentence: 해요체, the reader's name only when one was given. */
function assertSentence(sentence: string, name: string | null, term: string) {
  assert(/요[.?!]$/.test(sentence), `해요체: ${sentence}`);
  assert(sentence.includes(term), `${term}: ${sentence}`);
  assertEquals(
    sentence.includes("민지님"),
    name !== null,
    `name ${name}: ${sentence}`,
  );
}

type SampleProduct = TasteFitProductRow & { name_ko: string };

/** The BP cards as they were stored before the gauges. */
async function readCards(): Promise<LegacyCardFacts[]> {
  return (await bpFixtures()).map(([, facts]) => facts);
}

async function readProducts(): Promise<SampleProduct[]> {
  const raw = JSON.parse(
    await Deno.readTextFile(new URL("taste_fit_products.json", fixtures)),
  ) as Array<
    Pick<
      SampleProduct,
      | "name_ko"
      | "abv_percent"
      | "style_key"
      | "category_key"
      | "levels"
      | "aroma_tags"
    >
  >;
  return raw.map((p, i) => ({
    producer: null,
    grape_variety_keys: [],
    production_process_keys: [],
    region_key: null,
    palate_tags: [],
    finish_tags: [],
    ...p,
    id: `product-${i}`,
  }));
}

type Bottle = {
  name: string;
  style_key: string;
  category_key: string;
  abv_percent: number;
  levels: Record<string, number>;
  aroma_tags: string[];
  palate_tags?: string[];
  finish_tags?: string[];
  production_process_keys: string[];
};

const whisky = (
  name: string,
  abv: number,
  levels: Record<string, number>,
  aromas: string[],
  processes: string[] = [],
  style = "single_malt_whisky",
): Bottle => ({
  name,
  style_key: style,
  category_key: "whisky",
  abv_percent: abv,
  levels,
  aroma_tags: aromas,
  production_process_keys: processes,
});
const wine = (
  name: string,
  style: string,
  levels: Record<string, number>,
  aromas: string[],
): Bottle => ({
  name,
  style_key: style,
  category_key: "wine",
  abv_percent: 13.5,
  levels,
  aroma_tags: aromas,
  production_process_keys: [],
});

// The catalog's own values for these bottles, read on 2026-11-14.
const BALVENIE = whisky(
  "발베니 더블우드 12년",
  40,
  { sweetness: 4, acidity: 1, bitterness: 2, body: 3, finish_length: 4 },
  ["fresh_fruit", "aged_aromatic", "honey"],
  ["cask_finishing", "ex_sherry_cask", "multi_cask_blend"],
);
const GLENFIDDICH = whisky(
  "글렌피딕 12년",
  40,
  { sweetness: 4, acidity: 2, bitterness: 2, body: 3, finish_length: 3 },
  ["floral", "pear", "oak"],
  ["ex_bourbon_cask", "ex_sherry_cask"],
);
const MACALLAN = whisky(
  "맥캘란 12년 셰리 오크",
  40,
  { sweetness: 2, acidity: 2, bitterness: 2, body: 4, finish_length: 4 },
  ["dried_fruit", "oak", "spice"],
  ["ex_sherry_cask"],
);
const LAPHROAIG = whisky(
  "라프로익 10년",
  40,
  { sweetness: 1, acidity: 2, bitterness: 3, body: 4, finish_length: 4 },
  ["peat", "smoke", "mineral"],
  ["ex_bourbon_cask", "peated_malt"],
);
/** Its aroma tags name no smoke; only its making does. */
const ARDBEG = whisky(
  "아드벡 10년",
  46,
  { sweetness: 1, acidity: 2, bitterness: 2, body: 3, finish_length: 4 },
  ["chocolate", "lemon_lime"],
  ["ex_bourbon_cask", "non_chill_filtered", "peated_malt"],
);
const CASK_STRENGTH = whisky(
  "글렌파클라스 105",
  60,
  { sweetness: 4, acidity: 2, bitterness: 2, body: 5, finish_length: 5 },
  ["dried_fruit", "oak"],
  ["cask_strength", "ex_sherry_cask"],
);
const DRY_RED = wine("드라이 레드", "red_wine", {
  sweetness: 1,
  acidity: 3,
  astringency: 4,
  body: 4,
}, ["berry", "tobacco"]);
const SOFT_RED = wine("부드러운 레드", "red_wine", {
  sweetness: 1,
  acidity: 3,
  astringency: 3,
  body: 4,
}, ["berry", "oak"]);
const SWEET_WHITE = wine("모스카토", "white_wine", {
  sweetness: 5,
  acidity: 2,
  astringency: 1,
  body: 2,
}, ["peach", "floral"]);
const TAKJU: Bottle = {
  name: "해창 12도",
  style_key: "takju",
  category_key: "korean_traditional",
  abv_percent: 12,
  levels: { sweetness: 4, acidity: 3, bitterness: 1, body: 5 },
  aroma_tags: ["rice", "yogurt"],
  production_process_keys: [],
};

const DOMAIN: Record<string, "taste" | "mouthfeel" | "finish"> = {
  sweetness: "taste",
  acidity: "taste",
  bitterness: "taste",
  light: "mouthfeel",
  heavy: "mouthfeel",
  smooth: "mouthfeel",
  drying: "mouthfeel",
  bubbles: "mouthfeel",
  warmth: "mouthfeel",
  persistence: "finish",
  clean: "finish",
};

type Answer = [
  subject: string,
  reaction: "liked" | "burden",
  qualifier?: string,
];

/**
 * A card saved before the gauges (card-facts-v2), by the parts the ledger
 * reads: the bottle and the answers. Such cards are never written again and
 * keep counting as they did.
 */
function cardOf(
  bottle: Bottle,
  answers: Answer[],
  revisit = "want_again",
): LegacyCardFacts {
  return {
    schema_version: "card-facts-v2",
    record: {
      product_name: bottle.name,
      category: bottle.category_key,
      style_key: bottle.style_key,
      revisit,
    },
    reactions: answers.map(([key, reaction, qualifier], i) => ({
      id: `r${i}`,
      kind: "reaction",
      subject: { domain: DOMAIN[key] ?? "aroma", key },
      phase: "drinking",
      reaction,
      qualifier: qualifier ?? null,
      focus: false,
      answer_refs: [],
    })),
    product_facts: [
      ...Object.entries(bottle.levels).map(([dimension, level], i) => ({
        id: `l${i}`,
        kind: "product",
        fact: { type: "level", dimension, level },
        source: "catalog:levels:2",
      })),
      ...bottle.aroma_tags.map((key, i) => ({
        id: `a${i}`,
        kind: "product",
        fact: { type: "descriptor", key, section: "aroma" },
        source: "catalog:aromas",
      })),
      ...bottle.production_process_keys.map((key, i) => ({
        id: `p${i}`,
        kind: "product",
        fact: { type: "production", key },
        source: "catalog:production",
      })),
      {
        id: "abv",
        kind: "product",
        fact: { type: "abv", value: bottle.abv_percent },
        source: "catalog:abv",
      },
    ],
    findings: [],
  } as unknown as LegacyCardFacts;
}

/** The bottle as the catalog serves it to the card engine, its levels read for it. */
function productOf(bottle: Bottle): SensoryProduct {
  return {
    name: bottle.name,
    category: bottle.category_key as SensoryProduct["category"],
    styleKey: bottle.style_key,
    region: null,
    abv: bottle.abv_percent,
    ingredients: [],
    grapeVarietyKeys: [],
    processes: bottle.production_process_keys,
    levels: bottle.levels as SensoryProduct["levels"],
    levelSources: Object.fromEntries(
      Object.keys(bottle.levels).map((dimension) => [dimension, 2]),
    ),
    levelRefs: {},
    descriptors: bottle.aroma_tags.map((key) => ({
      key,
      label: key,
      section: "aroma" as const,
      family: "test",
      traits: [],
      description: null,
      evidenceRefs: ["test"],
    })),
  };
}

/** A card written today from these answers about the bottle, as it is stored. */
function gaugeCard(bottle: Bottle, keys: string[]): CardFacts {
  return JSON.parse(JSON.stringify(
    buildCardFacts(recordFrom(bottle.name, keys, productOf(bottle))),
  ));
}

/** One record of a whisky in which everything named was liked. */
const BALVENIE_LIKED = cardOf(BALVENIE, [
  ["vanilla", "liked"],
  ["sweetness", "liked"],
  ["bitterness", "liked"],
  ["heavy", "liked"],
  ["warmth", "liked"],
  ["persistence", "liked"],
]);

Deno.test("one liked whisky does not make every whisky a match", () => {
  const ledger = buildLedger([BALVENIE_LIKED]);
  // The same bottle and one that stands where it stands: a match.
  assertEquals(judgeProduct(BALVENIE, ledger).badge, "star");
  assertEquals(judgeProduct(GLENFIDDICH, ledger).badge, "star");
  // Smoke the reader has never met in a whisky: different, not disliked.
  const smoky = judgeProduct(LAPHROAIG, ledger);
  assertEquals(smoky.badge, "unfamiliar");
  assertEquals(smoky.reasons[0], { family: "effect_smoke" });
  // Far stronger than the 40% whose warmth they liked.
  const strong = judgeProduct(CASK_STRENGTH, ledger);
  assertEquals(strong.badge, "unfamiliar");
  assert(
    strong.reasons.some((r) => "axis" in r && r.axis === "alcohol"),
    JSON.stringify(strong.reasons),
  );
  // Nothing the reader called a burden exists, so nothing is a caution.
  for (
    const bottle of [BALVENIE, GLENFIDDICH, MACALLAN, LAPHROAIG, ARDBEG]
  ) {
    assert(judgeProduct(bottle, ledger).badge !== "caution", bottle.name);
  }
});

Deno.test("a stored answer that is neither liked nor minded makes no line", () => {
  // A card stored while 적당했어요 was an answer holds it as "fine".
  const answers: Answer[] = [["sweetness", "liked"], ["heavy", "liked"]];
  const stored = cardOf(BALVENIE, [
    ...answers,
    ["bitterness", "fine" as Answer[1]],
    ["warmth", "fine" as Answer[1]],
  ]);
  assertEquals(
    buildLedger([stored]),
    buildLedger([cardOf(BALVENIE, answers)]),
  );
});

Deno.test("a kind the reader has no record of is not judged, and the copy says so", () => {
  const ledger = buildLedger([
    cardOf(TAKJU, [["sweetness", "liked"], ["heavy", "liked"]]),
  ]);
  const verdict = judgeProduct(DRY_RED, ledger);
  assertEquals(verdict.badge, "no_info");
  assertEquals(verdict.unjudged, "no_record");
  const copy = composeCopy(verdict, "민지");
  assertEquals(copy.headline, "아직 와인 기록이 없어요");
  assertEquals(copy.tags, []);
  assertEquals(
    copy.sentence,
    "아직 마셔본 와인 기록이 없어서, 평소 입맛과 잘 맞을지 알아가는 단계예요. " +
      "와인을 드신 날 가벼운 감상이라도 남겨 주시면, 다음부턴 취향 궁합을 콕 짚어 드릴게요!",
  );
  // Each kind is named as the reader would say it.
  assert(
    composeCopy(judgeProduct(BALVENIE, ledger), null).sentence.startsWith(
      "아직 마셔본 위스키 기록이 없어서",
    ),
  );
  // The same reader's takju is judged.
  assertEquals(judgeProduct(TAKJU, ledger).unjudged, undefined);
});

Deno.test("an aroma the reader minded is caught from the bottle's making too", () => {
  const ledger = buildLedger([
    cardOf(LAPHROAIG, [["smoke", "burden"]], "do_not_want_again"),
  ]);
  // Ardbeg's tags name no smoke; peated malt does.
  for (const bottle of [LAPHROAIG, ARDBEG]) {
    const verdict = judgeProduct(bottle, ledger);
    assertEquals(verdict.badge, "caution", bottle.name);
    assertEquals(verdict.reasons, [{ family: "effect_smoke" }]);
  }
  // A whisky without it is no caution.
  assertEquals(judgeProduct(BALVENIE, ledger).badge, "neutral");
  const copy = composeCopy(judgeProduct(ARDBEG, ledger), null);
  assertEquals(copy.headline, "아쉬운 PICK");
  assertEquals(copy.tags[0], "#스모키향");
  assertEquals(new Set(copy.tags).size, copy.tags.length);
});

Deno.test("a burden closes its side; one that covers the whole kind closes only what lies beyond", () => {
  // 40% is the weakest a whisky comes, so "too hot at 40%" cannot tell 40% whiskies apart.
  const hot = buildLedger([
    cardOf(GLENFIDDICH, [["warmth", "burden"], ["sweetness", "liked"]]),
  ]);
  assert(
    hot.get("whisky")!.axes.some((l) => l.axis === "alcohol" && l.kindWide),
  );
  assert(judgeProduct(BALVENIE, hot).badge !== "caution");
  const strong = judgeProduct(CASK_STRENGTH, hot);
  assertEquals(strong.badge, "caution");
  assertEquals(strong.reasons[0], { axis: "alcohol", level: "high" });
  assertEquals(composeCopy(strong, "민지").tags[0], "#센_알코올감");
  // "Too weak" closes the weaker side: a red that feels drier still, not a sweeter one.
  const thin = buildLedger([
    cardOf(SOFT_RED, [["sweetness", "burden", "too_weak"]]),
  ]);
  assertEquals(judgeProduct(DRY_RED, thin).badge, "caution");
  assert(judgeProduct(SWEET_WHITE, thin).badge !== "caution");
});

Deno.test("the reader's own word for the strength outranks the stored number", () => {
  // The catalog has this sherry-cask whisky on sweetness 2; the reader called its sweetness 또렷하다.
  const ledger = buildLedger([
    cardOf(MACALLAN, [["sweetness", "liked", "pronounced"]]),
  ]);
  const [line] = ledger.get("whisky")!.axes;
  assertEquals([line.axis, line.side, line.reach], ["sweetness", "like", "up"]);
  assertEquals(line.position, 0.5);
  // A sweet whisky is inside what they liked, the driest ones are not.
  const reasonsOf = (bottle: Bottle) => judgeProduct(bottle, ledger);
  assert(reasonsOf(BALVENIE).badge !== "unfamiliar");
  assertEquals(reasonsOf(LAPHROAIG).badge, "unfamiliar");
});

Deno.test("why a sensation was liked sets which side counts as different", () => {
  const sweet = {
    ...GLENFIDDICH,
    levels: { ...GLENFIDDICH.levels, sweetness: 5 },
  };
  const dry = {
    ...GLENFIDDICH,
    levels: { ...GLENFIDDICH.levels, sweetness: 1 },
  };
  const gentle = buildLedger([
    cardOf(GLENFIDDICH, [["sweetness", "liked", "gentle"]]),
  ]);
  assertEquals(judgeProduct(sweet, gentle).badge, "unfamiliar");
  assertEquals(judgeProduct(dry, gentle).badge, "neutral");
  const pronounced = buildLedger([
    cardOf(GLENFIDDICH, [["sweetness", "liked", "pronounced"]]),
  ]);
  assertEquals(judgeProduct(dry, pronounced).badge, "unfamiliar");
  assertEquals(judgeProduct(sweet, pronounced).badge, "neutral");
});

Deno.test("a dry-red drinker is told a sweet wine is different, never that it is a burden", () => {
  const ledger = buildLedger([
    cardOf(DRY_RED, [
      ["heavy", "liked"],
    ]),
  ]);
  const verdict = judgeProduct(SWEET_WHITE, ledger);
  assertEquals(verdict.badge, "unfamiliar");
  const copy = composeCopy(verdict, "민지");
  assertEquals(copy.headline, "낯선 PICK");
  assertSentence(copy.sentence, "민지", "와인과는 꽤 다른");
  assertSentence(
    composeCopy(verdict, null).sentence,
    null,
    "부담이라고 하신 적은 없는",
  );
  // A red beside the one they drank is compared and is no caution.
  assert(["star", "neutral"].includes(judgeProduct(SOFT_RED, ledger).badge));
});

Deno.test("a dimension the kind has no numbers for decides nothing", () => {
  // Whiskies carry no astringency level, so 부드러운 목넘김 cannot be checked on any of them.
  const ledger = buildLedger([cardOf(GLENFIDDICH, [["smooth", "liked"]])]);
  assertEquals(ledger.get("whisky")!.axes, []);
  const verdict = judgeProduct(BALVENIE, ledger);
  assertEquals(verdict.unjudged, "nothing_shared");
  assertEquals(composeCopy(verdict, "민지").headline, "비교할 정보가 부족해요");
});

Deno.test("the copy names the bottle's place in its own kind and whose taste it is", () => {
  const ledger = buildLedger([BALVENIE_LIKED]);
  const match = composeCopy(judgeProduct(GLENFIDDICH, ledger), "민지");
  assertEquals(match.headline, "딱 맞는 PICK");
  assert(match.tags.includes("#또렷한_단맛"), match.tags.join(" "));
  assert(match.tags.length <= 6);
  assertSentence(match.sentence, "민지", "좋아하신 특징");
  // One liked sensation met is never a match on its own.
  const single = buildLedger([cardOf(GLENFIDDICH, [["sweetness", "liked"]])]);
  const plain = composeCopy(judgeProduct(BALVENIE, single), null);
  assertEquals(plain.headline, "무난한 PICK");
  assertSentence(plain.sentence, null, "위스키와");
});

Deno.test("product facts name the producer, grape, region and process with the dictionary's explanation", async () => {
  const [balvenie] = await readProducts();
  const facts = productFacts({
    ...balvenie,
    producer: { key: "balvenie", name_ko: null, name_en: "Balvenie" },
    grape_variety_keys: ["pinot_noir"],
    production_process_keys: ["cultured_fermentation", "unknown_key"],
    region_key: "fr",
  });
  assertEquals(facts.map((f) => [f.kind, f.label]), [
    ["producer", "발베니"],
    ["grape", "피노 누아"],
    ["region", "프랑스"],
    ["process", "배양 효모 발효"],
  ]);
  assert(facts[0].description?.includes("플로어 몰팅"));
  assert(facts[1].description?.startsWith("서늘한 기후에서"));
  // An explained fact carries the dictionary key the reader saves it by.
  assertEquals(facts.map((f) => [f.key, f.description !== null]), [
    ["producer:balvenie", true],
    ["grape:pinot_noir", true],
    ["region:fr", true],
    [null, false],
  ]);
  assertEquals(productFacts(balvenie), []);
  // A producer the dictionary does not know keeps its catalog name without an explanation.
  assertEquals(
    productFacts({
      ...balvenie,
      producer: { key: "nobody", name_ko: "아무개", name_en: null },
    }),
    [{ kind: "producer", label: "아무개", description: null, key: null }],
  );
});

Deno.test("the gauges are the stored levels, as a shelf tag gives them; a whisky shows no sweetness", () => {
  const row = (bottle: Bottle): TasteFitProductRow => ({
    id: bottle.name,
    producer: null,
    grape_variety_keys: [],
    region_key: null,
    palate_tags: [],
    finish_tags: [],
    ...bottle,
  });
  const jammy = wine("잼 같은 레드", "red_wine", {
    sweetness: 1,
    acidity: 2,
    astringency: 2,
    body: 4,
  }, ["dried_fruit", "vanilla"]);
  const sweetRed = wine("단 레드", "red_wine", {
    sweetness: 4,
    acidity: 2,
    astringency: 2,
    body: 4,
  }, ["dried_fruit"]);
  // A dry red reads 1 however ripe it smells: the number on the shelf tag.
  assertEquals(shownLevels(row(DRY_RED)).sweetness, 1);
  assertEquals(shownLevels(row(jammy)).sweetness, 1);
  assertEquals(shownLevels(row(sweetRed)).sweetness, 4);
  assertEquals(shownLevels(row(DRY_RED)).astringency, 4);
  assertEquals(shownLevels(row(TAKJU)).sweetness, 4);
  assertEquals("sweetness" in shownLevels(row(BALVENIE)), false);
});

Deno.test("a bottle without levels or aroma tags cannot be judged", () => {
  const verdict = judgeProduct(
    {
      abv_percent: null,
      style_key: "single_malt_whisky",
      category_key: "whisky",
      levels: {},
      aroma_tags: [],
    },
    buildLedger([BALVENIE_LIKED]),
  );
  assertEquals(verdict.badge, "no_info");
  assertEquals(verdict.unjudged, "no_data");
  assertEquals(
    composeCopy(verdict, "민지").headline,
    "아직 이 술의 정보가 없어요",
  );
});

/* ----------------------------------------- cards written from the gauges */

/** 글렌피딕 with another 단맛 number. */
const sweetAt = (level: number): Bottle => ({
  ...GLENFIDDICH,
  name: `단맛 ${level}`,
  levels: { ...GLENFIDDICH.levels, sweetness: level },
});
const badgesBySweetness = (ledger: ReturnType<typeof buildLedger>) =>
  [1, 2, 3, 4, 5].map((level) => judgeProduct(sweetAt(level), ledger).badge);

Deno.test("a liked gauge step is a range of one step either side, counted from the bottle's own number", () => {
  // The catalog reads this whisky's 단맛 as 4, and the reader liked it.
  const liked = buildLedger([
    gaugeCard(GLENFIDDICH, ["revisit:wantAgain", "level:sweetness:4:liked"]),
  ]);
  const [line] = liked.get("whisky")!.axes;
  assertEquals(
    [line.axis, line.side, line.reach, line.level, line.byStep],
    ["sweetness", "like", "near", 4, true],
  );
  // 3, 4 and 5 are inside the range; two steps away is another kind of bottle.
  assertEquals(badgesBySweetness(liked), [
    "unfamiliar",
    "unfamiliar",
    "neutral",
    "neutral",
    "neutral",
  ]);
  assertEquals(judgeProduct(sweetAt(2), liked).reasons, [{
    axis: "sweetness",
    level: "low",
  }]);
  // The step the reader set does not move the line off the bottle's number:
  // other bottles are read on the catalog's scale.
  const lowStep = buildLedger([
    gaugeCard(GLENFIDDICH, ["revisit:wantAgain", "level:sweetness:2:liked"]),
  ]);
  assertEquals(lowStep.get("whisky")!.axes[0].level, 4);
  // A bottle the catalog has no number for: the step felt stands in.
  const unread = buildLedger([
    gaugeCard({ ...GLENFIDDICH, levels: { body: 3 } }, [
      "revisit:wantAgain",
      "level:sweetness:2:liked",
    ]),
  ]);
  assertEquals(unread.get("whisky")!.axes[0].level, 2);
  assertEquals(badgesBySweetness(unread), [
    "neutral",
    "neutral",
    "neutral",
    "unfamiliar",
    "unfamiliar",
  ]);
});

Deno.test("a step marked 아쉬웠어요 closes the side it names: 4–5 that number and up, 1–2 that number and down, the middle that number alone", () => {
  const minded = (step: number) =>
    buildLedger([
      gaugeCard(sweetAt(3), [`level:sweetness:${step}:disliked`]),
    ]);
  const reachOf = (ledger: ReturnType<typeof buildLedger>) => {
    const [line] = ledger.get("whisky")!.axes;
    return [line.side, line.reach, line.level, line.byStep];
  };
  for (
    const [step, reach, badges] of [
      [5, "up", ["neutral", "neutral", "caution", "caution", "caution"]],
      [4, "up", ["neutral", "neutral", "caution", "caution", "caution"]],
      [2, "down", ["caution", "caution", "caution", "neutral", "neutral"]],
      [1, "down", ["caution", "caution", "caution", "neutral", "neutral"]],
      [3, "near", ["neutral", "neutral", "caution", "neutral", "neutral"]],
    ] as const
  ) {
    const ledger = minded(step);
    assertEquals(reachOf(ledger), ["burden", reach, 3, true], `step ${step}`);
    assertEquals(badgesBySweetness(ledger), [...badges], `step ${step}`);
  }
});

Deno.test("only a gauge the catalog has a number for makes a line; 감칠맛 has none", () => {
  const sake: Bottle = {
    name: "준마이",
    style_key: "junmai",
    category_key: "sake",
    abv_percent: 15,
    levels: { sweetness: 3, acidity: 2 },
    aroma_tags: ["rice"],
    production_process_keys: [],
  };
  const junmai = buildLedger([
    gaugeCard(sake, [
      "level:acidity:4:liked",
      "level:umami:4:liked",
      "level:finish_character:5:liked",
    ]),
  ]);
  assertEquals(
    [...junmai.values()].flatMap((group) =>
      group.axes.map((line) => [line.axis, line.side, line.level])
    ),
    [["acidity", "like", 2]],
  );
  // 감칠맛, 스파이시, 피트 and 끝맛의 인상 are never given a number.
  const malt = buildLedger([
    gaugeCard(MACALLAN, [
      "level:spice:4:liked",
      "level:peat:1:liked",
      "level:finish_character:2:disliked",
    ]),
  ]).get("whisky")!;
  assertEquals(malt.axes, []);
  assertEquals(malt.tags.map((line) => [line.tag, line.wants, line.side]), [
    ["spice", "present", "like"],
    ["peat", "absent", "like"],
  ]);
});

/** A whisky nobody tagged: levels alone. */
const UNTAGGED: Bottle = {
  ...BALVENIE,
  name: "태그 없는 병",
  aroma_tags: [],
  production_process_keys: [],
};

Deno.test("피트 and 스파이시 are held against whether a bottle carries the aroma, and a bottle nobody tagged is not judged on them", () => {
  const tagsOf = (bottle: Bottle, keys: string[]) =>
    buildLedger([gaugeCard(bottle, keys)]).get("whisky")!.tags.map((
      line,
    ) => [line.tag, line.wants, line.side]);
  // A liked 4–5 wants it there, a liked 1–2 wants it away, a 4–5 marked
  // 아쉬웠어요 wants it away as a burden; the middle and too little ask nothing.
  assertEquals(tagsOf(LAPHROAIG, ["level:peat:5:liked"]), [
    ["peat", "present", "like"],
  ]);
  assertEquals(tagsOf(BALVENIE, ["level:peat:1:liked"]), [
    ["peat", "absent", "like"],
  ]);
  assertEquals(tagsOf(LAPHROAIG, ["level:peat:4:disliked"]), [
    ["peat", "absent", "burden"],
  ]);
  assertEquals(tagsOf(LAPHROAIG, ["level:peat:3:liked"]), []);
  assertEquals(tagsOf(LAPHROAIG, ["level:peat:2:disliked"]), []);

  const reasons = (bottle: Bottle, ledger: ReturnType<typeof buildLedger>) => {
    const verdict = judgeProduct(bottle, ledger);
    return [verdict.badge, verdict.unjudged ?? null, verdict.reasons];
  };
  const smoke = { family: "effect_smoke" as const };
  // 피트가 좋았다: the peated bottles match, by their tags or their making.
  const wanted = buildLedger([
    gaugeCard(LAPHROAIG, ["revisit:wantAgain", "level:peat:5:liked"]),
  ]);
  assertEquals(reasons(LAPHROAIG, wanted), ["neutral", null, [smoke]]);
  assertEquals(reasons(ARDBEG, wanted), ["neutral", null, [smoke]]);
  // A bottle without it is not counted against: its tags may only be short.
  assertEquals(reasons(BALVENIE, wanted), ["neutral", null, []]);
  assertEquals(reasons(UNTAGGED, wanted), ["no_info", "nothing_shared", []]);

  // 피트 없는 쪽이 좋았다: a bottle without it matches by its absence, a
  // peated one is another kind of bottle, never a burden.
  const unwanted = buildLedger([
    gaugeCard(BALVENIE, ["revisit:wantAgain", "level:peat:1:liked"]),
  ]);
  assertEquals(reasons(BALVENIE, unwanted), ["neutral", null, [{
    family: "effect_smoke",
    absent: true,
  }]]);
  assertEquals(
    composeCopy(judgeProduct(BALVENIE, unwanted), null).tags[0],
    "#연기향_없는_깔끔함",
  );
  assertEquals(reasons(LAPHROAIG, unwanted), ["unfamiliar", null, [smoke]]);
  assertEquals(reasons(ARDBEG, unwanted), ["unfamiliar", null, [smoke]]);
  // No tags is not "no peat": nothing is said of the bottle nobody tagged.
  assertEquals(reasons(UNTAGGED, unwanted), ["no_info", "nothing_shared", []]);

  // 피트가 과해서 아쉬웠다: a peated bottle is a caution.
  const burden = buildLedger([
    gaugeCard(LAPHROAIG, ["revisit:doNotWantAgain", "level:peat:4:disliked"]),
  ]);
  assertEquals(reasons(LAPHROAIG, burden), ["caution", null, [smoke]]);
  assertEquals(reasons(ARDBEG, burden), ["caution", null, [smoke]]);
  assertEquals(reasons(BALVENIE, burden), ["neutral", null, []]);
  assertEquals(reasons(UNTAGGED, burden), ["no_info", "nothing_shared", []]);

  // 스파이시 reads the same way on the 향신료 tags.
  const spice = { family: "effect_spice" as const };
  const spicy = buildLedger([
    gaugeCard(MACALLAN, ["revisit:wantAgain", "level:spice:4:liked"]),
  ]);
  assertEquals(reasons(MACALLAN, spicy), ["neutral", null, [spice]]);
  assertEquals(reasons(BALVENIE, spicy), ["neutral", null, []]);
  const mild = buildLedger([
    gaugeCard(BALVENIE, ["revisit:wantAgain", "level:spice:1:liked"]),
  ]);
  assertEquals(reasons(BALVENIE, mild), ["neutral", null, [{
    family: "effect_spice",
    absent: true,
  }]]);
  assertEquals(
    composeCopy(judgeProduct(BALVENIE, mild), null).tags[0],
    "#향신료향_없는_순함",
  );
  assertEquals(reasons(MACALLAN, mild), ["unfamiliar", null, [spice]]);
  const hot = buildLedger([
    gaugeCard(MACALLAN, ["revisit:doNotWantAgain", "level:spice:5:disliked"]),
  ]);
  assertEquals(reasons(MACALLAN, hot), ["caution", null, [spice]]);
  assertEquals(reasons(BALVENIE, hot), ["neutral", null, []]);
});

Deno.test("an aroma is held against the bottle's tags of the stage it was picked in, and against its nose when that stage has none", () => {
  const tasted = { ...GLENFIDDICH, aroma_tags: ["vanilla", "smoke"] };
  const bottle = (
    name: string,
    nose: string[],
    staged: Pick<Bottle, "palate_tags" | "finish_tags"> = {},
  ): Bottle => ({ ...GLENFIDDICH, name, aroma_tags: nose, ...staged });
  const smoke = [{ family: "effect_smoke" as const }];

  // 스모키 향 liked in the mouth.
  const liked = buildLedger([
    gaugeCard(tasted, ["revisit:wantAgain", "aroma:palate:smoke:liked"]),
  ]);
  assertEquals(
    liked.get("whisky")!.families.map((
      line,
    ) => [line.family, line.side, line.stages]),
    [["effect_smoke", "like", ["palate"]]],
  );
  // The bottle's palate tags decide where it has them.
  assertEquals(
    judgeProduct(
      bottle("코 pear, 입안 smoke", ["pear"], { palate_tags: ["smoke"] }),
      liked,
    ).reasons,
    smoke,
  );
  assertEquals(
    judgeProduct(
      bottle("코 smoke, 입안 pear", ["smoke"], { palate_tags: ["pear"] }),
      liked,
    ).reasons,
    [],
  );
  // No palate tags: its nose stands in.
  assertEquals(
    judgeProduct(bottle("코 smoke", ["smoke"]), liked).reasons,
    smoke,
  );

  // 스모키 향 that bothered after swallowing.
  const minded = buildLedger([
    gaugeCard(tasted, [
      "revisit:doNotWantAgain",
      "aroma:finish:smoke:disliked",
    ]),
  ]);
  const badge = (product: Bottle) => judgeProduct(product, minded).badge;
  assertEquals(
    badge(bottle("코 vanilla, 피니시 smoke", ["vanilla"], {
      finish_tags: ["smoke"],
    })),
    "caution",
  );
  assertEquals(
    badge(bottle("코 smoke, 피니시 vanilla", ["smoke"], {
      finish_tags: ["vanilla"],
    })),
    "neutral",
  );
  assertEquals(badge(bottle("코 smoke", ["smoke"])), "caution");

  // One aroma picked in several places is one line with its stages.
  const everywhere = buildLedger([
    gaugeCard(tasted, [
      "aroma:nose:smoke:liked",
      "aroma:palate:smoke:liked",
      "aroma:finish:smoke:liked",
    ]),
  ]).get("whisky")!.families.filter((line) => line.family === "effect_smoke");
  assertEquals(everywhere.map((line) => line.stages), [
    ["nose", "palate", "finish"],
  ]);
  // A card from before the three pickers is held against the nose alone.
  const before = buildLedger([cardOf(tasted, [["smoke", "liked"]])]);
  assertEquals(before.get("whisky")!.families[0].stages, undefined);
  assertEquals(
    judgeProduct(
      bottle("코 pear, 입안 smoke", ["pear"], { palate_tags: ["smoke"] }),
      before,
    ).reasons,
    [],
  );
});

Deno.test("the BP cards, stored before the gauges, still build the ledger of every kind they hold", async () => {
  const ledger = buildLedger(await readCards());
  assertEquals([...ledger.keys()].sort(), [
    "sake",
    "sparkling_wine",
    "takju",
    "whisky",
    "wine",
    "yakju",
  ]);
  for (const [group, mine] of ledger) {
    assert(mine.axes.length + mine.families.length > 0, group);
    // Nothing of an old card is read as a gauge step or a tag line.
    assert(mine.axes.every((line) => !line.byStep), group);
    assertEquals(mine.tags, [], group);
    assert(mine.families.every((line) => line.stages === undefined), group);
  }
  // 샤또 마고's tannin was a burden: a red as tannic is a caution.
  assertEquals(judgeProduct(DRY_RED, ledger).badge, "caution");
});

Deno.test("a card from before the gauges still counts beside today's, with the answers the questionnaire no longer asks", () => {
  // 쓴맛 is no longer asked; the stored answer keeps its line.
  const old = cardOf(BALVENIE, [["bitterness", "liked"]]);
  const ledger = buildLedger([
    old,
    gaugeCard(GLENFIDDICH, ["revisit:wantAgain", "level:sweetness:4:liked"]),
  ]);
  assertEquals(
    ledger.get("whisky")!.axes.map((
      line,
    ) => [line.axis, line.side, line.byStep ?? false]),
    [["bitterness", "like", false], ["sweetness", "like", true]],
  );
  // What the old cards alone say is what they said before today's card came.
  assertEquals(buildLedger([old]).get("whisky")!.axes, [
    ledger.get("whisky")!.axes[0],
  ]);
});

class FakeRepository implements TasteFitRepository {
  constructor(
    private readonly cards: unknown[],
    private readonly products: TasteFitProductRow[],
    private readonly name: string | null = "민지",
    private readonly active = true,
  ) {}
  loadReader(): Promise<TasteFitReader> {
    return Promise.resolve({ active: this.active, display_name: this.name });
  }
  loadUserCardFacts(): Promise<unknown[]> {
    return Promise.resolve(this.cards);
  }
  loadProducts(ids: readonly string[]): Promise<TasteFitProductRow[]> {
    return Promise.resolve(this.products.filter((p) => ids.includes(p.id)));
  }
}

const ID_A = "11111111-1111-4111-8111-111111111111";
const ID_B = "22222222-2222-4222-8222-222222222222";

Deno.test("the service answers every requested id in order and says whether cards exist", async () => {
  const cards = await readCards();
  const [balvenie] = await readProducts();
  const repository = new FakeRepository(cards, [{ ...balvenie, id: ID_A }]);
  const response = await judgeProductsForUser(repository, "user", [ID_B, ID_A]);
  assertEquals(response.schema_version, "taste-fit-v1");
  assertEquals(response.has_cards, true);
  assertEquals(response.products.map((p) => p.product_id), [ID_B, ID_A]);
  assertEquals(response.products[0].badge, "no_info");
  assert(
    ["star", "neutral", "unfamiliar", "caution"].includes(
      response.products[1].badge,
    ),
  );
  // A whisky's gauges leave sweetness out.
  assertEquals(response.products[1].levels, {
    acidity: 1,
    body: 3,
    finish_length: 4,
  });
  assert(response.products[1].sentence.includes("민지님"));
  assertEquals(response.products[1].facts, []);
  const empty = await judgeProductsForUser(
    new FakeRepository([{ not: "a card" }], [{ ...balvenie, id: ID_A }]),
    "user",
    [ID_A],
  );
  assertEquals(empty.has_cards, false);
  // Without a card there is no record of any kind to compare with.
  assertEquals(empty.products[0].badge, "no_info");
});

Deno.test("the service counts a card written today, an old card whose words are gone, and leaves out a broken one", async () => {
  const [balvenie] = await readProducts();
  const products = [{ ...balvenie, id: ID_A }];
  const judged = async (cards: unknown[]) => {
    const response = await judgeProductsForUser(
      new FakeRepository(cards, products),
      "user",
      [ID_A],
    );
    return [response.has_cards, response.products[0].badge];
  };
  const today = gaugeCard(BALVENIE, [
    "revisit:wantAgain",
    "level:sweetness:4:liked",
    "level:body:3:liked",
  ]);
  const [hasCards, badge] = await judged([today]);
  assertEquals(hasCards, true);
  assert(["star", "neutral"].includes(`${badge}`), `${badge}`);
  // An old card holds 쓴맛, a reason and a nickname the engine dropped: it is
  // taken by its shape and still counted.
  const old = {
    ...cardOf(BALVENIE, [
      ["bitterness", "liked"],
      ["sweetness", "liked", "harmonious"],
    ]),
    nickname: "균형잡힌 비터 러버",
  };
  assertEquals((await judged([old]))[0], true);
  // A card of today's version that fails its check is left out, not an error.
  const broken = { ...today, nickname: "없는 별명" };
  assertEquals(await judged([broken]), [false, "no_info"]);
  assertEquals((await judged([broken, old]))[0], true);
});

Deno.test("the endpoint requires a session and a valid id list", async () => {
  const repository = new FakeRepository([], []);
  const post = (body: unknown) =>
    new Request("https://edge.test/taste-fit", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  const signedIn = () => Promise.resolve({ user_id: "user" });
  const anonymous = () => Promise.resolve(null);

  const unauthorized = await handleTasteFitRequest(
    post({ product_ids: [ID_A] }),
    repository,
    anonymous,
  );
  assertEquals(unauthorized.status, 401);
  assertEquals(
    (await unauthorized.json()).error_code,
    "authorization_required",
  );

  const badIds = await handleTasteFitRequest(
    post({ product_ids: ["not-a-uuid"] }),
    repository,
    signedIn,
  );
  assertEquals(badIds.status, 400);
  assertEquals((await badIds.json()).error_code, "product_ids_invalid");

  const tooMany = await handleTasteFitRequest(
    post({ product_ids: Array.from({ length: 21 }, () => ID_A) }),
    repository,
    signedIn,
  );
  assertEquals(tooMany.status, 400);

  const inactive = await handleTasteFitRequest(
    post({ product_ids: [ID_A] }),
    new FakeRepository([], [], "민지", false),
    signedIn,
  );
  assertEquals(inactive.status, 403);
  assertEquals((await inactive.json()).error_code, "active_account_required");

  const ok = await handleTasteFitRequest(
    post({ product_ids: [ID_A] }),
    repository,
    signedIn,
  );
  assertEquals(ok.status, 200);
  const body = await ok.json();
  assertEquals(body.has_cards, false);
  assertEquals(body.products.length, 1);
  const [product] = body.products;
  assertEquals(Object.keys(product).sort(), [
    "badge",
    "facts",
    "headline",
    "levels",
    "product_id",
    "sentence",
    "tags",
  ]);
  assertEquals(
    [
      product.product_id,
      product.badge,
      product.tags,
      product.levels,
      product.facts,
    ],
    [ID_A, "no_info", [], {}, []],
  );
  assert(product.headline.includes("정보"), product.headline);
  assertSentence(product.sentence, null, "정보");
});

Deno.test("the store reads every record past the API's row cap and fails cleanly on a gateway page", async () => {
  const records = Array.from({ length: 1500 }, (_, index) => ({
    id: `record-${index}`,
    taste_cards: [{ facts: { index } }],
  }));
  const urls: URL[] = [];
  const store = new SupabaseTasteFitRepository(
    "https://db.test",
    "service",
    (input) => {
      const url = new URL(String(input));
      urls.push(url);
      // Like PostgREST, never more than 1000 rows in one answer.
      const offset = Number(url.searchParams.get("offset") ?? 0);
      const limit = Math.min(
        Number(url.searchParams.get("limit") ?? 1000),
        1000,
      );
      return Promise.resolve(
        new Response(JSON.stringify(records.slice(offset, offset + limit))),
      );
    },
  );
  assertEquals((await store.loadUserCardFacts("user")).length, 1500);
  assertEquals(urls.length, 2);
  assertEquals(urls[1].searchParams.get("order"), "created_at.asc,id.asc");

  const down = new SupabaseTasteFitRepository(
    "https://db.test",
    "service",
    () =>
      Promise.resolve(
        new Response("<html>Service Unavailable</html>", { status: 503 }),
      ),
  );
  let failure: unknown = null;
  try {
    await down.loadReader("user");
  } catch (error) {
    failure = error;
  }
  const { name, code, transient } = failure as {
    name?: string;
    code?: string;
    transient?: boolean;
  };
  assertEquals([name, code, transient], [
    "TasteFitRepositoryError",
    "http_503",
    true,
  ]);
});
