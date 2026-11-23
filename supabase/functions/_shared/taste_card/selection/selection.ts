/**
 * 결과 선정: the third stage of the 술결카드 생성 파이프라인. From the
 * evidence 근거 찾기 found it chooses what the card tells: at most two reasons
 * for 잘 맞았던 이유 and two for 아쉬웠던 이유. It finds nothing new and
 * writes no sentence (글쓰기).
 *
 * A reason is chosen from the reader's side (the user's word, 2026-11-21:
 * "사용자에게 가장 잘 맞는 근거"):
 *
 *   what was felt most     an end step (1 or 5) or an aroma picked at more
 *                          than one moment, before a step beside the middle
 *                          or an aroma picked once; the middle step comes
 *                          last. An end step most bottles of the kind sit on
 *                          (a red wine that was not sweet) is the kind's
 *                          usual way and comes last with the middle
 *   what sets the bottle   a step on the side the bottle stands out on among
 *   apart                  its kind (selection/standing.ts) counts a step
 *                          more: liking the smoke of a whisky far smokier
 *                          than most says more of the reader than liking a
 *                          taste every bottle of the kind has
 *   a cause of the bottle  among answers that say as much, one a cause of
 *                          the bottle explains before one only the kind, or
 *                          only the surroundings in the glass, explains; an
 *                          answer nothing explains comes after those and is
 *                          told from what was felt alone
 *   another cause          for the second reason, among answers that say as
 *                          much, one a cause the first did not tell by
 *   the fuller story       then the evidence with more of the three layers:
 *                          what the bottle is, why that tastes so, what
 *                          happened in this glass
 *
 * An answer felt clearly (not the middle, not the kind's usual way) is a
 * reason whether or not a cause was found for it, so a reason with a cause
 * does not push out what the reader felt more. One of a section's two
 * reasons is still the bottle's where one can be: when the first has no
 * cause of the bottle, the second is the best one that has.
 *
 * A reason speaks of one answer and is told by one cause. For a taste it is
 * the first cause that is the bottle's own (its cask, its maker, its
 * strength) and the kind only when nothing else speaks: every single malt is
 * a single malt. An aroma is told by the cause that leads the bottle's
 * identity, as 근거 찾기 orders them: the kind's own aromas are what the kind
 * is known by. When the section's other reason is already told by that
 * cause, another cause that says the same of the answer tells it instead
 * (프란치아코르타의 긴 여운, 병내 2차 발효의 산미), so that two answers one
 * cause explains are two reasons with two causes, not one reason that names
 * one of them (the user's word, 2026-11-21: "원인들이 엄청 많아야 정상인데
 * 왜 하나의 설명밖에 못 하는 거지?"). An aroma picked at several moments is
 * one answer here, and what its surroundings did to it (향의 작용) goes with
 * the reason of where it comes from.
 *
 * A cause a step off the answer (a kind of middle weight, felt heavy) places
 * the answer and explains nothing, so it is not what the reason is told from.
 * Nor is a middle answer felt differently from the bottle: it was not felt
 * much, and telling why it was not as expected reads as a correction. An
 * answer no reason tells and nothing explains is listed, the most felt
 * first.
 */
import type {
  Evidence,
  EvidenceAnswer,
  EvidenceResult,
} from "../evidence/evidence.ts";
import type { FactorKind } from "../evidence/identity.ts";
import { placeOfLevel } from "../facts/kind_place.ts";
import { USUAL_SHARE } from "../facts/name_counts.ts";
import { LINES_PER_SECTION } from "../limits.ts";
import type { GaugeLine } from "../prepare/interpretation.ts";
import type { Prepared } from "../prepare/prepare.ts";
import { givesAroma, makes } from "./causation.ts";
import { placeDimensionOf, standsOutIn } from "./standing.ts";

export type Section = "liked" | "burden";

