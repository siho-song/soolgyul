import { writeGuide } from "../../_shared/taste_card/summary/guide.ts";
import { terms } from "../../_shared/taste_card/dictionary/dictionary.ts";
import { grapeLeans } from "../../_shared/taste_card/facts/kind_place.ts";
import { buildCardFacts } from "../../_shared/taste_card/findings/conclusions.ts";
import { fixtures, recordFrom } from "../helpers/card_fixture_record.ts";
import type { CardFacts } from "../../_shared/taste_card/facts/facts.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
import { assert } from "../helpers/assert.ts";

// Which shelf each kind is read on: the chips and marks every card of it
// gets, so no kind leaves the reader with directions alone.
Deno.test("guide: every BP card has a guide with picks or directions", async () => {
  for (const [name, facts] of await fixtures()) {
    const guide = writeGuide(facts);
    assert(guide, `${name}: no guide`);
    assert(
      guide.picks.length > 0 || guide.directions.length > 0,
      `${name}: nothing to look for`,
    );
    for (const pick of guide.picks) {
      assert(
        !/향이 나는 향이/.test(pick.note ?? ""),
        `${name}: ${pick.note} says 향 twice`,
      );
    }
  }
});

Deno.test("guide: traditional cards get the shops' marks, and each label chip says what it brings", async () => {
  for (const [name, facts] of await fixtures()) {
    if (facts.record.category !== "korean_traditional") continue;
    const guide = writeGuide(facts)!;
    assert(
      guide.picks.length > 0 || guide.directions.length > 0,
      `${name}: nothing to look for`,
    );
    // A word in quotes to find on the label, then what it brings and why.
    assert(
      guide.picks.every((p) =>
        p.keyword.includes("'") && p.keyword.endsWith(" 표기") &&
        /요\.$/.test(p.note ?? "") && !/[{}]/.test(p.note ?? "")
      ),
      `${name}: not a label word with its reason: ${
        JSON.stringify(guide.picks)
      }`,
    );
    assert(
      guide.levels.map((l) => l.label).join(",") === "단맛,산미,탄산,바디,도수",
      `${name}: ${guide.levels.map((l) => l.label)}`,
    );
    assert(
      guide.levels.at(-1)!.range.includes("%"),
      `${name}: 도수 ${guide.levels.at(-1)!.range}`,
    );
    assert(guide.tip?.includes("맛 그래프"), `${name}: ${guide.tip}`);
  }
});

Deno.test("guide: whisky cards name the 도수 band, filled with label cues", async () => {
  const byName = new Map(await fixtures());
  // 라프로익 쿼터 캐스크 (48%, 열감 부담): two bands down, never under the legal 40%.
  const laphroaig = writeGuide(byName.get("bp-05.json")!)!;
  assert(
    laphroaig.levels.length === 1 && laphroaig.levels[0].label === "도수" &&
      laphroaig.levels[0].mark === 2 && laphroaig.levels[0].range === "40~43%",
    JSON.stringify(laphroaig.levels),
  );
  assert(
    laphroaig.tip !== null && laphroaig.tip.includes("라벨") &&
      laphroaig.tip.endsWith("!"),
    laphroaig.tip ?? "no tip",
  );
  // 아드벡 우거다일: one cask shares the aroma; the 단맛 cue fills the second chip.
  const ardbeg = writeGuide(byName.get("bp-12.json")!)!;
  assert(ardbeg.picks.length === 2, JSON.stringify(ardbeg.picks));
  assert(
    ardbeg.picks[1].keyword === "'Bourbon Cask' 표기" &&
      ardbeg.picks[1].note!.startsWith("함께 보시면 좋은 표기예요."),
    JSON.stringify(ardbeg.picks[1]),
  );
  // 54.2% found heavy while drinking: a whisky weighs less the weaker it is,
  // so the band under the bottle's own.
  assert(ardbeg.levels[0].range === "47~50%", ardbeg.levels[0].range);
});

