/**
 * A still wine's sweetness on its card. The card tells it from the bottle's
 * own traits where they explain the answer (facts/wine_sweetness.ts): the
 * tannin and acidity that stand high among its kind for a wine that felt
 * dry, the aromas, soft tannin, low acidity or full body for a dry wine that
 * felt sweet. Where they explain nothing it is told as it was felt.
 */
import { regionPath } from "../../_shared/record_reading/dictionary/dictionary.ts";
import { readWineSweetness } from "../../_shared/record_reading/facts/wine_sweetness.ts";
import type { SensoryProduct } from "../../_shared/record_reading/record/sensory_record.ts";
import { writeCard } from "../../_shared/taste_card/writing/card_text.ts";
import { assert, same as equal } from "../helpers/assert.ts";
import { recordFrom } from "../helpers/card_fixture_record.ts";

type Levels = Partial<
  Record<"sweetness" | "acidity" | "astringency" | "body", number>
>;

/** A bottle whose levels were all read for it (an outside rating). */
function bottle(
  styleKey: string,
  levels: Levels,
  aromas: readonly string[] = [],
  category = "wine",
): SensoryProduct {
  return {
    name: "시험 병",
    category,
    styleKey,
    abv: null,
    ingredients: [],
    processes: [],
    grapeVarietyKeys: [],
    levels,
    levelSources: Object.fromEntries(
      Object.keys(levels).map((dimension) => [dimension, 2]),
    ),
    levelRefs: {},
    descriptors: aromas.map((key) => ({ section: "aroma" as const, key })),
  } as unknown as SensoryProduct;
}

/** 단맛 at a low step marked 아쉬웠어요, at a high step liked, at a high step marked 아쉬웠어요. */
const TOO_WEAK = ["level:sweetness:2:disliked"];
const GENTLE = ["level:sweetness:2:liked"];
const PRONOUNCED = ["level:sweetness:4:liked"];
const TOO_STRONG = ["level:sweetness:4:disliked"];

/** The card's paragraphs as one plain text. */
function written(product: SensoryProduct, answers: readonly string[]) {
  const card = writeCard(recordFrom("wine", answers, product));
  return {
    text: [...card.positive, ...card.burden].map((p) =>
      `${p.answer}: ${p.text}`
    ).join(" ").replaceAll("**", ""),
    marked: [...card.positive, ...card.burden].map((p) => p.text).join(" "),
    tags: card.tags.map((tag) => tag.label),
  };
}

Deno.test("wine sweetness: 더 있었으면 is told by the tannin and acidity that stand high among the kind", () => {
  for (
    const [style, levels, said] of [
      [
        "red_wine",
        { sweetness: 1, acidity: 3, astringency: 4, body: 4 },
        "이 레드 와인은 같은 종류 가운데서도 타닌이 많은 편이라, 떫은 조임에 단맛이 뒤로 밀려나 술이 메마르고 심심하게 느껴져요.",
      ],
      [
        "red_wine",
        { sweetness: 1, acidity: 4, astringency: 5, body: 4 },
        "이 레드 와인은 같은 종류 가운데서도 타닌이 많고 산미도 높은 편이라, 떫은 조임과 산미에 단맛이 눌려 술이 메마르고 심심하게 느껴져요.",
      ],
      [
        "white_wine",
        { sweetness: 1, acidity: 4, astringency: 1, body: 3 },
        "이 화이트 와인은 같은 종류 가운데서도 산미가 높은 편이라, 새콤한 산미에 단맛이 눌려 술이 메마르고 심심하게 느껴져요.",
      ],
      // Neither stands high: the lack is told as it was felt.
      [
        "red_wine",
        { sweetness: 1, acidity: 3, astringency: 3, body: 3 },
        "이 레드 와인은 단맛이 적어, 맛의 모서리를 감싸 줄 것이 없어 술이 메마르고 심심하게 느껴져요.",
      ],
    ] as const
  ) {
    const lack = written(bottle(style, levels), TOO_WEAK);
    equal(lack.text, `옅은 단맛: • ${said}`);
    assert(!/부담/.test(lack.text), `a lack worded as a burden: ${lack.text}`);
    equal(lack.tags, ["적은단맛"]);
  }
});

