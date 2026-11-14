/**
 * 다음 술은 이렇게 골라보세요: the guide inside the 한입 summary. It names
 * what to look for on a label or menu, by kind of drink:
 *   A wine: country and grape pairs and the 당도·산도·타닌·바디 marks;
 *     sparkling wine: country and style pairs and the 당도·산도·탄산·바디 marks;
 *     with no grape or style that fits (a rosé), the kind's label cues
 *     ('Saignée', 'dry' 표기) and the marks. The sweetness of a red or a
 *     white is steered by how sweet the wine feels: grapes by the counted
 *     lean of their bottles with the reason, 타닌 and 산도 a step down, and
 *     no 당도 mark the kind hardly has
 *   B sake: sister grades of a similar strength in one chip, with the liked
 *     aromas they share, and the 당도(주도)·산미(산도) bands; a bottle unlike
 *     every grade gets the bands alone, which are the label's own numbers
 *   C whisky: casks and methods sharing an aroma with the reader, filled up
 *     to two chips with the kind's label cues, the label word to pass over
 *     for an aroma to turn down, and a cask or method whose dictionary taste
 *     row moves a level no cue answered; the 도수 band, and the directions.
 *     A chip is a new word, never the bottle's own cask as the way to change
 *   D Korean traditional drinks (탁주, 약주, 과실주, 증류식 소주): the words
 *     printed on the label that answer what the reader said ('생막걸리',
 *     '감압증류', 원재료명 '보리'), each with what it brings and why, and the
 *     marks the shops' own taste graphs use; a burden's word goes first,
 *     and a 증류식 소주 then names a cask or method that shares a liked
 *     aroma. The reader's own reason (또렷해서, 은은해서) names the side
 *     before the bottle's level does, the 도수 is read from the bottle's own
 *     number, and a 탁주 drinker is not sent to 과실주, so no other kind
 *     fills in
 *   E everything else: no guide
 * A guide has two chips when the dictionary holds two that fit, and one is
 * fine. The marks come from the bottle's own levels; the directions from what
 * the reader liked and wants changed (an aroma to turn down or up included).
 * A reader who liked nothing still gets one, aimed by the burdens alone, an
 * aroma alone included. Outside D the reader's own word for a strength
 * (또렷해서, 은은해서, 너무 강해서, 약해서, 가벼워서) outranks the catalog number.
 * Which head a card gets is fixed by the card.
 */
import { abvBandsFor } from "../facts/abv_levels.ts";
import { feltSweetness } from "../facts/felt_sweetness.ts";
import {
  familiesOfAroma,
  familiesOfBottle,
  grapeLeans,
  type PlaceDimension,
  placeOfLevel,
} from "../facts/kind_place.ts";
import { isBalanced } from "../writing/balanced.ts";
import { regionByKey, terms } from "../dictionary/dictionary.ts";
import { josa } from "../writing/korean.ts";
import {
  ACIDITY_BANDS,
  BURDENED,
  CASK_TIP,
  DRIER_BY,
  EFFECT_COUNTED,
  EFFECT_SAID,
  GYEOL,
  HEAD_BALANCED,
  HEAD_BURDEN,
  HEAD_ONLY_BURDEN,
  HEAD_POSITIVE,
  LABEL_TIP,
  LEAN_TASTES,
  LIKED,
  RESIDUE,
  SAKE_TIP,
  SAME_INGREDIENT,
  SMV_BANDS,
  SOJU_SPEC,
  SPARKLING_SPEC,
  SWEETER_BY,
  TRADITIONAL_SPEC,
  WINE_SPEC,
  WINE_TIP,
  WITHOUT_WORD,
  WORD_BRINGS,
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
  TasteCardGuideDirection,
  TasteCardGuideLevel,
  TasteCardGuidePick,
} from "../service/types.ts";

type Guide = TasteCardGuide;
type GuidePick = TasteCardGuidePick;
type GuideLevel = TasteCardGuideLevel;
type GuideDirection = TasteCardGuideDirection;

/** A guide with the parts given; the rest empty. */
function guideOf(head: string, parts: Partial<Omit<Guide, "head">>): Guide {
  return { head, picks: [], tip: null, levels: [], directions: [], ...parts };
}

/**
 * A guide of label words and marks only, for a kind with no grape, grade or
 * regional style that fits; null when it would say nothing but the head.
 */
function labelGuide(
  head: string,
  picks: GuidePick[],
  levels: GuideLevel[],
  directions: GuideDirection[],
  tip: string,
): Guide | null {
  if (!picks.length && !directions.length) return null;
  return guideOf(head, {
    picks,
    tip: picks.length || levels.length ? tip : null,
    levels,
    directions,
  });
}

/** Every row a bottle's style keys can name: its kind, grapes and styles. */
const DICTIONARY_STYLES = terms("kind", "grape", "regional_style");

