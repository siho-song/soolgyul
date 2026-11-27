/**
 * The words for what is sensed (catalog/dictionary/senses.json): aromas,
 * textures and finishes. Every question about such a word is answered here:
 * what it is called, what it is a kind of, what impressions it gives, and
 * which of them a reader is offered to pick.
 */
import {
  type FamilyNode,
  SENSES,
  type SensesFile,
  type WordNode,
} from "./files.ts";

/** A word with its type, its family and the word above it. */
export type SenseRow = {
  word: WordNode;
  /** aroma, texture or finish_character. */
  type: string;
  family: FamilyNode | null;
  above: string | null;
};

const TYPE_OF_FAMILY: Record<string, string> = {
  descriptor: "aroma",
  texture: "texture",
  finish_character: "finish_character",
};

/** Every word of the file, a word before the narrower words under it. */
export const SENSE_ROWS: readonly SenseRow[] = (() => {
  const out: SenseRow[] = [];
  const walk = (
    words: WordNode[],
    type: string,
    family: FamilyNode | null,
    above: string | null,
  ) => {
    for (const word of words) {
      out.push({ word, type, family, above });
      walk(word.words ?? [], type, family, word.key);
    }
  };
  for (const family of SENSES.families) {
    walk(family.words, TYPE_OF_FAMILY[family.of], family, null);
  }
  for (const [type, words] of Object.entries(SENSES.words_of_no_family)) {
    walk(words, type, null, null);
  }
  return out;
})();

export const SENSE_FAMILIES: SensesFile["families"] = SENSES.families;
export const SENSE_AXES: SensesFile["axes"] = SENSES.axes;
export const SENSE_TRAITS: SensesFile["traits"] = SENSES.traits;

const ROW_BY_KEY = new Map(SENSE_ROWS.map((row) => [row.word.key, row]));

/** Whether the dictionary holds [key] as an aroma, offered or not. */
export function isAroma(key: string): boolean {
  return ROW_BY_KEY.get(key)?.type === "aroma";
}

/**
 * The impressions an aroma word gives (sweet_scent, fruit_scent, …): its own
 * and its family's. A narrower word that states none takes the word above it.
 */
export function aromaTraits(key: string): readonly string[] {
  for (
    let row = ROW_BY_KEY.get(key);
    row;
    row = ROW_BY_KEY.get(row.above ?? "")
  ) {
    if (row.word.traits?.length) {
      return [...new Set([...row.word.traits, ...(row.family?.traits ?? [])])];
    }
    if (!row.above) return row.family?.traits ?? [];
  }
  return [];
}

/* ------------------------------------------------- what an aroma is a kind of */

/** The aroma above each aroma a bottle can be tagged with (a word kept for its meaning only is no tag). */
const AROMA_ABOVE = new Map<string, string | null>(
  SENSE_ROWS.filter((row) => row.type === "aroma" && !row.word.meaning_only)
    .map((row) => [row.word.key, row.above]),
);

/**
 * An aroma, then each aroma it is a kind of, up to the widest (레몬 →
 * 시트러스 → 과일). A key the dictionary does not hold yields only itself.
 *
 * A reader's answer and a bottle's tag are taken as the same observation
 * when one sits above the other on that line: the reader's 복숭아 meets a
 * bottle's 핵과. A wide name is never read as a narrower one nobody named.
 */
export function aromaLine(key: string): string[] {
  const out: string[] = [];
  let current: string | null = key;
  while (current !== null && !out.includes(current)) {
    out.push(current);
    current = AROMA_ABOVE.get(current) ?? null;
  }
  return out;
}

/** True when the two aromas are the same or one is a kind of the other. */
export function sameAromaLine(a: string, b: string): boolean {
  return a === b || aromaLine(a).includes(b) || aromaLine(b).includes(a);
}

/* ------------------------------------------------ the words a reader picks */

