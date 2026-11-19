/**
 * 결과 선정: the third stage of the 술결카드 생성 파이프라인. From the
 * evidence 근거 찾기 found it chooses what the card tells: at most two reasons
 * for 잘 맞았던 이유 and two for 아쉬웠던 이유. It finds nothing new and
 * writes no sentence (글쓰기).
 *
 * A reason is told from the reader's side:
 *
 *   a cause first          a cause of the bottle that meets the answer comes
 *                          before the kind's usual way for a wine, a middle
 *                          answer met in the middle, and an aroma's
 *                          surroundings alone
 *   what was felt most     then an end step (1 or 5) or an aroma picked at
 *                          more than one moment, before a step beside the
 *                          middle or an aroma picked once; the middle step
 *                          comes last
 *   why this bottle        among answers felt as much, a cause that is the
 *                          bottle's own before its kind alone
 *   the fuller story       then the evidence with more of the three layers:
 *                          what the bottle is, why that tastes so, what
 *                          happened in this glass
 *
 * What one cause explains of several answers is one reason (a grape that is
 * both tannic and sharp), three answers at most, one of them an aroma when
 * the cause explains one. The two reasons of a section
 * are told by different causes where the evidence allows; a second reason by
 * the same cause is told only when it is another kind of finding (an answer
 * felt differently, two causes at odds) and nothing else is left. An aroma
 * picked at several moments is one answer here, and what its surroundings did
 * to it (향의 작용) goes with the reason of where it comes from.
 *
 * A cause a step off the answer (a kind of middle weight, felt heavy) places
 * the answer and explains nothing, so it makes no reason. An answer without a
 * reason to give is listed, the most felt first, so that 글쓰기 can say it as
 * it was felt.
 */
import type {
  Evidence,
  EvidenceAnswer,
  EvidenceResult,
} from "../evidence/evidence.ts";
import type { FactorKind } from "../evidence/identity.ts";
import type { Prepared } from "../prepare/prepare.ts";

export type Section = "liked" | "burden";

/** How much the reader felt an answer: the middle step, a step beside it or an aroma, an end step. */
export type Felt = 1 | 2 | 3;

/**
 * How much a reason is this bottle's: an aroma's surroundings alone, a wine's
 * kind or a middle met in the middle, the kind meeting the answer, a cause of
 * the bottle's own meeting the answer.
 */
export type Closeness = 0 | 1 | 2 | 3;

export type Reason = {
  id: string;
  section: Section;
  /**
   * The evidence it is told from: the one that leads, then what the same
   * cause explains of other answers, then what the surroundings did to an
   * aroma it speaks of.
   */
  evidence: readonly string[];
  /** The answers it speaks of, the leading one first. */
  answers: readonly string[];
  /** The cause it is told by; none when only the surroundings speak. */
  told_by: { factor: FactorKind; key: string } | null;
  felt: Felt;
  closeness: Closeness;
  /** How many of the three layers its leading evidence holds. */
  layers: 1 | 2 | 3;
};

export type Selection = Readonly<
  Record<Section, {
    reasons: readonly Reason[];
    /** The answers of the section no reason can be given for, the most felt first. */
    unexplained: readonly string[];
  }>
>;

const REASONS_PER_SECTION = 2;
const ANSWERS_PER_REASON = 3;

/** One answer of the reader: a gauge step, or an aroma with every moment it was picked at. */
type Answered = {
  key: string;
  section: Section;
  refs: string[];
  felt: Felt;
  /** Where it stands among the answers as they were given. */
  order: number;
};