/** How much the reader felt an answer: the middle step or the kind's usual end, a step beside the middle or an aroma, an end step. */
export type Felt = 1 | 2 | 3;

/**
 * How much a reason is this bottle's: the surroundings in the glass alone, a wine's
 * kind or a middle met in the middle, the kind meeting the answer, a cause of
 * the bottle's own meeting the answer.
 */
export type Closeness = 0 | 1 | 2 | 3;

export type Reason = {
  id: string;
  section: Section;
  /**
   * The evidence it is told from: the one that leads, then what the
   * surroundings did to an aroma it speaks of. Empty when nothing explains
   * the answer: it is then told from what was felt.
   */
  evidence: readonly string[];
  /** The answer it speaks of: one gauge step, or every moment an aroma was picked at. */
  answers: readonly string[];
  /** The cause it is told by; none when only the surroundings in the glass speak, or nothing does. */
  told_by: { factor: FactorKind; key: string } | null;
  felt: Felt;
  /** Whether its leading answer is on the side the bottle stands out on among its kind. */
  apart: boolean;
  closeness: Closeness;
  /** How many of the three layers its leading evidence holds. */
  layers: 1 | 2 | 3;
};

/** Evidence with no cause of the bottle: what the surroundings in the glass did. */
const SURROUNDINGS: readonly Evidence["type"][] = [
  "aroma_effect",
  "in_this_glass",
];

export type Selection = Readonly<
  Record<Section, {
    reasons: readonly Reason[];
    /** The answers of the section no reason tells, the most felt first. */
    untold: readonly string[];
  }>
>;

/** One answer of the reader: a gauge step, or an aroma with every moment it was picked at. */
type Answered = {
  key: string;
  section: Section;
  refs: string[];
  felt: Felt;
  /** The gauge it was set on and the side of the middle it was set to. */
  gauge?: { axis: GaugeLine["axis"]; side: "high" | "low" | null };
  /** Where it stands among the answers as they were given. */
  order: number;
};

type Candidate = {
  answered: Answered;
  /** What it is told from; null when nothing explains the answer. */
  lead: Evidence | null;
  /** Whether the answer is on the side the bottle stands out on among its kind. */
  apart: boolean;
  /** 향의 작용 of the same answer, told with its origin. */
  with: Evidence[];
  closeness: Closeness;
  layers: 1 | 2 | 3;
};

function answerKey(a: EvidenceAnswer): string {
  return a.kind === "gauge"
    ? `gauge:${a.axis}`
    : `aroma:${a.aroma}:${a.reaction}`;
}

/**
 * How much a gauge step was felt. An end step is felt most, unless most
 * bottles of the kind sit on it: nine red wines in ten are not sweet, so a
 * red that was not sweet says the reader met the kind, not this bottle, and
 * is told only when nothing felt more is left to tell.
 */
function feltOf(g: GaugeLine, bottle: Prepared["bottle"]): Felt {
  if (g.level === 3) return 1;
  if (g.level !== 1 && g.level !== 5) return 2;
  const dimension = placeDimensionOf(g.axis);
  const place = dimension
    ? placeOfLevel(dimension, bottle.style_key, bottle.category, g.level)
    : null;
  return place && place.share > USUAL_SHARE ? 1 : 3;
}

/** The reader's answers, an aroma's moments folded into one. */
function answersOf(prepared: Prepared): Answered[] {
  const out: Answered[] = [];
  const { gauges, aromas } = prepared.interpretation;
  for (const g of gauges) {
    out.push({
      key: `gauge:${g.axis}`,
      section: g.reaction,
      refs: [g.answer_ref],
      felt: feltOf(g, prepared.bottle),
      gauge: {
        axis: g.axis,
        side: g.level > 3 ? "high" : g.level < 3 ? "low" : null,
      },
      order: out.length,
    });
  }
  for (const a of aromas) {
    const key = `aroma:${a.aroma}:${a.reaction}`;
    const seen = out.find((x) => x.key === key);
    if (seen) {
      seen.refs.push(a.answer_ref);
      seen.felt = 3;
    } else {
      out.push({
        key,
        section: a.reaction,
        refs: [a.answer_ref],
        felt: 2,
        order: out.length,
      });
    }
  }
  return out;
}

