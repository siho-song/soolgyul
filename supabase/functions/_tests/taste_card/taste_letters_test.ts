// 나의 취향 조각 네 글자: the marks a record puts on each ruler, the place
// they average to, and when a letter shows or turns.
import {
  computeTasteLetters,
  type LetterAxis,
  letterMarks,
  type LetterRecord,
} from "../../_shared/taste_card/taste_letters.ts";
import { validateCardFacts } from "../../_shared/taste_card/facts/facts.ts";
import type { CardReading } from "../../_shared/taste_card/facts/reading.ts";
import {
  convertAnonymousTasteCard,
  createTasteCardResult,
  deleteOwnedTasteCardRecord,
} from "../../_shared/taste_card/service/orchestrator.ts";
import {
  SENSORY_QUESTIONNAIRE_VERSION,
  SENSORY_QUESTIONS,
} from "../../_shared/taste_card/record/questionnaire.ts";
import type { CreateTasteCardResultRequest } from "../../_shared/taste_card/service/types.ts";
import { TasteCardRepositoryError } from "../../_shared/taste_card/service/errors.ts";
import {
  ActualQuestionnaireRepository,
  testDependencies,
} from "../fixtures/actual_questionnaire_v3.ts";

const dir = new URL("../fixtures/card_facts/", import.meta.url);

