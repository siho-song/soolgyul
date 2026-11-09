/**
 * 쓰기: turns the findings a card chose into one section text.
 *
 * Each finding gives one explanation (card_prose.ts): a short name and one
 * body sentence (the drink's trait and what it does in the mouth), filled with
 * the card's words. A section is the names joined into one subtitle (또렷한
 * 과일 향과 깔끔하게 떨어지는 산미) and the bodies run together, the later
 * ones led by 또한/게다가, closed by one sentence that says those traits were
 * the charm or the burden (the user's shape, 2026-11-06). When every level an
 * explanation stands on was copied from the kind's table, its body speaks of
 * the kind (이런 와인은 보통 …) instead of the bottle.
 */
import { serviceVocabulary as vocabulary, terms } from "./dictionary.ts";
import type {
  CardFacts,
  Finding,
  ReactionFact,
  Subject,
} from "./card_facts.ts";
import { INTENSITY_ROWS } from "./card_knowledge.ts";
import { styleDimension } from "./card_findings.ts";
import {
  mergedStyleProfile,
  STYLE_ENTRIES,
  type StyleProfile,
  styleTraitLine,
} from "./style_lines.ts";
import { BURDEN_PROSE, LIKED_PROSE, type Prose } from "./card_prose.ts";

export type Paragraph = {
  finding: string;
  /** The card_prose.ts entry the paragraph was written from. */
  prose: string;
  /** 짧은 이름, filled: one part of the section's subtitle. */
  name: string;
  /** The body sentence, filled, as it stands in the section text but without the ** marks. */
  body: string;
};
export type WrittenSection = {
  /** The names joined: "또렷한 과일 향과 깔끔하게 떨어지는 산미"; "" when empty. */
  title: string;
  /** The bodies run together and the closing sentence; "" when empty. */
  text: string;
  paragraphs: readonly Paragraph[];
  /**
   * Chosen findings without prose yet and no other explanation of the same
   * answer to write instead; the section simply has fewer paragraphs.
   */
  skipped: readonly { finding: string; reason: string }[];
};
export type WriteOptions = {
  /** Korean display name when the catalog name is not Korean. */
  productName?: string;
};

export type Section = "positive" | "burden";

/**
 * 왜 잘 맞았을까요 / 왜 부담이었을까요: one paragraph per finding the card
 * chose for that section, run together into one subtitle and one text.
 */
export function writeSection(
  facts: CardFacts,
  section: Section,
  options: WriteOptions = {},
): WrittenSection {
  const card = cardContext(facts, options);
  const table = section === "burden" ? BURDEN_PROSE : LIKED_PROSE;
  const drafts: Draft[] = [];
  const skipped: { finding: string; reason: string }[] = [];
  const written = new Set<string>();
  /** The answers the drafts so far already explain. */
  const explained = new Set<string>();
  for (const id of facts.sections[section]) {
    const chosen = facts.findings.find((d) => d.id === id)!;
    // Two answers can share one explanation (단맛과 산미의 조합); it is written once.
    if (written.has(chosen.id)) continue;
    const reactionsOf = (d: Finding) =>
      d.reactions.map((r) => facts.reactions.find((x) => x.id === r)!);
    // No prose for the chosen explanation yet: write another explanation of
    // the same answer (a 종류 표 line, say) rather than leave the answer unspoken.
    const candidates = [
      chosen,
      ...facts.findings.filter((d) =>
        d.id !== id && !written.has(d.id) && d.polarity === chosen.polarity &&
        chosen.reactions.every((r) => d.reactions.includes(r))
      ),
    ];
    let finding = chosen;
    let key: string | null = null;
    for (const candidate of candidates) {
      key = proseKey(candidate, reactionsOf(candidate), card, table);
      if (key) {
        finding = candidate;
        break;
      }
    }
    if (!key) {
      skipped.push({ finding: id, reason: `no prose for ${chosen.row}` });
      continue;
    }
    written.add(finding.id);
    const reactions = reactionsOf(finding);
    // A second explanation of answers the section already explains (단맛이
    // 쌉쌀함을 덮었다 and then 단맛이 쌉쌀함보다 먼저 온다): one sensation,
    // one explanation. Only this side's answers count; the 쌉쌀함 liked that
    // the pair also stands on belongs to the other section.
    const own = reactions.filter((r) =>
      r.reaction === (section === "burden" ? "burden" : "liked")
    );
    if (own.length && own.every((r) => explained.has(r.id))) continue;
    const copied = standsOnCopiedLevels(finding, facts);
    const prose = copied ? ofTheKind(table[key]) : table[key];
    const vars = variables(finding, reactions, card);
    const draft: Draft = {
      finding,
      prose: key,
      text: prose,
      vars,
      aromas: aromaKeys(reactions),
      subjects: [subjectNoun(finding)],
      // Every sensation the paragraph stands on (단맛과 산미, both answers),
      // not only the one it is named after.
      subjectKeys: unique(
        reactions.filter((r) => r.subject.domain !== "aroma").map((r) =>
          r.subject.key
        ),
      ),
    };
    // The same text about another sensation (사과 향 and 시트러스 향 both
    // 겉만 시원한): one paragraph about both.
    const twin = drafts.find((d) =>
      d.prose === key && shape(d) === shape(draft)
    );
    if (twin) {
      twin.aromas = unique([...twin.aromas, ...draft.aromas]);
      twin.subjects = unique([...twin.subjects, ...draft.subjects]);
      twin.subjectKeys = unique([...twin.subjectKeys, ...draft.subjectKeys]);
    } else drafts.push(draft);
    for (const r of finding.reactions) explained.add(r);
  }
  const paragraphs = drafts.map((d, index) => {
    const body = fill(
      index ? ledBody(d.text.body, section) : d.text.body,
      mergedVars(d, "body"),
    );
    return {
      finding: d.finding.id,
      prose: d.prose,
      name: fill(d.text.name, mergedVars(d, "name")),
      body,
    };
  });
  // The marks go on the whole text at once: a sensation two paragraphs share
  // (체리 향 twice) is set in bold once, at its first mention.
  const text = paragraphs.length ? sectionText(section, paragraphs) : "";
  return {
    title: subtitle(paragraphs.map((p) => p.name)),
    text: emphasize(text, keyWords(drafts, paragraphs.map((p) => p.body))),
    paragraphs,
    skipped,
  };
}

