/**
 * 결론: the card's conclusions from its reactions and findings. Nothing here
 * invents a sensation; every conclusion points back to reactions, findings
 * and product facts by id.
 *
 * - nickname: the approved catalogue's selector, run on the card's reactions
 * - next_choice: keep what was liked, adjust what was a burden
 * - sections: at most two findings each for 잘 맞음 and 부담, the ones with
 *   the sharpest product evidence first
 */
import {
  CARD_FACTS_SCHEMA_VERSION,
  type CardFacts,
  type Finding,
  type NextChoice,
  type ReactionFact,
  type Subject,
  type Thinking,
  validateCardFacts,
} from "../facts/facts.ts";
import { type CardReading, oldCardReading } from "../facts/old_vocabulary.ts";
import { findCard } from "./findings.ts";
import { selectTasteNickname } from "../nickname/selector.ts";
import type { SensoryRecord } from "../record/sensory_record.ts";
type CardConclusions = Pick<
  CardFacts,
  "nickname" | "summary" | "sections"
>;

function concludeCard(
  reading: CardReading,
  findings: readonly Finding[],
): CardConclusions {
  const sections = {
    positive: selectFindings(reading, findings, "positive"),
    burden: selectFindings(reading, findings, "burden"),
  };
  return {
    nickname: nickname(reading),
    summary: {
      preference: sections.positive,
      next_choice: nextChoice(reading.reactions, findings),
    },
    sections,
  };
}

/** 준비 → 설명 → 결론, validated as one card. */
export function buildCardFacts(record: SensoryRecord): CardFacts {
  const reading = oldCardReading(record);
  const findings = findCard(reading);
  return validateCardFacts({
    schema_version: CARD_FACTS_SCHEMA_VERSION,
    ...reading,
    findings,
    ...concludeCard(reading, findings),
  });
}

/* ------------------------------------------------------------- helpers */

const sameSubject = (a: Subject, b: Subject) =>
  a.domain === b.domain && a.key === b.key;

/**
 * The answers the next choice is made from. What stayed in the nose after
 * swallowing is already there as the finish aromas themselves, and 끝맛의
 * 인상 is no level a bottle can be looked for by.
 */
const steersChoice = (r: ReactionFact) =>
  !(r.subject.domain === "finish" &&
    ["aroma_echo", "off_flavor", "character"].includes(r.subject.key));

/* ------------------------------------------------------------ nickname */

function nickname(reading: CardReading): string {
  // Tannin is not a product fact of the card yet, so the 떫음 wording is used.
  try {
    return selectTasteNickname(reading.reactions).label;
  } catch {
    // No catalogue entry covers what the reader liked: the neutral name,
    // never a failed card.
    return "취향 탐색자";
  }
}

/* --------------------------------------------------------- next choice */

function direction(r: ReactionFact): NextChoice["adjust"][number]["direction"] {
  if (r.qualifier === "too_weak" || r.qualifier === "too_brief") {
    return "higher";
  }
  // A finish that stayed too long.
  if (r.qualifier === "lingering") return "shorter";
  if (r.subject.key === "bubbles" || r.subject.key === "warmth") {
    return "softer";
  }
  return "lower";
}

function nextChoice(
  reactions: readonly ReactionFact[],
  findings: readonly Finding[],
): NextChoice {
  const answers = reactions.filter(steersChoice);
  // A flavour liked at one moment and marked 아쉬웠어요 at another is turned,
  // not kept.
  const minded = (subject: Subject) =>
    answers.some((r) =>
      r.reaction === "burden" && sameSubject(r.subject, subject)
    );
  const keep: Subject[] = [];
  for (const r of answers) {
    if (keep.length === 3) break;
    if (
      r.reaction === "liked" && !minded(r.subject) &&
      !keep.some((s) => sameSubject(s, r.subject))
    ) keep.push(r.subject);
  }
  const adjust: {
    subject: Subject;
    direction: ReturnType<typeof direction>;
  }[] = [];
  for (const r of answers) {
    // An aroma minded both while drinking and after swallowing is turned once.
    if (
      r.reaction === "burden" &&
      !adjust.some((a) => sameSubject(a.subject, r.subject))
    ) adjust.push({ subject: r.subject, direction: direction(r) });
  }
  const avoid: Subject[][] = [];
  for (const d of findings) {
    if (d.thinking !== "combination" || d.polarity !== "burden") continue;
    const pair = [...d.conclusion.subjects];
    if (!avoid.some((p) => JSON.stringify(p) === JSON.stringify(pair))) {
      avoid.push(pair);
    }
  }
  return { keep, adjust, avoid_combinations: avoid };
}

