/**
 * 다음 술은 이렇게 골라보세요: the guide inside the 한입 summary, written to
 * be used at a shelf or shown to shop staff as it is. It holds a head
 * sentence, up to two chips, the marks or the profile of the drink to look
 * for, and a tip. By kind of drink:
 *   A wine: grapes with the region most of their bottles come from, and the
 *     당도·산도·타닌·바디 marks; sparkling wine: regional styles and the
 *     당도·산도·탄산·바디 marks; with no grape or style that fits (a rosé),
 *     the kind's label cues (Saignée, dry) and the marks. The sweetness of a
 *     red or a white is steered by how sweet the wine feels: grapes by the
 *     counted lean of their bottles, 타닌 and 산도 a step down, and no 당도
 *     mark the kind hardly has
 *   B sake: sister grades of a similar strength in one chip, and the
 *     당도(주도)·산미(산도) bands; a bottle unlike every grade gets its label
 *     cues and the bands, which are the label's own numbers
 *   C whisky: casks and methods that carry an aroma the reader liked, filled
 *     up to two chips with the kind's label cues, the label word to pass
 *     over for an aroma to turn down, and a cask or method whose dictionary
 *     taste row moves a level no cue answered; the 도수 band; and the drink
 *     said in words (AROMA, FLAVOR, FINISH). A chip is a new word, never the
 *     bottle's own cask as the way to change
 *   D Korean traditional drinks (탁주, 약주, 과실주, 증류식 소주): the words
 *     printed on the label that answer what the reader said (생막걸리,
 *     감압증류, 원재료명 보리) and the marks the shops' own taste graphs use;
 *     a burden's word goes first, and a 증류식 소주 then names a cask or
 *     method that carries a liked aroma. The reader's own reason (또렷해서,
 *     은은해서) names the side before the bottle's level does, the 도수 is
 *     read from the bottle's own number, and a 탁주 drinker is not sent to
 *     과실주, so no other kind fills in
 *   E everything else: no guide
 *
 * Which chips: practical first. Every chooser keeps only the options whose
 * reason holds for this reader (it answers something they said, undoes
 * nothing else they said, and is not the bottle's own cask or grape as the
 * way to change), drops the ones the catalog counts as too rare to find
 * (FINDABLE_SHARE of the shelf; a grape, MIN_GRAPE_BOTTLES and for a lean
 * LEAN_SHARE), and of what is left names the most common first, by the
 * bottle counts of facts/kind_place.ts. A label word the catalog has no
 * column for (dry, 생막걸리) cannot be counted and is chosen by the
 * dictionary's order. When nothing is left the guide has no chip.
 *
 * A chip's words are spelled as a label prints them with their reading,
 * Merlot(메를로), and a word printed in Korean stays Korean (생막걸리). The
 * note under a chip says why it is picked for this reader, never what the
 * word means: the word's own explanation is attached when the card is served
 * (writing/terms.ts). A mark is also said in the word a shop uses (드라이,
 * 미디엄 바디). The directions the older cards carried are no longer written.
 *
 * A reader who liked nothing still gets a guide, aimed by the burdens alone,
 * an aroma alone included. Outside D the reader's own word for a strength
 * (또렷해서, 은은해서, 너무 강해서, 약해서, 가벼워서) outranks the catalog
 * number. Which head a card gets is fixed by the card.
 */
import { abvBandsFor } from "../facts/abv_levels.ts";
import { feltSweetness } from "../facts/felt_sweetness.ts";
import {
  bottlesCarrying,
  type Carried,
  grapeLeans,
  MIN_GRAPE_BOTTLES,
  type PlaceDimension,
  placeOfLevel,
  shelfOfKind,
} from "../facts/kind_place.ts";
import { regionByKey, type Term, terms } from "../dictionary/dictionary.ts";
import { josa } from "../writing/korean.ts";
import {
  ACIDITY_BANDS,
  BURDENED,
  EVIDENCE_COUNTED,
  EVIDENCE_LEAN,
  HEAD_BURDEN,
  HEAD_ONLY_BURDEN,
  HEAD_POSITIVE,
  LEAN_SIDE,
  LIKED,
  LIKED_SIDE,
  NOTE_CARRY,
  NOTE_CARRY_KIN,
  NOTE_EASE_KEEP,
  NOTE_FILL_KEEP,
  NOTE_ONLY_EASE,
  NOTE_ONLY_EASE_ALIKE,
  NOTE_ONLY_FILL,
  NOTE_ONLY_FILL_ALIKE,
  NOTE_PASS,
  NOTE_PASS_OWN,
  NOTE_SAME_GRADE,
  NOTE_SAME_GRAPE,
  NOTE_SAME_INGREDIENT,
  NOTE_SAME_KIND,
  NOTE_WHICH,
  PROFILE_BURDENED,
  PROFILE_LABELS,
  PROFILE_LESS,
  PROFILE_MORE,
  PROFILE_NOT_LINGERING,
  PROFILE_WITHOUT,
  RESIDUE,
  SAKE_TIP,
  SHARE_SAID,
  SMV_BANDS,
  SOJU_SPEC,
  SPARKLING_SPEC,
  TRADITIONAL_LEVEL_WORDS,
  TRADITIONAL_SPEC,
  TRADITIONAL_TIP,
  WHISKY_TIP,
  WINE_LEVEL_WORDS,
  WINE_SPEC,
  WINE_TIP,
  WITHOUT_WORD,
} from "./guide_words.ts";
import type {
  CardFacts,
  NextChoice,
  ProductFact,
  ReactionFact,
  Subject,
} from "../facts/facts.ts";
import type {
  TasteCardGuide,
  TasteCardGuideLevel,
  TasteCardGuidePick,
  TasteCardGuideProfileLine,
} from "../service/types.ts";

type Guide = TasteCardGuide;
type GuidePick = TasteCardGuidePick;
type GuideLevel = TasteCardGuideLevel;
type ProfileLine = TasteCardGuideProfileLine;

/**
 * A guide with the parts given. A card always gets its head and its kind's
 * tip; the directions stay empty, kept only for the cards stored before.
 */
function guideOf(
  head: string,
  tip: string,
  parts: Partial<Pick<Guide, "picks" | "levels" | "profile">>,
): Guide {
  return { head, picks: [], tip, levels: [], directions: [], ...parts };
}

/** Every row a bottle's style keys can name: its kind, grapes and styles. */
const DICTIONARY_STYLES = terms("kind", "grape", "regional_style");

/**
 * A chip: its words one by one, and the same words in one line. [labelWord]:
 * the words are printed on the label (dry, 山廃, 생막걸리) and do not name
 * what the bottle is (a grape, a region, a grade, a cask).
 */
function pickOf(
  chip: {
    words: readonly string[];
    labelWord: boolean;
    note?: string | null;
    country?: { country: string; name: string };
    place?: string;
    /** Only where the line says more than the words: Peated(…) 없는 것. */
    keyword?: string;
  },
): GuidePick {
  return {
    country: chip.country?.country ?? null,
    place: [chip.country?.name, chip.place].filter(Boolean).join(" ") || null,
    keyword: chip.keyword ?? chip.words.join(" · "),
    words: chip.words.map((text) => ({ text })),
    labelWord: chip.labelWord,
    note: chip.note ?? null,
  };
}

type Band = "low" | "mid" | "high";
type Levels = Readonly<Record<string, Band>>;

type Style = {
  key: string;
  name: string;
  colors: readonly string[];
  levels: Levels;
  aromas: readonly string[];
  abv: readonly [number, number] | null;
  /** Where a grape's bottles come from, most first (counted from the catalog). */
  bottledRegions: readonly { region: string; bottles: number }[];
  /** The dictionary rows it was read from: a grape's, and its region's after. */
  rows: readonly Term[];
};

type Cue = {
  /** The level the words turn; an aroma cue names [aroma] instead. */
  axis?: string;
  /** The aroma the words bring up or down ('야마하이' → lactic). */
  aroma?: string;
  direction: "lower" | "higher";
  cue: string;
  compare: string;
  effect: string;
  why: string;
  /** The chip's words when [compare] alone does not say where to look: 원재료명 '찹쌀' 표기. */
  label?: string;
  /** Only for a bottle of these colors: 'Lambrusco' is red sparkling. */
  colors?: string[];
  /**
   * What the label words stand for, when two labels share a word but not a
   * meaning: '생막걸리' fresh from the brewery or kept for weeks.
   */
  words?: string[];
  /** How well the sentence is sourced; 1 is best. */
  grade?: number;
};

/** The bottle's own ingredient as a label word: 원재료명 '보리'. Without [text] it only names the word. */
type IngredientCue = { ingredient: string; label: string; text?: string };

type Adjust = NextChoice["adjust"][number];

type Shape = "A" | "B" | "C" | "D" | "E";

const SHAPES: Readonly<Record<string, Shape>> = {
  wine: "A",
  sake: "B",
  whisky: "C",
  korean_traditional: "D",
};

/** The dictionary axis a reaction speaks about, and the band the reader meant by it. */
function axisOf(subject: Subject): { axis: string; band?: Band } | null {
  switch (`${subject.domain}.${subject.key}`) {
    case "taste.sweetness":
      return { axis: "sweetness" };
    case "taste.acidity":
      return { axis: "acidity" };
    case "taste.bitterness":
      return { axis: "bitterness" };
    case "mouthfeel.drying":
      return { axis: "astringency" };
    case "mouthfeel.heavy":
      return { axis: "body", band: "high" };
    case "mouthfeel.light":
      return { axis: "body", band: "low" };
    case "mouthfeel.bubbles":
      return { axis: "carbonation" };
    case "mouthfeel.warmth":
      return { axis: "alcohol_presence" };
    case "finish.persistence":
      return { axis: "finish_length" };
    case "finish.clean":
      return { axis: "finish_cleanliness", band: "high" };
    case "finish.aroma_echo":
      return { axis: "aroma_intensity", band: "high" };
    case "finish.off_flavor":
      return { axis: "flavour_clarity", band: "high" };
    default:
      return null;
  }
}

const AROMA_NAMES = new Map(
  terms("aroma").map((t) => [t.key, t.names?.ko ?? t.key] as const),
);

/** 체리 and 자두 share a family (복숭아·자두·체리 계열). */
const AROMA_FAMILY = new Map(
  terms("aroma").flatMap((t) => t.parent ? [[t.key, t.parent] as const] : []),
);

/**
 * 바닐라 향, 백단향: a name that already closes on 향 is not given another
 * ("백단향 향이 나요"). 정향 and 회향 are spices and keep theirs.
 */
function scent(aroma: string): string {
  const name = AROMA_NAMES.get(aroma) ?? aroma;
  return /..향$/.test(name) ? name : `${name} 향`;
}

function liked(subject: Subject): string | null {
  if (subject.domain === "aroma") return scent(subject.key);
  return LIKED[`${subject.domain}.${subject.key}`] ?? null;
}

function burden(subject: Subject): string | null {
  return BURDENED[`${subject.domain}.${subject.key}`] ?? null;
}

/** What was liked, with the reader's own reason for a taste: 은은한 단맛, 또렷한 산미. */
function likedSaid(
  subject: Subject,
  reactions: readonly ReactionFact[],
): string | null {
  const word = liked(subject);
  const side = subject.domain === "taste"
    ? sideNamed(subject, reactions)
    : null;
  return word && side && side !== "mid" ? `${LIKED_SIDE[side]} ${word}` : word;
}

/** [closing the phrase, joined with the next one] */
function turned(direction: Adjust["direction"]): [string, string] {
  if (direction === "higher") return ["더 살린", "더 살리고"];
  if (direction === "softer") return ["부드럽게 다듬은", "부드럽게 다듬고"];
  return ["줄인", "줄이고"];
}

/** 부담은 줄인 / 아쉬움은 채운 / 부담은 줄이고 아쉬움은 채운: what the burdens asked for, unnamed. */
function turnedPhrase(adjust: readonly Adjust[]): string {
  const raised = adjust.some((a) => a.direction === "higher");
  const lowered = adjust.some((a) => a.direction !== "higher");
  if (raised && lowered) return "부담은 줄이고 아쉬움은 채운";
  return raised ? "아쉬움은 채운" : "부담은 줄인";
}

/** 떫은맛만 줄인 / 단맛은 줄이고 무게감은 더 살린 */
function adjustedPhrase(adjust: readonly Adjust[]): string {
  const parts = adjust.map((a) => ({
    noun: burden(a.subject)!,
    words: turned(a.direction),
  }));
  if (parts.every((p) => p.words[0] === parts[0].words[0])) {
    return `${parts.map((p) => p.noun).join("{과} ")}만 ${parts[0].words[0]}`;
  }
  return parts.map((p, i) =>
    `${p.noun}{은} ${i === parts.length - 1 ? p.words[0] : p.words[1]}`
  ).join(" ");
}

function bandOfLevel(level: number): Band {
  return level <= 2 ? "low" : level === 3 ? "mid" : "high";
}

function bandOfWord(level: string | undefined): Band | null {
  if (level === "none" || level === "low") return "low";
  if (level === "mid") return "mid";
  if (level === "high") return "high";
  return null;
}

function colorOfStyle(key: string, ko: string): string[] {
  if (key.endsWith("_red") || ko.includes("레드")) return ["red"];
  if (key.endsWith("_white") || ko.includes("화이트")) return ["white"];
  if (key.endsWith("_rose") || ko.includes("로제")) return ["rose"];
  return [];
}

function styleOf(t: Term): Style {
  const name = t.names?.ko ?? t.key;
  const levels: Record<string, Band> = {};
  for (const [axis, entry] of Object.entries(t.taste ?? {})) {
    const band = bandOfWord(entry.level);
    if (band) levels[axis] = band;
  }
  const hints = (t.hints ?? {}) as {
    colors?: string[];
    abv_range?: [number, number];
    bottled_regions?: { region: string; bottles: number }[];
  };
  return {
    key: t.key,
    name,
    colors: hints.colors ?? colorOfStyle(t.key, name),
    levels,
    aromas: (t.aromas ?? []).map((a) => a.key),
    abv: hints.abv_range ?? null,
    bottledRegions: hints.bottled_regions ?? [],
    rows: [t],
  };
}