/* ------------------------------------------------ one text per section */

/** A paragraph before its words are filled in, open to taking a twin's subject. */
type Draft = {
  finding: Finding;
  prose: string;
  text: Prose;
  vars: Record<string, string>;
  /** The aromas the paragraph is about, a twin's included. */
  aromas: string[];
  /** The sensations the paragraph is about, a twin's included. */
  subjects: string[];
  /** Their keys (sweetness, drying …), for the words set in bold. */
  subjectKeys: string[];
};

/** The words that name the paragraph's own sensation; blank, two twins read alike. */
const SUBJECT_VARS = ["aroma", "aroma_kind", "aroma_short", "subject_noun"];

const unique = (words: readonly string[]) => [...new Set(words)];

/** The body with the sensation blanked out: what the text says apart from its subject. */
function shape(draft: Draft): string {
  const blank = { ...draft.vars };
  for (const v of SUBJECT_VARS) blank[v] = "§";
  return fill(draft.text.body, blank);
}

/**
 * The variables with a twin's sensation folded in: "사과·시트러스 향" in the
 * name, "사과 향과 시트러스 향" in the body, "복숭아 향과 신맛" for either.
 */
function mergedVars(
  draft: Draft,
  part: "name" | "body",
): Record<string, string> {
  if (draft.aromas.length < 2 && draft.subjects.length < 2) return draft.vars;
  return {
    ...draft.vars,
    aroma: part === "name"
      ? aromaList(draft.aromas)
      : aromaPairList(draft.aromas),
    subject_noun: andJoin(draft.subjects),
  };
}

/**
 * The words the app sets in bold: each sensation the section is about, as the
 * first paragraph about it names it, one word per sensation ("체리 향" once,
 * even when two paragraphs name it; 무겁게 in the first paragraph rather than
 * 무게 in the second). The word is looked for in that paragraph's own body
 * first, then in the others.
 */
function keyWords(
  drafts: readonly Draft[],
  bodies: readonly string[],
): string[] {
  const words: string[] = [];
  const done = new Set<string>();
  drafts.forEach((draft, index) => {
    const own = [bodies[index], ...bodies.filter((_, i) => i !== index)];
    const text = own.join(" ");
    for (const k of draft.aromas) {
      if (done.has(`aroma:${k}`)) continue;
      done.add(`aroma:${k}`);
      const name = short(k);
      const at = text.indexOf(name);
      words.push(
        at >= 0 && text.startsWith(`${name} 향`, at) ? `${name} 향` : name,
      );
    }
    for (const key of draft.subjectKeys) {
      if (done.has(key)) continue;
      done.add(key);
      words.push(
        wordUsed(
          own,
          EMPHASIS_WORDS[key] ?? [SUBJECT_WORDS[key]?.noun ?? ""],
        ) ??
          wordUsed(own, EMPHASIS_FALLBACK[key] ?? []) ?? "",
      );
    }
  });
  return words;
}

/** The first of the words that the first body naming the sensation uses. */
function wordUsed(
  bodies: readonly string[],
  words: readonly string[],
): string | undefined {
  for (const body of bodies) {
    const word = words.find((w) => w && body.includes(w));
    if (word) return word;
  }
}

/** The words a body may call a sensation by; the first one the text uses is set in bold. */
export const EMPHASIS_WORDS: Readonly<Record<string, readonly string[]>> = {
  sweetness: ["단맛"],
  acidity: ["산미", "신맛", "새콤함"],
  bitterness: ["쌉쌀함", "쓴맛"],
  light: ["가벼움", "가볍게", "가벼운 느낌", "가벼운", "가볍고", "경쾌하게"],
  heavy: ["무게감", "묵직함", "무게", "무겁게", "묵직하게", "묵직한"],
  smooth: [
    "부드러움",
    "매끄러운 질감",
    "매끄러운 촉감",
    "질감",
    "밋밋하게",
    "매끄럽게",
    "매끄럽다",
  ],
  drying: ["떫은 조임", "떫은맛", "떫은 맛", "떫은 느낌", "떫음", "떫은 성분"],
  bubbles: ["탄산"],
  warmth: ["열감", "온기", "알코올 기운", "화끈하게"],
  persistence: ["여운"],
  aroma_echo: ["여운", "코로 올라오는 향"],
  clean: ["깔끔하게", "깔끔한", "마무리"],
  off_flavor: ["잡내"],
};

/** The bottle's word for a sensation, set in bold only when the text never names the sensation itself. */
export const EMPHASIS_FALLBACK: Readonly<Record<string, readonly string[]>> = {
  drying: ["타닌"],
};

/**
 * The first mention of each word wrapped in ** for the app to set in bold;
 * a mention already inside a mark is left alone.
 */
export function emphasize(text: string, words: readonly string[]): string {
  let out = text;
  for (const word of unique(words.filter(Boolean))) {
    let from = 0;
    for (;;) {
      const at = out.indexOf(word, from);
      if (at < 0) break;
      const inside = (out.slice(0, at).split("**").length - 1) % 2 === 1;
      if (!inside) {
        out = `${out.slice(0, at)}**${word}**${out.slice(at + word.length)}`;
        break;
      }
      from = at + word.length;
    }
  }
  return out;
}

/**
 * The bodies run together and the closing sentence. A last body that ends on
 * the wish (그 몫을 다하지 못했어요) runs straight into the closing: "…다하지
 * 못했고, 이 특징이 아쉬움으로 남은 것 같아요."
 */
function sectionText(
  section: Section,
  paragraphs: readonly Paragraph[],
): string {
  const bodies = paragraphs.map((p) => p.body);
  const last = bodies[bodies.length - 1];
  if (last.endsWith(WISH_ENDING)) {
    bodies[bodies.length - 1] = `${
      last.slice(0, -WISH_ENDING.length)
    }그 몫을 다하지 못했고,`;
  }
  return [...bodies, closing(section, paragraphs)].join(" ");
}

/** How an aroma's 더 또렷했으면 body ends (card_prose_effects.ts). */
const WISH_ENDING = "그 몫을 다하지 못했어요.";

/**
 * The names joined by 과/와; when a name already carries 과/와 of its own
 * (단맛과 신맛의 균형), a comma list instead, so the subtitle never reads
 * "A과 B과 C".
 */