function closenessOf(e: Evidence): Closeness {
  if (SURROUNDINGS.includes(e.type)) return 0;
  if (e.type === "kind_tendency" || e.clarity !== "clear") return 1;
  return causesOf(e).some((c) => c.factor !== "kind") ? 3 : 2;
}

function layersOf(e: Evidence, effects: number): 1 | 2 | 3 {
  const why = e.causes.some((c) => c.why || c.in_climate);
  const glass = Boolean(e.perception?.rules.length) ||
    Boolean(e.relations?.length) || Boolean(e.support?.same_side) ||
    effects > 0;
  const what = e.causes.length > 0;
  return Math.max(1, Number(what) + Number(why) + Number(glass)) as 1 | 2 | 3;
}

/**
 * How closely a cause is this bottle's: who made it and how before what it
 * is made of and where, and its kind last. A reason is told by the closest
 * there is (셰리 캐스크의 바닐라 향, not 싱글 몰트 위스키 특유의).
 */
const NEARNESS: Readonly<Record<string, number>> = {
  producer: 0,
  making: 0,
  cask: 0,
  label_word: 0,
  abv: 0,
  age: 0,
  grape: 1,
  ingredient: 1,
  region_style: 1,
  kind: 2,
};

/**
 * The causes of a piece of evidence that can be said to make the answer's
 * taste, the closest to the bottle first; among causes as close, as 근거
 * 찾기 orders them.
 */
function causesOf(e: Evidence): Evidence["causes"] {
  const answer = e.answer;
  const able = answer.kind === "gauge"
    ? e.causes.filter((c) => makes(c, answer.axis))
    : e.causes.filter((c) => givesAroma(c, answer.aroma));
  const grapes = able.filter((c) => c.factor === "grape");
  // A style named after its grapes (로마냐 산지오베제) says less than the
  // grape itself.
  // A wine is told by its place and its grape before its strength: 따뜻한
  // 산지에서 잘 익은 포도라 묵직하다 is the wine's own story, 도수가 14%라
  // 묵직하다 is not (the user's review, 2026-11-21).
  const ofWine = able.some((c) =>
    c.factor === "grape" || c.factor === "region_style"
  );
  const near = (c: Evidence["causes"][number]) =>
    c.factor === "region_style" && grapes.some((g) => c.ko.includes(g.ko))
      ? 1.5
      : c.factor === "abv" && ofWine
      ? 1.7
      : NEARNESS[c.factor] ?? 1;
  return able.map((c, at) => ({ c, at })).sort((a, b) =>
    near(a.c) - near(b.c) || a.at - b.at
  ).map(({ c }) => c);
}

/**
 * Evidence that explains. A cause a step off the answer only places it, a
 * middle answer felt differently is not told, and a way of making that does
 * not make the taste is no cause of it (selection/causation.ts).
 */
function explains(e: Evidence): boolean {
  if (SURROUNDINGS.includes(e.type)) return true;
  if (e.clarity === "weak") return false;
  if (e.causes.length && !causesOf(e).length) return false;
  return !(e.type === "felt_differently" && e.answer.kind === "gauge" &&
    e.answer.side === "middle");
}

/**
 * One candidate for each answer that can be a reason: one something that
 * explains was found for, or one felt clearly with nothing to explain it.
 */
