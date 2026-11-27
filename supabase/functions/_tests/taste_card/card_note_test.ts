import { writeNote } from "../../_shared/taste_card/summary/note.ts";
import { withNoteWords } from "../../_shared/taste_card/summary/note_redraw.ts";
import { parseTasteCardResultEnvelope } from "../../_shared/taste_card/service/serialization.ts";
import { CARD_ENGINE_VERSION } from "../../_shared/taste_card/writing/card_text.ts";
import type { TasteCardView } from "../../_shared/taste_card/service/types.ts";
import { readRecord } from "../../_shared/record_reading/read_record.ts";
import { aromaName } from "../../_shared/record_reading/dictionary/aromas.ts";
import { validateSensoryAnswers } from "../../_shared/record_reading/record/questionnaire.ts";
import {
  buildSensoryRecord,
  catalogProduct,
} from "../../_shared/record_reading/record/record_builder.ts";
import { recordFrom } from "../helpers/card_fixture_record.ts";
import type { SensoryProduct } from "../../_shared/record_reading/record/sensory_record.ts";
import { assert, same } from "../helpers/assert.ts";

type Bottle = Parameters<typeof writeNote>[2];
const NO_BOTTLE: Bottle = {
  style_label: null,
  name_en: null,
  producer: null,
  region_key: null,
  vintage_year: null,
  age_years: null,
  grape_keys: [],
  ingredient_keys: [],
};

function noteOf(
  answers: string[],
  product: SensoryProduct,
  bottle: Partial<Bottle> = {},
) {
  const record = recordFrom("note", answers, product);
  return writeNote(record, readRecord(record), { ...NO_BOTTLE, ...bottle });
}

const red: SensoryProduct = {
  name: "샤또 마고",
  category: "wine",
  styleKey: "red_wine",
  region: null,
  abv: 13.5,
  ingredients: [],
  grapeVarietyKeys: ["cabernet_sauvignon", "merlot"],
  processes: [],
  levels: {
    sweetness: 1,
    acidity: 4,
    astringency: 4,
    body: 4,
    finish_length: 4,
  },
  levelRefs: {},
  descriptors: [],
};

