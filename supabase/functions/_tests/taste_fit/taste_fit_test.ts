import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  type CardFacts,
  validateCardFacts,
} from "../../_shared/taste_card/facts/facts.ts";
import {
  buildLedger,
  type LedgerEntry,
} from "../../_shared/taste_fit/ledger.ts";
import { judgeProduct } from "../../_shared/taste_fit/judge.ts";
import { composeCopy } from "../../_shared/taste_fit/copy.ts";
import { productFacts } from "../../_shared/taste_fit/facts.ts";
import { judgeProductsForUser } from "../../_shared/taste_fit/service.ts";
import type {
  TasteFitProductRow,
  TasteFitRepository,
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

async function readCards(): Promise<CardFacts[]> {
  const dir = new URL("card_facts/", fixtures);
  const names: string[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (entry.isFile && /^bp-\d+\.json$/.test(entry.name)) {
      names.push(entry.name);
    }
  }
  names.sort();
  const cards: CardFacts[] = [];
  for (const name of names) {
    cards.push(
      validateCardFacts(
        JSON.parse(await Deno.readTextFile(new URL(name, dir))),
      ),
    );
  }
  return cards;
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
    ...p,
    id: `product-${i}`,
  }));
}

Deno.test("the ledger keeps only findings a search result can be checked against", async () => {
  const ledger = buildLedger(await readCards());
  assert(ledger.length > 0);
  for (const entry of ledger) {
    assert(
      Object.keys(entry.cond).length > 0 || entry.aromas !== null,
      `${entry.row} carries no condition`,
    );
    assert(
      !entry.row.startsWith("origin_"),
      "origin rows carry nothing checkable",
    );
    assert(
      !entry.row.startsWith("distinction_"),
      "distinction rows carry nothing checkable",
    );
    if (entry.row.startsWith("intensity_")) {
      assert(
        Object.values(entry.cond).every((want) => want !== "mid"),
        `${entry.row}: a mid band is not a preference`,
      );
    }
  }
  const sweet = ledger.find((e) =>
    e.row === "intensity_sweetness" && e.polarity === "burden"
  );
  assertEquals(sweet?.cond, { sweetness: "high" });
  const fruitAcid = ledger.find((e) =>
    e.row === "combination_fruit_scent_acidity"
  );
  assertEquals(fruitAcid?.cond, { acidity: "mid+" });
  assertEquals(fruitAcid?.aromas, ["fruit"]);
});

Deno.test("the sample bottles get the agreed badges", async () => {
  const ledger = buildLedger(await readCards());
  const products = await readProducts();
  const badges = Object.fromEntries(
    products.map((p) => [p.name_ko, judgeProduct(p, ledger).badge]),
  );
  assertEquals(badges, {
    "발베니 더블우드 12년": "caution",
    "라가불린 16년": "caution",
    "몬테스 알파 시라": "caution",
    "클라우디 베이 소비뇽 블랑": "star",
    "복순도가 손막걸리": "star",
    "모엣 샹동 그랑 빈티지": "star",
    "잭 다니엘스 젠틀맨 잭": "star",
    "쁘띠 몬테리아 스파클링": "star",
    "산토리 가쿠빈": "star",
    "화요 41": "caution",
    "도멘 부르소 쥬브레 샹베르땅": "neutral",
  });
});

