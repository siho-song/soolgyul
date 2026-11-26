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

Deno.test("card sense: the wording the second review returned (2026-11-24)", () => {
  // … 가볍게 넘어가, … 술술 넘어가요 says 넘어가 twice.
  equal(
    actAfter(
      "",
      "가볍게 넘어가서",
      "입안에 머무는 느낌 없이 술술 넘어가요",
      [],
    ),
    "입안에 머무는 느낌 없이 목넘김이 매끄러워요",
  );
  equal(
    actAfter(
      "",
      "질감이 가벼워서",
      "입안에 머무는 느낌 없이 술술 넘어가요",
      [],
    ),
    "입안에 머무는 느낌 없이 술술 넘어가요",
  );
});

Deno.test("card sense: an aroma is said to come only from where the dictionary says it does (2026-11-25)", () => {
  const liked = (aroma: string, product: SensoryProduct) =>
    textOf(card([`aroma:nose:${aroma}:liked`], product).positive);
  // An age band lists what shows more at that age, not where it comes from.
  const twelve = bottle("whisky", "single_malt_whisky", {
    name: "시험 12년",
    ageStatementYears: 12,
  });
  equal(
    liked("apple", twelve),
    "• 사과 향이 가볍고 상쾌하게 퍼지면서, 술이 한결 산뜻하게 느껴져요.",
  );
  // 곡물 on a row is not the 쌀 a reader picked; it is the 곡물 one picked.
  const blend = bottle("whisky", "blended_whisky");
  assert(!liked("rice", blend).includes("향은"), liked("rice", blend));
  assert(
    liked("cereal", blend).includes(
      "블렌디드 위스키의 주원료인 곡물에서 우러나는 향",
    ),
    liked("cereal", blend),
  );
  // A grape has no soil of its own.
  const riesling = bottle("wine", "white_wine", {
    abv: 12,
    grapeVarietyKeys: ["riesling"],
  });
  assert(
    !liked("mineral", riesling).includes("토양"),
    liked("mineral", riesling),
  );
});

Deno.test("card sense: an aroma's origin is said in the row's own words where the row has them (2026-11-26)", () => {
  const liked = (aroma: string, product: SensoryProduct) =>
    textOf(card([`aroma:nose:${aroma}:liked`], product).positive);
  const chablis = bottle("wine", "white_wine", {
    abv: 12.5,
    region: regionPath("fr_chablis"),
    grapeVarietyKeys: ["chardonnay"],
  });
  const burgundy = bottle("wine", "white_wine", {
    abv: 13,
    region: regionPath("fr_bourgogne"),
    grapeVarietyKeys: ["chardonnay"],
  });
  const barossa = bottle("wine", "red_wine", {
    abv: 14.5,
    region: regionPath("au_barossa_valley"),
    grapeVarietyKeys: ["syrah"],
  });
  const said = (aroma: string, product: SensoryProduct, from: string) =>
    assert(
      liked(aroma, product).startsWith(`• ${from} 향이에요.`),
      liked(aroma, product),
    );
  // A cask is said as what it is.
  said(
    "raisin",
    { ...MALT, processes: ["ex_sherry_cask"] },
    "건포도 향은 셰리 와인을 담아 두었던 오크통에서 숙성하는 동안 밴",
  );
  // A house, by the casks it mostly ages in.
  said(
    "chocolate",
    { ...MALT, producer: "글렌알라키" },
    "초콜릿 향은 글렌알라키 증류소가 숙성에 주로 쓰는 셰리 캐스크에서 우러난",
  );
  // A grape, by the step its row names.
  said(
    "butter",
    chablis,
    "버터 향은 샤르도네 와인이 유산균 발효를 거치면서 우유나 버터처럼 고소해진",
  );
  // No trade word a drinker would have to look up (the user's word,
  // 2026-11-26: 귀부균 is not said).
  said(
    "honey",
    bottle("wine", "white_wine", { abv: 13.5, processes: ["noble_rot"] }),
    "꿀 향은 껍질에 핀 이로운 곰팡이가 포도 물기를 날려 단맛과 향이 짙어지면서 생기는",
  );
  // A grape's fruit, by the climate its row names the aroma in: a cool place
  // says so, a moderate one does not, and an aroma the row names in both
  // climates (시라's 블랙베리) is not said to come from either.
  said(
    "lemon",
    chablis,
    "레몬 향은 서늘한 곳에서 자란 샤르도네 품종에서 자주 나타나는",
  );
  said("lemon", burgundy, "레몬 향은 샤르도네 품종에서 자주 나타나는");
  said(
    "blackberry",
    barossa,
    "블랙베리 향은 시라·쉬라즈 품종에서 자주 나타나는",
  );
  // The phrase stands before 향이에요, so it does not end on a 향 of its
  // own (효모가 과일 향을 만들어 내는 향이에요 read twice over).
  said(
    "melon",
    bottle("sake", "junmai_ginjo"),
    "멜론 향은 준마이 긴조가 쌀을 깎아 내고 낮은 온도에서 천천히 발효할 때 효모가 만들어 내는",
  );
  // The row's own words are said even where they name the aroma again, for
  // they explain it (the user's word, 2026-11-26); a short form that only
  // says the thing twice (오크통에서 우러난 오크 향) is not.
  said(
    "peat",
    { ...MALT, processes: ["peated_malt"] },
    "피트 향은 싹 틔운 보리를 말릴 때 피트를 태운 연기를 쐬어서 생기는",
  );
  said(
    "oak",
    { ...MALT, processes: ["new_oak_cask"] },
    "오크 향은 한 번도 술을 담지 않은 새 오크통에서 숙성하며 나무 속 성분이 진하게 우러난",
  );
  equal(
    liked("oak", BAROLO),
    "• 오크 향이 은은하게 올라와 머물면서, 술이 차분하고 안정감 있게 느껴져요.",
  );
  // What a drink is made of and how is said of the aroma of that name too.
  said(
    "fermentation",
    bottle("korean_traditional", "takju"),
    "발효 향은 탁주를 빚을 때 쓰는 누룩의 발효 과정에서 생기는",
  );
});