/** The rows line 1 and line 2 can name, by shape. */
function pool(shape: Shape, category: string): Style[] {
  const types = shape === "A"
    ? ["grape"]
    : shape === "B"
    ? ["kind"]
    : shape === "C"
    ? ["maturation", "process"]
    : [];
  return terms(...types)
    .filter((t) => (t.categories ?? []).includes(category))
    .map(styleOf);
}

function recordLevels(facts: readonly ProductFact[]): Record<string, Band> {
  const out: Record<string, Band> = {};
  for (const p of facts) {
    if (p.fact.type === "level") {
      out[p.fact.dimension] = bandOfLevel(p.fact.level);
    }
  }
  return out;
}

/** One thing the reader said, in their own word: 단맛 liked, 묵직함 to ease, 여운 to fill. */
type Said = { word: string; turn: "keep" | "lower" | "higher" };

type Want =
  /**
   * from: the bottle's own band, which an adjusted level must move away from.
   * near: a level the reader did not mention; a next bottle two bands off it
   * is named only when no closer one fits, and it earns no score.
   */
  | {
    axis: string;
    band: Band;
    adjust: boolean;
    from?: Band;
    near?: true;
    /** A burden the bottle already sits at the end of: kept there. */
    floor?: true;
    /** With [floor]: a style known to sit off that end does not fit. */
    strict?: true;
    /** What the reader said that asks for it; an unmentioned level has none. */
    said?: Said;
  }
  /** avoid: an aroma to turn down, which the next bottle should not carry. */
  | { aroma: string; avoid?: true; said: Said };

/**
 * The band each kept or adjusted sensation should have in the next bottle.
 * An adjustment needs a level to move away from; a kept one stays where it
 * is; an unmentioned one stays near the record's when any style can (a dry
 * drinker who wants softer bubbles is not sent to 모스카토 다스티), and only a
 * bottle unlike every style is sent further.
 *
 * A burden the bottle already sits at the end of (a 40% whisky found hot) is
 * kept at that end: nothing can be shown to go further, but the guide is
 * still written.
 *
 * The reader's own word outranks the catalog number. 가벼워서 아쉬웠다 asks
 * for a heavier bottle; 또렷해서 좋았다 of a level the catalog calls low is
 * kept a band up from it, 은은해서 좋았다 a band down; a burden kept at its
 * end rules out a style known to sit off that end. An aroma to turn down is
 * kept out of the next bottle.
 *
 * [settled]: the four traditional kinds, whose guides were settled on the
 * earlier reading and are written by their own label rules.
 */
function wanted(
  next: NextChoice,
  record: Levels,
  reactions: readonly ReactionFact[],
  settled: boolean,
): Want[] {
  const out: Want[] = [];
  for (const a of next.adjust) {
    if (a.subject.domain === "aroma") {
      // One wanted stronger is looked for like a liked one.
      if (!settled) {
        const said: Said = { word: scent(a.subject.key), turn: saidTurn(a) };
        out.push(
          saidTurn(a) === "higher"
            ? { aroma: a.subject.key, said }
            : { aroma: a.subject.key, avoid: true, said },
        );
      }
      continue;
    }
    const target = axisOf(a.subject);
    if (!target) continue;
    const from = target.band ?? record[target.axis];
    if (!from) continue;
    const up = (settled ? saidTurn(a) : axisTurn(a)) === "higher";
    if (from === (up ? "high" : "low")) {
      out.push({
        axis: target.axis,
        band: from,
        adjust: false,
        floor: true,
        ...(settled ? {} : { strict: true as const }),
      });
      continue;
    }
    const word = burdenWord(a, reactions);
    out.push({
      axis: target.axis,
      band: up ? "high" : "low",
      adjust: true,
      from,
      ...(word ? { said: { word, turn: saidTurn(a) } } : {}),
    });
  }
  for (const s of next.keep) {
    const word = likedSaid(s, reactions);
    if (s.domain === "aroma") {
      out.push({ aroma: s.key, said: { word: scent(s.key), turn: "keep" } });
      continue;
    }
    const target = axisOf(s);
    const own = target && (target.band ?? record[target.axis]);
    const band = settled || !own ? own : toward(own, sideNamed(s, reactions));
    if (
      target && band && !out.some((w) => "axis" in w && w.axis === target.axis)
    ) {
      out.push({
        axis: target.axis,
        band,
        adjust: false,
        ...(word ? { said: { word, turn: "keep" as const } } : {}),
      });
    }
  }
  for (const [axis, band] of Object.entries(record)) {
    if (!out.some((w) => "axis" in w && w.axis === axis)) {
      out.push({ axis, band, adjust: false, near: true });
    }
  }
  return out;
}

const RANK: Readonly<Record<Band, number>> = { low: 0, mid: 1, high: 2 };

/** One band from the catalog's reading toward the side the reader named. */
function toward(own: Band, said: Band | null): Band {
  if (!said || said === own) return own;
  return own === "mid" ? said : "mid";
}
/** The score cost of sitting two bands off a level the reader did not mention. */
const FAR = -100;

/**
 * A style's band for an axis. Casks and methods hold 부드러움 (smoothness)
 * where kinds hold 알코올 열감: a smooth one is one with little heat.
 */
function bandFor(style: Style, axis: string): Band | undefined {
  const band = style.levels[axis];
  if (band || axis !== "alcohol_presence") return band;
  const smooth = style.levels.smoothness;
  return smooth === "high" ? "low" : smooth === "low" ? "high" : smooth;
}

/** Does the style bring the aroma, or one of its line (피트 for 스모키's own kind)? */
function carries(style: Style, aroma: string): boolean {
  return style.aromas.some((a) =>
    lineage(a).includes(aroma) || lineage(aroma).includes(a)
  );
}

/**
 * How well a style fits: null when it cannot be shown to turn every burden
 * down, brings an aroma to turn down, or sits two bands off a level the
 * reader kept; two bands off a level the reader did not mention costs [FAR].
 */
function fit(style: Style, wants: readonly Want[]): number | null {
  let kept = 0;
  for (const w of wants) {
    if ("aroma" in w) {
      if (w.avoid) {
        if (carries(style, w.aroma)) return null;
      } else if (style.aromas.includes(w.aroma)) kept++;
      continue;
    }
    const band = bandFor(style, w.axis);
    if (w.near) {
      if (band && Math.abs(RANK[band] - RANK[w.band]) > 1) kept += FAR;
    } else if (w.adjust) {
      // Any step the asked way counts: 탄산 high to mid is softer bubbles.
      const moved = band && w.from &&
        (w.band === "low"
          ? RANK[band] < RANK[w.from]
          : RANK[band] > RANK[w.from]);
      if (!moved) return null;
    } else if (band === w.band) {
      kept++;
    } else if (band && (w.strict || Math.abs(RANK[band] - RANK[w.band]) > 1)) {
      return null;
    }
  }
  return kept;
}

/** A burden head when something is to change, else the liked head. */
function headFor(adjust: readonly unknown[], liked = true): string {
  if (adjust.length && !liked) return HEAD_ONLY_BURDEN;
  return adjust.length ? HEAD_BURDEN : HEAD_POSITIVE;
}

function fill(text: string, slots: Readonly<Record<string, string>>): string {
  return josa(text.replace(/\{([A-Z]+)\}/g, (m, k: string) => slots[k] ?? m))
    .replace(/\s+/g, " ").trim();
}

/** Sparkling and fortified wine are named only by their own kind of style, and still wine never by them. */
function sameShape(style: Style, own: readonly string[]): boolean {
  return ["sparkling", "fortified"].every((shape) =>
    own.some((k) => k.includes(shape)) === style.key.includes(shape)
  );
}

/** A sister kind is named only when its usual strength overlaps the record's kind: 탁주 never points to 소주. */
function near(
  a: readonly [number, number] | null,
  b: readonly [number, number] | null,
): boolean {
  return !!a && !!b && a[0] <= b[1] && b[0] <= a[1];
}

/** The words a reader looks for on the label: '생막걸리' from "'살균'보다 '생막걸리'이고 …". */
function labelWords(cue: Cue): string {
  if (cue.label) return cue.label;
  const after = cue.compare.split("보다").pop()!;
  const quoted = after.match(/'[^']+'/g);
  if (quoted) return `${quoted.slice(0, 2).join("·")} 표기`;
  // "숙성 연수가 15~18년인 것" reads 숙성 연수 15~18년: the number is the thing to find.
  const measured = cue.compare.match(/^(.+?)(?:가|이) (\d.*?)인 것/);
  if (measured) return `${measured[1]} ${measured[2]}`;
  return cue.cue.endsWith("표기") ? cue.cue : `${cue.cue} 표기`;
}

function direction(band: Band): "lower" | "higher" | null {
  return band === "high" ? "higher" : band === "low" ? "lower" : null;
}

/* ------------------------------------------------- what a shelf holds */

/** A word on fewer than one bottle in a hundred of its shelf is not one to send a reader looking for. */
const FINDABLE_SHARE = 0.01;

/**
 * A grape is named for a felt-sweetness lean when this part of its bottles
 * leans that way. A kind's bottles lean a third each way on the whole.
 */
const LEAN_SHARE = 0.4;

/**
 * The shelf a word is counted on. A whisky's casks and a sake's grades are
 * named across the kinds of the category, so the category; a wine or a
 * traditional drink is never sent to another kind, so the reader's own kind
 * (a kind of too few bottles to count borrows its pool, then its category).
 */
function shelfOf(c: GuideContext): string | null {
  if (c.category === "whisky" || c.category === "sake") return c.category;
  return shelfOfKind(c.facts.record.style_key, c.category);
}

type Counted = { bottles: number; of: number };

/** How many bottles of the reader's shelf carry the key; null where the catalog keeps no count. */
function shelfCount(
  c: GuideContext,
  what: Carried,
  key: string,
): Counted | null {
  return bottlesCarrying(what, key, shelfOf(c));
}

/**
 * False only for what the catalog counts and counts too few of: a word on
 * fewer than FINDABLE_SHARE of the shelf, a grape the kind does not list
 * (fewer than MIN_GRAPE_BOTTLES).
 */
function findable(counted: Counted | null, what: Carried = "made"): boolean {
  if (!counted) return true;
  return what === "grapes"
    ? counted.bottles >= MIN_GRAPE_BOTTLES
    : counted.bottles >= FINDABLE_SHARE * counted.of;
}

/** Most common first, then by key so the order never depends on the dictionary's. */
function byCommon<T extends { key: string; counted: Counted | null }>(
  x: T,
  y: T,
): number {
  return (y.counted?.bottles ?? 0) - (x.counted?.bottles ?? 0) ||
    x.key.localeCompare(y.key);
}

const count = (n: number) => n.toLocaleString("en-US");

/* ------------------------------------------------ what a chip is called */

const hasLatin = (word: string) => /[A-Za-z]/.test(word);
const hasHangul = (word: string) => /[가-힣]/.test(word);

/** 산지오베제(키안티·브루넬로) is named 산지오베제. */
const bare = (name: string) => name.replace(/\(.*\)$/, "").trim();

/** 원어(한글): the label's spelling and how it is read; the Korean alone where a label prints Korean. */
const spelled = (label: string | null | undefined, ko: string) =>
  label && label !== ko ? `${label}(${ko})` : ko;

/**
 * The chip words of a grape, a grade or a regional style, by the label
 * spelling the dictionary keeps for it (names.label). A grape of two names
 * is two words: Syrah(시라) · Shiraz(쉬라즈).
 */
function nameWords(term: Term): string[] {
  const ko = bare(term.names.ko);
  const readings = ko.split("·");
  const labels = term.names.label?.split("·") ?? [];
  return labels.length === readings.length && labels.length > 1
    ? readings.map((reading, i) => spelled(labels[i].trim(), reading.trim()))
    : [spelled(term.names.label, ko)];
}

/**
 * The spelling a cask or a method is printed as: its first label word. A
 * 전통주 label prints Korean, so its chip stays Korean; a sake label prints
 * kanji; elsewhere the first word in Latin letters.
 */
function termLabel(key: string, category: string): string | null {
  if (category === "korean_traditional") return null;
  const words = labelWordsOf(key);
  return (category === "sake" ? words[0] : words.find(hasLatin)) ?? null;
}

/** The chip word of a cask or a method: Sherry Cask(셰리 캐스크), 목재 캐스크. */
function termWord(key: string, category: string): string {
  return spelled(
    termLabel(key, category),
    caskTermByKey.get(key)?.names.ko ?? key,
  );
}

/**
 * One quoted label word as a chip writes it. A word the dictionary names is
 * spelled with its reading: dry(드라이), Bourbon Cask(버번 캐스크),
 * 貴醸酒(기조슈), 山廃(야마하이); else the reading the kind's own cues give
 * ('Amarone'(아마로네)); else the word alone. A 전통주 word stays as printed.
 */
function labelWord(word: string, c: GuideContext): string {
  if (c.category === "korean_traditional") return word;
  const key = wordKey(word);
  const named = NAMED_WORDS.get(key);
  if (named) {
    return hasHangul(word)
      ? spelled(named.label, word)
      : spelled(word, named.ko);
  }
  const made = MADE_WORDS.get(key);
  if (made && hasHangul(word)) {
    return spelled(termLabel(made.key, c.category), word);
  }
  // A cask's reading is its name only for its first label word: Barrel Proof is not 캐스크 스트렝스.
  const first = made && labelWordsOf(made.key)[0];
  if (made && first && wordKey(first) === key) {
    return spelled(first, made.names.ko);
  }
  const reading = c.readings.get(key);
  return reading ? spelled(word, reading) : word;
}

/** The words a cue's chip shows: its quoted label words, else its own name for what to find. */
function cueWords(cue: Cue): string[] {
  const shown = shownWords(cue);
  return shown.length ? shown : [labelWords(cue).replace(/\s*표기$/, "")];
}

/* ------------------------------------------------- why a chip is picked */

/**
 * Why a pick suits the reader: what it answers of what they said, and what
 * shows it.
 */
