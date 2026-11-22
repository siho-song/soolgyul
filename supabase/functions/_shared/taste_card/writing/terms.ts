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
 *
 * The 다음 술 가이드 is explained the same way: every word of a chip
 * (Merlot(메를로), dry, 생막걸리) and every gauge name (당도, 타닌) opens the
 * dictionary term that names it.
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
  TasteCardGuidePick,
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

/**
 * The guide's gauges by name, to the axis each one marks and its kind word.
 * 도수 has no term, and neither do the label numbers a sake gauge is read
 * from (일본주도, 산도): 당도(주도) opens the sweetness it stands for.
 */
const GAUGE_TERMS: Readonly<
  Record<string, readonly [axis: string, kind: string]>
> = {
  당도: ["sweetness", "맛"],
  단맛: ["sweetness", "맛"],
  산도: ["acidity", "맛"],
  산미: ["acidity", "맛"],
  타닌: ["astringency", "질감"],
  바디: ["body", "질감"],
  탄산: ["carbonation", "질감"],
};

/** The kind word of a sensation's term (axis:sweetness is 맛), whatever names it. */
export function sensationKind(type: string, key: string): string | undefined {
  return Object.values(SUBJECT_TERMS).find(([t, k]) => t === type && k === key)
    ?.[2] ??
    (type === "axis"
      ? Object.values(GAUGE_TERMS).find(([axis]) => axis === key)?.[1]
      : undefined);
}

/** A term's name across the dictionary: its type and its key within it. */
export const termKey = (term: Pick<Term, "type" | "key">): string =>
  `${term.type}:${term.key}`;

/** Words compare without spaces: the tag 체리향 is the text's 체리 향. */
const fold = (word: string) => word.replace(/\s+/g, "");

function entry(term: Term | undefined, kind: string): Entry | null {
  const description = term?.summary?.trim();
  return term && description
    ? { key: termKey(term), label: term.names.ko, kind, description }
    : null;
}

/**
 * Words a card written before 2026-11-16 set in bold or tagged and a card
 * written now does not: 쓴맛 is no longer asked, and 잔향 is named by the
 * finish aromas. A stored card keeps their explanations.
 */
const RETIRED_WORDS: Readonly<Record<string, readonly string[]>> = {
  bitterness: ["쌉쌀함", "쓴맛"],
  aroma_echo: ["잔향"],
};

/** The gauge names a reason sets in bold (묵직한 바디감, 깔끔한 끝맛), to the axis that explains each. */
const AXIS_WORDS: Readonly<
  Record<string, readonly [axis: string, kind: string]>
> = {
  바디감: ["body", "질감"],
  감칠맛: ["umami", "맛"],
  끝맛: ["finish_cleanliness", "여운"],
  "알싸한 자극": ["spice", "질감"],
  열감: ["spice", "질감"],
  자극: ["spice", "질감"],
  "피트·스모키 향": ["peat", "향"],
};

const IN_TEXT_ONLY: ReadonlySet<string> = new Set(["열감", "자극"]);

/**
 * The aromas a card explains. An aroma everyone knows by its name (자두,
 * 체리, 꿀, 장미) opens nothing (the user's review, 2026-11-22); these are
 * the ones whose name alone does not say what is smelled in a drink.
 */
const UNFAMILIAR_AROMAS: ReadonlySet<string> = new Set([
  "hop",
  "eucalyptus",
  "agave",
  "brioche",
  "malt",
  "creme_brulee",
  "toffee",
  "roasted",
  "cedar",
  "sandalwood",
  "cherry_wood",
  "oak",
  "peat",
  "smoke",
  "mineral",
  "saline",
  "wet_stone",
  "earth",
  "leather",
  "savory",
  "fermentation",
  "nuruk",
  "yeast",
  "ginjo_aroma",
  "clove",
  "coriander_seed",
  "juniper",
  "liquorice",
  "nutmeg",
  "sherry",
]);

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
        ...(RETIRED_WORDS[subject] ?? []),
        SUBJECT_LABEL[subject] ?? "",
        SUMMARY_LABEL[subject] ?? "",
      ]
    ) put(word, e);
  }
  // The names the reasons call a gauge by, where no sensation above has them.
  for (const [word, [axis, kind]] of Object.entries(AXIS_WORDS)) {
    put(word, entry(byKey.get(`axis:${axis}`), kind));
  }
  for (const t of terms("aroma", "aroma_family")) {
    if (!UNFAMILIAR_AROMAS.has(t.key)) continue;
    const e = entry(t, "향");
    for (const name of [aromaShort(t.key), t.names.ko]) {
      put(name, e);
      put(`${name} 향`, e);
    }
  }
  return map;
})();

