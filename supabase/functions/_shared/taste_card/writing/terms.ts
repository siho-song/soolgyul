/**
 * The dictionary's explanation of the words a card sets in bold (체리 향,
 * 산미, 떫은 조임) and of its 핵심 요약 tags (체리향, 떫은맛), so the reader
 * can open a word they do not know. Nothing is stored: a card's words are
 * looked up when it is served, so every card, old ones included, carries the
 * dictionary as it stands.
 *
 * A bold word is one the writer chose for a sensation (writing/sections.ts
 * EMPHASIS_WORDS, the aroma's short name) or a verdict (기분 좋은 매력, 부담);
 * only the former are in the dictionary, so a verdict stays plain.
 */
import { type Term, terms } from "../dictionary/dictionary.ts";
import {
  aromaShort,
  EMPHASIS_FALLBACK,
  EMPHASIS_WORDS,
  SUBJECT_LABEL,
  SUMMARY_LABEL,
} from "./words.ts";
import type {
  TasteCardParagraph,
  TasteCardTag,
  TasteCardTerm,
  TasteCardView,
} from "../service/types.ts";

type Entry = Omit<TasteCardTerm, "word">;

/**
 * The dictionary term that explains a sensation the card names, and the kind
 * word the balloon shows beside it. Sensations without an explained term
 * (warmth, off_flavor) are left out.
 */
const SUBJECT_TERMS: Readonly<
  Record<string, readonly [type: string, key: string, kind: string]>
> = {
  sweetness: ["axis", "sweetness", "맛"],
  acidity: ["axis", "acidity", "맛"],
  bitterness: ["axis", "bitterness", "맛"],
  drying: ["axis", "astringency", "질감"],
  light: ["texture", "light_texture", "질감"],
  heavy: ["texture", "heavy_texture", "질감"],
  smooth: ["texture", "smooth_texture", "질감"],
  bubbles: ["axis", "carbonation", "질감"],
  persistence: ["axis", "finish_length", "여운"],
  lingering: ["axis", "finish_length", "여운"],
  aroma_echo: ["axis", "finish_length", "여운"],
  clean: ["axis", "finish_cleanliness", "여운"],
};

/** Words compare without spaces: the tag 체리향 is the text's 체리 향. */
const fold = (word: string) => word.replace(/\s+/g, "");

function entry(term: Term | undefined, kind: string): Entry | null {
  const description = term?.summary?.trim();
  return term && description
    ? { label: term.names.ko, kind, description }
    : null;
}

/** Every word the card may set in bold or tag, to the term that explains it. */
const WORDS: ReadonlyMap<string, Entry> = (() => {
  const map = new Map<string, Entry>();
  const put = (word: string, e: Entry | null) => {
    const key = fold(word);
    if (e && key.length > 1 && !map.has(key)) map.set(key, e);
  };
  const byKey = new Map(
    terms("axis", "texture").map((t) => [`${t.type}:${t.key}`, t]),
  );
  for (const [subject, [type, key, kind]] of Object.entries(SUBJECT_TERMS)) {
    const e = entry(byKey.get(`${type}:${key}`), kind);
    for (
      const word of [
        ...(EMPHASIS_WORDS[subject] ?? []),
        ...(EMPHASIS_FALLBACK[subject] ?? []),
        SUBJECT_LABEL[subject] ?? "",
        SUMMARY_LABEL[subject] ?? "",
      ]
    ) put(word, e);
  }
  for (const t of terms("aroma", "aroma_family")) {
    const e = entry(t, "향");
    for (const name of [aromaShort(t.key), t.names.ko]) {
      put(name, e);
      put(`${name} 향`, e);
    }
  }
  return map;
})();

/** The explained words of a text, in the order they are set in bold, each once. */
export function textTerms(text: string): TasteCardTerm[] {
  const out: TasteCardTerm[] = [];
  for (const [, word] of text.matchAll(/\*\*(.+?)\*\*/g)) {
    const e = WORDS.get(fold(word));
    if (e && !out.some((t) => t.word === word)) out.push({ word, ...e });
  }
  return out;
}

/** A tag's explanation, or null when the dictionary has none for it. */
export function tagTerm(label: string): TasteCardTerm | null {
  const e = WORDS.get(fold(label));
  return e ? { word: label, ...e } : null;
}

/** A cask or method the guide names, by the name its chip opens with. */
const PICK_TERMS: ReadonlyMap<string, Entry> = new Map(
  terms("process", "maturation").flatMap((t) => {
    const e = entry(t, "제조·숙성");
    return e ? [[t.names.ko, e] as const] : [];
  }),
);

/**
 * A guide chip's explanation: 셰리 캐스크(Sherry Cask) opens the dictionary's
 * 셰리 캐스크. A grape, a grade or a quoted label word has none.
 */
export function pickTerm(keyword: string): TasteCardTerm | null {
  const e = PICK_TERMS.get(keyword.replace(/\(.*\)$/, "").trim());
  return e ? { word: keyword, ...e } : null;
}

/** The view with its paragraphs', tags' and guide chips' explanations attached. */
export function withCardTerms(view: TasteCardView): TasteCardView {
  const explain = (paragraphs: TasteCardParagraph[]) =>
    paragraphs.map((p) => ({ ...p, terms: textTerms(p.text) }));
  const tags = view.bite.tags.map((t): TasteCardTag => ({
    ...t,
    term: tagTerm(t.label),
  }));
  const guide = view.bite.guide && {
    ...view.bite.guide,
    picks: view.bite.guide.picks.map((p) => ({
      ...p,
      term: pickTerm(p.keyword),
    })),
  };
  return {
    ...view,
    bite: { ...view.bite, tags, guide },
    positive: explain(view.positive),
    burden: explain(view.burden),
    balanced: explain(view.balanced),
  };
}
