import { regionPath } from "../../_shared/taste_card/dictionary/dictionary.ts";
import { findEvidence } from "../../_shared/taste_card/evidence/evidence.ts";
import { prepareCard } from "../../_shared/taste_card/prepare/prepare.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
import { selectReasons } from "../../_shared/taste_card/selection/selection.ts";
import type { TasteCardNextLine } from "../../_shared/taste_card/service/types.ts";
import { writeNext } from "../../_shared/taste_card/writing/next.ts";
import { assert, same } from "../helpers/assert.ts";
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

function next(keys: string[], product: SensoryProduct): TasteCardNextLine[] {
  const prepared = prepareCard(recordFrom("next", keys, product));
  const found = findEvidence(prepared);
  return writeNext(prepared, found, selectReasons(prepared, found))?.lines ??
    [];
}

const BURGUNDY = bottle("wine", "red_wine", {
  name: "부르고뉴 피노 누아",
  abv: 13,
  region: regionPath("fr_bourgogne"),
  grapeVarietyKeys: ["pinot_noir"],
});

const BAROLO = bottle("wine", "red_wine", {
  name: "바롤로",
  abv: 14,
  region: regionPath("it_barolo"),
  grapeVarietyKeys: ["nebbiolo"],
});

/** The names a line tells the reader to look for. */
const named = (line: TasteCardNextLine) =>
  [...line.text.matchAll(/\*\*(.+?)\*\*/g)].map((m) => m[1]);

Deno.test("다음 방향: the place that gave a minded aroma is not looked for again; two others that keep what was liked are", () => {
  const lines = next(
    [
      "level:acidity:4:liked",
      "aroma:nose:cherry:liked",
      "aroma:palate:earth:disliked",
    ],
    BURGUNDY,
  );
  // 부르고뉴 gave the acidity and the cherry, and the earth too.
  assert(lines.every((l) => !l.text.includes("부르고뉴")));
  const change = lines.at(-1)!;
  // Two to choose from, a country said in words where the name does not say
  // it, each name marked to be explained; then what both keep and what the
  // choice takes away.
  assert(
    /^(\S+의 )?\*\*[^*]+\*\*(이나|나) (\S+의 )?\*\*[^*]+\*\* (와인|품종)을 선택하시면, /
      .test(change.text),
    change.text,
  );
  assert(!/[\u{1F1E6}-\u{1F1FF}]/u.test(change.text), "no flag");
  assert(
    change.text.endsWith(
      "높은 산미와 체리 향은 그대로 살리면서 흙 향은 줄일 수 있어요.",
    ),
  );
});

Deno.test("다음 방향: every line says what choosing so does, the kept and the changed alike", () => {
  const lines = next(
    ["level:tannin:5:disliked", "level:body:4:liked"],
    BAROLO,
  );
  same(lines.map((l) => l.text), [
    // What was liked is kept by the cask it was told by and by its shop word.
    "**목재 캐스크**(Oak Aged), 14% 전후 **풀바디**를 선택하시면, 좋았던 묵직한 바디감을 그대로 가져갈 수 있어요.",
    // 그르나슈 is low in tannin; 메를로 is in the middle, less than 네비올로.
    "**그르나슈·가르나차**나 **메를로** 품종을 선택하시면, 묵직한 바디감은 그대로 살리면서 타닌은 줄일 수 있어요.",
  ]);
  // No line has a heading of its own.
  for (const line of lines) same(Object.keys(line), ["text"]);
});

Deno.test("다음 방향: with nothing liked, what gave the minded taste is said as what it is mostly like, then what to choose instead", () => {
  const lines = next(["level:tannin:5:disliked"], BAROLO);
  same(lines.length, 2);
  // Not an order to pass it by.
  same(
    lines[0].text,
    "**바롤로** 와인이나 **네비올로** 품종은 타닌이 대체로 높은 편이에요.",
  );
  assert(lines[1].text.endsWith("선택하시면, 타닌을 줄일 수 있어요."));
});

Deno.test("다음 방향: with nothing minded, the same is kept and two alike are offered", () => {
  const lines = next(
    ["level:acidity:5:liked", "aroma:nose:grapefruit:liked"],
    bottle("wine", "white_wine", {
      name: "말보로 소비뇽 블랑",
      abv: 13,
      region: regionPath("nz_marlborough"),
      grapeVarietyKeys: ["sauvignon_blanc"],
    }),
  );
  same(lines.length, 2);
  same(named(lines[0]), ["소비뇽 블랑"]);
  assert(lines[0].text.endsWith("그대로 가져갈 수 있어요."), lines[0].text);
  same(named(lines[1]).length, 2);
  assert(lines[1].text.endsWith("비슷하게 즐길 수 있어요."));
});

Deno.test("다음 방향: a grape few bottles carry is not named as what gave the minded taste", () => {
  const lines = next(
    ["level:acidity:5:disliked"],
    bottle("wine", "red_wine", { grapeVarietyKeys: ["frappato"] }),
  );
  same(lines.length, 1);
  assert(!lines[0].text.includes("프라파토"), lines[0].text);
  assert(lines[0].text.endsWith("산미를 줄일 수 있어요."));
});
