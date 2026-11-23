/**
 * 용어 도움말: what the dictionary shows of a term when a reader opens it
 * (the help balloon of a card, a bottle's facts in 나에게 맞는 술 찾기, and
 * 나의 용어 사전, which keeps the terms saved from either). One term reads the
 * same wherever it is opened, and can be saved from every place or from none.
 */
import { kindByKey, type Term, termByKey, termKey } from "./dictionary.ts";

/** What a help balloon shows of a term. */
export type TermHelp = {
  /** The key 나의 용어 사전 saves the term by (grape:merlot); absent when the term cannot be saved. */
  key?: string;
  /** The dictionary's name: 체리, 셰리 캐스크, 스페이사이드. */
  label: string;
  /** What the term is: 향, 맛, 질감, 여운, 품종, 산지, 산지 스타일 · 레드, 제조·숙성, 생산자, 라벨 표기, 원재료, 종류. */
  kind: string;
  description: string;
};

/** What each taste gauge is felt as. A gauge left out (향의 세기) opens no help. */
const KIND_OF_AXIS: Readonly<Record<string, string>> = {
  sweetness: "맛",
  acidity: "맛",
  bitterness: "맛",
  umami: "맛",
  astringency: "질감",
  body: "질감",
  carbonation: "질감",
  spice: "질감",
  finish_length: "여운",
  finish_cleanliness: "여운",
  peat: "향",
};

/** What a term of each type is. A type left out opens no help. */
const KIND_OF_TYPE: Readonly<Record<string, string>> = {
  aroma: "향",
  aroma_family: "향",
  texture: "질감",
  grape: "품종",
  region: "산지",
  regional_style: "산지 스타일",
  process: "제조·숙성",
  maturation: "제조·숙성",
  producer: "생산자",
  label_word: "라벨 표기",
  ingredient: "원재료",
  kind: "종류",
};

/**
 * The types 나의 용어 사전 files. A term of another type (a label word, an
 * ingredient, a kind of drink) opens without a key, so its balloon offers no
 * save.
 */
const SAVED_TYPES: ReadonlySet<string> = new Set([
  "axis",
  "aroma",
  "aroma_family",
  "texture",
  "grape",
  "region",
  "regional_style",
  "process",
  "maturation",
  "producer",
]);

/** The kind a regional style is a drink of, in few words (레드 와인 → 레드), or null. */
export function styleKindLabel(style: Term): string | null {
  return kindByKey(style.kind_key)?.names.ko.replace(/ 와인$/, "") ?? null;
}

/** What a term is, as a balloon says it beside the name: 품종, 산지 스타일 · 레드. Null for a term that opens no help. */
export function kindWordOf(term: Term): string | null {
  if (term.type === "axis") return KIND_OF_AXIS[term.key] ?? null;
  const word = KIND_OF_TYPE[term.type] ?? null;
  const of = term.type === "regional_style" ? styleKindLabel(term) : null;
  return word && of ? `${word} · ${of}` : word;
}

/**
 * The help a term opens, or null when the dictionary does not explain it. A
 * label word another row explains (생막걸리 → 비살균) opens that row.
 */
export function termHelp(term: Term | null | undefined): TermHelp | null {
  if (!term) return null;
  const [type, key] = term.explained_by?.split(":") ?? [];
  const told = termByKey(type ?? "", key) ?? term;
  const kind = kindWordOf(told);
  if (!kind || !told.summary) return null;
  return {
    ...(SAVED_TYPES.has(told.type) ? { key: termKey(told) } : {}),
    label: told.names.ko,
    kind,
    description: told.summary,
  };
}

/** The help of the term a saved key names (grape:merlot), or null when it cannot be saved. */
export function savedTermHelp(
  savedKey: string,
): { term: Term; help: TermHelp & { key: string } } | null {
  const at = savedKey.indexOf(":");
  const term = at < 0
    ? null
    : termByKey(savedKey.slice(0, at), savedKey.slice(at + 1));
  const help = termHelp(term);
  return term && help?.key === savedKey
    ? { term, help: { ...help, key: savedKey } }
    : null;
}