/**
 * The explained words of a text, in the order they are set in bold, each
 * once. [kindKey] is the kind of the card's drink (red_wine): a place that
 * makes several kinds under one name (보르도) is explained as that one.
 */
export function textTerms(text: string, kindKey?: string): TasteCardTerm[] {
  const out: TasteCardTerm[] = [];
  for (const [, word] of text.matchAll(/\*\*(.+?)\*\*/g)) {
    if (out.some((t) => t.word === word)) continue;
    const sense = WORDS.get(fold(word));
    if (sense) {
      out.push({ word, ...sense });
      continue;
    }
    // A cause of the bottle the reason names (말벡, 셰리 캐스크, 라프로익):
    // the dictionary row of that name, as the dictionary explains it.
    const e = causeTerm(word, kindKey);
    if (e) out.push({ word, ...e });
  }
  return out;
}

/**
 * What explains a word, as a name to tell two words of one explanation by
 * (타닌 and 떫은맛 open the same balloon), or null when nothing explains it.
 */
export function explainedBy(word: string, kindKey?: string): string | null {
  const e = WORDS.get(fold(word)) ?? causeTerm(word, kindKey);
  return e ? `${e.kind}:${e.label}` : null;
}

/** A tag's explanation, or null when the dictionary has none for it. */
export function tagTerm(label: string): TasteCardTerm | null {
  const word = fold(label);
  // A tag names the step too (묵직한바디감, 단맛없음): it is explained by the
  // longest known word it ends on, 없음 aside. A tag of an older card that
  // names no known word (알코올열감) stays unexplained.
  const named = word.replace(/없음$/, "");
  for (let from = 0; from < named.length - 1; from++) {
    // 열감 and 자극 name the gauge in a sentence only: an older card's tag
    // 알코올열감 is not that gauge.
    if (IN_TEXT_ONLY.has(named.slice(from))) continue;
    const e = WORDS.get(named.slice(from));
    if (e) return { word: label, ...e };
  }
  return null;
}

/** A cask or method the guide names, by the name its chip opens with. */
const PICK_TERMS: ReadonlyMap<string, Entry> = new Map(
  terms("process", "maturation").flatMap((t) => {
    const e = entry(t, "제조·숙성");
    return e ? [[t.names.ko, e] as const] : [];
  }),
);

/**
 * A cask or method chip's explanation by its Korean name: 셰리 캐스크(Sherry
 * Cask) opens the dictionary's 셰리 캐스크. Kept for the cards stored before
 * a chip carried its words; [wordTerm] explains every word.
 */
export function pickTerm(keyword: string): TasteCardTerm | null {
  const e = PICK_TERMS.get(keyword.replace(/\(.*\)$/, "").trim());
  return e ? { word: keyword, ...e } : null;
}

/* ------------------------------------------------------------ guide words */

/**
 * The kind word a balloon shows beside a term a guide chip can name, by the
 * term's type. The order is also who keeps a name two rows share: 샤블리 is
 * the wine before it is the place, and 라이 is the grain before it is the
 * whisky made of it.
 */
/** The order a word two rows answer to is opened by: a wine named after its grape (람브루스코) is the wine. */
const WORD_KIND: Readonly<Record<string, string>> = {
  label_word: "라벨 표기",
  regional_style: "산지 스타일",
  grape: "품종",
  process: "제조·숙성",
  maturation: "제조·숙성",
  ingredient: "원재료",
  kind: "종류",
  region: "산지",
  producer: "생산자",
};

/**
 * The types 나의 용어 사전 files (glossary/glossary.ts). A term of another
 * type opens without its key, so its balloon offers no save.
 */
const SAVED_TYPES: ReadonlySet<string> = new Set([
  "grape",
  "process",
  "maturation",
  "region",
  "regional_style",
]);

/** A kind of drink in few words, as a style's balloon says it: 레드 와인 → 레드. */
const kindShort = (name: string) => name.replace(/ 와인$/, "");

const KINDS: readonly Term[] = terms("kind");
const KIND_BY_KEY = new Map(KINDS.map((t) => [t.key, t]));
const KIND_KEY_BY_NAME = new Map(KINDS.map((t) => [t.names.ko, t.key]));

