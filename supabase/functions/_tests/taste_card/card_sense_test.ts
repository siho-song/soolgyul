// A card does not say two things that cannot both be so: its tags, its one
// line, its two reason sections and 다음 방향 are checked against each other.
import { regionPath } from "../../_shared/record_reading/dictionary/dictionary.ts";
import type { SensoryProduct } from "../../_shared/record_reading/record/sensory_record.ts";
import { josa } from "../../_shared/korean.ts";
import { writeCard } from "../../_shared/taste_card/writing/card_text.ts";
import { thing } from "../../_shared/taste_card/writing/reason_glass.ts";
import { actAfter } from "../../_shared/taste_card/writing/reason_taste.ts";
import { namedByPlace } from "../../_shared/taste_card/writing/reason_causes.ts";
import { assert, same as equal } from "../helpers/assert.ts";
import { recordFrom } from "../helpers/card_fixture_record.ts";

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

const RED = bottle("wine", "red_wine");
const MALT = bottle("whisky", "single_malt_whisky");
const BURGUNDY = bottle("wine", "red_wine", {
  abv: 13,
  region: regionPath("fr_bourgogne"),
  grapeVarietyKeys: ["pinot_noir"],
});
const BAROLO = bottle("wine", "red_wine", {
  abv: 14,
  region: regionPath("it_barolo"),
  grapeVarietyKeys: ["nebbiolo"],
});

const card = (keys: string[], product: SensoryProduct) =>
  writeCard(recordFrom("sense", keys, product));
const plain = (text: string) => text.replaceAll("**", "");
const textOf = (sections: { text: string }[]) =>
  plain(sections.map((s) => s.text).join("\n"));

Deno.test("card sense: what was missed is not named by a word that praises it, nor said to weigh", () => {
  const none = card(["level:sweetness:1:disliked"], RED);
  equal([none.summary, none.tags], [
    "거의 없는 단맛은 조금 아쉬웠어요.",
    [{ label: "단맛없음", kind: "burden" }],
  ]);
  const middle = card(
    ["level:body:5:liked", "level:finish_length:3:disliked"],
    RED,
  );
  equal(
    middle.summary,
    "묵직한 바디감은 잘 맞았지만, 애매한 여운은 조금 아쉬웠어요.",
  );
  assert(
    middle.tags.some((t) => t.label === "애매한여운"),
    JSON.stringify(middle.tags),
  );
  // What weighed and what was missed take their own endings.
  const both = card(
    [
      "level:acidity:4:liked",
      "level:body:5:disliked",
      "level:finish_length:1:disliked",
    ],
    RED,
  );
  equal(
    both.summary,
    "높은 산미는 잘 맞았지만, 묵직한 바디감은 조금 부담스러웠고, 짧은 여운은 조금 아쉬웠어요.",
  );
});

Deno.test("card sense: an aroma the section calls faint is missed in the one line, and nothing offers less of it", () => {
  const faint = card(
    ["level:body:4:liked", "aroma:nose:lemon:disliked"],
    BURGUNDY,
  );
  assert(
    textOf(faint.burden).includes("가볍게만 스치면서"),
    faint.burden[0].text,
  );
  assert(
    faint.summary.endsWith("옅은 레몬 향은 조금 아쉬웠어요."),
    faint.summary,
  );
  assert(
    faint.tags.some((t) => t.label === "레몬향"),
    JSON.stringify(faint.tags),
  );
  const lines = (faint.next?.lines ?? []).map((l) => plain(l.text)).join(" ");
  assert(!/레몬 향[은을] 줄일/.test(lines), lines);
});