type Why = {
  /** The burdens it eases and the lacks it fills. */
  turned: Said[];
  /** The liked things it is shown to keep. */
  kept: Said[];
  /** A liked aroma it carries only a neighbour of: 바닐라 liked, 코코넛 brought. */
  kin?: { liked: string; brought: string } | null;
  /** No level the reader left unsaid sits far from the bottle's. */
  alike: boolean;
  /** One sentence of what was counted or how sure the dictionary is. */
  evidence: string | null;
};

/** The dictionary's row for a style's level; a cask holds 부드러움 where a kind holds 알코올 열감 (bandFor). */
function tasteRow(style: Style, axis: string) {
  for (const row of style.rows) {
    const taste = row.taste ?? {};
    const found = taste[axis] ??
      (axis === "alcohol_presence" ? taste.smoothness : undefined);
    if (found) return found;
  }
  return undefined;
}

function aromaRow(style: Style, aroma: string) {
  for (const row of style.rows) {
    const found = (row.aromas ?? []).find((a) => a.key === aroma);
    if (found) return found;
  }
  return undefined;
}

/** A count speaks from this many bottles: "51병이 대체로 그랬어요" says little. */
const MIN_EVIDENCE_BOTTLES = 100;

/**
 * What was counted behind a dictionary row, said: a level that is the middle
 * value of enough of our own bottles. How the dictionary knows a row it did
 * not count (made that way, usual, collected) orders the picks and is never
 * said: the word's own explanation tells it.
 */
function evidenceOf(
  row: { basis?: string; reason?: string } | undefined,
): string | null {
  const bottles = countedBottles(row);
  return bottles >= MIN_EVIDENCE_BOTTLES
    ? fill(EVIDENCE_COUNTED, { N: count(bottles) })
    : null;
}

/**
 * No unmentioned level of the style sits two bands off the bottle's. [axes]:
 * only these levels are compared, where a kind is told apart by its marks.
 */
function alikeTo(
  style: Style,
  wants: readonly Want[],
  axes?: readonly [string, string][],
): boolean {
  const unsaid = wants.filter((w) =>
    "axis" in w && w.near && (!axes || axes.some(([axis]) => axis === w.axis))
  );
  return (fit(style, unsaid) ?? 0) > FAR / 2;
}

/**
 * What a style answers of what the reader said: each burden it turns, each
 * liked level it sits on and each liked aroma it carries, with the
 * dictionary row behind the first of them. Call it for a style that fits.
 */
function answersOf(
  style: Style,
  wants: readonly Want[],
  axes?: readonly [string, string][],
): Why {
  const turned: Said[] = [];
  const kept: Said[] = [];
  type Row = Parameters<typeof evidenceOf>[0];
  // The row behind the first burden turned speaks before a liked thing's.
  const rows: { turned?: Row; kept?: Row } = {};
  const claim = (said: Said, row: Row) => {
    const side = said.turn === "keep" ? "kept" : "turned";
    (side === "kept" ? kept : turned).push(said);
    rows[side] ??= row;
  };
  for (const w of wants) {
    if ("aroma" in w) {
      if (w.avoid) {
        if (!carries(style, w.aroma)) claim(w.said, undefined);
      } else if (style.aromas.includes(w.aroma)) {
        claim(w.said, aromaRow(style, w.aroma));
      }
      continue;
    }
    if (w.near || w.floor || !w.said) continue;
    const band = bandFor(style, w.axis);
    const answered = w.adjust
      ? !!band && !!w.from &&
        (w.band === "low"
          ? RANK[band] < RANK[w.from]
          : RANK[band] > RANK[w.from])
      : band === w.band;
    if (answered) claim(w.said, tasteRow(style, w.axis));
  }
  return {
    turned,
    kept,
    alike: alikeTo(style, wants, axes),
    evidence: evidenceOf(turned.length ? rows.turned : rows.kept),
  };
}

/** The first two of what was said, joined: 단맛과 산미. */
const saidWords = (said: readonly Said[]) =>
  said.slice(0, 2).map((s) => s.word).join("{과} ");

/**
 * The note under a chip: the frame its answers call for, then the evidence.
 * A pick that turns a burden and is shown to keep a liked thing says both;
 * one that only turns a burden speaks from this bottle; one that only keeps
 * says what carries on. The counts go to every frame for the owner's wording.
 */
function noteOf(
  c: GuideContext,
  why: Why,
  counted: Counted | null = null,
): string | null {
  // Only the reader's own words: a burden they named in the place of what is
  // eased, a thing they liked in the place of what stays.
  const turned = why.turned.filter((s) => c.burdenWords.has(s.word));
  const kept = why.kept.filter((s) => c.keptWords.has(s.word));
  const first = turned[0];
  const filling = first?.turn === "higher";
  const frame = first
    ? kept.length
      ? filling ? NOTE_FILL_KEEP : NOTE_EASE_KEEP
      : why.alike
      ? filling ? NOTE_ONLY_FILL_ALIKE : NOTE_ONLY_EASE_ALIKE
      : filling
      ? NOTE_ONLY_FILL
      : NOTE_ONLY_EASE
    : kept.length
    ? NOTE_CARRY
    : why.kin
    ? NOTE_CARRY_KIN
    : null;
  if (!frame) return null;
  const said = fill(frame, {
    X: saidWords(turned.filter((s) => s.turn === first?.turn)),
    L: kept.length ? saidWords(kept) : why.kin?.liked ?? "",
    A: why.kin?.brought ?? "",
    N: counted ? count(counted.bottles) : "",
    T: counted ? count(counted.of) : "",
    K: c.shelfName,
  });
  return [said, why.evidence].filter(Boolean).join(" ");
}

/* ------------------------------------- grapes, grades and regional styles */

type Option = { s: Style; key: string; why: Why; counted: Counted | null };

/**
 * The styles to name, practical first. Kept: the ones that fit (every burden
 * turned, nothing the reader said undone), answer at least one thing the
 * reader said, and sit near the bottle on every level that went unsaid (a
 * brut drinker who liked the 산미 is not sent to 모스카토 다스티). A wine is
 * compared on the marks its guide shows ([axes]): a grape is not left out
 * for a 여운 the shelf does not print. Dropped: the ones the shelf hardly
 * holds. Then the most common first.
 */
function chooseStyles(
  c: GuideContext,
  styles: readonly Style[],
  what: Carried,
  axes?: readonly [string, string][],
): Option[] {
  return styles.flatMap((s) => {
    if (fit(s, c.wants) === null) return [];
    const why = answersOf(s, c.wants, axes);
    return why.alike && (why.turned.length || why.kept.length)
      ? [{ s, key: s.key, why, counted: shelfCount(c, what, s.key) }]
      : [];
  }).filter((option) => findable(option.counted, what)).sort(byCommon);
}

/* ------------------------------------------------------ casks and methods */

/** sure: the dictionary says the cask is made to carry the sought aroma or usually does; a collected note is a weaker reason. */
type CaskOption = Option & { sure: boolean };

const SURE_BASIS: ReadonlySet<string> = new Set(["production", "typical"]);

/**
 * 목재 캐스크 beside 셰리 캐스크 tells no bottle apart: a cask the dictionary
 * holds only as the root of more particular ones is not named while the
 * shelf has one of those.
 */
function bareRoot(
  c: GuideContext,
  style: Style,
  pool: readonly Style[],
): boolean {
  const parentOf = (key: string) =>
    (caskTermByKey.get(key)?.extra?.taxonomy as
      | { parent_term_key?: string }
      | undefined)?.parent_term_key;
  if (parentOf(style.key)) return false;
  return pool.some((other) =>
    parentOf(other.key) === style.key &&
    findable(shelfCount(c, "made", other.key))
  );
}

/**
 * Casks and methods for a sought aroma, practical first. Kept: one that
 * carries a sought aroma itself (a neighbour of the aroma is no answer),
 * brings no aroma to turn down and moves no burden the wrong way (most casks
 * hold no 알코올 열감 at all; 캐스크 스트렝스 is no answer after a 40% whisky
 * found hot). Dropped: the ones the shelf hardly holds. Of what is left the
 * ones the dictionary is sure of stay when there are any (an aroma the cask
 * is made to or usually does carry, before one only collected notes give
 * it), the most common first. The bottle's own cask is named for the liked
 * aroma alone, never as what turns a burden.
 */
function chooseCasks(
  c: GuideContext,
  styles: readonly Style[],
  sought: ReadonlySet<string>,
): CaskOption[] {
  const sureOf = (s: Style, aroma: string) =>
    SURE_BASIS.has(aromaRow(s, aroma)?.basis ?? "");
  const open = styles.flatMap((s): CaskOption[] => {
    const turned: Said[] = [];
    let moved: string | undefined;
    for (const w of c.wants) {
      if ("aroma" in w) {
        if (w.avoid && carries(s, w.aroma)) return [];
        continue;
      }
      const band = bandFor(s, w.axis);
      if (band && w.strict && Math.abs(RANK[band] - RANK[w.band]) > 1) {
        return [];
      }
      if (!band || !w.from || !w.adjust) continue;
      const wrong = w.band === "low"
        ? RANK[band] > RANK[w.from]
        : RANK[band] < RANK[w.from];
      if (wrong) return [];
      if (band !== w.from && w.said && !c.made.has(s.key)) {
        turned.push(w.said);
        moved ??= w.axis;
      }
    }
    // The aroma the dictionary is surest of speaks for the cask.
    const carried = [...sought].filter((l) => s.aromas.includes(l))
      .sort((x, y) => Number(sureOf(s, y)) - Number(sureOf(s, x)));
    if (!carried.length) return [];
    const said = carried.map((l): Said => ({
      word: scent(l),
      turn: c.raisedAromas.includes(l) ? "higher" : "keep",
    }));
    return [{
      s,
      key: s.key,
      why: {
        turned: [...turned, ...said.filter((x) => x.turn !== "keep")],
        kept: said.filter((x) => x.turn === "keep"),
        alike: alikeTo(s, c.wants),
        evidence: evidenceOf(
          moved ? tasteRow(s, moved) : aromaRow(s, carried[0]),
        ),
      },
      counted: shelfCount(c, "made", s.key),
      sure: sureOf(s, carried[0]),
    }];
  }).filter((option) =>
    findable(option.counted) && !bareRoot(c, option.s, styles)
  );
  const sure = open.filter((option) => option.sure);
  return (sure.length ? sure : open).sort(byCommon);
}

/**
 * "피에몬테(Piemonte) > 아스티(Asti)": the top region's country, the root of
 * the region tree. The English name, else the bottle count, decides between
 * same-named regions (피에몬테 is also a stray row elsewhere).
 */
function countryOfRegion(
  row: { hints?: unknown },
): { country: string; name: string } | undefined {
  const top =
    ((row.hints as { region_labels?: string[] }).region_labels?.[0] ?? "")
      .split(" > ")[0];
  const [, ko = top, en = ""] = top.match(/^(.*?)\((.*)\)$/) ?? [];
  const regions = terms("region");
  const named = regions.filter((t) => t.names.ko === ko.trim());
  const same = named.filter((t) =>
    (t.names.en ?? "").toLowerCase() === en.trim().toLowerCase()
  );
  // The busiest row wins: it_piemonte (1,928 bottles), not a stray cn_piemonte.
  let region: (typeof regions)[number] | undefined =
    [...(same.length ? same : named)].sort((x, y) =>
      ((y.extra?.bottles as number) ?? 0) - ((x.extra?.bottles as number) ?? 0)
    )[0];
  while (region?.parent) region = regionByKey.get(region.parent);
  return region ? { country: region.key, name: region.names.ko } : undefined;
}

/** The country a region sits in: the root of its tree (its key is ISO 3166-1 alpha-2). */
function countryOfKey(
  key: string,
): { country: string; name: string } | undefined {
  let row = regionByKey.get(key);
  while (row?.parent) row = regionByKey.get(row.parent);
  return row ? { country: row.key, name: row.names.ko } : undefined;
}

/** A grape bottled in one region: the grape's taste, the region's where the grape has none, the aromas of both. */
function grapeInRegion(grape: Style, region: Style): Style {
  return {
    ...grape,
    levels: { ...region.levels, ...grape.levels },
    aromas: [...new Set([...grape.aromas, ...region.aromas])],
    rows: [...grape.rows, ...region.rows],
  };
}

/** A grape's chip: its label spelling, led by the region given. */
function grapePick(
  grape: Style,
  region: string | undefined,
  note: string | null,
): GuidePick {
  const row = region ? regionByKey.get(region) : undefined;
  return pickOf({
    country: row && countryOfKey(row.key),
    place: row?.parent ? row.names.ko : undefined,
    words: nameWords(grape.rows[0]),
    labelWord: false,
    note,
  });
}

/** A grape is led by a region with at least this part of the bottles its largest region has: 토스카나 for 산지오베제, not a region with a handful. */
const REGION_SHARE = 0.2;

/** The still-wine regions a grape's chip may be led by, most bottles first, at most three. */
function homeRegions(grape: Style): string[] {
  const still = grape.bottledRegions.filter((r) => {
    const row = regionByKey.get(r.region);
    return row && styleOf(row).levels.carbonation !== "high";
  });
  return still
    .filter((r) => r.bottles >= REGION_SHARE * still[0].bottles)
    .slice(0, 3)
    .map((r) => r.region);
}

/**
 * A: up to two grapes, each read in the region most of its bottles come
 * from that fits (a sparkling region stays out of still wine; a grape none
 * of whose regions fits, or without region counts, stands on its own),
 * chosen as chooseStyles chooses.
 */
function grapePicks(c: GuideContext, grapes: readonly Style[]): GuidePick[] {
  const where = new Map<string, string>();
  const read = grapes.flatMap((g) => {
    if (!g.bottledRegions.length) return [g];
    for (const region of homeRegions(g)) {
      const row = regionByKey.get(region);
      if (!row) continue;
      const both = grapeInRegion(g, styleOf(row));
      if (fit(both, c.wants) === null) continue;
      where.set(g.key, region);
      return [both];
    }
    // None of its regions fits: the grape by its own row, led by no place.
    return [g];
  });
  return chooseStyles(c, read, "grapes", WINE_SPEC).slice(0, 2).map((option) =>
    grapePick(
      option.s,
      where.get(option.key),
      noteOf(c, option.why, option.counted),
    )
  );
}

