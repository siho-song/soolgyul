/**
 * 나의 취향 조각 네 글자: four axes, one letter each, read from a person's records.
 *
 * Every axis is a ruler from 1 (its left letter) to 5 (its right letter), and
 * every record puts marks on it. A mark is an answer read against the bottle
 * it was said about: liking the sweetness of a very sweet bottle marks far to
 * the sweet side, finding an ordinary one too sweet marks the dry side, and
 * 적당했어요 marks where the bottle stands. The bottle stands at its level,
 * read half as the number and half as where that number sits among bottles of
 * its kind. An answer that names its own side (묵직해서, 은은해서) is never
 * moved off that side by the catalog.
 *
 * Marks do not weigh the same. An answer about the axis counts fully,
 * 적당했어요 half, and an answer about something next to the axis (열감,
 * 텁텁함, 잡내, an aroma that bothered) a little; the record's answer to
 * 다시 마시고 싶은지 moves each a quarter up or down.
 *
 * The person's place is the weighted average of the marks, recent records
 * counting more, started from the middle. So one record leans it a little and
 * no number of records carries it to the end. The letter is the side the
 * place leans to, so the letter and the shares shown under it always agree.
 * It shows once the axis has a liked or minded answer, or two 적당했어요. The
 * first letter of an axis, and a letter that came to lean clearly the other
 * way, are kept as moments of the person's 변천사.
 */
import type { CardReading } from "./facts/reading.ts";
import type { ReactionFact } from "./facts/facts.ts";
import { placeWithinKind } from "./facts/level_spread.ts";
import { NICKNAME_BASE_GROUPS } from "./nickname/catalog.ts";

const TASTE_LETTERS_RULE_VERSION = "taste-letters-v3";

const LETTER_AXES = [
  { key: "aroma", left: "F", right: "R" }, // 산 산뜻한 향 / 풍 풍부한 향
  { key: "sweetness", left: "D", right: "S" }, // 드 드라이 / 달 달콤한
  { key: "weight", left: "L", right: "H" }, // 가 가벼운 / 묵 묵직한
  { key: "finish", left: "C", right: "P" }, // 깔 깔끔한 여운 / 길 긴 여운
] as const;

export type LetterAxis = typeof LETTER_AXES[number]["key"];
type Letter = typeof LETTER_AXES[number]["left" | "right"];

/** One mark a record puts on an axis's ruler. */
export type LetterMark = {
  /** 1 (the left letter) to 5 (the right letter). */
  place: number;
  weight: number;
  /**
   * answer: liked or minded on the axis itself; one is enough to show a letter.
   * fine: 적당했어요 on the axis; two show a letter.
   * neighbour: an answer about something next to the axis. It moves a letter
   * and never shows one.
   */
  from: "answer" | "fine" | "neighbour";
};
export type LetterMarks = Readonly<Record<LetterAxis, readonly LetterMark[]>>;

/** One record's contribution, read from its card. */
export type LetterRecord = {
  record_id: string;
  product_name: string;
  /** ISO timestamp of the record; records are replayed in this order. */
  recorded_at: string;
  marks: LetterMarks;
};