function subtitle(names: readonly string[]): string {
  return names.some((n) => /[과와] /.test(n))
    ? names.join(", ")
    : andJoin(names);
}

const LEAD: Readonly<Record<Section, string>> = {
  positive: "또한",
  burden: "게다가",
};

/**
 * A body after the first: led by 또한/게다가 in place of its "이 와인은"
 * opening; a body that opens otherwise (이런 와인은 보통 …, 체리 향은 …) keeps
 * its opening after the lead.
 */
function ledBody(body: string, section: Section): string {
  const opening = "이 {kind}{은} ";
  return body.startsWith(opening)
    ? `${LEAD[section]} ${body.slice(opening.length)}`
    : `${LEAD[section]} ${body}`;
}

/** A wish (더 있었으면, 더 또렷했으면): what was missing rather than a burden. */
const isWish = (prose: string) => /too_weak|too_brief/.test(prose);

/** The sentence that closes a section: those traits were the charm, or the burden. */
function closing(section: Section, paragraphs: readonly Paragraph[]): string {
  const count = ["", "이 특징이", "이 두 가지 특징이", "이 세 가지 특징이"][
    paragraphs.length
  ] ?? "이 특징들이";
  if (section === "positive") {
    return `${count} 입안에서 **기분 좋은 매력**으로 다가온 것 같아요.`;
  }
  return paragraphs.every((p) => isWish(p.prose))
    ? `${count} **아쉬움**으로 남은 것 같아요.`
    : `${count} **부담**으로 다가온 것 같아요.`;
}

/* ---------------------------------------------------- subject words */

/** Where the summary names a sensation differently from the paragraphs. */
export const SUMMARY_LABEL: Readonly<Record<string, string>> = {
  drying: "떫은 맛",
  warmth: "알코올 열감",
};
/**
 * Sensations as the reader knows them, aromas gathered into one phrase:
 * "코코넛·피트 향", "산미", "떫은 맛", "긴 여운".
 */
export function subjectPhrases(subjects: readonly Subject[]): string[] {
  const aromas = subjects.filter((s) => s.domain === "aroma").map((s) => s.key);
  const rest = subjects.filter((s) => s.domain !== "aroma").map((s) =>
    SUMMARY_LABEL[s.key] ?? SUBJECT_LABEL[s.key] ?? ""
  );
  return [...(aromas.length ? [aromaList(aromas)] : []), ...rest].filter(
    Boolean,
  );
}

/* ------------------------------------------------ of the kind */

/**
 * Every level the finding stands on was copied from the kind's table (the
 * catalog's level_sources say table or style_median), so the paragraph may
 * speak of the kind but not assert the number of this bottle.
 */
function standsOnCopiedLevels(finding: Finding, facts: CardFacts): boolean {
  const levels = finding.product_facts
    .map((id) => facts.product_facts.find((p) => p.id === id))
    .filter((p) => p?.fact.type === "level");
  return levels.length > 0 &&
    levels.every((p) => p!.fact.type === "level" && p!.fact.estimated);
}

/** The prose with its 본문 said of the kind: "이런 와인은 보통 단맛이 거의 없어서, …". */
function ofTheKind(prose: Prose): Prose {
  return prose.body.startsWith("이 {kind}{은} ")
    ? {
      ...prose,
      body: `이런 {kind}{은} 보통 ${prose.body.slice("이 {kind}{은} ".length)}`,
    }
    : prose;
}

/* ------------------------------------------------- which prose entry */

type CardContext = {
  name: string;
  kind: string;
  kindKey: string;
  styleKey: string;
  /** The style, grape and region lines of the 종류 표 that apply to this product. */
  styleProfile: StyleProfile | null;
  levels: ReadonlyMap<string, number>;
  /** Dimensions whose number is the kind's usual value, not a reading of this bottle. */
  estimatedLevels: ReadonlySet<string>;
  /** The reader's answer on each taste while drinking (liked, burden, fine). */
  tasteAnswers: ReadonlyMap<string, ReactionFact["reaction"]>;
  /** The catalog's ABV, when stated. */
  abv: number | null;
  ingredients: ReadonlySet<string>;
  /** What was done to the drink (니고리, 오크 숙성). */
  productions: ReadonlySet<string>;
  likedAromas: readonly string[];
  /** The aromas that bothered the reader while drinking, for 잡내 after swallowing. */
  burdenAromas: readonly string[];
  /** A sensation that stayed after swallowing as a burden (텁텁하고 무거운 느낌). */
  lingeringBurden: string | null;
};

const KIND_LABEL: Readonly<Record<string, string>> = {
  wine: "와인",
  sake: "사케",
  whisky: "위스키",
  takju: "막걸리",
  yakju: "약주",
  traditional: "전통주",
};
/** Styles people name as a kind of their own (샴페인). */
const STYLE_KIND_LABEL: Readonly<Record<string, string>> = {
  champagne_sparkling: "샴페인",
};
export const SUBJECT_LABEL: Readonly<Record<string, string>> = {
  sweetness: "단맛",
  acidity: "산미",
  bitterness: "쓴맛",
  light: "가벼움",
  heavy: "무게감",
  smooth: "부드러움",
  drying: "떫음",
  bubbles: "탄산",
  warmth: "열감",
  persistence: "긴 여운",
  clean: "깔끔한 마무리",
  aroma_echo: "향",
  off_flavor: "잡내",
};

