/**
 * 근거 찾기 · 감각끼리 표 (설계 부록 A): how one sense is taken for another,
 * hides it or brings it out, the same for every drink. It is read to say why
 * a reader felt a taste other than the bottle's identity leads one to expect
 * (다르게 느낀 이유), to say beside an explanation what the reader's other
 * answers did in the glass, and its aroma rows (나-8, 나-9) for what a picked
 * aroma did (향의 작용).
 *
 * A row holds only when something says the other sense was there, strongest
 * first: an answer the reader gave (1), a fact of the bottle (2), what the
 * bottle's identity usually has (3). A level or tag the seller wrote never
 * makes a row hold on its own. A row only ever says it could be so.
 */
import {
  aromaTraits,
  type Strength,
} from "../../record_reading/dictionary/dictionary.ts";
import type { GaugeAxis } from "../../record_reading/facts/facts.ts";
import type { Answers, GaugeLine } from "../../record_reading/answers.ts";
import type { Factor, Identity, Side } from "./identity.ts";

/** What says the other sense was there: 1 an answer, 2 a fact of the bottle, 3 a tendency. */
export type By = { said: string; strength: 1 | 2 | 3 };

export type PerceptionRow = {
  row: string;
  name: string;
  /** How strongly the row works, as researched. */
  strength: Strength;
  by: readonly By[];
};

const ROW_STRENGTH: Readonly<Record<string, Strength>> = {
  "가-1": "strong",
  "가-2": "strong",
  "가-3": "mid",
  "가-4": "strong",
  "가-5": "mid",
  "가-6": "mid",
  "가-7": "strong",
  "가-9": "strong",
  "가-10": "weak",
  "가-11": "mid",
  "나-1": "strong",
  "나-2": "strong",
  "나-3": "mid",
  "나-4": "mid",
  "나-5": "strong",
  "나-6": "strong",
  "나-7": "weak",
  "나-8": "mid",
  "나-9": "mid",
  "다-1": "strong",
  "라-1": "strong",
  "마-1": "strong",
  "마-2": "strong",
  "마-3": "mid",
  "마-4": "mid",
  "마-5": "mid",
  "마-6": "strong",
  "마-7": "strong",
  "마-8": "strong",
  "마-9": "strong",
};

/** Which way the feeling went from the bottle's tendency. */
export type Direction = "higher" | "lower";

/** All a row may look at. */
export type PerceptionContext = {
  drink: string;
  kind: string | null;
  identity: Identity;
  answers: Answers;
  /** The bottle's ABV is in the upper part of its kind's usual range (or it is cask strength). */
  strong: boolean;
  /** The bottle is a sparkling wine or a 탁주. */
  fizzy: boolean;
  /** The ABV the bottle states, for what a row says. */
  abv: number | null;
  /** The bottle's processes and casks, as the catalog states them. */
  processes: readonly string[];
};

/* ------------------------------------------------------------ reading */

/** The reader's answer on another gauge, if any. */
function answered(ctx: PerceptionContext, axis: GaugeAxis): GaugeLine | null {
  return ctx.answers.gauges.find((g) => g.axis === axis) ?? null;
}

const DICT_AXIS: Readonly<Partial<Record<GaugeAxis, string>>> = {
  tannin: "astringency",
  sparkling: "carbonation",
};

/** A gauge's axis as the dictionary names it. */
export function dictAxis(axis: GaugeAxis): string {
  return DICT_AXIS[axis] ?? axis;
}

/** The side the bottle's identity leads one to expect on an axis: its first cause that says one. */
export function expectedSide(
  identity: Identity,
  axis: GaugeAxis,
): { side: Side; by: Factor } | null {
  for (const f of identity.factors) {
    const t = f.taste[dictAxis(axis)];
    if (t && !t.varies) return { side: t.side, by: f };
  }
  return null;
}

/** Something says the axis was on that side: the reader's answer, else the identity's tendency. */
function sideSaid(
  ctx: PerceptionContext,
  axis: GaugeAxis,
  sides: readonly Side[],
): By[] {
  const line = answered(ctx, axis);
  if (line) {
    return sides.includes(line.side)
      ? [{ said: `answer:${axis}:${line.level}`, strength: 1 }]
      : [];
  }
  const expected = expectedSide(ctx.identity, axis);
  return expected && sides.includes(expected.side)
    ? [{
      said: `${expected.by.factor}:${expected.by.key}:${
        dictAxis(axis)
      }:${expected.side}`,
      strength: 3,
    }]
    : [];
}

const HIGH: readonly Side[] = ["high"];
const LOW: readonly Side[] = ["low", "none"];

