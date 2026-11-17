import { writeGuide } from "../../_shared/taste_card/summary/guide.ts";
import {
  BURDENED,
  LIKED,
  NOTE_CARRY,
  NOTE_EASE_KEEP,
  NOTE_FILL_KEEP,
  NOTE_ONLY_EASE,
  NOTE_ONLY_EASE_ALIKE,
  NOTE_ONLY_FILL,
  NOTE_ONLY_FILL_ALIKE,
  NOTE_SAME_GRADE,
  NOTE_SAME_GRAPE,
  NOTE_SAME_KIND,
  SAKE_TIP,
  TRADITIONAL_TIP,
  WHISKY_TIP,
  WINE_TIP,
} from "../../_shared/taste_card/summary/guide_words.ts";
import { terms } from "../../_shared/taste_card/dictionary/dictionary.ts";
import { bottlesCarrying } from "../../_shared/taste_card/facts/kind_place.ts";
import { buildCardFacts } from "../../_shared/taste_card/findings/conclusions.ts";
import {
  bpRecords,
  fixtureProduct,
  recordFrom,
} from "../helpers/card_fixture_record.ts";
import {
  type CardFacts,
  readStoredCardFacts,
} from "../../_shared/taste_card/facts/facts.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
import type { TasteCardGuide } from "../../_shared/taste_card/service/types.ts";
import { assert } from "../helpers/assert.ts";

const TIPS: Readonly<Record<string, string>> = {
  wine: WINE_TIP,
  whisky: WHISKY_TIP,
  sake: SAKE_TIP,
  korean_traditional: TRADITIONAL_TIP,
};

