/**
 * 나의 술결 네 글자: four axes, one letter each, read from a person's records.
 *
 * Every record casts at most one vote per axis, from the reactions and the
 * bottle facts the 읽기 stage already produced. The votes of all records are
 * then weighed with a mild preference for recent ones; the heavier side is
 * the letter, so the letter and the shares shown under it always agree. A
 * letter shows from the first vote and keeps its side on an even split.
 * Every flip (or first reveal) is kept as a moment of the person's 변천사.
 */
import type { CardReading } from "./facts/reading.ts";
import type { ReactionFact } from "./facts/facts.ts";
import { NICKNAME_BASE_GROUPS } from "./nickname/catalog.ts";

const TASTE_LETTERS_RULE_VERSION = "taste-letters-v2";

const LETTER_AXES = [
  { key: "aroma", left: "F", right: "R" }, // 산 산뜻한 향 / 풍 풍부한 향
  { key: "sweetness", left: "D", right: "S" }, // 드 드라이 / 달 달콤한
  { key: "weight", left: "L", right: "H" }, // 가 가벼운 / 묵 묵직한
  { key: "finish", left: "C", right: "P" }, // 깔 깔끔한 여운 / 길 긴 여운
] as const;

export type LetterAxis = typeof LETTER_AXES[number]["key"];
type Letter = typeof LETTER_AXES[number]["left" | "right"];
export type LetterVotes = Readonly<Record<LetterAxis, Letter | null>>;

/** One record's contribution, stored next to its card. */
export type LetterRecord = {
  record_id: string;
  product_name: string;
  /** ISO timestamp of the record; records are replayed in this order. */
  recorded_at: string;
  votes: LetterVotes;
};

type LetterAxisState = {
  letter: Letter | null;
  left_share: number;
  right_share: number;
  vote_count: number;
};

export type LetterChange = {
  record_id: string;
  product_name: string;
  changed_at: string;
  axis: LetterAxis;
  from_letter: Letter | null;
  to_letter: Letter;
  left_share: number;
  right_share: number;
};

export type TasteLettersState = {
  rule_version: typeof TASTE_LETTERS_RULE_VERSION;
  record_count: number;
  axes: Readonly<Record<LetterAxis, LetterAxisState>>;
};

/** An older record weighs this much of the one after it. */
const RECENCY_WEIGHT = 0.9;

// 향 families from the nickname catalogue: fresh ones lift, rich ones settle.
// 떼루아·세이보리·머스크 are neither and cast no vote.
const FRESH_FAMILIES = new Set(["fruity", "floral", "herbal", "vegetable"]);
const RICH_FAMILIES = new Set([
  "bakery",
  "sweet_aroma",
  "nutty",
  "mocha",
  "milky",
  "woody",
  "smoky",
  "spice",
  "fermented",
  "leathery",
]);
const AROMA_FAMILY = new Map<string, string>();
for (const group of NICKNAME_BASE_GROUPS) {
  if (group.domain !== "aroma") continue;
  for (const key of group.sensory_keys) AROMA_FAMILY.set(key, group.key);
}

function aromaSide(key: string): "F" | "R" | null {
  const family = AROMA_FAMILY.get(key);
  if (family && FRESH_FAMILIES.has(family)) return "F";
  if (family && RICH_FAMILIES.has(family)) return "R";
  return null;
}

/** A level the catalogue read from this bottle (never the kind's estimate). */
function readLevel(reading: CardReading, dimension: string): number | null {
  for (const fact of reading.product_facts) {
    if (
      fact.fact.type === "level" && fact.fact.dimension === dimension &&
      !fact.fact.estimated
    ) return fact.fact.level;
  }
  return null;
}

function aromaVote(reactions: readonly ReactionFact[]): Letter | null {
  // Which aromas the person liked decides; several aromas in one record are
  // settled by majority, a tie is no vote.
  let fresh = 0;
  let rich = 0;
  for (const r of reactions) {
    if (r.subject.domain !== "aroma" || r.phase !== "drinking") continue;
    const side = aromaSide(r.subject.key);
    if (!side) continue;
    if (r.reaction === "liked") side === "F" ? fresh++ : rich++;
  }
  if (fresh === rich) return null;
  return fresh > rich ? "F" : "R";
}

function sweetnessVote(reading: CardReading): Letter | null {
  const sides = new Set<Letter>();
  const level = readLevel(reading, "sweetness");
  for (const r of reading.reactions) {
    if (r.subject.domain !== "taste" || r.subject.key !== "sweetness") continue;
    if (r.phase === "finish") {
      if (r.reaction === "liked") sides.add("S"); // 달콤한 끝맛이 좋았어요
      else if (r.reaction === "burden") sides.add("D"); // 단맛이 오래 남아서 물렸어요
      continue;
    }
    if (r.reaction === "liked") {
      if (r.qualifier === "gentle") sides.add("D");
      else if (r.qualifier === "pronounced") sides.add("S");
      else if (level !== null && level <= 2) sides.add("D");
      else if (level !== null && level >= 4) sides.add("S");
    } else if (r.reaction === "burden") {
      if (r.qualifier === "excessive" || r.qualifier === "masking") {
        sides.add("D");
      } else if (r.qualifier === "too_weak") sides.add("S");
      else if (level !== null && level >= 4) sides.add("D");
    }
  }
  return sides.size === 1 ? [...sides][0] : null;
}

