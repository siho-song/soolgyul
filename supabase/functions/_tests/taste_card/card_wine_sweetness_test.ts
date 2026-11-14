/**
 * A still wine's sweetness on its card is read by the bottle's places within
 * its kind: what makes it feel drier (tannin, acidity) or sweeter (ripe-fruit
 * and sweet-scent aromas, soft tannin, low acidity, a full body) is said from
 * the bottle's own data, and nothing is said when the data has no reason.
 */
import { readCard } from "../../_shared/taste_card/facts/reading.ts";
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

const REST = [
  "reaction:taste:acidity:fine",
  "reaction:taste:bitterness:fine",
  "aroma:unsure",
  "mouthfeel:unsure",
  "finish:unsure",
  "revisit:unsure",
];
const sweetness = (side: "liked" | "disliked", reason: string) => [
  `reaction:taste:sweetness:${side}`,
  `reason:taste:sweetness:${side}:${reason}`,
  ...REST,
];
const TOO_WEAK = sweetness("disliked", "too_weak");
const PRONOUNCED = sweetness("liked", "pronounced");
const TOO_STRONG = sweetness("disliked", "too_strong");

/** The card's paragraphs as one plain text, and the rows that explained them. */
function written(product: SensoryProduct, answers: readonly string[]) {
  const card = writeCard(recordFrom("wine", answers, product));
  const chosen = [
    ...card.facts.sections.positive,
    ...card.facts.sections.burden,
  ];
  return {
    text: [...card.positive, ...card.burden, ...card.balanced].map((p) =>
      `${p.answer}: ${p.text}`
    ).join(" ").replaceAll("**", ""),
    rows: card.facts.findings.filter((d) => chosen.includes(d.id)).map((d) =>
      d.row
    ),
    tags: card.tags.map((tag) => tag.label),
  };
}

const NOTHING_COVERS =
  "단맛을 가리는 맛이 없어 느끼신 단맛이 이 술이 가진 단맛 그대로예요";

Deno.test("wine sweetness: 더 있었으면 on a red whose tannin stands high is explained by the tannin, never by nothing covering it", () => {
  const tannic = written(
    bottle("red_wine", { sweetness: 1, acidity: 3, astringency: 4, body: 4 }),
    TOO_WEAK,
  );
  assert(
    tannic.text.includes("레드 와인 가운데서도 타닌이 많은 편인데") &&
      tannic.text.includes("한결 드라이하게 느껴져요"),
    `tannin not named: ${tannic.text}`,
  );
  assert(!tannic.text.includes("가리는 맛이 없어"), tannic.text);
  assert(
    tannic.text.startsWith("아쉬운 단맛:") &&
      tannic.text.endsWith("이 특징이 아쉬움으로 남은 것 같아요."),
    `a lack keeps its name and closing: ${tannic.text}`,
  );

  const both = written(
    bottle("red_wine", { sweetness: 1, acidity: 4, astringency: 5, body: 4 }),
    TOO_WEAK,
  );
  assert(
    both.text.includes("타닌이 많고 산미도 높은 편인데") &&
      !both.text.includes("가리는 맛이 없어"),
    `tannin and acidity not named together: ${both.text}`,
  );

  // A white has no tannin to speak of; its acidity standing high is the reason.
  const white = written(
    bottle("white_wine", { sweetness: 1, acidity: 4, astringency: 1, body: 3 }),
    TOO_WEAK,
  );
  assert(
    white.text.includes("산미가 높은 술인데") &&
      !white.text.includes("가리는 맛이 없어"),
    `acidity not named: ${white.text}`,
  );
});

Deno.test("wine sweetness: 더 있었으면 on a red whose tannin and acidity do not stand high still says nothing covers the sweetness", () => {
  const soft = written(
    bottle("red_wine", { sweetness: 1, acidity: 3, astringency: 2, body: 3 }),
    TOO_WEAK,
  );
  assert(
    soft.text.includes("타닌도 산미도") && soft.text.includes(NOTHING_COVERS),
    `the old sentence, with the tannin it stands on: ${soft.text}`,
  );
  // A mark of 2 stands high among red wines, so it is not called low.
  const marked = written(
    bottle("red_wine", { sweetness: 2, acidity: 3, astringency: 2, body: 3 }),
    TOO_WEAK,
  );
  assert(
    !/단맛이 (낮|적|거의 없)/.test(marked.text),
    `level said against its place: ${marked.text}`,
  );
});

