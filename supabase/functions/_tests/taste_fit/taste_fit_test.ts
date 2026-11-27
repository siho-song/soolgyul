import { assert, assertEquals } from "jsr:@std/assert@1";
import { readRecord } from "../../_shared/record_reading/read_record.ts";
import type { SensoryProduct } from "../../_shared/record_reading/record/sensory_record.ts";
import { recordFrom } from "../helpers/card_fixture_record.ts";
import { badgeForBottle } from "../../_shared/taste_fit/badge_for_bottle.ts";
import {
  preferencesFromRecords,
  type RecordForFit,
} from "../../_shared/taste_fit/preferences_from_records.ts";
import { composeCopy } from "../../_shared/taste_fit/copy.ts";
import { productFacts } from "../../_shared/taste_fit/facts.ts";
import {
  fitOfBottlesForUser,
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

/** One record of the bottle answered with these options, as the fit reads it. */
function recordOf(bottle: Bottle, keys: string[]): RecordForFit {
  const { answers, bottle: read } = readRecord(
    recordFrom(bottle.name, keys, productOf(bottle)),
  );
  return { answers, bottle: read };
}

/** One record of a whisky in which everything named was liked. */
const BALVENIE_LIKED = recordOf(BALVENIE, [
  "revisit:wantAgain",
  "aroma:nose:vanilla:liked",
  "level:sweetness:4:liked",
  "level:body:3:liked",
  "level:finish_length:4:liked",
]);

Deno.test("one liked whisky does not make every whisky a match", () => {
  const preferences = preferencesFromRecords([BALVENIE_LIKED]);
  // A bottle that stands where the liked one stands: a match.
  assertEquals(badgeForBottle(GLENFIDDICH, preferences).badge, "star");
  // Smoke the reader has never met in a whisky: different, not disliked.
  const smoky = badgeForBottle(LAPHROAIG, preferences);
  assertEquals(smoky.badge, "unfamiliar");
  assertEquals(smoky.reasons[0], { family: "effect_smoke" });
});

Deno.test("a kind the reader has no record of is not judged, and the copy says so", () => {
  const preferences = preferencesFromRecords([
    recordOf(TAKJU, ["level:sweetness:4:liked", "level:body:5:liked"]),
  ]);
  const verdict = badgeForBottle(DRY_RED, preferences);
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
    composeCopy(badgeForBottle(BALVENIE, preferences), null).sentence
      .startsWith("아직 마셔본 위스키 기록이 없어서"),
  );
  // The same reader's takju is judged.
  assertEquals(badgeForBottle(TAKJU, preferences).unjudged, undefined);
});

Deno.test("an aroma the reader minded is caught from the bottle's making too", () => {
  const preferences = preferencesFromRecords([
    recordOf(LAPHROAIG, [
      "aroma:nose:smoke:disliked",
      "revisit:doNotWantAgain",
    ]),
  ]);
  // Ardbeg's tags name no smoke; peated malt does.
  for (const bottle of [LAPHROAIG, ARDBEG]) {
    const verdict = badgeForBottle(bottle, preferences);
    assertEquals(verdict.badge, "caution", bottle.name);
    assertEquals(verdict.reasons, [{ family: "effect_smoke" }]);
  }
  // A whisky without it is no caution.
  assertEquals(badgeForBottle(BALVENIE, preferences).badge, "neutral");
  const copy = composeCopy(badgeForBottle(ARDBEG, preferences), null);
  assertEquals(copy.headline, "아쉬운 PICK");
  assertEquals(copy.tags[0], "#스모키향");
  assertEquals(new Set(copy.tags).size, copy.tags.length);
});

Deno.test("a dry-red drinker is told a sweet wine is different, never that it is a burden", () => {
  const preferences = preferencesFromRecords([
    recordOf(DRY_RED, ["level:body:4:liked"]),
  ]);
  const verdict = badgeForBottle(SWEET_WHITE, preferences);
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
  assert(
    ["star", "neutral"].includes(badgeForBottle(SOFT_RED, preferences).badge),
  );
});