type Candidate = {
  answered: Answered;
  lead: Evidence;
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

/** The reader's answers, an aroma's moments folded into one. */
function answersOf(prepared: Prepared): Answered[] {
  const out: Answered[] = [];
  const { gauges, aromas } = prepared.interpretation;
  for (const g of gauges) {
    out.push({
      key: `gauge:${g.axis}`,
      section: g.reaction,
      refs: [g.answer_ref],
      felt: g.level === 1 || g.level === 5 ? 3 : g.level === 3 ? 1 : 2,
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
  if (e.type === "aroma_effect") return 0;
  if (e.type === "kind_tendency" || e.clarity !== "clear") return 1;
  return e.causes.some((c) => c.factor !== "kind") ? 3 : 2;
}

function layersOf(e: Evidence, effects: number): 1 | 2 | 3 {
  const why = e.causes.some((c) => c.why || c.in_climate);
  const glass = Boolean(e.perception?.rules.length) ||
    Boolean(e.relations?.length) || Boolean(e.support?.same_side) ||
    effects > 0;
  return (1 + Number(why) + Number(glass)) as 1 | 2 | 3;
}

/** Evidence that explains: a cause a step off the answer only places it. */
const explains = (e: Evidence) =>
  e.type === "aroma_effect" || e.clarity !== "weak";

/** One candidate for each answer something that explains was found for. */
function candidatesOf(
  answered: readonly Answered[],
  evidence: readonly Evidence[],
): Candidate[] {
  const out: Candidate[] = [];
  for (const a of answered) {
    const own = evidence.filter((e) =>
      answerKey(e.answer) === a.key && explains(e)
    );
    if (!own.length) continue;
    const effects = own.filter((e) => e.type === "aroma_effect");
    // The same origin found at every moment of an aroma is one finding.
    const lead = own.find((e) => e.type !== "aroma_effect") ?? own[0];
    const told = lead.type === "aroma_effect" ? [] : uniqueByClaim(effects);
    out.push({
      answered: a,
      lead,
      with: told,
      closeness: closenessOf(lead),
      layers: layersOf(lead, told.length),
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

const toldBy = (e: Evidence) => e.causes[0] ?? null;
const causeKey = (e: Evidence) => {
  const c = toldBy(e);
  return c ? `${c.factor}:${c.key}` : null;
};

/** What one cause may explain of several answers: a clear meeting with the cause's own tendency. */
function joins(c: Candidate, first: Candidate): boolean {
  const types = ["explain", "aroma_origin", "kind_tendency"];
  return c !== first && c.lead.clarity === "clear" &&
    first.lead.clarity === "clear" &&
    types.includes(c.lead.type) && types.includes(first.lead.type) &&
    (c.lead.type === "kind_tendency") ===
      (first.lead.type === "kind_tendency") &&
    causeKey(c.lead) !== null && causeKey(c.lead) === causeKey(first.lead);
}

const ofAroma = (c: Candidate) => c.lead.answer.kind === "aroma";

/** A finding that is more than a cause's tendency meeting the answer, and so can be told beside it. */
function anotherFinding(c: Candidate): boolean {
  return c.closeness >= 2 &&
    ["felt_differently", "split", "bottle_trait"].includes(c.lead.type);
}

function selectSection(
  section: Section,
  answered: readonly Answered[],
  candidates: readonly Candidate[],
): Selection[Section] {
  const ranked = candidates
    .filter((c) => c.answered.section === section)
    .sort((a, b) =>
      Number(b.closeness >= 2) - Number(a.closeness >= 2) ||
      b.answered.felt - a.answered.felt ||
      b.closeness - a.closeness ||
      b.layers - a.layers ||
      a.answered.order - b.answered.order
    );
  const reasons: Reason[] = [];
  const used = new Set<Candidate>();
  const tellers = new Set<string>();
  const tell = (first: Candidate) => {
    const joined = ranked.filter((c) => !used.has(c) && joins(c, first));
    let members = [first, ...joined].slice(0, ANSWERS_PER_REASON);
    // An aroma the cause explains is told with its tastes, not crowded out by them.
    const aroma = joined.find(ofAroma);
    if (aroma && !members.some(ofAroma)) {
      members = [...members.slice(0, ANSWERS_PER_REASON - 1), aroma];
    }
    // Whatever else the cause explains is told here or not at all.
    for (const c of ranked) {
      if (c === first || joins(c, first)) used.add(c);
    }
    const cause = toldBy(first.lead);
    if (cause) tellers.add(`${cause.factor}:${cause.key}`);
    reasons.push({
      id: `${section}${reasons.length + 1}`,
      section,
      evidence: [
        ...members.map((c) => c.lead.id),
        ...members.flatMap((c) => c.with.map((e) => e.id)),
      ],
      answers: members.flatMap((c) => c.answered.refs),
      told_by: cause ? { factor: cause.factor, key: cause.key } : null,
      felt: first.answered.felt,
      closeness: first.closeness,
      layers: first.layers,
    });
  };
  // Different causes first, then what is left by a cause already told.
  for (const again of [false, true]) {
    for (const first of ranked) {
      if (reasons.length === REASONS_PER_SECTION) break;
      if (used.has(first)) continue;
      const teller = causeKey(first.lead);
      if (teller && tellers.has(teller) && !(again && anotherFinding(first))) {
        continue;
      }
      tell(first);
    }
  }
  const found = new Set(candidates.map((c) => c.answered));
  const unexplained = answered
    .filter((a) => a.section === section && !found.has(a))
    .sort((a, b) => b.felt - a.felt || a.order - b.order)
    .flatMap((a) => a.refs);
  return { reasons, unexplained };
}

/** 결과 선정: the reasons the card tells, chosen from the evidence. Pure. */
export function selectReasons(
  prepared: Prepared,
  found: EvidenceResult,
): Selection {
  const answered = answersOf(prepared);
  const candidates = candidatesOf(answered, found.evidence);
  return {
    liked: selectSection("liked", answered, candidates),
    burden: selectSection("burden", answered, candidates),
  };
}