Deno.test("note: a red wine's sheet holds the bottle's rows, what was named and how each gauge was set", () => {
  const note = noteOf(
    [
      "revisit:wantAgain",
      "aroma:nose:cherry:liked",
      "aroma:nose:vanilla:liked",
      "aroma:nose:leather:disliked",
      "level:sweetness:2:liked",
      "level:acidity:4:liked",
      "level:tannin:4:disliked",
      "level:body:3:liked",
      "aroma:palate:oak:liked",
      "level:finish_length:4:liked",
      "level:finish_character:2:disliked",
      "aroma:finish:smoke:disliked",
    ],
    red,
    {
      style_label: "레드 와인",
      name_en: "Château Margaux",
      producer: "샤또 마고",
      region_key: "fr_bordeaux",
      vintage_year: 2019,
      grape_keys: ["cabernet_sauvignon", "merlot"],
    },
  );
  same(Object.keys(note), [
    "original_name",
    "facts",
    "nose",
    "balance",
    "flavor",
    "texture",
    "finish_balance",
    "finish",
    "revisit",
    "appearance",
    "serving",
  ]);
  same(note.original_name, "Château Margaux");
  // The kind and the ABV are the product's own; the sheet's rows are the rest.
  same(note.facts.map((f) => f.label), ["생산자", "품종", "산지", "빈티지"]);
  same(
    note.facts.find((f) => f.label === "품종")?.value,
    "까베르네 소비뇽 · 메를로",
  );
  // The narrowest place alone, without the country over it.
  same(note.facts.find((f) => f.label === "산지")?.value, "보르도");
  // Every aroma named by the nose is listed by how it was taken.
  same(note.nose, [
    {
      label: "마음에 들었어요",
      marks: [{ label: "체리", felt: "liked" }, {
        label: "바닐라",
        felt: "liked",
      }],
    },
    { label: "부담됐어요", marks: [{ label: "가죽", felt: "burden" }] },
  ]);
  // One row per gauge of the sheet, in its order: the bottle's own level
  // (mark), the step the reader set (level) and its word (said). A step
  // marked 아쉬웠어요 reads by its side: a high one wanted less.
  same(
    note.balance.map((row) => [row.key, row.mark, row.level, row.felt]),
    [
      ["sweetness", 1, 2, "liked"],
      ["acidity", 4, 4, "liked"],
      ["body", 4, 3, "liked"],
      ["tannin", 4, 4, "less"],
    ],
  );
  for (const row of note.balance) {
    assert(row.label.length > 0 && typeof row.said === "string", row.key);
  }
  // 입안에서 느껴진 풍미 and 삼킨 뒤 느껴진 풍미 are listed like the nose.
  same(note.flavor, [
    { label: "마음에 들었어요", marks: [{ label: "오크", felt: "liked" }] },
  ]);
  same(note.finish, [
    { label: "부담됐어요", marks: [{ label: "스모키", felt: "burden" }] },
  ]);
  // 질감 is no section of a card written now.
  same(note.texture, []);
  // 여운 밸런스: the length carries the bottle's level, 끝맛 has none; both
  // name the two ends of their track.
  same(
    note.finish_balance?.map((row) => [
      row.key,
      row.mark,
      row.level,
      row.felt,
      row.ends?.length ?? null,
    ]),
    [
      ["finish_length", 4, 4, "liked", 2],
      ["finish_character", null, 2, "burden", 2],
    ],
  );
  same(note.revisit, "있음");
  // What the member may fill in: a red wine's colour, how it clings to the
  // glass, and how the bottle was opened.
  same(note.appearance?.groups.map((g) => [g.key, g.options.length]), [
    ["appearance", 8],
    ["appearance_texture", 3],
  ]);
  assert(
    note.appearance?.groups[0].options.every((o) => o.swatch) &&
      note.appearance?.groups[1].options.every((o) => o.icon),
    JSON.stringify(note.appearance),
  );
  same(note.serving?.options.map((o) => o.short ?? o.label), [
    "바로 오픈",
    "브리딩",
    "에어링",
    "디캔팅",
    "칠링",
  ]);
});

Deno.test("note: 붉은 체리 is no name of its own: a record that answered it, and a bottle tagged with it, read as 체리", () => {
  // 붉은 체리 was offered once and has folded into 체리. The stored option
  // still reads, as 체리's; with 체리 beside it the aroma is named once.
  const record = recordFrom("folded", [
    "aroma:nose:red_cherry:liked",
    "aroma:nose:cherry:liked",
    "aroma:palate:red_cherry:disliked",
  ], red);
  same(
    record.aromas.map((a) => [a.stage, a.key, a.reaction, a.answerRef]),
    [
      ["nose", "cherry", "liked", "aroma:nose:cherry:liked"],
      ["palate", "cherry", "burden", "aroma:palate:cherry:disliked"],
    ],
  );
  const note = writeNote(record, readRecord(record), NO_BOTTLE);
  same(note.nose, [{
    label: "마음에 들었어요",
    marks: [{ label: "체리", felt: "liked" }],
  }]);
  same(note.flavor?.flatMap((group) => group.marks), [
    { label: "체리", felt: "burden" },
  ]);
  // 향신료 is offered no more and is shown as no other word: a record that
  // answered it still passes the check, and the answer says nothing.
  const held = [
    ["sensory_revisit", ["revisit:wantAgain"]] as const,
    [
      "sensory_nose_aroma",
      ["aroma:nose:spice:liked", "aroma:nose:vanilla:liked"],
    ] as const,
  ].map(([question_key, selected_option_keys]) => ({
    question_key,
    selected_option_keys: [...selected_option_keys],
    free_text: null,
  }));
  validateSensoryAnswers(held);
  same(
    buildSensoryRecord("unshown", held, red).aromas.map((a) => a.key),
    ["vanilla"],
  );
  same(aromaName("spice"), null);
  // A bottle's tag is shown under the offered word too.
  same(aromaName("red_cherry"), "체리");
  same(
    catalogProduct({}, { aroma_tags: ["red_cherry", "cherry"] }).descriptors
      .map((d) => [d.key, d.label]),
    [["cherry", "체리"]],
  );
});

