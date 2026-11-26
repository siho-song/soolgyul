/**
 * 나의 취향 조각 네 글자: four axes, one letter each, from the marks a
 * person's records put on them.
 *
 * Every axis is a ruler from 1 (its left letter) to 5 (its right letter). A
 * mark says where on the ruler one answer stands and how much it weighs;
 * how an answer becomes a mark is marks_from_record.ts, and nothing here
 * knows what was asked or what was drunk.
 *
 * The person's place is the weighted average of the marks, recent records
 * counting more, started from the middle. So one record leans it a little
 * and no number of records carries it to the end. The letter is the side the
 * place leans to, so the letter and the shares shown under it always agree.
 * It shows once the axis has a liked or minded answer. The first letter of
 * an axis, and a letter that came to lean clearly the other way, are kept as
 * moments of the person's 변천사.
 */
const TASTE_LETTERS_RULE_VERSION = "taste-letters-v5";

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
   * neighbour: an answer about something next to the axis. It moves a letter
   * and never shows one.
   */
  from: "answer" | "neighbour";
};
export type LetterMarks = Readonly<Record<LetterAxis, readonly LetterMark[]>>;

/** One record's marks, and what a moment of the 변천사 says of it. */
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

/** The ends and the middle of every ruler. */
export const LEFT = 1;
export const RIGHT = 5;
export const MIDDLE = 3;

/** An older record weighs this much of the one after it. */
const RECENCY_WEIGHT = 0.9;
/** A letter that turned is a moment once its side holds this share. */
const TURN_SHARE = 55;
/** The place starts in the middle as if this many unmarked records stood there. */
const START_WEIGHT = 2;

function emptyAxis(): LetterAxisState {
  return { letter: null, left_share: 0, right_share: 0, vote_count: 0 };
}

/** What the replay keeps for one axis as the records go by. */
type AxisRun = {
  /** Marks of the records that spoke on the axis, oldest first. */
  spoke: (readonly LetterMark[])[];
  answers: number;
  letter: Letter | null;
  /** The letter of the last moment kept. */
  noted: Letter | null;
};

function emptyRun(): AxisRun {
  return { spoke: [], answers: 0, letter: null, noted: null };
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
export function lettersFromMarks(
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
      const right = rightShare(run.spoke);
      // The leaning side; an even place keeps the letter shown.
      if (run.answers >= 1 && right !== 50) {
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
