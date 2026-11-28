/**
 * 근거 찾기: the second stage of the 술결카드 생성 파이프라인. For every
 * answer it finds what of the bottle could be why it was felt so, as the
 * bottle's identity (identity.ts) and what the dictionary says that identity
 * is usually like. It does not choose (결과 선정) and writes no sentence
 * (글쓰기).
 *
 *   설명            the answer and a cause's tendency are on the same side
 *   엇갈림          a cause is on the answer's side while another, as much
 *                   the bottle's own, says the opposite (two casks; the
 *                   kind against its cask): both are kept, and the answer
 *                   says which of them came through
 *   이 병의 특징     no cause is on the answer's side, but the level read
 *                   for the bottle is, two steps or more from its identity
 *   다르게 느낀 이유  the answer is on the other side of what the identity
 *                   leads one to expect, past the drink's threshold, and the
 *                   table of senses (perception.ts) says what could have made
 *                   it so; one per answer, every row that held inside it
 *   이번 잔에서      nothing of the bottle is on the answer's side, but
 *                   another answer of the reader makes a row of the table of
 *                   senses hold (no sweetness, so the acidity stood out)
 *   향의 유래        a picked aroma is one the identity's rows name
 *   향의 작용        a liked aroma came through because of its surroundings
 *   종류 경향        for wine, only the kind's tendency explains the answer
 *
 * 설명 and 엇갈림 also carry the rows of the table of senses that another
 * answer of the reader or a fact of the bottle makes hold: what happened in
 * this glass, beside what the bottle is. A row only the identity's tendency
 * supports is read for 다르게 느낀 이유 alone.
 *
 * The answer is never held wrong. A level the seller wrote adds a little
 * weight (support) to evidence found otherwise, and makes evidence only as
 * 이 병의 특징, where the reader's own answer says the same. A cause whose
 * tendency runs several ways (varies) says nothing on that axis, and then
 * the kind does not speak for it either.
 */
import {
  lineNamesAroma,
  namesAroma,
} from "../../record_reading/dictionary/aromas.ts";
import { usualAbvRange } from "../../record_reading/dictionary/dictionary.ts";
import type { Relation } from "../../record_reading/dictionary/files.ts";
import {
  catalogAxis,
  catalogLevelOf,
  type GaugeAxis,
} from "../../record_reading/facts/facts.ts";
import type { BottleFacts } from "../../record_reading/bottle.ts";
import type { AromaLine, GaugeLine } from "../../record_reading/answers.ts";
import type { RecordReading } from "../../record_reading/read_record.ts";
import {
  bottleIdentity,
  type CauseOn,
  type Factor,
  type FactorKind,
  type Identity,
  type Lead,
  type Side,
  sideOf,
  type WineCase,
} from "./identity.ts";
import {
  aromaRows,
  type PerceptionContext,
  type PerceptionRow,
  perceptionRows,
} from "./perception.ts";

export type EvidenceType =
  | "explain"
  | "split"
  | "bottle_trait"
  | "felt_differently"
  | "in_this_glass"
  | "aroma_origin"
  | "aroma_effect"
  | "kind_tendency";

/** How sharply the cause and the answer meet: both pronounced, one in the middle, both middle. */
export type Clarity = "clear" | "weak" | "balance";

export type EvidenceAnswer =
  | {
    kind: "gauge";
    axis: GaugeAxis;
    level: number;
    side: Side;
    reaction: "liked" | "burden";
    weight: number;
    ref: string;
  }
  | {
    kind: "aroma";
    aroma: string;
    stage: string;
    reaction: "liked" | "burden";
    weight: number;
    ref: string;
  };

export type Cause = {
  factor: FactorKind;
  key: string;
  ko: string;
  rank: number;
  on: CauseOn;
  /** Its tendency on the answer's axis, as a step. */
  tendency?: { axis: string; step: number };
  /** The aroma word of the row the picked aroma met. */
  aroma?: string;
  /** Where the row says that aroma comes from: material, ageing, cask, yeast … */
  aroma_source?: string;
  /** How that aroma comes about, in the row's own words; empty where the row tells nothing of it. */
  aroma_how?: string;
  /** The casks the house mostly ages in, of an aroma its casks give. */
  aroma_casks?: readonly string[];
  /** The climate the grape's row names that aroma in and not in the other, when the bottle is from there. */
  aroma_climate?: "cool" | "warm" | "hot";
  climate?: string;
  /** Why the cause tastes so. */
  why?: string;
  /** A grape from a cooler or a warmer place, and what it is like there. */
  in_climate?: { side: "cooler" | "warmer"; text: string };
};