/** The kind a regional style is a drink of, in few words (레드), or null. */
export function styleKindLabel(term: Term): string | null {
  const kind = KIND_BY_KEY.get(String(term.extra?.kind_key));
  return kind ? kindShort(kind.names.ko) : null;
}

/** The kind word a balloon shows beside a term: 품종, 산지 스타일 · 레드. */
export function wordKind(term: Term): string {
  const of = term.type === "regional_style" ? styleKindLabel(term) : null;
  return of ? `${WORD_KIND[term.type]} · ${of}` : WORD_KIND[term.type];
}

const WORD_ROWS: readonly Term[] = Object.keys(WORD_KIND).flatMap((type) =>
  terms(type)
);
const WORD_ROW_BY_KEY = new Map(WORD_ROWS.map((t) => [termKey(t), t]));

/** A row's explanation; a label word another row explains (생막걸리 → 비살균) opens that row. */
function wordEntry(term: Term): Entry | null {
  const told = WORD_ROW_BY_KEY.get(String(term.extra?.explained_by)) ?? term;
  const e = entry(told, wordKind(told));
  if (!e || SAVED_TYPES.has(told.type)) return e;
  return { label: e.label, kind: e.kind, description: e.description };
}

/** Label words compare without case, spaces, hyphens or accents: Pét-Nat is pet nat. */
const foldLabel = (word: string) =>
  word.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/[\s\-‐–]/g, "").replace(/[’`]/g, "'");

/** 산지오베제(키안티·브루넬로) is named 산지오베제. */
const bare = (name: string) => name.replace(/\(.*\)$/, "").trim();

/** A grape or an ingredient of two names answers to both and to each: 시라·쉬라즈, Syrah·Shiraz. */
const TWO_NAMED: ReadonlySet<string> = new Set(["grape", "ingredient"]);
const eachName = (t: Term, name: string | undefined) =>
  name && TWO_NAMED.has(t.type) ? [name, ...name.split("·")] : [name];

const labelWords = (t: Term) =>
  (t.hints?.label_words as string[] | undefined) ?? [];
const isCaskOrMethod = (t: Term) =>
  t.type === "process" || t.type === "maturation";

/**
 * What names a row, surest first: its Korean name, its label spelling (a
 * cask's or a method's is its first label word), its other names, the other
 * words a label prints for a cask or method, then the spellings it is
 * matched by. A word two rows answer to goes to the surer naming, then to
 * the earlier type. The label words of a kind, a grape or a regional style
 * name no row: they are what such a bottle may also print (스파클링 와인
 * lists demi-sec, 샤르도네 lists Chablis), not what the row is called.
 */
const NAMINGS: readonly ((t: Term) => (string | undefined)[])[] = [
  (t) => [t.names.ko, ...eachName(t, bare(t.names.ko))],
  (t) => eachName(t, t.names.label),
  (t) => isCaskOrMethod(t) ? [labelWords(t)[0]] : [],
  (t) => [t.names.en, ...(t.names.aliases ?? [])],
  (t) => isCaskOrMethod(t) ? labelWords(t) : [],
  (t) => t.names.label_patterns ?? [],
];

type Named = { sureness: number; entry: Entry; term: Term };

const WORD_TERMS: ReadonlyMap<string, Named> = (() => {
  const map = new Map<string, Named>();
  const explained = WORD_ROWS.flatMap((t) => {
    const e = wordEntry(t);
    return e ? [[t, e] as const] : [];
  });
  NAMINGS.forEach((naming, sureness) => {
    for (const [term, e] of explained) {
      for (const name of naming(term)) {
        const key = name ? foldLabel(name) : "";
        if (key && !map.has(key)) map.set(key, { sureness, entry: e, term });
      }
    }
  });
  return map;
})();

/**
 * The spellings a chip word may be looked up by: itself, and both sides of
 * 원어(한글). Quotes and the chip's own 표기 are not part of the word:
 * 'Bourbon Cask' 표기, 원재료명 '찹쌀' 표기.
 */
function spellings(text: string): string[] {
  const plain = text.trim().replace(/\s*표기(가 없는 것)?$/, "").trim();
  const word = plain.match(/^(?:[^'‘]*\s)?['‘](.+)['’]$/)?.[1] ?? plain;
  const pair = word.match(/^(.+?)\s*\(([^()]+)\)$/);
  return pair ? [word, pair[1], pair[2]] : [word];
}

function namedRow(spelled: readonly string[]): Named | null {
  let found: Named | undefined;
  for (const s of spelled) {
    const hit = WORD_TERMS.get(foldLabel(s));
    if (hit && (!found || hit.sureness < found.sureness)) found = hit;
  }
  return found ?? null;
}

const named = (spelled: readonly string[]): Entry | null =>
  namedRow(spelled)?.entry ?? null;

/** The regional styles of one name, a place's red, white and sparkling among them. */
const STYLES_NAMED: ReadonlyMap<string, readonly Term[]> = (() => {
  const map = new Map<string, Term[]>();
  for (const t of terms("regional_style")) {
    const name = foldLabel(bare(t.names.ko));
    map.set(name, [...(map.get(name) ?? []), t]);
  }
  return map;
})();

/** The style of that name that is a drink of the kind, when the name has one. */
function styleOfKind(word: string, kindKey?: string): Term | null {
  const all = kindKey ? STYLES_NAMED.get(foldLabel(word)) : undefined;
  if (!all) return null;
  return all.find((t) => t.extra?.kind_key === kindKey) ??
    all.find((t) =>
      (t.hints?.style_keys as string[] | undefined)?.includes(kindKey!)
    ) ?? null;
}

/**
 * The explanation of one word of a guide chip, however the chip writes it:
 * Merlot(메를로), 메를로, Sherry Cask(셰리 캐스크), 'Bourbon Cask', 생막걸리,
 * Triple Distilled. A number on a label is read as any number: '15 Years'
 * and '18 Years' open the same 숙성 연수.
 */
export function wordTerm(text: string): TasteCardTerm | null {
  const spelled = spellings(text);
  const e = named(spelled) ??
    named(spelled.map((s) => s.replace(/\d+/g, "0")));
  return e ? { word: text, ...e } : null;
}

const AXIS_BY_KEY = new Map(terms("axis").map((t) => [t.key, t]));

/** A cause's explanation by the name the text gives it; a verdict (부담) names no row. */
function causeTerm(word: string, kindKey?: string): Entry | null {
  const hit = namedRow([word]);
  if (hit?.term.type !== "regional_style") return hit?.entry ?? null;
  const own = styleOfKind(word, kindKey);
  return own && own !== hit.term ? wordEntry(own) ?? hit.entry : hit.entry;
}

/** A gauge name's explanation: 당도, 타닌, 산미(산도). 도수 has none. */
export function levelTerm(label: string): TasteCardTerm | null {
  const [axis, kind] = GAUGE_TERMS[bare(label)] ?? [];
  const e = axis ? entry(AXIS_BY_KEY.get(axis), kind) : null;
  return e ? { word: label, ...e } : null;
}

/**
 * A chip with every word explained. Its own term is its first word's, for an
 * app that reads one per chip; a card stored before chips carried words is
 * explained by its keyword.
 */
function withPickTerms(pick: TasteCardGuidePick): TasteCardGuidePick {
  if (!pick.words) {
    return { ...pick, term: pickTerm(pick.keyword) ?? wordTerm(pick.keyword) };
  }
  const words = pick.words.map((w) => ({ ...w, term: wordTerm(w.text) }));
  return { ...pick, words, term: words[0]?.term ?? null };
}

/** The view with its paragraphs', tags', guide chips' and gauges' explanations attached. */
export function withCardTerms(view: TasteCardView): TasteCardView {
  // The kind of the card's drink, as its product names it (레드 와인).
  const kindKey = KIND_KEY_BY_NAME.get(
    String(
      (view.product as { style_label?: string | null } | undefined)
        ?.style_label,
    ),
  );
  const explain = (paragraphs: TasteCardParagraph[]) =>
    paragraphs.map((p) => ({ ...p, terms: textTerms(p.text, kindKey) }));
  const tags = view.bite.tags.map((t): TasteCardTag => ({
    ...t,
    term: tagTerm(t.label),
  }));
  const guide = view.bite.guide && {
    ...view.bite.guide,
    picks: view.bite.guide.picks.map(withPickTerms),
    levels: view.bite.guide.levels?.map((l) => ({
      ...l,
      term: levelTerm(l.label),
    })),
  };
  // 다음 방향: the names a line tells the reader to look for.
  const next = view.bite.next && {
    lines: view.bite.next.lines.map((l) => ({
      ...l,
      terms: textTerms(l.text, kindKey),
    })),
  };
  return {
    ...view,
    bite: {
      ...view.bite,
      tags,
      guide,
      ...(view.bite.next === undefined ? {} : { next }),
    },
    positive: explain(view.positive),
    burden: explain(view.burden),
    balanced: explain(view.balanced),
  };
}