/** The 도수 printed on the bottle, when the catalog holds it. */
function abvOf(facts: readonly ProductFact[]): number | null {
  const fact = facts.find((p) => p.fact.type === "abv")?.fact;
  return fact && fact.type === "abv" ? fact.value : null;
}

/** The bottle's own 1–5 level on an axis, estimated or read. */
function levelOf(
  facts: readonly ProductFact[],
  axis: string,
): number | undefined {
  const fact = facts.find((p) =>
    p.fact.type === "level" && p.fact.dimension === axis
  )?.fact;
  return fact && fact.type === "level" ? fact.level : undefined;
}

/**
 * The 1–5 marks to look for on a shelf or menu, from the bottle's own levels.
 * A level to lower is named two steps down, one to raise a step up, a liked
 * one as it is: one number, the safe side. Only an unmentioned level gets a
 * range, and never wider than one step. A level copied from the kind
 * (estimated) still guides: it is what such a bottle usually is. Each mark
 * is also said in the word a shop uses for it.
 */
function specLevels(
  facts: readonly ProductFact[],
  adjust: readonly Adjust[],
  keptAxes: ReadonlySet<string>,
  axes: readonly [string, string][],
  words: Readonly<Record<string, readonly string[]>>,
  named: (axis: string) => Band | null = () => null,
): GuideLevel[] {
  const rows: GuideLevel[] = [];
  for (const [axis, label] of axes) {
    const v = levelOf(facts, axis);
    if (!v) continue;
    const a = adjust.find((x) => axisOf(x.subject)?.axis === axis);
    // Filled marks sit at the level to look for; the words give the range.
    let [mark, lo, hi] = aimAt(v, a ? axisTurn(a) : null, keptAxes.has(axis));
    // 또렷해서 좋았다 reaches a step up from the bottle, 은은해서 좋았다 a step down.
    const side = !a && keptAxes.has(axis) ? named(axis) : null;
    if (side === "high") hi = Math.min(5, v + 1);
    if (side === "low") lo = Math.max(1, v - 1);
    if (side) mark = v;
    rows.push({
      label,
      mark,
      range: lo === hi ? `${lo}` : `${lo}~${hi}`,
      word: words[axis]?.[mark - 1] ?? null,
    });
  }
  return rows;
}

/** [mark, lo, hi]: the level to look for, and the range the words give. */
function aimAt(
  v: number,
  turn: "higher" | "lower" | null,
  kept: boolean,
): [number, number, number] {
  if (turn) {
    const at = turn === "higher" ? Math.min(5, v + 1) : Math.max(1, v - 2);
    return [at, at, at];
  }
  if (kept) return [v, v, v];
  return v === 1 ? [1, 1, 2] : [v, v - 1, v];
}

/** The burden's own word: 더 높게 raises, every other one lowers. */
const saidTurn = (a: Adjust): "higher" | "lower" =>
  a.direction === "higher" ? "higher" : "lower";

/**
 * Which way the burden moves the level it speaks of. 가벼움 is the low end of
 * 바디, so turning it down is a heavier bottle.
 */
function axisTurn(a: Adjust): "higher" | "lower" {
  const said = saidTurn(a);
  if (axisOf(a.subject)?.band !== "low") return said;
  return said === "higher" ? "lower" : "higher";
}

/**
 * 도수: the band to look for on the label, in percent on the kind's own ABV
 * bands (40~43% for a whisky), aimed like the other marks. A band no bottle of
 * the kind reaches (a whisky under 40%) is passed over for the next one up.
 */
function abvLevel(
  facts: CardFacts,
  adjust: readonly Adjust[],
  keptAxes: ReadonlySet<string>,
  kindMin: number | null,
  fromBottle = false,
): GuideLevel | null {
  const v = levelOf(facts.product_facts, "alcohol_presence");
  const found = abvBandsFor(facts.record.style_key, facts.record.category);
  if (!v || !found) return null;
  const a = adjust.find((x) => axisOf(x.subject)?.axis === "alcohol_presence");
  const bounds = found.bands.bounds;
  const own = abvOf(facts.product_facts);
  const abv = fromBottle ? own : null;
  // Read on the kind's bands alone: a whisky.
  const whisky = !fromBottle;
  // A 탁주 or 소주 weighs more the stronger it is (our own shelf: 탁주 under
  // 7% averages body 2.4, over 13% 4.2), so a weight to turn while drinking
  // moves the 도수 one band the same way when the heat itself went unsaid.
  // 텁텁함 alone is what stays after swallowing, not that weight. A whisky
  // does the same, and its finish lengthens with it (our own shelf: single
  // malts under 43% average body 2.9 and finish 3.7, those of 55% and over
  // 4.0 and 4.2), so a finish to lengthen moves its 도수 up a band too.
  const weight =
    (abv !== null || whisky) && !a && !keptAxes.has("alcohol_presence")
      ? adjust.find((x) =>
        (x.subject.domain === "mouthfeel" &&
          (x.subject.key === "light" ||
            (x.subject.key === "heavy" && !isResidue(x, facts.reactions)))) ||
        (whisky && x.subject.domain === "finish" &&
          x.subject.key === "persistence")
      )
      : undefined;
  const stronger = weight &&
    (weight.subject.key === "light" ||
      (weight.subject.key === "persistence" && saidTurn(weight) === "higher"));
  // Nothing to turn: the bottle's own number is the place to look.
  if (abv !== null && !a && !weight) {
    return { label: "도수", mark: v, range: `${abv}% 안팎`, word: null };
  }
  const moved = weight
    ? stronger ? Math.min(5, v + 1) : Math.max(1, v - 1)
    : null;
  let [mark, lo, hi] = moved === null
    ? aimAt(v, a ? saidTurn(a) : null, keptAxes.has("alcohol_presence"))
    : [moved, moved, moved];
  while (lo < 5 && kindMin !== null && kindMin >= bounds[lo - 1]) lo++;
  mark = Math.max(mark, lo);
  hi = Math.max(hi, lo);
  const floor = bounds[lo - 2];
  let ceiling = bounds[hi - 1];
  // A lower 도수 ends under the bottle's own: "17~24%" after a 25% bottle.
  const lowering = a ? a.direction !== "higher" : !!weight && !stronger;
  // A whisky's does while its band has room under the bottle: "40~42%" after
  // a 43% one, "40~43%" after a 40% one, the lowest a whisky goes.
  const room = fromBottle ||
    (own !== null && floor !== undefined && Math.ceil(own) - 1 > floor);
  if (
    own !== null && lowering && ceiling !== undefined && ceiling >= own && room
  ) {
    ceiling = Math.ceil(own) - 1;
  }
  const range = floor !== undefined && ceiling !== undefined
    ? `${floor}~${ceiling}%`
    : ceiling !== undefined
    ? `${ceiling}% 미만`
    : `${floor}% 이상`;
  // The band already speaks in the label's own number.
  return { label: "도수", mark, range, word: null };
}

/**
 * The label numbers to look for on a sake: the band of the bottle's own level,
 * two steps drier or lighter for a level to lower, one step up for one to
 * raise. A band is already a range, so no level gets a wider one.
 */
function sakeLevels(
  facts: readonly ProductFact[],
  adjust: readonly Adjust[],
): GuideLevel[] {
  const rows: GuideLevel[] = [];
  const axes: readonly [string, string, readonly string[]][] = [
    ["sweetness", "당도(주도)", SMV_BANDS],
    ["acidity", "산미(산도)", ACIDITY_BANDS],
  ];
  for (const [axis, label, bands] of axes) {
    const v = levelOf(facts, axis);
    if (!v) continue;
    const a = adjust.find((x) => axisOf(x.subject)?.axis === axis);
    const at = !a
      ? v
      : a.direction === "higher"
      ? Math.min(5, v + 1)
      : Math.max(1, v - 2);
    rows.push({
      label,
      mark: at,
      range: bands[at - 1],
      // The band already says its trade name (카라구치) and the label's own number.
      word: null,
    });
  }
  return rows;
}

/**
 * 純米(준마이) · 純米吟醸(준마이 긴조): up to two sister grades in one chip,
 * the most common that fits and the next one that answers something the
 * first does. The note says only what both answer.
 */
function gradePick(c: GuideContext, grades: readonly Option[]): GuidePick {
  const [first] = grades;
  const shared = (other: Option): Why => {
    const both = (mine: Said[], theirs: Said[]) =>
      mine.filter((s) => theirs.some((t) => t.word === s.word));
    return {
      ...first.why,
      turned: both(first.why.turned, other.why.turned),
      kept: both(first.why.kept, other.why.kept),
      alike: first.why.alike && other.why.alike,
    };
  };
  const second = grades.slice(1).find((other) => {
    const why = shared(other);
    return why.turned.length === first.why.turned.length &&
      (why.turned.length > 0 || why.kept.length > 0);
  });
  return pickOf({
    words: [first, ...(second ? [second] : [])].flatMap((grade) =>
      nameWords(grade.s.rows[0])
    ),
    labelWord: false,
    note: noteOf(c, second ? shared(second) : first.why, first.counted),
  });
}

/** Every cask (maturation) and method (process) row by its key. */
const caskTermByKey = new Map(
  terms("maturation", "process").map((t) => [t.key, t]),
);

/** The words a cask or method is printed as on a label. */
function labelWordsOf(key: string): string[] {
  const row = caskTermByKey.get(key);
  return (row?.hints as { label_words?: string[] } | undefined)?.label_words ??
    [];
}

/**
 * A dictionary word a quoted label word answers to: a row that keeps its
 * label spelling (a grape, a grade, a regional style, a word printed on
 * labels), by that spelling and by its Korean name.
 */
const NAMED_WORDS: ReadonlyMap<string, { label: string; ko: string }> = (() => {
  const map = new Map<string, { label: string; ko: string }>();
  for (const term of terms("label_word", "grape", "regional_style", "kind")) {
    if (!term.names.label) continue;
    const readings = bare(term.names.ko).split("·");
    const labels = term.names.label.split("·");
    const pairs = labels.length === readings.length
      ? labels.map((label, i) => [label, readings[i]] as const)
      : [[term.names.label, bare(term.names.ko)] as const];
    for (const [label, ko] of pairs) {
      const named = { label: label.trim(), ko: ko.trim() };
      for (const word of [named.label, named.ko]) {
        if (!map.has(wordKey(word))) map.set(wordKey(word), named);
      }
    }
  }
  return map;
})();

/** The cask or method a label word is printed for, the first row that lists it. */
const MADE_WORDS: ReadonlyMap<string, Term> = (() => {
  const map = new Map<string, Term>();
  for (const term of caskTermByKey.values()) {
    for (const word of [term.names.ko, ...labelWordsOf(term.key)]) {
      if (!map.has(wordKey(word))) map.set(wordKey(word), term);
    }
  }
  return map;
})();

/** The grape a label word names, for a wine cue that points at one: 'Riesling'. */
const GRAPE_WORDS: ReadonlyMap<string, string> = new Map(
  terms("grape").flatMap((term) =>
    (term.names.label?.split("·") ?? []).map((label) =>
      [wordKey(label), term.key] as const
    )
  ),
);

/** What every shape of guide reads from one card. */
type GuideContext = {
  facts: CardFacts;
  next: NextChoice;
  record: Levels;
  wants: ReturnType<typeof wanted>;
  /** The burdens the guide can name. */
  adjust: NextChoice["adjust"];
  /** The aromas to turn down. The four traditional kinds answer them by their label rules and hold none here. */
  turnedAromas: string[];
  /** The aromas wanted stronger, looked for like the liked ones. */
  raisedAromas: string[];
  /** The bottle's own casks and methods. */
  made: Set<string>;
  /** The aromas the reader liked and keeps. */
  skipAromas: Set<string>;
  /** The liked axes that stay where the bottle has them. */
  keptAxes: Set<string>;
  styleKeys: string[];
  category: string;
  kindRow: ReturnType<typeof terms>[number] | undefined;
  kind: Style | null;
  cues: Cue[];
  slots: Record<string, string>;
  /** The name of the shelf the chips are counted on: 위스키, 레드 와인. */
  shelfName: string;
  /** How the kind's own cues read a label word: 'Amarone'(아마로네). */
  readings: Map<string, string>;
  /** What the head counts as turned: the nameable burdens, and the aromas to turn. */
  turns: NextChoice["adjust"];
  /** The burdens and lacks in the reader's own words: the only words a note may say are eased or filled. */
  burdenWords: Set<string>;
  /** What the reader keeps, in their own words: the only words a note may say carry on. */
  keptWords: Set<string>;
  head: string;
};

/** The guide for one card, or null for a card that says nothing to act on or a kind without a guide. */
export function writeGuide(facts: CardFacts): Guide | null {
  const context = guideContext(facts);
  if (!context) return null;
  const shape: Shape = SHAPES[context.category] ?? "E";
  switch (shape) {
    case "A":
      return context.styleKeys.some((k) => k.includes("sparkling"))
        ? sparklingGuide(context)
        : wineGuide(context);
    case "B":
      return sakeGuide(context);
    case "C":
      return caskGuide(context);
    case "D":
      return traditionalGuide(context);
    default:
      return null;
  }
}

