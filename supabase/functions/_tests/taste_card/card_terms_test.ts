import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  levelTerm,
  pickTerm,
  tagTerm,
  textTerms,
  withCardTerms,
  wordTerm,
} from "../../_shared/taste_card/writing/terms.ts";
import { glossaryTerm } from "../../_shared/glossary/glossary.ts";
import { terms } from "../../_shared/taste_card/dictionary/dictionary.ts";
import type { TasteCardView } from "../../_shared/taste_card/service/types.ts";
import chipWords from "../fixtures/guide_chip_words.json" with { type: "json" };

/** A word's term as the balloon heads it: 품종: 메를로. */
const opened = (word: string) => {
  const term = wordTerm(word);
  return term && `${term.kind}: ${term.label}`;
};

Deno.test("bold sensation words carry the dictionary's explanation, verdict words do not", () => {
  const text =
    "이 와인은 향이 짙어서 **체리 향**이 또렷하게 피어올라요. 단맛이 거의 없어서 **산미** 특유의 산뜻함이 드러나요. " +
    "**떫은 조임**이 혀를 붙들어요. 이 특징이 **기분 좋은 매력**으로 다가온 것 같아요.";
  const terms = textTerms(text);
  assertEquals(terms.map((t) => [t.word, t.label, t.kind]), [
    ["체리 향", "체리", "향"],
    ["산미", "산미", "맛"],
    ["떫은 조임", "떫음", "질감"],
  ]);
  assert(terms.every((t) => t.description.length > 20));
});

Deno.test("a word set in bold twice is explained once; a text without marks has none", () => {
  assertEquals(
    textTerms("**단맛**과 **산미**, 그리고 다시 **단맛**.").map((t) => t.word),
    ["단맛", "산미"],
  );
  assertEquals(textTerms("아무 표시가 없는 글이에요."), []);
});

Deno.test("tags are looked up without their spaces; an unknown tag has no term", () => {
  assertEquals(tagTerm("체리향")?.label, "체리");
  assertEquals(tagTerm("떫은맛")?.label, "떫음");
  assertEquals(tagTerm("긴여운")?.kind, "여운");
  assertEquals(tagTerm("산미")?.kind, "맛");
  assertEquals(tagTerm("기분좋은매력"), null);
});

Deno.test("withCardTerms explains every section and tag and changes nothing else", () => {
  const view = {
    product: {
      drink_name_snapshot: "테스트",
      user_name: null,
      image_reference: null,
      category_label: "와인",
    },
    bite: {
      nickname: "별명",
      tags: [
        { label: "체리향", kind: "liked" },
        { label: "알코올열감", kind: "burden" },
      ],
      summary: "요약",
      guide: null,
    },
    positive: [{ answer: "답", text: "**체리 향**이 좋았어요." }],
    burden: [{ answer: "답", text: "**부담**이었어요." }],
    balanced: [],
    metadata: {
      snapshot_ref: "s",
      schema_version: 3,
      engine_version: "e",
      generated_at: "2026-11-07T00:00:00.000Z",
      generated_from_record_ref: "r",
    },
  } as unknown as TasteCardView;
  const served = withCardTerms(view);
  assertEquals(served.bite.tags[0].term?.label, "체리");
  assertEquals(served.bite.tags[1].term, null);
  assertEquals(served.positive[0].terms?.map((t) => t.word), ["체리 향"]);
  assertEquals(served.burden[0].terms, []);
  assertEquals(served.balanced, []);
  assertEquals(served.product, view.product);
  assertEquals(served.metadata, view.metadata);
  // The stored view is untouched.
  assertEquals("terms" in view.positive[0], false);
});

Deno.test("pickTerm still explains a cask or method by its Korean name, and nothing else", () => {
  const sherry = pickTerm("셰리 캐스크(Sherry Cask)");
  assertEquals(sherry?.word, "셰리 캐스크(Sherry Cask)");
  assertEquals(sherry?.label, "셰리 캐스크");
  assertEquals(sherry?.kind, "제조·숙성");
  assert(sherry!.description.startsWith("셰리 와인을 담아 두었던 오크통"));
  assertEquals(pickTerm("상압 증류")?.label, "상압 증류");
  assertEquals(pickTerm("바르베라"), null);
  assertEquals(pickTerm("'Sherry Cask' 표기"), null);
});

Deno.test("a card stored before chips carried words is explained by its keyword", () => {
  const pick = (keyword: string) => ({
    country: null,
    place: null,
    keyword,
    note: null,
  });
  const view = {
    bite: {
      tags: [],
      guide: {
        head: "머리",
        picks: [
          pick("버번 캐스크(Bourbon Cask)"),
          pick("메를로"),
          pick("긴조 · 준마이"),
        ],
        tip: null,
        levels: [],
        directions: [],
      },
    },
    positive: [],
    burden: [],
    balanced: [],
  } as unknown as TasteCardView;
  const served = withCardTerms(view);
  const picks = served.bite.guide!.picks;
  assertEquals(picks[0].term?.label, "버번 캐스크");
  assertEquals(picks[0].term?.word, "버번 캐스크(Bourbon Cask)");
  assertEquals([picks[1].term?.kind, picks[1].term?.label], ["품종", "메를로"]);
  // Two grades in one chip have no single term.
  assertEquals(picks[2].term, null);
  assertEquals(picks.some((p) => "words" in p), false);
  assertEquals(served.bite.guide?.head, "머리");
  assertEquals("term" in view.bite.guide!.picks[0], false);
});

