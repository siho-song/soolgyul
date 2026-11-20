import { buildCardFacts } from "../../_shared/taste_card/findings/conclusions.ts";
import { regionPath } from "../../_shared/taste_card/dictionary/dictionary.ts";
import { wineRegionKey } from "../../_shared/taste_card/prepare/bottle.ts";
import {
  CARD_FACTS_SCHEMA_VERSION,
  readStoredCardFacts,
  type Subject,
} from "../../_shared/taste_card/facts/facts.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
import {
  fixtureProduct,
  fixtures,
  recordFrom,
} from "../helpers/card_fixture_record.ts";
import { assert } from "../helpers/assert.ts";

const same = (a: unknown, b: unknown) =>
  JSON.stringify(a) === JSON.stringify(b);

/** The bottle of one BP card, as the catalog would serve it. */
async function bottleOf(name: string): Promise<SensoryProduct> {
  const facts = new Map(await fixtures()).get(`${name}.json`);
  assert(facts, `no fixture ${name}`);
  return fixtureProduct(facts);
}

Deno.test("card conclusions: only likes means nothing to adjust; only burdens means nothing to keep and 취향 유랑자", async () => {
  // 해창 9도: its sweetness, its acidity and its clean finish, all liked.
  const likes = buildCardFacts(
    recordFrom("likes", [
      "level:sweetness:3:liked",
      "level:acidity:3:liked",
      "level:finish_length:2:liked",
    ], await bottleOf("bp-15")),
  );
  assert(likes.schema_version === CARD_FACTS_SCHEMA_VERSION);
  // The facts as stored read back whole, for the letters and the fit check.
  assert(same(readStoredCardFacts(JSON.parse(JSON.stringify(likes))), likes));
  assert(likes.summary.next_choice.keep.length > 0);
  assert(likes.summary.next_choice.adjust.length === 0);
  assert(likes.sections.burden.length === 0);

  // 이니스킬린 아이스와인: too sweet, too heavy, and it stayed too long.
  const only = buildCardFacts(
    recordFrom("burden-only", [
      "level:sweetness:5:disliked",
      "level:body:4:disliked",
      "level:finish_length:5:disliked",
    ], await bottleOf("bp-13")),
  );
  assert(only.nickname === "취향 유랑자");
  assert(only.summary.next_choice.keep.length === 0);
  assert(
    same(only.summary.next_choice.adjust.map((a) => a.direction), [
      "lower",
      "lower",
      "shorter",
    ]),
  );
  assert(only.sections.positive.length === 0);
  assert(only.sections.burden.length === 2);
});

Deno.test("card conclusions: a record without reactions is still a valid card with 취향 탐색자", async () => {
  // A middle 바디 is an answer the card keeps and says nothing of.
  const middle = buildCardFacts(
    recordFrom("middle", ["level:body:3:liked"], await bottleOf("bp-02")),
  );
  assert(middle.gauges.length === 1 && middle.reactions.length === 0);
  assert(middle.nickname === "취향 탐색자" && middle.findings.length === 0);
  assert(
    same(middle.summary.next_choice, {
      keep: [],
      adjust: [],
      avoid_combinations: [],
    }),
  );
  assert(
    middle.sections.positive.length === 0 &&
      middle.sections.burden.length === 0,
  );
  // The bottle is read all the same.
  assert(middle.product_facts.length > 0);

  // An aroma that bothered after swallowing, with no drinking answer, is a
  // burden on its own.
  const alone = buildCardFacts(
    recordFrom("alone", ["aroma:finish:oak:disliked"], await bottleOf("bp-01")),
  );
  assert(alone.reactions.every((r) => r.reaction === "burden"));
  assert(alone.nickname === "취향 유랑자");
  assert(
    alone.sections.burden.length === 1 &&
      alone.findings.some((f) =>
        f.thinking === "persistence" && f.frame === "burden"
      ),
  );
});