type LetterAxisState = {
  letter: Letter | null;
  left_share: number;
  right_share: number;
  /** Records that put a mark on the axis. */
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

const LEFT = 1;
const RIGHT = 5;
const MIDDLE = 3;
/** Where an answer that names its side stands at least, and stands when the bottle has no level. */
const LOW_SIDE = 2;
const HIGH_SIDE = 4;
/**
 * The catalog's finish lengths nearly all read 4, so they tell bottles apart
 * too little to stand on: a finish answer stands half a step inside its end.
 */
const CLEAN_FINISH = 1.5;
const LONG_FINISH = 4.5;

const ANSWER_WEIGHT = 1;
const FINE_WEIGHT = 0.5;
const NEIGHBOUR_WEIGHT = 0.3;
/** 코끝 잔향 is about what stayed in the nose, a little beside the length itself. */
const AROMA_ECHO_WEIGHT = 0.7;
/** 다시 마시고 싶은지 moves a mark's weight this far up or down. */
const VERDICT_SHIFT = 0.25;
/** The place starts in the middle as if this many unmarked records stood there. */
const START_WEIGHT = 2;
/** An older record weighs this much of the one after it. */
const RECENCY_WEIGHT = 0.9;
/** A letter that turned is a moment once its side holds this share. */
const TURN_SHARE = 55;

// 향 families from the nickname catalogue: fresh ones lift, rich ones settle.
// 떼루아·세이보리·머스크 are neither and put no mark.
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

function aromaSide(key: string): "fresh" | "rich" | null {
  const family = AROMA_FAMILY.get(key);
  if (family && FRESH_FAMILIES.has(family)) return "fresh";
  if (family && RICH_FAMILIES.has(family)) return "rich";
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

/** Where the bottle stands on a ruler: its level, half as the number and half as its place in its kind. */
function bottlePlace(
  reading: CardReading,
  dimension: "sweetness" | "body",
): number | null {
  const level = readLevel(reading, dimension);
  if (level === null) return null;
  const within = placeWithinKind(dimension, reading.record.category, level);
  return within === null ? level : (level + within) / 2;
}

/** A mark before the record's 다시 마시고 싶은지 is weighed in. */
type Toned = LetterMark & { tone: "liked" | "fine" | "burden" };

/** Too much at this place: the middle of what lies a step or more below it. */
const lessThan = (place: number) => Math.max(LEFT, place / 2);
/** Too little at this place: the middle of what lies a step or more above it. */
const moreThan = (place: number) => Math.min(RIGHT, (place + RIGHT + 1) / 2);

/**
 * The mark of an answer about a sensation the ruler measures. `named` is the
 * side the answer itself spoke of: the high side praised (충분히 달아서,
 * 묵직해서) or found too much, the low side praised (은은해서, 가벼워서) or
 * found too little. An answer that names no side stands where the bottle
 * does, and says nothing when the bottle has no level.
 */
function rulerMark(
  tone: Toned["tone"],
  named: "high" | "low" | null,
  bottle: number | null,
): Toned | null {
  if (tone === "fine") {
    return bottle === null
      ? null
      : { place: bottle, weight: FINE_WEIGHT, from: "fine", tone };
  }
  let place: number | null;
  if (tone === "liked") {
    place = named === "high"
      ? Math.max(bottle ?? HIGH_SIDE, HIGH_SIDE)
      : named === "low"
      ? Math.min(bottle ?? LOW_SIDE, LOW_SIDE)
      : bottle;
  } else {
    place = named === "high"
      ? lessThan(bottle ?? HIGH_SIDE)
      : named === "low"
      ? moreThan(bottle ?? LOW_SIDE)
      : null;
  }
  return place === null
    ? null
    : { place, weight: ANSWER_WEIGHT, from: "answer", tone };
}

const neighbour = (place: number, tone: Toned["tone"]): Toned => ({
  place,
  weight: NEIGHBOUR_WEIGHT,
  from: "neighbour",
  tone,
});

function toneOf(reaction: ReactionFact["reaction"]): Toned["tone"] | null {
  return reaction === "liked" || reaction === "fine" || reaction === "burden"
    ? reaction
    : null;
}

function aromaMarks(reactions: readonly ReactionFact[]): Toned[] {
  // What was liked decides, as the mix it was: two fresh aromas and a rich
  // one lean fresh a little, three rich ones lean rich more than one does.
  const liked = { fresh: 0, rich: 0 };
  const minded = { fresh: 0, rich: 0 };
  for (const r of reactions) {
    if (r.subject.domain !== "aroma" || r.phase !== "drinking") continue;
    const side = aromaSide(r.subject.key);
    if (!side) continue;
    if (r.reaction === "liked") liked[side]++;
    else if (r.reaction === "burden") minded[side]++;
  }
  const marks: Toned[] = [];
  const count = liked.fresh + liked.rich;
  if (count > 0) {
    marks.push({
      place: LEFT + (RIGHT - LEFT) * (liked.rich + 0.5) / (count + 1),
      weight: ANSWER_WEIGHT,
      from: "answer",
      tone: "liked",
    });
  }
  // An aroma that bothered leans away from its side.
  if (minded.rich > 0) marks.push(neighbour(LOW_SIDE, "burden"));
  if (minded.fresh > 0) marks.push(neighbour(HIGH_SIDE, "burden"));
  return marks;
}

function sweetnessMarks(reading: CardReading): Toned[] {
  const level = readLevel(reading, "sweetness");
  const bottle = bottlePlace(reading, "sweetness");
  const marks: Toned[] = [];
  for (const r of reading.reactions) {
    if (
      r.subject.domain !== "taste" || r.subject.key !== "sweetness" ||
      r.phase !== "drinking"
    ) continue;
    const tone = toneOf(r.reaction);
    if (!tone) continue;
    let named: "high" | "low" | null = null;
    if (tone === "liked") {
      if (r.qualifier === "pronounced") named = "high";
      else if (r.qualifier === "gentle") named = "low";
    } else if (tone === "burden") {
      if (r.qualifier === "excessive" || r.qualifier === "masking") {
        named = "high";
      } else if (r.qualifier === "too_weak") named = "low";
      // 아쉬웠어요 with no reason, about a sweet bottle: its sweetness.
      else if (level !== null && level >= HIGH_SIDE) named = "high";
    }
    const mark = rulerMark(tone, named, bottle);
    if (mark) marks.push(mark);
  }
  return marks;
}

function weightMarks(reading: CardReading): Toned[] {
  const bottle = bottlePlace(reading, "body");
  const marks: Toned[] = [];
  for (const r of reading.reactions) {
    if (r.subject.domain !== "mouthfeel") continue;
    const tone = toneOf(r.reaction);
    if (!tone) continue;
    const key = r.subject.key;
    if (r.phase === "finish") {
      // 텁텁하고 무거운 느낌이 남았어요 leans light.
      if (key === "heavy" && tone === "burden") {
        marks.push(neighbour(LOW_SIDE, tone));
      }
      continue;
    }
    if (key === "light" || key === "heavy") {
      // 무게감 itself. 가벼워서 아쉬웠어요 wanted more, 묵직해서 아쉬웠어요 less.
      const mark = rulerMark(tone, key === "heavy" ? "high" : "low", bottle);
      if (mark) marks.push(mark);
    } else if (key === "warmth" && tone !== "fine") {
      // 열감 sits next to weight: welcome leans heavy, a burden leans light.
      marks.push(neighbour(tone === "liked" ? HIGH_SIDE : LOW_SIDE, tone));
    }
  }
  return marks;
}

function finishMarks(reactions: readonly ReactionFact[]): Toned[] {
  const marks: Toned[] = [];
  for (const r of reactions) {
    if (r.phase !== "finish") continue;
    const tone = toneOf(r.reaction);
    if (!tone || tone === "fine") continue;
    const answer = (place: number, weight = ANSWER_WEIGHT): Toned => ({
      place,
      weight,
      from: "answer",
      tone,
    });
    if (r.subject.domain === "finish") {
      const key = r.subject.key;
      // 기분 좋게 이어졌어요, or 너무 빨리 사라졌어요: both want it to stay.
      if (key === "persistence") marks.push(answer(LONG_FINISH));
      if (key === "clean" && tone === "liked") marks.push(answer(CLEAN_FINISH));
      if (key === "aroma_echo" && tone === "liked") {
        marks.push(answer(LONG_FINISH, AROMA_ECHO_WEIGHT));
      }
      // 잡내 stayed as a burden: nobody welcomes it, so it only leans.
      if (key === "off_flavor" && tone === "burden") {
        marks.push(neighbour(LOW_SIDE, tone));
      }
    } else if (
      r.subject.domain === "mouthfeel" && r.subject.key === "heavy" &&
      tone === "burden"
    ) {
      // 텁텁함 stayed as a burden.
      marks.push(neighbour(LOW_SIDE, tone));
    }
  }
  return marks;
}

/**
 * The record's own verdict weighs its marks: what was liked in a drink wanted
 * again counts more and what was minded in it less, the other way round in a
 * drink not wanted again. 적당했어요 in a drink not wanted again was no
 * comfort and is dropped.
 */
function weighByVerdict(
  marks: readonly Toned[],
  revisit: CardReading["record"]["revisit"],
): LetterMark[] {
  const out: LetterMark[] = [];
  for (const { tone, ...mark } of marks) {
    let weight = mark.weight;
    if (revisit === "want_again") {
      weight *= tone === "burden" ? 1 - VERDICT_SHIFT : 1 + VERDICT_SHIFT;
    } else if (revisit === "do_not_want_again") {
      if (tone === "fine") continue;
      weight *= tone === "burden" ? 1 + VERDICT_SHIFT : 1 - VERDICT_SHIFT;
    }
    out.push({ ...mark, weight });
  }
  return out;
}

/** One record's marks per axis, from its card reading. */
export function letterMarks(reading: CardReading): LetterMarks {
  const revisit = reading.record.revisit;
  return {
    aroma: weighByVerdict(aromaMarks(reading.reactions), revisit),
    sweetness: weighByVerdict(sweetnessMarks(reading), revisit),
    weight: weighByVerdict(weightMarks(reading), revisit),
    finish: weighByVerdict(finishMarks(reading.reactions), revisit),
  };
}

function emptyAxis(): LetterAxisState {
  return { letter: null, left_share: 0, right_share: 0, vote_count: 0 };
}

/** What the replay keeps for one axis as the records go by. */
type AxisRun = {
  /** Marks of the records that spoke on the axis, oldest first. */
  spoke: (readonly LetterMark[])[];
  answers: number;
  fines: number;
  letter: Letter | null;
  /** The letter of the last moment kept. */
  noted: Letter | null;
};

function emptyRun(): AxisRun {
  return { spoke: [], answers: 0, fines: 0, letter: null, noted: null };
}

/** The right letter's share of the place the marks average to, in whole percent. */
function rightShare(spoke: AxisRun["spoke"]): number {
  let weight = 0;
  let sum = 0;
  let fade = 1;
  for (let i = spoke.length - 1; i >= 0; i--) {
    for (const mark of spoke[i]) {
      weight += mark.weight * fade;
      sum += mark.weight * fade * mark.place;
    }
    fade *= RECENCY_WEIGHT;
  }
  const place = (START_WEIGHT * MIDDLE + sum) / (START_WEIGHT + weight);
  // Rounded as a distance from the middle, so both sides round alike.
  const lean = (place - LEFT) / (RIGHT - LEFT) * 100 - 50;
  return 50 + Math.sign(lean) * Math.round(Math.abs(lean));
}

/**
 * Replays the records in order and returns the state after the last one and
 * every moment a letter first showed or came to lean clearly the other way.
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
  const runs = Object.fromEntries(
    LETTER_AXES.map((axis) => [axis.key, emptyRun()]),
  ) as Record<LetterAxis, AxisRun>;
  const changes: LetterChange[] = [];
  for (const record of ordered) {
    for (const axis of LETTER_AXES) {
      const marks = record.marks[axis.key];
      if (marks.length === 0) continue;
      const run = runs[axis.key];
      run.spoke.push(marks);
      run.answers += marks.filter((mark) => mark.from === "answer").length;
      run.fines += marks.filter((mark) => mark.from === "fine").length;
      const right = rightShare(run.spoke);
      // The leaning side; an even place keeps the letter shown.
      if ((run.answers >= 1 || run.fines >= 2) && right !== 50) {
        run.letter = right > 50 ? axis.right : axis.left;
      }
      if (run.letter === null) {
        axes[axis.key] = { ...emptyAxis(), vote_count: run.spoke.length };
        continue;
      }
      axes[axis.key] = {
        letter: run.letter,
        left_share: 100 - right,
        right_share: right,
        vote_count: run.spoke.length,
      };
      const own = run.letter === axis.right ? right : 100 - right;
      if (
        run.noted === null || (run.letter !== run.noted && own >= TURN_SHARE)
      ) {
        changes.push({
          record_id: record.record_id,
          product_name: record.product_name,
          changed_at: record.recorded_at,
          axis: axis.key,
          from_letter: run.noted,
          to_letter: run.letter,
          left_share: 100 - right,
          right_share: right,
        });
        run.noted = run.letter;
      }
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