Deno.test("a caution lists only the burden rows as the reader's own burdens", async () => {
  const ledger = buildLedger(await readCards());
  const products = await readProducts();
  const balvenie = products.find((p) => p.name_ko === "발베니 더블우드 12년")!;
  const verdict = judgeProduct(balvenie, ledger);
  assertEquals(verdict.hits, ["intensity_sweetness"]);
  // Taste rows name no aroma family, so the bottle's own leading tags follow.
  assertEquals(verdict.aromas, ["fresh_fruit", "sherry", "honey"]);
  const copy = composeCopy(verdict.badge, verdict.hits, verdict.aromas, "민지");
  assert(copy.headline.length > 0, "caution headline");
  assertEquals(copy.tags, ["#진한_단맛", "#과일향", "#셰리향", "#꿀향"]);
  assertSentence(copy.sentence, "민지", "부담");
  const hwayo = products.find((p) => p.name_ko === "화요 41")!;
  const hwayoVerdict = judgeProduct(hwayo, ledger);
  const hwayoCopy = composeCopy(
    "caution",
    hwayoVerdict.hits,
    hwayoVerdict.aromas,
    null,
  );
  assertEquals(hwayoCopy.tags, [
    "#묵직한_무게감",
    "#센_타격감",
    "#쌀향",
    "#꽃향",
  ]);
  assertSentence(hwayoCopy.sentence, null, "부담");
  assertEquals(hwayoCopy.headline, copy.headline, "one headline per badge");
});

Deno.test("a match lists what the reader enjoys, a plain bottle explains itself", async () => {
  const ledger = buildLedger(await readCards());
  const products = await readProducts();
  const boksoondoga = products.find((p) => p.name_ko === "복순도가 손막걸리")!;
  const verdict = judgeProduct(boksoondoga, ledger);
  const copy = composeCopy("star", verdict.hits, verdict.aromas, "민지");
  assert(copy.headline.length > 0, "star headline");
  // "fruit" has no dictionary name, so only two aroma tags follow the rows.
  assertEquals(copy.tags, [
    "#깔끔한_끝맛",
    "#싱그러운_과일향",
    "#산뜻한_산미",
    "#곡물향",
    "#발효향",
  ]);
  // Aromas under a family the reader liked come first: the citrus line.
  const cloudy = products.find((p) =>
    p.name_ko === "클라우디 베이 소비뇽 블랑"
  )!;
  assertEquals(judgeProduct(cloudy, ledger).aromas, [
    "citrus",
    "grapefruit",
    "lemon_lime",
  ]);
  assertSentence(copy.sentence, "민지", "좋아");
  assertSentence(
    composeCopy("star", ["effect_floral"], [], null).sentence,
    null,
    "좋아",
  );
  const neutral = composeCopy("neutral", [], ["pepper"], "민지");
  assertEquals(neutral.tags, ["#후추향"]);
  assertSentence(neutral.sentence, "민지", "무난");
  assertSentence(composeCopy("neutral", [], [], null).sentence, null, "무난");
  // Each badge has its own headline; the empty one says there is nothing to judge.
  const headlines = (["star", "caution", "neutral", "no_info"] as const).map(
    (badge) => composeCopy(badge, [], [], null).headline,
  );
  assertEquals(new Set(headlines).size, 4, `distinct headlines ${headlines}`);
  assert(headlines[3].includes("정보"), headlines[3]);
});

Deno.test("적당했어요 answers carry their band over and speak only when no like or burden does", async () => {
  const cards = await readCards();
  const products = await readProducts();
  const fineCard = structuredClone(cards[0]);
  for (const reaction of fineCard.reactions) reaction.reaction = "fine";
  fineCard.findings = [];
  const fineLedger = buildLedger([fineCard]);
  assertEquals(
    fineLedger.map((e) => [e.row, e.polarity, e.cond]),
    [
      ["fine_acidity", "fine", { acidity: "high" }],
      ["fine_astringency", "fine", { astringency: "high" }],
    ],
  );
  const cloudy = products.find((p) =>
    p.name_ko === "클라우디 베이 소비뇽 블랑"
  )!;
  const verdict = judgeProduct(cloudy, fineLedger);
  assertEquals(verdict.badge, "neutral");
  assertEquals(verdict.hits, ["fine_acidity"]);
  const copy = composeCopy(verdict.badge, verdict.hits, verdict.aromas, "민지");
  assertEquals(copy.tags, [
    "#적당한_산미",
    "#시트러스향",
    "#자몽향",
    "#레몬_라임향",
  ]);
  assertSentence(copy.sentence, "민지", "적당");
  // A bottle meeting no fine band stays plain with the generic sentence.
  const gakubin = products.find((p) => p.name_ko === "산토리 가쿠빈")!;
  const plain = judgeProduct(gakubin, fineLedger);
  assertEquals(plain.hits, []);
  assertSentence(
    composeCopy(plain.badge, plain.hits, plain.aromas, "민지").sentence,
    "민지",
    "무난",
  );
  // With the same reader's likes on acidity in the ledger, the like wins.
  const mixed = buildLedger([fineCard, cards[0]]);
  assertEquals(judgeProduct(cloudy, mixed).badge, "star");
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
  assert(facts[1].description?.startsWith("서늘한 곳에서"));
  assertEquals(productFacts(balvenie), []);
  // A producer the dictionary does not know keeps its catalog name without an explanation.
  assertEquals(
    productFacts({
      ...balvenie,
      producer: { key: "nobody", name_ko: "아무개", name_en: null },
    }),
    [{ kind: "producer", label: "아무개", description: null }],
  );
});