Deno.test("note: how a gauge marked 아쉬웠어요 reads, and a gauge nobody set keeps the bottle's level alone", () => {
  const note = noteOf([
    "level:sweetness:5:disliked",
    "level:acidity:1:disliked",
    "level:body:3:disliked",
    "level:finish_length:5:disliked",
    "level:finish_character:5:disliked",
  ], red);
  // 4–5 wanted less, 1–2 wanted more, the middle step names no side; 끝맛의
  // 인상 is a place between two ends, so it never asks for less or more.
  same(note.balance.map((row) => [row.key, row.level ?? null, row.felt]), [
    ["sweetness", 5, "less"],
    ["acidity", 1, "more"],
    ["body", 3, "burden"],
    ["tannin", null, null],
  ]);
  // The reader did not set 타닌: the catalog's level stays, with no word of theirs.
  const tannin = note.balance.find((row) => row.key === "tannin")!;
  same([tannin.mark, tannin.said, "level" in tannin], [4, null, false]);
  same(note.finish_balance?.map((row) => [row.key, row.felt]), [
    ["finish_length", "less"],
    ["finish_character", "burden"],
  ]);
});

Deno.test("note: a section nobody answered is empty, and the kind's usual level is never a mark", () => {
  // No level was read for this bottle: the style table's levels stay out.
  const bare = { ...red, levels: {}, grapeVarietyKeys: [] };
  const note = noteOf(
    ["revisit:unsure", "nose:unsure", "level:sweetness:2:liked"],
    bare,
  );
  same([note.nose, note.flavor, note.texture], [[], [], []]);
  same([note.finish_balance, note.finish], [[], []]);
  same(note.facts, []);
  same(note.original_name, null);
  // A skipped 재음용 의사 reads as the question's own middle choice.
  same(note.revisit, "애매해요");
  // The one answered gauge of such a bottle is the answer alone.
  same(note.balance.map((row) => [row.key, row.mark, row.level]), [
    ["sweetness", null, 2],
  ]);
  // 재음용 의사: the middle answer is neither a yes nor a no.
  same(
    ["wantAgain", "wouldAcceptAgain", "doNotWantAgain", "unsure"].map((key) =>
      noteOf([`revisit:${key}`, "level:sweetness:2:liked"], bare).revisit
    ),
    ["있음", "무난", "없음", "애매해요"],
  );
});