export type Guide = {
  direction: "keep" | "reduce" | "increase" | "adjust";
  axis?: GaugeAxis;
  aroma?: string;
  /** What made the feeling, for a felt-differently answer: kept or reduced instead of the axis. */
  trait?: string;
  because: string;
};

export type Evidence = {
  id: string;
  answer: EvidenceAnswer;
  type: EvidenceType;
  causes: readonly Cause[];
  /** 엇갈림: the causes that say the opposite of the answer. */
  against?: readonly Cause[];
  clarity: Clarity;
  cause_on: CauseOn;
  /** The rows of the table of senses that held. */
  perception?: { rules: readonly PerceptionRow[] };
  /** What two of the bottle's own rows do together on the answer's axis. */
  relations?: readonly Relation[];
  /** The bottle's own level on the axis, read for it, and whether it is on the answer's side. */
  support?: { axis: string; bottle: number; same_side: boolean };
  identity_key: string;
  claim_key: string;
  lead: Lead;
  guide: Guide;
};

/** An answer no evidence was found for, and why. */
export type Miss = {
  ref: string;
  reason: "varies" | "no_cause";
  /** The cause that runs several ways on the axis. */
  by?: string;
};

export type EvidenceResult = {
  evidence: readonly Evidence[];
  misses: readonly Miss[];
  identity: {
    drink: string | null;
    kind: string | null;
    lead: Lead | null;
    identity_key: string | null;
    wine_case?: WineCase;
    causes: readonly {
      factor: FactorKind;
      key: string;
      rank: number;
      on: CauseOn;
    }[];
    /** The relations of the drink this bottle meets, whatever was answered. */
    relations: readonly Relation[];
    /** Axes a cause of the bottle runs several ways on. */
    varies: readonly { axis: string; by: string }[];
  };
};

/* ------------------------------------------------------------ settings */

/**
 * How far an answer must stand from the expected step before it is felt
 * differently (설계 4-2). Sweetness is a fact of the label on wine, sake and
 * 전통주 (one step, from a tendency that is not the middle); a nuance on
 * whisky and 증류식 소주 (two). Every other axis: two.
 */
function threshold(
  drink: string,
  kind: string | null,
  axis: GaugeAxis,
): number {
  if (axis !== "sweetness") return 2;
  if (drink === "whisky" || kind === "distilled_soju") return 2;
  return 1;
}

/** The sense a felt-differently row leaves to keep or to reduce, instead of the axis. */
const TRAIT: Readonly<Record<string, string>> = {
  "가-1": "sweet_scent_sweetness",
  "가-2": "ripe_fruit_sweetness",
  "가-3": "alcohol_sweetness",
  "가-4": "texture_sweetness",
  "가-5": "bubbles_acidity",
  "가-6": "acidity_grip",
  "가-7": "sugar_alcohol_weight",
  "가-9": "alcohol_spice",
  "가-10": "charred_oak_smoke",
  "가-11": "intense_aroma_finish",
  "나-1": "sweetness_acidity_balance",
  "나-2": "acidity_tannin_sweetness_balance",
  "나-3": "bubbles_sweetness_balance",
  "나-4": "weight_acidity_balance",
  "나-5": "sweetness_tannin_balance",
  "나-6": "sweetness_weight_warmth_balance",
  "나-7": "sweetness_weight_bubbles_balance",
  "다-1": "fizz_acid_lightness",
  "라-1": "rich_sake_umami",
};

/* ------------------------------------------------------------- context */