Deno.test("card sense: a reason is not told by what the reader put on the other side", () => {
  // The sweetness that was liked is not what made the weight that was minded.
  const heavy = card(
    ["level:sweetness:5:liked", "level:body:5:disliked"],
    RED,
  );
  assert(!textOf(heavy.burden).includes("단맛"), textOf(heavy.burden));
  // Nor is the weight that was minded what made the sweetness that was liked.
  assert(!textOf(heavy.positive).includes("바디감"), textOf(heavy.positive));
  // An aroma that was minded is not what made the sweetness that was liked.
  const melon = card(
    ["level:sweetness:5:liked", "aroma:nose:melon:disliked"],
    bottle("sake", "junmai_ginjo"),
  );
  assert(!textOf(melon.positive).includes("멜론"), textOf(melon.positive));
});

Deno.test("card sense: what held in the glass is one plain clause", () => {
  const sweet = card(
    ["level:sweetness:5:liked", "level:body:5:liked"],
    RED,
  );
  const text = textOf(sweet.positive);
  assert(!/함께 있어|덕분에|탓에/.test(text), text);
  assert(/묵직한 바디감이 단맛을 돋보이게 해서,/.test(text), text);
  // A kind's own tendency is named as what it is, never as bubbles.
  equal(thing("kind:single_malt_whisky:sweetness:low")?.[1], "단맛");
  equal(thing("kind:sparkling_wine")?.[0], "탄산");
  const soft = card(["level:finish_length:1:liked"], MALT);
  assert(!textOf(soft.positive).includes("탄산"), textOf(soft.positive));
});

Deno.test("card sense: 다음 방향 offers more of what was too little, and never what the minded section spoke of", () => {
  const peat = card(
    ["level:body:4:liked", "level:peat:1:disliked"],
    MALT,
  );
  const said = (peat.next?.lines ?? []).map((l) => plain(l.text)).join(" ");
  assert(!/피트 향[은을] 줄일/.test(said), said);
  for (
    const [keys, product] of [
      [["level:tannin:5:disliked", "level:body:5:liked"], BAROLO],
      [
        ["level:acidity:4:liked", "aroma:palate:earth:disliked"],
        BURGUNDY,
      ],
      [["level:finish_length:5:liked", "level:acidity:5:disliked"], BAROLO],
    ] as [string[], SensoryProduct][]
  ) {
    const written = card(keys, product);
    const minded = textOf(written.burden);
    for (const line of written.next?.lines ?? []) {
      if (!line.text.includes("선택하시면")) continue;
      const offered = line.text.split("선택하시면")[0];
      for (const [, name] of offered.matchAll(/\*\*(.+?)\*\*/g)) {
        assert(
          !minded.includes(name),
          `${name} is offered though the minded section spoke of it: ${minded} / ${line.text}`,
        );
      }
    }
  }
});

Deno.test("card sense: a particle after a label in brackets follows the word before the bracket", () => {
  equal(josa("**새 오크통**(Virgin Oak){을}"), "**새 오크통**(Virgin Oak)을");
  equal(
    josa("**셰리 캐스크**(Sherry Cask){을}"),
    "**셰리 캐스크**(Sherry Cask)를",
  );
  equal(josa("프룬(건자두) 향{이}"), "프룬(건자두) 향이");
});

Deno.test("card sense: a section's subtitle lists its answers in two words each", () => {
  const liked = card(["level:tannin:2:liked", "aroma:nose:cherry:liked"], RED);
  // In the order of the lines under it.
  equal(liked.positive.map((p) => p.answer), ["체리 향, 낮은 타닌"]);
  const minded = card(
    ["level:body:5:disliked", "level:finish_length:3:disliked"],
    RED,
  );
  equal(minded.burden.map((p) => p.answer), ["묵직한 바디감, 애매한 여운"]);
});