function cardContext(facts: CardFacts, options: WriteOptions): CardContext {
  const { category, style_key } = facts.record;
  const kindKey = category === "korean_traditional"
    ? (style_key === "takju" || style_key === "yakju"
      ? style_key
      : "traditional")
    : category ?? "";
  const levels = new Map<string, number>();
  const estimatedLevels = new Set<string>();
  let abv: number | null = null;
  const ingredients = new Set<string>();
  const productions = new Set<string>();
  const styles: string[] = [];
  for (const { fact } of facts.product_facts) {
    if (fact.type === "style") styles.push(fact.key);
    if (fact.type === "level") {
      levels.set(fact.dimension, fact.level);
      if (fact.estimated) estimatedLevels.add(fact.dimension);
    }
    if (fact.type === "abv") abv = fact.value;
    if (fact.type === "ingredient") ingredients.add(fact.key);
    if (fact.type === "production") {
      productions.add(fact.key);
      styles.push(fact.key);
    }
  }
  const tasteAnswers = new Map<string, ReactionFact["reaction"]>();
  for (const r of facts.reactions) {
    if (r.phase === "drinking" && r.subject.domain === "taste") {
      tasteAnswers.set(r.subject.key, r.reaction);
    }
  }
  const lingeringBurden = facts.reactions.find((r) =>
    r.phase === "finish" && r.subject.domain !== "finish" &&
    r.reaction === "burden"
  );
  return {
    name: options.productName ?? facts.record.product_name,
    kind: STYLE_KIND_LABEL[style_key ?? ""] ??
      (styles.includes("sparkling_wine") ? "스파클링 와인" : null) ??
      KIND_LABEL[kindKey] ?? "술",
    kindKey,
    styleKey: style_key ?? "",
    styleProfile: mergedStyleProfile(styles),
    levels,
    estimatedLevels,
    tasteAnswers,
    abv,
    ingredients,
    productions,
    likedAromas: facts.reactions.filter((r) =>
      r.subject.domain === "aroma" && r.phase === "drinking" &&
      r.reaction === "liked"
    ).map((r) => r.subject.key),
    burdenAromas: facts.reactions.filter((r) =>
      r.subject.domain === "aroma" && r.phase === "drinking" &&
      r.reaction === "burden"
    ).map((r) => r.subject.key),
    lingeringBurden: lingeringBurden
      ? SUBJECT_LABEL[lingeringBurden.subject.key] ?? null
      : null,
  };
}

function levelOf(finding: Finding, card: CardContext): number | null {
  const given = finding.conclusion.given.find((c) => c.type === "level");
  return given ? card.levels.get(given.dimension) ?? null : null;
}

/** The most specific entry the table has for this finding, or null. */
function proseKey(
  finding: Finding,
  reactions: readonly ReactionFact[],
  card: CardContext,
  table: Readonly<Record<string, Prose>>,
): string | null {
  const row = finding.row;
  const subject = finding.conclusion.subjects[0];
  // 더 있었으면 on a taste: the one text composed from the levels, whichever
  // thinking explained it (a masking row would close on the burden's shape).
  const lacking = reactions.find((r) =>
    r.qualifier === "too_weak" && r.subject.domain === "taste"
  );
  if (lacking) {
    const key = `intensity_${lacking.subject.key}@too_weak`;
    return key in table ? key : null;
  }
  const tries: string[] = [];
  // An entry written for this very frame (@masks_others, @after_burden) wins.
  if (row !== "origin_style") tries.push(`${row}@${finding.frame}`);
  if (row === "origin_style") {
    // What was done to the drink explains before what kind it is (니고리 → 무게감).
    for (const production of card.productions) {
      tries.push(`origin_style@${subject.key}|${production}`);
    }
    tries.push(
      `origin_style@${subject.key}|${card.styleKey}`,
      `origin_style@${subject.key}|${card.kindKey}`,
      `origin_style@${subject.key}`,
    );
    // No prose written for this sensation and style: the matched line of the
    // 종류 표 is the principle.
    if (styleLine(subject, card)) tries.push("origin_style");
  } else if (finding.thinking === "effect") {
    // 은은해서, 너무 강해서, 더 또렷했으면 carry their own title and ending.
    if (finding.frame !== "liked" && finding.frame !== "burden") {
      tries.push(`${row}@${finding.frame}`);
    }
    tries.push(`${row}@${card.kindKey}`, row);
  } else if (row === "combination_aroma_pair") {
    const fams = families(aromaKeys(reactions));
    tries.push(
      fams.length >= 3
        ? `${row}@many`
        : fams.length === 2
        ? `${row}@mixed`
        : fams[0] === "smoke"
        ? `${row}@smoke`
        : row,
      row,
    );
  } else if (finding.thinking === "persistence") {
    if (row === "persistence_clean" && card.lingeringBurden) {
      tries.push(`${row}@with_burden`);
    }
    // No aroma named while drinking: the echo is told as a second, different
    // meeting with the drink, not as the length of the finish again.
    if (row === "persistence_aroma_echo" && !card.likedAromas.length) {
      tries.push(`${row}@no_aroma`);
    }
    // A finish burden with no burden of the same sensation while drinking.
    if (finding.frame === "burden_alone") tries.push(`${row}@alone`);
    tries.push(row);
  } else if (finding.thinking === "intensity") {
    // 더 있었으면: its own text, composed from the levels (lackVars).
    if (reactions.some((r) => r.qualifier === "too_weak")) {
      return `${row}@too_weak` in table ? `${row}@too_weak` : null;
    }
    // 은은해서 has its own text before any level variant.
    if (reactions.some((r) => r.qualifier === "gentle")) {
      tries.push(`${row}@gentle`);
    }
    if (finding.frame === "no_level") tries.push(`${row}@no_level`);
    else if (finding.frame.endsWith("_little")) tries.push(`${row}@little`);
    else if (levelOf(finding, card) === 3) tries.push(`${row}@mid`);
    if (row === "intensity_warmth" && card.likedAromas.length) {
      tries.push(`${row}@with_aromas`);
    }
    // A style that has the sensation by definition (샴페인 → 탄산) says so.
    tries.push(`${row}@${card.styleKey}`, row);
  } else {
    // A support pair is written for the sensation that burdened (@acidity).
    if (finding.frame === "support" && finding.conclusion.subjects[1]) {
      tries.push(`${row}@${finding.conclusion.subjects[1].key}`);
    }
    tries.push(`${row}@${card.kindKey}`, row);
  }
  return tries.find((key) => key in table) ?? null;
}

/* ----------------------------------------------------- placeholders */

const AROMA_LABEL = new Map(
  (vocabulary as { groups: { key: string; label_ko: string }[] }).groups.map((
    g,
  ) => [g.key, g.label_ko]),
);
const AROMA_CATEGORY = new Map(
  (vocabulary as { groups: { key: string; category_key?: string }[] }).groups
    .map((g) => [g.key, g.category_key ?? ""]),
);
/** Shorter words than the vocabulary labels for running text. */
const SHORT_LABEL: Readonly<Record<string, string>> = {
  floral: "꽃",
  fermentation: "발효",
  aged_aromatic: "진한 양주",
  smoke: "스모키",
  orange_tangerine: "오렌지",
  berry: "베리",
  nutty: "견과",
  juniper: "주니퍼",
};
type Family =
  | "bright"
  | "rich"
  | "sweet"
  | "toasty"
  | "oak"
  | "calm"
  | "smoke"
  | "green";