function strongFor(bottle: BottleFacts, identity: Identity): boolean {
  if (bottle.processes.includes("cask_strength")) return true;
  if (bottle.abv?.of !== "bottle") return false;
  const range = usualAbvRange(identity.drink, identity.kind);
  if (!range || range.length < 2) return false;
  const [low, high] = range;
  // The upper third of the kind's usual range.
  return bottle.abv.percent >= low + (high - low) * 2 / 3;
}

function contextOf(
  prepared: RecordReading,
  identity: Identity,
): PerceptionContext {
  const { bottle, answers } = prepared;
  return {
    drink: identity.drink,
    kind: identity.kind,
    identity,
    answers,
    strong: strongFor(bottle, identity),
    fizzy: identity.kind === "sparkling_wine" || identity.kind === "takju",
    abv: bottle.abv?.of === "bottle" ? bottle.abv.percent : null,
    processes: bottle.processes,
  };
}

/* --------------------------------------------------------------- gauges */

const MAKING: ReadonlySet<FactorKind> = new Set([
  "making",
  "cask",
  "ingredient",
]);

type Placed = {
  factor: Factor;
  step: number;
  side: Side;
  meet: "same" | "near" | "opposite";
  /** Which cause speaks before which on this axis; lower is first. */
  order: number;
};

/**
 * The cause that is the bottle's own fact on an axis and speaks before its
 * rank: the label's word on sweetness and bubbles, the strength on heat.
 */
const FIRST_ON: Readonly<Partial<Record<GaugeAxis, FactorKind>>> = {
  sweetness: "label_word",
  sparkling: "label_word",
  spice: "abv",
};

function placeFactors(
  line: GaugeLine,
  identity: Identity,
): { placed: Placed[]; varies: Factor[] } {
  const axis = catalogAxis(line.axis);
  const bound = threshold(identity.drink, identity.kind, line.axis);
  const placed: Placed[] = [];
  const varies: Factor[] = [];
  for (const factor of identity.factors) {
    const t = factor.taste[axis];
    if (!t) continue;
    if (t.varies) {
      varies.push(factor);
      continue;
    }
    // What making does is a push one way; a push to the middle is none.
    if (MAKING.has(factor.factor) && t.side === "middle") continue;
    const diff = line.level - t.step;
    const opposite =
      (line.side === "high" && (t.side === "low" || t.side === "none")) ||
      (t.side === "high" && (line.side === "low" || line.side === "none"));
    // Where one step counts, it counts from a pronounced tendency: a step
    // off the middle (a 카비넷 felt a little sweeter) is still as expected.
    const oneStep = bound === 1 &&
      (t.side !== "middle" || Math.abs(diff) >= 2);
    const meet =
      t.side === line.side || (line.side === "none" && t.side === "low")
        ? "same"
        : Math.abs(diff) >= bound && (opposite || oneStep)
        ? "opposite"
        : "near";
    placed.push({
      factor,
      step: t.step,
      side: t.side,
      meet,
      order: factor.factor === FIRST_ON[line.axis] ? 0 : factor.rank,
    });
  }
  // A cause that runs several ways keeps the kind from speaking for the axis.
  const kept = varies.length
    ? placed.filter((p) => p.factor.factor !== "kind")
    : placed;
  kept.sort((a, b) => a.order - b.order);
  return { placed: kept, varies };
}

function causeOf(p: Placed, axis: string): Cause {
  const f = p.factor;
  return {
    factor: f.factor,
    key: f.key,
    ko: f.ko,
    rank: f.rank,
    on: f.on,
    tendency: { axis, step: p.step },
    ...(f.climate ? { climate: f.climate } : {}),
    ...(f.why ? { why: f.why } : {}),
    ...(f.in_climate ? { in_climate: f.in_climate } : {}),
  };
}

function gaugeAnswer(line: GaugeLine): EvidenceAnswer {
  return {
    kind: "gauge",
    axis: line.axis,
    level: line.level,
    side: line.side,
    reaction: line.reaction,
    weight: line.weight,
    ref: line.answer_ref,
  };
}

function supportOf(bottle: BottleFacts, line: GaugeLine) {
  const dimension = catalogLevelOf(line.axis);
  const level = dimension ? bottle.levels[dimension] : undefined;
  if (!level || level.of !== "bottle") return undefined;
  return {
    axis: catalogAxis(line.axis),
    bottle: level.level,
    same_side: sideOf(level.level) === line.side,
  };
}