/* ------------------------------------------------------------ sections */

/** When two findings explain the same reaction equally well, this order decides. */
const THINKING_RANK: readonly Thinking[] = [
  "distinction",
  "masking",
  "exposure",
  "persistence",
  "combination",
  "intensity",
  "effect",
  "origin",
];

/** The thinkings that answer the strength a gauge step named; the card answers that first. */
const REASON_THINKINGS: Readonly<Partial<Record<string, readonly Thinking[]>>> =
  {
    pronounced: ["intensity", "exposure"],
    gentle: ["intensity", "masking"],
    excessive: ["masking", "intensity", "distinction"],
    too_weak: ["intensity", "masking"],
  };
const answersReason = (d: Finding, r: ReactionFact) =>
  r.qualifier !== null &&
  (REASON_THINKINGS[r.qualifier] ?? []).includes(d.thinking);

/**
 * A finding that says the drink has little of what the reader found strong or
 * burdensome. The catalog number may be wrong and the reader is not, so such a
 * finding is kept only when nothing else explains that reaction.
 */
const deniesReader = (d: Finding, r: ReactionFact) =>
  d.frame === "burden_little" || d.frame === "too_weak_much" ||
  d.frame === "too_brief_much" || d.frame === "lingering_little" ||
  (d.frame === "liked_little" &&
    (r.qualifier === "pronounced" || r.qualifier === "excessive"));

/** Product conditions a finding stands on; a mid level or a phase says little. */
const evidence = (d: Finding) =>
  d.conclusion.given.filter((c) =>
    c.type === "level" ? c.is !== "mid" : c.type !== "phase"
  ).length;

/**
 * One finding per reaction, at most two, in the order of the answers; for
 * each, a finding that does not deny what the reader felt, then the one that
 * answers the strength the reader named, then the one with the sharpest
 * evidence read for this bottle, then one not standing on the kind's usual
 * numbers alone, then the fixed thinking order. An aroma's effect has no
 * product evidence, so it explains an aroma only when nothing the card
 * knows about the bottle itself (a pairing, a masking, a read strength) does.
 */
function selectFindings(
  reading: CardReading,
  findings: readonly Finding[],
  polarity: Finding["polarity"],
): string[] {
  const reactions = reading.reactions;
  // Dimensions whose level was read for this bottle, not copied from the kind's table.
  const readDimensions = new Set(
    reading.product_facts.flatMap((p) =>
      p.fact.type === "level" && !p.fact.estimated ? [p.fact.dimension] : []
    ),
  );
  /**
   * The explanation's evidence without the levels copied from the kind's
   * table: a trait or descriptor counts as before, a telling level only when
   * it was read for this bottle. Equal to evidence() when nothing was copied.
   */
  const measured = (d: Finding) =>
    d.conclusion.given.filter((c) =>
      c.type === "phase"
        ? false
        : c.type === "level"
        ? c.is !== "mid" && readDimensions.has(c.dimension)
        : true
    ).length;
  /**
   * True when the explanation stands on levels alone and none of them was
   * read for this bottle: the kind's usual numbers. Such an explanation may
   * answer the reader's stated reason, but it never outranks one that needs
   * no number at all (an aroma's effect, a pairing of two answers).
   */
  const copiedOnly = (d: Finding) => {
    const levels = d.conclusion.given.filter((c) => c.type === "level");
    return levels.length > 0 &&
      levels.length ===
        d.conclusion.given.filter((c) => c.type !== "phase").length &&
      levels.every((c) =>
        c.type === "level" && !readDimensions.has(c.dimension)
      );
  };
  const chosen: Finding[] = [];
  for (const r of reactions) {
    if (chosen.length === 2) break;
    if (chosen.some((d) => d.reactions.includes(r.id))) continue;
    const candidates = findings.filter((d) =>
      d.polarity === polarity && d.reactions.includes(r.id)
    );
    const best = candidates
      .sort((a, b) =>
        Number(deniesReader(a, r)) - Number(deniesReader(b, r)) ||
        Number(answersReason(b, r)) - Number(answersReason(a, r)) ||
        measured(b) - measured(a) ||
        Number(copiedOnly(a)) - Number(copiedOnly(b)) ||
        evidence(b) - evidence(a) ||
        THINKING_RANK.indexOf(a.thinking) - THINKING_RANK.indexOf(b.thinking) ||
        a.row.localeCompare(b.row)
      )[0];
    if (best) chosen.push(best);
  }
  return chosen
    .sort((a, b) => findings.indexOf(a) - findings.indexOf(b))
    .map((d) => d.id);
}