const AROMA_FAMILY: Readonly<Record<string, Family>> = {
  floral: "bright",
  pear: "bright",
  apple: "bright",
  citrus: "bright",
  peach: "bright",
  cherry: "bright",
  orange_tangerine: "bright",
  berry: "bright",
  watermelon: "bright",
  tropical_fruit: "rich",
  jammy: "rich",
  dried_fruit: "rich",
  fruit_syrup: "rich",
  ginjo_aroma: "bright",
  vanilla: "sweet",
  coconut: "sweet",
  chocolate: "sweet",
  caramel: "toasty",
  malt: "toasty",
  nutty: "toasty",
  roasted: "toasty",
  bread: "toasty",
  cereal: "toasty",
  rice: "toasty",
  barley: "toasty",
  wheat: "toasty",
  corn: "toasty",
  almond: "toasty",
  walnut: "toasty",
  hazelnut: "toasty",
  coffee: "toasty",
  nuruk: "toasty",
  wood: "oak",
  oak: "oak",
  cherry_wood: "oak",
  peat: "smoke",
  smoke: "smoke",
  herbal: "green",
  juniper: "green",
  mint: "green",
  leaf: "green",
  medicinal_herb: "green",
};
const CATEGORY_FAMILY: Readonly<Record<string, Family>> = {
  fruit: "bright",
  botanical: "bright",
  bakery_sweets_nuts: "sweet",
};
/** How each family reads in running text ("꽃과 배의 화사함"). */
const FAMILY_WORDS: Readonly<Record<Family, { adj: string; noun: string }>> = {
  bright: { adj: "화사한", noun: "화사함" },
  rich: { adj: "잘 익은 과일", noun: "농익은 풍성함" },
  sweet: { adj: "달큰한", noun: "달큰함" },
  toasty: { adj: "구수한", noun: "구수함" },
  oak: { adj: "차분한", noun: "차분함" },
  calm: { adj: "차분한", noun: "차분함" },
  smoke: { adj: "스모키한", noun: "스모키함" },
  green: { adj: "싱그러운", noun: "싱그러움" },
};

const short = (key: string) => SHORT_LABEL[key] ?? AROMA_LABEL.get(key) ?? key;
/** The word running text calls an aroma by (card_terms.ts looks the words up). */
export const aromaShort = short;
const familyOf = (key: string): Family =>
  AROMA_FAMILY[key] ?? CATEGORY_FAMILY[AROMA_CATEGORY.get(key) ?? ""] ??
    "calm";
/** The aroma's kind for a subtitle: "과일 향" for a fruit, else its family ("화사한 향"). */
const aromaKind = (key: string) =>
  AROMA_CATEGORY.get(key) === "fruit"
    ? "과일 향"
    : `${FAMILY_WORDS[familyOf(key)].adj} 향`;
const aromaKeys = (reactions: readonly ReactionFact[]) =>
  reactions.filter((r) => r.subject.domain === "aroma").map((r) =>
    r.subject.key
  );
function families(keys: readonly string[]): Family[] {
  const out: Family[] = [];
  for (const key of keys) {
    if (!out.includes(familyOf(key))) out.push(familyOf(key));
  }
  return out;
}
const shorts = (keys: readonly string[]) => keys.map(short).join("·");
/** Two words joined by 과/와 ("꽃과 배"); three or more as a plain list
 * ("꽃, 배, 바닐라"), which reads more naturally in Korean than "A, B와 C". */
export function andJoin(words: readonly string[]): string {
  if (words.length < 2) return words[0] ?? "";
  if (words.length > 2) return words.join(", ");
  return josa(`${words[0]}{과} ${words[1]}`);
}
const shortsAnd = (keys: readonly string[]) => andJoin(keys.map(short));
const shortsComma = (keys: readonly string[]) => keys.map(short).join(", ");
/** Two groups joined by 과/와, more as a comma list. */
const familyGroups = (groups: readonly string[]) =>
  groups.length === 2 ? andJoin(groups) : groups.join(", ");
const aromaList = (keys: readonly string[]) =>
  keys.length ? `${shorts(keys)} 향` : "";
/** "A 향과 B 향", "A·B 향과 C 향". */
const aromaPairList = (keys: readonly string[]) =>
  keys.length < 2
    ? aromaList(keys)
    : `${shorts(keys.slice(0, -1))} 향과 ${short(keys[keys.length - 1])} 향`;

/** Words for a product level in the 사실 sentence, by dimension. */
type LevelWords = {
  most?: string;
  much: string;
  mid: string;
  little: string;
  none: string;
};
const LEVEL_WORDS: Readonly<Record<string, LevelWords>> = {
  acidity: {
    most: "새콤함이 아주 또렷한",
    much: "새콤함이 또렷한",
    mid: "새콤함이 적당히 있는",
    little: "새콤함이 적은",
    none: "새콤함이 있는",
  },
  sweetness: {
    most: "단맛이 아주 진한",
    much: "단맛이 꽤 있는",
    mid: "단맛이 적당히 있는",
    little: "단맛이 적은",
    none: "단맛이 있는",
  },
  astringency: {
    most: "떫은 맛이 아주 센",
    much: "떫은 맛이 센",
    mid: "떫은 맛이 적당히 있는",
    little: "떫은 맛이 적은",
    none: "떫은 맛이 있는",
  },
};
function levelWord(dimension: string, level: number | undefined): string {
  const words = LEVEL_WORDS[dimension];
  if (!words) return "";
  if (level === undefined) return words.none;
  if (level >= 5 && words.most) return words.most;
  return level >= 4 ? words.much : level <= 2 ? words.little : words.mid;
}

