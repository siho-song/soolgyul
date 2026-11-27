// 나의 취향 조각 네 글자: the marks a record puts on each ruler, the place
// they average to, and when a letter shows or turns.
import {
  type LetterAxis,
  type LetterMarks,
  type LetterRecord,
  lettersFromMarks,
} from "../../_shared/taste_letters/letters_from_marks.ts";
import type { SensoryProduct } from "../../_shared/record_reading/record/sensory_record.ts";
import {
  convertAnonymousTasteCard,
  createTasteCardResult,
  deleteOwnedTasteCardRecord,
} from "../../_shared/taste_card/service/orchestrator.ts";
import { TasteCardRepositoryError } from "../../_shared/taste_card/service/errors.ts";
import { recordFrom } from "../helpers/card_fixture_record.ts";
import {
  marksOf,
  MemoryTasteCardRepository,
  tasteCardRequest,
  testDependencies,
} from "../helpers/taste_card_service.ts";

function same(actual: unknown, expected: unknown, message = "equality") {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${message}: ${a} != ${b}`);
}

/* ------------------------------------------- the letters from marks alone */

Deno.test("letters: the four letters come from the marks alone, whatever was asked or drunk", () => {
  const record = (id: string, marks: Partial<LetterMarks>): LetterRecord => ({
    record_id: id,
    product_name: "병",
    recorded_at: `2026-01-0${id.slice(1)}T00:00:00.000Z`,
    marks: { aroma: [], sweetness: [], weight: [], finish: [], ...marks },
  });
  const { state, changes } = lettersFromMarks([
    record("r1", { sweetness: [{ place: 5, weight: 1, from: "answer" }] }),
    record("r2", {
      sweetness: [{ place: 4, weight: 0.3, from: "neighbour" }],
      weight: [{ place: 1, weight: 0.3, from: "neighbour" }],
    }),
  ]);
  // Started from the middle as two records, the older record a tenth lighter:
  // (2×3 + 0.9×5 + 0.3×4) / (2 + 0.9 + 0.3) = 3.66, two thirds of the way.
  same(state.axes.sweetness, {
    letter: "S",
    left_share: 34,
    right_share: 66,
    vote_count: 2,
  });
  // A mark from beside the ruler leans it and never shows a letter.
  same(state.axes.weight, {
    letter: null,
    left_share: 0,
    right_share: 0,
    vote_count: 1,
  });
  same(changes.map((c) => `${c.record_id}:${c.axis}:${c.to_letter}`), [
    "r1:sweetness:S",
  ]);
  same(state.record_count, 2);
});

/* ------------------------------------------------------- made-up records */

/** One record: the bottle's kind and read levels, and what was answered. */
type Said = {
  kind?: SensoryProduct["category"];
  sweet?: 1 | 2 | 3 | 4 | 5;
  body?: 1 | 2 | 3 | 4 | 5;
  revisit?: "wantAgain" | "wouldAcceptAgain" | "doNotWantAgain";
  answers: string[];
};
const card = (said: Said): Said => said;

// A step names its side: 4–5 the high one, 1–2 the low one, 3 neither.
const sweetLiked = "level:sweetness:3:liked";
const sweetEnough = "level:sweetness:4:liked";
const sweetGentle = "level:sweetness:2:liked";
const tooSweet = "level:sweetness:4:disliked";
const notSweet = "level:sweetness:2:disliked";
const heavyLiked = "level:body:4:liked";
const lightLiked = "level:body:2:liked";
const tooHeavy = "level:body:4:disliked";
const heatMinded = "level:spice:4:disliked";
const heatLiked = "level:spice:4:liked";
const lingered = "level:finish_length:4:liked";
const cleared = "level:finish_length:2:liked";
const aroma = (key: string, reaction: "liked" | "burden" = "liked") =>
  `aroma:nose:${key}:${reaction === "liked" ? "liked" : "disliked"}`;
const times = <T>(count: number, value: T): T[] =>
  Array.from({ length: count }, () => value);

function records(cards: readonly Said[]): LetterRecord[] {
  return cards.map((said, index) => {
    const levels = {
      ...(said.sweet ? { sweetness: said.sweet } : {}),
      ...(said.body ? { body: said.body } : {}),
    };
    const record = recordFrom(
      `r${index}`,
      [...said.answers, `revisit:${said.revisit ?? "wouldAcceptAgain"}`],
      bottle(said.kind ?? "whisky", null, levels),
    );
    return {
      record_id: `r${String(index + 1).padStart(2, "0")}`,
      product_name: `병 ${index + 1}`,
      recorded_at: new Date(Date.UTC(2026, 0, 1 + index)).toISOString(),
      marks: marksOf(record),
    };
  });
}

const GLYPHS: Record<string, string> = {
  F: "산",
  R: "풍",
  D: "드",
  S: "달",
  L: "가",
  H: "묵",
  C: "깔",
  P: "길",
};

/** What the screen shows for the axis: "달 66%", or "?" while it is closed. */
function shown(cards: readonly Said[], axis: LetterAxis): string {
  const state = lettersFromMarks(records(cards)).state.axes[axis];
  if (state.letter === null) return "?";
  const own = Math.max(state.left_share, state.right_share);
  return `${GLYPHS[state.letter]} ${own}%`;
}

const round = (value: number) => Math.round(value * 100) / 100;

/** A bottle whose levels were read for it. */
function bottle(
  category: SensoryProduct["category"],
  styleKey: string | null,
  levels: SensoryProduct["levels"] = {},
): SensoryProduct {
  return {
    name: "병",
    category,
    styleKey,
    region: null,
    abv: null,
    levels,
    levelSources: Object.fromEntries(
      Object.keys(levels).map((dimension) => [dimension, 2]),
    ),
    levelRefs: {},
    descriptors: [],
  };
}
const malt = (levels: SensoryProduct["levels"] = {}) =>
  bottle("whisky", "single_malt_whisky", levels);

/* ------------------------------------------------- the agreed situations */

// Agreed with the product owner on 2026-11-12: what each kind of record
// should show. 단맛 n is the bottle's catalog level.
const SITUATIONS: readonly [LetterAxis, string, Said[], string][] = [
  // The same 좋았어요 reads by how sweet the bottle is, and by its kind.
  ["sweetness", "아주 단 술(5)이 좋았다", [
    card({ sweet: 5, answers: [sweetLiked] }),
  ], "달 66%"],
  ["sweetness", "아주 단 술이 좋았고 다시 마시고 싶다", [
    card({ sweet: 5, revisit: "wantAgain", answers: [sweetLiked] }),
  ], "달 69%"],
  ["sweetness", "단맛 4 위스키가 충분히 달아서 좋았다", [
    card({ sweet: 4, answers: [sweetEnough] }),
  ], "달 59%"],
  ["sweetness", "단맛 4 와인이 좋았다 (와인 중 상위 5%)", [
    card({ kind: "wine", sweet: 4, answers: [sweetLiked] }),
  ], "달 62%"],
  ["sweetness", "보통 단맛(3) 사케가 좋았다", [
    card({ kind: "sake", sweet: 3, answers: [sweetLiked] }),
  ], "달 51%"],
  ["sweetness", "드라이 와인(1)이 좋았다", [
    card({ kind: "wine", sweet: 1, answers: [sweetLiked] }),
  ], "드 59%"],
  ["sweetness", "드라이 와인이 은은해서 좋았다", [
    card({ kind: "wine", sweet: 1, answers: [sweetGentle] }),
  ], "드 59%"],
  // A complaint reads by the bottle too: the sweetest bottle being too sweet
  // says little, an ordinary one being too sweet says much.
  ["sweetness", "아주 단 술(5)이 너무 달았다", [
    card({ sweet: 5, answers: [tooSweet] }),
  ], "드 54%"],
  ["sweetness", "보통 단맛(3) 사케가 너무 달았다", [
    card({ kind: "sake", sweet: 3, answers: [tooSweet] }),
  ], "드 62%"],
  ["sweetness", "꽤 단 술(4)인데 덜 달았다", [
    card({ kind: "korean_traditional", sweet: 4, answers: [notSweet] }),
  ], "달 67%"],
  // More records carry the place further, and never to the end.
  [
    "sweetness",
    "단맛 4가 충분히 달아서 좋았다, 세 번",
    times(3, card({ sweet: 4, answers: [sweetEnough] })),
    "달 65%",
  ],
  [
    "sweetness",
    "같은 답 열 번",
    times(10, card({ sweet: 4, answers: [sweetEnough] })),
    "달 70%",
  ],
  [
    "sweetness",
    "아주 단 술(5)만 열 번 좋아함",
    times(10, card({ sweet: 5, answers: [sweetLiked] })),
    "달 88%",
  ],
  ["weight", "묵직한 술(4)이 묵직해서 좋았다", [
    card({ body: 4, answers: [heavyLiked] }),
  ], "묵 58%"],
  ["weight", "가벼운 사케(2)가 가벼워서 좋았다", [
    card({ kind: "sake", body: 2, answers: [lightLiked] }),
  ], "가 59%"],
  ["weight", "묵직한 술(4)이 묵직해서 아쉬웠다", [
    card({ body: 4, answers: [tooHeavy] }),
  ], "가 59%"],
  // 열감 and 잡내 only lean the axis: they open no letter and cannot
  // cancel what was said about the weight itself.
  ["weight", "묵직해서 좋았다 + 열감 아쉬움", [
    card({ body: 4, answers: [heavyLiked, heatMinded] }),
  ], "묵 55%"],
  [
    "weight",
    "열감 아쉬움만 네 번",
    times(4, card({ body: 4, answers: [heatMinded] })),
    "?",
  ],
  [
    "weight",
    "묵직해서 좋았다 세 번, 열감도 좋았다",
    times(3, card({ body: 4, answers: [heavyLiked, heatLiked] })),
    "묵 66%",
  ],
  ["aroma", "꿀·바닐라가 좋았다", [
    card({ answers: [aroma("honey"), aroma("vanilla")] }),
  ], "풍 61%"],
  ["aroma", "레몬·복숭아·바닐라가 좋았다", [
    card({
      answers: [aroma("lemon"), aroma("peach"), aroma("vanilla")],
    }),
  ], "산 54%"],
  ["aroma", "레몬·복숭아가 좋았고 스모키는 거슬렸다", [
    card({
      answers: [aroma("lemon"), aroma("peach"), aroma("smoke", "burden")],
    }),
  ], "산 62%"],
  [
    "aroma",
    "꿀·바닐라·오크가 좋았다, 다섯 번",
    times(
      5,
      card({ answers: [aroma("honey"), aroma("vanilla"), aroma("oak")] }),
    ),
    "풍 75%",
  ],
  ["finish", "여운이 이어져서 좋았다", [
    card({ answers: [lingered] }),
  ], "길 63%"],
  ["finish", "금방 깔끔해져서 좋았다", [
    card({ answers: [cleared] }),
  ], "깔 63%"],
  [
    "finish",
    "이어져서 좋았다 다섯 번",
    times(5, card({ answers: [lingered] })),
    "길 75%",
  ],
];

Deno.test("letters: every agreed situation shows the agreed letter and share", () => {
  const wrong: string[] = [];
  for (const [axis, name, cards, expected] of SITUATIONS) {
    const actual = shown(cards, axis);
    if (actual !== expected) wrong.push(`${name}: ${actual}, not ${expected}`);
  }
  if (wrong.length > 0) throw new Error(wrong.join("\n"));
});

Deno.test("letters: the letter's side always holds more than half, and never the whole", () => {
  for (const [axis, name, cards] of SITUATIONS) {
    for (let count = 1; count <= cards.length; count++) {
      const state =
        lettersFromMarks(records(cards.slice(0, count))).state.axes[axis];
      if (state.letter === null) {
        same([state.left_share, state.right_share], [0, 0], name);
        continue;
      }
      same(state.left_share + state.right_share, 100, name);
      const leftLetter = state.letter === "F" || state.letter === "D" ||
        state.letter === "L" || state.letter === "C";
      const own = leftLetter ? state.left_share : state.right_share;
      if (own < 50 || own >= 100) {
        throw new Error(`${name} after ${count}: ${state.letter} at ${own}%`);
      }
    }
  }
});

Deno.test("letters: one record leans a little and the same answer keeps leaning further", () => {
  const sweet = card({ sweet: 5, answers: [sweetLiked] });
  const shares = [1, 2, 3, 6, 10, 30].map((count) =>
    lettersFromMarks(records(times(count, sweet))).state.axes.sweetness
      .right_share
  );
  for (let i = 1; i < shares.length; i++) {
    if (shares[i] < shares[i - 1]) {
      throw new Error(`shares fell: ${shares.join(", ")}`);
    }
  }
  if (shares[0] > 70) throw new Error(`one record leaned ${shares[0]}%`);
  if (shares[shares.length - 1] > 95) {
    throw new Error(`thirty records reached ${shares[shares.length - 1]}%`);
  }
});

Deno.test("letters: the letter follows the leaning side, and a turn is a moment only once it is clear", () => {
  // Four liked sweet bottles, then the same sweetness is too sweet each time.
  const run = [
    ...times(4, card({ sweet: 4, answers: [sweetEnough] })),
    ...times(4, card({ sweet: 4, answers: [tooSweet] })),
  ];
  const trail = run.map((_, index) =>
    shown(run.slice(0, index + 1), "sweetness")
  );
  same(trail, [
    "달 59%",
    "달 63%",
    "달 65%",
    "달 66%",
    "달 59%",
    "달 54%",
    "달 50%",
    "드 53%",
  ], "what the screen shows after each record");
  const { changes } = lettersFromMarks(records(run));
  same(
    changes.map((c) => `${c.record_id}:${c.from_letter}>${c.to_letter}`),
    ["r01:null>S"],
    "the letter leans dry at 53% without a moment yet",
  );

  const longer = [...run, ...times(2, card({ sweet: 4, answers: [tooSweet] }))];
  const turned = lettersFromMarks(records(longer));
  same(
    turned.changes.map((c) =>
      `${c.record_id}:${c.from_letter}>${c.to_letter}:${c.left_share}`
    ),
    ["r01:null>S:41", "r09:S>D:56"],
    "the turn is kept once the dry side holds 55% or more",
  );
});

Deno.test("letters: answers that go back and forth keep the letter near the middle without moments", () => {
  const run = Array.from(
    { length: 8 },
    (_, index) =>
      card({ sweet: 4, answers: [index % 2 ? tooSweet : sweetEnough] }),
  );
  const { state, changes } = lettersFromMarks(records(run));
  const own = Math.max(
    state.axes.sweetness.left_share,
    state.axes.sweetness.right_share,
  );
  if (own > 54) throw new Error(`leaned to ${own}%`);
  same(changes.length, 1, "only the first letter is a moment");
});

Deno.test("letters: a record that says nothing on an axis leaves it as it was", () => {
  const sweet = card({ sweet: 4, answers: [sweetEnough] });
  const silent = card({ answers: [lingered] });
  const { state } = lettersFromMarks(
    records([sweet, silent, silent, sweet]),
  );
  same(state.axes.sweetness.vote_count, 2);
  same(
    state.axes.sweetness.right_share,
    lettersFromMarks(records([sweet, sweet])).state.axes.sweetness
      .right_share,
  );
  same(state.record_count, 4);
});

Deno.test("letters: an answer that names its side is not moved off it by the catalog", () => {
  // The catalog calls the bottle light, the reader said 묵직해서 좋았어요.
  same(shown([card({ body: 1, answers: [heavyLiked] })], "weight"), "묵 58%");
  // The catalog calls it very sweet, the reader said 은은해서 좋았어요.
  same(
    shown([card({ sweet: 5, answers: [sweetGentle] })], "sweetness"),
    "드 58%",
  );
  // No level at all: the named side still counts, a bare 좋았어요 cannot.
  same(shown([card({ answers: [sweetEnough] })], "sweetness"), "달 58%");
  same(shown([card({ answers: [sweetLiked] })], "sweetness"), "?");
});

/** The marks of a card written today from these answers: "answer 4.5 x1". */
function gaugeMarks(keys: string[], product: SensoryProduct) {
  const marks = marksOf(recordFrom("letters", keys, product));
  return Object.fromEntries(
    Object.entries(marks).flatMap(([axis, list]) =>
      list.length
        ? [[
          axis,
          list.map((m) => `${m.from} ${round(m.place)} x${round(m.weight)}`),
        ]]
        : []
    ),
  );
}

Deno.test("letters: a 단맛 or 바디 gauge marks by the side its step names, against where the bottle stands", () => {
  const cases: [string, string[], SensoryProduct, Record<string, string[]>][] =
    [
      // A high step liked stands at the bottle, never under the high side.
      [
        "아주 단 술(5), 5단계가 좋았다",
        ["level:sweetness:5:liked"],
        malt({
          sweetness: 5,
        }),
        { sweetness: ["answer 4.98 x1"] },
      ],
      ["병 값 없이 4단계가 좋았다", ["level:sweetness:4:liked"], malt(), {
        sweetness: ["answer 4 x1"],
      }],
      // A low step liked is never moved off the low side by the catalog.
      [
        "아주 단 술(5), 2단계가 좋았다",
        ["level:sweetness:2:liked"],
        malt({
          sweetness: 5,
        }),
        { sweetness: ["answer 2 x1"] },
      ],
      // The middle step names no side: it stands where the bottle does, and
      // says nothing when the bottle has no level or when it was minded.
      [
        "아주 단 술(5), 3단계가 좋았다",
        ["level:sweetness:3:liked"],
        malt({
          sweetness: 5,
        }),
        { sweetness: ["answer 4.98 x1"] },
      ],
      ["병 값 없이 3단계가 좋았다", ["level:sweetness:3:liked"], malt(), {}],
      [
        "3단계가 아쉬웠다",
        ["level:sweetness:3:disliked"],
        malt({
          sweetness: 4,
        }),
        {},
      ],
      // 아쉬웠어요 at a high step wanted less, at a low step more.
      [
        "아주 단 술(5), 5단계가 아쉬웠다",
        ["level:sweetness:5:disliked"],
        malt({
          sweetness: 5,
        }),
        { sweetness: ["answer 2.49 x1"] },
      ],
      [
        "꽤 단 술(4), 2단계가 아쉬웠다",
        ["level:sweetness:2:disliked"],
        bottle("korean_traditional", "takju", { sweetness: 4 }),
        { sweetness: ["answer 5 x1"] },
      ],
      [
        "묵직한 술(4), 4단계가 좋았다",
        ["level:body:4:liked"],
        malt({
          body: 4,
        }),
        { weight: ["answer 4 x1"] },
      ],
      [
        "가벼운 사케(2), 2단계가 좋았다",
        ["level:body:2:liked"],
        bottle("sake", "junmai", { body: 2 }),
        { weight: ["answer 1.91 x1"] },
      ],
      [
        "묵직한 술(4), 4단계가 아쉬웠다",
        ["level:body:4:disliked"],
        malt({
          body: 4,
        }),
        { weight: ["answer 1.94 x1"] },
      ],
      // 스파이시 only leans the weight: welcome heavy, too much light; too
      // faint, or none at all, says nothing of weight.
      [
        "묵직해서 좋았다 + 스파이시 아쉬움",
        ["level:body:4:liked", "level:spice:4:disliked"],
        malt({ body: 4 }),
        { weight: ["answer 4 x1", "neighbour 2 x0.3"] },
      ],
      ["스파이시가 좋았다", ["level:spice:4:liked"], malt({ body: 4 }), {
        weight: ["neighbour 4 x0.3"],
      }],
      ["스파이시가 약해 아쉬웠다", ["level:spice:2:disliked"], malt(), {}],
      // 사케의 감칠맛 and 끝맛의 인상 are on no ruler.
      [
        "감칠맛, 끝맛의 인상",
        ["level:umami:4:liked", "level:finish_character:5:liked"],
        bottle("sake", "junmai", { acidity: 2 }),
        {},
      ],
    ];
  for (const [name, keys, product, expected] of cases) {
    same(gaugeMarks(keys, product), expected, name);
  }
});

Deno.test("letters: the finish is marked by 여운의 길이 alone", () => {
  const cases: [string, string[], Record<string, string[]>][] = [
    ["길어서 좋았다", ["level:finish_length:4:liked"], {
      finish: ["answer 4.5 x1"],
    }],
    ["깔끔해서 좋았다", ["level:finish_length:2:liked"], {
      finish: ["answer 1.5 x1"],
    }],
    // A short finish minded wants it to stay, a long one minded to clear.
    ["짧아서 아쉬웠다", ["level:finish_length:1:disliked"], {
      finish: ["answer 4.5 x1"],
    }],
    ["길어서 아쉬웠다", ["level:finish_length:5:disliked"], {
      finish: ["answer 1.5 x1"],
    }],
    ["중간 길이", ["level:finish_length:3:liked"], {}],
    // 다시 마시고 싶은지 moves a liked mark up and a minded one down, and back.
    [
      "다시 마시고 싶다",
      ["revisit:wantAgain", "level:finish_length:4:liked"],
      { finish: ["answer 4.5 x1.25"] },
    ],
    [
      "다시 마시고 싶지 않다",
      ["revisit:doNotWantAgain", "level:finish_length:4:liked"],
      { finish: ["answer 4.5 x0.75"] },
    ],
  ];
  for (const [name, keys, expected] of cases) {
    same(gaugeMarks(keys, malt()), expected, name);
  }
});

Deno.test("letters: the aromas a record names are counted together, each once, at whichever moment they were picked", () => {
  const cases: [string, string[], Record<string, string[]>][] = [
    ["꿀 하나", ["aroma:nose:honey:liked"], { aroma: ["answer 4 x1"] }],
    // The same aroma named again in the mouth is not a second one.
    ["꿀, 코와 입안", ["aroma:nose:honey:liked", "aroma:palate:honey:liked"], {
      aroma: ["answer 4 x1"],
    }],
    ["꿀(코) + 바닐라(입안)", [
      "aroma:nose:honey:liked",
      "aroma:palate:vanilla:liked",
    ], { aroma: ["answer 4.33 x1"] }],
    ["레몬·복숭아(코) + 바닐라(입안)", [
      "aroma:nose:lemon:liked",
      "aroma:nose:peach:liked",
      "aroma:palate:vanilla:liked",
    ], { aroma: ["answer 2.5 x1"] }],
    ["레몬·복숭아가 좋았고 입안의 스모키는 거슬렸다", [
      "aroma:nose:lemon:liked",
      "aroma:nose:peach:liked",
      "aroma:palate:smoke:disliked",
    ], { aroma: ["answer 1.67 x1", "neighbour 2 x0.3"] }],
    // The 피트 gauge is the 피트 aroma.
    ["피트 4단계가 좋았다", ["level:peat:4:liked"], { aroma: ["answer 4 x1"] }],
    // An aroma picked after swallowing is an aroma like the others.
    ["삼킨 뒤 남은 꿀 향", ["aroma:finish:honey:liked"], {
      aroma: ["answer 4 x1"],
    }],
    [
      "꿀, 코와 삼킨 뒤",
      ["aroma:nose:honey:liked", "aroma:finish:honey:liked"],
      {
        aroma: ["answer 4 x1"],
      },
    ],
  ];
  for (const [name, keys, expected] of cases) {
    same(gaugeMarks(keys, malt()), expected, name);
  }
});

/* ---------------------------------------------------------- the service */

const ITEM = "30000000-0000-4000-8000-000000000001";
const AUTH = "10000000-0000-4000-8000-000000000002";
const CONVERT = "10000000-0000-4000-8000-000000000003";

/** 샤또 마고: cherry liked, a bright acidity liked, a clean finish liked. */
const request = (idempotencyKey: string, anonymous: boolean) =>
  tasteCardRequest([
    "aroma:nose:cherry:liked",
    "level:acidity:4:liked",
    "level:finish_length:2:liked",
  ], {
    idempotency_key: idempotencyKey,
    anonymous_session_id: anonymous ? "anonymous-session-one" : null,
  });

const margauxRows = {
  items: [{
    id: ITEM,
    name_ko: "샤또 마고",
    name_en: "Château Margaux",
    abv_percent: 13.5,
    style_key: "red_wine",
    region_key: null,
    ingredient_keys: [],
    production_process_keys: [],
    grape_variety_keys: ["cabernet_sauvignon"],
    category: { category_key: "wine" },
  }],
  profiles: [{
    alcohol_item_id: ITEM,
    sweetness: 1,
    acidity: 4,
    bitterness: 2,
    astringency: 4,
    body: 4,
    carbonation: 1,
    aroma_intensity: 4,
    finish_length: 4,
    finish_character: 3,
    aroma_tags: ["cherry", "oak"],
    palate_tags: [],
    finish_tags: [],
    level_sources: { sweetness: 2, acidity: 2, astringency: 2, body: 2 },
  }],
  media: [],
};

Deno.test("letters: a saved card refreshes the account's letters, a converted one too", async () => {
  const repository = new MemoryTasteCardRepository(margauxRows);
  const deps = testDependencies(repository);
  await createTasteCardResult(deps, request(AUTH, false), {
    user_id: "user-a",
  });
  const after = repository.letters.get("user-a");
  if (!after) throw new Error("letters not saved for the signed-in card");
  same(after.state.axes.aroma.letter, "F");
  same(after.state.axes.finish.letter, "C");
  same(after.state.axes.sweetness.letter, null);
  same(after.changes.length, 2);

  const anonymous = await createTasteCardResult(
    deps,
    request(CONVERT, true),
    null,
  );
  if (anonymous.state !== "final" || !anonymous.result.conversion) {
    throw new Error("anonymous card expected");
  }
  same(repository.letters.has("user-b"), false, "nothing before conversion");
  await convertAnonymousTasteCard(deps, {
    result_id: anonymous.result.result_id,
    anonymous_session_id: "anonymous-session-one",
    conversion_token: anonymous.result.conversion.conversion_token,
    idempotency_key: CONVERT,
  }, { user_id: "user-b" });
  same(repository.letters.get("user-b")?.state.record_count, 1);
});

Deno.test("letters: deleting a saved record recomputes the letters without it", async () => {
  const repository = new MemoryTasteCardRepository(margauxRows);
  const deps = testDependencies(repository);
  const created = await createTasteCardResult(deps, request(AUTH, false), {
    user_id: "user-a",
  });
  if (created.state !== "final") throw new Error("saved card expected");
  const resultId = created.result.result_id;
  same(repository.letters.get("user-a")?.state.record_count, 1);

  let refused = "";
  try {
    await deleteOwnedTasteCardRecord(deps, resultId, { user_id: "user-b" });
  } catch (error) {
    refused = (error as { code?: string }).code ?? String(error);
  }
  same(refused, "result_not_found", "a stranger cannot delete the record");
  same(repository.letters.get("user-a")?.state.record_count, 1);

  same(
    await deleteOwnedTasteCardRecord(deps, resultId, { user_id: "user-a" }),
    { deleted: true },
  );
  const after = repository.letters.get("user-a");
  same(after?.state.record_count, 0);
  same(after?.state.axes.aroma.letter, null);
  same(after?.changes.length, 0);
  same(await repository.getOwnedResult(resultId, "user-a"), null);
});

/** A store that refuses the first [failures] letter saves with [error]. */
function refusingStore(failures: number, error: () => Error) {
  class RefusingRepository extends MemoryTasteCardRepository {
    saves = 0;
    override saveTasteLetters(
      ...args: Parameters<MemoryTasteCardRepository["saveTasteLetters"]>
    ) {
      if (++this.saves <= failures) return Promise.reject(error());
      return super.saveTasteLetters(...args);
    }
  }
  return new RefusingRepository(margauxRows);
}

Deno.test("letters: a save refused as stale is read and computed again", async () => {
  const repository = refusingStore(
    2,
    () => new TasteCardRepositoryError("P0001", "taste_letters_stale"),
  );
  await createTasteCardResult(
    testDependencies(repository),
    request(AUTH, false),
    { user_id: "user-a" },
  );
  same(repository.saves, 3);
  same(repository.letters.get("user-a")?.state.record_count, 1);
});

Deno.test("letters: a save refused for any other reason is not tried again", async () => {
  const repository = refusingStore(
    3,
    () =>
      new TasteCardRepositoryError("22023", "taste letters payload is invalid"),
  );
  const created = await createTasteCardResult(
    testDependencies(repository),
    request(AUTH, false),
    { user_id: "user-a" },
  );
  // The card is saved; only the letters wait for the next card.
  same(created.state, "final");
  same(repository.saves, 1);
  same(repository.letters.has("user-a"), false);
});
