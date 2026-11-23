import { regionPath } from "../../_shared/taste_card/dictionary/dictionary.ts";
import { findEvidence } from "../../_shared/taste_card/evidence/evidence.ts";
import {
  MOST_OF_A_NAME,
  shareOnSide,
} from "../../_shared/taste_card/facts/name_counts.ts";
import { prepareCard } from "../../_shared/taste_card/prepare/prepare.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
import { selectReasons } from "../../_shared/taste_card/selection/selection.ts";
import { writeCard } from "../../_shared/taste_card/writing/card_text.ts";
import { writeNext } from "../../_shared/taste_card/writing/next.ts";
import { assert, same } from "../helpers/assert.ts";
import { recordFrom } from "../helpers/card_fixture_record.ts";

/**
 * A name (a place, a grape, a kind) stands for many bottles that differ. The
 * card says where a taste comes from; it does not say every bottle of the
 * name has it, and it does not send the reader back to the whole kind.
 */

function bottle(
  category: SensoryProduct["category"],
  styleKey: string,
  more: Partial<SensoryProduct> = {},
): SensoryProduct {
  return {
    name: "시험",
    category,
    styleKey,
    abv: null,
    levels: {},
    descriptors: [],
    ...more,
  };
}

const told = (keys: string[], product: SensoryProduct) => {
  const card = writeCard(recordFrom("names", keys, product));
  return {
    liked: card.positive.map((p) => p.text).join("\n"),
    burden: card.burden.map((p) => p.text).join("\n"),
  };
};

const next = (keys: string[], product: SensoryProduct) => {
  const prepared = prepareCard(recordFrom("names", keys, product));
  const found = findEvidence(prepared);
  return (writeNext(prepared, found, selectReasons(prepared, found))?.lines ??
    []).map((line) => line.text);
};

const BURGUNDY = bottle("wine", "red_wine", {
  abv: 13,
  region: regionPath("fr_bourgogne"),
  grapeVarietyKeys: ["pinot_noir"],
});

Deno.test("names: an aroma is told by where the dictionary says it comes from, and by the grape before the place", () => {
  const card = told([
    "level:acidity:4:liked",
    "aroma:nose:cherry:liked",
    "aroma:palate:earth:disliked",
  ], BURGUNDY);
  // The row lists earth as what comes with age, and cherry as the fruit's.
  assert(
    card.burden.includes(
      "**흙 향**은 **피노 누아** 와인이 숙성되면서 생기는 향이에요.",
    ),
    card.burden,
  );
  assert(
    card.liked.includes("**체리 향**은 **피노 누아** 포도에서 오는 향이에요."),
    card.liked,
  );
  // An aroma the name itself says is not said to come from it.
  const makgeolli = told(
    ["aroma:nose:nuruk:disliked"],
    bottle("korean_traditional", "takju", { abv: 6 }),
  );
  assert(!makgeolli.burden.includes("누룩에서 오는"), makgeolli.burden);
});

Deno.test("names: no aroma is 특유의 of a place, a grape, a kind or a maker", () => {
  const cards = [
    told(["aroma:nose:cherry:liked", "aroma:palate:earth:disliked"], BURGUNDY),
    told(
      ["aroma:nose:plum:liked"],
      bottle("wine", "red_wine", {
        region: regionPath("ar_mendoza"),
        grapeVarietyKeys: ["malbec"],
      }),
    ),
    told(
      ["aroma:nose:melon:liked"],
      bottle("sake", "junmai_daiginjo", { abv: 15 }),
    ),
    told(
      ["aroma:palate:vanilla:liked", "aroma:nose:smoke:liked"],
      bottle("whisky", "single_malt_whisky", { abv: 46 }),
    ),
  ];
  for (const card of cards) {
    assert(!`${card.liked}${card.burden}`.includes("특유"), card.liked);
  }
});

Deno.test("names: a taste is a kind's mark only when most of the kind's bottles have it", () => {
  const light = shareOnSide(
    { what: "kinds", key: "junmai_daiginjo" },
    null,
    "body",
    "low",
  );
  assert(light !== null && light < MOST_OF_A_NAME, String(light));
  const card = told(
    ["level:body:2:liked"],
    bottle("sake", "junmai_daiginjo", { abv: 15 }),
  );
  // Told of this bottle, with how it is made, not as what the kind is.
  assert(card.liked.includes("이 **준마이 다이긴조**는"), card.liked);
  assert(!card.liked.includes("특징이에요"), card.liked);
});

Deno.test("다음 방향: the kind just drunk is not what to look for, and a shop's word alone is no line", () => {
  const SAID_BACK = new Set(["풀바디", "라이트 바디", "드라이", "피트 위스키"]);
  const names = (line: string) =>
    [...line.matchAll(/\*\*(.+?)\*\*/g)].map((m) => m[1]);
  for (
    const [keys, product, kind] of [
      [
        ["level:peat:5:liked", "level:body:4:liked"],
        bottle("whisky", "single_malt_whisky", { abv: 46 }),
        "싱글 몰트 위스키",
      ],
      [
        ["level:body:2:liked", "level:umami:2:liked"],
        bottle("sake", "junmai_daiginjo", { abv: 15 }),
        "준마이 다이긴조",
      ],
    ] as const
  ) {
    for (const line of next([...keys], product)) {
      assert(!names(line).includes(kind), line);
      assert(names(line).some((name) => !SAID_BACK.has(name)), line);
    }
  }
  // 라이트 바디 for a light body is the answer said back: no line.
  same(
    next(["level:body:2:liked"], bottle("sake", "junmai", { abv: 13 })),
    [],
  );
  // A cask of the bottle is a name to look for; the kind still is not.
  const lines = next(
    ["level:sweetness:4:liked", "level:body:4:liked"],
    bottle("whisky", "single_malt_whisky", {
      abv: 43,
      processes: ["ex_sherry_cask"],
    }),
  );
  assert(lines.some((line) => line.includes("**셰리 캐스크**")), lines.join());
  assert(!lines.join().includes("싱글 몰트 위스키"), lines.join());
});