function variables(
  finding: Finding,
  reactions: readonly ReactionFact[],
  card: CardContext,
): Record<string, string> {
  const keys = aromaKeys(reactions);
  const fams = families(keys);
  const ofFamily = (f: Family | undefined) =>
    keys.filter((k) => familyOf(k) === f);
  // The aroma a masking explanation stands on, e.g. the 베리 향 that 떫음 covered.
  const givenAromas: string[] = [];
  for (const c of finding.conclusion.given) {
    if (c.type === "descriptor") givenAromas.push(c.key);
  }
  // A masking row that stands on "a fruit scent" rather than one named aroma
  // (떫음이 과일 향을 덮었다) names the aroma the reader answered about.
  const givenAroma = givenAromas.length
    ? `${short(givenAromas[0])} 향`
    : keys.length
    ? `${short(keys[0])} 향`
    : "";
  const nouns = fams.map((f) => FAMILY_WORDS[f].noun);
  const rowWords = (INTENSITY_ROWS as Record<
    string,
    { words?: { much: string; little: string } }
  >)[finding.row]?.words;
  const vars: Record<string, string> = {
    name: card.name,
    kind: card.kind,
    aroma: keys.length ? `${short(keys[0])} 향` : "",
    aroma_kind: keys.length ? aromaKind(keys[0]) : "",
    aroma_short: keys.length ? short(keys[0]) : "",
    aromas: aromaList(keys),
    aromas_short: shorts(keys),
    aromas_and: aromaPairList(keys),
    aromas_a: aromaList(ofFamily(fams[0])),
    aromas_b: aromaList(ofFamily(fams[1])),
    aromas_a_short: shorts(ofFamily(fams[0])),
    aromas_b_short: shorts(ofFamily(fams[1])),
    aromas_short_and: shortsAnd(keys),
    aromas_comma: shortsComma(keys),
    aromas_a_short_and: shortsAnd(ofFamily(fams[0])),
    aromas_b_short_and: shortsAnd(ofFamily(fams[1])),
    given_aroma: givenAroma,
    given_aromas: givenAromas.length ? `${shortsAnd(givenAromas)} 향` : "",
    // "꽃과 배의 화사함, 바닐라의 달큰함, 나무의 차분함"
    family_groups: familyGroups(
      fams.map((f) => `${shortsAnd(ofFamily(f))}의 ${FAMILY_WORDS[f].noun}`),
    ),
    family_adj: fams.length ? FAMILY_WORDS[fams[0]].adj : "",
    family_noun: nouns[0] ?? "",
    family_a_noun: nouns[0] ?? "",
    family_b_noun: nouns[1] ?? "",
    family_rest: andJoin(nouns.slice(0, -1)),
    family_last: nouns[nouns.length - 1] ?? "",
    liked_aromas: card.likedAromas.length
      ? `${shortsAnd(card.likedAromas)} 향`
      : "향",
    flavour: card.likedAromas.length
      ? `${shortsAnd(card.likedAromas)} 풍미`
      : "풍미",
    burden_aromas: card.burdenAromas.length
      ? `${shortsAnd(card.burdenAromas)} 향`
      : "향",
    lingering_burden: card.lingeringBurden ?? "",
    subject_noun: subjectNoun(finding),
    level: rowWords
      ? (finding.frame.endsWith("_little") ? rowWords.little : rowWords.much)
      : "",
    strength: strengthPhrase(card, "인"),
    strength_and: strengthPhrase(card, "이고"),
  };
  for (const dimension of Object.keys(LEVEL_WORDS)) {
    vars[`level_${dimension}`] = levelWord(
      dimension,
      card.levels.get(dimension),
    );
  }
  const lacking = reactions.find((r) =>
    r.qualifier === "too_weak" && r.subject.domain === "taste"
  );
  if (lacking) Object.assign(vars, lackVars(lacking.subject.key, card));
  Object.assign(vars, styleVars(finding, card));
  return vars;
}

/* ------------------------------------------------- 더 있었으면 (the lack) */

const LACK_WORDS: Readonly<Record<string, { noun: string; rich: string }>> = {
  sweetness: { noun: "단맛", rich: "단" },
  acidity: { noun: "산미", rich: "새콤한" },
  bitterness: { noun: "쓴맛", rich: "쌉쌀한" },
};
/**
 * The lack beside another taste (c). `cause` is why a higher c makes the
 * subject taste feel weaker (the covering direction, c → subject).
 */
type LackRole = {
  cause: (c: string, coverKeys: readonly string[]) => string;
  coveredEffect: string;
  heldEffect: string;
};
const LACK_ROLES: Readonly<Record<string, LackRole>> = {
  sweetness: {
    cause: (c) => `단맛은 ${c}{과} 균형을 이루기 때문에`,
    coveredEffect: "실제 당도가 같아도 단맛이 훨씬 적게 느껴져요",
    heldEffect: "실제 당도보다 단맛이 덜 느껴져요",
  },
  acidity: {
    cause: (c, keys) =>
      keys.length > 1
        ? `${c}{은} 둘 다 산미의 산뜻함을 덮는 맛이기 때문에`
        : keys[0] === "sweetness"
        ? "단맛은 산미의 신 자극을 둥글게 감싸기 때문에"
        : "쓴맛은 끝에 오래 남아 산미의 산뜻함을 덮기 때문에",
    coveredEffect: "실제 양이 같아도 산미가 훨씬 적게 느껴져요",
    heldEffect: "실제 양보다 산미가 덜 느껴져요",
  },
  bitterness: {
    cause: (c, keys) =>
      keys.length > 1
        ? `${c}{은} 둘 다 쓴맛을 앞에서 가리는 맛이기 때문에`
        : keys[0] === "sweetness"
        ? "단맛은 쓴맛을 둥글게 감싸 눌러 주기 때문에"
        : "산미는 입안을 먼저 치고 들어와 쓴맛을 뒤로 밀어내기 때문에",
    coveredEffect: "실제 양이 같아도 쓴맛이 훨씬 적게 느껴져요",
    heldEffect: "실제 양보다 쓴맛이 덜 느껴져요",
  },
};
/** How the drink was distilled, named in the fact (a glossary tip explains the term). */
const DISTILLATION_NAMES: ReadonlyMap<string, string> = new Map(
  terms("process").filter((t) =>
    [
      "pot_distillation",
      "column_distillation",
      "atmospheric_distillation",
      "vacuum_distillation",
    ].includes(t.key)
  ).map((t) => [t.key, t.names.ko]),
);
type LackBand = "low" | "mid" | "high";

/**
 * The name and body of a 더 있었으면 paragraph, from the bottle's levels.
 * The body says how little of the taste the drink has (of the bottle or, when
 * the number is the kind's, of the kind, named with its distillation when the
 * catalog records one), and why the other tastes make it feel so; when
 * nothing covers it, that the taste felt is the drink's own (the user's
 * reading, 2026-11-01). A drink that has plenty of the taste is never said so
 * against the reader: no level, only the other tastes.
 */