Deno.test("every chip word that had no help opens a dictionary term", () => {
  const words = Object.entries(chipWords as Record<string, string>);
  assertEquals(words.length, 126);
  for (const [word, name] of words) {
    assertEquals(opened(word), name, word);
    assert(wordTerm(word)!.description.trim().length > 10, word);
    // The chip may quote the word or say 표기 after it.
    assertEquals(opened(`'${word}' 표기`), name, word);
  }
});

Deno.test("a chip word is found however the chip writes it", () => {
  for (
    const text of [
      "Merlot(메를로)",
      "메를로",
      "merlot",
      "MERLOT",
      "메를로(Merlot)",
    ]
  ) assertEquals(opened(text), "품종: 메를로", text);
  for (
    const text of [
      "Sherry Cask(셰리 캐스크)",
      "셰리 캐스크(Sherry Cask)",
      "'Sherry Cask'",
      "sherry cask",
      "셰리캐스크",
    ]
  ) assertEquals(opened(text), "제조·숙성: 셰리 캐스크", text);
  assertEquals(opened("'Bourbon Cask'"), "제조·숙성: 버번 캐스크");
  assertEquals(opened("Triple Distilled"), "제조·숙성: 3회 증류");
  assertEquals(opened("triple distilled"), "제조·숙성: 3회 증류");
  assertEquals(opened("Non-chill filtered"), "제조·숙성: 비냉각여과");
  assertEquals(opened("생막걸리"), "제조·숙성: 비살균");
  assertEquals(opened("갓 나온 '생막걸리'"), "제조·숙성: 비살균");
  assertEquals(opened("원재료명 '찹쌀' 표기"), "원재료: 찹쌀");
  // The label spelling with or without its accents, and each of two names.
  assertEquals(
    opened("Gewürztraminer(게뷔르츠트라미너)"),
    "품종: 게뷔르츠트라미너",
  );
  assertEquals(opened("gewurztraminer"), "품종: 게뷔르츠트라미너");
  assertEquals(opened("Syrah·Shiraz(시라·쉬라즈)"), "품종: 시라·쉬라즈");
  assertEquals(opened("Shiraz(쉬라즈)"), "품종: 시라·쉬라즈");
  assertEquals(
    opened("Crémant d'Alsace(크레망 달자스)"),
    "산지 스타일: 크레망 달자스",
  );
  assertEquals(opened("純米大吟醸(준마이 다이긴조)"), "종류: 준마이 다이긴조");
  assertEquals(opened("本醸造"), "종류: 혼조조");
  assertEquals(opened("生酒(나마자케)"), "제조·숙성: 비살균");
  assertEquals(opened("Pedro Ximenez"), "산지 스타일: 페드로 히메네스 셰리");
  assertEquals(opened("PX"), "산지 스타일: 페드로 히메네스 셰리");
  assertEquals(wordTerm("Merlot(메를로)")?.word, "Merlot(메를로)");
  assertEquals(opened("알 수 없는 말"), null);
  assertEquals(opened(""), null);
});

Deno.test("each word of a two-word chip opens its own term", () => {
  assertEquals(
    ["dry", "trocken"].map(opened),
    ["라벨 표기: 드라이", "라벨 표기: 트로켄"],
  );
  assertEquals(
    ["Fino(피노)", "Manzanilla(만사니야)"].map(opened),
    ["산지 스타일: 피노 셰리", "산지 스타일: 만사니야"],
  );
  assert(
    wordTerm("dry")!.description !== wordTerm("trocken")!.description,
  );
  // A number on a label is explained once, whatever the number.
  assertEquals(opened("15 Years"), "라벨 표기: 숙성 연수");
  assertEquals(
    wordTerm("15 Years")!.description,
    wordTerm("18 Years(18년)")!.description,
  );
  assertEquals(opened("쿄카이 9호"), "라벨 표기: 쿄카이 효모");
});

Deno.test("a word two rows answer to opens the one it names", () => {
  // The traditional 원주 is not the sake term that lists it as another name.
  assertEquals(opened("원주"), "라벨 표기: 원주");
  assert(!wordTerm("원주")!.description.includes("17~20도"));
  assertEquals(opened("겐슈"), "제조·숙성: 겐슈");
  assertEquals(opened("原酒(겐슈)"), "제조·숙성: 겐슈");
  // Cream on a sherry is the sherry, not the aroma.
  assertEquals(opened("Cream"), "산지 스타일: 크림 셰리");
  // A word a kind's bottles may also print does not name the kind.
  assertEquals(opened("demi-sec"), null);
  assertEquals(opened("Chablis"), "산지: 샤블리");
  // A place is the wine named after it before it is the place.
  assertEquals(opened("샴페인"), "산지 스타일: 샴페인");
  assertEquals(opened("Tavel"), "산지: 따벨");
});