Deno.test("wine sweetness: a trait is not named against the reader's own answer", () => {
  const tannic = bottle("red_wine", {
    sweetness: 1,
    acidity: 3,
    astringency: 4,
    body: 4,
  });
  // The reader found the tannin low: it is not what made the wine dry.
  const { text } = written(tannic, [...TOO_WEAK, "level:tannin:2:liked"]);
  assert(!text.includes("타닌이 많은 편"), text);
  const soft = bottle("red_wine", {
    sweetness: 1,
    acidity: 3,
    astringency: 2,
    body: 3,
  });
  const firm = written(soft, [...PRONOUNCED, "level:tannin:4:disliked"]);
  assert(!firm.text.includes("타닌이 순한 편"), firm.text);
});

Deno.test("wine sweetness: a dry wine that felt sweet is told by its aromas and what is soft in it", () => {
  const dry = { sweetness: 1, acidity: 3, astringency: 3, body: 4 };
  const soft = { sweetness: 1, acidity: 3, astringency: 2, body: 3 };
  equal(
    written(bottle("red_wine", dry, ["vanilla"]), PRONOUNCED).text,
    "진한 단맛: • 이 레드 와인은 바닐라 향을 지니고 있어, 코로 들어온 달콤한 향이 단맛과 하나로 묶여 실제보다 더 달게 느껴져요.",
  );
  const minded = written(bottle("red_wine", dry, ["vanilla"]), TOO_STRONG);
  equal(
    minded.text,
    "진한 단맛: • 이 레드 와인은 바닐라 향을 지니고 있어, 코로 들어온 달콤한 향이 단맛과 하나로 묶여 실제보다 훨씬 달게 느껴져요.",
  );
  // The aroma opens its explanation, and the sweetness is the word marked.
  assert(minded.marked.includes("**바닐라 향**"), minded.marked);
  const both = written(
    bottle("red_wine", soft, ["vanilla", "peach"]),
    PRONOUNCED,
  );
  equal(
    both.text,
    "진한 단맛: • 이 레드 와인은 복숭아 향과 바닐라 향을 지닌 데다 같은 종류 가운데 타닌이 순한 편이라, 달콤한 향이 단맛처럼 느껴지고 그 단맛을 누르는 맛도 적어 단맛이 또렷하게 드러나요.",
  );
  // An aroma the dictionary has no name for is not said by its key.
  for (const aromas of [["beeswax"], ["beeswax", "vanilla"]]) {
    const { text } = written(bottle("red_wine", dry, aromas), PRONOUNCED);
    assert(!/[a-z]/.test(text), text);
  }
  equal(
    written(bottle("red_wine", soft), PRONOUNCED).text,
    "진한 단맛: • 이 레드 와인은 같은 종류 가운데 타닌이 순한 편이라, 단맛을 누르는 맛이 적어 단맛이 가려지지 않고 또렷하게 드러나요.",
  );
});

Deno.test("wine sweetness: the bottle's own traits tell before a place that gives no why, and before the glass", () => {
  // 옅은 단맛은 바롤로 지역의 특징이에요 is true of nine red wines in ten.
  const barolo = {
    ...bottle("red_wine", {
      sweetness: 1,
      acidity: 4,
      astringency: 5,
      body: 4,
    }),
    region: regionPath("it_barolo"),
    grapeVarietyKeys: ["nebbiolo"],
  } as SensoryProduct;
  const lack = written(barolo, [...TOO_WEAK, "level:body:4:liked"]);
  assert(
    lack.text.includes(
      "이 레드 와인은 같은 종류 가운데서도 타닌이 많고 산미도 높은 편이라, 떫은 조임과 산미에 단맛이 눌려 술이 메마르고 심심하게 느껴져요.",
    ) && !lack.text.includes("단맛은 바롤로"),
    lack.text,
  );
  // 묵직한 바디감이 단맛을 돋보이게 해서 … held in the glass too; why
  // a dry Merlot felt sweet is said first.
  const merlot = {
    ...bottle(
      "red_wine",
      { sweetness: 1, acidity: 3, astringency: 2, body: 4 },
      ["vanilla"],
    ),
    grapeVarietyKeys: ["merlot"],
  } as SensoryProduct;
  const sweet = written(merlot, [...PRONOUNCED, "level:body:4:liked"]);
  assert(
    sweet.text.includes(
      "이 레드 와인은 바닐라 향을 지닌 데다 같은 종류 가운데 타닌이 순한 편이라, 달콤한 향이 단맛처럼 느껴지고 그 단맛을 누르는 맛도 적어 단맛이 또렷하게 드러나요.",
    ),
    sweet.text,
  );
  // A red whose mark stands high among reds is not told that little
  // sweetness is its place's mark.
  const primitivo = {
    ...bottle("red_wine", {
      sweetness: 2,
      acidity: 2,
      astringency: 2,
      body: 4,
    }),
    region: regionPath("it_manduria"),
    grapeVarietyKeys: ["primitivo"],
  } as SensoryProduct;
  const gentle = written(primitivo, GENTLE);
  assert(!/적은 단맛은|단맛이 적어/.test(gentle.text), gentle.text);
});