function lackVars(
  subjectKey: string,
  card: CardContext,
): Record<string, string> {
  const words = LACK_WORDS[subjectKey];
  if (!words) return {};
  const taste = words.noun;
  const kindBand = (dimension: string): LackBand | null => {
    const line = card.styleProfile?.traits[dimension]?.level;
    return line === "none"
      ? "low"
      : line === "low" || line === "mid" || line === "high"
      ? line
      : null;
  };
  const bandOf = (dimension: string): LackBand | null => {
    const level = card.levels.get(dimension);
    if (level === undefined) return kindBand(dimension);
    return level <= 2 ? "low" : level === 3 ? "mid" : "high";
  };
  const ownLevel = card.levels.get(subjectKey);
  const ofKind = ownLevel === undefined ||
    card.estimatedLevels.has(subjectKey);
  const little = bandOf(subjectKey) === "low";
  const none = ownLevel !== undefined
    ? ownLevel <= 1
    : card.styleProfile?.traits[subjectKey]?.level === "none";
  const attr = none ? "거의 없는" : "적은";
  // The other tastes: those the reader answered, and those the bottle has a
  // reading of its own for (a wine's acidity beside a sweetness answer).
  const others = Object.keys(LACK_WORDS).filter((k) =>
    k !== subjectKey &&
    (card.tasteAnswers.has(k) ||
      (card.levels.has(k) && !card.estimatedLevels.has(k)))
  );
  const nouns = (keys: readonly string[]) =>
    keys.map((k) => LACK_WORDS[k].noun);
  const known = others.filter((k) => bandOf(k) !== null);
  const highKeys = known.filter((k) => bandOf(k) === "high");
  const high = nouns(highKeys);
  const kindName = card.kindKey === "traditional"
    ? STYLE_ENTRIES.get(card.styleKey)?.name_ko ?? card.kind
    : card.kind;
  const method = [...card.productions].map((k) => DISTILLATION_NAMES.get(k))
    .find(Boolean);
  const midKeys = known.filter((k) => bandOf(k) === "mid");
  const mid = nouns(midKeys);
  const doList = (ns: readonly string[]) => ns.map((n) => `${n}도`).join(" ");
  const role = LACK_ROLES[subjectKey];
  // The lead clause when the number is the kind's: of the kind, not the bottle.
  const kindLead = () =>
    method
      ? `이 ${kindName}{은} ${method}로 내린 술이라 ${taste}{이} ${attr} 편인데`
      : `이런 ${kindName}{은} 본래 ${taste}{이} ${attr} 편인데`;

  let body: string;
  if (high.length) {
    // Beside a high taste: it covers the subject, so the reader wants balance.
    const c = andJoin(high);
    const lead = !little
      ? `이 ${kindName}{은} ${c}{이} 높은 술인데`
      : ofKind
      ? kindLead()
      : `이 ${kindName}{은} ${taste}{이} ${
        none ? attr : "낮은"
      } 대신 ${c}{이} 높은 술인데`;
    body = `${lead}, ${role.cause(c, highKeys)} ${role.coveredEffect}.`;
  } else if (!little && mid.length) {
    // The drink has the taste, and a middling other taste holds it back:
    // the level is never said against the reader.
    const c = andJoin(mid);
    body = `이 ${kindName}{은} ${c}{이} 어느 정도 있는 술인데, ${
      role.cause(c, midKeys)
    } ${role.heldEffect}.`;
  } else if (known.length) {
    // The other tastes are not strong, so nothing covers the subject: the
    // reader wants the taste itself, not balance (the user's reading,
    // 2026-11-01). A drink that has the taste is only said to be plain.
    const quiet = doList(nouns(known));
    const lead = !little
      ? `이 ${kindName}{은} ${quiet} 세지 않은 술이라서`
      : ofKind
      ? kindLead()
      : `이 ${kindName}{은} ${taste}{이} ${
        none ? "거의 없고" : "낮고"
      } ${quiet} 세지 않은 술이라서`;
    body =
      `${lead}, ${taste}{을} 가리는 맛이 없어 느끼신 ${taste}{이} 이 술이 가진 ${taste} 그대로예요.`;
  } else {
    // Nothing known of the other tastes: a reading on the reader's answer alone.
    const lead = little
      ? ofKind ? kindLead() : `이 ${kindName}{은} ${taste}{이} ${attr} 술인데`
      : `${taste}{은} 혼자 느껴지는 게 아니라 다른 맛과 견줘서 느껴지는 맛이라`;
    body = little
      ? `${lead}, ${taste}{은} 다른 맛과 견줘서 느껴지는 맛이라 다른 맛보다 한 발 뒤에 있으면 그 자리가 비어 보여요.`
      : `${lead}, 다른 맛보다 한 발 뒤에 있으면 그 자리가 비어 보여요.`;
  }
  return { lack_body: body, lack_name: `아쉬운 ${taste}` };
}

/**
 * The bottle's strength as a fact: its ABV, and where it sits on its kind's
 * five bands (the alcohol presence read from it). "도수가 48도인", "도수가
 * 58도로 높은", "도수가 63도로 아주 높은", "도수가 9도로 낮은"; without an
 * ABV, only the band.
 */
function strengthPhrase(card: CardContext, mid: "인" | "이고"): string {
  const level = card.levels.get("alcohol_presence");
  const band = level === undefined
    ? null
    : level >= 5
    ? "아주 높"
    : level === 4
    ? "높"
    : level === 2
    ? "낮"
    : level <= 1
    ? "아주 낮"
    : null;
  const tail = mid === "인" ? "은" : "고";
  if (card.abv === null) {
    return band ? `도수가 ${band}${tail}` : `도수가 보통${mid}`;
  }
  const abv = `${
    Number.isInteger(card.abv) ? card.abv : card.abv.toFixed(1)
  }도`;
  return band ? `도수가 ${abv}로 ${band}${tail}` : `도수가 ${abv}${mid}`;
}

/* --------------------------------------------- the 종류 표 line behind 유래 */