Deno.test("a bottle without levels or aroma tags cannot be judged", () => {
  const verdict = judgeProduct(
    {
      abv_percent: null,
      style_key: null,
      category_key: null,
      levels: {},
      aroma_tags: [],
    },
    [],
  );
  assertEquals(verdict, { badge: "no_info", hits: [], aromas: [] });
});

Deno.test("one dimension with both sides: the more specific side wins unless outnumbered", () => {
  const ledger: LedgerEntry[] = [
    {
      row: "intensity_sweetness",
      polarity: "burden" as const,
      cond: { sweetness: "high" as const },
      aromas: null,
      subjects: ["sweetness"],
      count: 1,
    },
    {
      row: "combination_sweet_acid",
      polarity: "positive" as const,
      cond: { sweetness: "mid+" as const, acidity: "mid+" as const },
      aromas: null,
      subjects: ["sweetness", "acidity"],
      count: 1,
    },
  ];
  const sweetAndSour = {
    abv_percent: null,
    style_key: null,
    category_key: null,
    levels: { sweetness: 4, acidity: 4 },
    aroma_tags: [],
  };
  // The pairing explains sweetness more specifically and is not outnumbered: a match.
  assertEquals(judgeProduct(sweetAndSour, ledger).badge, "star");
  // Three cards of plain burden outnumber the one specific comfort: a caution.
  assertEquals(
    judgeProduct(sweetAndSour, [{ ...ledger[0], count: 3 }, ledger[1]]).badge,
    "caution",
  );
  // Even split at the same specificity drops the dimension: nothing left.
  assertEquals(
    judgeProduct(sweetAndSour, [
      { ...ledger[0], count: 1 },
      {
        ...ledger[0],
        polarity: "positive",
        row: "intensity_sweetness",
        count: 1,
      },
    ]).badge,
    "neutral",
  );
});

class FakeRepository implements TasteFitRepository {
  constructor(
    private readonly cards: unknown[],
    private readonly products: TasteFitProductRow[],
    private readonly name: string | null = "민지",
  ) {}
  loadDisplayName(): Promise<string | null> {
    return Promise.resolve(this.name);
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
  assertEquals(response.products[1].badge, "caution");
  assertEquals(response.products[1].levels, {
    sweetness: 4,
    acidity: 1,
    body: 3,
    finish_length: 4,
  });
  assert(
    response.products[1].sentence.startsWith("평소 민지님께서 부담을 느끼신"),
  );
  assertEquals(response.products[1].facts, []);
  const empty = await judgeProductsForUser(
    new FakeRepository([{ not: "a card" }], [{ ...balvenie, id: ID_A }]),
    "user",
    [ID_A],
  );
  assertEquals(empty.has_cards, false);
  assertEquals(empty.products[0].badge, "neutral");
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

  const wrongMethod = await handleTasteFitRequest(
    new Request("https://edge.test/taste-fit", { method: "GET" }),
    repository,
    signedIn,
  );
  assertEquals(wrongMethod.status, 405);

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