Deno.test("note: each kind has its own rows", () => {
  const base = {
    region: null,
    ingredients: [],
    grapeVarietyKeys: [],
    levelRefs: {},
    descriptors: [],
  };
  const rows = (note: ReturnType<typeof noteOf>) =>
    note.balance.map((row) => row.key);
  // A whisky: the age and the casks; its 단맛, 스파이시 and 피트 are answers,
  // never a mark of the catalog's.
  const whisky = noteOf(
    [
      "revisit:wouldAcceptAgain",
      "level:sweetness:3:liked",
      "level:spice:4:liked",
      "level:peat:1:liked",
    ],
    {
      ...base,
      name: "발베니 더블우드 12년",
      category: "whisky",
      styleKey: "single_malt_whisky",
      abv: 40,
      processes: ["wooden_cask", "ex_sherry_cask", "cask_finishing"],
      levels: { sweetness: 4, body: 3, finish_length: 4 },
    },
    { style_label: "싱글 몰트 위스키", producer: "발베니", age_years: 12 },
  );
  same(whisky.facts, [
    { label: "생산자", value: "발베니" },
    { label: "숙성", value: "12년" },
    { label: "캐스크", value: "셰리 캐스크 · 캐스크 피니시" },
  ]);
  same(whisky.balance.map((row) => [row.key, row.mark, row.level ?? null]), [
    ["sweetness", null, 3],
    ["body", 3, null],
    ["spice", null, 4],
    ["peat", null, 1],
  ]);
  same(whisky.finish_balance?.map((row) => [row.key, row.mark]), [
    ["finish_length", 4],
  ]);
  same(whisky.serving?.options.map((o) => o.key), [
    "neat",
    "rocks",
    "highball",
    "water",
  ]);
  same(whisky.appearance?.groups.map((g) => g.key), [
    "appearance",
    "appearance_texture",
  ]);

  // A sparkling wine trades 타닌 for 탄산감; a white wine has neither.
  const sweet = ["level:sweetness:3:liked"];
  const sparkling = noteOf(sweet, {
    ...base,
    name: "모엣 샹동",
    category: "wine",
    styleKey: "sparkling_wine",
    abv: 12,
    processes: [],
    levels: { sweetness: 1, astringency: 1, carbonation: 4, body: 2 },
  });
  same(rows(sparkling), ["sweetness", "body", "sparkling"]);
  same(sparkling.balance.at(-1)?.mark, 4);
  const white = noteOf(sweet, {
    ...base,
    name: "샤블리",
    category: "wine",
    styleKey: "white_wine",
    abv: 12.5,
    processes: [],
    levels: { sweetness: 1, astringency: 1, body: 2 },
  });
  same(rows(white), ["sweetness", "body"]);

  // A sake's 감칠맛 has no level of the bottle to stand beside; a still
  // sake's 탄산 1 is no row.
  const sake = noteOf(["level:acidity:4:liked", "level:umami:4:liked"], {
    ...base,
    name: "닷사이 45",
    category: "sake",
    styleKey: "junmai_daiginjo",
    abv: 16,
    processes: [],
    levels: { sweetness: 3, acidity: 2, body: 2, carbonation: 1 },
  });
  same(sake.balance.map((row) => [row.key, row.mark, row.level ?? null]), [
    ["sweetness", 3, null],
    ["acidity", 2, 4],
    ["umami", null, 4],
    ["body", 2, null],
  ]);
  same(sake.balance[0].word, null);
  same(sake.appearance, null);
  same(sake.serving?.label, "음용 온도");
  same(sake.serving?.options.map((o) => [o.label, o.short]), [
    ["차갑게(레이슈)", "레이슈"],
    ["상온", undefined],
    ["미지근하게(누루칸)", "누루칸"],
    ["따뜻하게(아쓰캉)", "아쓰캉"],
  ]);

  // A 탁주 names its ingredients, reads its marks in plain words and is
  // asked 탄산감.
  const takju = noteOf(["level:sparkling:2:liked"], {
    ...base,
    name: "해창 12도",
    category: "korean_traditional",
    styleKey: "takju",
    abv: 12,
    ingredients: ["rice", "nuruk_starter"],
    processes: ["parallel_multiple_fermentation"],
    levels: { sweetness: 4, acidity: 2, carbonation: 1, body: 4 },
  }, { region_key: "kr_haenam", ingredient_keys: ["rice", "nuruk_starter"] });
  // No name in another language: none is written.
  same(takju.original_name, null);
  same(takju.facts.find((f) => f.label === "주원료")?.value, "쌀 · 누룩");
  same(takju.balance.map((row) => [row.key, row.word]), [
    ["sweetness", "단 편"],
    ["acidity", "산미가 은은한 편"],
    ["body", "조금 묵직한 편"],
    ["sparkling", "탄산이 거의 없는 편"],
  ]);

  // A 증류식 소주 says how it was distilled; it is not asked 탄산감.
  const soju = noteOf(sweet, {
    ...base,
    name: "화요 25",
    category: "korean_traditional",
    styleKey: "distilled_soju",
    abv: 25,
    ingredients: ["rice"],
    processes: ["pot_distillation"],
    levels: { sweetness: 2, body: 2, carbonation: 1 },
  });
  same(soju.facts.find((f) => f.label === "증류·숙성")?.value, "단식 증류");
  same(rows(soju), ["sweetness", "body"]);
});

/** A stored view around one note, written by the engine named. */
function viewWith(
  note: ReturnType<typeof noteOf>,
  engine_version: string,
): TasteCardView {
  return {
    product: {
      drink_name_snapshot: "샤또 마고",
      user_name: null,
      image_reference: null,
      category_label: "와인",
      style_label: null,
      abv_percent: null,
    },
    bite: {
      nickname: "취향 탐색자",
      tags: [],
      summary: "요약",
      brief: "요약",
      guide: null,
    },
    positive: [],
    burden: [],
    balanced: [],
    note,
    metadata: {
      snapshot_ref: "snapshot",
      schema_version: 3,
      engine_version,
      generated_at: "2026-11-16T00:00:00.000Z",
      generated_from_record_ref: "record",
    },
  };
}