/** Picked aromas with a trait (any of them). */
function pickedWith(
  ctx: PerceptionContext,
  traits: readonly string[],
  test?: (t: readonly string[]) => boolean,
): By[] {
  const out: By[] = [];
  for (const a of ctx.answers.aromas) {
    const own = aromaTraits(a.aroma);
    if (test ? test(own) : own.some((t) => traits.includes(t))) {
      out.push({ said: `aroma:${a.aroma}`, strength: 1 });
    }
  }
  return dedupe(out);
}

/** Aromas the identity's rows name with a trait, or every aroma of one origin. */
function identityAromas(
  ctx: PerceptionContext,
  test: (key: string, origin: string) => boolean,
): By[] {
  const out: By[] = [];
  for (const f of ctx.identity.factors) {
    for (const [origin, keys] of Object.entries(f.aromas)) {
      for (const key of keys) {
        if (test(key, origin)) {
          out.push({ said: `${f.factor}:${f.key}:${key}`, strength: 3 });
        }
      }
    }
  }
  return dedupe(out);
}

function dedupe(list: By[]): By[] {
  const seen = new Set<string>();
  return list.filter((b) => !seen.has(b.said) && (seen.add(b.said), true));
}

const hasTrait = (traits: readonly string[]) => (key: string) =>
  aromaTraits(key).some((t) => traits.includes(t));

const RIPE = (t: readonly string[]) =>
  t.includes("fruit_scent") &&
  (t.includes("concentrated_scent") || t.includes("sweet_scent"));

const FERMENTED_NOT = new Set(["distilled_soju", "diluted_soju"]);
const SPIRIT = (ctx: PerceptionContext) =>
  ctx.drink === "whisky" || ctx.kind === "distilled_soju";
const FIZZ_DRINK = (ctx: PerceptionContext) =>
  ctx.kind === "sparkling_wine" || ctx.kind === "takju";
const TANNIC_DRINK = (ctx: PerceptionContext) =>
  ctx.drink === "wine" || ctx.drink === "korean_traditional";
const fact = (said: string): By => ({ said, strength: 2 });

/* --------------------------------------------------------------- rows */

type Row = {
  row: string;
  name: string;
  felt: GaugeAxis;
  direction: Direction;
  applies?: (ctx: PerceptionContext) => boolean;
  check: (ctx: PerceptionContext) => By[];
};

