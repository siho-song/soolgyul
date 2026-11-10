/**
 * 결론: the card's conclusions from its reactions and findings. Nothing here
 * invents a sensation; every conclusion points back to reactions, findings
 * and product facts by id.
 *
 * - nickname: the approved catalogue's selector, run on the record's answers
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
import { type CardReading, readCard } from "../facts/reading.ts";
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

/** 읽기 → 설명 → 결론, validated as one card. */
export function buildCardFacts(record: SensoryRecord): CardFacts {
  const reading = readCard(record);
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
 * What to keep: the liked answers, the explained one first. 적당했어요 is not
 * kept on purpose: the guide would call it liked (좋아하신 그대로), and its
 * level already stays "이번과 비슷하게" with the unanswered ones.
 */
function likedFirst(reactions: readonly ReactionFact[]): ReactionFact[] {
  const liked = reactions.filter((r) => r.reaction === "liked");
  return [...liked.filter((r) => r.focus), ...liked.filter((r) => !r.focus)];
}

/* ------------------------------------------------------------ nickname */

function nickname(reading: CardReading): string {
  const keys = [...new Set(reading.reactions.flatMap((r) => r.answer_refs))];
  // Tannin is not a product fact of the card yet, so the 떫음 wording is used.
  try {
    return selectTasteNickname(keys).label;
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
  const keep: Subject[] = [];
  // The balanced card (nothing liked or minded) keeps its 적당했어요 levels,
  // so the guide can hold that line.
  const balanced = !reactions.some((r) =>
    r.reaction === "liked" || r.reaction === "burden"
  );
  const kept = balanced
    ? reactions.filter((r) => r.reaction === "fine")
    : likedFirst(reactions);
  for (const r of kept) {
    if (keep.length === 3) break;
    if (!keep.some((s) => sameSubject(s, r.subject))) keep.push(r.subject);
  }
  const adjust: {
    subject: Subject;
    direction: ReturnType<typeof direction>;
  }[] = [];
  for (const r of reactions) {
    const seen = adjust.find((a) => sameSubject(a.subject, r.subject));
    if (seen) {
      // A burden while drinking that was still there after swallowing should not linger.
      if (r.qualifier === "lingering") seen.direction = "shorter";
      continue;
    }
    if (r.reaction === "burden") {
      adjust.push({ subject: r.subject, direction: direction(r) });
    }
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

/** The thinkings that answer each reason the user gave; the card answers that reason first. */
const REASON_THINKINGS: Readonly<Partial<Record<string, readonly Thinking[]>>> =
  {
    pronounced: ["intensity", "exposure"],
    gentle: ["intensity", "masking"],
    harmonious: ["combination"],
    excessive: ["masking", "intensity", "distinction"],
    too_weak: ["intensity", "masking"],
    masking: ["masking"],
    disharmonious: ["combination", "distinction"],
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
  (d.frame === "liked_little" &&
    (r.qualifier === "pronounced" || r.qualifier === "excessive"));

/** Product conditions a finding stands on; a mid level or a phase says little. */
const evidence = (d: Finding) =>
  d.conclusion.given.filter((c) =>
    c.type === "level" ? c.is !== "mid" : c.type !== "phase"
  ).length;

/**
 * One finding per reaction, at most two. Reactions the user explained come
 * first; for each, a finding that does not deny what the reader felt, then
 * the one that answers the stated reason, then the one with the sharpest
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
  const ordered = [
    ...reactions.filter((r) => r.focus),
    ...reactions.filter((r) => !r.focus),
  ];
  for (const r of ordered) {
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