Deno.test("card sense: the subtitle alone calls the first two steps by one name; a tag and a sentence tell them apart", () => {
  const SPARKLING = bottle("wine", "sparkling_wine");
  const TAKJU = bottle("korean_traditional", "takju");
  const named = (key: string, product: SensoryProduct) => {
    const c = card([key], product);
    const section = key.endsWith(":liked") ? c.positive : c.burden;
    return [section[0]?.answer, c.tags[0]?.label, c.summary];
  };
  equal(named("level:sweetness:1:liked", RED), [
    "옅은 단맛",
    "단맛없음",
    "단맛 없는 깔끔함이 기분 좋게 잘 맞았어요.",
  ]);
  equal(named("level:sweetness:2:liked", RED), [
    "옅은 단맛",
    "적은단맛",
    "적은 단맛이 기분 좋게 잘 맞았어요.",
  ]);
  equal(named("level:sweetness:1:disliked", RED), [
    "옅은 단맛",
    "단맛없음",
    "거의 없는 단맛은 조금 아쉬웠어요.",
  ]);
  for (const step of [1, 2]) {
    equal(named(`level:tannin:${step}:liked`, RED)[0], "낮은 타닌");
    equal(named(`level:spice:${step}:liked`, MALT)[0], "약한 알싸함");
    // 젠틀 is a little of it: a sparkling wine has bubbles.
    equal(named(`level:sparkling:${step}:liked`, SPARKLING)[0], "약한 탄산");
    equal(
      named(`level:finish_character:${step}:disliked`, RED)[0],
      "옅은 끝맛",
    );
  }
  // 무탄산 and 논피트 say there is none.
  equal(named("level:sparkling:1:liked", TAKJU)[0], "탄산 없음");
  equal(named("level:sparkling:1:disliked", TAKJU)[0], "탄산 없음");
  equal(named("level:sparkling:2:liked", TAKJU)[0], "약한 탄산");
  equal(named("level:peat:1:liked", MALT)[0], "피트 향 없음");
  equal(named("level:peat:2:liked", MALT)[0], "옅은 피트 향");
  // The sentence under the subtitle says what was answered.
  const dry = card(["level:sweetness:1:liked"], BURGUNDY);
  assert(
    plain(dry.positive[0].text).includes("단맛이 거의 없는 건"),
    dry.positive[0].text,
  );
});

Deno.test("card sense: the wording the review returned (2026-11-24)", () => {
  // A strength is high for its kind, in two words.
  equal(thing("abv:14.5")?.[0], "비교적 높은 14.5% 도수");
  // 온기 alone at the head of a sentence reads cut off.
  equal(
    actAfter("", "도수에서 나와서", "그 온기가 향과 맛을 실어 줘요", []),
    "따뜻한 온기가 향과 맛을 실어 줘요",
  );
  // 깔끔 is not said twice in the one line.
  const clean = card(
    ["level:sweetness:1:liked", "level:finish_character:1:liked"],
    RED,
  );
  assert(
    clean.summary.includes("단맛 없는 담백함") &&
      clean.summary.includes("깔끔한 끝맛"),
    clean.summary,
  );
  equal(
    card(["level:sweetness:1:liked"], RED).summary,
    "단맛 없는 깔끔함이 기분 좋게 잘 맞았어요.",
  );
});

Deno.test("card sense: what the full audit found (2026-11-24)", () => {
  // A middle step alone is nothing a choice brings along: no line with an empty name.
  for (const key of ["level:acidity:3:liked", "level:body:3:liked"]) {
    for (const product of [BURGUNDY, BAROLO, MALT]) {
      const lines = (card([key], product).next?.lines ?? []).map((l) => l.text);
      for (const line of lines) {
        assert(!/좋았던 [을를]|(^|[ ,])[을를은는](?=[ ,.])/.test(line), line);
      }
    }
  }
  // A low tannin the reader minded is not thanked for the aroma they liked.
  const thanked = card(
    ["level:tannin:1:disliked", "aroma:nose:pomegranate:liked"],
    RED,
  );
  assert(
    !textOf(thanked.positive).includes("타닌이 낮은 덕분에"),
    textOf(thanked.positive),
  );
  // A style named by its place is that place's wine as a drink, not the place.
  const style = (key: string, ko: string) =>
    ({ factor: "region_style", key, ko }) as Parameters<typeof namedByPlace>[0];
  equal(namedByPlace(style("southern_france_red", "남프랑스")), true);
  equal(namedByPlace(style("bordeaux_left_bank_red", "보르도 좌안")), true);
});