const ROWS: readonly Row[] = [
  {
    row: "가-1",
    name: "단 향 → 단맛",
    felt: "sweetness",
    direction: "higher",
    check: (ctx) => [
      ...pickedWith(ctx, ["sweet_scent"]),
      ...identityAromas(ctx, hasTrait(["sweet_scent"])),
    ],
  },
  {
    row: "가-2",
    name: "익은 과일 향 → 단맛",
    felt: "sweetness",
    direction: "higher",
    check: (ctx) => [
      ...pickedWith(ctx, [], RIPE),
      ...identityAromas(
        ctx,
        (key, origin) => origin === "ripeness" || RIPE(aromaTraits(key)),
      ),
      ...ctx.identity.factors.filter((f) =>
        f.climate === "warm" || f.climate === "hot"
      )
        .map((f): By => ({
          said: `${f.factor}:${f.key}:climate:${f.climate}`,
          strength: 3,
        })),
    ],
  },
  {
    row: "가-3",
    name: "적당히 높은 도수 → 단맛",
    felt: "sweetness",
    direction: "higher",
    applies: (ctx) =>
      ctx.drink !== "whisky" && !FERMENTED_NOT.has(ctx.kind ?? ""),
    // Alcohol rounds a taste toward sweet from about 13% to 18%; above
    // that its heat comes first.
    check: (ctx) =>
      ctx.strong && (ctx.abv === null || (ctx.abv >= 13 && ctx.abv <= 18))
        ? [fact(`abv:${ctx.abv ?? "high"}`)]
        : [],
  },
  {
    row: "가-4",
    name: "진득한 질감 → 단맛",
    felt: "sweetness",
    direction: "higher",
    check: (ctx) => sideSaid(ctx, "body", HIGH),
  },
  {
    row: "가-5",
    name: "탄산 → 산미",
    felt: "acidity",
    direction: "higher",
    applies: FIZZ_DRINK,
    check: (ctx) => {
      const line = answered(ctx, "sparkling");
      if (line) {
        return line.side === "high"
          ? [{ said: `answer:sparkling:${line.level}`, strength: 1 }]
          : [];
      }
      return ctx.fizzy ? [fact(`kind:${ctx.kind}`)] : [];
    },
  },
  {
    row: "가-6",
    name: "강한 산미 → 떫음",
    felt: "tannin",
    direction: "higher",
    check: (ctx) => sideSaid(ctx, "acidity", HIGH),
  },
  {
    row: "가-7",
    name: "단맛·높은 도수 → 묵직함",
    felt: "body",
    direction: "higher",
    check: (ctx) => [
      ...sideSaid(ctx, "sweetness", HIGH),
      ...(ctx.strong ? [fact(`abv:${ctx.abv ?? "high"}`)] : []),
    ],
  },
  {
    row: "가-9",
    name: "높은 도수·매운 향 → 스파이시",
    felt: "spice",
    direction: "higher",
    applies: SPIRIT,
    check: (ctx) => [
      ...(ctx.strong ? [fact(`abv:${ctx.abv ?? "high"}`)] : []),
      ...pickedWith(ctx, ["spice_scent", "warm_scent"]),
      ...identityAromas(ctx, hasTrait(["spice_scent"])),
    ],
  },
  {
    row: "가-10",
    name: "탄 오크 향 → 피트",
    felt: "peat",
    direction: "higher",
    applies: (ctx) => ctx.drink === "whisky",
    check: (ctx) => [
      ...(ctx.processes.includes("charred_cask")
        ? [fact("making:charred_cask")]
        : []),
      ...ctx.identity.factors.filter((f) => f.factor === "cask").flatMap((f) =>
        Object.values(f.aromas).flat().filter(
          hasTrait(["smoky_scent", "toasted_scent"]),
        )
          .map((key): By => ({ said: `cask:${f.key}:${key}`, strength: 3 }))
      ),
    ],
  },
  {
    row: "가-11",
    name: "진한 향 → 긴 여운",
    felt: "finish_length",
    direction: "higher",
    check: (ctx) => [
      ...pickedWith(ctx, ["woody_scent", "smoky_scent", "concentrated_scent"]),
      ...ctx.identity.factors.filter((f) =>
        f.aroma_strength && !f.aroma_strength.varies &&
        f.aroma_strength.side === "high"
      )
        .map((f): By => ({
          said: `${f.factor}:${f.key}:aroma_strength:high`,
          strength: 3,
        })),
    ],
  },
  // 여운: what makes a finish feel short or long (조사 2026-11-20). A pair of
  // rows shares a number: the short side and the long side of one sense.
  {
    row: "마-1",
    name: "가벼운 바디 → 짧은 여운",
    felt: "finish_length",
    direction: "lower",
    check: (ctx) => sideSaid(ctx, "body", LOW),
  },
  {
    row: "마-1",
    name: "묵직한 바디 → 긴 여운",
    felt: "finish_length",
    direction: "higher",
    check: (ctx) => sideSaid(ctx, "body", HIGH),
  },
  {
    row: "마-2",
    name: "탄산이 입을 씻어 줌 → 짧은 여운",
    felt: "finish_length",
    direction: "lower",
    applies: (ctx) => ctx.drink !== "whisky",
    check: (ctx) => {
      const line = answered(ctx, "sparkling");
      return line?.side === "high"
        ? [{ said: `answer:sparkling:${line.level}`, strength: 1 }]
        : [];
    },
  },
  {
    row: "마-3",
    name: "단맛이 적음 → 짧은 여운",
    felt: "finish_length",
    direction: "lower",
    check: (ctx) => sideSaid(ctx, "sweetness", LOW),
  },
  {
    row: "마-3",
    name: "단맛 → 긴 여운",
    felt: "finish_length",
    direction: "higher",
    check: (ctx) => sideSaid(ctx, "sweetness", HIGH),
  },
  {
    row: "마-4",
    name: "떫음이 적음 → 짧은 여운",
    felt: "finish_length",
    direction: "lower",
    applies: TANNIC_DRINK,
    check: (ctx) => sideSaid(ctx, "tannin", LOW),
  },
  {
    row: "마-4",
    name: "떫음 → 긴 여운",
    felt: "finish_length",
    direction: "higher",
    applies: TANNIC_DRINK,
    check: (ctx) => sideSaid(ctx, "tannin", HIGH),
  },
  {
    row: "마-5",
    name: "감칠맛이 적음 → 짧은 여운",
    felt: "finish_length",
    direction: "lower",
    applies: (ctx) => ctx.drink !== "whisky",
    check: (ctx) => sideSaid(ctx, "umami", LOW),
  },
  {
    row: "마-5",
    name: "감칠맛 → 긴 여운",
    felt: "finish_length",
    direction: "higher",
    applies: (ctx) => ctx.drink !== "whisky",
    check: (ctx) => sideSaid(ctx, "umami", HIGH),
  },
  {
    row: "마-6",
    name: "옅은 향 → 짧은 여운",
    felt: "finish_length",
    direction: "lower",
    // The questionnaire asks no strength of aroma: only the bottle's rows say it.
    check: (ctx) =>
      ctx.identity.factors.filter((f) =>
        f.aroma_strength && !f.aroma_strength.varies &&
        f.aroma_strength.side === "low"
      )
        .map((f): By => ({
          said: `${f.factor}:${f.key}:aroma_strength:low`,
          strength: 3,
        })),
  },
  {
    row: "마-7",
    name: "높은 도수 → 긴 여운",
    felt: "finish_length",
    direction: "higher",
    check: (ctx) => ctx.strong ? [fact(`abv:${ctx.abv ?? "high"}`)] : [],
  },
  {
    row: "마-8",
    name: "높은 산미 → 긴 여운",
    felt: "finish_length",
    direction: "higher",
    applies: (ctx) => ctx.drink !== "whisky",
    check: (ctx) => sideSaid(ctx, "acidity", HIGH),
  },
  {
    row: "마-9",
    name: "피트 → 긴 여운",
    felt: "finish_length",
    direction: "higher",
    applies: (ctx) => ctx.drink === "whisky",
    check: (ctx) => sideSaid(ctx, "peat", HIGH),
  },
  {
    row: "나-1",
    name: "단맛이 산미를 감쌈",
    felt: "acidity",
    direction: "lower",
    applies: (ctx) => ctx.drink !== "whisky",
    check: (ctx) => sideSaid(ctx, "sweetness", HIGH),
  },
  {
    row: "나-1",
    name: "단맛이 없어 산미가 드러남",
    felt: "acidity",
    direction: "higher",
    applies: (ctx) => ctx.drink !== "whisky",
    check: (ctx) => sideSaid(ctx, "sweetness", LOW),
  },
  {
    row: "나-2",
    name: "산미·떫음이 단맛을 가림",
    felt: "sweetness",
    direction: "lower",
    applies: (ctx) => ctx.drink !== "whisky",
    check: (
      ctx,
    ) => [...sideSaid(ctx, "acidity", HIGH), ...sideSaid(ctx, "tannin", HIGH)],
  },
  {
    row: "나-2",
    name: "산미·떫음이 순해 단맛이 드러남",
    felt: "sweetness",
    direction: "higher",
    applies: (ctx) => ctx.drink !== "whisky",
    check: (ctx) => {
      // Both soft: the acidity, and the astringency where the bottle has any.
      const acid = sideSaid(ctx, "acidity", LOW);
      const tannin = sideSaid(ctx, "tannin", LOW);
      const hasTannin = !!answered(ctx, "tannin") ||
        !!expectedSide(ctx.identity, "tannin");
      return acid.length && (!hasTannin || tannin.length)
        ? [...acid, ...tannin]
        : [];
    },
  },
  {
    row: "나-3",
    name: "탄산이 단맛을 가림",
    felt: "sweetness",
    direction: "lower",
    applies: FIZZ_DRINK,
    check: (ctx) => {
      const line = answered(ctx, "sparkling");
      if (line) {
        return line.side === "high"
          ? [{ said: `answer:sparkling:${line.level}`, strength: 1 }]
          : [];
      }
      return ctx.fizzy ? [fact(`kind:${ctx.kind}`)] : [];
    },
  },
  {
    row: "나-4",
    name: "묵직함이 산미를 덮음",
    felt: "acidity",
    direction: "lower",
    applies: (ctx) => ctx.drink !== "whisky",
    check: (ctx) => sideSaid(ctx, "body", HIGH),
  },
  {
    row: "나-5",
    name: "단맛·진득함이 떫음을 감쌈",
    felt: "tannin",
    direction: "lower",
    check: (
      ctx,
    ) => [...sideSaid(ctx, "sweetness", HIGH), ...sideSaid(ctx, "body", HIGH)],
  },
  {
    row: "나-5",
    name: "단맛이 없어 떫음이 드러남",
    felt: "tannin",
    direction: "higher",
    check: (ctx) => sideSaid(ctx, "sweetness", LOW),
  },
  {
    row: "나-6",
    name: "단맛·묵직함이 알코올 자극을 감쌈",
    felt: "spice",
    direction: "lower",
    applies: SPIRIT,
    check: (
      ctx,
    ) => [...sideSaid(ctx, "sweetness", HIGH), ...sideSaid(ctx, "body", HIGH)],
  },
  {
    row: "나-6",
    name: "단맛·묵직함이 없어 자극이 드러남",
    felt: "spice",
    direction: "higher",
    applies: SPIRIT,
    check: (ctx) => {
      const sweet = sideSaid(ctx, "sweetness", LOW);
      const body = sideSaid(ctx, "body", LOW);
      return sweet.length && body.length ? [...sweet, ...body] : [];
    },
  },
  {
    row: "나-7",
    name: "단맛·묵직함이 탄산을 둥글림",
    felt: "sparkling",
    direction: "lower",
    applies: FIZZ_DRINK,
    check: (
      ctx,
    ) => [...sideSaid(ctx, "sweetness", HIGH), ...sideSaid(ctx, "body", HIGH)],
  },
  {
    row: "나-7",
    name: "단맛·묵직함이 없어 탄산이 드러남",
    felt: "sparkling",
    direction: "higher",
    applies: FIZZ_DRINK,
    check: (ctx) => {
      const sweet = sideSaid(ctx, "sweetness", LOW);
      const body = sideSaid(ctx, "body", LOW);
      return sweet.length && body.length ? [...sweet, ...body] : [];
    },
  },
  {
    row: "다-1",
    name: "탄산·산미 → 가벼움",
    felt: "body",
    direction: "lower",
    applies: (ctx) => ctx.drink !== "whisky",
    check: (ctx) => {
      const line = answered(ctx, "sparkling");
      const fizz = line
        ? (line.side === "high"
          ? [{ said: `answer:sparkling:${line.level}`, strength: 1 } as By]
          : [])
        : ctx.fizzy
        ? [fact(`kind:${ctx.kind}`)]
        : [];
      return [...fizz, ...sideSaid(ctx, "acidity", HIGH)];
    },
  },
  {
    row: "라-1",
    name: "전통 주모·진한 술 → 감칠맛",
    felt: "umami",
    direction: "higher",
    // Only where the grade itself has little umami (긴조·다이긴조); a grade
    // rich in it explains the feeling by itself.
    applies: (ctx) =>
      ctx.drink === "sake" && ["ginjo", "daiginjo"].includes(ctx.kind ?? ""),
    check: (ctx) => [
      ...ctx.processes.filter((p) =>
        [
          "kimoto_starter",
          "yamahai_starter",
          "undiluted",
          "unfiltered_claim",
          "unpasteurised",
          "coarse_filtered",
        ]
          .includes(p)
      ).map((p) => fact(`making:${p}`)),
      ...pickedWith(ctx, ["nutty_scent", "savory_scent"]),
    ],
  },
];

