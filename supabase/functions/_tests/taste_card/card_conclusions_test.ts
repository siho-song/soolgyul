import { buildCardFacts } from "../../_shared/taste_card/findings/conclusions.ts";
import { wineRegionKey } from "../../_shared/taste_card/facts/reading.ts";
import type {
  CardFacts,
  Subject,
} from "../../_shared/taste_card/facts/facts.ts";
import {
  fixtureProduct,
  fixtureRecord,
  fixtures,
  questionnaireOptions,
  recordFrom,
} from "../helpers/card_fixture_record.ts";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
const same = (a: unknown, b: unknown) =>
  JSON.stringify(a) === JSON.stringify(b);
const keysOf = (facts: CardFacts, ids: readonly string[]) =>
  facts.reactions.filter((r) => ids.includes(r.id)).flatMap((r) =>
    r.answer_refs
  );

Deno.test("card conclusions: every BP fixture is exactly what the engine builds from its record", async () => {
  for (const [name, facts] of await fixtures()) {
    const built = buildCardFacts(fixtureRecord(name, facts));
    if (!same(built, facts)) {
      throw new Error(
        `${name} differs:\n${JSON.stringify(built.summary)}\n${
          JSON.stringify(built.sections)
        }`,
      );
    }
  }
});

Deno.test("card conclusions: only likes means nothing to adjust; only burdens means nothing to keep and 취향 유랑자", async () => {
  const all = await fixtures();
  const [name15, bp15] = all.find(([n]) => n === "bp-15.json")!;
  const likes = buildCardFacts(fixtureRecord(name15, bp15));
  assert(likes.summary.next_choice.adjust.length === 0);
  assert(likes.sections.burden.length === 0);

  const [, bp13] = all.find(([n]) => n === "bp-13.json")!;
  const burdens = bp13.reactions.filter((r) => r.reaction === "burden").map((
    r,
  ) => r.id);
  const only = buildCardFacts(
    recordFrom("burden-only", keysOf(bp13, burdens), fixtureProduct(bp13)),
  );
  assert(only.nickname === "취향 유랑자");
  assert(only.summary.next_choice.keep.length === 0);
  // Sweetness burdened while drinking; the weight lingered as well (the heavy
  // finish carries a side since 2026-10-25).
  assert(
    same(only.summary.next_choice.adjust.map((a) => a.direction), [
      "lower",
      "shorter",
    ]),
  );
  assert(only.sections.positive.length === 0);
  assert(only.sections.burden.length === 2);
});

Deno.test("card conclusions: a record without reactions is still a valid card with 취향 탐색자", async () => {
  const all = await fixtures();
  const [, bp02] = all.find(([n]) => n === "bp-02.json")!;
  const empty = buildCardFacts(
    recordFrom(
      "empty",
      ["reaction:taste:sweetness:fine"],
      fixtureProduct(bp02),
    ),
  );
  assert(empty.nickname === "취향 탐색자");
  assert(empty.findings.length === 0);
  // The balanced card keeps its 적당했어요 level so the guide can hold it.
  assert(
    same(empty.summary.next_choice, {
      keep: [{ domain: "taste", key: "sweetness" }],
      adjust: [],
      avoid_combinations: [],
    }),
  );
  assert(
    empty.sections.positive.length === 0 && empty.sections.burden.length === 0,
  );

  // A lingering heavy finish with no drinking answer is a burden on its own (2026-10-25).
  const [, bp01] = all.find(([n]) => n === "bp-01.json")!;
  const alone = buildCardFacts(
    recordFrom("alone", ["finish:heavy"], fixtureProduct(bp01)),
  );
  assert(
    alone.reactions.length === 1 && alone.reactions[0].reaction === "burden",
  );
  assert(
    alone.findings.some((f) =>
      f.thinking === "persistence" && f.frame === "burden_alone"
    ),
  );
});

Deno.test("card conclusions: 적당했어요 keeps that level and explains nothing", async () => {
  const [[, bp01]] = await fixtures();
  const product = {
    ...fixtureProduct(bp01),
    levels: { sweetness: 3 as const, body: 4 as const },
  };
  const facts = buildCardFacts(
    recordFrom("fine", [
      "reaction:taste:sweetness:fine",
      "notice:mouthfeel:heavy",
      "reaction:mouthfeel:heavy:fine",
      "revisit:unsure",
    ], product),
  );
  assert(
    facts.reactions.length === 2 &&
      facts.reactions.every((r) => r.reaction === "fine"),
  );
  assert(facts.findings.length === 0);
  assert(
    facts.sections.positive.length === 0 && facts.sections.burden.length === 0,
  );
  // Nothing liked or minded: the 적당했어요 levels are what to keep.
  assert(
    same(facts.summary.next_choice.keep.map((s) => s.key), [
      "sweetness",
      "heavy",
    ]),
  );
  assert(facts.summary.next_choice.adjust.length === 0);
});

Deno.test("card conclusions: wanting more of a taste adjusts it higher, too much adjusts it lower", async () => {
  const all = await fixtures();
  const [, bp01] = all.find(([n]) => n === "bp-01.json")!;
  const weak = buildCardFacts(
    recordFrom("weak", [
      "reaction:taste:acidity:disliked",
      "reason:taste:acidity:disliked:too_weak",
    ], { ...fixtureProduct(bp01), levels: { acidity: 2 as const } }),
  );
  const [higher] = weak.summary.next_choice.adjust;
  assert(higher.subject.key === "acidity" && higher.direction === "higher");

  const [, bp02] = all.find(([n]) => n === "bp-02.json")!;
  // The catalog puts this takju at the lowest acidity, yet the reader found it too sour.
  const sour = buildCardFacts(
    recordFrom("sour", [
      "reaction:taste:acidity:disliked",
      "reason:taste:acidity:disliked:too_strong",
    ], { ...fixtureProduct(bp02), levels: { acidity: 1 as const } }),
  );
  const [lower] = sour.summary.next_choice.adjust;
  assert(lower.subject.key === "acidity" && lower.direction === "lower");
});