function same(actual: unknown, expected: unknown, message = "equality") {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${message}: ${a} != ${b}`);
}

/* ------------------------------------------------------ made-up records */

type Reaction = CardReading["reactions"][number];
type Revisit = CardReading["record"]["revisit"];

function answer(
  domain: string,
  key: string,
  reaction: Reaction["reaction"],
  qualifier: string | null = null,
  phase: Reaction["phase"] = "drinking",
): Reaction {
  return {
    id: `${phase}:${domain}:${key}`,
    kind: "reaction",
    subject: { domain, key } as Reaction["subject"],
    phase,
    reaction,
    qualifier: qualifier as Reaction["qualifier"],
    focus: false,
    answer_refs: ["answer"],
  };
}

/** One record: the bottle's kind and read levels, and what was answered. */
function card(
  input: {
    kind?: string;
    sweet?: number;
    body?: number;
    revisit?: Revisit;
    answers: Reaction[];
  },
): CardReading {
  const level = (dimension: string, value: number | undefined, id: string) =>
    value === undefined ? [] : [{
      id,
      kind: "product" as const,
      fact: { type: "level" as const, dimension, level: value },
      source: "catalog:levels:2",
    }];
  return {
    record: {
      product_name: "병",
      category: input.kind ?? "whisky",
      style_key: null,
      revisit: input.revisit ?? "would_accept_again",
      section_states: {
        aroma: "answered",
        taste: "answered",
        mouthfeel: "answered",
        finish: "answered",
      },
    },
    reactions: input.answers,
    product_facts: [
      ...level("sweetness", input.sweet, "p1"),
      ...level("body", input.body, "p2"),
    ] as CardReading["product_facts"],
  };
}

const sweetLiked = answer("taste", "sweetness", "liked");
const sweetEnough = answer("taste", "sweetness", "liked", "pronounced");
const sweetGentle = answer("taste", "sweetness", "liked", "gentle");
const sweetFine = answer("taste", "sweetness", "fine");
const tooSweet = answer("taste", "sweetness", "burden", "excessive");
const notSweet = answer("taste", "sweetness", "burden", "too_weak");
const heavyLiked = answer("mouthfeel", "heavy", "liked");
const lightLiked = answer("mouthfeel", "light", "liked");
const weightFine = answer("mouthfeel", "heavy", "fine");
const tooHeavy = answer("mouthfeel", "heavy", "burden");
const heatMinded = answer("mouthfeel", "warmth", "burden");
const heatLiked = answer("mouthfeel", "warmth", "liked");
const lingered = answer("finish", "persistence", "liked", null, "finish");
const cleared = answer("finish", "clean", "liked", null, "finish");
const tooBrief = answer(
  "finish",
  "persistence",
  "burden",
  "too_brief",
  "finish",
);
const echoLiked = answer(
  "finish",
  "aroma_echo",
  "liked",
  "lingering",
  "finish",
);
const offFlavor = answer(
  "finish",
  "off_flavor",
  "burden",
  "lingering",
  "finish",
);
const residue = answer("mouthfeel", "heavy", "burden", "lingering", "finish");
const aroma = (key: string, reaction: Reaction["reaction"] = "liked") =>
  answer("aroma", key, reaction);
const times = <T>(count: number, value: T): T[] =>
  Array.from({ length: count }, () => value);

function records(cards: readonly CardReading[]): LetterRecord[] {
  return cards.map((reading, index) => ({
    record_id: `r${String(index + 1).padStart(2, "0")}`,
    product_name: `병 ${index + 1}`,
    recorded_at: new Date(Date.UTC(2026, 0, 1 + index)).toISOString(),
    marks: letterMarks(reading),
  }));
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
function shown(cards: readonly CardReading[], axis: LetterAxis): string {
  const state = computeTasteLetters(records(cards)).state.axes[axis];
  if (state.letter === null) return "?";
  const own = Math.max(state.left_share, state.right_share);
  return `${GLYPHS[state.letter]} ${own}%`;
}

/* ------------------------------------------------- the agreed situations */

// Agreed with the product owner on 2026-11-12: what each kind of record
// should show. 단맛 n is the bottle's catalog level.
const SITUATIONS: readonly [LetterAxis, string, CardReading[], string][] = [
  // The same 좋았어요 reads by how sweet the bottle is, and by its kind.
  ["sweetness", "아주 단 술(5)이 좋았다", [
    card({ sweet: 5, answers: [sweetLiked] }),
  ], "달 66%"],
  ["sweetness", "아주 단 술이 좋았고 다시 마시고 싶다", [
    card({ sweet: 5, revisit: "want_again", answers: [sweetLiked] }),
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
  // 적당했어요 says the bottle's place was comfortable; two open the letter.
  ["sweetness", "드라이 와인이 적당했다, 한 번", [
    card({ kind: "wine", sweet: 1, answers: [sweetFine] }),
  ], "?"],
  [
    "sweetness",
    "드라이 와인이 적당했다, 두 번",
    times(2, card({ kind: "wine", sweet: 1, answers: [sweetFine] })),
    "드 59%",
  ],
  [
    "sweetness",
    "드라이 와인이 적당했다, 다섯 번",
    times(5, card({ kind: "wine", sweet: 1, answers: [sweetFine] })),
    "드 64%",
  ],
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
  // 적당했어요 is not thrown away when a liked answer comes after it.
  ["sweetness", "드라이 와인 다섯 번 적당 뒤 아주 단 술이 좋았다", [
    ...times(5, card({ kind: "wine", sweet: 1, answers: [sweetFine] })),
    card({ kind: "wine", sweet: 5, answers: [sweetLiked] }),
  ], "드 51%"],
  ["weight", "묵직한 술(4)이 묵직해서 좋았다", [
    card({ body: 4, answers: [heavyLiked] }),
  ], "묵 58%"],
  ["weight", "가벼운 사케(2)가 가벼워서 좋았다", [
    card({ kind: "sake", body: 2, answers: [lightLiked] }),
  ], "가 59%"],
  ["weight", "묵직한 술(4)이 묵직해서 아쉬웠다", [
    card({ body: 4, answers: [tooHeavy] }),
  ], "가 59%"],
  // 열감 and 텁텁함 only lean the axis: they open no letter and cannot
  // cancel what was said about the weight itself.
  ["weight", "무게감 적당 + 열감 아쉬움", [
    card({ body: 3, revisit: "want_again", answers: [weightFine, heatMinded] }),
  ], "?"],
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
      answers: [aroma("lemon_lime"), aroma("peach"), aroma("vanilla")],
    }),
  ], "산 54%"],
  ["aroma", "레몬·복숭아가 좋았고 스모키는 거슬렸다", [
    card({
      answers: [aroma("lemon_lime"), aroma("peach"), aroma("smoke", "burden")],
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
  ["finish", "너무 빨리 사라졌다 + 코끝 잔향은 좋았다", [
    card({ answers: [tooBrief, echoLiked] }),
  ], "길 67%"],
  ["finish", "금방 깔끔해져서 좋았다 + 잡내", [
    card({ answers: [cleared, offFlavor] }),
  ], "깔 64%"],
  ["finish", "텁텁함만 세 번", times(3, card({ answers: [residue] })), "?"],
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
        computeTasteLetters(records(cards.slice(0, count))).state.axes[axis];
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
    computeTasteLetters(records(times(count, sweet))).state.axes.sweetness
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
  const { changes } = computeTasteLetters(records(run));
  same(
    changes.map((c) => `${c.record_id}:${c.from_letter}>${c.to_letter}`),
    ["r01:null>S"],
    "the letter leans dry at 53% without a moment yet",
  );

  const longer = [...run, ...times(2, card({ sweet: 4, answers: [tooSweet] }))];
  const turned = computeTasteLetters(records(longer));
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
  const { state, changes } = computeTasteLetters(records(run));
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
  const { state } = computeTasteLetters(
    records([sweet, silent, silent, sweet]),
  );
  same(state.axes.sweetness.vote_count, 2);
  same(
    state.axes.sweetness.right_share,
    computeTasteLetters(records([sweet, sweet])).state.axes.sweetness
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

Deno.test("letters: 적당했어요 in a drink not wanted again is no comfort", () => {
  const fine = (revisit: Revisit) =>
    times(2, card({ kind: "wine", sweet: 1, revisit, answers: [sweetFine] }));
  same(shown(fine("would_accept_again"), "sweetness"), "드 59%");
  same(shown(fine("do_not_want_again"), "sweetness"), "?");
});

/* ------------------------------------------------------- the BP records */

async function bpRecords(): Promise<LetterRecord[]> {
  const names: string[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (entry.isFile && /^bp-\d+\.json$/.test(entry.name)) {
      names.push(entry.name);
    }
  }
  names.sort();
  const out: LetterRecord[] = [];
  for (const [index, name] of names.entries()) {
    const facts = validateCardFacts(
      JSON.parse(await Deno.readTextFile(new URL(name, dir))),
    );
    out.push({
      record_id: name,
      product_name: facts.record.product_name,
      recorded_at: new Date(Date.UTC(2025, 8, 1 + index * 11)).toISOString(),
      marks: letterMarks(facts),
    });
  }
  return out;
}

const round = (value: number) => Math.round(value * 100) / 100;

Deno.test("letters: the BP cards put the marks their answers and bottles say", async () => {
  const byName = new Map(
    (await bpRecords()).map((record) => [
      record.record_id,
      Object.fromEntries(
        Object.entries(record.marks).map(([axis, marks]) => [
          axis,
          marks.map((m) => `${m.from} ${round(m.place)} x${round(m.weight)}`),
        ]),
      ),
    ]),
  );
  // 샤또 마고: cherry liked, one fresh aroma. Nothing else was said on the
  // four axes.
  same(byName.get("bp-01.json"), {
    aroma: ["answer 2 x1"],
    sweetness: [],
    weight: [],
    finish: [],
  });
  // 해창 12도: its ordinary sweetness (3) was liked; a middling body was
  // already too heavy, and the weight stayed as 텁텁함.
  same(byName.get("bp-02.json"), {
    aroma: [],
    sweetness: ["answer 3.2 x1"],
    weight: ["answer 1.4 x1", "neighbour 2 x0.3"],
    finish: ["neighbour 2 x0.3"],
  });
  // 아드벡 우거다일: peat and smoke liked; a whisky with little sweetness (2)
  // was still too sweet, which stands at the dry end.
  same(byName.get("bp-12.json"), {
    aroma: ["answer 4.33 x1"],
    sweetness: ["answer 1 x1"],
    weight: ["answer 1.95 x1", "neighbour 2 x0.3"],
    finish: ["neighbour 2 x0.3"],
  });
  // 이니스킬린 아이스와인: the sweetest wine was too sweet, which says little
  // (2.5 of 5); the weight of a full wine was a burden.
  same(byName.get("bp-13.json"), {
    aroma: ["answer 1.67 x1"],
    sweetness: ["answer 2.49 x1"],
    weight: ["answer 1.99 x1", "neighbour 2 x0.3"],
    finish: ["neighbour 2 x0.3"],
  });
  // 우고노츠키: wanted again, so its liked answers weigh a quarter more.
  same(byName.get("bp-18.json"), {
    aroma: ["answer 1.67 x1.25"],
    sweetness: [],
    weight: ["answer 2 x1.25"],
    finish: ["answer 1.5 x1.25"],
  });
});

Deno.test("letters: replaying the BP cards as one person's records", async () => {
  const { state, changes } = computeTasteLetters(await bpRecords());
  same(
    Object.fromEntries(
      Object.entries(state.axes).map(([axis, value]) => [
        axis,
        value.letter === null
          ? "?"
          : `${value.letter} ${Math.max(value.left_share, value.right_share)}`,
      ]),
    ),
    { aroma: "F 61", sweetness: "D 58", weight: "L 68", finish: "C 65" },
    "final letters",
  );
  // The sixteen cards are sixteen different drinkers, so the finish swings
  // between 51% and 59% from bp-04 on; the swing is a moment only at bp-15,
  // where the clean side reached 58%. Sweetness turned at once at bp-12,
  // where a whisky with little sweetness was too sweet.
  same(
    changes.map((change) =>
      `${change.record_id}:${change.axis}:${change.from_letter}>${change.to_letter}`
    ),
    [
      "bp-01.json:aroma:null>F",
      "bp-02.json:sweetness:null>S",
      "bp-02.json:weight:null>L",
      "bp-03.json:finish:null>P",
      "bp-12.json:sweetness:S>D",
      "bp-15.json:finish:P>C",
    ],
    "changes",
  );
});

/* ---------------------------------------------------------- the service */

const ITEM = "30000000-0000-4000-8000-000000000001";
const AUTH = "10000000-0000-4000-8000-000000000002";
const CONVERT = "10000000-0000-4000-8000-000000000003";

function request(
  idempotencyKey: string,
  anonymous: boolean,
): CreateTasteCardResultRequest {
  const answers: Record<string, string[]> = {
    sensory_revisit: ["revisit:wantAgain"],
    sensory_aroma: [
      "notice:aroma:cherry",
      "reaction:aroma:cherry:liked",
      "reason:aroma:cherry:liked:pronounced",
    ],
    sensory_taste: [
      "reaction:taste:acidity:liked",
      "reason:taste:acidity:liked:pronounced",
    ],
    sensory_finish: ["finish:clean"],
  };
  return {
    idempotency_key: idempotencyKey,
    anonymous_session_id: anonymous ? "anonymous-session-one" : null,
    questionnaire_version: SENSORY_QUESTIONNAIRE_VERSION,
    alcohol_identification: {
      mode: "catalog_match",
      alcohol_item_id: ITEM,
      alcohol_name_snapshot: "샤또 마고",
      category: "wine",
    },
    answers: Object.keys(SENSORY_QUESTIONS).map((key) => ({
      question_key: key,
      selected_option_keys: answers[key] ?? [],
      free_text: null,
    })),
    q7_free_text: null,
    photo_asset_id: null,
  };
}

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
    finish_cleanliness: 3,
    aroma_tags: ["cherry", "oak"],
    palate_tags: [],
    finish_tags: [],
    aroma_note: null,
    palate_note: null,
    level_sources: { sweetness: 2, acidity: 2, astringency: 2, body: 2 },
  }],
  media: [],
};

Deno.test("letters: a saved card refreshes the account's letters, a converted one too", async () => {
  const repository = new ActualQuestionnaireRepository(margauxRows);
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
  const repository = new ActualQuestionnaireRepository(margauxRows);
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
  class RefusingRepository extends ActualQuestionnaireRepository {
    saves = 0;
    override saveTasteLetters(
      ...args: Parameters<ActualQuestionnaireRepository["saveTasteLetters"]>
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