/** The matched style line for the finding's subject: an aroma line or the trait of its dimension. */
function styleLine(
  subject: Finding["conclusion"]["subjects"][number],
  card: CardContext,
): { reason_ko: string; source: string } | null {
  if (subject.domain === "aroma") return null;
  const map = styleDimension(subject, card.styleProfile);
  if (!map) return null;
  const line = styleTraitLine(card.styleProfile, map.dimension);
  return line?.reason_ko
    ? { reason_ko: line.reason_ko, source: line.source }
    : null;
}

/** How a paragraph names each taste or mouthfeel subject the 종류 표 explains. */
const SUBJECT_WORDS: Readonly<
  Record<string, {
    noun: string;
    liked: string;
    burden: string;
  }>
> = {
  sweetness: {
    noun: "단맛",
    liked: "입안을 감싸는 단맛",
    burden: "도드라지게 튀는 단맛",
  },
  acidity: {
    noun: "신맛",
    liked: "입안을 깨우는 산뜻한 산미",
    burden: "혀를 찌르는 강한 신맛",
  },
  bitterness: {
    noun: "쓴맛",
    liked: "끝맛을 정리하는 쌉쌀함",
    burden: "끝까지 입안에 남는 쓴맛",
  },
  light: {
    noun: "가벼움",
    liked: "가볍고 깔끔한 목넘김",
    burden: "물처럼 밋밋한 가벼움",
  },
  heavy: {
    noun: "무게감",
    liked: "입안을 채우는 든든한 무게감",
    burden: "입안을 짓누르는 무게감",
  },
  smooth: {
    noun: "부드러움",
    liked: "걸리는 것 없는 매끄러운 질감",
    burden: "포인트 없이 밋밋한 질감",
  },
  drying: {
    noun: "떫은 맛",
    liked: "입안을 기분 좋게 조이는 떫은맛",
    burden: "향과 맛을 가로막는 떫은맛",
  },
  bubbles: {
    noun: "탄산",
    liked: "기분 좋게 톡 쏘는 탄산",
    burden: "맛을 가릴 만큼 쏘는 탄산",
  },
  warmth: {
    noun: "열감",
    liked: "은은하게 퍼지는 따뜻한 온기",
    burden: "목을 타고 확 치고 올라오는 열감",
  },
};

/** The first subject of a finding as the paragraph names it (체리 향, 단맛, 탄산). */
function subjectNoun(finding: Finding): string {
  const subject = finding.conclusion.subjects[0];
  if (!subject) return "";
  if (subject.domain === "aroma") return `${short(subject.key)} 향`;
  return SUBJECT_WORDS[subject.key]?.noun ?? SUBJECT_LABEL[subject.key] ?? "";
}

/** "알자스 화이트" → "알자스의 화이트 와인"; names without a colour word stay as they are. */
function regionPhrase(name: string): string {
  const plain = name.replace(/\s*\(.*\)$/, "");
  const m = plain.match(/^(.*\S)\s+(화이트|레드|로제|스파클링)$/);
  return m ? `${m[1]}의 ${m[2]} 와인` : plain;
}

/** {style_fact}, {style_reason} and the subject words of a 종류 표 explanation. */
function styleVars(
  finding: Finding,
  card: CardContext,
): Record<string, string> {
  if (finding.row !== "origin_style") return {};
  const subject = finding.conclusion.subjects[0];
  const line = styleLine(subject, card);
  const entry = line ? STYLE_ENTRIES.get(line.source) : undefined;
  if (!line || !entry) return {};
  const words = SUBJECT_WORDS[subject.key];
  // A blend names the grape as one of its grapes, a varietal as what it is made from.
  const styleFact = entry.kind === "region"
    ? regionPhrase(entry.name_ko)
    : entry.kind === "process"
    ? `${entry.fact_ko ?? entry.name_ko} ${card.kind}`
    : entry.kind !== "grape"
    ? entry.name_ko
    : (card.styleProfile?.grapes.length ?? 0) > 1
    ? `${entry.name_ko}{이} 들어간 ${card.kind}`
    : `${entry.name_ko}{으로} 만든 ${card.kind}`;
  return {
    style_fact: styleFact,
    style_reason: line.reason_ko.replace(/\.$/, ""),
    subject_noun: words?.noun ?? "",
    subject_anchor: !words
      ? ""
      : finding.polarity === "burden"
      ? words.burden
      : words.liked,
  };
}

/** Fills {placeholders}, then the particles that follow them. */
export function fill(text: string, vars: Record<string, string>): string {
  const filled = text.replace(
    /\{([a-z_]+)\}/g,
    (match, key: string) => vars[key] ?? match,
  );
  return josa(filled);
}

/* ------------------------------------------------------------ particles */

const PARTICLES: Readonly<Record<string, [string, string]>> = {
  "은": ["은", "는"],
  "이": ["이", "가"],
  "을": ["을", "를"],
  "과": ["과", "와"],
  "예요": ["이에요", "예요"],
  "이라": ["이라", "라"],
  "으로": ["으로", "로"],
  "이고": ["이고", "고"],
  "이나": ["이나", "나"],
  "이다": ["이다", "다"],
};

/** Resolves {은} {이} {을} {과} {예요} {이라} {으로} {이고} {이나} {이다} by the syllable before them. */
export function josa(text: string): string {
  return text.replace(
    /\{(은|이|을|과|예요|이라|으로|이고|이나|이다)\}/g,
    (_match, key: string, offset: number) => {
      const before = text.slice(0, offset).replace(/['’"”)\]]+$/, "");
      const last = before.charAt(before.length - 1);
      // 으로/로: a final ㄹ takes 로 (쌀로, 메를로로 is 메를로 + 로).
      const consonant = hasFinalConsonant(last) &&
        !(key === "으로" && finalIsRieul(last));
      return PARTICLES[key][consonant ? 0 : 1];
    },
  );
}

function finalIsRieul(ch: string): boolean {
  const code = ch.charCodeAt(0);
  return code >= 0xac00 && code <= 0xd7a3 && (code - 0xac00) % 28 === 8;
}

function hasFinalConsonant(ch: string): boolean {
  if (!ch) return false;
  const code = ch.charCodeAt(0);
  if (code >= 0xac00 && code <= 0xd7a3) return (code - 0xac00) % 28 !== 0;
  if (/[0-9]/.test(ch)) return "013678".includes(ch);
  return /[lmn]/i.test(ch);
}
