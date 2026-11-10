import { recordFrom } from "../helpers/card_fixture_record.ts";
import { buildCardFacts } from "../../_shared/taste_card/findings/conclusions.ts";
import { writeSummary } from "../../_shared/taste_card/summary/summary.ts";
import { writeSection } from "../../_shared/taste_card/writing/sections.ts";
import {
  FIXTURE_DISPLAY_NAMES,
  fixtureRecord,
  fixtures,
} from "../helpers/card_fixture_record.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}
function equal(actual: unknown, expected: unknown, message = "") {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) {
    throw new Error(`${message}\n  actual:   ${a}\n  expected: ${b}`);
  }
}

async function summaries() {
  const out = new Map<string, ReturnType<typeof writeSummary>>();
  for (const [name, fixture] of await fixtures()) {
    const facts = buildCardFacts(fixtureRecord(name, fixture));
    const productName = FIXTURE_DISPLAY_NAMES[fixture.record.product_name];
    const options = productName ? { productName } : {};
    out.set(
      name.replace(/\.json$/, ""),
      writeSummary(
        facts,
        writeSection(facts, "positive", options),
        writeSection(facts, "burden", options),
        options,
      ),
    );
  }
  return out;
}

const KINDS = ["liked", "less", "burden", "more", "fine"];

Deno.test("card summary: every BP card gets one to three tags and one whole line", async () => {
  for (const [name, summary] of await summaries()) {
    assert(summary, `${name}: a card with answers has a summary`);
    assert(
      summary.tags.length >= 1 && summary.tags.length <= 3,
      `${name}: ${summary.tags.length} tags`,
    );
    for (const tag of summary.tags) {
      assert(KINDS.includes(tag.kind), `${name}: tag kind ${tag.kind}`);
      assert(
        tag.label && !tag.label.includes(" ") && !tag.label.startsWith("#"),
        `${name}: tag label ${tag.label}`,
      );
    }
    const line = summary.line;
    assert(!/[{}]|undefined|null/.test(line), `${name}: unfilled: ${line}`);
    assert(!line.includes("\n"), `${name}: one line: ${line}`);
    assert(/요[.?!]$/.test(line), `${name}: 해요체: ${line}`);
    const brief = summary.brief;
    assert(
      brief && !/[{}*\n]|undefined|null/.test(brief),
      `${name}: brief: ${brief}`,
    );
    assert(/요[.?!]$/.test(brief), `${name}: brief 해요체: ${brief}`);
    assert(brief.length < line.length, `${name}: brief shorter: ${brief}`);
    // The sensations are marked for the app to set in bold, in pairs.
    const marks = line.split("**").length - 1;
    assert(marks >= 2 && marks % 2 === 0, `${name}: emphasis marks: ${line}`);
    // Liked tags come first, then burdens, then lacks.
    const order = summary.tags.map((t) =>
      t.kind === "liked" ? 0 : t.kind === "more" ? 2 : 1
    );
    equal(order, [...order].sort(), `${name}: tag order ${summary.tags}`);
  }
});

/** Where a word first appears in the line, or -1. */
const at = (line: string, word: string) => line.indexOf(word);

Deno.test("card summary: BP-01 reads as agreed; the other BP lines keep their shape", async () => {
  const all = await summaries();
  const bp01 = all.get("bp-01")!;
  equal(bp01.tags, [
    { label: "체리향", kind: "liked" },
    { label: "산미", kind: "liked" },
    { label: "떫은맛", kind: "less" },
  ]);
  equal(
    bp01.line.replaceAll("**", ""),
    "싱그러운 체리 향과 침샘을 자극하는 깔끔한 산미는 매력적이지만, 입안을 꽉 조이는 떫은맛은 조금 덜어내고 싶어요.",
    "BP-01 엇갈림",
  );
  // 호감만: the liked things in one breath, no turn.
  const bp03 = all.get("bp-03")!;
  equal(bp03.shape, "호감만");
  equal(bp03.tags.map((t) => t.kind), ["liked", "liked"]);
  const line03 = bp03.line.replaceAll("**", "");
  assert(
    line03.includes("향") && line03.includes("여운") &&
      !line03.includes("지만"),
    `BP-03 호감만: ${line03}`,
  );
  // 엇갈림: the liked things, a turn, then the burden.
  const bp05 = all.get("bp-05")!;
  equal(bp05.tags.map((t) => t.kind), ["liked", "liked", "less"]);
  const line05 = bp05.line.replaceAll("**", "");
  assert(
    at(line05, "코코넛") < at(line05, "지만") &&
      at(line05, "지만") < at(line05, "알코올"),
    `BP-05 liked, then the turn, then the burden: ${line05}`,
  );
  // Two burdens are joined in one clause after the turn.
  const line13 = all.get("bp-13")!.line.replaceAll("**", "");
  assert(
    at(line13, "지만") < at(line13, "단맛") &&
      at(line13, "지만") < at(line13, "묵직") &&
      line13.split("지만").length === 2,
    `BP-13 two burdens after one turn: ${line13}`,
  );
  // A sweet aroma beside a liked sweetness: 달콤 is said once.
  const line15 = all.get("bp-15")!.line.replaceAll("**", "");
  equal(line15.split("달콤").length - 1, 1, `BP-15 달콤 once: ${line15}`);
});