Deno.test("card conclusions: wanting more of a taste adjusts it higher, too much adjusts it lower", async () => {
  const weak = buildCardFacts(
    recordFrom("weak", ["level:acidity:2:disliked"], {
      ...await bottleOf("bp-01"),
      levels: { acidity: 2 as const },
    }),
  );
  const [higher] = weak.summary.next_choice.adjust;
  assert(higher.subject.key === "acidity" && higher.direction === "higher");

  // The catalog puts this takju at the lowest acidity, yet the reader found it too sour.
  const sour = buildCardFacts(
    recordFrom("sour", ["level:acidity:4:disliked"], {
      ...await bottleOf("bp-02"),
      levels: { acidity: 1 as const },
    }),
  );
  const [lower] = sour.summary.next_choice.adjust;
  assert(lower.subject.key === "acidity" && lower.direction === "lower");

  // A finish too brief is wanted longer, one that stayed too long shorter;
  // 끝맛의 인상 is no level a bottle can be looked for by.
  const directions = async (key: string) =>
    buildCardFacts(recordFrom(key, [key], await bottleOf("bp-01"))).summary
      .next_choice.adjust.map((a) => `${a.subject.key}:${a.direction}`);
  assert(
    same(await directions("level:finish_length:1:disliked"), [
      "persistence:higher",
    ]),
  );
  assert(
    same(await directions("level:finish_length:5:disliked"), [
      "persistence:shorter",
    ]),
  );
  assert(same(await directions("level:finish_character:5:disliked"), []));
});

Deno.test("card conclusions: a burden pair is avoided together", async () => {
  const facts = buildCardFacts(
    recordFrom("pair", [
      "aroma:nose:jammy:liked",
      "aroma:nose:tropical_fruit:liked",
      "level:sweetness:5:disliked",
      "level:body:4:disliked",
    ], await bottleOf("bp-13")),
  );
  const pair: Subject[] = [{ domain: "taste", key: "sweetness" }, {
    domain: "mouthfeel",
    key: "heavy",
  }];
  assert(same(facts.summary.next_choice.avoid_combinations, [pair]));
});

Deno.test("card conclusions: the order of answers does not change the card", async () => {
  const product = await bottleOf("bp-01");
  const keys = [
    "revisit:wouldAcceptAgain",
    "aroma:nose:cherry:liked",
    "aroma:palate:vanilla:liked",
    "level:acidity:4:liked",
    "level:tannin:4:disliked",
    "level:finish_length:4:liked",
    "aroma:finish:oak:disliked",
  ];
  const once = buildCardFacts(recordFrom("order", keys, product));
  const again = buildCardFacts(
    recordFrom("order", [...keys].reverse(), {
      ...product,
      descriptors: [...product.descriptors].reverse(),
    }),
  );
  assert(same(once, again), "conclusions depend on input order");
});

Deno.test("card conclusions: an aroma answer is explained by what the aroma does, unless the drink explains it better", async () => {
  // The Alsace fixture.
  const base = await bottleOf("bp-04");
  const chosen = (
    answers: string[],
    section: "positive" | "burden" = "positive",
  ) => {
    const facts = buildCardFacts(
      recordFrom(answers.join(","), answers, base),
    );
    return facts.sections[section]
      .map((id) => facts.findings.find((d) => d.id === id)!)
      .map((d) => `${d.row}#${d.frame}`);
  };
  const peach = "aroma:nose:peach:liked";
  // Liked or a burden, by the nose or in the mouth: what the aroma does.
  assert(same(chosen([peach]), ["effect_ripe_fruit#liked"]));
  assert(
    same(chosen(["aroma:palate:peach:liked"]), ["effect_ripe_fruit#liked"]),
  );
  assert(
    same(chosen(["aroma:nose:peach:disliked"], "burden"), [
      "effect_ripe_fruit#burden",
    ]),
  );
  // Beside a liked acidity the pairing explains both.
  assert(
    chosen([peach, "level:acidity:4:liked"])[0].startsWith(
      "combination_fruit_scent_acidity#",
    ),
  );
  // Two liked aromas: their pairing explains both, so there is one paragraph.
  const pair = chosen(["aroma:nose:floral:liked", peach]);
  assert(pair.length === 1 && pair[0].startsWith("combination_aroma_pair#"));
});