/** Reads the card once; null when it names nothing the guide can act on. */
function guideContext(facts: CardFacts): GuideContext | null {
  const category = facts.record.category ?? "";
  // The four traditional kinds keep the reading their guides were settled on.
  const settled = SHAPES[category] === "D";
  const next = facts.summary.next_choice;
  const record = recordLevels(facts.product_facts);
  const wants = wanted(next, record, facts.reactions, settled);
  const adjust = next.adjust.filter((a) => burden(a.subject));
  const adjusted = wants.flatMap((w) =>
    "axis" in w && (w.adjust || w.floor) ? [w] : []
  );
  // A card whose only burden is an aroma is still answered: the aroma is turned.
  const aromaTurns = settled
    ? []
    : next.adjust.filter((a) => a.subject.domain === "aroma");
  const turned = adjusted.length + aromaTurns.length;
  if (adjust.length && !turned) return null;

  const likedWords = next.keep.flatMap((s) => liked(s) ?? []);
  if (!likedWords.length && !turned) return null;

  const styleKeys = facts.product_facts.flatMap((p) =>
    p.fact.type === "style" ? [p.fact.key] : []
  );
  // What the head counts as turned: the burdens it can name, and the aromas.
  const turns = [...adjust, ...aromaTurns];
  const kindRow = terms("kind").find((t) => styleKeys.includes(t.key));
  const cueRow = kindRow ?? terms("category").find((t) => t.key === category);
  // A champagne drinker is not sent to a red sparkling.
  const colors = new Set(
    DICTIONARY_STYLES.filter((t) => styleKeys.includes(t.key)).flatMap((t) =>
      styleOf(t).colors
    ),
  );
  const cues: Cue[] =
    ((cueRow?.hints as { choice_cues?: Cue[] } | undefined)?.choice_cues ?? [])
      .filter((c) => !c.colors || c.colors.some((k) => colors.has(k)));
  const slots: Record<string, string> = {
    P: likedWords.slice(0, 2).join("{과} "),
    PP: likedWords.slice(0, 2).join("{과} "),
    PA: likedWords[0],
    PB: likedWords[1] ?? "",
    N: adjust.map((a) => burden(a.subject)!).join("{과} "),
    ND: adjust.length ? adjustedPhrase(adjust) : "",
    NB: turnedPhrase(turns),
    K: kindRow?.names?.ko ?? "술",
  };
  const shelf = category === "whisky" || category === "sake"
    ? terms("category").find((t) => t.key === category)
    : kindRow;
  return {
    facts,
    next,
    record,
    wants,
    adjust,
    turnedAromas: aromaTurns.flatMap((a) =>
      saidTurn(a) === "higher" ? [] : [a.subject.key]
    ),
    raisedAromas: aromaTurns.flatMap((a) =>
      saidTurn(a) === "higher" ? [a.subject.key] : []
    ),
    made: new Set(
      facts.product_facts.flatMap((p) =>
        p.fact.type === "production" ? [p.fact.key] : []
      ),
    ),
    skipAromas: new Set(
      next.keep.flatMap((s) => s.domain === "aroma" ? [s.key] : []),
    ),
    keptAxes: new Set(
      wants.flatMap((w) => "axis" in w && !w.adjust && !w.near ? [w.axis] : []),
    ),
    styleKeys,
    category,
    kindRow,
    kind: kindRow ? styleOf(kindRow) : null,
    cues,
    slots,
    shelfName: shelf?.names.ko ?? slots.K,
    readings: new Map(
      cues.flatMap((cue) =>
        [...cue.compare.matchAll(/'([^']+)'\(([가-힣 ·]+)\)/g)].map((
          [, word, reading],
        ) => [wordKey(word), reading] as const)
      ),
    ),
    turns,
    burdenWords: new Set(
      next.adjust.flatMap((a) => burdenWord(a, facts.reactions) ?? []),
    ),
    keptWords: new Set(
      next.keep.flatMap((s) => likedSaid(s, facts.reactions) ?? []),
    ),
    head: headOf(turns, slots),
  };
}

const headOf = (
  adjust: NextChoice["adjust"],
  slots: Record<string, string>,
) => fill(headFor(adjust, !!slots.P), slots);

/**
 * Methods the 전통주 shelf holds for 탁주, 약주 and 과실주 that no 증류식 소주
 * label names: a distilled soju is not pasteurised, macerated or fortified,
 * one from a column still is 희석식, and none sells itself as kept in steel.
 */
const NOT_ON_SOJU: ReadonlySet<string> = new Set([
  "column_distillation",
  "pasteurised",
  "maceration",
  "spirit_fortification",
  "amphora_vessel",
  "stainless_steel_vessel",
]);

/**
 * Blended on a label is a kind of whisky (Blended Scotch Whisky, Blended
 * Malt), not a way a single malt is made: a method whose label word opens
 * the label words of a kind is no cask or method to look for.
 */
function namesAKind(key: string, category: string): boolean {
  const label = labelWordsOf(key)[0];
  if (!label) return false;
  return terms("kind").some((kind) =>
    (kind.categories ?? []).includes(category) &&
    ((kind.hints as { label_words?: string[] } | undefined)?.label_words ?? [])
      .some((word) => word === label || word.startsWith(`${label} `))
  );
}

/** The other styles of the reader's kind a guide of this shape may point to. */
function candidateStyles(c: GuideContext, shape: "A" | "B" | "C"): Style[] {
  const all = pool(shape, c.category);
  const colors = new Set([
    ...all.filter((s) => c.styleKeys.includes(s.key)).flatMap((s) => s.colors),
    ...(c.kind?.colors ?? []),
  ]);
  return all
    .filter((s) => !c.styleKeys.includes(s.key))
    .filter((s) => !colors.size || s.colors.some((k) => colors.has(k)))
    .filter((s) => shape !== "A" || sameShape(s, c.styleKeys))
    .filter((s) => shape !== "B" || near(s.abv, c.kind?.abv ?? null))
    // A cask or method without aromas reads as a bare level ("묵직한 특징이 있어요").
    .filter((s) => shape !== "C" || s.aromas.length > 0)
    // A chip is a word to find on the label: 냉각여과 is printed on none.
    .filter((s) => shape !== "C" || labelWordsOf(s.key).length > 0)
    .filter((s) => shape !== "C" || !namesAKind(s.key, c.category))
    .filter((s) =>
      c.kindRow?.key !== "distilled_soju" || !NOT_ON_SOJU.has(s.key)
    );
}

/**
 * Sparkling wine: up to two regional styles with the country they come from,
 * chosen as chooseStyles chooses, else the kind's label words; and the
 * 당도·산도·탄산·바디 marks.
 */
function sparklingGuide(c: GuideContext): Guide {
  const styles = terms("regional_style")
    .filter((t) => t.key.includes("sparkling") && !c.styleKeys.includes(t.key))
    .map(styleOf);
  const options = chooseStyles(c, styles, "styles", SPARKLING_SPEC)
    .slice(0, 2);
  return guideOf(
    headOf(c.turns, { ...c.slots, K: "스파클링 와인" }),
    WINE_TIP,
    {
      picks: orTheSame(
        c,
        options.length
          ? options.map((option) =>
            pickOf({
              country: countryOfRegion(option.s.rows[0]),
              words: nameWords(option.s.rows[0]),
              labelWord: false,
              note: noteOf(c, option.why, option.counted),
            })
          )
          : cuePicks(c, chooseCues(c, c.cues, 2)),
      ),
      levels: specLevels(
        c.facts.product_facts,
        c.adjust,
        c.keptAxes,
        SPARKLING_SPEC,
        WINE_LEVEL_WORDS,
      ),
    },
  );
}

/** Still wine: the grapes that lean the asked way in felt sweetness, else the grapes that fit, else the label words. */
function wineGuide(c: GuideContext): Guide {
  const styles = candidateStyles(c, "A");
  const lean = sweetLean(c);
  const levels = leanLevels(
    c,
    lean,
    specLevels(
      c.facts.product_facts,
      c.adjust,
      c.keptAxes,
      WINE_SPEC,
      WINE_LEVEL_WORDS,
    ),
  );
  const leaning = lean ? leanPicks(c, styles, lean) : [];
  const grapes = leaning.length ? leaning : grapePicks(c, styles);
  return guideOf(c.head, WINE_TIP, {
    // No grape fits: the kind's own label words.
    picks: orTheSame(
      c,
      grapes.length ? grapes : cuePicks(c, chooseCues(c, c.cues, 2)),
    ),
    levels,
  });
}

/* ------------------------------------------------- the same thing again */

/**
 * A card of liked answers alone that the rules leave without a chip names
 * what the bottle itself is: the reader liked it, and shop staff can find the
 * same thing at once. A wine's grape (its first one the dictionary keeps a
 * label spelling for) with the place its style comes from, else its regional
 * style; a sake's grade; a fortified wine's own label word (Fino, Tawny) or
 * kind (Port). Never with a burden or a lack on the card: the same thing
 * would carry it again. A whisky has its profile and a traditional drink its
 * own-ingredient chip, so neither is given one. What the shelf hardly holds
 * is not named here either.
 */
function orTheSame(c: GuideContext, picks: GuidePick[]): GuidePick[] {
  if (picks.length) return picks;
  const liked = c.facts.reactions.some((r) => r.reaction === "liked");
  if (
    !liked || c.next.adjust.length ||
    c.facts.record.revisit === "do_not_want_again"
  ) return picks;
  const same = c.category === "sake" ? sameGrade(c) : sameWine(c);
  return same ? [same] : picks;
}

function sameGrade(c: GuideContext): GuidePick | null {
  const grade = c.kindRow;
  if (
    !grade?.names.label || !findable(shelfCount(c, "kinds", grade.key), "kinds")
  ) return null;
  return pickOf({
    words: nameWords(grade),
    labelWord: false,
    note: NOTE_SAME_GRADE,
  });
}

function sameWine(c: GuideContext): GuidePick | null {
  const own = c.styleKeys.flatMap((key) =>
    DICTIONARY_STYLES.find((t) => t.key === key) ?? []
  );
  const style = own.find((t) => t.type === "regional_style");
  const grape = own.find((t) =>
    t.type === "grape" && t.names.label &&
    findable(shelfCount(c, "grapes", t.key), "grapes")
  );
  if (grape) {
    // 보르도(Bordeaux) > 메독(Médoc): the place the bottle's own style is read from.
    const place = (style?.hints as { region_labels?: string[] } | undefined)
      ?.region_labels?.[0]?.split(" > ").pop()?.replace(/\(.*\)$/, "").trim();
    const country = style && countryOfRegion(style);
    return pickOf({
      country,
      place: place && place !== country?.name ? place : undefined,
      words: nameWords(grape),
      labelWord: false,
      note: NOTE_SAME_GRAPE,
    });
  }
  if (
    style?.names.label && findable(shelfCount(c, "styles", style.key), "styles")
  ) {
    return pickOf({
      country: countryOfRegion(style),
      words: nameWords(style),
      labelWord: false,
      note: NOTE_SAME_KIND,
    });
  }
  // A fortified wine is told apart by a word on its label: Fino, Tawny, Sercial.
  const kind = c.kindRow;
  if (!kind || !FORTIFIED.has(kind.key)) return null;
  const name = wordKey(c.facts.record.product_name);
  const word = terms("label_word").find((t) =>
    !!t.names.label &&
    (t.key.startsWith(`${kind.key.replace(/_wine$/, "")}_`) ||
      t.extra?.explained_by === `kind:${kind.key}`) &&
    [t.names.label, t.names.ko].some((spelling) =>
      name.includes(wordKey(spelling))
    )
  ) ?? (kind.names.label ? kind : undefined);
  return word
    ? pickOf({ words: nameWords(word), labelWord: true, note: NOTE_SAME_KIND })
    : null;
}

/** The kinds of wine made by fortifying, named by a word on the label and not by a grape. */
const FORTIFIED: ReadonlySet<string> = new Set([
  "port_wine",
  "sherry_wine",
  "madeira_wine",
  "fortified_wine",
  "vermouth",
]);

/* ------------------------------------------ how sweet a still wine feels */

type Lean = "sweeter" | "drier";

const isSweetness = (s: Subject) =>
  s.domain === "taste" && s.key === "sweetness";

/**
 * Which way the reader asks the sweetness of a still wine to go. 93 of 100
 * reds carry 당도 1, so the mark cannot be chosen: what moves is how sweet
 * the wine feels (facts/felt_sweetness.ts). 약해서 아쉬웠다 and a liked
 * sweetness ask for the sweeter-feeling side, 너무 강했다 and 은은해서 좋았다
 * for the drier one. Only a kind whose grapes are counted is read this way
 * (red and white); sparkling and fortified wine keep their own marks.
 */
function sweetLean(c: GuideContext): Lean | null {
  if (!grapeLeans(c.facts.record.style_key).length) return null;
  const turn = c.adjust.find((a) => isSweetness(a.subject));
  if (turn) return saidTurn(turn) === "higher" ? "sweeter" : "drier";
  const liked = c.facts.reactions.find((r) =>
    r.reaction === "liked" && isSweetness(r.subject)
  );
  if (!liked || !c.next.keep.some(isSweetness)) return null;
  return sideNamed(liked.subject, c.facts.reactions) === "low"
    ? "drier"
    : "sweeter";
}

/** The tastes that hold a wine's felt sweetness down: 타닌 and 산미 for a red, 산미 for a white. */
function sweetLevers(styleKey: string | null): string[] {
  const felt = (levels: Record<string, number>) =>
    feltSweetness({
      style_key: styleKey,
      levels: { sweetness: 1, astringency: 3, acidity: 3, ...levels },
      aroma_tags: [],
    }) ?? 0;
  return ["astringency", "acidity"].filter((axis) =>
    felt({ [axis]: 2 }) > felt({})
  );
}

/**
 * A level fewer than one bottle in ten of the kind reaches from [side] is not
 * one to look for on a shelf: 당도 2 and up among reds, 산도 2 and down.
 */
function reachable(
  c: GuideContext,
  axis: string,
  level: number,
  side: "up" | "down",
): boolean {
  const place = placeOfLevel(
    axis as PlaceDimension,
    c.facts.record.style_key,
    c.category,
    level,
  );
  if (!place) return true;
  const below = place.position - place.share / 2;
  return (side === "up" ? 1 - below : below + place.share) >= 0.1;
}

/**
 * The marks of a wine whose sweetness is to feel higher: 당도 is not raised
 * to a level the kind hardly has, and each taste that holds the felt
 * sweetness down goes one step lower where the kind has bottles there,
 * unless the reader spoke of it.
 */