/** A record from questionnaire answers and a bare product, for cases the fixtures do not hold. */
function record(answers: readonly string[], levels: Record<string, number>) {
  return recordFrom("lack", answers, {
    name: "샤또 마고",
    category: "wine",
    styleKey: "red_wine",
    region: null,
    abv: 13,
    ingredients: [],
    processes: [],
    grapeVarietyKeys: [],
    levels: levels as never,
    levelRefs: {},
    levelSources: Object.fromEntries(Object.keys(levels).map((k) => [k, 2])),
    descriptors: [],
  });
}

function write(answers: readonly string[], levels: Record<string, number>) {
  const facts = buildCardFacts(record(answers, levels));
  const positive = writeSection(facts, "positive", {});
  const burden = writeSection(facts, "burden", {});
  return writeSummary(facts, positive, burden, {})!;
}

const cherry = [
  "notice:aroma:cherry",
  "reaction:aroma:cherry:liked",
  "reason:aroma:cherry:liked:pronounced",
];
const tooWeak = [
  "reaction:taste:sweetness:disliked",
  "reason:taste:sweetness:disliked:too_weak",
];

Deno.test("card summary: 너무 약했어요 is a lack (한스푼 더), not a burden", () => {
  const dry = write(
    [
      ...cherry,
      ...tooWeak,
      "mouthfeel:unsure",
      "finish:unsure",
      "revisit:wantAgain",
    ],
    { sweetness: 1, acidity: 4, astringency: 4, aroma_intensity: 4 },
  );
  equal(dry.shape, "엇갈림");
  equal(dry.tags, [{ label: "체리향", kind: "liked" }, {
    label: "단맛",
    kind: "more",
  }]);
  const dryLine = dry.line.replaceAll("**", "");
  assert(
    at(dryLine, "체리") < at(dryLine, "단맛") &&
      !/버겁|과하|강렬/.test(dryLine),
    `a lack is asked for, not minded: ${dryLine}`,
  );
  // A burden and a lack together: both named, the lack last.
  const both = write(
    [
      ...cherry,
      ...tooWeak,
      "notice:mouthfeel:drying",
      "reaction:mouthfeel:drying:disliked",
      "finish:unsure",
      "revisit:wantAgain",
    ],
    { sweetness: 1, acidity: 4, astringency: 5, aroma_intensity: 4 },
  );
  equal(both.tags, [{ label: "체리향", kind: "liked" }, {
    label: "떫은맛",
    kind: "less",
  }, { label: "단맛", kind: "more" }]);
  const bothLine = both.line.replaceAll("**", "");
  assert(
    at(bothLine, "체리") < at(bothLine, "떫") &&
      at(bothLine, "떫") < at(bothLine, "단맛"),
    `liked, burden, then the lack: ${bothLine}`,
  );
  // Only a lack: the 부담만 shape asks for more, not less.
  const only = write(
    [
      "aroma:unsure",
      ...tooWeak,
      "mouthfeel:unsure",
      "finish:unsure",
      "revisit:unsure",
    ],
    { sweetness: 1 },
  );
  equal(only.shape, "부담만");
  equal(only.tags, [{ label: "단맛", kind: "more" }]);
  equal(
    only.line.replaceAll("**", ""),
    "단맛이 살짝 아쉬웠어요. 다음엔 단맛이 조금 더 있는 술로 가볼까요?",
  );
  // A burden and a lack with nothing liked.
  const minded = write(
    [
      "aroma:unsure",
      ...tooWeak,
      "notice:mouthfeel:drying",
      "reaction:mouthfeel:drying:disliked",
      "finish:unsure",
      "revisit:unsure",
    ],
    { sweetness: 1, astringency: 5 },
  );
  equal(minded.tags, [{ label: "떫은맛", kind: "less" }, {
    label: "단맛",
    kind: "more",
  }]);
  const mindedLine = minded.line.replaceAll("**", "");
  assert(
    at(mindedLine, "떫") < at(mindedLine, "단맛") &&
      mindedLine.endsWith("?") && mindedLine.includes("더"),
    `the burden first, then the lack asked for more: ${mindedLine}`,
  );
});

Deno.test("card summary: a sensation liked while drinking and minded in the finish is named once, the finish as 여운", () => {
  const heavy = write(
    [
      ...cherry,
      "reaction:taste:sweetness:fine",
      "notice:mouthfeel:heavy",
      "reaction:mouthfeel:heavy:liked",
      "finish:heavy",
      "revisit:unsure",
    ],
    { body: 4 },
  );
  equal(heavy.tags, [{ label: "체리향", kind: "liked" }, {
    label: "무게감",
    kind: "liked",
  }, { label: "여운", kind: "less" }]);
  assert(
    heavy.line.replaceAll("**", "").includes("입안에 오래 남는 여운") &&
      !heavy.line.includes("무게감은"),
    heavy.line,
  );
});
