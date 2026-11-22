/**
 * A still wine's sweetness on its card. The card tells it from what was
 * felt: a lack as a lack, and a dry style that felt sweet as this glass
 * beside its style. What the bottle's own tannin, acidity and aromas do to
 * its sweetness is still read (findings/wine_sweetness.ts) and kept with the
 * card's facts.
 */
import { oldCardReading } from "../../_shared/taste_card/facts/old_vocabulary.ts";
import { readWineSweetness } from "../../_shared/taste_card/findings/wine_sweetness.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
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
const PRONOUNCED = ["level:sweetness:4:liked"];
const TOO_STRONG = ["level:sweetness:4:disliked"];

/** The card's paragraphs as one plain text, and the rows that explained them. */
function written(product: SensoryProduct, answers: readonly string[]) {
  const card = writeCard(recordFrom("wine", answers, product));
  const chosen = [
    ...card.facts.sections.positive,
    ...card.facts.sections.burden,
  ];
  return {
    text: [...card.positive, ...card.burden].map((p) =>
      `${p.answer}: ${p.text}`
    ).join(" ").replaceAll("**", ""),
    rows: card.facts.findings.filter((d) => chosen.includes(d.id)).map((d) =>
      d.row
    ),
    tags: card.tags.map((tag) => tag.label),
  };
}

Deno.test("wine sweetness: 더 있었으면 is told as a lack, from what was felt", () => {
  for (
    const [style, name, levels] of [
      ["red_wine", "레드 와인", {
        sweetness: 1,
        acidity: 3,
        astringency: 4,
        body: 4,
      }],
      ["red_wine", "레드 와인", {
        sweetness: 1,
        acidity: 4,
        astringency: 5,
        body: 4,
      }],
      ["red_wine", "레드 와인", {
        sweetness: 1,
        acidity: 3,
        astringency: 2,
        body: 3,
      }],
      ["white_wine", "화이트 와인", {
        sweetness: 1,
        acidity: 4,
        astringency: 1,
        body: 3,
      }],
    ] as const
  ) {
    const lack = written(bottle(style, levels), TOO_WEAK);
    equal(
      lack.text,
      `조금 옅었던 단맛: • 이 ${name}은 단맛이 적어, 맛의 모서리를 감싸 줄 것이 없어 술이 메마르고 심심하게 느껴져요.`,
    );
    assert(!/부담/.test(lack.text), `a lack worded as a burden: ${lack.text}`);
    equal(lack.tags, ["적은단맛"]);
  }
});

Deno.test("wine sweetness: a dry style that felt sweet is told as this glass beside its style", () => {
  const dry = { sweetness: 1, acidity: 3, astringency: 3, body: 4 };
  const liked = written(bottle("red_wine", dry, ["cherry", "oak"]), PRONOUNCED);
  equal(
    liked.text,
    "포근하게 감도는 단맛: • 표기된 스타일은 단맛이 거의 없는 편이지만 이번 잔에서는 단맛이 또렷하게 다가와, 혀에 가장 먼저 닿는 그 단맛이 첫 모금의 인상을 부드럽고 포근하게 감싸 줘요.",
  );
  equal(liked.rows, ["intensity_sweetness"]);
  const minded = written(bottle("red_wine", dry, ["vanilla"]), TOO_STRONG);
  equal(
    minded.text,
    "혼자 앞서 도드라진 단맛: • 표기된 스타일은 단맛이 거의 없는 편이지만 이번 잔에서는 단맛이 또렷하게 다가오는데, 혀에 가장 먼저 닿는 단맛이 다른 맛을 누르고 혼자 앞으로 나서요.",
  );
  // What the bottle's own aromas and soft tannin do is still found for it.
  equal(minded.rows, ["wine_sweetness_raised"]);
  equal(
    written(
      bottle(
        "red_wine",
        { sweetness: 1, acidity: 3, astringency: 2, body: 3 },
        ["vanilla", "peach"],
      ),
      PRONOUNCED,
    ).rows,
    ["wine_sweetness_raised"],
  );
  // A tannic red with the lowest mark is never told its sweetness is rich.
  const strong = written(
    bottle("red_wine", { sweetness: 1, acidity: 3, astringency: 4, body: 4 }),
    TOO_STRONG,
  );
  assert(!strong.text.includes("진한 만큼"), strong.text);
});

Deno.test("wine sweetness: a mark of 2 is a little, never none", () => {
  const red = bottle("red_wine", {
    sweetness: 2,
    acidity: 3,
    astringency: 3,
    body: 4,
  });
  for (const answers of [PRONOUNCED, TOO_STRONG]) {
    const { text } = written(red, answers);
    assert(
      text.includes("표기된 스타일은 단맛이 적은 편이지만") &&
        !text.includes("거의 없"),
      text,
    );
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
    for (const answers of [TOO_WEAK, PRONOUNCED, TOO_STRONG, heavy]) {
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
    readWineSweetness(
      oldCardReading(recordFrom("kind", ["level:body:3:liked"], product)),
    );
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