function gaugeGuide(line: GaugeLine, because: string): Guide {
  if (line.reaction === "liked") {
    return { direction: "keep", axis: line.axis, because };
  }
  const direction = line.side === "high"
    ? "reduce"
    : line.side === "low" || line.side === "none"
    ? "increase"
    : "adjust";
  return { direction, axis: line.axis, because };
}

/* ----------------------------------------------------------------- main */

/** 근거 찾기: every answer of the record held against the bottle. Pure. */
export function findEvidence(prepared: RecordReading): EvidenceResult {
  const identity = bottleIdentity(prepared.bottle);
  if (!identity) {
    return {
      evidence: [],
      misses: [
        ...prepared.answers.gauges.map((g) => ({
          ref: g.answer_ref,
          reason: "no_cause" as const,
        })),
        ...prepared.answers.aromas.map((a) => ({
          ref: a.answer_ref,
          reason: "no_cause" as const,
        })),
      ],
      identity: {
        drink: null,
        kind: null,
        lead: null,
        identity_key: null,
        causes: [],
        relations: [],
        varies: [],
      },
    };
  }
  const ctx = contextOf(prepared, identity);
  const evidence: Evidence[] = [];
  const misses: Miss[] = [];
  const add = (e: Omit<Evidence, "id" | "identity_key" | "lead">) =>
    evidence.push({
      id: `e${evidence.length + 1}`,
      identity_key: identity.identity_key,
      lead: identity.lead,
      ...e,
    });

  for (const line of prepared.answers.gauges) {
    const before = evidence.length;
    const axis = catalogAxis(line.axis);
    const { placed, varies } = placeFactors(line, identity);
    const support = supportOf(prepared.bottle, line);
    const isWine = identity.drink === "wine";

    // For wine the kind speaks only when nothing else does.
    const speaking = (list: Placed[]) => {
      const notKind = list.filter((p) => p.factor.factor !== "kind");
      return isWine && notKind.length ? notKind : list;
    };
    const same = speaking(placed.filter((p) => p.meet === "same"));
    const near = speaking(placed.filter((p) => p.meet === "near"));

    const basis = placed[0];
    const bottleIsSo = support && support.same_side &&
      basis && Math.abs(support.bottle - basis.step) >= 2;
    const explainedBySide = same.some((p) =>
      !(isWine && p.factor.factor === "kind")
    );
    // 엇갈림: the causes that say the opposite and are as much this bottle's
    // own as the first cause on the answer's side. The kind is what bottles
    // like it share, so it never stands against a cause of the bottle, and
    // any cause of the bottle stands against an answer only the kind explains.
    const own = (p: Placed) => p.factor.factor === "kind" ? Infinity : p.order;
    const against = explainedBySide
      ? placed.filter((p) =>
        p.meet === "opposite" && own(p) <= Math.min(...same.map(own))
      )
      : [];
    // What happened in this glass: only what the reader answered elsewhere
    // or the bottle states makes a row hold beside an explanation.
    const inThisGlass = line.side === "middle" ? [] : perceptionRows(
      ctx,
      line.axis,
      line.side === "high" ? "higher" : "lower",
    ).map((rule) => ({
      ...rule,
      by: rule.by.filter((b) => b.strength < 3),
    })).filter((rule) => rule.by.length);

    // 이 병의 특징: nothing of the identity is on the answer's side, but the
    // level read for the bottle is, well off what the identity says.
    if (basis && basis.meet === "opposite" && bottleIsSo && !explainedBySide) {
      add({
        answer: gaugeAnswer(line),
        type: "bottle_trait",
        causes: [causeOf(basis, axis)],
        clarity: "clear",
        cause_on: "bottle",
        support,
        claim_key: `bottle:${line.axis}:${line.side}`,
        guide: gaugeGuide(line, `bottle:${axis}`),
      });
    }

    // 다르게 느낀 이유: against the first cause that says something on the
    // axis, when no cause of the bottle is on the answer's side, and the
    // bottle's own level does not already say it is so (설계 4-2).
    if (
      basis && basis.meet === "opposite" && !bottleIsSo && !explainedBySide &&
      !(isWine && basis.factor.factor === "kind")
    ) {
      // The rows speak of the answer as it was given, higher or lower.
      const direction = line.level > basis.step ? "higher" : "lower";
      const rules = perceptionRows(ctx, line.axis, direction);
      if (rules.length) {
        const trait = TRAIT[rules[0].row];
        add({
          answer: gaugeAnswer(line),
          type: "felt_differently",
          causes: [causeOf(basis, axis)],
          clarity: "clear",
          cause_on: basis.factor.on,
          perception: { rules },
          ...(support ? { support } : {}),
          claim_key: `felt:${line.axis}:${line.side}`,
          guide: {
            direction: line.reaction === "liked" ? "keep" : "reduce",
            ...(trait ? { trait } : {}),
            because: `${basis.factor.factor}:${basis.factor.key}`,
          },
        });
      }
    }

    // 설명: the causes on the answer's side; failing those, the ones a step
    // off it, unless the answer was already felt differently.
    const chosen = same.length ? same : evidence.length > before ? [] : near;
    if (chosen.length) {
      const first = chosen[0];
      const kindOnly = isWine && first.factor.factor === "kind";
      const together = same.length
        ? identity.relations.filter((r) => r.on.includes(axis))
        : [];
      // The strength is already there as a cause: a row it alone supports adds nothing.
      const byStrength = chosen.some((p) => p.factor.factor === "abv");
      const glass = inThisGlass.map((rule) => ({
        ...rule,
        by: rule.by.filter((b) => !(byStrength && b.said.startsWith("abv:"))),
      })).filter((rule) => rule.by.length);
      add({
        answer: gaugeAnswer(line),
        type: kindOnly ? "kind_tendency" : against.length ? "split" : "explain",
        causes: chosen.map((p) => causeOf(p, axis)),
        ...(against.length
          ? { against: against.map((p) => causeOf(p, axis)) }
          : {}),
        clarity: same.length
          ? (line.side === "middle" ? "balance" : "clear")
          : "weak",
        cause_on: first.factor.on,
        ...(same.length && !kindOnly && glass.length
          ? { perception: { rules: glass } }
          : {}),
        ...(together.length ? { relations: together } : {}),
        ...(support ? { support } : {}),
        claim_key:
          `${first.factor.factor}:${first.factor.key}/${line.axis}:${line.side}`,
        guide: gaugeGuide(line, `${first.factor.factor}:${first.factor.key}`),
      });
    }

    // 이번 잔에서: no cause of the bottle is on the answer's side, and what
    // the reader answered elsewhere makes a row hold. A row only the bottle's
    // strength or a tendency supports says nothing here.
    const byReader = inThisGlass.map((rule) => ({
      ...rule,
      by: rule.by.filter((b) => b.strength === 1),
    })).filter((rule) => rule.by.length);
    const explained = evidence.slice(before).some((e) => e.clarity !== "weak");
    if (!explained && byReader.length) {
      const trait = TRAIT[byReader[0].row];
      add({
        answer: gaugeAnswer(line),
        type: "in_this_glass",
        causes: [],
        clarity: "weak",
        cause_on: "bottle",
        perception: { rules: byReader },
        ...(support ? { support } : {}),
        claim_key: `glass:${byReader[0].row}/${line.axis}:${line.side}`,
        guide: {
          direction: line.reaction === "liked" ? "keep" : "reduce",
          ...(trait ? { trait } : {}),
          because: `effect:${byReader[0].row}`,
        },
      });
    }

    if (evidence.length === before) {
      misses.push(
        varies.length
          ? {
            ref: line.answer_ref,
            reason: "varies",
            by: `${varies[0].factor}:${varies[0].key}`,
          }
          : { ref: line.answer_ref, reason: "no_cause" },
      );
    }
  }

  for (const line of prepared.answers.aromas) {
    const before = evidence.length;
    const answer = aromaAnswer(line);
    const met: Cause[] = [];
    for (const f of identity.factors) {
      for (const [source, keys] of Object.entries(f.aromas)) {
        const hit = keys.find((k) => namesAroma(k, line.aroma));
        if (!hit) continue;
        met.push({
          factor: f.factor,
          key: f.key,
          ko: f.ko,
          rank: f.rank,
          on: f.on,
          aroma: hit,
          aroma_source: source,
          ...aromaDetail(f, source, hit, line.aroma),
        });
        break;
      }
    }
    const causes = identity.drink === "wine" && met.some((c) =>
        c.factor !== "kind"
      )
      ? met.filter((c) => c.factor !== "kind")
      : met;
    if (causes.length) {
      const first = causes[0];
      add({
        answer,
        type: identity.drink === "wine" && first.factor === "kind"
          ? "kind_tendency"
          : "aroma_origin",
        causes,
        clarity: "clear",
        cause_on: first.on,
        claim_key: `${first.factor}:${first.key}/aroma:${line.aroma}`,
        guide: {
          direction: line.reaction === "liked" ? "keep" : "reduce",
          aroma: line.aroma,
          because: `${first.factor}:${first.key}`,
        },
      });
    }
    if (line.reaction === "liked") {
      for (const rule of aromaRows(ctx, line.aroma)) {
        add({
          answer,
          type: "aroma_effect",
          causes: [],
          clarity: "weak",
          cause_on: "bottle",
          perception: { rules: [rule] },
          claim_key: `effect:${rule.row}/aroma:${line.aroma}`,
          guide: {
            direction: "keep",
            aroma: line.aroma,
            because: `effect:${rule.row}`,
          },
        });
      }
    }
    if (evidence.length === before) {
      misses.push({
        ref: line.answer_ref,
        reason: "no_cause",
      });
    }
  }

  const variesAxes: { axis: string; by: string }[] = [];
  for (const f of identity.factors) {
    for (const [axis, t] of Object.entries(f.taste)) {
      if (t.varies && !variesAxes.some((v) => v.axis === axis)) {
        variesAxes.push({ axis, by: `${f.factor}:${f.key}` });
      }
    }
  }
  return {
    evidence,
    misses,
    identity: {
      drink: identity.drink,
      kind: identity.kind,
      lead: identity.lead,
      identity_key: identity.identity_key,
      ...(identity.wine_case ? { wine_case: identity.wine_case } : {}),
      causes: identity.factors.map(({ factor, key, rank, on }) => ({
        factor,
        key,
        rank,
        on,
      })),
      relations: identity.relations,
      varies: variesAxes,
    },
  };
}