function leanLevels(
  c: GuideContext,
  lean: Lean | null,
  rows: GuideLevel[],
): GuideLevel[] {
  const raised = lean === "sweeter" &&
    c.adjust.some((a) => isSweetness(a.subject));
  if (!raised) return rows;
  const label = (axis: string) => WINE_SPEC.find(([a]) => a === axis)?.[1];
  const spoken = new Set([
    ...c.adjust.flatMap((a) => axisOf(a.subject)?.axis ?? []),
    ...c.keptAxes,
  ]);
  const levers = sweetLevers(c.facts.record.style_key)
    .filter((axis) => !spoken.has(axis));
  return rows.map((row) => {
    if (row.label === label("sweetness")) {
      const own = levelOf(c.facts.product_facts, "sweetness")!;
      return reachable(c, "sweetness", row.mark, "up") ? row : {
        ...row,
        mark: own,
        range: `${own}`,
        word: WINE_LEVEL_WORDS.sweetness[own - 1],
      };
    }
    const axis = levers.find((lever) => label(lever) === row.label);
    const own = axis && levelOf(c.facts.product_facts, axis);
    if (!axis || !own || own === 1 || !reachable(c, axis, own - 1, "down")) {
      return row;
    }
    const hi = own - 1;
    const lo = hi > 1 && reachable(c, axis, hi - 1, "down") ? hi - 1 : hi;
    return {
      ...row,
      mark: hi,
      range: lo === hi ? `${hi}` : `${lo}~${hi}`,
      word: WINE_LEVEL_WORDS[axis][hi - 1],
    };
  });
}

/** What the reader said of the sweetness: a burden to turn, or the liked sweetness in their own word. */
function sweetnessSaid(c: GuideContext): Said {
  const turn = c.adjust.find((a) => isSweetness(a.subject));
  if (turn) return { word: burden(turn.subject)!, turn: saidTurn(turn) };
  const subject = c.next.keep.find(isSweetness)!;
  return { word: likedSaid(subject, c.facts.reactions)!, turn: "keep" };
}

/** 많은 편, 절반 이상, 대부분: the wording a counted share earns. */
const shareSaid = (share: number) =>
  SHARE_SAID.find(([from]) => share >= from)![1];

/**
 * The grapes whose bottles lean the asked way in felt sweetness (counted
 * from the catalog's single-variety bottles), practical first. Kept: a grape
 * LEAN_SHARE of whose bottles lean that way and more than lean the other,
 * that the dictionary does not say goes the other way, and that fits what
 * else the reader said. Then the grape the kind has most bottles of first,
 * each with the counted share as its evidence.
 */
function leanPicks(
  c: GuideContext,
  styles: readonly Style[],
  lean: Lean,
): GuidePick[] {
  const styleKey = c.facts.record.style_key;
  const leans = new Map(grapeLeans(styleKey).map((g) => [g.grape, g]));
  const levers = sweetLevers(styleKey);
  const rest = c.wants.filter((w) => "aroma" in w || w.axis !== "sweetness");
  const said = rest.filter((w) => "aroma" in w || !w.near);
  const raising = c.adjust.some((a) => isSweetness(a.subject));
  const own = c.record.sweetness ?? "low";
  const sweet = sweetnessSaid(c);
  return styles.flatMap((s): Option[] => {
    const counted = leans.get(s.key);
    if (!counted || fit(s, said) === null) return [];
    const [share, other] = lean === "sweeter"
      ? [counted.sweeter, counted.drier]
      : [counted.drier, counted.sweeter];
    if (share < LEAN_SHARE || share <= other) return [];
    const sweetness = s.levels.sweetness ?? "low";
    const against = lean === "drier"
      ? sweetness !== "low"
      // A dry grape the dictionary calls firm or sharp is no sweeter-feeling
      // pick, and a liked sweetness is not sent two bands up the scale.
      : sweetness === "low"
      ? levers.some((axis) => s.levels[axis] === "high")
      : !raising && RANK[sweetness] - RANK[own] > 1;
    if (against) return [];
    const also = answersOf(s, rest, WINE_SPEC);
    const why: Why = {
      ...also,
      turned: sweet.turn === "keep" ? also.turned : [sweet, ...also.turned],
      kept: sweet.turn === "keep" ? [sweet, ...also.kept] : also.kept,
      evidence: fill(EVIDENCE_LEAN, {
        N: count(counted.bottles),
        P: `${Math.round(share * 100)}`,
        S: LEAN_SIDE[lean],
        M: shareSaid(share),
      }),
    };
    return [{ s, key: s.key, why, counted: shelfCount(c, "grapes", s.key) }];
  })
    .filter((option) => findable(option.counted, "grapes"))
    .sort(byCommon)
    .slice(0, 2)
    .map((option) =>
      grapePick(
        option.s,
        homeRegions(option.s)[0],
        noteOf(c, option.why, option.counted),
      )
    );
}

/**
 * Sake: the sister grades in one chip, else the label words of a bottle no
 * grade fits (a grade two bands off the bottle would send a 곡물 향 drinker
 * to 긴조: the label numbers say it better); and the label bands. The chip
 * names other grades, so the head names the kind as a whole: 사케.
 */
function sakeGuide(c: GuideContext): Guide {
  const grades = chooseStyles(c, candidateStyles(c, "B"), "kinds");
  return guideOf(
    headOf(c.turns, { ...c.slots, K: "사케" }),
    SAKE_TIP,
    {
      picks: orTheSame(
        c,
        grades.length ? [gradePick(c, grades)] : cuePicks(c, sakeCues(c)),
      ),
      levels: sakeLevels(c.facts.product_facts, c.adjust),
    },
  );
}

/**
 * Whisky: the casks or methods that carry a liked aroma, then a label word
 * for each level to turn or keep, the word to pass over for an aroma to turn
 * down, and a cask or method the dictionary says moves a level no label word
 * answered. A chip is a new word to look for: the bottle's own cask or method
 * is named only for a liked aroma nothing else carries (피트 처리 맥아 after a
 * liked 스모키 향). Beside the 도수 band the drink is said in words.
 */
function caskGuide(c: GuideContext): Guide {
  const styles = candidateStyles(c, "C");
  const fresh = styles.filter((s) => !c.made.has(s.key));
  const sought = new Set([...c.skipAromas, ...c.raisedAromas]);
  // An aroma to turn down keeps one of the two places for its word.
  const passed = passOverPicks(c, 1);
  const room = 2 - passed.length;
  const found = chooseCasks(c, fresh, sought);
  const casks = (found.length ? found : chooseCasks(c, styles, sought))
    .slice(0, room);
  const abvRow = abvRowOf(c);
  // A word is said once: no cue for a cask already named, no cask for a cue's word.
  const taken = new Set(
    casks.flatMap((option) => labelWordsOf(option.key).map(wordKey)),
  );
  // The 도수 mark already says the strength: no cue about it twice.
  const cueRows = chooseCues(
    c,
    c.cues,
    room - casks.length,
    new Set(abvRow ? ["alcohol_presence"] : []),
    taken,
  );
  for (const { cue } of cueRows) {
    for (const word of meant(cue)) taken.add(wordKey(word));
  }
  const effects = effectOptions(
    c,
    fresh.filter((s) =>
      !labelWordsOf(s.key).some((word) => taken.has(wordKey(word)))
    ),
    room - casks.length - cueRows.length,
    new Set(cueRows.flatMap(({ cue }) => cue.axis ?? [])),
  );
  return guideOf(c.head, WHISKY_TIP, {
    picks: [
      ...casks.map((option) => caskPick(c, option)),
      ...cuePicks(c, cueRows),
      ...passed,
      ...effects.map((option) => caskPick(c, option)),
    ],
    levels: abvRow ? [abvRow] : [],
    profile: profileOf(c, [...casks, ...effects].map((option) => option.s)),
  });
}

/** The chip of a cask or method: its label word with its name, and where its bottles cluster. */
function caskPick(c: GuideContext, option: Option): GuidePick {
  const row = caskTermByKey.get(option.key);
  // Where its bottles cluster in our catalog: 피트 처리 맥아 -> 아일라섬.
  const region = (row?.hints as {
    bottled_regions?: { category: string; region: string }[];
  } | undefined)?.bottled_regions?.find((r) => r.category === c.category)
    ?.region;
  return pickOf({
    place: region,
    words: [termWord(option.key, c.category)],
    labelWord: false,
    note: noteOf(c, option.why, option.counted),
  });
}

/**
 * An aroma to turn down: the label word of a cask or method whose making is
 * sure to leave it (the dictionary's production-based aromas), as a word to
 * pass over. The bottle's own word goes first (its aroma came from there),
 * then the word most bottles of the shelf carry; a word the shelf hardly
 * holds is nothing to pass over, and one that also makes an aroma the reader
 * liked is not passed over.
 */
function passOverPicks(c: GuideContext, limit: number): GuidePick[] {
  const picks: GuidePick[] = [];
  const named = new Set<string>();
  for (const aroma of c.turnedAromas) {
    if (picks.length >= limit) break;
    const [row] = [...caskTermByKey.values()].flatMap((term) => {
      const made = (term.aromas ?? []).filter((a) => a.basis === "production");
      const brings = made.some((a) =>
        lineage(a.key).includes(aroma) || lineage(aroma).includes(a.key)
      );
      if (
        !brings || named.has(term.key) ||
        !(term.categories ?? []).includes(c.category) ||
        !termLabel(term.key, c.category) ||
        made.some((a) => c.skipAromas.has(a.key))
      ) return [];
      const counted = shelfCount(c, "made", term.key);
      return findable(counted)
        ? [{ key: term.key, counted, own: c.made.has(term.key) }]
        : [];
    }).sort((x, y) => Number(y.own) - Number(x.own) || byCommon(x, y));
    if (!row) continue;
    named.add(row.key);
    const word = termWord(row.key, c.category);
    picks.push(pickOf({
      words: [word],
      labelWord: true,
      keyword: fill(WITHOUT_WORD, { W: word }),
      note: fill(row.own ? NOTE_PASS_OWN : NOTE_PASS, {
        X: scent(aroma),
        N: row.counted ? count(row.counted.bottles) : "",
        T: row.counted ? count(row.counted.of) : "",
        K: c.shelfName,
      }),
    }));
  }
  return picks;
}

/** "우리 상품 354병에 기록된 수준의 중간값이에요": the bottles an aggregate row was counted from. */
function countedBottles(row: { basis?: string; reason?: string } | undefined) {
  if (row?.basis !== "aggregate") return 0;
  return Number(row.reason?.match(/(\d+)병/)?.[1] ?? 0);
}

/**
 * The levels a cask or method is named for by its dictionary taste row, and
 * the sides it may be named on. 알코올 열감 only on the softer side: a
 * stronger drink is the 도수 mark's to say.
 */
const EFFECT_SIDES: Readonly<Record<string, readonly Band[]>> = {
  sweetness: ["high", "low"],
  body: ["high", "low"],
  alcohol_presence: ["low"],
  finish_length: ["high", "low"],
};

/**
 * A cask or method for each level the reader asked to turn or keep on a side
 * and no label word answered, practical first. Kept: one whose dictionary
 * taste row sits on that side (a cask of long 여운 for a finish too short),
 * that pushes no other answer the other way and brings no aroma to turn
 * down; a row counted from our bottles must say how many; of those, the ones
 * that leave the bottle's unmentioned levels alone when there are any.
 * Dropped: the ones the shelf hardly holds. Then the most common first.
 */
function effectOptions(
  c: GuideContext,
  styles: readonly Style[],
  limit: number,
  answered: ReadonlySet<string>,
): Option[] {
  const asks = levelAsks(c);
  const side = (ask: Ask): Band => ask.direction === "higher" ? "high" : "low";
  const otherSide = (ask: Ask): Band =>
    ask.direction === "higher" ? "low" : "high";
  const options: Option[] = [];
  for (const ask of asks) {
    if (options.length >= limit) break;
    const axis = ask.axis!;
    if (answered.has(axis) || !EFFECT_SIDES[axis]?.includes(side(ask))) {
      continue;
    }
    const open = styles
      .filter((s) =>
        !options.some((o) => o.key === s.key) &&
        bandFor(s, axis) === side(ask) &&
        asks.every((other) =>
          other === ask || bandFor(s, other.axis!) !== otherSide(other)
        ) &&
        !c.turnedAromas.some((aroma) => carries(s, aroma))
      )
      .map((s) => ({
        s,
        key: s.key,
        row: tasteRow(s, axis),
        alike: alikeTo(s, c.wants),
        counted: shelfCount(c, "made", s.key),
      }))
      .filter((x) =>
        (x.row?.basis !== "aggregate" || countedBottles(x.row) > 0) &&
        findable(x.counted) && !bareRoot(c, x.s, styles)
      );
    const alike = open.filter((x) => x.alike);
    const [best] = (alike.length ? alike : open).sort(byCommon);
    if (!best) continue;
    const liked = [...c.skipAromas].filter((l) => best.s.aromas.includes(l))
      .map((l): Said => ({ word: scent(l), turn: "keep" }));
    const said = ask.said ? [ask.said] : [];
    options.push({
      s: best.s,
      key: best.key,
      counted: best.counted,
      why: {
        turned: ask.turn ? said : [],
        kept: [...(ask.turn ? [] : said), ...liked],
        alike: best.alike,
        evidence: evidenceOf(best.row),
      },
    });
  }
  return options;
}

/**
 * A whisky said in words, as a shop's card says one: what the reader liked
 * (aromas under AROMA, tastes and mouthfeel under FLAVOR, the finish under
 * FINISH), what the chosen casks are made to or usually do bring by the
 * dictionary's aroma rows, and a burden as its absence or its turn. Nothing is made up: a line with nothing
 * to say is left out, and with no line there is no profile.
 */