Deno.test("card sense: a row tells each aroma by its own reason, or tells nothing of it (the returned review, 2026-11-27)", () => {
  const liked = (aroma: string, product: SensoryProduct) =>
    textOf(card([`aroma:nose:${aroma}:liked`], product).positive);
  const said = (aroma: string, product: SensoryProduct, from: string) =>
    assert(
      liked(aroma, product).startsWith(`• ${from} 향이에요.`),
      liked(aroma, product),
    );
  const untold = (aroma: string, product: SensoryProduct) =>
    assert(!liked(aroma, product).includes("향이에요"), liked(aroma, product));
  // One origin, two reasons: the charred oak's sweetness does not explain
  // its spice.
  const bourbon = bottle("whisky", "bourbon");
  said(
    "vanilla",
    bourbon,
    "바닐라 향은 버번 위스키가 안쪽을 불에 구운 새 오크통에서 달콤하게 그을린 나무 내음이 밴",
  );
  said(
    "cinnamon",
    bourbon,
    "계피 향은 버번 위스키가 안쪽을 불에 구운 새 오크통에서 계피나 정향처럼 알싸한 내음이 밴",
  );
  // The reason is the picked aroma's where the row has one for it: peat
  // smoke tells 라가불린's 요오드 and nothing of a 미네랄; a sweetness that
  // thickened tells nothing of a 시트러스 said to be light and fresh.
  const lagavulin = { ...MALT, producer: "라가불린" };
  said(
    "peat",
    lagavulin,
    "피트 향은 라가불린 증류소의 위스키가 피트를 태운 연기로 말린 보리를 써서 생기는",
  );
  untold("mineral", lagavulin);
  const beerenauslese = bottle("wine", "white_wine", {
    name: "시험 Beerenauslese",
  });
  said(
    "spice",
    beerenauslese,
    "향신료 향은 포도 껍질에 핀 이로운 곰팡이가 수분을 빼앗아 껍질 속 알싸한 기운까지 진해진",
  );
  untold("citrus", beerenauslese);
  // 포도로 빚은 향 would have the aroma brewed: the wine is, the aroma comes of it.
  said(
    "ginger",
    bottle("wine", "white_wine", { name: "시험 Auslese" }),
    "생강 향은 나무에서 오래 익어 포도 껍질의 알싸한 기운이 진해진 포도로 빚어서 생기는",
  );
  // Words with a subject of their own stand around the name, not after 와인이.
  said(
    "peach",
    bottle("wine", "white_wine", { region: regionPath("fr_sauternes") }),
    "복숭아 향은 껍질에 핀 이로운 곰팡이가 수분을 빼앗아 단맛과 향이 잼처럼 짙어진 포도로 빚은 소테른 화이트 와인의",
  );
  said(
    "honey",
    { ...MALT, producer: "글렌 기어리" },
    "꿀 향은 글렌 기어리 증류소의 위스키에 버번 통의 달큰한 바닐라 내음과 셰리 통의 과일 내음이 함께 밴",
  );
  said(
    "citrus",
    bottle("wine", "madeira_wine"),
    "시트러스 향은 마데이라 와인을 산미가 높은 포도로 빚어 따뜻하게 숙성한 뒤에도 상큼함이 살아 있는",
  );
  // 쌀 향은 준마이의 주원료에서 우러나는 says the rice without naming it.
  const junmai = bottle("sake", "junmai");
  untold("rice", junmai);
  said("cereal", junmai, "곡물 향은 준마이의 주원료에서 우러나는");
  // A label word is said without its quotes; a spirit's house distils.
  said(
    "wood",
    bottle("sake", "junmai", { name: "시험 樽酒" }),
    "나무 향은 타루자케에서 오는",
  );
  said(
    "honey",
    bottle("wine", "white_wine", { name: "시험 moelleux" }),
    "꿀 향은 무알뢰 방식으로 빚은 와인에서 자주 나타나는",
  );
  said(
    "malt",
    { ...MALT, producer: "아마하간" },
    "맥아 향은 아마하간의 원료와 발효·증류 과정에서 비롯된",
  );
});