/** A word the questionnaire offers, with the bottle tags that are shown as it. */
export type SenseChoice = {
  key: string;
  /** The word's name (`ko`), which the picker and every text show. */
  label: string;
  /** The picker's group the word sits in (과일, 꽃, 향신료 …). */
  group: string;
  /** descriptor (an aroma), texture or finish_character. */
  of: string;
  /** The bottle tags shown as this word: narrower words and other spellings. */
  tags: string[];
  /** Other words a tasting note names it by. */
  found_by: string[];
  /** Where the word can be said: aroma, palate, finish. */
  said_of: string[];
  /** The dictionary's explanation of the word, or null. */
  description: string | null;
  /** The impressions the word gives. */
  traits: string[];
};

const OF: Record<string, string> = {
  aroma: "descriptor",
  texture: "texture",
  finish_character: "finish_character",
};

/** The offered word each word is shown as: the one it names, else the nearest offered word at or above it. */
const SHOWN_AS: ReadonlyMap<string, string | null> = (() => {
  const offered = new Set(
    SENSE_ROWS.filter((r) => r.word.choice).map((r) => r.word.key),
  );
  const above = new Map(SENSE_ROWS.map((r) => [r.word.key, r.above]));
  const out = new Map<string, string | null>();
  for (const { word } of SENSE_ROWS) {
    if (word.shown_as !== undefined) {
      out.set(word.key, word.shown_as);
      continue;
    }
    let key: string | null = word.key;
    while (key !== null && !offered.has(key)) key = above.get(key) ?? null;
    out.set(word.key, key);
  }
  return out;
})();

/** What the dictionary says of a word, by key; a family of the same key speaks where the word does not. */
const SAID: ReadonlyMap<string, { description: string; traits: string[] }> =
  (() => {
    const out = new Map<string, { description: string; traits: string[] }>();
    for (const row of [...SENSE_FAMILIES, ...SENSE_ROWS.map((r) => r.word)]) {
      if (row.summary) {
        out.set(row.key, {
          description: row.summary,
          traits: row.traits ?? [],
        });
      }
    }
    return out;
  })();

const CHOICES: readonly SenseChoice[] = (() => {
  const taggable = new Set(
    SENSE_ROWS.filter((r) => !r.word.meaning_only).map((r) => r.word.key),
  );
  return SENSE_ROWS.filter((r) => r.word.choice)
    .sort((a, b) => a.word.choice!.order - b.word.choice!.order)
    .map(({ word, type }): SenseChoice => ({
      key: word.key,
      label: word.ko,
      group: word.choice!.group,
      of: OF[type],
      tags: [...SHOWN_AS].filter(([key, shown]) =>
        shown === word.key && taggable.has(key)
      ).map(([key]) => key),
      found_by: word.choice!.found_by ?? [],
      said_of: word.choice!.said_of ?? word.said_of ?? [],
      description: SAID.get(word.key)?.description ?? null,
      traits: SAID.get(word.key)?.traits ?? [],
    }));
})();

const CHOICE_BY_KEY = new Map(CHOICES.map((choice) => [choice.key, choice]));
/** A tag to the offered word it is shown as; an offered word is shown as itself unless it names another. */
const CHOICE_OF_TAG = new Map(
  CHOICES.flatMap((choice) =>
    [choice.key, ...choice.tags].map((tag) => [tag, choice.key] as const)
  ),
);

/**
 * The name a reader is shown for an aroma (체리, 레몬): that of the offered
 * word it is shown as, so a bottle's 붉은 체리 is named 체리. Null for an
 * aroma shown as no offered word (향신료, 과일), which is not spoken of, and
 * for a key that is no aroma.
 */
export function aromaName(key: string): string | null {
  if (!isAroma(key)) return null;
  return CHOICE_BY_KEY.get(CHOICE_OF_TAG.get(key) ?? "")?.label ?? null;
}

/** Every word the questionnaire offers, in the picker's order. */
export function senseChoices(): readonly SenseChoice[] {
  return CHOICES;
}

/** An offered word by its key, or null when the questionnaire does not offer it. */
export function senseChoiceByKey(key: string): SenseChoice | null {
  return CHOICE_BY_KEY.get(key) ?? null;
}

/** The offered word a bottle's tag is shown as (lemon → citrus), or null when it is shown as none. */
export function senseChoiceOfTag(tag: string): string | null {
  return CHOICE_OF_TAG.get(tag) ?? null;
}