/** What every guide written now holds, whatever its kind. */
function assertShape(name: string, category: string, guide: TasteCardGuide) {
  assert(guide.head.length > 0, `${name}: no head`);
  assert(guide.directions.length === 0, `${name}: directions are written`);
  assert(guide.tip === TIPS[category], `${name}: tip ${guide.tip}`);
  for (const pick of guide.picks) {
    const words = (pick.words ?? []).map((w) => w.text);
    assert(words.length > 0, `${name}: ${pick.keyword} has no words`);
    assert(
      typeof pick.labelWord === "boolean",
      `${name}: ${pick.keyword} does not say what kind of chip it is`,
    );
    // The line is the words; only a word to pass over says more.
    assert(
      pick.keyword === words.join(" · ") ||
        pick.keyword === `${words.join(" · ")} 없는 것`,
      `${name}: ${pick.keyword} is not its words ${JSON.stringify(words)}`,
    );
    for (const text of [pick.keyword, ...words]) {
      assert(
        !/['‘’"]/.test(text.replace(/d'|l'/g, "")) && !text.includes("표기"),
        `${name}: ${text} still quotes its word`,
      );
    }
    assert(
      pick.note === null ||
        (/요\.$/.test(pick.note) && !/[{}]/.test(pick.note) &&
          !/향이 나는 향이/.test(pick.note)),
      `${name}: ${pick.note}`,
    );
  }
  for (const level of guide.levels) {
    assert("word" in level, `${name}: ${level.label} has no word`);
    assert(
      level.label !== "도수" || level.word === null,
      `${name}: 도수 ${level.word}`,
    );
  }
  assert(
    category === "whisky" ? "profile" in guide : !("profile" in guide),
    `${name}: profile of a ${category}`,
  );
  for (const line of guide.profile ?? []) {
    assert(
      ["AROMA", "FLAVOR", "FINISH"].includes(line.label) &&
        line.words.length > 0,
      `${name}: ${JSON.stringify(line)}`,
    );
  }
}

/** The BP bottles as today's questionnaire would record them, each with its card. */
async function bpCards(): Promise<[string, CardFacts][]> {
  return (await bpRecords()).map((
    [name, record],
  ) => [name, buildCardFacts(record)]);
}

Deno.test("guide: every BP card has a guide of its head, chips of label words, marks said in words and its kind's tip", async () => {
  for (const [name, facts] of await bpCards()) {
    const guide = writeGuide(facts);
    assert(guide, `${name}: no guide`);
    assertShape(name, facts.record.category ?? "", guide);
  }
});

Deno.test("guide: traditional cards get the shops' marks in plain words, and each chip its reason", async () => {
  for (const [name, facts] of await bpCards()) {
    if (facts.record.category !== "korean_traditional") continue;
    const guide = writeGuide(facts)!;
    // A word printed in Korean stays Korean, and is a label word.
    assert(
      guide.picks.every((p) =>
        p.labelWord === true && !/[A-Za-z(]/.test(p.keyword) &&
        (p.note ?? "").length > 0
      ),
      `${name}: ${JSON.stringify(guide.picks)}`,
    );
    assert(
      guide.levels.map((l) => l.label).join(",") === "단맛,산미,탄산,바디,도수",
      `${name}: ${guide.levels.map((l) => l.label)}`,
    );
    assert(
      guide.levels.slice(0, 4).every((l) => (l.word ?? "").length > 0),
      `${name}: ${JSON.stringify(guide.levels)}`,
    );
    assert(
      guide.levels.at(-1)!.range.includes("%"),
      `${name}: 도수 ${guide.levels.at(-1)!.range}`,
    );
  }
});

Deno.test("guide: sake grades share one chip, in kanji with their reading, and its note says what both keep", async () => {
  const byName = new Map(await bpCards());
  const dassai = writeGuide(byName.get("bp-03")!)!;
  assert(dassai.picks.length === 1, JSON.stringify(dassai.picks));
  const [grades] = dassai.picks;
  assert(
    grades.labelWord === false && grades.words!.length === 2 &&
      grades.words!.every((w) => /^[一-龯]+\([가-힣 ]+\)$/.test(w.text)),
    JSON.stringify(grades),
  );
  assert(
    grades.note !== null && grades.note.includes("배 향"),
    grades.note ?? "no note",
  );
  assert(
    dassai.levels.map((l) => l.label).join(",") === "당도(주도),산미(산도)" &&
      dassai.levels.every((l) => l.range.length > 0),
    JSON.stringify(dassai.levels),
  );
});

Deno.test("guide: a 40% whisky found hot still gets its guide, aimed at the floor band", () => {
  // 조니워커 블랙 라벨: 40% is the lowest a whisky goes, so the 열감 burden has
  // nowhere lower to point; the guide keeps the floor instead of vanishing.
  const facts = buildCardFacts(recordFrom("jw-black-hot", [
    "revisit:unsure",
    "level:sweetness:3:liked",
    "aroma:nose:chocolate:liked",
    "level:spice:4:disliked",
  ], {
    name: "조니워커 블랙 라벨",
    category: "whisky",
    styleKey: "blended_whisky",
    region: null,
    abv: 40,
    ingredients: [],
    grapeVarietyKeys: [],
    processes: ["wooden_cask"],
    levels: { sweetness: 3, bitterness: 2, body: 3 },
    levelRefs: {},
    descriptors: [],
  }));
  const guide = writeGuide(facts);
  assert(guide, "no guide for a whisky at the floor");
  assert(
    guide.levels.length === 1 && guide.levels[0].label === "도수" &&
      guide.levels[0].mark === 2 && guide.levels[0].range === "40~43%",
    JSON.stringify(guide.levels),
  );
  // What the reader said is in the profile, the burden as its turn.
  assert(
    JSON.stringify(guide.profile) === JSON.stringify([
      { label: "AROMA", words: ["초콜릿"] },
      { label: "FLAVOR", words: ["단맛", "알코올 열감 덜하게"] },
    ]),
    JSON.stringify(guide.profile),
  );
});

/**
 * What each card once saved without a guide (the 테스터 account,
 * 2026-11-08) said of its bottle, set on today's gauges and pickers.
 */
const GAP_ANSWERS: Readonly<Record<string, readonly string[]>> = {
  "auchentoshan-21": [
    "revisit:doNotWantAgain",
    "aroma:nose:berry:disliked",
    "level:sweetness:4:disliked",
    "level:body:4:disliked",
    "aroma:finish:berry:disliked",
  ],
  "jw-black-smoke": [
    "revisit:wantAgain",
    "aroma:nose:caramel:liked",
    "aroma:nose:vanilla:liked",
    "aroma:nose:smoke:disliked",
    "level:sweetness:4:liked",
    "level:spice:4:disliked",
    "level:finish_length:4:liked",
  ],
  kanagaso: [
    "revisit:wouldAcceptAgain",
    "aroma:nose:cereal:liked",
    "aroma:finish:cereal:liked",
  ],
  "teliani-muscat-rose": [
    "revisit:wantAgain",
    "aroma:nose:berry:liked",
    "level:acidity:4:disliked",
    "level:finish_length:2:disliked",
  ],
  "taittinger-louis": [
    "revisit:doNotWantAgain",
    "aroma:nose:almond:disliked",
    "level:acidity:4:disliked",
    "aroma:finish:almond:disliked",
  ],
  "yokoyama-silver-7": [
    "revisit:wantAgain",
    "aroma:nose:green_apple:liked",
    "aroma:finish:green_apple:liked",
  ],
  "isse-junmai": [
    "aroma:nose:rice:liked",
    "level:sweetness:2:disliked",
    "level:body:2:liked",
    "level:finish_length:2:liked",
  ],
};

/** The bottle of one such card, answered again on today's questionnaire. */
async function gapCard(name: string): Promise<CardFacts> {
  const url = new URL(`../fixtures/guide_gaps/${name}.json`, import.meta.url);
  const stored = readStoredCardFacts(JSON.parse(await Deno.readTextFile(url)));
  assert(stored, `${name} is no stored card`);
  return buildCardFacts(
    recordFrom(name, GAP_ANSWERS[name], fixtureProduct(stored)),
  );
}

Deno.test("guide: a reader who liked nothing is aimed by the burdens alone", async () => {
  // 오켄토션 21년: 베리 향, 단맛, 무게, 잡내 all to turn down.
  const guide = writeGuide(await gapCard("auchentoshan-21"));
  assert(guide, "no guide without a liked sensation");
  assert(
    guide.head === "부담은 줄인 싱글 몰트 위스키의 추천 키워드예요.",
    guide.head,
  );
  assert(guide.picks.length > 0, JSON.stringify(guide.picks));
  // Nothing was liked: no line of the profile claims a taste.
  assert(
    (guide.profile ?? []).every((line) =>
      line.words.every((word) => /없이$|덜하게$|남지 않게$/.test(word))
    ),
    JSON.stringify(guide.profile),
  );
});

Deno.test("guide: an aroma to turn down is said as its absence in a whisky's profile", async () => {
  // 조니워커 블랙 라벨: 스모키 향 to turn down beside 알코올 열감.
  const guide = writeGuide(await gapCard("jw-black-smoke"))!;
  const aroma = guide.profile?.find((line) => line.label === "AROMA");
  assert(aroma?.words.includes("스모키 없이"), JSON.stringify(guide.profile));
});

Deno.test("guide: a sake unlike every grade gets the label numbers and its own grade, no far grade", async () => {
  // 카나가소: 산미·바디·알코올감 high, every grade low; 긴조 would miss its 곡물 향,
  // and no label word speaks of 곡물·쌀 향. Only liked answers: the same grade again.
  const guide = writeGuide(await gapCard("kanagaso"));
  assert(guide, "no guide for a bottle unlike every grade");
  assert(
    guide.picks.map((p) => p.keyword).join() === "純米(준마이)" &&
      guide.picks[0].labelWord === false &&
      guide.picks[0].note === NOTE_SAME_GRADE,
    JSON.stringify(guide.picks),
  );
  assert(
    guide.levels.map((l) => l.label).join(",") === "당도(주도),산미(산도)",
    JSON.stringify(guide.levels),
  );
  assert(guide.tip === SAKE_TIP, guide.tip ?? "no tip");
});

/** A plain bottle of one kind, every level in the middle. */
function plainBottle(
  category: "korean_traditional" | "whisky",
  styleKey: string,
  abv: number,
): SensoryProduct {
  return {
    name: styleKey,
    category,
    styleKey,
    region: null,
    abv,
    ingredients: [],
    grapeVarietyKeys: [],
    processes: [],
    levels: { sweetness: 3, acidity: 3, body: 3 },
    levelRefs: {},
    descriptors: [],
  };
}

function likedAroma(aroma: string): string[] {
  return [`aroma:nose:${aroma}:liked`];
}

Deno.test("guide: 증류식 소주 is not sent to a method only 탁주 or wine carries", () => {
  const soju = plainBottle("korean_traditional", "distilled_soju", 25);
  for (
    const aroma of ["rice", "corn", "spice", "dried_fruit", "nuruk", "citrus"]
  ) {
    const guide = writeGuide(
      buildCardFacts(recordFrom(`soju-${aroma}`, likedAroma(aroma), soju)),
    );
    const words = (guide?.picks ?? []).map((p) => p.keyword).join(",");
    assert(
      !/병행복발효|연속식 증류|살균|침용|강화|암포라|스테인리스/.test(words),
      `${aroma}: ${words}`,
    );
  }
});

Deno.test("guide: a cask chip's note is the reason for this reader, not what the cask is", () => {
  const malt = plainBottle("whisky", "single_malt_whisky", 46);
  const guide = writeGuide(buildCardFacts(recordFrom(
    "malt-vanilla",
    likedAroma("vanilla"),
    malt,
  )))!;
  const definitions = terms("process", "maturation").flatMap((t) =>
    (t.hints as { guide_note?: string } | undefined)?.guide_note ?? []
  );
  assert(guide.picks.length === 2, JSON.stringify(guide.picks));
  for (const pick of guide.picks) {
    assert(
      pick.note!.includes("좋아하신 바닐라 향") &&
        definitions.every((text) => !pick.note!.includes(text)),
      JSON.stringify(pick),
    );
  }
  // A neighbour of the liked aroma is no reason: no cask is made to carry 나무 향.
  const wood = writeGuide(buildCardFacts(recordFrom(
    "malt-wood",
    likedAroma("wood"),
    malt,
  )))!;
  assert(wood.picks.length === 0, JSON.stringify(wood.picks));
  assert(
    JSON.stringify(wood.profile) ===
      JSON.stringify([{ label: "AROMA", words: ["나무"] }]),
    JSON.stringify(wood.profile),
  );
});

/** A 전통주 bottle as the catalog holds one: its levels, what it is made from and how. */
function traditional(
  styleKey: string,
  abv: number,
  levels: SensoryProduct["levels"],
  ingredients: string[] = [],
  processes: string[] = [],
): SensoryProduct {
  return {
    ...plainBottle("korean_traditional", styleKey, abv),
    levels,
    ingredients,
    processes,
  };
}

const VACUUM_SOJU = traditional(
  "distilled_soju",
  25,
  { sweetness: 2, acidity: 2, bitterness: 1, body: 3 },
  ["rice"],
  ["vacuum_distillation"],
);
const POT_BARLEY_SOJU = traditional(
  "distilled_soju",
  40,
  { sweetness: 2, acidity: 2, bitterness: 2, body: 4 },
  ["barley"],
  ["atmospheric_distillation"],
);
const FRESH_TAKJU = traditional(
  "takju",
  6,
  { sweetness: 3, acidity: 3, bitterness: 1, body: 2, carbonation: 3 },
  ["rice"],
  ["unpasteurised"],
);
const THICK_TAKJU = traditional(
  "takju",
  12,
  { sweetness: 3, acidity: 2, bitterness: 2, body: 4, carbonation: 2 },
  ["rice", "glutinous_rice"],
);

/** The guide for one bottle and its answers. */
function guideFor(product: SensoryProduct, answers: string[]) {
  const guide = writeGuide(
    buildCardFacts(recordFrom(product.name, answers, product)),
  );
  assert(guide, `${product.name}: no guide for ${answers}`);
  return {
    guide,
    words: guide.picks.map((p) => p.keyword),
    mark: (label: string) => guide.levels.find((l) => l.label === label),
  };
}

/** The gauge step that names each sensation of the mouth. */
const FEEL: Readonly<Record<string, string>> = {
  light: "level:body:2",
  heavy: "level:body:4",
  smooth: "level:tannin:2",
  bubbles: "level:sparkling:4",
  warmth: "level:spice:4",
};
const feel = (key: string, side: "liked" | "disliked") => [
  `${FEEL[key]}:${side}`,
];
const minded = (key: string) => feel(key, "disliked");
/** 잡내: an aroma that bothered after swallowing. */
const OFF_FLAVOR = "aroma:finish:fermentation:disliked";
const TOO_SHORT = "level:finish_length:2:disliked";
const LONG_FINISH = "level:finish_length:4:liked";

Deno.test("guide: 증류식 소주 shows 단맛 and 바디 beside the bottle's own 도수", () => {
  const { guide, mark } = guideFor(VACUUM_SOJU, [
    "level:sweetness:3:liked",
    "level:acidity:3:liked",
  ]);
  assert(
    guide.levels.map((l) => l.label).join(",") === "단맛,바디,도수",
    JSON.stringify(guide.levels),
  );
  // Nothing to turn: the number printed on this bottle is the place to look.
  assert(mark("도수")!.range === "25% 안팎", mark("도수")!.range);
  assert(guide.tip === TRADITIONAL_TIP, guide.tip ?? "no tip");
});

Deno.test("guide: the word the bottle already carries is no answer to its burden", () => {
  // A 감압증류 soju found heavy: '감압증류', the word for a lighter soju, is
  // not what to change to.
  const heavy = guideFor(VACUUM_SOJU, minded("heavy"));
  assert(
    heavy.words.every((w) => !w.includes("감압증류")),
    JSON.stringify(heavy.words),
  );
  // 도수 to lower ends under the bottle's own 25%.
  assert(heavy.mark("도수")!.range === "17~24%", heavy.mark("도수")!.range);
});

/** The cask or method a whisky chip names, by the label word it opens with. */
function caskOf(word: string) {
  const label = word.replace(/\(.*$/, "");
  const term = terms("process", "maturation").find((t) =>
    (t.hints as { label_words?: string[] } | undefined)?.label_words?.[0] ===
      label
  );
  assert(term, `${word} is no cask or method`);
  return term;
}

Deno.test("guide: a cask or method chip is spelled as the label prints it with its reading, and is never one the shelf hardly holds", () => {
  const malt = plainBottle("whisky", "single_malt_whisky", 46);
  const asked = [
    ...["vanilla", "caramel", "dried_fruit", "citrus", "honey", "spice", "oak"]
      .map(likedAroma),
    minded("heavy"),
    minded("light"),
    minded("warmth"),
    [TOO_SHORT],
  ];
  let chips = 0;
  for (const answers of asked) {
    const guide = writeGuide(
      buildCardFacts(recordFrom(`malt-${answers[0]}`, answers, malt)),
    )!;
    for (const pick of guide.picks.filter((p) => p.labelWord === false)) {
      assert(
        /^[A-Za-z][A-Za-z ]*\([가-힣 ]+\)$/.test(pick.keyword),
        `${answers[0]}: ${pick.keyword}`,
      );
      const counted = bottlesCarrying(
        "made",
        caskOf(pick.keyword).key,
        "whisky",
      )!;
      // One bottle in a hundred of the whisky shelf: 29 of 2,899.
      assert(
        counted.bottles >= 0.01 * counted.of,
        `${pick.keyword} is on ${counted.bottles} of ${counted.of}`,
      );
      chips++;
    }
    // 아메리칸 오크 (3 bottles), 3회 증류 (none) and 연속식 증류 (2) fit well and are not named.
    assert(
      guide.picks.every((p) => !/American Oak|Triple|Column/.test(p.keyword)),
      JSON.stringify(guide.picks.map((p) => p.keyword)),
    );
  }
  assert(chips > 5, `only ${chips} cask chips`);
});

Deno.test("guide: of the casks that carry a liked aroma, the one on more bottles goes first", () => {
  const malt = plainBottle("whisky", "single_malt_whisky", 46);
  for (const aroma of ["vanilla", "dried_fruit", "spice"]) {
    const guide = writeGuide(
      buildCardFacts(recordFrom(`malt-${aroma}`, likedAroma(aroma), malt)),
    )!;
    const bottles = guide.picks.map((p) =>
      bottlesCarrying("made", caskOf(p.keyword).key, "whisky")!.bottles
    );
    assert(
      bottles.length === 2 && bottles[0] >= bottles[1],
      `${aroma}: ${guide.picks.map((p) => p.keyword)} ${bottles}`,
    );
  }
  // 버번 캐스크 (1,048 bottles) before 새 오크통 (205); 목재 캐스크, on more
  // bottles than either, says nothing a named cask does not.
  const vanilla = writeGuide(
    buildCardFacts(recordFrom("malt-vanilla", likedAroma("vanilla"), malt)),
  )!;
  assert(
    vanilla.picks.map((p) => p.keyword).join(",") ===
      "Bourbon Cask(버번 캐스크),Virgin Oak(새 오크통)",
    JSON.stringify(vanilla.picks),
  );
});

/* ---- wine and whisky: a level is read among the bottle's own kind ---- */

function bottle(
  category: "wine" | "whisky" | "sake",
  styleKey: string,
  abv: number,
  levels: SensoryProduct["levels"],
  made: { grapes?: string[]; processes?: string[] } = {},
): SensoryProduct {
  return {
    name: `${styleKey} ${abv}`,
    category,
    styleKey,
    region: null,
    abv,
    ingredients: [],
    grapeVarietyKeys: made.grapes ?? [],
    processes: made.processes ?? [],
    levels,
    levelRefs: {},
    descriptors: [],
  };
}

// 93 of 100 reds carry 당도 1: this is the ordinary one.
const DRY_RED = bottle("wine", "red_wine", 14, {
  sweetness: 1,
  acidity: 4,
  astringency: 4,
  body: 4,
}, { grapes: ["cabernet_sauvignon"] });
const DRY_WHITE = bottle("wine", "white_wine", 13, {
  sweetness: 1,
  acidity: 4,
  astringency: 1,
  body: 2,
}, { grapes: ["sauvignon_blanc"] });
const SHERRY_MALT = bottle("whisky", "single_malt_whisky", 40, {
  sweetness: 2,
  acidity: 2,
  bitterness: 3,
  body: 4,
  finish_length: 4,
}, { processes: ["ex_sherry_cask"] });
const BOURBON_CASK_MALT = bottle("whisky", "single_malt_whisky", 40, {
  sweetness: 4,
  acidity: 3,
  bitterness: 2,
  body: 3,
  finish_length: 3,
}, { processes: ["ex_bourbon_cask"] });
const PEATED_MALT = bottle("whisky", "single_malt_whisky", 45.8, {
  sweetness: 3,
  acidity: 2,
  bitterness: 2,
  body: 4,
  finish_length: 4,
}, { processes: ["ex_bourbon_cask", "peated_malt"] });

const sweetness = (level: 2 | 3 | 4, side: "liked" | "disliked") => [
  `level:sweetness:${level}:${side}`,
];
const aromaSaid = (key: string, side: "liked" | "disliked") => [
  `aroma:nose:${key}:${side}`,
];

Deno.test("guide: a regional style is named with its country, the common one first, and never one the shelf hardly holds", () => {
  const brut = bottle("wine", "sparkling_wine", 12, {
    sweetness: 1,
    acidity: 4,
    carbonation: 4,
    body: 3,
  });
  const { guide } = guideFor(brut, feel("bubbles", "liked"));
  assert(
    guide.picks.map((p) => p.keyword).join(",") ===
      "Champagne(샴페인),Prosecco(프로세코)",
    JSON.stringify(guide.picks),
  );
  assert(
    guide.picks.every((p) => p.labelWord === false && p.country !== null),
    JSON.stringify(guide.picks),
  );
  assert(
    guide.levels.map((l) => l.word).join(",") ===
      "드라이,조금 높은 산도,조금 강한 탄산,미디엄 바디",
    JSON.stringify(guide.levels),
  );
  // Whatever is asked, a style on fewer than one sparkling bottle in a hundred
  // is not named: 트렌토독 (15 bottles) and 까바 (23) fit and stay out.
  for (
    const answers of [
      minded("bubbles"),
      ["level:acidity:3:liked"],
      [LONG_FINISH],
    ]
  ) {
    for (const pick of guideFor(brut, answers).guide.picks) {
      if (pick.labelWord) continue;
      const style = terms("regional_style").find((t) =>
        t.names.label === pick.keyword.replace(/\(.*$/, "")
      )!;
      const counted = bottlesCarrying("styles", style.key, "sparkling_wine")!;
      assert(
        counted.bottles >= 0.01 * counted.of,
        `${pick.keyword} is on ${counted.bottles} of ${counted.of}`,
      );
    }
  }
});

Deno.test("guide: the reader's own word for a strength outranks the catalog number", () => {
  // 단맛 2 of 5 in the catalog, liked because it was 또렷했다: more of it.
  const { guide, words } = guideFor(
    SHERRY_MALT,
    sweetness(4, "liked"),
  );
  assert(words.length > 0, "nothing to look for");
  assert(
    guide.picks.every((p) => !p.keyword.includes("Bourbon")),
    JSON.stringify(guide.picks),
  );
  assert(
    guide.picks[0].note?.includes("또렷한 단맛"),
    guide.picks[0].note ?? "",
  );
  // 단맛 4 of 5, liked because it was 은은했다: not a sweeter cask.
  const mild = guideFor(BOURBON_CASK_MALT, sweetness(2, "liked"));
  assert(
    mild.guide.picks.every((p) => !p.keyword.includes("Sherry")),
    JSON.stringify(mild.guide.picks),
  );
});

Deno.test("guide: a card whose only burden is an aroma is told the label word to pass over", () => {
  const { guide } = guideFor(PEATED_MALT, aromaSaid("smoke", "disliked"));
  assert(
    guide.head === "부담은 줄인 싱글 몰트 위스키의 추천 키워드예요.",
    guide.head,
  );
  // The word is the chip's one word; that it is to pass over is in the line.
  assert(
    guide.picks.length === 1 &&
      guide.picks[0].keyword === "Peated(피트 처리 맥아) 없는 것" &&
      guide.picks[0].words!.map((w) => w.text).join() ===
        "Peated(피트 처리 맥아)" &&
      guide.picks[0].labelWord === true,
    JSON.stringify(guide.picks),
  );
  // The bottle is peated: its 스모키 향 came from the word.
  assert(
    guide.picks[0].note?.includes("이번 술의 스모키 향"),
    guide.picks[0].note ?? "",
  );
  assert(
    JSON.stringify(guide.profile) ===
      JSON.stringify([{ label: "AROMA", words: ["스모키 없이"] }]),
    JSON.stringify(guide.profile),
  );
  // Beside a liked aroma it keeps one of the two places.
  const both = guideFor(BOURBON_CASK_MALT, [
    ...aromaSaid("vanilla", "liked"),
    ...aromaSaid("smoke", "disliked"),
  ]);
  assert(
    both.words.length === 2 &&
      both.words[1] === "Peated(피트 처리 맥아) 없는 것",
    JSON.stringify(both.words),
  );
  // A word to pass over is one the shelf holds, the bottle's own first:
  // 바닐라 향 of a bourbon-cask whisky is 버번 캐스크, not 새 오크통.
  const vanilla = guideFor(BOURBON_CASK_MALT, aromaSaid("vanilla", "disliked"));
  assert(
    vanilla.words.join(",") === "Bourbon Cask(버번 캐스크) 없는 것",
    JSON.stringify(vanilla.words),
  );
  // A wine has no such word, and still gets its guide.
  const wine = guideFor(DRY_RED, aromaSaid("berry", "disliked"));
  assert(wine.guide.tip === WINE_TIP, wine.guide.tip ?? "");
});

Deno.test("guide: a chip is a new word, and the bottle's own only for a liked aroma nothing else carries", () => {
  // 단맛 to lower: the Bourbon Cask cue is no answer to a bourbon-cask bottle.
  const sweet = guideFor(
    BOURBON_CASK_MALT,
    sweetness(4, "disliked"),
  );
  assert(sweet.words.length > 0, "nothing to look for");
  assert(
    sweet.words.every((w) => !w.includes("Bourbon")),
    JSON.stringify(sweet.words),
  );
  // 바닐라 향 liked: other casks carry it too.
  const vanilla = guideFor(BOURBON_CASK_MALT, aromaSaid("vanilla", "liked"));
  assert(
    vanilla.words.length > 0 &&
      vanilla.words.every((w) => !w.includes("Bourbon")),
    JSON.stringify(vanilla.words),
  );
  // 스모키 향 liked: only peated malt brings it, so it is named again.
  const smoke = guideFor(PEATED_MALT, aromaSaid("smoke", "liked"));
  assert(
    smoke.words.join(",") === "Peated(피트 처리 맥아)" &&
      smoke.guide.picks[0].labelWord === false,
    JSON.stringify(smoke.guide.picks),
  );
});

Deno.test("guide: a burden no label cue answers gets a cask or method by what the dictionary says it does", () => {
  // 40% found hot: no lower 도수 to point to, so a method that softens.
  const hot = guideFor(BOURBON_CASK_MALT, minded("warmth"));
  assert(hot.mark("도수")!.range === "40~43%", hot.mark("도수")!.range);
  assert(
    hot.guide.picks[0]?.labelWord === false &&
      hot.guide.picks[0].note?.includes("알코올 열감"),
    JSON.stringify(hot.guide.picks),
  );
  // 여운이 짧았다 of a 45.8% whisky: a word of long finish, and a band up.
  const brief = guideFor(PEATED_MALT, [TOO_SHORT]);
  assert(
    brief.guide.picks[0]?.note?.includes("여운"),
    JSON.stringify(brief.guide.picks),
  );
  // The row was counted from our bottles, and the note says how many.
  assert(
    /\d+병/.test(brief.guide.picks[0].note!),
    brief.guide.picks[0].note ?? "",
  );
  // A row the dictionary did not count adds no sentence: 40% found hot gets its frame alone.
  assert(
    hot.guide.picks[0].note!.split("요.").length === 2,
    hot.guide.picks[0].note ?? "",
  );
  assert(
    brief.words.every((w) => !w.includes("Peated")),
    JSON.stringify(brief.words),
  );
  assert(brief.mark("도수")!.range === "47~50%", brief.mark("도수")!.range);
  // 43% found hot: the range ends under the bottle's own.
  const fortyThree = guideFor(
    bottle("whisky", "single_malt_whisky", 43, { sweetness: 3, body: 3 }),
    minded("warmth"),
  );
  assert(
    fortyThree.mark("도수")!.range === "40~42%",
    fortyThree.mark("도수")!.range,
  );
});

/* ------------------------- what every guide holds, whatever was said ---- */

Deno.test("guide: a whisky is said in words by what was liked, what the chosen cask brings and what to leave out", () => {
  const { guide } = guideFor(SHERRY_MALT, [
    ...aromaSaid("vanilla", "liked"),
    ...aromaSaid("smoke", "disliked"),
    ...sweetness(4, "liked"),
    ...minded("warmth"),
    LONG_FINISH,
  ]);
  const line = (label: string) =>
    guide.profile?.find((l) => l.label === label)?.words ?? [];
  // 바닐라 was liked; 버번 캐스크, the chip, is made to bring it; 스모키 is left out.
  assert(
    line("AROMA").join(",") === "바닐라,스모키 없이",
    JSON.stringify(guide.profile),
  );
  assert(
    line("FLAVOR").join(",") === "또렷한 단맛,알코올 열감 덜하게",
    JSON.stringify(guide.profile),
  );
  assert(line("FINISH").join(",") === "긴 여운", JSON.stringify(guide.profile));
  // With its profile a whisky keeps the 도수 band alone.
  assert(
    guide.levels.map((l) => l.label).join(",") === "도수",
    JSON.stringify(guide.levels),
  );
});

Deno.test("guide: whatever one answer a reader gives, the guide keeps its shape", () => {
  const bottles: [string, SensoryProduct][] = [
    ["wine", DRY_RED],
    ["wine", DRY_WHITE],
    ["whisky", SHERRY_MALT],
    ["whisky", PEATED_MALT],
    ["korean_traditional", FRESH_TAKJU],
    ["korean_traditional", POT_BARLEY_SOJU],
    [
      "sake",
      bottle("sake", "junmai", 15, { sweetness: 3, acidity: 3, body: 3 }),
    ],
  ];
  const said = [
    ...["sweetness", "acidity", "umami"].flatMap((taste) => [
      [`level:${taste}:3:liked`],
      [`level:${taste}:4:disliked`],
    ]),
    ...Object.keys(FEEL).flatMap((key) => [feel(key, "liked"), minded(key)]),
    ...["vanilla", "smoke", "floral", "rice", "cherry"].flatMap((aroma) => [
      aromaSaid(aroma, "liked"),
      aromaSaid(aroma, "disliked"),
      [`aroma:palate:${aroma}:liked`],
      [`aroma:finish:${aroma}:liked`],
    ]),
    [TOO_SHORT],
    [OFF_FLAVOR],
    [LONG_FINISH],
    ["level:finish_character:4:liked"],
  ];
  let guides = 0;
  for (const [category, product] of bottles) {
    for (const answers of said) {
      const guide = writeGuide(
        buildCardFacts(recordFrom(product.name, answers, product)),
      );
      if (!guide) continue;
      assertShape(`${product.name} ${answers[0]}`, category, guide);
      guides++;
    }
  }
  assert(guides > 100, `only ${guides} guides`);
});

/* ---------------------------------- the reader's own words, and no others ---- */

const scentOf = (key: string) => {
  const name = terms("aroma").find((t) => t.key === key)?.names.ko ?? key;
  return /..향$/.test(name) ? name : `${name} 향`;
};

/** A frame as a pattern, with what filled {X} and {L}. */
function frameOf(template: string) {
  const pattern = template
    .replace(/[.*+?^$()|[\]\\]/g, "\\$&")
    .replace("{X}", "(?<X>.+?)")
    .replace("{L}", "(?<L>.+?)")
    .replace(/\{은\}/g, "(?:은|는)")
    .replace(/\{이\}/g, "(?:이|가)")
    .replace(/\{과\}/g, "(?:과|와)");
  return new RegExp(`^${pattern}`);
}

const FRAMES = [
  NOTE_EASE_KEEP,
  NOTE_FILL_KEEP,
  NOTE_ONLY_EASE_ALIKE,
  NOTE_ONLY_FILL_ALIKE,
  NOTE_ONLY_EASE,
  NOTE_ONLY_FILL,
  NOTE_CARRY,
].map(frameOf);

const wordsIn = (slot: string | undefined) =>
  slot ? slot.split(/(?:과|와) /) : [];

/** What the reader called a burden or a lack, and what they liked, read from the answers themselves. */
function saidBy(facts: CardFacts) {
  const key = (r: CardFacts["reactions"][number]) =>
    `${r.subject.domain}.${r.subject.key}`;
  const burdens = new Set(
    facts.reactions.filter((r) => r.reaction === "burden").map((r) =>
      r.subject.domain === "aroma" ? scentOf(r.subject.key) : BURDENED[key(r)]
    ),
  );
  const liked = new Set(
    facts.reactions.filter((r) => r.reaction === "liked").flatMap((r) =>
      r.subject.domain === "aroma"
        ? [scentOf(r.subject.key)]
        : [LIKED[key(r)], BURDENED[key(r)]].filter(Boolean)
    ),
  );
  return { burdens, liked };
}

Deno.test("guide: a note eases only what the reader called a burden, in their own word, and never something they liked", () => {
  const bottles: SensoryProduct[] = [
    DRY_RED,
    DRY_WHITE,
    SHERRY_MALT,
    BOURBON_CASK_MALT,
    PEATED_MALT,
    bottle("whisky", "bourbon", 45, { sweetness: 4, body: 4 }, {
      processes: ["wooden_cask"],
    }),
    FRESH_TAKJU,
    THICK_TAKJU,
    POT_BARLEY_SOJU,
    bottle("sake", "junmai", 15, { sweetness: 3, acidity: 3, body: 3 }),
  ];
  const atoms: string[][] = [
    sweetness(4, "liked"),
    sweetness(4, "disliked"),
    sweetness(2, "disliked"),
    ["level:acidity:3:liked"],
    ["level:acidity:4:disliked"],
    feel("heavy", "liked"),
    feel("heavy", "disliked"),
    feel("light", "liked"),
    feel("light", "disliked"),
    feel("warmth", "disliked"),
    feel("smooth", "liked"),
    aromaSaid("vanilla", "liked"),
    aromaSaid("vanilla", "disliked"),
    aromaSaid("smoke", "disliked"),
    aromaSaid("floral", "liked"),
    [TOO_SHORT],
    [OFF_FLAVOR],
    [LONG_FINISH],
  ];
  // One gauge holds one step, one aroma one answer in a picker.
  const subject = (a: string[]) =>
    a[0].split(":").slice(0, 2).join(":") +
    (a[0].startsWith("aroma:") ? `:${a[0].split(":")[2]}` : "");
  let framed = 0;
  const wrong: string[] = [];
  for (const product of bottles) {
    for (let i = 0; i < atoms.length; i++) {
      for (let j = i + 1; j < atoms.length; j++) {
        if (subject(atoms[i]) === subject(atoms[j])) continue;
        const answers = [...atoms[i], ...atoms[j]];
        const facts = buildCardFacts(
          recordFrom(product.name, answers, product),
        );
        const { burdens, liked } = saidBy(facts);
        for (const pick of writeGuide(facts)?.picks ?? []) {
          const found = FRAMES.map((frame) => pick.note?.match(frame)?.groups)
            .find(Boolean);
          if (!found) continue;
          framed++;
          const eased = wordsIn(found.X);
          const carried = wordsIn(found.L).map((w) =>
            w.replace(/^(은은한|또렷한) /, "")
          );
          if (
            eased.some((w) => !burdens.has(w)) ||
            eased.some((w) => liked.has(w) && !burdens.has(w)) ||
            carried.some((w) => !liked.has(w))
          ) {
            wrong.push(`${product.name} ${answers.join(" ")}: ${pick.note}`);
          }
        }
      }
    }
  }
  assert(framed > 500, `only ${framed} framed notes`);
  assert(
    wrong.length === 0,
    `${wrong.length} of ${framed}: ${wrong.slice(0, 5).join(" | ")}`,
  );
});

Deno.test("guide: a card of liked answers alone with no chip to give names what the bottle itself is", () => {
  // Liked answers no chip speaks of: a smooth tannin, a long finish.
  const smooth = feel("smooth", "liked");
  const chip = (product: SensoryProduct, answers = [LONG_FINISH]) =>
    guideFor(product, answers).guide.picks;
  // No grape answers a liked 목넘김: the bottle's own grape, led by where its style is from.
  const red = chip(
    { ...DRY_RED, region: "보르도(Bordeaux) > 메독(Medoc)" },
    smooth,
  );
  assert(
    red.length === 1 &&
      red[0].keyword === "Cabernet Sauvignon(까베르네 소비뇽)" &&
      red[0].labelWord === false && red[0].note === NOTE_SAME_GRAPE &&
      red[0].country === "fr" && red[0].place === "프랑스 메독",
    JSON.stringify(red),
  );
  // A grape the kind's shelf hardly holds is not named, nor a bottle without one.
  const tannat = chip(
    bottle("wine", "red_wine", 13, { sweetness: 1, acidity: 3, body: 3 }, {
      grapes: ["tannat"],
    }),
    smooth,
  );
  assert(tannat.length === 0, JSON.stringify(tannat));
  // A sparkling wine of a named style: the style. (Sparkling styles say how
  // long their finish is, so a liked finish is answered by other styles.)
  const champagne = chip({
    ...bottle("wine", "sparkling_wine", 12, {
      sweetness: 1,
      acidity: 4,
      carbonation: 4,
      body: 3,
    }),
    region: "샹빠뉴(Champagne)",
  }, aromaSaid("smoke", "liked"));
  assert(
    champagne.map((p) => p.keyword).join() === "Champagne(샴페인)" &&
      champagne[0].labelWord === false && champagne[0].note === NOTE_SAME_KIND,
    JSON.stringify(champagne),
  );
  // A sake: its grade.
  const sake = chip(
    bottle("sake", "junmai", 15, { sweetness: 3, acidity: 3, body: 3 }),
    aromaSaid("smoke", "liked"),
  );
  assert(
    sake.map((p) => p.keyword).join() === "純米(준마이)" &&
      sake[0].labelWord === false && sake[0].note === NOTE_SAME_GRADE,
    JSON.stringify(sake),
  );
  // A fortified wine: the word its own label carries, else its kind's.
  const named = (name: string, styleKey: string, answers?: string[]) =>
    chip({
      ...bottle("wine", styleKey, 18, { sweetness: 2, acidity: 3, body: 3 }),
      name,
    }, answers);
  const fino = named("티오 페페 피노", "sherry_wine");
  assert(
    fino.map((p) => p.keyword).join() === "Fino(피노)" &&
      fino[0].labelWord === true && fino[0].note === NOTE_SAME_KIND,
    JSON.stringify(fino),
  );
  assert(
    named("테일러 10년 토니 포트", "port_wine", smooth)[0]?.keyword ===
      "Tawny(토니)",
    "tawny port",
  );
  assert(
    named("그라함 포트", "port_wine", smooth)[0]?.keyword === "Port(포트 와인)",
    "port",
  );
  assert(named("루스타우 셰리", "sherry_wine").length === 0, "plain sherry");
  // Never with a burden: the same thing would carry it again.
  const burdened = chip({ ...DRY_RED, region: "보르도(Bordeaux)" }, [
    ...smooth,
    OFF_FLAVOR,
  ]);
  assert(
    burdened.every((p) => !p.keyword.includes("Cabernet Sauvignon")),
    JSON.stringify(burdened),
  );
  // A whisky has its profile and a traditional drink its own-ingredient chip: neither is given one.
  for (const product of [SHERRY_MALT, VACUUM_SOJU]) {
    assert(
      chip(product).every((p) =>
        ![NOTE_SAME_GRAPE, NOTE_SAME_GRADE, NOTE_SAME_KIND].includes(
          p.note ?? "",
        )
      ),
      product.name,
    );
  }
});