const STRENGTH_ORDER = (a: By, b: By) => a.strength - b.strength;

/**
 * The rows that say why the reader felt `axis` higher or lower than the
 * identity leads one to expect, strongest support first, then by row number.
 */
export function perceptionRows(
  ctx: PerceptionContext,
  axis: GaugeAxis,
  direction: Direction,
): PerceptionRow[] {
  const held: PerceptionRow[] = [];
  for (const r of ROWS) {
    if (r.felt !== axis || r.direction !== direction) continue;
    if (r.applies && !r.applies(ctx)) continue;
    const by = dedupe(r.check(ctx)).sort(STRENGTH_ORDER);
    if (by.length) {
      held.push({
        row: r.row,
        name: r.name,
        strength: ROW_STRENGTH[r.row],
        by,
      });
    }
  }
  return held.sort((a, b) => a.by[0].strength - b.by[0].strength);
}

/* -------------------------------------------------------- aroma rows */

/**
 * What a picked aroma's surroundings did to it (나-8, 나-9): little
 * astringency let a fruit aroma through; a modest strength let a delicate
 * one through. Read for a liked aroma only: a picked aroma says nothing of
 * how strongly it was there, and a minded one was there anyway.
 */
export function aromaRows(
  ctx: PerceptionContext,
  aroma: string,
): PerceptionRow[] {
  const traits = aromaTraits(aroma);
  const out: PerceptionRow[] = [];
  if (ctx.drink === "wine" && traits.includes("fruit_scent")) {
    const by = sideSaid(ctx, "tannin", LOW);
    if (by.length) {
      out.push({
        row: "나-8",
        name: "떫음이 적어 과일 향이 드러남",
        strength: ROW_STRENGTH["나-8"],
        by,
      });
    }
  }
  const delicate = traits.some((t) =>
    ["floral_scent", "fresh_scent", "fruit_scent"].includes(t)
  );
  if (delicate && ctx.abv !== null && !ctx.strong && ctx.drink !== "whisky") {
    out.push({
      row: "나-9",
      name: "도수가 높지 않아 섬세한 향이 드러남",
      strength: ROW_STRENGTH["나-9"],
      by: [fact(`abv:${ctx.abv}`)],
    });
  }
  return out;
}
