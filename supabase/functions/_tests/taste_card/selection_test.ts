import { regionPath } from "../../_shared/taste_card/dictionary/dictionary.ts";
import {
  type EvidenceResult,
  findEvidence,
} from "../../_shared/taste_card/evidence/evidence.ts";
import { prepareCard } from "../../_shared/taste_card/prepare/prepare.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
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
  const prepared = prepareCard(recordFrom("selection", keys, product));
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
  return `${by} ← ${from.join(", ")}`;
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

Deno.test("결과 선정: what one cause explains of several answers is one reason, the most felt answer first", () => {
  const { found, picked } = selected(
    [
      "level:finish_length:4:liked",
      "level:body:5:liked",
      "aroma:nose:violet:liked",
    ],
    MALBEC,
  );
  same(picked.liked.reasons.map((r) => told(found, r)), [
    "grape:malbec ← body:5 explain, finish_length:4 explain, aroma:violet aroma_origin",
  ]);
  const [reason] = picked.liked.reasons;
  same(reason.felt, 3);
  same(reason.closeness, 3);
  same(reason.answers, [
    "level:body:5:liked",
    "level:finish_length:4:liked",
    "aroma:nose:violet:liked",
  ]);
  same(picked.burden, { reasons: [], unexplained: [] });
});

Deno.test("결과 선정: an aroma the cause explains keeps a place among its three answers", () => {
  const { found, picked } = selected(
    [
      "level:body:5:liked",
      "level:finish_length:4:liked",
      "level:acidity:2:liked",
      "level:tannin:4:liked",
      "aroma:nose:violet:liked",
    ],
    MALBEC,
  );
  const [reason] = picked.liked.reasons;
  same(reason.told_by, { factor: "grape", key: "malbec" });
  same(reason.answers.length, 3);
  same(reason.answers[0], "level:body:5:liked");
  same(reason.answers[2], "aroma:nose:violet:liked");
  assert(
    found.evidence.filter((e) => e.causes[0]?.key === "malbec").length > 3,
    "the grape explains more than three answers",
  );
});

Deno.test("결과 선정: a section tells two reasons at most, each of its own reaction", () => {
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
    "region_style:barolo_red ← body:4 explain, aroma:rose aroma_origin",
  ]);
  same(picked.burden.reasons.map((r) => told(found, r)), [
    "region_style:barolo_red ← tannin:5 explain, acidity:4 explain",
  ]);
  for (const section of ["liked", "burden"] as const) {
    assert(picked[section].reasons.length <= 2, "two at most");
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

Deno.test("결과 선정: a cause tells one reason; a second by the same cause is another kind of finding", () => {
  // 말벡 is dry: a middle sweetness is felt differently, and that is told
  // beside what the grape explains, though both are told by the grape.
  const { found, picked } = selected(
    ["level:body:5:liked", "level:sweetness:3:liked"],
    MALBEC,
  );
  same(picked.liked.reasons.map((r) => told(found, r)), [
    "grape:malbec ← body:5 explain",
    "grape:malbec ← sweetness:3 felt_differently",
  ]);
  same(picked.liked.reasons.map((r) => r.felt), [3, 1]);
});

Deno.test("결과 선정: a cause a step off the answer makes no reason, however much the answer was felt", () => {
  // 약주 is of middle weight and low acidity: the end-step body is only
  // placed beside the kind, the milder acidity answer is explained.
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
    "kind:yakju ← acidity:2 explain",
  ]);
  same(picked.liked.reasons[0].closeness, 2);
  same(picked.liked.unexplained, ["level:body:5:liked"]);
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

Deno.test("결과 선정: an answer without a reason to give is listed, the most felt first", () => {
  // A red wine known by its kind alone: a red is dry, and of middle weight
  // and grip, so the heavy and the gripping answers are only placed.
  const { found, picked } = selected(
    ["level:sweetness:1:liked", "level:tannin:4:liked", "level:body:5:liked"],
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
    ],
  );
  same(picked.liked.reasons.map((r) => told(found, r)), [
    "kind:red_wine ← sweetness:1 kind_tendency",
  ]);
  same(picked.liked.reasons[0].closeness, 1);
  same(picked.liked.unexplained, [
    "level:body:5:liked",
    "level:tannin:4:liked",
  ]);
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