Deno.test("a chip word's term carries its key only when 나의 용어 사전 files it", () => {
  const words = [
    ...Object.keys(chipWords),
    ...terms(
      "grape",
      "kind",
      "regional_style",
      "process",
      "maturation",
      "ingredient",
      "label_word",
    ).map((t) => t.names.ko),
  ];
  const found = words.flatMap((word) => wordTerm(word) ?? []);
  assert(found.length > 250);
  for (const term of found) {
    if (term.key === undefined) continue;
    const saved = glossaryTerm(term.key);
    assertEquals(
      [saved?.label, saved?.kind, saved?.description],
      [term.label, term.kind, term.description],
      term.word,
    );
  }
  assertEquals(wordTerm("메를로")?.key, "grape:merlot");
  assertEquals(wordTerm("Peated")?.key, "process:peated_malt");
  assertEquals(wordTerm("Tavel")?.key, "region:fr_tavel");
  // 나의 용어 사전 files no kind, style, ingredient or label word yet.
  for (const word of ["준마이", "프로세코", "찹쌀", "Fino"]) {
    assertEquals("key" in wordTerm(word)!, false, word);
  }
});

Deno.test("a gauge name opens the axis it marks; 도수 has none", () => {
  const named = (label: string) => {
    const term = levelTerm(label);
    return term && [term.key, term.kind, term.word];
  };
  assertEquals(named("당도"), ["axis:sweetness", "맛", "당도"]);
  assertEquals(named("단맛"), ["axis:sweetness", "맛", "단맛"]);
  assertEquals(named("산도"), ["axis:acidity", "맛", "산도"]);
  assertEquals(named("산미"), ["axis:acidity", "맛", "산미"]);
  assertEquals(named("타닌"), ["axis:astringency", "질감", "타닌"]);
  assertEquals(named("바디"), ["axis:body", "질감", "바디"]);
  assertEquals(named("탄산"), ["axis:carbonation", "질감", "탄산"]);
  assertEquals(named("당도(주도)")?.[0], "axis:sweetness");
  assertEquals(named("산미(산도)")?.[0], "axis:acidity");
  assertEquals(named("도수"), null);
  for (const label of ["당도", "산도", "타닌", "바디", "탄산"]) {
    const term = levelTerm(label)!;
    assert(term.description.length > 20, label);
    assertEquals(glossaryTerm(term.key!)?.kind, term.kind, label);
  }
});

Deno.test("withCardTerms explains every word of a chip and every gauge, and leaves the stored guide as it was", () => {
  const view = {
    bite: {
      tags: [],
      guide: {
        head: "머리",
        picks: [
          {
            country: "FR",
            place: "프랑스 보르도",
            keyword: "Merlot(메를로)",
            words: [{ text: "Merlot(메를로)" }],
            note: null,
          },
          {
            country: null,
            place: null,
            keyword: "dry · trocken",
            words: [{ text: "dry(드라이)" }, { text: "trocken(트로켄)" }],
            note: "단맛이 거의 없어요.",
          },
          {
            country: null,
            place: null,
            keyword: "도수 40~43%",
            words: [{ text: "도수 40~43%" }],
            note: null,
          },
        ],
        tip: null,
        levels: [
          { label: "당도", mark: 2, range: "1~2" },
          { label: "도수", mark: 3, range: "40~46%" },
        ],
        directions: [],
      },
    },
    positive: [],
    burden: [],
    balanced: [],
  } as unknown as TasteCardView;
  const guide = withCardTerms(view).bite.guide!;
  const [merlot, dry, abv] = guide.picks;
  assertEquals(merlot.words?.map((w) => w.term?.label), ["메를로"]);
  assertEquals(merlot.term, merlot.words![0].term);
  assertEquals(merlot.term?.word, "Merlot(메를로)");
  assertEquals(merlot.place, "프랑스 보르도");
  assertEquals(dry.words?.map((w) => [w.text, w.term?.label]), [
    ["dry(드라이)", "드라이"],
    ["trocken(트로켄)", "트로켄"],
  ]);
  // The chip's own term is its first word's, for an app that reads one.
  assertEquals(dry.term?.label, "드라이");
  assertEquals(dry.note, "단맛이 거의 없어요.");
  assertEquals(abv.words, [{ text: "도수 40~43%", term: null }]);
  assertEquals(abv.term, null);
  assertEquals(guide.levels.map((l) => l.term?.key ?? null), [
    "axis:sweetness",
    null,
  ]);
  assertEquals(guide.levels[0].mark, 2);
  // The stored view is untouched.
  const stored = view.bite.guide!;
  assertEquals("term" in stored.picks[0], false);
  assertEquals("term" in stored.picks[1].words![0], false);
  assertEquals("term" in stored.levels[0], false);
});