function profileOf(
  c: GuideContext,
  chosen: readonly Style[],
): ProfileLine[] | null {
  const aroma: string[] = [];
  const flavor: string[] = [];
  const finish: string[] = [];
  // Every liked answer, the ones the summary keeps first.
  const turning = (s: Subject) =>
    c.next.adjust.some((a) =>
      a.subject.domain === s.domain && a.subject.key === s.key
    );
  const likedOnes = [
    ...c.next.keep,
    ...c.facts.reactions.map((r) => r.subject),
  ].filter((s, i, all) =>
    !turning(s) &&
    all.findIndex((x) => x.domain === s.domain && x.key === s.key) === i &&
    c.facts.reactions.some((r) =>
      r.reaction === "liked" && r.subject.domain === s.domain &&
      r.subject.key === s.key
    )
  );
  for (
    const key of [
      ...likedOnes.flatMap((s) => s.domain === "aroma" ? [s.key] : []),
      ...c.raisedAromas,
    ]
  ) {
    const name = AROMA_NAMES.get(key);
    if (name) aroma.push(name);
  }
  for (const style of chosen) {
    // Only what the cask is made to or usually does bring: a collected note is not promised.
    const brought = (style.rows[0].aromas ?? []).filter((a) =>
      AROMA_NAMES.has(a.key) && SURE_BASIS.has(a.basis ?? "")
    );
    const first = brought.find((a) => a.basis === "production") ?? brought[0];
    if (first) aroma.push(AROMA_NAMES.get(first.key)!);
  }
  for (const key of c.turnedAromas) {
    const name = AROMA_NAMES.get(key);
    if (name) aroma.push(fill(PROFILE_WITHOUT, { X: name }));
  }
  for (const subject of likedOnes) {
    if (subject.domain === "aroma") continue;
    const word = likedSaid(subject, c.facts.reactions);
    if (word) (subject.domain === "finish" ? finish : flavor).push(word);
  }
  for (const a of c.next.adjust) {
    if (a.subject.domain === "aroma") continue;
    const key = `${a.subject.domain}.${a.subject.key}`;
    const residue = isResidue(a, c.facts.reactions);
    const word = residue ? RESIDUE : PROFILE_BURDENED[key] ?? burden(a.subject);
    if (!word) continue;
    const lingering = a.direction === "shorter";
    const text = a.direction === "higher"
      ? PROFILE_MORE
      : residue || key === "finish.off_flavor"
      ? PROFILE_WITHOUT
      : lingering
      ? PROFILE_NOT_LINGERING
      : PROFILE_LESS;
    (a.subject.domain === "finish" || lingering ? finish : flavor).push(
      fill(text, { X: word }),
    );
  }
  const lines = ([
    [PROFILE_LABELS.aroma, aroma],
    [PROFILE_LABELS.flavor, flavor],
    [PROFILE_LABELS.finish, finish],
  ] as const).flatMap(([label, words]) =>
    words.length ? [{ label, words: [...new Set(words)].slice(0, 5) }] : []
  );
  return lines.length ? lines : null;
}

/**
 * Traditional drinks: the words printed on the label that answer what the
 * reader said, then the marks. A 증류식 소주 also names a cask or method that
 * carries a liked aroma, as a whisky does, and shows 단맛·바디 beside its 도수.
 */
function traditionalGuide(c: GuideContext): Guide {
  const soju = c.kindRow?.key === "distilled_soju";
  const asks = labelAsks(c);
  const taken: string[] = [];
  const take = (found: Answered[]) => {
    taken.push(...found.flatMap(({ cue }) => shownWords(cue)));
    return found;
  };
  // A burden's own word first: the cask of a liked aroma does not crowd it out.
  const turns = take(chooseLabels(c, asks.filter((a) => a.turn), 2, taken));
  const casks = soju ? sojuCasks(c, 2 - turns.length, taken) : [];
  taken.push(...casks.flatMap((o) => [o.s.name, ...labelWordsOf(o.key)]));
  const free = () => 2 - turns.length - casks.length;
  const keeps = take(
    chooseLabels(c, asks.filter((a) => !a.turn), free(), taken),
  );
  // A second word for an answer fills a place still free.
  const more = take(chooseLabels(c, asks, free() - keeps.length, taken));
  const picks = [
    ...cuePicks(c, turns, asks),
    ...casks.map((option) => caskPick(c, option)),
    ...cuePicks(c, [...keeps, ...more], asks),
  ];
  if (picks.length < 2) {
    const own = ownIngredientPick(c, taken);
    if (own) picks.push(own);
  }
  const abvRow = abvLevel(
    c.facts,
    c.adjust,
    c.keptAxes,
    c.kind?.abv?.[0] ?? null,
    true,
  );
  const levels = [
    ...specLevels(
      c.facts.product_facts,
      c.adjust,
      c.keptAxes,
      soju ? SOJU_SPEC : TRADITIONAL_SPEC,
      TRADITIONAL_LEVEL_WORDS,
      (axis) =>
        sideNamed(
          { domain: "taste", key: axis } as Subject,
          c.facts.reactions,
        ),
    ),
    ...(abvRow ? [abvRow] : []),
  ];
  return guideOf(c.head, TRADITIONAL_TIP, { picks, levels });
}

/** A whisky label always prints the 도수; the mark says which band to look for. */
const abvRowOf = (c: GuideContext) =>
  abvLevel(c.facts, c.adjust, c.keptAxes, c.kind?.abv?.[0] ?? null);

/**
 * The casks and methods of a 증류식 소주 that carry a liked aroma, without
 * one the words already chosen rule out ('감압증류' was said: not 상압 증류)
 * or one that undoes an answer.
 */
function sojuCasks(
  c: GuideContext,
  limit: number,
  taken: readonly string[],
): Option[] {
  if (limit <= 0) return [];
  const asks = labelAsks(c);
  const used = new Set(taken.map(spaceless));
  const wordsOf = (s: Style) => [s.name, ...labelWordsOf(s.key)];
  const open = candidateStyles(c, "C").filter((s) =>
    !rivals(wordsOf(s), used, eitherOr(c)) && !undoes(wordsOf(s), c, asks)
  );
  const [first, second] = chooseCasks(c, open, c.skipAromas);
  if (!first) return [];
  for (const word of wordsOf(first.s)) used.add(spaceless(word));
  return second && limit > 1 && !rivals(wordsOf(second.s), used, eitherOr(c))
    ? [first, second]
    : [first];
}

/* ------------------------------------------------- the label's own words */

/** One thing the reader said that a label word, a cask or a method may answer. */
type Ask = {
  axis?: string;
  aroma?: string;
  direction: "lower" | "higher";
  /** A burden to turn, not a liked thing to keep. */
  turn: boolean;
  /** The reader's own word for it; null where they have none. */
  said: Said | null;
  /**
   * The way the answer itself points, whatever level the bottle sits on: a
   * liked 단맛 asks for the sweeter of two bottles unless it was liked for
   * being 은은한, which points neither way (null). Absent where it is
   * [direction].
   */
  toward?: "lower" | "higher" | null;
};

/** A label cue and what the reader said that it answers. */
type Answered = { cue: Cue; ask: Ask };

/** An aroma and what it is a kind of: 청사과, 사과, 과수 과일, 신선한 과일. */
function lineage(aroma: string): string[] {
  const up = AROMA_FAMILY.get(aroma);
  return up ? [aroma, ...lineage(up)] : [aroma];
}

/** 입안에 텁텁하게 남음, said of the finish alone: not the weight while drinking. */
function isResidue(a: Adjust, reactions: readonly ReactionFact[]): boolean {
  return a.subject.domain === "mouthfeel" && a.subject.key === "heavy" &&
    a.direction === "shorter" &&
    !reactions.some((r) =>
      r.phase === "drinking" && r.reaction === "burden" &&
      r.subject.domain === "mouthfeel" && r.subject.key === "heavy"
    );
}

/**
 * The side the reader named with their reason: 또렷해서·충분히 달아서 is the
 * high one, 은은해서 the low one, whatever level the catalog gives the bottle.
 */
function sideNamed(
  subject: Subject,
  reactions: readonly ReactionFact[],
): Band | null {
  const reason = reactions.find((r) =>
    r.reaction === "liked" && r.subject.domain === subject.domain &&
    r.subject.key === subject.key && r.qualifier
  )?.qualifier;
  return reason === "pronounced" ? "high" : reason === "gentle" ? "low" : null;
}

/** The level a label word speaks of: 목넘김 has words on a label and no mark. */
const labelAxis = (s: Subject) =>
  s.domain === "mouthfeel" && s.key === "smooth"
    ? "smoothness"
    : axisOf(s)?.axis;

/** A burden in the reader's word, or null for one they have no word for. */
function burdenSaid(a: Adjust, c: GuideContext): Said | null {
  const word = burdenWord(a, c.facts.reactions);
  return word ? { word, turn: saidTurn(a) } : null;
}

/**
 * A burden in the word of the reader's own answer, never the name of the
 * level it moves: 뒤가 텁텁했다 is 텁텁함, though what answers it is a lighter
 * 바디; an aroma is its own name.
 */
function burdenWord(
  a: Adjust,
  reactions: readonly ReactionFact[],
): string | null {
  if (a.subject.domain === "aroma") return scent(a.subject.key);
  return isResidue(a, reactions) ? RESIDUE : burden(a.subject);
}

function keptSaid(subject: Subject, c: GuideContext): Said | null {
  const word = likedSaid(subject, c.facts.reactions);
  return word ? { word, turn: "keep" } : null;
}

/** What the card asks a label for: the burdens first, then what was liked. */
function labelAsks(c: GuideContext): Ask[] {
  const asks: Ask[] = [];
  const add = (ask: Ask) => {
    const same = (x: Ask) => x.axis === ask.axis && x.aroma === ask.aroma;
    if (!asks.some(same)) asks.push(ask);
  };
  for (const a of c.next.adjust) {
    if (a.subject.domain === "aroma") {
      add({
        aroma: a.subject.key,
        direction: saidTurn(a),
        turn: true,
        said: burdenSaid(a, c),
      });
      continue;
    }
    const axis = labelAxis(a.subject);
    if (axis && !isResidue(a, c.facts.reactions)) {
      add({ axis, direction: axisTurn(a), turn: true, said: burdenSaid(a, c) });
    }
    // 묵직함 that stayed after swallowing is 텁텁함, with label words of its own.
    if (
      a.subject.domain === "mouthfeel" && a.subject.key === "heavy" &&
      a.direction === "shorter"
    ) {
      add({
        axis: "residue",
        direction: "lower",
        turn: true,
        said: burdenSaid(a, c),
      });
    }
  }
  for (const s of c.next.keep) {
    const said = keptSaid(s, c);
    if (s.domain === "aroma") {
      add({ aroma: s.key, direction: "higher", turn: false, said });
      continue;
    }
    const key = `${s.domain}.${s.key}`;
    if (key === "mouthfeel.smooth" || key === "finish.persistence") {
      add({ axis: labelAxis(s)!, direction: "higher", turn: false, said });
      continue;
    }
    const target = axisOf(s);
    if (!target) continue;
    const reason = sideNamed(s, c.facts.reactions);
    const band = reason ?? target.band ?? c.record[target.axis];
    const side = band && direction(band);
    if (side) {
      add({
        axis: target.axis,
        direction: side,
        turn: false,
        said,
        // 은은해서 좋았다 points neither way: less of what was liked is not more of it.
        toward: target.band ? side : reason === "low" ? null : "higher",
      });
    }
  }
  return asks;
}

