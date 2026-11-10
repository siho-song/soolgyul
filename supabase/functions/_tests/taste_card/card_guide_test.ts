import { writeGuide } from "../../_shared/taste_card/summary/guide.ts";
import { buildCardFacts } from "../../_shared/taste_card/findings/conclusions.ts";
import { fixtures, recordFrom } from "../helpers/card_fixture_record.ts";
import type { CardFacts } from "../../_shared/taste_card/facts/facts.ts";

function assert(cond: unknown, message: string): asserts cond {
  if (!cond) throw new Error(message);
}

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

Deno.test("guide: traditional cards get the shops' marks, label chips only from their own kind", async () => {
  for (const [name, facts] of await fixtures()) {
    if (facts.record.category !== "korean_traditional") continue;
    const guide = writeGuide(facts)!;
    // 해창 12도 finds its 도수 cue; the liked-only cards keep their directions instead.
    assert(
      guide.picks.length > 0 || guide.directions.length > 0,
      `${name}: nothing to look for`,
    );
    assert(
      guide.picks.every((p) =>
        !/과실주|약주|청주|탁주/.test(p.keyword) && p.keyword.includes("'") &&
        p.note === null
      ),
      `${name}: not a bare label word: ${JSON.stringify(guide.picks)}`,
    );
    assert(
      guide.levels.map((l) => l.label).join(",") === "단맛,산미,탄산,바디,도수",
      `${name}: ${guide.levels.map((l) => l.label)}`,
    );
    assert(
      guide.levels.at(-1)!.range.endsWith("%"),
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
  assert(ardbeg.levels[0].range === "47% 이상", ardbeg.levels[0].range);
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
