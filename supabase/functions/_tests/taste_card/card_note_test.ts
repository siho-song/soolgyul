import { writeNote } from "../../_shared/taste_card/summary/note.ts";
import { noteWords } from "../../_shared/taste_card/summary/note_redraw.ts";
import { buildCardFacts } from "../../_shared/taste_card/findings/conclusions.ts";
import { recordFrom } from "../helpers/card_fixture_record.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
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
  return writeNote(record, buildCardFacts(record), { ...NO_BOTTLE, ...bottle });
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
  levels: { sweetness: 1, acidity: 4, astringency: 4, body: 4 },
  levelRefs: {},
  descriptors: [],
};

Deno.test("note: a red wine's sheet holds the bottle's rows, what was named and what was said of it", () => {
  const note = noteOf(
    [
      "revisit:wantAgain",
      "notice:aroma:cherry",
      "reaction:aroma:cherry:liked",
      "notice:aroma:vanilla",
      "notice:aroma:leather",
      "reaction:aroma:leather:disliked",
      "reaction:taste:sweetness:liked",
      "reason:taste:sweetness:liked:gentle",
      "reaction:taste:acidity:liked",
      "reaction:taste:bitterness:disliked",
      "reason:taste:bitterness:disliked:too_strong",
      "notice:mouthfeel:heavy",
      "reaction:mouthfeel:heavy:liked",
      "notice:mouthfeel:drying",
      "reaction:mouthfeel:drying:disliked",
      "finish:pleasantLength",
      "finish:offFlavor",
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
  same(note.original_name, "Château Margaux");
  // The kind and the ABV are the product's own; the sheet's rows are the rest.
  same(note.facts.map((f) => f.label), ["생산자", "품종", "산지", "빈티지"]);
  same(
    note.facts.find((f) => f.label === "품종")?.value,
    "까베르네 소비뇽 · 메를로",
  );
  // The narrowest place alone, without the country over it.
  same(note.facts.find((f) => f.label === "산지")?.value, "보르도");
  // Every aroma named is listed by how it was taken, liked or a burden;
  // one only named, as older answers hold, reads as liked.
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
  same(note.balance, [
    {
      key: "sweetness",

      label: "당도",
      mark: 1,
      word: "드라이",
      felt: "liked",
      said: "은은해서 좋았어요",
    },
    {
      key: "acidity",

      label: "산도",
      mark: 4,
      word: "조금 높은 산도",
      felt: "liked",
      said: "좋았어요",
    },
    // The catalog read no 쓴맛 for the bottle: the row is the answer alone.
    {
      key: "bitterness",

      label: "쓴맛",
      mark: null,
      word: null,
      felt: "less",
      said: "너무 강해서 부담스러웠어요",
    },
    {
      key: "astringency",
      label: "타닌",
      mark: 4,
      word: "탄탄한 타닌",
      felt: null,
      said: null,
    },
    {
      key: "body",
      label: "바디",
      mark: 4,
      word: "미디엄-풀 바디",
      felt: null,
      said: null,
    },
  ]);
  same(note.texture, [
    { label: "마음에 들었어요", marks: [{ label: "묵직함", felt: "liked" }] },
    { label: "부담됐어요", marks: [{ label: "떫음", felt: "less" }] },
  ]);
  same(note.finish, [
    {
      label: "마음에 들었어요",
      marks: [{ label: "기분 좋게 이어지는 여운", felt: "liked" }],
    },
    {
      label: "부담됐어요",
      marks: [{ label: "삼킨 뒤 올라오는 잡내", felt: "less" }],
    },
  ]);
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

Deno.test("note: a section nobody answered is empty, and the kind's usual level is never a mark", () => {
  // No level was read for this bottle: the style table's levels stay out.
  const note = noteOf([
    "revisit:unsure",
    "aroma:unsure",
    "reaction:taste:sweetness:liked",
    "reaction:taste:acidity:liked",
    "reaction:taste:bitterness:liked",
    "mouthfeel:unsure",
    "finish:unsure",
  ], { ...red, levels: {}, grapeVarietyKeys: [] });
  same(note.nose, []);
  same(note.texture, []);
  same(note.finish, []);
  same(note.balance.map((row) => [row.label, row.mark, row.said]), [
    ["당도", null, "좋았어요"],
    ["산도", null, "좋았어요"],
    ["쓴맛", null, "좋았어요"],
  ]);
  same(note.facts, []);
  same(note.original_name, null);
  same(note.revisit, "모르겠음");
});

Deno.test("note: each kind has its own rows", () => {
  const tastes = [
    "revisit:wouldAcceptAgain",
    "reaction:taste:sweetness:liked",
    "reaction:taste:acidity:liked",
    "reaction:taste:bitterness:liked",
  ];
  const base = {
    region: null,
    ingredients: [],
    grapeVarietyKeys: [],
    levelRefs: {},
    descriptors: [],
  };
  // A whisky: the age and the casks; its 단맛 is the answer, never a mark.
  const whisky = noteOf(tastes, {
    ...base,
    name: "발베니 더블우드 12년",
    category: "whisky",
    styleKey: "single_malt_whisky",
    abv: 40,
    processes: ["wooden_cask", "ex_sherry_cask", "cask_finishing"],
    levels: { sweetness: 4, body: 3 },
  }, { style_label: "싱글 몰트 위스키", producer: "발베니", age_years: 12 });
  same(whisky.facts, [
    { label: "생산자", value: "발베니" },
    { label: "숙성", value: "12년" },
    { label: "캐스크", value: "셰리 캐스크 · 캐스크 피니시" },
  ]);
  same(whisky.balance[0], {
    key: "sweetness",
    label: "단맛",
    mark: null,
    word: null,
    felt: "liked",
    said: "좋았어요",
  });
  same(whisky.balance.at(-1)?.label, "바디");
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

  // A sparkling wine trades 타닌 for 탄산; a white wine has no 타닌 row.
  const sparkling = noteOf(tastes, {
    ...base,
    name: "모엣 샹동",
    category: "wine",
    styleKey: "sparkling_wine",
    abv: 12,
    processes: [],
    levels: { sweetness: 1, astringency: 1, carbonation: 4, body: 2 },
  });
  same(sparkling.balance.map((row) => row.label), [
    "당도",
    "산도",
    "쓴맛",
    "탄산",
    "바디",
  ]);
  const white = noteOf(tastes, {
    ...base,
    name: "샤블리",
    category: "wine",
    styleKey: "white_wine",
    abv: 12.5,
    processes: [],
    levels: { sweetness: 1, astringency: 1, body: 2 },
  });
  assert(
    !white.balance.some((row) => row.label === "타닌"),
    JSON.stringify(white.balance),
  );

  // A still sake's 탄산 1 is no row.
  const sake = noteOf(tastes, {
    ...base,
    name: "닷사이 45",
    category: "sake",
    styleKey: "junmai_daiginjo",
    abv: 16,
    processes: [],
    levels: { sweetness: 3, body: 2, carbonation: 1 },
  });
  same(sake.balance.map((row) => row.label), ["단맛", "산미", "쓴맛", "바디"]);
  same(sake.balance[0].word, null);
  same(sake.appearance, null);
  same(sake.serving?.label, "음용 온도");
  same(sake.serving?.options.map((o) => [o.label, o.short]), [
    ["차갑게(레이슈)", "레이슈"],
    ["상온", undefined],
    ["미지근하게(누루칸)", "누루칸"],
    ["따뜻하게(아쓰캉)", "아쓰캉"],
  ]);

  // A 탁주 names its ingredients and reads its marks in plain words.
  const takju = noteOf(tastes, {
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
  same(takju.balance.map((row) => [row.label, row.word]), [
    ["단맛", "단 편"],
    ["산미", "산미가 은은한 편"],
    ["쓴맛", null],
    ["탄산", "탄산이 거의 없는 편"],
    ["바디", "조금 묵직한 편"],
  ]);

  // A 증류식 소주 says how it was distilled; it has no 탄산 row.
  const soju = noteOf(tastes, {
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
  assert(
    !soju.balance.some((row) => row.label === "탄산"),
    JSON.stringify(soju.balance),
  );
});

Deno.test("note: the redraw words say of each answer what the sheet would", () => {
  const words = noteWords();
  // A thing was liked or it was not: no middle group.
  same(words.groups.map((group) => group.label), [
    "마음에 들었어요",
    "부담됐어요",
  ]);
  // Six sensations named, liked or minded, and six finishes; three tastes
  // liked or minded, each with its four reasons; four revisits.
  same(
    [words.marks, words.taste, words.revisit].map((w) => Object.keys(w).length),
    [24, 30, 4],
  );
  // A sensation only named reads as liked.
  same(words.marks["notice:mouthfeel:heavy"], {
    label: "묵직함",
    felt: "liked",
  });
  same(words.marks["reaction:mouthfeel:drying:disliked"], {
    label: "떫음",
    felt: "less",
  });
  same(words.marks["finish:offFlavor"], {
    label: "삼킨 뒤 올라오는 잡내",
    felt: "less",
  });
  same(words.taste["reason:taste:sweetness:liked:gentle"], {
    felt: "liked",
    said: "은은해서 좋았어요",
  });
  same(words.revisit["revisit:doNotWantAgain"], "없음");
  // What a whole record's sheet says is what its answers' words say.
  const note = noteOf([
    "revisit:wantAgain",
    "reaction:taste:bitterness:disliked",
    "reason:taste:bitterness:disliked:too_strong",
    "notice:mouthfeel:heavy",
    "reaction:mouthfeel:heavy:liked",
    "finish:pleasantLength",
  ], red);
  same(
    note.balance.find((row) => row.label === "쓴맛")?.said,
    words.taste["reason:taste:bitterness:disliked:too_strong"].said,
  );
  same(note.texture[0].marks[0], words.marks["reaction:mouthfeel:heavy:liked"]);
  same(note.finish[0].marks[0], words.marks["finish:pleasantLength"]);

  // The order the marks come in, whatever order they were chosen in.
  same(words.order, [
    "notice:mouthfeel:warmth",
    "notice:mouthfeel:heavy",
    "notice:mouthfeel:light",
    "notice:mouthfeel:bubbles",
    "notice:mouthfeel:drying",
    "notice:mouthfeel:smooth",
    "finish:pleasantLength",
    "finish:clean",
    "finish:tooShort",
    "finish:heavy",
    "finish:aromaEcho",
    "finish:offFlavor",
  ]);
  const chosenBackwards = noteOf([
    "revisit:wantAgain",
    "notice:mouthfeel:smooth",
    "notice:mouthfeel:light",
    "notice:mouthfeel:warmth",
    "finish:aromaEcho",
    "finish:pleasantLength",
  ], red);
  same(
    chosenBackwards.texture[0].marks,
    ["warmth", "light", "smooth"].map((key) =>
      words.marks[`notice:mouthfeel:${key}`]
    ),
  );
  same(
    chosenBackwards.finish[0].marks,
    ["pleasantLength", "aromaEcho"].map((key) => words.marks[`finish:${key}`]),
  );
});
