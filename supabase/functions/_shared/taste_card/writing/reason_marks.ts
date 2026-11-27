/** The words of a line the dictionary explains, marked so that the app opens them. */
import {
  plainName,
  terms,
} from "../../record_reading/dictionary/dictionary.ts";
import { explainedBy } from "./help_balloons.ts";
import { AXIS } from "./reason_words.ts";

/** Names the card's own sentences use as plain words: 물리지 않고, 오렌지 와인, 포르투갈. */
export const NOT_A_NAME: ReadonlySet<string> = new Set([
  "물리",
  "오렌지",
  "포르투",
  "피노",
  "포도",
  "허브",
]);

/** The grains and ferments a clause names; a fruit in a clause is an aroma, not what the drink is made of. */
export const MADE_OF: ReadonlySet<string> = new Set([
  "효모",
  "유산균",
  "코지",
  "백국",
  "황국",
  "누룩",
  "보리",
  "맥아",
  "옥수수",
  "호밀",
  "귀리",
  "찹쌀",
  "오마치 쌀",
  "수수",
  "메밀",
  "고구마",
  "홉",
]);

export const KIND_NAMES: ReadonlySet<string> = new Set(
  terms("kind").map((t) => t.names.ko),
);

/**
 * The words a line may hold that the dictionary explains, longest first: the
 * tastes by their names, and the grapes, places, casks, ways of making,
 * grains and label words by theirs. A maker is marked only on its own
 * bottle (마시 is also 마시기 좋아요).
 */
export const EXPLAINED: readonly string[] = (() => {
  const names = new Set<string>([
    ...Object.values(AXIS).map((a) => a.noun),
    "신맛",
  ]);
  for (
    const t of terms(
      "grape",
      "regional_style",
      "region",
      "process",
      "maturation",
      "label_word",
      "kind",
      "ingredient",
    )
  ) {
    const name = plainName(t.names.ko);
    if (t.type === "ingredient" && !MADE_OF.has(name)) continue;
    // A country (미국산 참나무, 일본 물참나무) is no word to look up.
    if (t.type === "region" && !t.parent) continue;
    names.add(name);
    if (t.type === "grape") {
      for (const part of name.split("·")) names.add(part);
    }
  }
  return [...names].filter((n) =>
    n.replace(/\s/g, "").length >= 2 && !NOT_A_NAME.has(n) &&
    explainedBy(n) !== null
  ).sort((a, b) => b.length - a.length);
})();

/** The line with each explained word marked once, where a word begins. */
export function explainedWords(line: string, own: readonly string[]): string {
  const had = new Set(
    [...line.matchAll(/\*\*(.+?)\*\*/g)].flatMap(([, w]) =>
      explainedBy(w) ?? []
    ),
  );
  let text = line;
  const names = [
    ...own.filter((n) => n.length >= 2 && !EXPLAINED.includes(n)),
    ...EXPLAINED,
  ];
  for (const name of names) {
    if (!text.includes(name)) continue;
    const by = explainedBy(name);
    if (!by || had.has(by)) continue;
    // 유러피언 오크 has just been opened: the 오크 after it is the same wood.
    if (
      [...text.matchAll(/\*\*(.+?)\*\*/g)].some(([, w]) => w.includes(name))
    ) {
      continue;
    }
    const parts = text.split(/(\*\*.+?\*\*)/);
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].startsWith("**")) continue;
      let at = parts[i].indexOf(name);
      while (at >= 0) {
        const before = parts[i].slice(0, at);
        const begins = at === 0 || /[\s'"(·,‘“]$/.test(before);
        // 이 레드 와인은 …, 이 **키안티** 레드 와인은 … is the drink itself,
        // not a word to open.
        const itself = KIND_NAMES.has(name) &&
          (/(^|\s)이 $/.test(before) ||
            (before === " " && i >= 2 && /(^|\s)이 $/.test(parts[i - 2])));
        // 보리 맥아 is one thing: a grain right beside a marked word is not
        // opened too (**보리** **맥아**).
        const after = parts[i].slice(at + name.length);
        const beside = MADE_OF.has(name) &&
          ((before === " " && i >= 1) ||
            (after === " " && i + 1 < parts.length));
        if (begins && !itself && !beside) break;
        at = parts[i].indexOf(name, at + 1);
      }
      if (at < 0) continue;
      parts[i] = `${parts[i].slice(0, at)}**${name}**${
        parts[i].slice(at + name.length)
      }`;
      had.add(by);
      break;
    }
    text = parts.join("");
  }
  return text;
}