function candidatesOf(
  answered: readonly Answered[],
  evidence: readonly Evidence[],
  standsOut: ReturnType<typeof standsOutIn>,
): Candidate[] {
  const out: Candidate[] = [];
  for (const a of answered) {
    const own = evidence.filter((e) =>
      answerKey(e.answer) === a.key && explains(e)
    );
    const effects = own.filter((e) => e.type === "aroma_effect");
    // The same origin found at every moment of an aroma is one finding.
    const lead = own.find((e) => e.type !== "aroma_effect") ?? own[0] ?? null;
    if (!lead && a.felt < 2) continue;
    const told = !lead || lead.type === "aroma_effect"
      ? []
      : uniqueByClaim(effects);
    const side = a.gauge?.side;
    out.push({
      answered: a,
      lead,
      apart: Boolean(
        a.gauge && side && a.felt >= 2 &&
          standsOut(a.gauge.axis, lead?.causes ?? []) === side,
      ),
      with: told,
      closeness: lead ? closenessOf(lead) : 0,
      layers: lead ? layersOf(lead, told.length) : 1,
    });
  }
  return out;
}

function uniqueByClaim(list: readonly Evidence[]): Evidence[] {
  const seen = new Set<string>();
  return list.filter((e) =>
    seen.has(e.claim_key) ? false : (seen.add(e.claim_key), true)
  );
}

/** Whether a cause says of a gauge answer what the reader said: the same side of the middle. */
function agrees(c: Evidence["causes"][number], e: Evidence): boolean {
  if (e.answer.kind !== "gauge") return true;
  const step = c.tendency?.step;
  return step !== undefined &&
    Math.sign(step - 3) === Math.sign(e.answer.level - 3);
}

/**
 * The cause a piece of evidence is told by: for a taste the first cause that
 * is not the kind, for an aroma the first cause 근거 찾기 names (the one that
 * leads the bottle's identity); failing those, the first cause there is.
 * A cause the section has already told a reason by gives way to another
 * that agrees with the answer, when there is one.
 */
function toldBy(
  e: Evidence | null,
  told: ReadonlySet<string>,
): Evidence["causes"][number] | null {
  if (!e) return null;
  const causes = causesOf(e);
  const first = causes[0] ?? null;
  // An aroma keeps the cause it comes from: 말벡 특유의 자두 향.
  if (
    !first || e.answer.kind !== "gauge" ||
    !told.has(`${first.factor}:${first.key}`)
  ) return first;
  return causes.find((c) =>
    c.factor !== "kind" && !told.has(`${c.factor}:${c.key}`) && agrees(c, e)
  ) ?? first;
}

/** How much an answer says of the reader: how much it was felt, a step more where the bottle stands apart. */
const says = (c: Candidate) => c.answered.felt + Number(c.apart);

/** Whether a cause of the bottle, or its kind, meets the answer. */
const hasCause = (c: Candidate) => c.closeness >= 2;

/** The candidates of a section, the one that says most of the reader first. */
function rankSection(
  section: Section,
  candidates: readonly Candidate[],
): Candidate[] {
  return candidates
    .filter((c) => c.answered.section === section)
    .sort((a, b) =>
      says(b) - says(a) ||
      Number(b.apart) - Number(a.apart) ||
      Number(hasCause(b)) - Number(hasCause(a)) ||
      Number(b.lead !== null) - Number(a.lead !== null) ||
      b.closeness - a.closeness ||
      b.layers - a.layers ||
      a.answered.order - b.answered.order
    );
}

/** The peat gauge and the peat or smoke aroma are one thing the reader said twice. */
const sameSense = (a: Answered, b: Answered) =>
  [a.key, b.key].some((k) => k === "gauge:peat") &&
  [a.key, b.key].some((k) => /^aroma:(peat|smoke):/.test(k));

