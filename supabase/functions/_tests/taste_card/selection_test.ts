import { regionPath } from "../../_shared/record_reading/dictionary/dictionary.ts";
import {
  type EvidenceResult,
  findEvidence,
} from "../../_shared/taste_card/evidence/evidence.ts";
import { readRecord } from "../../_shared/record_reading/read_record.ts";
import type { SensoryProduct } from "../../_shared/record_reading/record/sensory_record.ts";
import {
  type Reason,
  type Selection,
  selectReasons,
} from "../../_shared/taste_card/selection/selection.ts";
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

function selected(
  keys: string[],
  product: SensoryProduct,
): { found: EvidenceResult; picked: Selection } {
  const prepared = readRecord(recordFrom("selection", keys, product));
  const found = findEvidence(prepared);
  return { found, picked: selectReasons(prepared, found) };
}

/** "grape:malbec ← body:5 explain, finish_length:4 explain" */
function told(found: EvidenceResult, reason: Reason): string {
  const from = reason.evidence.map((id) => {
    const e = found.evidence.find((x) => x.id === id)!;
    const a = e.answer.kind === "gauge"
      ? `${e.answer.axis}:${e.answer.level}`
      : `aroma:${e.answer.aroma}`;
    return `${a} ${e.type}`;
  });
  const by = reason.told_by
    ? `${reason.told_by.factor}:${reason.told_by.key}`
    : "none";
  // A reason nothing explains is told from what was felt: its answer is shown.
  const felt = reason.answers.map((ref) => ref.split(":").slice(1, 3).join(":"))
    .join(", ");
  return `${by} ← ${from.length ? from.join(", ") : `felt ${felt}`}`;
}

const MALBEC = bottle("wine", "red_wine", {
  name: "멘델 말벡 2020",
  abv: 14.5,
  region: regionPath("ar_mendoza"),
  grapeVarietyKeys: ["malbec"],
});

const BAROLO = bottle("wine", "red_wine", {
  name: "바롤로 2019",
  abv: 14,
  region: regionPath("it_barolo"),
  grapeVarietyKeys: ["nebbiolo"],
});

const YAKJU = bottle("korean_traditional", "yakju", { name: "약주" });

Deno.test("결과 선정: a reason speaks of one answer, the most felt first, and two answers one cause explains are told by two causes", () => {
  const { found, picked } = selected(
    [
      "level:finish_length:4:liked",
      "level:body:5:liked",
      "aroma:nose:violet:liked",
    ],
    MALBEC,
  );
  // 말벡 explains all three. The end step leads and is told by the oak, a
  // cause of the bottle's own that says the same; the aroma by the grape.
  same(picked.liked.reasons.map((r) => told(found, r)), [
    "making:european_oak ← body:5 explain",
    "grape:malbec ← aroma:violet aroma_origin",
  ]);
  const [reason] = picked.liked.reasons;
  same(reason.felt, 3);
  same(reason.closeness, 3);
  same(reason.answers, ["level:body:5:liked"]);
  same(picked.liked.untold, ["level:finish_length:4:liked"]);
  same(picked.burden, { reasons: [], untold: [] });
});

Deno.test("결과 선정: a section tells two reasons at most, each of its own reaction, and lists the rest", () => {
  const five = selected(
    [
      "level:body:5:liked",
      "level:finish_length:4:liked",
      "level:acidity:2:liked",
      "level:tannin:4:liked",
      "aroma:nose:violet:liked",
    ],
    MALBEC,
  );
  same(five.picked.liked.reasons.length, 2);
  same(five.picked.liked.untold, [
    "level:acidity:2:liked",
    "level:tannin:4:liked",
    "level:finish_length:4:liked",
  ]);
  assert(
    five.found.evidence.filter((e) => e.causes[0]?.key === "malbec").length >
      3,
    "the grape explains more than three answers",
  );

  const { found, picked } = selected(
    [
      "level:tannin:5:disliked",
      "level:acidity:4:disliked",
      "level:body:4:liked",
      "aroma:nose:rose:liked",
    ],
    BAROLO,
  );
  same(picked.liked.reasons.map((r) => told(found, r)), [
    "making:wooden_cask ← body:4 explain",
    "region_style:barolo_red ← aroma:rose aroma_origin",
  ]);
  // 바롤로 tells the tannin, so the acidity is told by the grape.
  same(picked.burden.reasons.map((r) => told(found, r)), [
    "region_style:barolo_red ← tannin:5 explain",
    "grape:nebbiolo ← acidity:4 explain",
  ]);
  for (const section of ["liked", "burden"] as const) {
    for (const reason of picked[section].reasons) {
      same(reason.section, section);
      for (const ref of reason.answers) {
        assert(
          ref.endsWith(section === "liked" ? ":liked" : ":disliked"),
          `${ref} in ${section}`,
        );
      }
    }
  }
});