/**
 * What the row says more of where an aroma comes from: how, in its own
 * words; the casks of the house, of an aroma its casks give; and the climate
 * the bottle is from, of an aroma the grape's row names in that climate and
 * not in the other (블랙베리 is named in both of 시라's: no climate). Where
 * the row tells each aroma apart, the words are those of the aroma the
 * reader picked, else of the row's own word for it: 라가불린's 요오드 is told
 * by its peat, and nothing is told of it to one who picked 미네랄.
 */
function aromaDetail(
  f: Factor,
  source: string,
  aroma: string,
  picked: string,
): Pick<Cause, "aroma_how" | "aroma_casks" | "aroma_climate"> {
  const told = f.aromas_how?.[source];
  const how = typeof told === "string" ? told : told?.[picked] ?? told?.[aroma];
  const casks = source === "cask" ? f.house_casks ?? [] : [];
  const grown = source === "material" || source === "ripeness"
    ? f.grown_in
    : undefined;
  const there = grown && lineNamesAroma(grown.here, aroma) &&
    !lineNamesAroma(grown.there, aroma);
  return {
    ...(how !== undefined ? { aroma_how: how } : {}),
    ...(casks.length ? { aroma_casks: casks } : {}),
    ...(there ? { aroma_climate: grown.climate } : {}),
  };
}

function aromaAnswer(line: AromaLine): EvidenceAnswer {
  return {
    kind: "aroma",
    aroma: line.aroma,
    stage: line.stage,
    reaction: line.reaction,
    weight: line.weight,
    ref: line.answer_ref,
  };
}