Deno.test("card conclusions: a burden pair is avoided together", async () => {
  const all = await fixtures();
  const [name, bp13] = all.find(([n]) => n === "bp-13.json")!;
  const facts = buildCardFacts(fixtureRecord(name, bp13));
  const pair: Subject[] = [{ domain: "taste", key: "sweetness" }, {
    domain: "mouthfeel",
    key: "heavy",
  }];
  assert(same(facts.summary.next_choice.avoid_combinations, [pair]));
});

Deno.test("card conclusions: the order of answers does not change the card", async () => {
  const [[name, facts]] = await fixtures();
  const product = fixtureProduct(facts);
  const keys = questionnaireOptions(facts).map((r) => r.option_key);
  const once = buildCardFacts(recordFrom(name, keys, product));
  const again = buildCardFacts(
    recordFrom(name, [...keys].reverse(), {
      ...product,
      descriptors: [...product.descriptors].reverse(),
    }),
  );
  assert(same(once, again), "conclusions depend on input order");
});

Deno.test("card conclusions: an aroma answer is explained by what the aroma does, unless the drink explains it better", async () => {
  const all = await fixtures();
  const [, bp04] = all.find(([n]) => n === "bp-04.json")!;
  // The Alsace fixture, without and with a strength level.
  const base = fixtureProduct(bp04);
  const strong = {
    ...base,
    levels: { ...base.levels, aroma_intensity: 4 as const },
  };
  const rest = [
    "reaction:taste:sweetness:fine",
    "mouthfeel:unsure",
    "finish:unsure",
    "revisit:unsure",
  ];
  const peach = ["notice:aroma:peach", "reaction:aroma:peach:liked"];
  const dislike = ["notice:aroma:peach", "reaction:aroma:peach:disliked"];
  const chosen = (
    answers: string[],
    product = base,
    section: "positive" | "burden" = "positive",
  ) => {
    const facts = buildCardFacts(
      recordFrom(answers.join(","), answers, product),
    );
    return facts.sections[section]
      .map((id) => facts.findings.find((d) => d.id === id)!)
      .map((d) => `${d.row}#${d.frame}`);
  };
  // No reason, 은은해서: what the aroma does, the reason in its frame.
  assert(same(chosen([...peach, ...rest]), ["effect_ripe_fruit#liked"]));
  assert(
    same(chosen([...peach, "reason:aroma:peach:liked:gentle", ...rest]), [
      "effect_ripe_fruit#gentle",
    ]),
  );
  // 또렷해서: the same, unless the catalog agrees that the aromas are strong.
  const pronounced = [...peach, "reason:aroma:peach:liked:pronounced", ...rest];
  assert(same(chosen(pronounced), ["effect_ripe_fruit#liked"]));
  assert(same(chosen(pronounced, strong), ["intensity_aroma#liked_much"]));
  // A burden is explained the same way, whatever the catalog level says;
  // 너무 강해서 and 더 또렷했으면 keep the reader's reason in the frame.
  assert(
    same(chosen([...dislike, ...rest], strong, "burden"), [
      "effect_ripe_fruit#burden",
    ]),
  );
  assert(
    same(
      chosen(
        [...dislike, "reason:aroma:peach:disliked:too_strong", ...rest],
        strong,
        "burden",
      ),
      ["effect_ripe_fruit#excessive"],
    ),
  );
  assert(
    same(
      chosen(
        [...dislike, "reason:aroma:peach:disliked:too_weak", ...rest],
        strong,
        "burden",
      ),
      ["effect_ripe_fruit#too_weak"],
    ),
  );
  // 어울려서 with the acidity: the pairing answers that reason.
  assert(
    chosen([
      ...peach,
      "reason:aroma:peach:liked:harmony",
      "reaction:taste:acidity:liked",
      "mouthfeel:unsure",
      "finish:unsure",
      "revisit:unsure",
    ])[0].startsWith("combination_fruit_scent_acidity#"),
  );
  // Two liked aromas: their pairing explains both, so there is one paragraph.
  const two = [
    "notice:aroma:floral",
    "reaction:aroma:floral:liked",
    ...peach,
    ...rest,
  ];
  const pair = chosen(two);
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
    // the region label, or a sub-region of it
    ["모엣 샹동 브뤼 임페리얼", "샹빠뉴(Champagne)", "champagne_sparkling"],
    [
      "까띠에르 브뤼 블랑 드 블랑",
      "샹빠뉴(Champagne) > 꼬뜨 데 블랑(Côte des Blancs)",
      "champagne_sparkling",
    ],
    // an appellation in the name when the region is blank
    ["니노 프랑코 루스티코 프로세코", null, "prosecco_sparkling"],
    // a new-world traditional-method region
    [
      "글로리아 페레 바 데 비 울트라 뀌베",
      "캘리포니아(California) > 소노마 카운티(Sonoma County)",
      "new_world_traditional_sparkling",
    ],
    // a sparkling wine from nowhere the table knows stays a plain sparkling wine
    ["미구엘 토레스 에스텔라도 로제", "센트럴 밸리(Central Valley)", null],
  ];
  for (const [name, region, expected] of cases) {
    const got = wineRegionKey(product(name, region));
    if (got !== expected) throw new Error(`${name}: ${got} != ${expected}`);
  }
});