Deno.test("wine sweetness: a wine with the lowest mark that felt sweet is explained by its own aromas and soft structure", () => {
  const ripe = written(
    bottle(
      "red_wine",
      { sweetness: 1, acidity: 3, astringency: 2, body: 3 },
      ["vanilla", "peach"],
    ),
    PRONOUNCED,
  );
  equal(ripe.rows, ["wine_sweetness_raised"], ripe.text);
  assert(
    ripe.text.includes("복숭아와 바닐라 향을 지닌 데다") &&
      ripe.text.includes("레드 와인 가운데 타닌이 순한 편이라서"),
    `aromas and soft tannin not named: ${ripe.text}`,
  );

  const aromaOnly = written(
    bottle(
      "white_wine",
      { sweetness: 1, acidity: 4, astringency: 1, body: 3 },
      ["honey"],
    ),
    PRONOUNCED,
  );
  assert(
    aromaOnly.text.includes("꿀 향을 지니고 있어서") &&
      !aromaOnly.text.includes("누르는 맛"),
    `beside a high acidity only the aroma is named: ${aromaOnly.text}`,
  );

  const softOnly = written(
    bottle("red_wine", { sweetness: 1, acidity: 3, astringency: 2, body: 3 }),
    PRONOUNCED,
  );
  assert(
    softOnly.text.includes(
      "레드 와인 가운데 타닌이 순한 편이라서, 단맛을 누르는 맛이 적은 만큼",
    ),
    softOnly.text,
  );

  // The same explanation when the sweetness was too much.
  const burden = written(
    bottle(
      "red_wine",
      { sweetness: 1, acidity: 3, astringency: 3, body: 4 },
      ["vanilla"],
    ),
    TOO_STRONG,
  );
  equal(burden.rows, ["wine_sweetness_raised"], burden.text);
  assert(
    burden.text.startsWith("생각보다 달게 느껴진 단맛:") &&
      burden.text.includes("바닐라 향을 지니고 있어서") &&
      !burden.text.includes("단맛이 진한 만큼"),
    burden.text,
  );
});

Deno.test("wine sweetness: with no reason in the bottle's data the card says only what was felt", () => {
  // Middle tannin, middle acidity, no sweet-leaning aroma.
  const plain = written(
    bottle(
      "red_wine",
      { sweetness: 1, acidity: 3, astringency: 3, body: 4 },
      ["cherry", "oak"],
    ),
    PRONOUNCED,
  );
  equal(plain.rows, ["intensity_sweetness"], plain.text);
  assert(plain.text.includes("이 와인에서는 단맛이 또렷하게 다가와서"));
  // Soft tannin explains nothing while the acidity stands high.
  const pinot = written(
    bottle("red_wine", { sweetness: 1, acidity: 4, astringency: 2, body: 2 }),
    PRONOUNCED,
  );
  equal(pinot.rows, ["intensity_sweetness"], pinot.text);
  assert(!pinot.text.includes("누르는 맛"), pinot.text);
  // 단맛이 너무 강했어요 on a tannic red with the lowest mark: never "단맛이 진한 만큼".
  const strong = written(
    bottle("red_wine", { sweetness: 1, acidity: 3, astringency: 4, body: 4 }),
    TOO_STRONG,
  );
  assert(!strong.text.includes("진한 만큼"), strong.text);
});

Deno.test("wine sweetness: a mark that stands high among its kind is said so, and never called little", () => {
  const red = bottle("red_wine", {
    sweetness: 2,
    acidity: 3,
    astringency: 3,
    body: 4,
  });
  assert(
    written(red, PRONOUNCED).text.includes(
      "레드 와인 가운데 단맛이 있는 편이라서",
    ),
  );
  assert(
    written(red, TOO_STRONG).text.includes(
      "레드 와인 가운데 단맛이 있는 편이라,",
    ),
  );
  const acidityLiked = written(red, [
    "reaction:taste:acidity:liked",
    "reason:taste:acidity:liked:pronounced",
    "reaction:taste:sweetness:fine",
    "reaction:taste:bitterness:fine",
    "aroma:unsure",
    "mouthfeel:unsure",
    "finish:unsure",
    "revisit:unsure",
  ]);
  assert(!acidityLiked.text.includes("단맛이 거의 없어서"), acidityLiked.text);
  // The balanced card: 적당했어요 on every taste.
  const fine = [
    "reaction:taste:sweetness:fine",
    "reaction:taste:acidity:fine",
    "reaction:taste:bitterness:fine",
    "aroma:unsure",
    "mouthfeel:unsure",
    "finish:unsure",
    "revisit:unsure",
  ];
  const balanced = written(red, fine);
  assert(
    balanced.text.includes("레드 와인 가운데 단맛이 있는 편이에요") &&
      !balanced.text.includes("드라이") && !balanced.tags.includes("드라이"),
    `${balanced.text} ${balanced.tags}`,
  );
  // The lowest mark with nothing sweet-leaning stays the dry wine it was.
  const dry = written(
    bottle("red_wine", { sweetness: 1, acidity: 3, astringency: 3, body: 4 }),
    fine,
  );
  assert(dry.tags.includes("드라이"), `${dry.text} ${dry.tags}`);
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
  const heavy = [
    "notice:mouthfeel:heavy",
    "reaction:mouthfeel:heavy:liked",
    "reaction:taste:sweetness:fine",
    "aroma:unsure",
    "finish:unsure",
    "revisit:unsure",
  ];
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
    readWineSweetness(readCard(recordFrom("kind", REST, product)));
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