Deno.test("wine sweetness: a dry wine with no such trait is told as it came across in this glass", () => {
  const dry = { sweetness: 1, acidity: 3, astringency: 3, body: 4 };
  // Oak and cherry are no sweet-leaning aromas.
  const liked = written(bottle("red_wine", dry, ["cherry", "oak"]), PRONOUNCED);
  equal(
    liked.text,
    "진한 단맛: • 이 레드 와인에서는 단맛이 또렷하게 다가와, 혀에 가장 먼저 닿는 그 단맛이 첫 모금의 인상을 부드럽고 포근하게 감싸 줘요.",
  );
  // A tannic red with the lowest mark is never told its sweetness is rich,
  // nor that its tannin is soft.
  const strong = written(
    bottle("red_wine", { sweetness: 1, acidity: 3, astringency: 4, body: 4 }),
    TOO_STRONG,
  );
  assert(!/진한 만큼|순한 편/.test(strong.text), strong.text);
});

Deno.test("wine sweetness: a mark that stands high among the kind is never called little", () => {
  // 93 of 100 red wines carry sweetness 1: a red with 2 is a sweet one.
  const red = bottle("red_wine", {
    sweetness: 2,
    acidity: 3,
    astringency: 3,
    body: 4,
  });
  for (const answers of [PRONOUNCED, TOO_STRONG]) {
    const { text } = written(red, answers);
    assert(
      text.includes("이 레드 와인은 같은 종류 가운데서는 단맛이 있는 편이라") &&
        !/거의 없|단맛이 적/.test(text),
      text,
    );
  }
  for (const answers of [TOO_WEAK, GENTLE]) {
    const { text } = written(red, answers);
    assert(!/단맛이 (적어|적은|거의 없)/.test(text), text);
  }
  const acidityLiked = written(red, ["level:acidity:4:liked"]);
  assert(!acidityLiked.text.includes("단맛이 거의 없어서"), acidityLiked.text);
});

Deno.test("wine sweetness: no card sentence states how much sugar a wine has", () => {
  const bottles = [
    bottle("red_wine", { sweetness: 1, acidity: 3, astringency: 4, body: 4 }),
    bottle("red_wine", { sweetness: 1, acidity: 3, astringency: 2, body: 3 }, [
      "vanilla",
    ]),
    bottle("white_wine", { sweetness: 1, acidity: 3, astringency: 1, body: 2 }),
    bottle("rose_wine", { sweetness: 2, acidity: 3, astringency: 1, body: 2 }),
  ];
  const heavy = ["level:body:4:liked"];
  for (const product of bottles) {
    for (const answers of [TOO_WEAK, GENTLE, PRONOUNCED, TOO_STRONG, heavy]) {
      const { text } = written(product, answers);
      assert(
        !/당분|당도[가는] (거의 )?(없|낮|적)/.test(text),
        `${product.styleKey}: ${text}`,
      );
    }
  }
});

Deno.test("wine sweetness: only still wines are read this way", () => {
  const reading = (product: SensoryProduct) =>
    readWineSweetness({
      style_key: product.styleKey,
      category: product.category,
      levels: product.levels,
      aromas: [],
    });
  const levels = { sweetness: 1, acidity: 3, astringency: 4, body: 4 };
  for (const style of ["red_wine", "white_wine", "rose_wine", "orange_wine"]) {
    assert(reading(bottle(style, levels)), `${style} is a still wine`);
  }
  for (
    const [style, category] of [
      ["sparkling_wine", "wine"],
      ["port_wine", "wine"],
      ["single_malt_whisky", "whisky"],
      ["junmai", "sake"],
      ["takju", "korean_traditional"],
    ]
  ) {
    equal(reading(bottle(style, levels, [], category)), null, style);
  }
  // White and rosé have no tannin to read; a red's is read among red wines.
  equal(reading(bottle("white_wine", levels))!.tannin, null);
  equal(reading(bottle("red_wine", levels))!.tannin, "high");
  equal(reading(bottle("red_wine", levels))!.scope, "red_wine");
});
