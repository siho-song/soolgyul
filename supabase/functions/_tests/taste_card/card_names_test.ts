import { regionPath } from "../../_shared/record_reading/dictionary/dictionary.ts";
import { findEvidence } from "../../_shared/taste_card/evidence/evidence.ts";
import {
  MOST_OF_A_NAME,
  shareOnSide,
} from "../../_shared/record_reading/facts/name_counts.ts";
import { readRecord } from "../../_shared/record_reading/read_record.ts";
import type { SensoryProduct } from "../../_shared/record_reading/record/sensory_record.ts";
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
  const prepared = readRecord(recordFrom("names", keys, product));
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
      "**흙 향**은 **피노 누아** 와인이 병 속에서 오랜 시간 공기와 차단된 채 천천히 익으며 차분하게 변한 향이에요.",
    ),
    card.burden,
  );
  assert(
    card.liked.includes(
      "**체리 향**은 껍질과 과육에 향긋한 기운이 풍부한 **피노 누아** 품종을 발효할 때 피어나는 향이에요.",
    ),
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

Deno.test("names: a grape or a place is a taste's owner only when half its bottles have it", () => {
  const chianti = bottle("wine", "red_wine", {
    abv: 13,
    region: regionPath("it_chianti"),
    grapeVarietyKeys: ["sangiovese"],
  });
  const card = told(
    ["level:acidity:5:disliked", "level:tannin:4:disliked"],
    chianti,
  );
  // More than half the 키안티 reds are high in acid: the place's mark.
  assert(
    card.burden.includes("**키안티** 지역 **레드 와인**의 특징이에요"),
    card.burden,
  );
  // A quarter of the 산지오베제 reds are high in tannin: told of this bottle.
  assert(card.burden.includes("이 **산지오베제** 레드 와인은"), card.burden);
  assert(!card.burden.includes("품종에서 나와요"), card.burden);
  const lines = next(
    ["level:acidity:5:disliked", "level:tannin:4:disliked"],
    chianti,
  );
  assert(
    lines.some((line) => line.includes("산미가 대체로 높은 편이에요")),
    lines.join(),
  );
});

Deno.test("다음 방향: a name is turned to only when its own bottles bear it out, and never one too few to count", () => {
  const lines = next([
    "level:tannin:2:liked",
    "level:body:2:liked",
    "level:acidity:4:liked",
    "aroma:nose:cherry:liked",
    "aroma:palate:earth:disliked",
  ], BURGUNDY).join();
  // 가메 carries the earth more often than a red does; 바르베라 does not,
  // and two in three of its bottles are high in acid.
  assert(lines.includes("**바르베라**") && !lines.includes("가메"), lines);
  assert(lines.includes("흙 향은 줄일 수 있어요"), lines);
  // Under thirty bottles of its own, a grape is not sent for.
  assert(!/카나이올로|생소/.test(lines), lines);
  // 메를로 is full in barely half its bottles, 템프라니요 in three of five.
  const barolo = next(
    ["level:tannin:5:disliked", "level:body:4:liked"],
    bottle("wine", "red_wine", {
      abv: 14,
      region: regionPath("it_barolo"),
      grapeVarietyKeys: ["nebbiolo"],
    }),
  ).join();
  assert(barolo.includes("타닌은 줄일 수 있어요"), barolo);
});