Deno.test("결과 선정: an answer the bottle's causes are at odds over is told from what was felt", () => {
  // The bourbon cask explains the sweetness. That the whisky felt light is
  // the same cask against the sherry cask: nothing of the bottle says light.
  const { found, picked } = selected(
    ["level:sweetness:4:liked", "level:body:2:liked"],
    bottle("whisky", "single_malt_whisky", {
      name: "버번·셰리 캐스크 싱글 몰트",
      processes: ["ex_bourbon_cask", "ex_sherry_cask"],
    }),
  );
  assert(found.evidence.some((e) => e.type === "split"), "근거 찾기 finds it");
  same(picked.liked.reasons.map((r) => told(found, r)), [
    "cask:ex_bourbon_cask ← sweetness:4 explain",
    "none ← felt body:2",
  ]);
  same(picked.liked.reasons.map((r) => r.closeness), [3, 0]);
});

Deno.test("결과 선정: a middle answer felt differently from the bottle is not told", () => {
  const { found, picked } = selected(
    ["level:body:5:liked", "level:sweetness:3:liked"],
    MALBEC,
  );
  assert(
    found.evidence.some((e) => e.type === "felt_differently"),
    "근거 찾기 still finds it",
  );
  same(picked.liked.reasons.map((r) => told(found, r)), [
    "making:european_oak ← body:5 explain",
  ]);
  same(picked.liked.untold, ["level:sweetness:3:liked"]);
});

Deno.test("결과 선정: a taste is told by a cause of the bottle's own before its kind", () => {
  const { found, picked } = selected(
    [
      "level:body:4:liked",
      "level:sweetness:4:liked",
      "level:peat:1:liked",
      "aroma:nose:raisin:liked",
    ],
    bottle("whisky", "single_malt_whisky", {
      name: "셰리 캐스크 싱글 몰트",
      processes: ["ex_sherry_cask"],
    }),
  );
  const body = found.evidence.find((e) =>
    e.answer.kind === "gauge" && e.answer.axis === "body"
  )!;
  // The kind is the first cause 근거 찾기 names, and the cask is the bottle's own.
  same(body.causes.map((c) => `${c.factor}:${c.key}`), [
    "kind:single_malt_whisky",
    "cask:ex_sherry_cask",
  ]);
  // The end step leads, and only the kind speaks of it; the sweetness is the cask's.
  same(picked.liked.reasons.map((r) => told(found, r)), [
    "kind:single_malt_whisky ← peat:1 explain",
    "cask:ex_sherry_cask ← sweetness:4 explain",
  ]);
  same(picked.liked.untold, ["level:body:4:liked", "aroma:nose:raisin:liked"]);
});

Deno.test("결과 선정: an aroma does not push out a taste that was felt more", () => {
  const { found, picked } = selected(
    [
      "level:tannin:5:liked",
      "level:acidity:5:liked",
      "level:finish_length:5:liked",
      "aroma:nose:rose:liked",
    ],
    BAROLO,
  );
  same(picked.liked.reasons.map((r) => told(found, r)), [
    "region_style:barolo_red ← tannin:5 explain",
    "grape:nebbiolo ← finish_length:5 explain",
  ]);
  same(picked.liked.untold, ["level:acidity:5:liked", "aroma:nose:rose:liked"]);
  // An aroma picked at two moments is felt as much as an end step, and leads.
  const twice = selected(
    [
      "level:body:4:liked",
      "aroma:nose:violet:liked",
      "aroma:palate:violet:liked",
    ],
    MALBEC,
  );
  same(twice.picked.liked.reasons.map((r) => told(twice.found, r)), [
    "grape:malbec ← aroma:violet aroma_origin",
    "making:european_oak ← body:4 explain",
  ]);
});