/** The view as the store returns it: read through the stored envelope's parser. */
function parsed(view: unknown): TasteCardView {
  return parseTasteCardResultEnvelope({
    wire_schema_version: "taste-card-result-wire-v3",
    result_id: "result",
    record_id: "record",
    snapshot_ref: "snapshot",
    ownership_state: "saved",
    alcohol_identification: {
      mode: "catalog_match",
      alcohol_item_id: "30000000-0000-4000-8000-000000000001",
      alcohol_name_snapshot: "샤또 마고",
      category: "wine",
    },
    view,
    conversion: null,
    created_at: "2026-11-16T00:00:00.000Z",
  }).view;
}

Deno.test("note: the redraw words go with a card of today's engine only, and hold the groups and 재음용 의사", () => {
  const note = noteOf(
    ["revisit:wouldAcceptAgain", "aroma:nose:cherry:liked"],
    red,
  );
  const served = withNoteWords(viewWith(note, CARD_ENGINE_VERSION));
  const words = served.note?.words;
  same(Object.keys(words ?? {}), ["groups", "revisit"]);
  // A thing was liked or it was not: no middle group.
  same(words?.groups, [
    { felt: "liked", label: "마음에 들었어요" },
    { felt: "missed", label: "부담됐어요" },
  ]);
  same(words?.revisit, {
    "revisit:wantAgain": "있음",
    "revisit:wouldAcceptAgain": "무난",
    "revisit:doNotWantAgain": "없음",
    "revisit:unsure": "애매해요",
  });
  // What the sheet says is what the answer's word says.
  same(note.revisit, words?.revisit["revisit:wouldAcceptAgain"]);
  same(note.nose[0].label, words?.groups[0].label);
  // A card written before the gauges cannot be re-answered: no words.
  const old = withNoteWords(viewWith(note, "card-facts-v2"));
  same(old.note?.words, undefined);
  // A card stored while a skipped 재음용 의사 was written 모르겠음 is served
  // with today's word, whatever engine wrote it; any other word stays.
  const skipped = { ...note, revisit: "모르겠음" };
  same(
    [CARD_ENGINE_VERSION, "card-facts-v2"].map((engine) =>
      withNoteWords(viewWith(skipped, engine)).note?.revisit
    ),
    ["애매해요", "애매해요"],
  );
  same(old.note?.revisit, "무난");
  same(
    withNoteWords({ ...viewWith(note, CARD_ENGINE_VERSION), note: null }).note,
    null,
  );
});

Deno.test("note: the stored view's parser takes today's note, and one stored before the gauges", () => {
  const today = viewWith(
    noteOf([
      "level:sweetness:2:liked",
      "level:finish_character:4:disliked",
      "aroma:palate:oak:liked",
    ], red),
    CARD_ENGINE_VERSION,
  );
  same(parsed(JSON.parse(JSON.stringify(today))), today);
  // A note stored before: no flavor, no finish_balance, no level; 질감 filled.
  const { flavor: _flavor, finish_balance: _finish, ...before } = today.note!;
  const stored = {
    ...today,
    note: {
      ...before,
      balance: [{
        key: "sweetness",
        label: "당도",
        mark: 1,
        word: "드라이",
        felt: "liked",
        said: "은은해서 좋았어요",
      }],
      texture: [{
        label: "마음에 들었어요",
        marks: [{ label: "묵직함", felt: "liked" }],
      }],
    },
  };
  same(parsed(JSON.parse(JSON.stringify(stored))), stored);
  // 끝맛의 인상's ends are two words or nothing.
  const broken = JSON.parse(JSON.stringify(today));
  broken.note.finish_balance.at(-1).ends = ["하나"];
  let code = "";
  try {
    parsed(broken);
  } catch (error) {
    code = (error as { code?: string }).code ?? String(error);
  }
  same(code, "note_ends_invalid");
});