function selectSection(
  section: Section,
  answered: readonly Answered[],
  candidates: readonly Candidate[],
  introduced: ReadonlySet<string>,
): Selection[Section] {
  const ranked = rankSection(section, candidates);
  const reasons: Reason[] = [];
  const used = new Set<Candidate>();
  const tellers = new Set<string>();
  // Every cause of a reason already told: the sentence may have named any.
  const shown = new Set<string>();
  const tell = (c: Candidate) => {
    used.add(c);
    for (const x of c.lead ? causesOf(c.lead) : []) {
      shown.add(`${x.factor}:${x.key}`);
    }
    const cause = toldBy(c.lead, tellers);
    if (cause) tellers.add(`${cause.factor}:${cause.key}`);
    reasons.push({
      id: `${section}${reasons.length + 1}`,
      section,
      evidence: [
        ...(c.lead ? [c.lead.id] : []),
        ...c.with.map((e) => e.id),
      ],
      answers: c.answered.refs,
      told_by: cause ? { factor: cause.factor, key: cause.key } : null,
      felt: c.answered.felt,
      apart: c.apart,
      closeness: c.closeness,
      layers: c.layers,
    });
  };
  while (reasons.length < LINES_PER_SECTION) {
    // One of the two reasons is the bottle's where one can be.
    const wantsCause = reasons.length === 1 && reasons[0].closeness < 2;
    const pool = wantsCause
      ? [
        ...ranked.filter((c) => hasCause(c) && c.answered.felt >= 2),
        ...ranked,
      ]
      : ranked;
    const open = (c: Candidate) =>
      !used.has(c) &&
      !reasons.some((r) =>
        answered.some((a) =>
          a.refs.includes(r.answers[0]) && sameSense(a, c.answered)
        )
      );
    const best = pool.find(open);
    if (!best) break;
    // Among answers that say as much, one that shows another thing of the
    // bottle comes first: an aroma with where it comes from (말벡 특유의 자두
    // 향), or a taste a cause not yet named explains (병내 2차 발효의 산미),
    // before a second taste of what the card has already named.
    const named = new Set([...tellers, ...introduced, ...shown]);
    const brings = (c: Candidate) => {
      if (!c.lead || !hasCause(c)) return false;
      if (!c.answered.gauge) return true;
      return causesOf(c.lead).some((cause) =>
        cause.factor !== "kind" && agrees(cause, c.lead!) &&
        !named.has(`${cause.factor}:${cause.key}`)
      );
    };
    const fresh = reasons.length && !brings(best)
      ? pool.find((c) => open(c) && says(c) === says(best) && brings(c))
      : undefined;
    tell(fresh ?? best);
  }
  const told = new Set(reasons.flatMap((r) => r.answers));
  const untold = answered
    .filter((a) =>
      a.section === section && !a.refs.some((ref) => told.has(ref))
    )
    .sort((a, b) => b.felt - a.felt || a.order - b.order)
    .flatMap((a) => a.refs);
  return { reasons, untold };
}

/** 결과 선정: the reasons the card tells, chosen from the evidence. Pure. */
export function selectReasons(
  prepared: Prepared,
  found: EvidenceResult,
): Selection {
  const answered = answersOf(prepared);
  const candidates = candidatesOf(
    answered,
    found.evidence,
    standsOutIn(prepared.bottle),
  );
  // What a wine's first sentence says of it before any reason: its place
  // and its grape (글쓰기 opens on them).
  const introduced = new Set<string>(
    prepared.bottle.category === "wine"
      ? [
        ...found.identity.causes.filter((c) => c.factor === "region_style")
          .map((c) => `${c.factor}:${c.key}`),
        ...prepared.bottle.grapes.slice(0, 1).map((key) => `grape:${key}`),
      ]
      : [],
  );
  return {
    liked: selectSection("liked", answered, candidates, introduced),
    burden: selectSection("burden", answered, candidates, introduced),
  };
}

/** One answer as 결과 선정 weighed it, for showing why a reason was chosen. */
export type Weighed = {
  section: Section;
  answers: readonly string[];
  felt: Felt;
  apart: boolean;
  closeness: Closeness;
  layers: 1 | 2 | 3;
  /** The evidence it would be told from; null when nothing explains it. */
  evidence: string | null;
};