function weightVote(reactions: readonly ReactionFact[]): Letter | null {
  // 가벼움·묵직함·열감: liking weight or warmth leans heavy, liking lightness
  // (or finding weight or heat a burden) leans light. Finish answers count too.
  const sides = new Set<Letter>();
  for (const r of reactions) {
    if (r.subject.domain !== "mouthfeel") continue;
    const key = r.subject.key;
    if (key !== "light" && key !== "heavy" && key !== "warmth") continue;
    if (r.reaction !== "liked" && r.reaction !== "burden") continue;
    const towardHeavy = (key !== "light") === (r.reaction === "liked");
    sides.add(towardHeavy ? "H" : "L");
  }
  return sides.size === 1 ? [...sides][0] : null;
}

function finishVote(reactions: readonly ReactionFact[]): Letter | null {
  const sides = new Set<Letter>();
  for (const r of reactions) {
    if (r.phase !== "finish") continue;
    if (r.subject.domain === "finish") {
      if (r.subject.key === "clean" && r.reaction === "liked") sides.add("C");
      // 기분 좋게 이어졌어요, or 너무 빨리 사라졌어요: both want it to stay.
      if (r.subject.key === "persistence" && r.reaction !== "unstated") {
        sides.add("P");
      }
      // 코끝으로 올라오는 잔향 stayed and was welcome; 잡내 stayed as a burden.
      if (r.subject.key === "aroma_echo") sides.add("P");
      if (r.subject.key === "off_flavor") sides.add("C");
      continue;
    }
    // A taste or mouthfeel that stayed: welcome → P, a burden → C.
    if (r.reaction === "liked") sides.add("P");
    else if (r.reaction === "burden") sides.add("C");
  }
  return sides.size === 1 ? [...sides][0] : null;
}

/** One record's vote per axis, from its card reading. */
export function letterVotes(reading: CardReading): LetterVotes {
  return {
    aroma: aromaVote(reading.reactions),
    sweetness: sweetnessVote(reading),
    weight: weightVote(reading.reactions),
    finish: finishVote(reading.reactions),
  };
}

function emptyAxis(): LetterAxisState {
  return { letter: null, left_share: 0, right_share: 0, vote_count: 0 };
}

/**
 * Replays the records in order and returns the state after the last one and
 * every moment a letter appeared or flipped.
 */
export function computeTasteLetters(
  records: readonly LetterRecord[],
): { state: TasteLettersState; changes: LetterChange[] } {
  const ordered = [...records].sort((a, b) =>
    a.recorded_at.localeCompare(b.recorded_at) ||
    a.record_id.localeCompare(b.record_id)
  );
  const axes = Object.fromEntries(
    LETTER_AXES.map((axis) => [axis.key, emptyAxis()]),
  ) as Record<LetterAxis, LetterAxisState>;
  const changes: LetterChange[] = [];
  for (let i = 0; i < ordered.length; i++) {
    for (const axis of LETTER_AXES) {
      const current = axes[axis.key];
      let left = 0;
      let right = 0;
      let leftVotes = 0;
      let rightVotes = 0;
      let weight = 1;
      for (let j = i; j >= 0; j--) {
        const vote = ordered[j].votes[axis.key];
        if (vote === axis.left) {
          left += weight;
          leftVotes++;
        } else if (vote === axis.right) {
          right += weight;
          rightVotes++;
        }
        if (vote !== null) weight *= RECENCY_WEIGHT;
      }
      const voteCount = leftVotes + rightVotes;
      if (voteCount === 0 || ordered[i].votes[axis.key] === null) continue;
      const leftRatio = left / (left + right);
      const leftShare = Math.round(leftRatio * 100);
      // The heavier side; an even split keeps the letter shown.
      const letter = leftRatio > 0.5
        ? axis.left
        : leftRatio < 0.5
        ? axis.right
        : current.letter ?? axis.left;
      if (letter !== current.letter) {
        changes.push({
          record_id: ordered[i].record_id,
          product_name: ordered[i].product_name,
          changed_at: ordered[i].recorded_at,
          axis: axis.key,
          from_letter: current.letter,
          to_letter: letter,
          left_share: leftShare,
          right_share: 100 - leftShare,
        });
      }
      axes[axis.key] = {
        letter,
        left_share: leftShare,
        right_share: 100 - leftShare,
        vote_count: voteCount,
      };
    }
  }
  return {
    state: {
      rule_version: TASTE_LETTERS_RULE_VERSION,
      record_count: ordered.length,
      axes,
    },
    changes,
  };
}