Deno.test("card reading: a sparkling wine from 샹파뉴 reads as 샴페인, the way the catalog stores it", () => {
  const product = (name: string, region: string | null) => ({
    name,
    category: "wine" as const,
    styleKey: "sparkling_wine",
    region,
    abv: null,
    levels: {},
    levelRefs: {},
    descriptors: [],
  });
  const cases: [string, string | null, string | null][] = [
    // the region label, or a sub-region with its own style
    ["모엣 샹동 브뤼 임페리얼", "샹빠뉴(Champagne)", "champagne_sparkling"],
    [
      "까띠에르 브뤼 블랑 드 블랑",
      "샹빠뉴(Champagne) > 꼬뜨 데 블랑(Côte des Blancs)",
      "cote_des_blancs_sparkling",
    ],
    // an appellation in the name when the region is blank
    ["니노 프랑코 루스티코 프로세코", null, "prosecco_sparkling"],
    // a new-world traditional-method region
    [
      "글로리아 페레 바 데 비 울트라 뀌베",
      "캘리포니아(California) > 소노마 카운티(Sonoma County)",
      "new_world_traditional_sparkling",
    ],
    [
      "미구엘 토레스 에스텔라도 로제",
      "센트럴 밸리(Central Valley)",
      "chile_central_valley_sparkling",
    ],
    // a sparkling wine from nowhere the table knows stays a plain sparkling wine
    ["그라함 벡 브뤼", "웨스턴 케이프(Western Cape)", null],
    // a Frizzante of Austria is no Sekt
    [
      "지게티 블랑 드 블랑 브뤼",
      "부르겐란트(Burgenland)",
      "austria_sekt_sparkling",
    ],
    ["지게티 프리잔테 로제", "부르겐란트(Burgenland)", null],
    // 람브루스코 is read from the name, wherever in Italy the bottle is from
    ["람부르스코 만토바", "롬바르디아(Lombardia)", "lambrusco_sparkling"],
    ["체치 말바시아 브뤼", "에밀리아 로마냐(Emilia-Romagna)", null],
  ];
  for (const [name, region, expected] of cases) {
    const got = wineRegionKey(product(name, region));
    if (got !== expected) throw new Error(`${name}: ${got} != ${expected}`);
  }
});

Deno.test("card reading: a place's own style is read for each kind that has one, an orange and a fortified wine too", () => {
  const product = (styleKey: string, place: string) => ({
    name: "병",
    category: "wine" as const,
    styleKey,
    region: regionPath(place),
    abv: null,
    levels: {},
    levelRefs: {},
    descriptors: [],
  });
  const cases: [string, string, string | null][] = [
    // a village reads its own style before the bank it lies on
    ["red_wine", "fr_pauillac", "fr_pauillac_red"],
    // a kind the place had no style for
    ["rose_wine", "fr_bourgogne", "fr_bourgogne_rose"],
    // an orange wine has a colour of its own, a fortified wine is matched by its kind
    ["orange_wine", "au_mclaren_vale", "au_mclaren_vale_orange"],
    ["fortified_wine", "au_heathcote", "au_heathcote_fortified"],
    // a fortified wine does not read the red style of its place
    ["fortified_wine", "fr_pauillac", null],
    // a kind its label word decides reads no place
    ["vermouth", "it_piemonte", null],
  ];
  for (const [styleKey, place, expected] of cases) {
    const got = wineRegionKey(product(styleKey, place));
    if (got !== expected) {
      throw new Error(`${styleKey} ${place}: ${got} != ${expected}`);
    }
  }
});