Deno.test("answers that say nothing a bottle can be held against decide nothing", () => {
  // The middle step of 스파이시 asks for nothing a tag can show.
  const preferences = preferencesFromRecords([
    recordOf(GLENFIDDICH, ["level:spice:3:liked"]),
  ]);
  const mine = preferences.get("whisky")!;
  assertEquals([mine.tastes, mine.aromas, mine.peat_spice], [[], [], []]);
  const verdict = badgeForBottle(BALVENIE, preferences);
  assertEquals(verdict.unjudged, "nothing_shared");
  assertEquals(composeCopy(verdict, "민지").headline, "비교할 정보가 부족해요");
});

Deno.test("the copy names the bottle's place in its own kind and whose taste it is", () => {
  const preferences = preferencesFromRecords([BALVENIE_LIKED]);
  const match = composeCopy(badgeForBottle(GLENFIDDICH, preferences), "민지");
  assertEquals(match.headline, "딱 맞는 PICK");
  assert(match.tags.includes("#또렷한_단맛"), match.tags.join(" "));
  assert(match.tags.length <= 6);
  assertSentence(match.sentence, "민지", "좋아하신 특징");
  // One liked sensation met is never a match on its own.
  const single = preferencesFromRecords([
    recordOf(GLENFIDDICH, ["level:sweetness:4:liked"]),
  ]);
  const plain = composeCopy(badgeForBottle(BALVENIE, single), null);
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
  assert(facts[0].description?.includes("바닥에 보리를 펼쳐"));
  assert(facts[1].description?.startsWith("서늘한 기후에서"));
  // An explained fact carries the dictionary key the reader saves it by.
  assertEquals(facts.map((f) => [f.key, f.description !== null]), [
    ["producer:balvenie", true],
    ["grape:pinot_noir", true],
    ["region:fr", true],
    ["process:cultured_fermentation", true],
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
  const verdict = badgeForBottle(
    {
      abv_percent: null,
      style_key: "single_malt_whisky",
      category_key: "whisky",
      levels: {},
      aroma_tags: [],
    },
    preferencesFromRecords([BALVENIE_LIKED]),
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
const badgesBySweetness = (ledger: ReturnType<typeof preferencesFromRecords>) =>
  [1, 2, 3, 4, 5].map((level) => badgeForBottle(sweetAt(level), ledger).badge);

Deno.test("a liked gauge step is a range of one step either side, counted from the bottle's own number", () => {
  // The catalog reads this whisky's 단맛 as 4, and the reader liked it.
  const liked = preferencesFromRecords([
    recordOf(GLENFIDDICH, ["revisit:wantAgain", "level:sweetness:4:liked"]),
  ]);
  const [line] = liked.get("whisky")!.tastes;
  assertEquals(
    [line.axis, line.side, line.reach, line.level],
    ["sweetness", "like", "near", 4],
  );
  // 3, 4 and 5 are inside the range; two steps away is another kind of bottle.
  assertEquals(badgesBySweetness(liked), [
    "unfamiliar",
    "unfamiliar",
    "neutral",
    "neutral",
    "neutral",
  ]);
  assertEquals(badgeForBottle(sweetAt(2), liked).reasons, [{
    axis: "sweetness",
    level: "low",
  }]);
  // The step the reader set does not move the line off the bottle's number:
  // other bottles are read on the catalog's scale.
  const lowStep = preferencesFromRecords([
    recordOf(GLENFIDDICH, ["revisit:wantAgain", "level:sweetness:2:liked"]),
  ]);
  assertEquals(lowStep.get("whisky")!.tastes[0].level, 4);
  // A bottle the catalog has no number for: the step felt stands in.
  const unread = preferencesFromRecords([
    recordOf({ ...GLENFIDDICH, levels: { body: 3 } }, [
      "revisit:wantAgain",
      "level:sweetness:2:liked",
    ]),
  ]);
  assertEquals(unread.get("whisky")!.tastes[0].level, 2);
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
    preferencesFromRecords([
      recordOf(sweetAt(3), [`level:sweetness:${step}:disliked`]),
    ]);
  const reachOf = (ledger: ReturnType<typeof preferencesFromRecords>) => {
    const [line] = ledger.get("whisky")!.tastes;
    return [line.side, line.reach, line.level];
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
    assertEquals(reachOf(ledger), ["burden", reach, 3], `step ${step}`);
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
  const junmai = preferencesFromRecords([
    recordOf(sake, [
      "level:acidity:4:liked",
      "level:umami:4:liked",
      "level:finish_character:5:liked",
    ]),
  ]);
  assertEquals(
    [...junmai.values()].flatMap((group) =>
      group.tastes.map((line) => [line.axis, line.side, line.level])
    ),
    [["acidity", "like", 2]],
  );
  // 감칠맛, 스파이시, 피트 and 끝맛의 인상 are never given a number.
  const malt = preferencesFromRecords([
    recordOf(MACALLAN, [
      "level:spice:4:liked",
      "level:peat:1:liked",
      "level:finish_character:2:disliked",
    ]),
  ]).get("whisky")!;
  assertEquals(malt.tastes, []);
  assertEquals(
    malt.peat_spice.map((line) => [line.tag, line.wants, line.side]),
    [
      ["spice", "present", "like"],
      ["peat", "absent", "like"],
    ],
  );
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
    preferencesFromRecords([recordOf(bottle, keys)]).get("whisky")!.peat_spice
      .map((
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

  const reasons = (
    bottle: Bottle,
    ledger: ReturnType<typeof preferencesFromRecords>,
  ) => {
    const verdict = badgeForBottle(bottle, ledger);
    return [verdict.badge, verdict.unjudged ?? null, verdict.reasons];
  };
  const smoke = { family: "effect_smoke" as const };
  // 피트가 좋았다: the peated bottles match, by their tags or their making.
  const wanted = preferencesFromRecords([
    recordOf(LAPHROAIG, ["revisit:wantAgain", "level:peat:5:liked"]),
  ]);
  assertEquals(reasons(LAPHROAIG, wanted), ["neutral", null, [smoke]]);
  assertEquals(reasons(ARDBEG, wanted), ["neutral", null, [smoke]]);
  // A bottle without it is not counted against: its tags may only be short.
  assertEquals(reasons(BALVENIE, wanted), ["neutral", null, []]);
  assertEquals(reasons(UNTAGGED, wanted), ["no_info", "nothing_shared", []]);

  // 피트 없는 쪽이 좋았다: a bottle without it matches by its absence, a
  // peated one is another kind of bottle, never a burden.
  const unwanted = preferencesFromRecords([
    recordOf(BALVENIE, ["revisit:wantAgain", "level:peat:1:liked"]),
  ]);
  assertEquals(reasons(BALVENIE, unwanted), ["neutral", null, [{
    family: "effect_smoke",
    absent: true,
  }]]);
  assertEquals(
    composeCopy(badgeForBottle(BALVENIE, unwanted), null).tags[0],
    "#연기향_없는_깔끔함",
  );
  assertEquals(reasons(LAPHROAIG, unwanted), ["unfamiliar", null, [smoke]]);
  assertEquals(reasons(ARDBEG, unwanted), ["unfamiliar", null, [smoke]]);
  // No tags is not "no peat": nothing is said of the bottle nobody tagged.
  assertEquals(reasons(UNTAGGED, unwanted), ["no_info", "nothing_shared", []]);

  // 피트가 과해서 아쉬웠다: a peated bottle is a caution.
  const burden = preferencesFromRecords([
    recordOf(LAPHROAIG, ["revisit:doNotWantAgain", "level:peat:4:disliked"]),
  ]);
  assertEquals(reasons(LAPHROAIG, burden), ["caution", null, [smoke]]);
  assertEquals(reasons(ARDBEG, burden), ["caution", null, [smoke]]);
  assertEquals(reasons(BALVENIE, burden), ["neutral", null, []]);
  assertEquals(reasons(UNTAGGED, burden), ["no_info", "nothing_shared", []]);

  // 스파이시 reads the same way on the 향신료 tags.
  const spice = { family: "effect_spice" as const };
  const spicy = preferencesFromRecords([
    recordOf(MACALLAN, ["revisit:wantAgain", "level:spice:4:liked"]),
  ]);
  assertEquals(reasons(MACALLAN, spicy), ["neutral", null, [spice]]);
  assertEquals(reasons(BALVENIE, spicy), ["neutral", null, []]);
  const mild = preferencesFromRecords([
    recordOf(BALVENIE, ["revisit:wantAgain", "level:spice:1:liked"]),
  ]);
  assertEquals(reasons(BALVENIE, mild), ["neutral", null, [{
    family: "effect_spice",
    absent: true,
  }]]);
  assertEquals(
    composeCopy(badgeForBottle(BALVENIE, mild), null).tags[0],
    "#향신료향_없는_순함",
  );
  assertEquals(reasons(MACALLAN, mild), ["unfamiliar", null, [spice]]);
  const hot = preferencesFromRecords([
    recordOf(MACALLAN, ["revisit:doNotWantAgain", "level:spice:5:disliked"]),
  ]);
  assertEquals(reasons(MACALLAN, hot), ["caution", null, [spice]]);
  assertEquals(reasons(BALVENIE, hot), ["neutral", null, []]);
});

Deno.test("an aroma is held against every aroma the bottle carries, at whichever moment it was picked", () => {
  const tasted = { ...GLENFIDDICH, aroma_tags: ["vanilla", "smoke"] };
  const bottle = (
    name: string,
    nose: string[],
    later: Pick<Bottle, "palate_tags" | "finish_tags"> = {},
  ): Bottle => ({ ...GLENFIDDICH, name, aroma_tags: nose, ...later });
  const smoke = [{ family: "effect_smoke" as const }];

  // 스모키 향 liked: where the bottle carries it does not matter.
  const liked = preferencesFromRecords([
    recordOf(tasted, ["revisit:wantAgain", "aroma:nose:smoke:liked"]),
  ]);
  assertEquals(
    liked.get("whisky")!.aromas.map((line) => [line.family, line.side]),
    [["effect_smoke", "like"]],
  );
  for (
    const product of [
      bottle("코 smoke", ["smoke"]),
      bottle("코 pear, 입안 smoke", ["pear"], { palate_tags: ["smoke"] }),
      bottle("코 pear, 피니시 smoke", ["pear"], { finish_tags: ["smoke"] }),
    ]
  ) assertEquals(badgeForBottle(product, liked).reasons, smoke, product.name);
  assertEquals(
    badgeForBottle(
      bottle("코 pear, 입안 vanilla", ["pear"], { palate_tags: ["vanilla"] }),
      liked,
    ).reasons,
    [],
  );

  // 스모키 향 that bothered.
  const minded = preferencesFromRecords([
    recordOf(tasted, ["revisit:doNotWantAgain", "aroma:nose:smoke:disliked"]),
  ]);
  const badge = (product: Bottle) => badgeForBottle(product, minded).badge;
  assertEquals(
    badge(bottle("코 vanilla, 피니시 smoke", ["vanilla"], {
      finish_tags: ["smoke"],
    })),
    "caution",
  );
  assertEquals(badge(bottle("코 smoke", ["smoke"])), "caution");
  assertEquals(badge(bottle("코 vanilla", ["vanilla"])), "neutral");

  // A record answered with the three pickers of before: one aroma picked in
  // several of them is one line, and reads as the same preference.
  const before = preferencesFromRecords([
    recordOf(tasted, [
      "revisit:wantAgain",
      "aroma:nose:smoke:liked",
      "aroma:palate:smoke:liked",
      "aroma:finish:smoke:liked",
    ]),
  ]);
  assertEquals(before.get("whisky")!.aromas, liked.get("whisky")!.aromas);
});

class FakeRepository implements TasteFitRepository {
  constructor(
    private readonly records: RecordForFit[],
    private readonly products: TasteFitProductRow[],
    private readonly name: string | null = "민지",
    private readonly active = true,
  ) {}
  loadReader(): Promise<TasteFitReader> {
    return Promise.resolve({ active: this.active, display_name: this.name });
  }
  loadRecords(): Promise<RecordForFit[]> {
    return Promise.resolve(this.records);
  }
  loadProducts(ids: readonly string[]): Promise<TasteFitProductRow[]> {
    return Promise.resolve(this.products.filter((p) => ids.includes(p.id)));
  }
}

const ID_A = "11111111-1111-4111-8111-111111111111";
const ID_B = "22222222-2222-4222-8222-222222222222";

Deno.test("the service answers every requested id in order and says whether cards exist", async () => {
  const [balvenie] = await readProducts();
  const repository = new FakeRepository([BALVENIE_LIKED], [{
    ...balvenie,
    id: ID_A,
  }]);
  const response = await fitOfBottlesForUser(repository, "user", [ID_B, ID_A]);
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
  const empty = await fitOfBottlesForUser(
    new FakeRepository([], [{ ...balvenie, id: ID_A }]),
    "user",
    [ID_A],
  );
  assertEquals(empty.has_cards, false);
  // Without a record there is nothing of any kind to compare with.
  assertEquals(empty.products[0].badge, "no_info");
});

Deno.test("the service counts a record answered on the gauges", async () => {
  const [balvenie] = await readProducts();
  const today = recordOf(BALVENIE, [
    "revisit:wantAgain",
    "level:sweetness:4:liked",
    "level:body:3:liked",
  ]);
  const response = await fitOfBottlesForUser(
    new FakeRepository([today], [{ ...balvenie, id: ID_A }]),
    "user",
    [ID_A],
  );
  assertEquals(response.has_cards, true);
  assert(["star", "neutral"].includes(response.products[0].badge));
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

Deno.test("the store reads the reader's records from their answers and today's catalog, never from a card, and fails cleanly on a gateway page", async () => {
  const records = [
    {
      id: "record-new",
      created_at: "2026-11-16T00:00:00Z",
      questionnaire_version: "sensory-questionnaire-v2",
      alcohol_item_id: ID_A,
      answers: [
        {
          question_key: "sensory_revisit",
          selected_option_keys: ["revisit:wantAgain"],
        },
        {
          question_key: "sensory_palate_level",
          selected_option_keys: ["level:body:4:liked"],
        },
        {
          question_key: "sensory_nose_aroma",
          selected_option_keys: ["aroma:nose:oak:liked"],
        },
      ],
    },
    // Answered under a questionnaire that is no longer read: it says nothing.
    {
      id: "record-old",
      created_at: "2026-09-01T00:00:00Z",
      questionnaire_version: "sensory-questionnaire-v1",
      alcohol_item_id: ID_B,
      answers: [],
    },
  ];
  const urls: URL[] = [];
  const store = new SupabaseTasteFitRepository(
    "https://db.test",
    "service",
    (input) => {
      const url = new URL(String(input));
      urls.push(url);
      const table = url.pathname.split("/").at(-1);
      const rows = table === "drink_records"
        ? records
        : table === "alcohol_items"
        ? [{
          id: ID_A,
          name_ko: "시험 레드",
          name_en: null,
          abv_percent: 14,
          region_key: null,
          style_key: "red_wine",
          ingredient_keys: [],
          production_process_keys: [],
          grape_variety_keys: [],
          category: { category_key: "wine" },
        }]
        : [{ alcohol_item_id: ID_A, body: 4 }];
      return Promise.resolve(new Response(JSON.stringify(rows)));
    },
  );
  const read = await store.loadRecords("user");
  assertEquals(read.length, 1);
  const [{ answers, bottle }] = read;
  assertEquals(answers.revisit, "want_again");
  assertEquals(answers.gauges.map((g) => [g.axis, g.level, g.reaction]), [[
    "body",
    4,
    "liked",
  ]]);
  // The bottle is today's catalog row, and no card is read for what it says.
  assertEquals(bottle.levels.body?.level, 4);
  const [recordsUrl] = urls;
  assertEquals(recordsUrl.searchParams.get("order"), "created_at.asc,id.asc");
  assert(!recordsUrl.search.includes("semantic_snapshot"));
  // Only the bottle of the readable record is asked for.
  assertEquals(
    urls.filter((url) => url.pathname.endsWith("alcohol_items")).map((url) =>
      url.searchParams.get("id")
    ),
    [`in.(${ID_A})`],
  );

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
    "DatabaseError",
    "http_503",
    true,
  ]);
});