/** The words a chip shows in quotes: 감압증류, 오크 숙성. */
const quoted = (text: string) =>
  (text.match(/'[^']+'/g) ?? []).map((word) => word.slice(1, -1));
const shownWords = (cue: Cue) => quoted(labelWords(cue));
/** What those words stand for; two cues that share one speak of the same thing. */
const meant = (cue: Cue) => cue.words ?? shownWords(cue);
const spaceless = (word: string) => word.replace(/\s+/g, "");

/**
 * One label word for each of [answer], up to [limit]. A word must be printed
 * on the label (a number is the marks' job), must not undo anything else the
 * reader said (a 탄산 lover is not sent to '살균탁주' for its sweetness), is
 * never what the bottle already is when something is to change, is said once,
 * never beside a word no bottle carries with it ('상압증류' after
 * '감압증류'), and never an ingredient the kind's shelf hardly holds. A
 * 전통주 label word has no catalog column to be counted in, so the
 * better-sourced sentence goes first.
 */
function chooseLabels(
  c: GuideContext,
  answer: readonly Ask[],
  limit: number,
  taken: readonly string[],
): Answered[] {
  if (limit <= 0) return [];
  const asks = labelAsks(c);
  const cues = [...c.cues].sort((x, y) => (x.grade ?? 9) - (y.grade ?? 9));
  const own = ownWords(c);
  const used = new Set(taken.map(spaceless));
  const chosen: Answered[] = [];
  const fits = (cue: Cue, ask: Ask) =>
    answers(cue, ask) && shownWords(cue).length > 0 &&
    !undoes(meant(cue), c, asks) &&
    !(ask.turn && meant(cue).some((word) => own.has(spaceless(word)))) &&
    !shownWords(cue).some((word) => used.has(spaceless(word))) &&
    !rivals(shownWords(cue), used, eitherOr(c)) && cueFindable(c, cue);
  for (const ask of answer) {
    if (chosen.length >= limit) break;
    const cue = cues.find((x) => fits(x, ask));
    if (!cue) continue;
    chosen.push({ cue, ask });
    for (const word of shownWords(cue)) used.add(spaceless(word));
  }
  return chosen;
}

const answers = (cue: Cue, ask: Ask) =>
  cue.direction === ask.direction && speaksOf(cue, ask);

const speaksOf = (cue: Cue, ask: Ask) =>
  ask.aroma
    ? !!cue.aroma && lineage(ask.aroma).includes(cue.aroma)
    : cue.axis === ask.axis;

/** 묵직함 and 텁텁함 are one weight: a heavier bottle leaves more behind. */
const WEIGHT: ReadonlySet<string> = new Set(["body", "residue"]);
const touches = (cue: Cue, ask: Ask) =>
  speaksOf(cue, ask) ||
  (!!cue.axis && !!ask.axis && WEIGHT.has(cue.axis) && WEIGHT.has(ask.axis));

/**
 * Do these words, by any sentence the kind holds, push something the reader
 * said the other way? A sentence about the words themselves does when it
 * turns an answer around; one about their compared other side ('감압증류'
 * is said to leave less 잡내 than '상압증류') does when it is what the
 * reader asked for.
 */
function undoes(
  words: readonly string[],
  c: GuideContext,
  asks: readonly Ask[],
): boolean {
  const mine = new Set(words.map(spaceless));
  const compared = eitherOr(c).filter((pair) => pair.compared);
  return c.cues.some((other) => {
    const theirs = new Set(meant(other).map(spaceless));
    const same = [...theirs].some((word) => mine.has(word));
    const across = !same && rivals(words, theirs, compared);
    if (!same && !across) return false;
    return asks.some((ask) =>
      touches(other, ask) && (other.direction === ask.direction) === across
    );
  });
}

/**
 * Label words no one bottle carries together. [compared]: every sentence
 * about one side is said against the other, as with 상압증류 and 감압증류.
 */
type EitherOr = { words: string[]; compared?: boolean };
const eitherOr = (c: GuideContext) =>
  (c.kindRow?.hints as { either_or?: EitherOr[] } | undefined)?.either_or ?? [];

/** Is one of [words] the other side of a word already [used]? */
function rivals(
  words: readonly string[],
  used: ReadonlySet<string>,
  pairs: readonly EitherOr[],
): boolean {
  const mine = new Set(words.map(spaceless));
  return pairs.some((pair) => {
    const sides = pair.words.map(spaceless);
    return sides.some((side) => mine.has(side)) &&
      sides.some((side) => !mine.has(side) && used.has(side));
  });
}

const ingredientCuesOf = (c: GuideContext) =>
  (c.kindRow?.hints as { ingredient_cues?: IngredientCue[] } | undefined)
    ?.ingredient_cues ?? [];

/** What the bottle's own label already says: its 쌀 or 보리, its 감압 증류. */
function ownWords(c: GuideContext): Set<string> {
  const rows = ingredientCuesOf(c);
  return new Set(
    c.facts.product_facts.flatMap((p) => {
      const fact = p.fact;
      if (fact.type === "ingredient") {
        return rows.filter((r) => r.ingredient === fact.key).flatMap((r) =>
          quoted(r.label)
        );
      }
      return fact.type === "production" ? labelWordsOf(fact.key) : [];
    }).map(spaceless),
  );
}

/**
 * 이번 술과 같은 원료: the ingredient the bottle was made from, when the
 * reader liked something in it, the ingredient tells bottles of the kind
 * apart (보리 among 소주, never 쌀) and the kind's shelf holds enough of it.
 * Left out when it would undo an answer.
 */
function ownIngredientPick(
  c: GuideContext,
  taken: readonly string[],
): GuidePick | null {
  if (!c.next.keep.length || c.facts.record.revisit === "do_not_want_again") {
    return null;
  }
  const asks = labelAsks(c);
  const used = new Set(taken.map(spaceless));
  for (const p of c.facts.product_facts) {
    if (p.fact.type !== "ingredient") continue;
    const key = p.fact.key;
    const row = ingredientCuesOf(c).find((r) => r.ingredient === key && r.text);
    if (!row) continue;
    const words = quoted(row.label);
    if (words.some((word) => used.has(spaceless(word)))) continue;
    if (undoes(words, c, asks)) continue;
    if (!findable(shelfCount(c, "ingredients", key))) continue;
    return pickOf({ words, labelWord: true, note: NOTE_SAME_INGREDIENT });
  }
  return null;
}

/**
 * The levels the card asks for: each burden turned the way its word says
 * (가벼움 down is 바디 up), then each liked level that sits on a side. The
 * side is the reader's own word when they gave one (또렷해서, 은은해서), else
 * the bottle's level.
 */
function levelAsks(c: GuideContext): Ask[] {
  const asks: Ask[] = [];
  for (const a of c.adjust) {
    const axis = axisOf(a.subject)?.axis;
    if (axis) {
      asks.push({
        axis,
        direction: axisTurn(a),
        turn: true,
        said: burdenSaid(a, c),
      });
    }
  }
  for (const s of c.next.keep) {
    const target = axisOf(s);
    const band = target &&
      (sideNamed(s, c.facts.reactions) ?? target.band ??
        c.record[target.axis]);
    const dir = band && direction(band);
    if (target && dir && !asks.some((x) => x.axis === target.axis)) {
      asks.push({
        axis: target.axis,
        direction: dir,
        turn: false,
        said: keptSaid(s, c),
      });
    }
  }
  return asks;
}

/** Label words compare without case, spaces, hyphens or accents: 'Non-chill filtered' is "Non Chill Filtered". */
function wordKey(word: string): string {
  return word.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[\s\-]/g, "");
}

/** The words the bottle's own label carries: its casks and methods, its grapes and styles. */
function bottleWords(c: GuideContext): Set<string> {
  return new Set(
    [
      ...[...c.made].flatMap(labelWordsOf),
      ...DICTIONARY_STYLES.filter((t) => c.styleKeys.includes(t.key)).flatMap((
        t,
      ) => [
        t.names.ko,
        t.names.en ?? "",
        ...(t.names.label?.split("·") ?? []),
      ]),
    ].filter(Boolean).map(wordKey),
  );
}

/**
 * Categories whose bottles carry the casks and methods their labels print,
 * so a quoted label word that names one can be counted. A 전통주 row carries
 * how its kind is made (병행복발효, 단식 증류) and not what its label says
 * (no bottle carries 감압 증류), and a wine's label words (dry, Saignée) have
 * no column at all.
 */
const CUES_COUNTED: ReadonlySet<string> = new Set(["whisky", "sake"]);

/**
 * The catalog count behind one quoted label word: an ingredient the kind
 * names on its labels, a cask or method, or a grape. Null for a word the
 * catalog has no column for, which cannot be counted.
 */
function wordCount(
  c: GuideContext,
  word: string,
): { counted: Counted; what: Carried } | null {
  const of = (what: Carried, key: string | undefined) => {
    const counted = key ? shelfCount(c, what, key) : null;
    return counted ? { counted, what } : null;
  };
  const ingredient = ingredientCuesOf(c).find((row) =>
    quoted(row.label).some((w) => spaceless(w) === spaceless(word))
  );
  if (ingredient) return of("ingredients", ingredient.ingredient);
  if (CUES_COUNTED.has(c.category)) {
    // By the word shown, or by the spelling the label prints for it: 타루자케 is 樽酒.
    const label = NAMED_WORDS.get(wordKey(word))?.label;
    const term = MADE_WORDS.get(wordKey(word)) ??
      (label ? MADE_WORDS.get(wordKey(label)) : undefined);
    const made = of("made", term?.key);
    if (made) return made;
  }
  return c.category === "wine"
    ? of("grapes", GRAPE_WORDS.get(wordKey(word)))
    : null;
}

/** A cue is dropped only when the catalog counts every word of it and counts each too rare. */
function cueFindable(c: GuideContext, cue: Cue): boolean {
  return cueWords(cue).some((word) => {
    const found = wordCount(c, word);
    return !found || findable(found.counted, found.what);
  });
}

/**
 * The cues in the dictionary's order, with the ones the catalog can count
 * trading places among themselves so the more common goes first. A cue that
 * cannot be counted stays where it was.
 */
function commonFirst(c: GuideContext, cues: readonly Cue[]): Cue[] {
  const bottles = (cue: Cue) =>
    Math.max(
      -1,
      ...cueWords(cue).map((word) => wordCount(c, word)?.counted.bottles ?? -1),
    );
  const counted = cues.filter((cue) => bottles(cue) >= 0)
    .sort((x, y) => bottles(y) - bottles(x));
  return cues.map((cue) => bottles(cue) >= 0 ? counted.shift()! : cue);
}

/**
 * The label cues that answer the card: the burdens first, never a cue that
 * undoes one, then the liked levels that sit high or low. At most [limit], no
 * two with the same label words, none on an axis in [skipAxes], none that
 * names a word the bottle already carries (a sherry-cask whisky is not told
 * to look for Sherry Cask) or a word in [taken], and none the catalog counts
 * as too rare (Triple Distilled is on no whisky of ours).
 */
function chooseCues(
  c: GuideContext,
  cues: readonly Cue[],
  limit: number,
  skipAxes: ReadonlySet<string> = new Set(),
  taken: ReadonlySet<string> = new Set(),
): Answered[] {
  const asks = levelAsks(c);
  const own = bottleWords(c);
  // The same words by another sentence of the kind push a burden the other way.
  const undoes = (cue: Cue) => {
    const mine = new Set(cueWords(cue).map(wordKey));
    return cues.some((o) =>
      cueWords(o).some((word) => mine.has(wordKey(word))) &&
      asks.some((x) =>
        x.turn && x.axis === o.axis && x.direction !== o.direction
      )
    );
  };
  const chosen: Answered[] = [];
  for (const ask of asks) {
    if (chosen.length >= limit) break;
    if (skipAxes.has(ask.axis!)) continue;
    const [cue] = commonFirst(
      c,
      cues.filter((x) =>
        x.axis === ask.axis && x.direction === ask.direction && !undoes(x) &&
        !meant(x).some((word) =>
          own.has(wordKey(word)) || taken.has(wordKey(word))
        ) &&
        !chosen.some((o) => labelWords(o.cue) === labelWords(x)) &&
        cueFindable(c, x)
      ),
    );
    if (cue) chosen.push({ cue, ask });
  }
  return chosen;
}

/**
 * A sake's label words for a bottle no grade fits: the aromas the reader
 * liked or wants turned first (山廃 for 유산 발효 향, 쿄카이 1801호 for 사과
 * 향, an aroma of the same family counting), then the levels. The label
 * numbers (일본주도, 산도) are left to the marks, which already show them.
 */
function sakeCues(c: GuideContext): Answered[] {
  const { next, cues } = c;
  // 청사과 asks for the 사과 cue: one aroma within the other's line, or siblings.
  const kin = (a: string, b: string) =>
    lineage(a).includes(b) || lineage(b).includes(a) ||
    (!!AROMA_FAMILY.get(a) && AROMA_FAMILY.get(a) === AROMA_FAMILY.get(b));
  const asks: Ask[] = [
    ...next.adjust.flatMap((a): Ask[] =>
      a.subject.domain === "aroma"
        ? [{
          aroma: a.subject.key,
          direction: saidTurn(a),
          turn: true,
          said: burdenSaid(a, c),
        }]
        : []
    ),
    ...next.keep.flatMap((s): Ask[] =>
      s.domain === "aroma"
        ? [{
          aroma: s.key,
          direction: "higher",
          turn: false,
          said: keptSaid(s, c),
        }]
        : []
    ),
  ];
  const chosen: Answered[] = [];
  for (const ask of asks) {
    const cue = cues.find((x) =>
      x.aroma && x.direction === ask.direction && kin(x.aroma, ask.aroma!) &&
      !chosen.some((o) => o.cue === x) && cueFindable(c, x)
    );
    if (cue && chosen.length < 2) chosen.push({ cue, ask });
  }
  const words = cues.filter((x) => x.axis && !x.cue.includes("숫자"));
  for (const found of chooseCues(c, words, 2 - chosen.length)) {
    if (!chosen.some((o) => labelWords(o.cue) === labelWords(found.cue))) {
      chosen.push(found);
    }
  }
  return chosen;
}

/**
 * Which bottle a word is meant on, where the kind's cues tell two apart by
 * more than the word: 생막걸리 fresh from the brewery or kept for weeks. The
 * reader's answers decide: each thing they said points one way (a liked 단맛
 * to the sweeter bottle, a liked 산미 to the sourer), and the kind's sentence
 * about the word for that way names the bottle. Answers that point to both,
 * or to neither, leave it unsaid.
 */
function whichOf(
  c: GuideContext,
  cue: Cue,
  asks: readonly Ask[],
): string[] {
  const told = new Map<string, Set<string>>();
  for (const word of cueWords(cue)) {
    for (const ask of asks) {
      for (const sentence of c.cues) {
        const way = ask.toward === undefined ? ask.direction : ask.toward;
        if (!speaksOf(sentence, ask) || sentence.direction !== way) continue;
        for (const meaning of sentence.words ?? []) {
          if (meaning === word || !meaning.endsWith(word)) continue;
          const which = meaning.slice(0, -word.length).trim();
          told.set(word, (told.get(word) ?? new Set()).add(which));
        }
      }
    }
  }
  return [...told].flatMap(([word, which]) =>
    which.size === 1 ? [fill(NOTE_WHICH, { W: word, Q: [...which][0] })] : []
  );
}

/**
 * The reason under a cue's chip: what the reader said that it answers, and
 * whatever else they said that the kind's sentences about the same words
 * answer too. A label word has no levels to compare with the bottle's, so it
 * never claims the rest is alike.
 */
function cueNote(
  c: GuideContext,
  { cue, ask }: Answered,
  asks: readonly Ask[],
): string | null {
  const mine = new Set(meant(cue).map(spaceless));
  const same = c.cues.filter((other) =>
    meant(other).some((word) => mine.has(spaceless(word)))
  );
  const also = asks.filter((other) =>
    (other.axis !== ask.axis || other.aroma !== ask.aroma) &&
    same.some((sentence) => answers(sentence, other))
  );
  const said = [ask, ...also].flatMap((a) => a.said ?? []);
  // A liked aroma the word brings only a neighbour of is not said to carry on.
  const brought = !ask.turn && ask.aroma && cue.aroma &&
      !lineage(ask.aroma).includes(cue.aroma) && AROMA_NAMES.has(cue.aroma)
    ? { liked: scent(ask.aroma), brought: scent(cue.aroma) }
    : null;
  const kept = said.filter((s) => s.turn === "keep")
    .filter((s) => !brought || s.word !== ask.said?.word);
  const counted =
    cueWords(cue).flatMap((word) => wordCount(c, word)?.counted ?? [])[0] ??
      null;
  const reason = noteOf(c, {
    turned: said.filter((s) => s.turn !== "keep"),
    kept,
    kin: brought,
    alike: false,
    evidence: null,
  }, counted);
  return [reason, ...whichOf(c, cue, asks)].filter(Boolean).join(" ") || null;
}

/** The cue chips: the label words as printed with their reading, and under them why they are picked. */
function cuePicks(
  c: GuideContext,
  answered: readonly Answered[],
  asks: readonly Ask[] = levelAsks(c),
): GuidePick[] {
  return answered.map((found) =>
    pickOf({
      words: cueWords(found.cue).map((word) => labelWord(word, c)),
      labelWord: true,
      note: cueNote(c, found, asks),
    })
  );
}