Deno.test("guide: sake grades share one chip with the liked aromas they carry", async () => {
  const byName = new Map(await fixtures());
  const dassai = writeGuide(byName.get("bp-03.json")!)!;
  // One chip carries both grades; its note names the liked aroma.
  assert(dassai.picks.length === 1, JSON.stringify(dassai.picks));
  const [grades] = dassai.picks;
  assert(
    grades.keyword.includes("다이긴조") && grades.keyword.includes("긴조") &&
      grades.keyword.includes(" · "),
    grades.keyword,
  );
  assert(
    grades.note !== null && grades.note.includes("배") &&
      /요[.!]?$/.test(grades.note),
    grades.note ?? "no note",
  );
  assert(
    dassai.levels.map((l) => l.label).join(",") === "당도(주도),산미(산도)" &&
      dassai.levels.every((l) => l.range.length > 0),
    JSON.stringify(dassai.levels),
  );
  assert(
    dassai.tip !== null && dassai.tip.includes("라벨") &&
      dassai.tip.endsWith("!"),
    dassai.tip ?? "no tip",
  );
});

Deno.test("guide: a 40% whisky found hot still gets its guide, aimed at the floor band", () => {
  // 조니워커 블랙 라벨: 40% is the lowest a whisky goes, so the 열감 burden has
  // nowhere lower to point; the guide keeps the floor instead of vanishing.
  const facts = buildCardFacts(recordFrom("jw-black-hot", [
    "revisit:unsure",
    "reaction:taste:sweetness:liked",
    "notice:aroma:chocolate",
    "reaction:aroma:chocolate:liked",
    "notice:mouthfeel:warmth",
    "reaction:mouthfeel:warmth:disliked",
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
  assert(guide.directions.length > 0, "no directions");
});

/** Cards once saved without a guide (the 테스터 account, 2026-11-08). */
async function gapCard(name: string): Promise<CardFacts> {
  const url = new URL(`../fixtures/guide_gaps/${name}.json`, import.meta.url);
  return JSON.parse(await Deno.readTextFile(url));
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
  assert(
    guide.directions.every((d) => d.change === "lower"),
    JSON.stringify(guide.directions),
  );
});

Deno.test("guide: an aroma to turn is one of the directions", async () => {
  // 조니워커 블랙 라벨: 스모키 향 to turn down beside 알코올 열감.
  const guide = writeGuide(await gapCard("jw-black-smoke"))!;
  assert(
    guide.directions.some((d) =>
      d.word === "스모키 향" && d.change === "lower"
    ),
    JSON.stringify(guide.directions),
  );
});

Deno.test("guide: a sake unlike every grade gets the label numbers, no far grade", async () => {
  // 카나가소: 산미·바디·알코올감 high, every grade low; 긴조 would miss its 곡물 향,
  // and no label word speaks of 곡물·쌀 향.
  const guide = writeGuide(await gapCard("kanagaso"));
  assert(guide, "no guide for a bottle unlike every grade");
  assert(guide.picks.length === 0, JSON.stringify(guide.picks));
  assert(
    guide.levels.map((l) => l.label).join(",") === "당도(주도),산미(산도)",
    JSON.stringify(guide.levels),
  );
  assert(guide.tip !== null, "no tip");
});

Deno.test("guide: a rosé with no grape to name gets its own label words", async () => {
  // 텔리아니 밸리 뮈스카: 산미 to soften; the dictionary's rosé cue is 'Saignée'.
  const guide = writeGuide(await gapCard("teliani-muscat-rose"));
  assert(guide, "no guide for a rosé");
  assert(
    guide.picks[0]?.keyword === "'Saignée' 표기",
    JSON.stringify(guide.picks),
  );
  assert(
    guide.levels.map((l) => l.label).join(",") === "당도,산도,타닌,바디",
    JSON.stringify(guide.levels),
  );
});

Deno.test("guide: a sparkling wine no regional style softens gets label words", async () => {
  // 따흘랑 뀌베 루이: 산미 and 떫은맛 to turn down; no listed style is softer.
  const guide = writeGuide(await gapCard("taittinger-louis"));
  assert(guide, "no guide for the sparkling wine");
  assert(
    guide.picks.length > 0 &&
      guide.picks.every((p) => p.keyword.endsWith("표기")),
    JSON.stringify(guide.picks),
  );
  // A champagne drinker is not sent to a red sparkling.
  assert(
    guide.picks.every((p) => !p.keyword.includes("Lambrusco")),
    JSON.stringify(guide.picks),
  );
  assert(
    guide.levels.map((l) => l.label).join(",") === "당도,산도,탄산,바디",
    JSON.stringify(guide.levels),
  );
});

Deno.test("guide: a sake no grade fits gets label words by the liked aroma", async () => {
  // 요코야마 실버 7: 청사과 향 liked; '쿄카이 1801호' brings 사과 향, of its line.
  const guide = writeGuide(await gapCard("yokoyama-silver-7"))!;
  assert(
    guide.picks[0]?.keyword === "'쿄카이 1801호' 표기",
    JSON.stringify(guide.picks),
  );
  // The label numbers stay in the marks, not in a chip.
  assert(
    guide.picks.every((p) => !p.keyword.includes("일본주도")) &&
      guide.levels.map((l) => l.label).join(",") === "당도(주도),산미(산도)",
    JSON.stringify(guide),
  );
});

Deno.test("guide: a sake no grade fits gets label words for the level to turn", async () => {
  // 이상 준마이: 단맛 wanted higher, 가벼운 질감 kept.
  const guide = writeGuide(await gapCard("isse-junmai"))!;
  assert(
    guide.picks.map((p) => p.keyword).join(",") ===
      "'기조슈' 표기,'정미보합' 표기",
    JSON.stringify(guide.picks),
  );
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

const UNSURE = ["mouthfeel:unsure", "finish:unsure", "revisit:unsure"];

function likedAroma(aroma: string): string[] {
  return [
    `notice:aroma:${aroma}`,
    `reaction:aroma:${aroma}:liked`,
    "reaction:taste:sweetness:fine",
    ...UNSURE,
  ];
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

Deno.test("guide: a cask chip says what the cask does and then its aroma, and 백단향 is not given a second 향", () => {
  const guide = writeGuide(buildCardFacts(recordFrom(
    "malt-wood",
    likedAroma("wood"),
    plainBottle("whisky", "single_malt_whisky", 46),
  )))!;
  const mizunara = guide.picks.find((p) => p.keyword.includes("Mizunara"));
  assert(
    mizunara?.note ===
      "수분이 많고 조직이 성긴 물참나무에서 장기 숙성을 거쳐 동양적이고 고풍스러운 그윽한 결을 입혀요. 차분하고 그윽한 백단향이 나요.",
    JSON.stringify(guide.picks),
  );
});

Deno.test("guide: a 약주 chip says where on the label its word is printed", () => {
  const guide = writeGuide(buildCardFacts(recordFrom("yakju-heavy", [
    "notice:mouthfeel:heavy",
    "reaction:mouthfeel:heavy:liked",
    "reaction:taste:sweetness:fine",
    "finish:unsure",
    "revisit:unsure",
  ], plainBottle("korean_traditional", "yakju", 13))))!;
  // The better-sourced word first; a second word for the same answer fills the free place.
  assert(
    guide.picks.map((p) => p.keyword).join(",") ===
      "원재료명 '찹쌀' 표기,'원주' 표기",
    JSON.stringify(guide.picks),
  );
  assert(
    guide.picks[0].note?.includes("바디감"),
    guide.picks[0].note ?? "no note",
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
const LIGHT_SOJU = traditional(
  "distilled_soju",
  17,
  { sweetness: 2, acidity: 2, bitterness: 1, body: 2 },
  ["rice"],
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

const FINE = "reaction:taste:sweetness:fine";

/** The guide for one bottle and its answers; the sections left out are 모르겠어요. */
function guideFor(product: SensoryProduct, answers: string[]) {
  const said = (section: string) =>
    answers.some((a) => a.includes(`${section}:`));
  const guide = writeGuide(buildCardFacts(recordFrom(product.name, [
    ...answers,
    ...(answers.some((a) => a.includes(":taste:")) ? [] : [FINE]),
    ...(said("mouthfeel") ? [] : ["mouthfeel:unsure"]),
    ...(said("finish") ? [] : ["finish:unsure"]),
    "revisit:unsure",
  ], product)));
  assert(guide, `${product.name}: no guide for ${answers}`);
  return {
    guide,
    words: guide.picks.map((p) => p.keyword),
    mark: (label: string) => guide.levels.find((l) => l.label === label),
  };
}

const minded = (key: string) => [
  `notice:mouthfeel:${key}`,
  `reaction:mouthfeel:${key}:disliked`,
];

Deno.test("guide: 증류식 소주 shows 단맛 and 바디 beside the bottle's own 도수", () => {
  const { guide, mark } = guideFor(VACUUM_SOJU, [
    FINE,
    "reaction:taste:acidity:fine",
    "reaction:taste:bitterness:fine",
  ]);
  assert(
    guide.levels.map((l) => l.label).join(",") === "단맛,바디,도수",
    JSON.stringify(guide.levels),
  );
  // Nothing to turn: the number printed on this bottle is the place to look.
  assert(mark("도수")!.range === "25% 안팎", mark("도수")!.range);
  assert(guide.tip?.includes("맛 그래프"), guide.tip ?? "no tip");
});

Deno.test("guide: a burden's label word goes before the cask of a liked aroma", () => {
  const { guide, words } = guideFor(POT_BARLEY_SOJU, [
    "finish:offFlavor",
    "notice:aroma:vanilla",
    "reaction:aroma:vanilla:liked",
  ]);
  assert(words[0] === "'감압증류' 표기", JSON.stringify(words));
  assert(guide.picks[0].note?.includes("잡내"), guide.picks[0].note ?? "");
  assert(words.length === 2, JSON.stringify(words));
  // The cask shares the liked aroma and is not the other side of '감압증류'.
  assert(
    guide.picks[1].note?.includes("바닐라 향") && !words[1].includes("상압"),
    JSON.stringify(guide.picks[1]),
  );
});

Deno.test("guide: the word the bottle already carries is no answer to its burden", () => {
  // A 감압증류 soju found hot or leaving 잡내: '감압증류' is not what to change to.
  for (const answers of [["finish:offFlavor"], minded("warmth")]) {
    const { words } = guideFor(VACUUM_SOJU, answers);
    assert(
      words.every((w) => !w.includes("감압증류")),
      `${answers}: ${JSON.stringify(words)}`,
    );
  }
  // 도수 to lower ends under the bottle's own 25%.
  const hot = guideFor(VACUUM_SOJU, minded("warmth"));
  assert(hot.mark("도수")!.range === "17~24%", hot.mark("도수")!.range);
});

Deno.test("guide: of two words told apart by comparison, neither is named against an answer the other gives", () => {
  // 여운이 짧았고 잡내가 남았다: 상압증류 leaves more 잡내, 감압증류 a shorter finish.
  const { words } = guideFor(LIGHT_SOJU, [
    "finish:tooShort",
    "finish:offFlavor",
  ]);
  assert(
    words.join(",") === "'옹기 숙성'·'항아리 숙성' 표기",
    JSON.stringify(words),
  );
});

Deno.test("guide: 가벼움 to turn down is a heavier bottle", () => {
  const { guide, words, mark } = guideFor(FRESH_TAKJU, minded("light"));
  assert(
    guide.directions.some((d) => d.word === "가벼움" && d.change === "lower"),
    JSON.stringify(guide.directions),
  );
  assert(mark("바디")!.mark === 3, JSON.stringify(mark("바디")));
  assert(mark("도수")!.range === "8.5~12.5%", mark("도수")!.range);
  assert(words[0] === "'원주' 표기", JSON.stringify(words));
});

Deno.test("guide: 묵직함 to turn down lowers the 도수 a band under the bottle's own", () => {
  const takju = guideFor(THICK_TAKJU, minded("heavy"));
  assert(takju.mark("바디")!.mark === 2, JSON.stringify(takju.mark("바디")));
  assert(takju.mark("도수")!.range === "6~8.5%", takju.mark("도수")!.range);
  const soju = guideFor(POT_BARLEY_SOJU, minded("heavy"));
  assert(soju.mark("도수")!.range === "25~36%", soju.mark("도수")!.range);
  assert(
    soju.words.join(",") === "'감압증류' 표기,원재료명 '쌀' 표기",
    JSON.stringify(soju.words),
  );
});

Deno.test("guide: 텁텁함 has its own word and is not answered with a heavier bottle", () => {
  // 뒤가 텁텁했고 여운은 짧았다: '원주' would lengthen the finish and thicken the rest.
  const { guide, words } = guideFor(FRESH_TAKJU, [
    "finish:heavy",
    "finish:tooShort",
  ]);
  assert(
    guide.directions.some((d) => d.word === "텁텁함" && d.change === "lower"),
    JSON.stringify(guide.directions),
  );
  assert(words.join(",") === "'살균탁주' 표기", JSON.stringify(words));
  assert(guide.picks[0].note?.includes("텁텁한 잔여감이 덜하고"), "");
});

Deno.test("guide: the reason a taste was liked names the side to look on", () => {
  // 산미 2 of 5, liked because it was 또렷했다: more of it, not less.
  const clear = guideFor(THICK_TAKJU, [
    "reaction:taste:acidity:liked",
    "reason:taste:acidity:liked:pronounced",
  ]);
  assert(clear.words[0] === "'생막걸리' 표기", JSON.stringify(clear.words));
  assert(
    clear.guide.picks[0].note?.includes("신맛이 또렷해요"),
    clear.guide.picks[0].note ?? "",
  );
  assert(clear.mark("산미")!.range === "2~3", clear.mark("산미")!.range);
  // The same level liked because it was 은은했다 stays on the low side.
  const mild = guideFor(THICK_TAKJU, [
    "reaction:taste:acidity:liked",
    "reason:taste:acidity:liked:gentle",
  ]);
  assert(
    mild.words.every((w) => w !== "'생막걸리' 표기"),
    JSON.stringify(mild.words),
  );
  assert(mild.mark("산미")!.range === "1~2", mild.mark("산미")!.range);
});

Deno.test("guide: a 탄산 burden is not sent to 생막걸리 for its lower sweetness", () => {
  const { words } = guideFor(THICK_TAKJU, [
    "reaction:taste:sweetness:disliked",
    "reason:taste:sweetness:disliked:too_strong",
    ...minded("bubbles"),
  ]);
  assert(words.length > 0, "no label word for 단맛 to lower");
  assert(
    words.every((w) => !w.includes("생막걸리")),
    JSON.stringify(words),
  );
});

Deno.test("guide: 이번 술과 같은 원료 is said of an ingredient that tells bottles apart, never of 쌀", () => {
  const liked = [
    "reaction:taste:sweetness:liked",
    "reason:taste:sweetness:liked:harmony",
  ];
  const sweetPotato = guideFor(
    traditional(
      "distilled_soju",
      40,
      { sweetness: 3, acidity: 2, bitterness: 1, body: 4 },
      ["sweet_potato"],
    ),
    liked,
  );
  assert(
    sweetPotato.words.join(",") === "원재료명 '고구마' 표기",
    JSON.stringify(sweetPotato.words),
  );
  assert(
    sweetPotato.guide.picks[0].note?.startsWith("이번 술과 같은 원료예요. "),
    sweetPotato.guide.picks[0].note ?? "",
  );
  assert(
    guideFor(VACUUM_SOJU, liked).words.length === 0,
    "쌀 is on most labels of the kind",
  );
});

Deno.test("guide: every direction the reader gave stays, with or without a label word for it", () => {
  // No 탁주 label says how bitter it is: the direction is still the reader's own.
  const { guide, words } = guideFor(FRESH_TAKJU, [
    "reaction:taste:bitterness:disliked",
    "reason:taste:bitterness:disliked:too_strong",
  ]);
  assert(
    guide.directions.length === 1 && guide.directions[0].word === "쓴맛" &&
      guide.directions[0].change === "lower",
    JSON.stringify(guide.directions),
  );
  assert(words.length === 0, JSON.stringify(words));
});

Deno.test("guide: every cask or method chip is a word printed on a label", () => {
  const malt = plainBottle("whisky", "single_malt_whisky", 46);
  for (const aroma of ["vanilla", "wood", "caramel", "dried_fruit", "citrus"]) {
    const guide = writeGuide(
      buildCardFacts(recordFrom(`malt-${aroma}`, likedAroma(aroma), malt)),
    );
    for (const pick of guide?.picks ?? []) {
      assert(
        /\(.*[A-Za-z].*\)|'/.test(pick.keyword),
        `${aroma}: ${pick.keyword} names no label word`,
      );
    }
  }
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

const sweetness = (side: "liked" | "disliked", why: string) => [
  `reaction:taste:sweetness:${side}`,
  `reason:taste:sweetness:${side}:${why}`,
];
const aromaSaid = (key: string, side: "liked" | "disliked") => [
  `notice:aroma:${key}`,
  `reaction:aroma:${key}:${side}`,
];

/** The counted lean of each grape a guide named, by the name on its chip. */
function leansOf(styleKey: string, words: readonly string[]) {
  const named = new Map(
    terms("grape").map((t) => [t.names.ko.replace(/\(.*\)/, "").trim(), t.key]),
  );
  const leans = new Map(grapeLeans(styleKey).map((g) => [g.grape, g]));
  return words.map((word) => {
    const lean = leans.get(named.get(word) ?? "");
    assert(lean, `${word} is not a counted grape of ${styleKey}`);
    return lean;
  });
}

Deno.test("guide: a red found too little sweet keeps its 당도 mark and is steered by what makes a wine feel sweeter", () => {
  const { guide, words, mark } = guideFor(
    DRY_RED,
    sweetness("disliked", "too_weak"),
  );
  // The reader's own direction stays; the mark no red shelf can answer does not move.
  assert(
    guide.directions.some((d) => d.word === "단맛" && d.change === "higher"),
    JSON.stringify(guide.directions),
  );
  assert(
    mark("당도")!.mark === 1 && mark("당도")!.range === "1",
    JSON.stringify(mark("당도")),
  );
  // 타닌 and 산도 hold the felt sweetness down: each a step under the bottle's own.
  assert(mark("타닌")!.mark === 3, JSON.stringify(mark("타닌")));
  assert(mark("산도")!.mark === 3, JSON.stringify(mark("산도")));
  assert(words.length > 0, "no grape to look for");
  assert(
    guide.picks.every((p) => p.note?.endsWith("더 달게 느껴져요.")),
    JSON.stringify(guide.picks),
  );
  for (const lean of leansOf("red_wine", words)) {
    assert(lean.sweeter > 1 / 3 && lean.sweeter > lean.drier, lean.grape);
  }
});

Deno.test("guide: a liked sweetness in a red names the grapes that lean sweeter, by their counted lean and never the firm ones", () => {
  const clear = guideFor(DRY_RED, sweetness("liked", "pronounced"));
  const leans = leansOf("red_wine", clear.words);
  assert(leans.length === 2, JSON.stringify(clear.words));
  assert(
    leans[0].sweeter >= leans[1].sweeter &&
      leans.every((lean) => lean.sweeter > 1 / 3),
    JSON.stringify(leans),
  );
  // The strongest lean of the kind goes first, whatever its bottle count.
  const strongest = Math.max(...grapeLeans("red_wine").map((g) => g.sweeter));
  assert(leans[0].sweeter === strongest, JSON.stringify(leans[0]));
  assert(
    clear.words.every((w) => !/산지오베제|네비올로/.test(w)),
    JSON.stringify(clear.words),
  );
  assert(
    clear.guide.picks.every((p) => (p.note ?? "").length > 0),
    JSON.stringify(clear.guide.picks),
  );
  assert(clear.mark("당도")!.range === "1", clear.mark("당도")!.range);
  // 은은해서 좋았다 asks for the other side.
  const mild = guideFor(DRY_RED, sweetness("liked", "gentle"));
  for (const lean of leansOf("red_wine", mild.words)) {
    assert(lean.drier > 1 / 3 && lean.drier > lean.sweeter, lean.grape);
  }
  assert(
    mild.guide.picks.every((p) => p.note?.endsWith("덜 달게 느껴져요.")),
    JSON.stringify(mild.guide.picks),
  );
});

Deno.test("guide: a white found too little sweet is steered by its 산도, and a level its kind has may rise", () => {
  const { guide, words, mark } = guideFor(
    DRY_WHITE,
    sweetness("disliked", "too_weak"),
  );
  assert(mark("산도")!.mark === 3, JSON.stringify(mark("산도")));
  // A white has no 타닌 to turn; one white in six carries 당도 2 or more.
  assert(mark("타닌")!.mark === 1, JSON.stringify(mark("타닌")));
  assert(mark("당도")!.mark === 2, JSON.stringify(mark("당도")));
  for (const lean of leansOf("white_wine", words)) {
    assert(lean.sweeter > 1 / 3 && lean.sweeter > lean.drier, lean.grape);
  }
  assert(
    guide.picks.every((p) => (p.note ?? "").length > 0),
    JSON.stringify(guide.picks),
  );
});

Deno.test("guide: the reader's own word for a strength outranks the catalog number", () => {
  // 단맛 2 of 5 in the catalog, liked because it was 또렷했다: more of it.
  const { guide, words } = guideFor(
    SHERRY_MALT,
    sweetness("liked", "pronounced"),
  );
  assert(words.length > 0, "nothing to look for");
  assert(
    guide.picks.every((p) =>
      !p.keyword.includes("Bourbon") && !p.note?.includes("과하지 않고")
    ),
    JSON.stringify(guide.picks),
  );
  assert(
    guide.picks[0].note?.startsWith("단맛이 도는 쪽이에요."),
    guide.picks[0].note ?? "",
  );
  // 단맛 4 of 5, liked because it was 은은했다: not a sweeter cask.
  const mild = guideFor(BOURBON_CASK_MALT, sweetness("liked", "gentle"));
  assert(
    mild.guide.picks.every((p) => !p.keyword.includes("Sherry")),
    JSON.stringify(mild.guide.picks),
  );
});

Deno.test("guide: 가벼워서 아쉬웠다 is a heavier bottle in whisky, wine and sake", () => {
  const malt = guideFor(BOURBON_CASK_MALT, minded("light"));
  assert(
    malt.words.every((w) => !w.includes("Triple")) &&
      malt.guide.picks[0]?.note?.includes("묵직"),
    JSON.stringify(malt.guide.picks),
  );
  // A whisky weighs more the stronger it is: one band over the bottle's 40%.
  assert(malt.mark("도수")!.range === "43~47%", malt.mark("도수")!.range);
  const lightRed = bottle("wine", "red_wine", 12.5, {
    sweetness: 1,
    acidity: 3,
    astringency: 2,
    body: 2,
  }, { grapes: ["pinot_noir"] });
  const red = guideFor(lightRed, minded("light"));
  assert(red.mark("바디")!.mark === 3, JSON.stringify(red.mark("바디")));
  assert(
    red.words.length > 0 && red.words.every((w) => !w.includes("가메")),
    JSON.stringify(red.words),
  );
  const junmai = bottle("sake", "junmai", 15, {
    sweetness: 3,
    acidity: 3,
    body: 2,
  });
  const sake = guideFor(junmai, minded("light"));
  assert(
    sake.words.every((w) => !w.includes("긴조")),
    JSON.stringify(sake.words),
  );
});

Deno.test("guide: a card whose only burden is an aroma is told the label word to pass over", () => {
  const { guide, words } = guideFor(
    PEATED_MALT,
    aromaSaid("smoke", "disliked"),
  );
  assert(
    guide.head === "부담은 줄인 싱글 몰트 위스키의 추천 키워드예요.",
    guide.head,
  );
  assert(
    guide.directions.length === 1 &&
      guide.directions[0].word === "스모키 향" &&
      guide.directions[0].change === "lower",
    JSON.stringify(guide.directions),
  );
  assert(
    words.join(",") === "'Peated' 표기가 없는 것",
    JSON.stringify(words),
  );
  // The dictionary's own caution about the word.
  assert(
    guide.picks[0].note ===
      "라벨에 'Peated'나 'Islay'가 있으면 훈연 향이 센 쪽이에요.",
    guide.picks[0].note ?? "",
  );
  // Beside a liked aroma it keeps one of the two places.
  const both = guideFor(BOURBON_CASK_MALT, [
    ...aromaSaid("vanilla", "liked"),
    ...aromaSaid("smoke", "disliked"),
  ]);
  assert(
    both.words.length === 2 && both.words[1] === "'Peated' 표기가 없는 것",
    JSON.stringify(both.words),
  );
  // A wine has no such word, and still gets its guide.
  const wine = guideFor(DRY_RED, aromaSaid("berry", "disliked"));
  assert(
    wine.guide.directions.some((d) => d.change === "lower"),
    JSON.stringify(wine.guide.directions),
  );
});

Deno.test("guide: a chip is a new word, and the bottle's own only for a liked aroma nothing else carries", () => {
  // 단맛 to lower: the 'Bourbon Cask' cue is no answer to a bourbon-cask bottle.
  const sweet = guideFor(
    BOURBON_CASK_MALT,
    sweetness("disliked", "too_strong"),
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
    smoke.words.join(",") === "피트 처리 맥아(Peated)",
    JSON.stringify(smoke.words),
  );
});

Deno.test("guide: the bourbon cask cue says what its cask rows hold, and the settled whisky cues stay", () => {
  for (const kind of terms("kind")) {
    const cues = (kind.hints as { choice_cues?: { why: string }[] } | undefined)
      ?.choice_cues ?? [];
    assert(
      cues.every((cue) => !cue.why.includes("잔여 당분")),
      `${kind.key}: a cue still speaks of 잔여 당분`,
    );
  }
  const sweet = guideFor(SHERRY_MALT, sweetness("disliked", "too_strong"));
  assert(
    sweet.words[0] === "'Bourbon Cask' 표기" &&
      sweet.guide.picks[0].note?.includes("바닐라와 꿀 향"),
    JSON.stringify(sweet.guide.picks),
  );
  const heavy = guideFor(SHERRY_MALT, minded("heavy"));
  assert(
    heavy.words[0] === "'Triple distilled' 표기",
    JSON.stringify(heavy.words),
  );
  const bourbon = bottle("whisky", "bourbon", 45, {
    sweetness: 4,
    acidity: 2,
    bitterness: 2,
    body: 4,
  }, { processes: ["wooden_cask"] });
  const rye = guideFor(bourbon, sweetness("disliked", "too_strong"));
  assert(rye.words[0] === "'High Rye' 표기", JSON.stringify(rye.words));
});

Deno.test("guide: a burden no label cue answers gets a cask or method by what the dictionary says it does", () => {
  // 40% found hot: no lower 도수 to point to, so a method that softens.
  const hot = guideFor(BOURBON_CASK_MALT, minded("warmth"));
  assert(hot.mark("도수")!.range === "40~43%", hot.mark("도수")!.range);
  assert(
    hot.guide.picks[0]?.note?.startsWith("목넘김이 부드러운 쪽이에요."),
    JSON.stringify(hot.guide.picks),
  );
  // 여운이 짧았다 of a 45.8% whisky: a word of long finish, and a band up.
  const brief = guideFor(PEATED_MALT, ["finish:tooShort"]);
  assert(
    brief.guide.picks[0]?.note?.startsWith("여운이 긴 쪽이에요."),
    JSON.stringify(brief.guide.picks),
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