function pickOf(
  country: { country: string; name: string } | undefined,
  place: string | undefined,
  keyword: string,
  note: string | null = null,
): GuidePick {
  return {
    country: country?.country ?? null,
    place: [country?.name, place].filter(Boolean).join(" ") || null,
    keyword,
    note,
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
  /** How each aroma reads in this style: cherry → "상큼한". */
  feels: Readonly<Record<string, string>>;
  abv: readonly [number, number] | null;
  /** Where a grape's bottles come from, most first (counted from the catalog). */
  bottledRegions: readonly { region: string; bottles: number }[];
  /** How many bottles we carry of it; ties between fits go to the fuller shelf. */
  bottles: number;
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

// deno-lint-ignore no-explicit-any
function styleOf(t: any): Style {
  const name = t.names?.ko ?? t.key;
  const levels: Record<string, Band> = {};
  for (const [axis, entry] of Object.entries(t.taste ?? {})) {
    const band = bandOfWord((entry as { level?: string }).level);
    if (band) levels[axis] = band;
  }
  const hints = t.hints ?? {};
  return {
    key: t.key,
    name,
    colors: hints.colors ?? colorOfStyle(t.key, name),
    levels,
    aromas: (t.aromas ?? []).map((a: { key: string }) => a.key),
    feels: Object.fromEntries(
      (t.aromas ?? []).flatMap((a: { key: string; feel?: string }) =>
        a.feel ? [[a.key, a.feel]] : []
      ),
    ),
    abv: hints.abv_range ?? null,
    bottledRegions: hints.bottled_regions ?? [],
    bottles: t.extra?.bottles ?? 0,
  };
}

/** Best fit first; among equal fits the style we carry more bottles of. */
function byFit(
  x: { s: Style; score: number },
  y: { s: Style; score: number },
): number {
  return y.score - x.score || y.s.bottles - x.s.bottles ||
    x.s.key.localeCompare(y.s.key);
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
  }
  /** avoid: an aroma to turn down, which the next bottle should not carry. */
  | { aroma: string; avoid?: true };

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
        out.push(
          saidTurn(a) === "higher"
            ? { aroma: a.subject.key }
            : { aroma: a.subject.key, avoid: true },
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
    out.push({
      axis: target.axis,
      band: up ? "high" : "low",
      adjust: true,
      from,
    });
  }
  for (const s of next.keep) {
    if (s.domain === "aroma") {
      out.push({ aroma: s.key });
      continue;
    }
    const target = axisOf(s);
    const own = target && (target.band ?? record[target.axis]);
    const band = settled || !own ? own : toward(own, sideNamed(s, reactions));
    if (
      target && band && !out.some((w) => "axis" in w && w.axis === target.axis)
    ) {
      out.push({ axis: target.axis, band, adjust: false });
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

/**
 * 핵심 매력: "체리·제비꽃 향이 나는 산뜻한". Aromas the reader already named,
 * the aroma line 2 is told apart by, and 결 rows about an adjusted sensation
 * are left out, so no line repeats another.
 */
function charm(
  style: Style,
  skipAxes: ReadonlySet<string>,
  skipAromas: ReadonlySet<string>,
): string {
  const aromas = style.aromas
    .filter((a) => !skipAromas.has(a) && AROMA_NAMES.has(a))
    .slice(0, 2)
    .map((a) => AROMA_NAMES.get(a)!);
  // "과일 향이 나는 향이 진한": an aroma row says nothing about 향 twice.
  const gyeol = GYEOL.find((g) =>
    Object.entries(g.when).every(([axis, bands]) =>
      !skipAxes.has(axis) && style.levels[axis] !== undefined &&
      !(aromas.length && axis === "aroma_intensity") &&
      bands.includes(style.levels[axis])
    )
  )?.word;
  return [aromas.length ? `${aromas.join("·")} 향이 나는` : "", gyeol ?? ""]
    .filter(Boolean).join(" ");
}

type Difference = {
  words: [string, string, string];
  /** "가볍게" for a level step, used in the wine line's title. */
  adverb?: string;
  aroma?: string;
};

/** 차별점 of style 2 against style 1: [modifier, joined with 면서, joined with 서] */
function difference(
  a: Style,
  b: Style,
  skipAxes: ReadonlySet<string>,
): Difference | null {
  const step = (axis: string) => {
    const x = a.levels[axis], y = b.levels[axis];
    return x && y && !skipAxes.has(axis) ? Math.sign(RANK[y] - RANK[x]) : 0;
  };
  const steps: [string, number, [string, string, string], string][] = [
    [
      "acidity",
      -1,
      ["산미가 둥근", "산미가 둥글면서", "산미가 둥글어서"],
      "산미는 둥글게",
    ],
    [
      "acidity",
      1,
      ["산미가 또렷한", "산미가 또렷하면서", "산미가 또렷해서"],
      "산미는 또렷하게",
    ],
    ["body", 1, ["묵직한", "묵직하면서", "묵직해서"], "묵직하게"],
    ["body", -1, ["가벼운", "가벼우면서", "가벼워서"], "가볍게"],
    ["sweetness", 1, ["달콤한", "달콤하면서", "달콤해서"], "달콤하게"],
    ["sweetness", -1, ["덜 단", "덜 달면서", "덜 달아서"], "덜 달게"],
    ["smoothness", 1, ["부드러운", "부드러우면서", "부드러워서"], "부드럽게"],
    [
      "aroma_intensity",
      1,
      ["향이 진한", "향이 진하면서", "향이 진해서"],
      "향은 진하게",
    ],
    ["aroma_intensity", -1, [
      "향이 은은한",
      "향이 은은하면서",
      "향이 은은해서",
    ], "향은 은은하게"],
  ];
  for (const [axis, dir, words, adverb] of steps) {
    if (step(axis) === dir) return { words, adverb };
  }
  const extra = b.aromas.find((x) =>
    !a.aromas.includes(x) && AROMA_NAMES.has(x)
  );
  if (!extra) return null;
  const name = AROMA_NAMES.get(extra)!;
  return {
    words: [
      `${name} 향이 있는`,
      `${name} 향이 있으면서`,
      `${name} 향이 있어서`,
    ],
    aroma: extra,
  };
}

/** A burden head when something is to change, else the balanced or the liked head. */
function headFor(
  adjust: readonly unknown[],
  balanced: boolean,
  liked = true,
): string {
  if (adjust.length && !liked) return HEAD_ONLY_BURDEN;
  if (adjust.length) return HEAD_BURDEN;
  return balanced ? HEAD_BALANCED : HEAD_POSITIVE;
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

/** 라벨에 'X'가 적힌 것 reads 'X'가 적힌 것 after "라벨에서 … 확인해 보세요". */
function feature(compare: string): string {
  return compare.replace(/^라벨(에|의)\s*/, "");
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

type Ranked = { s: Style; score: number; core: string };

/**
 * Casks and methods for C: a liked aroma or one of its family counts, and an
 * adjusted level only rules a cask out when it is known to go the wrong way
 * (most casks hold no 알코올 열감 at all).
 */
function chooseCasks(
  styles: readonly Style[],
  wants: readonly Want[],
  liked: ReadonlySet<string>,
): { first: Ranked; second: Ranked | null; diff: null } | null {
  const ranked = styles.flatMap((s) => {
    let score = 0;
    let shared = 0;
    for (const w of wants) {
      if ("aroma" in w) {
        if (w.avoid && carries(s, w.aroma)) return [];
        continue;
      }
      const band = bandFor(s, w.axis);
      // 캐스크 스트렝스 is no answer after a 40% whisky found hot.
      if (band && w.strict && Math.abs(RANK[band] - RANK[w.band]) > 1) {
        return [];
      }
      if (!band || !w.from) continue;
      if (w.adjust) {
        const wrong = w.band === "low"
          ? RANK[band] > RANK[w.from]
          : RANK[band] < RANK[w.from];
        if (wrong) return [];
        if (band !== w.from) score++;
      }
    }
    for (const l of liked) {
      if (s.aromas.includes(l)) shared += 2;
      else if (
        s.aromas.some((a) =>
          AROMA_FAMILY.get(a) === l ||
          (!!AROMA_FAMILY.get(l) && AROMA_FAMILY.get(a) === AROMA_FAMILY.get(l))
        )
      ) shared++;
    }
    // A cask must share an aroma with the reader; 활성탄 여과 is no answer to 피트.
    return shared ? [{ s, score: score + shared, core: "" }] : [];
  }).sort(byFit);
  if (!ranked.length) return null;
  return { first: ranked[0], second: ranked[1] ?? null, diff: null };
}

/** Line 1 and line 2 for A–C, or null when nothing fits. */
function choose(
  styles: readonly Style[],
  wants: readonly Want[],
  skipAxes: ReadonlySet<string>,
  skipAromas: ReadonlySet<string>,
): { first: Ranked; second: Ranked | null; diff: Difference | null } | null {
  const ranked = styles.flatMap((s) => {
    const score = fit(s, wants);
    const core = charm(s, skipAxes, skipAromas);
    return score === null || !core ? [] : [{ s, score, core }];
  }).sort(byFit);
  if (!ranked.length) return null;
  // A style far from an unmentioned level stands in only when nothing else fits.
  const close = ranked.filter((r) => r.score > FAR / 2);
  if (close.length) ranked.splice(0, ranked.length, ...close);
  const first = ranked[0];
  // 가메(보졸레) and 보졸레 are one choice to the reader.
  const second =
    ranked.slice(1).find((r) =>
      !r.s.name.includes(first.s.name) && !first.s.name.includes(r.s.name) &&
      difference(first.s, r.s, skipAxes) !== null
    ) ?? null;
  if (!second) return { first, second, diff: null };
  const diff = difference(first.s, second.s, skipAxes)!;
  // The aroma line 2 is told apart by is not said again in its 핵심 매력.
  const core = diff.aroma
    ? charm(second.s, skipAxes, new Set([...skipAromas, diff.aroma]))
    : second.core;
  return { first, second: { ...second, core: core || second.core }, diff };
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

/**
 * Sparkling wine: the two styles (country and style) that fit the wants best,
 * and the 당도·산도·탄산·바디 marks.
 */
function writeSparklingGuide(
  facts: CardFacts,
  styleKeys: readonly string[],
  wants: readonly Want[],
  adjust: readonly Adjust[],
  head: string,
  directions: GuideDirection[],
): Guide | null {
  const rows = terms("regional_style").filter((t) =>
    t.key.includes("sparkling") && !styleKeys.includes(t.key)
  );
  const scored = rows.flatMap((t) => {
    const s = styleOf(t);
    const score = fit(s, wants);
    return score === null ? [] : [{ t, s, score }];
  }).sort(byFit);
  const close = scored.filter((x) => x.score > FAR / 2);
  const top = (close.length ? close : scored).slice(0, 2).map((x) => x.t);
  if (!top.length) return null;
  const keptAxes = new Set(
    wants.flatMap((w) => "axis" in w && !w.adjust && !w.near ? [w.axis] : []),
  );
  const levels = specLevels(
    facts.product_facts,
    adjust,
    keptAxes,
    SPARKLING_SPEC,
  );
  return guideOf(head, {
    picks: top.map((t) => pickOf(countryOfRegion(t), undefined, t.names.ko)),
    tip: levels.length ? WINE_TIP : null,
    levels,
    directions,
  });
}

/** The country a region sits in: the root of its tree (its key is ISO 3166-1 alpha-2). */
function countryOfKey(
  key: string,
): { country: string; name: string } | undefined {
  let row = regionByKey.get(key);
  while (row?.parent) row = regionByKey.get(row.parent);
  return row ? { country: row.key, name: row.names.ko } : undefined;
}

/**
 * Up to three grapes that fit, one line per region most of its bottles come
 * from (a fifth of them or more, at most two), led by the country and closed
 * with an aroma of that region: "포르투갈 비뉴 베르드 알바리뇨 (꽃 계열 향이 나요)".
 */
/** A grape bottled in one region: the grape's taste, the region's where the grape has none, the aromas of both. */
function grapeInRegion(grape: Style, region: Style): Style {
  return {
    ...grape,
    levels: { ...region.levels, ...grape.levels },
    aromas: [...new Set([...grape.aromas, ...region.aromas])],
    feels: { ...region.feels, ...grape.feels },
  };
}

/**
 * A: the two grape × region pairs that fit the wants best, ties broken by
 * how many bottles we carry. Sparkling regions stay out of still wine. A grape
 * without region counts stands on its own.
 */
function wineKeywords(
  grapes: readonly Style[],
  wants: readonly Want[],
): GuidePick[] {
  const pairs = grapes.flatMap((g) => {
    // "코르비나(발폴리첼라·아마로네)" reads "코르비나".
    const name = g.name.replace(/\(.*\)/, "").trim();
    const inRegions = g.bottledRegions.flatMap(({ region, bottles }) => {
      const row = regionByKey.get(region);
      if (!row) return [];
      const r = styleOf(row);
      if (r.levels.carbonation === "high") return [];
      const score = fit(grapeInRegion(g, r), wants);
      if (score === null) return [];
      const place = row.parent ? r.name : undefined;
      const pick = pickOf(countryOfKey(region), place, name);
      return [{ pick, score, bottles }];
    });
    if (inRegions.length) return inRegions;
    const score = fit(g, wants);
    return score === null
      ? []
      : [{ pick: pickOf(undefined, undefined, name), score, bottles: 0 }];
  });
  const text = (p: GuidePick) => `${p.place ?? ""} ${p.keyword}`;
  return pairs
    .sort((x, y) =>
      y.score - x.score || y.bottles - x.bottles ||
      text(x.pick).localeCompare(text(y.pick))
    )
    .slice(0, 2)
    .map((p) => p.pick);
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
 * (estimated) still guides: it is what such a bottle usually is.
 */
function specLevels(
  facts: readonly ProductFact[],
  adjust: readonly Adjust[],
  keptAxes: ReadonlySet<string>,
  axes: readonly [string, string][],
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
    rows.push({ label, mark, range: lo === hi ? `${lo}` : `${lo}~${hi}` });
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
const saidTurn = (a: Adjust) => a.direction === "higher" ? "higher" : "lower";

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
    return { label: "도수", mark: v, range: `${abv}% 안팎` };
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
  return { label: "도수", mark, range };
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
    rows.push({ label, mark: at, range: bands[at - 1] });
  }
  return rows;
}

/**
 * 다이긴조 · 준마이 긴조: the sister grades in one chip, with the liked aromas
 * every one of them carries ("달콤하고 시원한 배 향과 꽃 향이 나요"); when they
 * share none, the aromas any of them carries.
 */
function gradePick(
  grades: readonly Style[],
  likedAromas: readonly string[],
): GuidePick {
  const carried = (every: boolean) =>
    likedAromas.filter((a) =>
      every
        ? grades.every((g) => g.aromas.includes(a))
        : grades.some((g) => g.aromas.includes(a))
    );
  const aromas = (carried(true).length ? carried(true) : carried(false))
    .filter((a) => AROMA_NAMES.has(a))
    .slice(0, 2);
  const feel = grades.find((g) => g.feels[aromas[0]])?.feels[aromas[0]];
  const said = aromas.length
    ? josa(
      aromas
        .map((a, i) => `${i === 0 && feel ? `${feel} ` : ""}${scent(a)}`)
        .join("{과} ") + "이 나요",
    )
    : null;
  return pickOf(
    undefined,
    undefined,
    grades.map((g) => g.name).join(" · "),
    said,
  );
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
 * Casks and methods to look for: the label word, what the cask or method
 * does to the drink (the dictionary's guide_note) and one aroma it brings,
 * a liked one or one of its family first ("셰리 캐스크(Sherry Cask): 스페인 셰리
 * 와인이 깊게 밴 통에서 숙성되어 … 진하고 깊은 말린 과일 향이 나요.").
 */
function caskPicks(
  styles: readonly Style[],
  likedAromas: readonly string[],
  category: string,
): GuidePick[] {
  return styles.map((st) => {
    const row = caskTermByKey.get(st.key);
    const aroma = st.aromas.find((a) =>
      likedAromas.includes(a) ||
      likedAromas.some((l) =>
        AROMA_FAMILY.get(a) === l ||
        (!!AROMA_FAMILY.get(l) && AROMA_FAMILY.get(a) === AROMA_FAMILY.get(l))
      )
    ) ?? st.aromas.find((a) => AROMA_NAMES.has(a) && !a.endsWith("_character"));
    const scented = aroma
      ? `${[st.feels[aroma], scent(aroma)].filter(Boolean).join(" ")}이 나요`
      : null;
    const does = (row?.hints as { guide_note?: string } | undefined)?.guide_note
      ?.trim();
    // The aroma closes the note; alone it stays the short line it was.
    const said = does
      ? [does, scented && `${scented}.`].filter(Boolean).join(" ")
      : scented;
    return caskChip(st, category, said);
  });
}

/**
 * 이번 술을 기준으로: each liked thing kept, each burden turned. [named] gives
 * a burden its own word where a kind has one.
 */
function directionsOf(
  next: NextChoice,
  named: (a: Adjust) => string | null = () => null,
): GuideDirection[] {
  return [
    ...next.keep.flatMap((s) => {
      const word = liked(s);
      return word ? [{ word, change: "keep" as const }] : [];
    }),
    ...next.adjust.flatMap((a) => {
      // 베리 향 ↓ as well as 단맛 ↓: an aroma to turn is a direction too.
      const word = named(a) ?? burden(a.subject) ??
        (a.subject.domain === "aroma" ? liked(a.subject) : null);
      if (!word) return [];
      return [{
        word,
        change: a.direction === "higher" ? "higher" as const : "lower" as const,
      }];
    }),
  ];
}

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
  /** The axes a burden moves: never offered again as something to keep. */
  skipAxes: Set<string>;
  /** The aromas the reader keeps: a pick does not repeat them as news. */
  skipAromas: Set<string>;
  /** The liked axes that stay where the bottle has them. */
  keptAxes: Set<string>;
  styleKeys: string[];
  category: string;
  kindRow: ReturnType<typeof terms>[number] | undefined;
  kind: Style | null;
  cues: Cue[];
  slots: Record<string, string>;
  /** 내 취향 기준: every kind shows what the reader keeps and turns. */
  directions: ReturnType<typeof directionsOf>;
  /** What the head counts as turned: the nameable burdens, and the aromas to turn. */
  turns: NextChoice["adjust"];
  head: string;
};

/** The guide for one card, or null when nothing in the dictionary fits it. */
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
    skipAxes: new Set(adjusted.map((w) => w.axis)),
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
    directions: directionsOf(next),
    turns,
    head: headOf(facts, turns, slots),
  };
}

const headOf = (
  facts: CardFacts,
  adjust: NextChoice["adjust"],
  slots: Record<string, string>,
) => fill(headFor(adjust, isBalanced(facts), !!slots.P), slots);

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
    .filter((s) =>
      c.kindRow?.key !== "distilled_soju" || !NOT_ON_SOJU.has(s.key)
    );
}

/** Sparkling wine: its own guide, else the label words and the marks. */
function sparklingGuide(c: GuideContext): Guide | null {
  return writeSparklingGuide(
    c.facts,
    c.styleKeys,
    c.wants,
    c.adjust,
    headOf(c.facts, c.turns, { ...c.slots, K: "스파클링 와인" }),
    c.directions,
  ) ?? labelGuide(
    c.head,
    cuePicks(chooseCues(c, c.cues, 2), c.slots, true),
    specLevels(c.facts.product_facts, c.adjust, c.keptAxes, SPARKLING_SPEC),
    c.directions,
    WINE_TIP,
  );
}

/** Still wine: the grapes and regions that fit, else the label words. */
function wineGuide(c: GuideContext): Guide | null {
  const styles = candidateStyles(c, "A");
  const lean = sweetLean(c);
  const levels = leanLevels(
    c,
    lean,
    specLevels(c.facts.product_facts, c.adjust, c.keptAxes, WINE_SPEC),
  );
  const leaning = lean ? leanPicks(c, styles, lean) : [];
  if (leaning.length) {
    return guideOf(c.head, {
      picks: leaning,
      tip: WINE_TIP,
      levels,
      directions: c.directions,
    });
  }
  if (!choose(styles, c.wants, c.skipAxes, c.skipAromas)) {
    // No grape fits: the kind's own label words, then the marks.
    return labelGuide(
      c.head,
      cuePicks(chooseCues(c, c.cues, 2), c.slots, true),
      levels,
      c.directions,
      WINE_TIP,
    );
  }
  return guideOf(c.head, {
    picks: wineKeywords(styles, c.wants),
    tip: levels.length ? WINE_TIP : null,
    levels,
    directions: c.directions,
  });
}

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
      return reachable(c, "sweetness", row.mark, "up")
        ? row
        : { ...row, mark: own, range: `${own}` };
    }
    const axis = levers.find((lever) => label(lever) === row.label);
    const own = axis && levelOf(c.facts.product_facts, axis);
    if (!axis || !own || own === 1 || !reachable(c, axis, own - 1, "down")) {
      return row;
    }
    const hi = own - 1;
    const lo = hi > 1 && reachable(c, axis, hi - 1, "down") ? hi - 1 : hi;
    return { ...row, mark: hi, range: lo === hi ? `${hi}` : `${lo}~${hi}` };
  });
}

/**
 * The grapes whose bottles lean the asked way in felt sweetness, the
 * strongest lean first (counted from the catalog's single-variety bottles,
 * never by how many bottles a grape has), each with what in its dictionary
 * row makes it so. A grape must lean that way more than a kind's bottles do
 * on the whole (a third), must not be said by the dictionary to go the other
 * way, and must fit what else the reader said.
 */
function leanPicks(
  c: GuideContext,
  styles: readonly Style[],
  lean: Lean,
): GuidePick[] {
  const styleKey = c.facts.record.style_key;
  const leans = new Map(grapeLeans(styleKey).map((g) => [g.grape, g]));
  const levers = sweetLevers(styleKey);
  const said = c.wants.filter((w) =>
    "aroma" in w || (!w.near && w.axis !== "sweetness")
  );
  const raising = c.adjust.some((a) => isSweetness(a.subject));
  const own = c.record.sweetness ?? "low";
  return styles.flatMap((s) => {
    const counted = leans.get(s.key);
    if (!counted || fit(s, said) === null) return [];
    const [share, other] = lean === "sweeter"
      ? [counted.sweeter, counted.drier]
      : [counted.drier, counted.sweeter];
    if (share <= 1 / 3 || share <= other) return [];
    const sweetness = s.levels.sweetness ?? "low";
    const against = lean === "drier"
      ? sweetness !== "low"
      // A dry grape the dictionary calls firm or sharp is no sweeter-feeling
      // pick, and a liked sweetness is not sent two bands up the scale.
      : sweetness === "low"
      ? levers.some((axis) => s.levels[axis] === "high")
      : !raising && RANK[sweetness] - RANK[own] > 1;
    return against ? [] : [{ s, share }];
  })
    .sort((x, y) => y.share - x.share || x.s.key.localeCompare(y.s.key))
    .slice(0, 2)
    .map(({ s }) => {
      // "네비올로(바롤로·바르바레스코)" reads "네비올로".
      const name = s.name.replace(/\(.*\)/, "").trim();
      const region = s.bottledRegions.map((r) => regionByKey.get(r.region))
        .find((row) => row && styleOf(row).levels.carbonation !== "high");
      return pickOf(
        region && countryOfKey(region.key),
        region?.parent ? region.names.ko : undefined,
        name,
        leanReason(s, lean, levers),
      );
    });
}

/** Why the grape feels sweeter or drier, from its own dictionary row. */
function leanReason(s: Style, lean: Lean, levers: readonly string[]): string {
  const tastes = (band: Band) =>
    levers.filter((axis) => s.levels[axis] === band).map((axis) =>
      LEAN_TASTES[axis]
    ).join("{과} ");
  if (lean === "drier") {
    const firm = tastes("high");
    return fill(firm ? DRIER_BY.firm : DRIER_BY.counted, { S: firm });
  }
  if (s.levels.sweetness === "high") return SWEETER_BY.sweet;
  if (s.levels.sweetness === "mid") return SWEETER_BY.off_dry;
  const soft = tastes("low");
  const ripe = s.aromas.filter((a) =>
    AROMA_NAMES.has(a) &&
    familiesOfAroma(a).some((family) =>
      family === "effect_ripe_fruit" || family === "effect_sweet_scent"
    )
  ).slice(0, 2).map(scent).join("{과} ");
  const text = soft && ripe
    ? SWEETER_BY.soft_and_ripe
    : soft
    ? SWEETER_BY.soft
    : ripe
    ? SWEETER_BY.ripe
    : SWEETER_BY.counted;
  return fill(text, { S: soft, A: ripe });
}

/** Sake: the sister grades in one chip and the label bands. */
function sakeGuide(c: GuideContext): Guide | null {
  const picked = choose(
    candidateStyles(c, "B"),
    c.wants,
    c.skipAxes,
    c.skipAromas,
  );
  // The chip names other grades, so the head names the kind as a whole: 사케.
  const head = headOf(c.facts, c.turns, { ...c.slots, K: "사케" });
  const levels = sakeLevels(c.facts.product_facts, c.adjust);
  // A grade two bands off the bottle would send a 곡물 향 drinker to 긴조: the label numbers say it better.
  if (!picked || picked.first.score <= FAR / 2) {
    return labelGuide(
      head,
      cuePicks(sakeCues(c), c.slots, true),
      levels,
      c.directions,
      SAKE_TIP,
    );
  }
  const top = [picked.first.s, ...(picked.second ? [picked.second.s] : [])];
  return guideOf(head, {
    picks: [gradePick(top, [...c.skipAromas])],
    tip: SAKE_TIP,
    levels,
    directions: c.directions,
  });
}

/**
 * Whisky: the casks or methods that carry a liked aroma, then a label word
 * for each level to turn or keep, the word to pass over for an aroma to turn
 * down, and a cask or method the dictionary says moves a level no label word
 * answered. A chip is a new word to look for: the bottle's own cask or method
 * is named only for a liked aroma nothing else carries (피트 처리 맥아 after a
 * liked 스모키 향).
 */
function caskGuide(c: GuideContext): Guide | null {
  const styles = candidateStyles(c, "C");
  const fresh = styles.filter((s) => !c.made.has(s.key));
  const sought = new Set([...c.skipAromas, ...c.raisedAromas]);
  const picked = chooseCasks(fresh, c.wants, sought) ??
    chooseCasks(styles, c.wants, sought);
  // An aroma to turn down keeps one of the two places for its word.
  const passed = passOverPicks(c, 1);
  const room = 2 - passed.length;
  const casks = picked
    ? [picked.first.s, ...(picked.second ? [picked.second.s] : [])]
      .slice(0, room)
    : [];
  const abvRow = abvRowOf(c);
  // The 도수 mark already says the strength: no cue about it twice.
  const cueRows = chooseCues(
    c,
    c.cues,
    room - casks.length,
    new Set(abvRow ? ["alcohol_presence"] : []),
  );
  const effects = effectPicks(
    c,
    fresh.filter((s) => !casks.includes(s)),
    room - casks.length - cueRows.length,
    new Set(cueRows.flatMap((cue) => cue.axis ?? [])),
  );
  const picks = [
    ...caskPicks(casks, [...sought], c.category),
    ...cuePicks(cueRows, c.slots, casks.length === 0),
    ...passed,
    ...effects,
  ];
  if (!picks.length && !c.directions.length) return null;
  return guideOf(c.head, {
    picks,
    tip: picks.length ? CASK_TIP : null,
    levels: abvRow ? [abvRow] : [],
    directions: c.directions,
  });
}

/** The chip of a cask or method: its name, the label word, and where its bottles cluster. */
function caskChip(st: Style, category: string, note: string | null): GuidePick {
  const row = caskTermByKey.get(st.key);
  // Where its bottles cluster in our catalog: 피트 처리 맥아 -> 아일라섬.
  const region = (row?.hints as {
    bottled_regions?: { category: string; region: string }[];
  } | undefined)?.bottled_regions?.find((r) => r.category === category)
    ?.region;
  const label = labelWordsOf(st.key).find((w) => /[A-Za-z]/.test(w));
  return pickOf(
    undefined,
    region,
    `${st.name}${label ? `(${label})` : ""}`,
    note,
  );
}

/**
 * An aroma to turn down: the label word of the cask or method whose making
 * is sure to leave it (the dictionary's production-based aromas), as a word
 * to pass over. The dictionary's own caution is the note when it speaks of
 * that word and its 향; else the aroma the word brings.
 */
function passOverPicks(c: GuideContext, limit: number): GuidePick[] {
  const picks: GuidePick[] = [];
  for (const aroma of c.turnedAromas) {
    for (const row of caskTermByKey.values()) {
      if (picks.length >= limit) return picks;
      if (!(row.categories ?? []).includes(c.category)) continue;
      const brought = (row.aromas ?? []).find((a) =>
        a.basis === "production" &&
        (lineage(a.key).includes(aroma) || lineage(aroma).includes(a.key))
      );
      const word = labelWordsOf(row.key).find((w) => /[A-Za-z]/.test(w));
      if (!brought || !word) continue;
      const keyword = fill(WITHOUT_WORD, { W: word });
      if (picks.some((p) => p.keyword === keyword)) continue;
      const caution = (row.hints as { avoid?: string } | undefined)?.avoid;
      const feel = (brought as { feel?: string }).feel;
      picks.push(pickOf(
        undefined,
        undefined,
        keyword,
        caution?.includes(`'${word}'`) && caution.includes("향")
          ? caution
          : fill(WORD_BRINGS, {
            W: word,
            A: [feel, scent(brought.key)].filter(Boolean).join(" "),
          }),
      ));
    }
  }
  return picks;
}

/** "우리 상품 354병에 기록된 수준의 중간값이에요": the bottles an aggregate row was counted from. */
function countedBottles(row: { basis?: string; reason?: string } | undefined) {
  if (row?.basis !== "aggregate") return 0;
  return Number(row.reason?.match(/(\d+)병/)?.[1] ?? 0);
}

/** How sure the dictionary is of a taste row: made that way, collected, usual, or counted from our bottles. */
const BASIS_RANK: Readonly<Record<string, number>> = {
  production: 0,
  collected: 1,
  typical: 2,
  aggregate: 3,
};

/**
 * A cask or method for each level the reader asked to turn or keep on a side
 * and no label word answered: one whose dictionary taste row sits on that
 * side (a 3회 증류 for 알코올 열감 to soften, a cask of long 여운 for a finish
 * too short). It must not push another answer the other way or bring an
 * aroma to turn down. Among those that fit, one that leaves the bottle's
 * unmentioned levels alone goes first, then the surer row, then the one
 * closer to the bottle's aromas, then the row counted from more bottles.
 */
function effectPicks(
  c: GuideContext,
  styles: readonly Style[],
  limit: number,
  answered: ReadonlySet<string>,
): GuidePick[] {
  const asks = levelAsks(c);
  const side = (ask: LevelAsk): Band =>
    ask.direction === "higher" ? "high" : "low";
  const otherSide = (ask: LevelAsk): Band =>
    ask.direction === "higher" ? "low" : "high";
  const row = (s: Style, axis: string) => {
    const taste = caskTermByKey.get(s.key)?.taste ?? {};
    // Casks and methods hold 부드러움 where kinds hold 알코올 열감 (bandFor).
    return taste[axis] ??
      (axis === "alcohol_presence" ? taste.smoothness : undefined);
  };
  const near = c.wants.filter((w) => "axis" in w && w.near);
  const families = familiesOfBottle(
    c.facts.product_facts.flatMap((p) =>
      p.fact.type === "descriptor" && p.fact.section === "aroma"
        ? [p.fact.key]
        : []
    ),
    [...c.made],
  );
  const shared = (s: Style) =>
    new Set(s.aromas.flatMap(familiesOfAroma).filter((f) => families.has(f)))
      .size;
  const picks: GuidePick[] = [];
  const used = new Set<string>();
  for (const ask of asks) {
    if (picks.length >= limit) break;
    if (answered.has(ask.axis) || !EFFECT_SAID[ask.axis]?.[side(ask)]) continue;
    const [best] = styles
      .filter((s) =>
        !used.has(s.key) && bandFor(s, ask.axis) === side(ask) &&
        asks.every((other) =>
          other === ask || bandFor(s, other.axis) !== otherSide(other)
        ) &&
        !c.turnedAromas.some((aroma) => carries(s, aroma))
      )
      .map((s, order) => ({
        s,
        order,
        far: fit(s, near) ?? 0,
        sure: BASIS_RANK[row(s, ask.axis)?.basis ?? ""] ?? 9,
        shared: shared(s),
        counted: countedBottles(row(s, ask.axis)),
      }))
      // A row counted from our bottles says how many it was counted from.
      .filter((x) => x.sure !== BASIS_RANK.aggregate || x.counted > 0)
      .sort((x, y) =>
        y.far - x.far || x.sure - y.sure || y.shared - x.shared ||
        y.counted - x.counted || x.order - y.order
      );
    if (!best) continue;
    used.add(best.s.key);
    const taste = row(best.s, ask.axis);
    const reason = taste?.basis === "aggregate"
      ? fill(EFFECT_COUNTED, { N: `${best.counted}` })
      : taste?.reason?.replace(/[.\s]*$/, ".");
    picks.push(
      caskChip(
        best.s,
        c.category,
        [EFFECT_SAID[ask.axis]![side(ask)], reason].filter(Boolean).join(" "),
      ),
    );
  }
  return picks;
}

/**
 * Traditional drinks: the words printed on the label that answer what the
 * reader said, then the marks. A 증류식 소주 also names a cask or method that
 * shares a liked aroma, as a whisky does, and shows 단맛·바디 beside its 도수.
 */
function traditionalGuide(c: GuideContext): Guide | null {
  const soju = c.kindRow?.key === "distilled_soju";
  const asks = labelAsks(c);
  const taken: string[] = [];
  const take = (cues: readonly Cue[]) => {
    taken.push(...cues.flatMap(shownWords));
    return cues;
  };
  // A burden's own word first: the cask of a liked aroma does not crowd it out.
  const turns = take(chooseLabels(c, asks.filter((a) => a.turn), 2, taken));
  const casks = soju ? sojuCasks(c, 2 - turns.length, taken) : [];
  taken.push(...casks.flatMap((s) => [s.name, ...labelWordsOf(s.key)]));
  const free = () => 2 - turns.length - casks.length;
  const keeps = take(
    chooseLabels(c, asks.filter((a) => !a.turn), free(), taken),
  );
  // A second word for an answer fills a place still free.
  const more = take(chooseLabels(c, asks, free() - keeps.length, taken));
  const picks = [
    ...labelPicks(turns, c.slots),
    ...caskPicks(casks, [...c.skipAromas], c.category),
    ...labelPicks([...keeps, ...more], c.slots),
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
      (axis) =>
        sideNamed(
          { domain: "taste", key: axis } as Subject,
          c.facts.reactions,
        ),
    ),
    ...(abvRow ? [abvRow] : []),
  ];
  const directions = labelDirections(c);
  if (!picks.length && !directions.length && !levels.length) return null;
  return guideOf(c.head, {
    picks,
    tip: levels.length ? LABEL_TIP : null,
    levels,
    directions,
  });
}

/** A whisky label always prints the 도수; the mark says which band to look for. */
const abvRowOf = (c: GuideContext) =>
  abvLevel(c.facts, c.adjust, c.keptAxes, c.kind?.abv?.[0] ?? null);

/**
 * The casks and methods of a 증류식 소주 that share a liked aroma, without one
 * the words already chosen rule out ('감압증류' was said: not 상압 증류) or
 * one that undoes an answer.
 */
function sojuCasks(
  c: GuideContext,
  limit: number,
  taken: readonly string[],
): Style[] {
  if (limit <= 0) return [];
  const asks = labelAsks(c);
  const used = new Set(taken.map(spaceless));
  const wordsOf = (s: Style) => [s.name, ...labelWordsOf(s.key)];
  const open = candidateStyles(c, "C").filter((s) =>
    !rivals(wordsOf(s), used, eitherOr(c)) && !undoes(wordsOf(s), c, asks)
  );
  const picked = chooseCasks(open, c.wants, c.skipAromas);
  if (!picked) return [];
  const first = picked.first.s;
  for (const word of wordsOf(first)) used.add(spaceless(word));
  const second = picked.second?.s;
  return second && limit > 1 && !rivals(wordsOf(second), used, eitherOr(c))
    ? [first, second]
    : [first];
}

/* ------------------------------------------------- the label's own words */

/** One thing the reader said that a label word may answer. */
type LabelAsk = {
  axis?: string;
  aroma?: string;
  direction: "lower" | "higher";
  /** A burden to turn, not a liked thing to keep. */
  turn: boolean;
};

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

/** What the card asks a label for: the burdens first, then what was liked. */
function labelAsks(c: GuideContext): LabelAsk[] {
  const asks: LabelAsk[] = [];
  const add = (ask: LabelAsk) => {
    const same = (x: LabelAsk) => x.axis === ask.axis && x.aroma === ask.aroma;
    if (!asks.some(same)) asks.push(ask);
  };
  for (const a of c.next.adjust) {
    if (a.subject.domain === "aroma") {
      add({ aroma: a.subject.key, direction: saidTurn(a), turn: true });
      continue;
    }
    const axis = labelAxis(a.subject);
    if (axis && !isResidue(a, c.facts.reactions)) {
      add({ axis, direction: axisTurn(a), turn: true });
    }
    // 묵직함 that stayed after swallowing is 텁텁함, with label words of its own.
    if (
      a.subject.domain === "mouthfeel" && a.subject.key === "heavy" &&
      a.direction === "shorter"
    ) {
      add({ axis: "residue", direction: "lower", turn: true });
    }
  }
  for (const s of c.next.keep) {
    if (s.domain === "aroma") {
      add({ aroma: s.key, direction: "higher", turn: false });
      continue;
    }
    const key = `${s.domain}.${s.key}`;
    if (key === "mouthfeel.smooth" || key === "finish.persistence") {
      add({ axis: labelAxis(s)!, direction: "higher", turn: false });
      continue;
    }
    const target = axisOf(s);
    if (!target) continue;
    const band = sideNamed(s, c.facts.reactions) ?? target.band ??
      c.record[target.axis];
    const side = band && direction(band);
    if (side) add({ axis: target.axis, direction: side, turn: false });
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
 * and never beside a word no bottle carries with it ('상압증류' after
 * '감압증류'). The better-sourced sentence goes first.
 */
function chooseLabels(
  c: GuideContext,
  answer: readonly LabelAsk[],
  limit: number,
  taken: readonly string[],
): Cue[] {
  if (limit <= 0) return [];
  const asks = labelAsks(c);
  const cues = [...c.cues].sort((x, y) => (x.grade ?? 9) - (y.grade ?? 9));
  const own = ownWords(c);
  const used = new Set(taken.map(spaceless));
  const chosen: Cue[] = [];
  const fits = (cue: Cue, ask: LabelAsk) =>
    answers(cue, ask) && shownWords(cue).length > 0 &&
    !undoes(meant(cue), c, asks) &&
    !(ask.turn && meant(cue).some((word) => own.has(spaceless(word)))) &&
    !shownWords(cue).some((word) => used.has(spaceless(word))) &&
    !rivals(shownWords(cue), used, eitherOr(c));
  for (const ask of answer) {
    if (chosen.length >= limit) break;
    const cue = cues.find((x) => fits(x, ask));
    if (!cue) continue;
    chosen.push(cue);
    for (const word of shownWords(cue)) used.add(spaceless(word));
  }
  return chosen;
}

const answers = (cue: Cue, ask: LabelAsk) =>
  cue.direction === ask.direction && speaksOf(cue, ask);

const speaksOf = (cue: Cue, ask: LabelAsk) =>
  ask.aroma
    ? !!cue.aroma && lineage(ask.aroma).includes(cue.aroma)
    : cue.axis === ask.axis;

/** 묵직함 and 텁텁함 are one weight: a heavier bottle leaves more behind. */
const WEIGHT: ReadonlySet<string> = new Set(["body", "residue"]);
const touches = (cue: Cue, ask: LabelAsk) =>
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
  asks: readonly LabelAsk[],
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

/** Each chip: the words, then what they bring and why. */
function labelPicks(
  cues: readonly Cue[],
  slots: Record<string, string>,
): GuidePick[] {
  return cues.map((cue) => {
    const compare = feature(cue.compare);
    const said = `${compare}${
      compare.endsWith("수록") ? "" : "{은}"
    } ${cue.effect}`;
    return pickOf(
      undefined,
      undefined,
      fill(labelWords(cue), slots),
      fill(`${said}. ${cue.why}`, slots),
    );
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
 * reader liked something in it and the ingredient tells bottles of the kind
 * apart (보리 among 소주, never 쌀). Left out when it would undo an answer.
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
    return pickOf(
      undefined,
      undefined,
      row.label,
      `${SAME_INGREDIENT} ${row.text}`,
    );
  }
  return null;
}

/** 내 취향 기준 for a traditional drink: 텁텁함 keeps its own word. */
const labelDirections = (c: GuideContext) =>
  directionsOf(
    c.next,
    (a) => isResidue(a, c.facts.reactions) ? RESIDUE : null,
  );

/** One level the card asks a label word or a cask for. */
type LevelAsk = {
  axis: string;
  direction: "lower" | "higher";
  /** A burden to turn, not a liked level to keep. */
  turn: boolean;
};

/**
 * The levels the card asks for: each burden turned the way its word says
 * (가벼움 down is 바디 up), then each liked level that sits on a side. The
 * side is the reader's own word when they gave one (또렷해서, 은은해서), else
 * the bottle's level.
 */
function levelAsks(c: GuideContext): LevelAsk[] {
  const asks: LevelAsk[] = [];
  for (const a of c.adjust) {
    const axis = axisOf(a.subject)?.axis;
    if (axis) asks.push({ axis, direction: axisTurn(a), turn: true });
  }
  for (const s of c.next.keep) {
    const target = axisOf(s);
    const band = target &&
      (sideNamed(s, c.facts.reactions) ?? target.band ??
        c.record[target.axis]);
    const dir = band && direction(band);
    if (target && dir && !asks.some((x) => x.axis === target.axis)) {
      asks.push({ axis: target.axis, direction: dir, turn: false });
    }
  }
  return asks;
}

/** A label word as it is compared: 'Non-chill filtered' is "Non Chill Filtered". */
const wordKey = (word: string) =>
  spaceless(word).replace(/-/g, "").toLowerCase();

/** The words the bottle's own label carries: its casks and methods, its grapes and styles. */
function bottleWords(c: GuideContext): Set<string> {
  return new Set(
    [
      ...[...c.made].flatMap(labelWordsOf),
      ...DICTIONARY_STYLES.filter((t) => c.styleKeys.includes(t.key)).flatMap((
        t,
      ) => [t.names.ko, t.names.en ?? ""]),
    ].filter(Boolean).map(wordKey),
  );
}

/**
 * The label cues that answer the card: the burdens first, never a cue that
 * undoes one, then the liked levels that sit high or low. At most [limit], no
 * two with the same label words, none on an axis in [skipAxes], and none
 * that names a word the bottle already carries (a sherry-cask whisky is not
 * told to look for 'Sherry Cask').
 */
function chooseCues(
  c: GuideContext,
  cues: readonly Cue[],
  limit: number,
  skipAxes: ReadonlySet<string> = new Set(),
): Cue[] {
  const asks = levelAsks(c);
  const own = bottleWords(c);
  const undoes = (cue: Cue) =>
    cues.some((o) =>
      o.cue === cue.cue &&
      asks.some((x) =>
        x.turn && x.axis === o.axis && x.direction !== o.direction
      )
    );
  const chosen: Cue[] = [];
  for (const ask of asks) {
    if (chosen.length >= limit) break;
    if (skipAxes.has(ask.axis)) continue;
    const cue = cues.find((x) =>
      x.axis === ask.axis && x.direction === ask.direction && !undoes(x) &&
      !meant(x).some((word) => own.has(wordKey(word))) &&
      !chosen.some((o) => labelWords(o) === labelWords(x))
    );
    if (cue) chosen.push(cue);
  }
  return chosen;
}

/**
 * A sake's label words for a bottle no grade fits: the aromas the reader
 * liked or wants turned first ('야마하이' for 유산 발효 향, '쿄카이 1801호' for 사과
 * 향, an aroma of the same family counting), then the levels. The label
 * numbers (일본주도, 산도) are left to the marks, which already show them.
 */
function sakeCues(c: GuideContext): Cue[] {
  const { next, cues } = c;
  // 청사과 asks for the 사과 cue: one aroma within the other's line, or siblings.
  const line = (a: string): string[] => {
    const up = AROMA_FAMILY.get(a);
    return up ? [a, ...line(up)] : [a];
  };
  const kin = (a: string, b: string) =>
    line(a).includes(b) || line(b).includes(a) ||
    (!!AROMA_FAMILY.get(a) && AROMA_FAMILY.get(a) === AROMA_FAMILY.get(b));
  const asks = [
    ...next.adjust.flatMap((a) =>
      a.subject.domain === "aroma"
        ? [{
          aroma: a.subject.key,
          direction: a.direction === "higher" ? "higher" : "lower",
        }]
        : []
    ),
    ...next.keep.flatMap((s) =>
      s.domain === "aroma" ? [{ aroma: s.key, direction: "higher" }] : []
    ),
  ];
  const chosen: Cue[] = [];
  for (const ask of asks) {
    const cue = cues.find((x) =>
      x.aroma && x.direction === ask.direction && kin(x.aroma, ask.aroma) &&
      !chosen.includes(x)
    );
    if (cue && chosen.length < 2) chosen.push(cue);
  }
  const words = cues.filter((x) => x.axis && !x.cue.includes("숫자"));
  for (const cue of chooseCues(c, words, 2 - chosen.length)) {
    if (!chosen.some((o) => labelWords(o) === labelWords(cue))) {
      chosen.push(cue);
    }
  }
  return chosen;
}

/**
 * The cue chips: the label words, and under them what the words bring. The
 * first chip of a guide carries the reason; one after another chip reads as
 * its companion.
 */
function cuePicks(
  cues: readonly Cue[],
  slots: Record<string, string>,
  lead: boolean,
): GuidePick[] {
  const said = (c: Cue) => {
    const compare = feature(c.compare);
    return `${compare}${compare.endsWith("수록") ? "" : "{은}"} ${c.effect}`;
  };
  return cues.map((c, i) =>
    pickOf(
      undefined,
      undefined,
      fill(labelWords(c), slots),
      fill(
        i === 0 && lead
          ? `${said(c)}. ${c.why}`
          : `함께 보시면 좋은 표기예요. ${said(c)}.`,
        slots,
      ),
    )
  );
}