Deno.test("결과 선정: an end step most bottles of the kind sit on is not what was felt most", () => {
  // Nine red wines in ten are not sweet: the answer says the reader met a
  // red wine, so it comes last, after the aroma.
  const { found, picked } = selected(
    [
      "level:body:5:liked",
      "level:sweetness:1:liked",
      "level:finish_length:5:liked",
      "aroma:nose:violet:liked",
    ],
    MALBEC,
  );
  same(picked.liked.reasons.map((r) => told(found, r)), [
    "grape:malbec ← finish_length:5 explain",
    "making:european_oak ← body:5 explain",
  ]);
  same(picked.liked.untold, [
    "aroma:nose:violet:liked",
    "level:sweetness:1:liked",
  ]);
  // A sweet red is rare, and stays what was felt most.
  same(
    selected(["level:sweetness:5:liked", "level:body:4:liked"], MALBEC).picked
      .liked.reasons.map((r) => r.felt),
    [3, 2],
  );
});

Deno.test("결과 선정: an answer felt clearly is a reason though a cause a step off explains nothing of it", () => {
  // 약주 is of middle weight and low acidity: the end-step body is only
  // placed beside the kind, so it is told from what was felt; the milder
  // acidity answer is explained.
  const { found, picked } = selected(
    ["level:body:5:liked", "level:acidity:2:liked"],
    YAKJU,
  );
  const acidity = found.evidence.find((e) =>
    e.answer.kind === "gauge" && e.answer.axis === "acidity"
  )!;
  const body = found.evidence.find((e) =>
    e.answer.kind === "gauge" && e.answer.axis === "body"
  )!;
  same([acidity.clarity, body.clarity], ["clear", "weak"]);
  same(picked.liked.reasons.map((r) => told(found, r)), [
    "none ← felt body:5",
    "kind:yakju ← acidity:2 explain",
  ]);
  same(picked.liked.reasons.map((r) => r.closeness), [0, 2]);
  same(picked.liked.untold, []);
});

Deno.test("결과 선정: an aroma picked at two moments is one answer, felt as much as an end step", () => {
  const { found, picked } = selected(
    [
      "level:body:4:liked",
      "aroma:nose:violet:liked",
      "aroma:palate:violet:liked",
    ],
    MALBEC,
  );
  const [reason] = picked.liked.reasons;
  same(reason.felt, 3);
  same(
    told(found, reason).split(", ")[0],
    "grape:malbec ← aroma:violet aroma_origin",
  );
  same(reason.answers.slice(0, 2), [
    "aroma:nose:violet:liked",
    "aroma:palate:violet:liked",
  ]);
});

Deno.test("결과 선정: one of a section's two reasons is the bottle's where one can be; what only the glass says is listed", () => {
  // A red wine known by its kind alone: a red is dry, and of middle weight
  // and grip, so the heavy and the gripping answers are only placed. The
  // heavy end step is told from what was felt, the dry answer by the kind.
  const { found, picked } = selected(
    ["level:sweetness:2:liked", "level:tannin:4:liked", "level:body:5:liked"],
    bottle("wine", "red_wine", { name: "이름만 있는 병" }),
  );
  same(
    found.evidence.map((e) =>
      `${e.answer.kind === "gauge" ? e.answer.axis : ""} ${e.type}/${e.clarity}`
    ),
    [
      "sweetness kind_tendency/clear",
      "body kind_tendency/weak",
      "tannin kind_tendency/weak",
      "tannin in_this_glass/weak",
    ],
  );
  same(picked.liked.reasons.map((r) => told(found, r)), [
    "none ← felt body:5",
    "kind:red_wine ← sweetness:2 kind_tendency",
  ]);
  same(picked.liked.reasons.map((r) => r.closeness), [0, 1]);
  same(picked.liked.untold, ["level:tannin:4:liked"]);
});

Deno.test("결과 선정: every reason points at evidence of its own section, and no answer is told twice", () => {
  const { found, picked } = selected(
    [
      "level:body:5:liked",
      "level:tannin:4:disliked",
      "level:sweetness:3:liked",
      "level:finish_length:4:liked",
      "level:acidity:2:disliked",
      "aroma:nose:plum:liked",
      "aroma:palate:vanilla:disliked",
    ],
    MALBEC,
  );
  const seen = new Set<string>();
  for (const section of ["liked", "burden"] as const) {
    for (const reason of picked[section].reasons) {
      assert(reason.evidence.length > 0, "a reason has evidence");
      for (const id of reason.evidence) {
        const e = found.evidence.find((x) => x.id === id);
        assert(e, `${id} is evidence that was found`);
        same(e.answer.reaction, section);
      }
      for (const ref of reason.answers) {
        assert(!seen.has(ref), `${ref} told once`);
        seen.add(ref);
      }
    }
  }
});
