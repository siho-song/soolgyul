/**
 * 다음 술은 이렇게 골라보세요: the guide inside the 한입 summary. It names
 * what to look for on a label or menu, by kind of drink:
 *   A wine: country and grape pairs and the 당도·산도·타닌·바디 marks;
 *     sparkling wine: country and style pairs and the 당도·산도·탄산·바디 marks;
 *     with no grape or style that fits (a rosé), the kind's label cues
 *     ('Saignée', 'dry' 표기) and the marks
 *   B sake: sister grades of a similar strength in one chip, with the liked
 *     aromas they share, and the 당도(주도)·산미(산도) bands; a bottle unlike
 *     every grade gets the bands alone, which are the label's own numbers
 *   C whisky, 증류식 소주: casks and methods sharing an aroma with the
 *     reader, filled up to two chips with the kind's label cues, the 도수
 *     band, and the directions
 *   D other Korean traditional drinks: the quoted label words of the kind's
 *     cues ('생막걸리', '원주'), bare, since the 단맛·산미·탄산·바디·도수 marks
 *     the shops' own taste graphs use say the rest; a 탁주 drinker is not
 *     sent to 과실주, so no other kind fills in, and with no word the marks
 *     and the directions stand alone
 *   E everything else: no guide
 * A guide has two chips when the dictionary holds two that fit, and one is
 * fine. The marks come from the bottle's own levels; the directions from what
 * the reader liked and wants changed (an aroma to turn down or up included).
 * A reader who liked nothing still gets one, aimed by the burdens alone.
 * Which head a card gets is fixed by the card.
 */
import { abvBandsFor } from "./abv_levels.ts";
import { isBalanced } from "./card_balanced.ts";
import { terms } from "./dictionary.ts";
import { josa } from "./card_writing.ts";
import type {
  CardFacts,
  NextChoice,
  ProductFact,
  Subject,
} from "./card_facts.ts";
import type {
  TasteCardGuide,
  TasteCardGuideDirection,
  TasteCardGuideLevel,
  TasteCardGuidePick,
} from "./types.ts";

export type Guide = TasteCardGuide;
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
  /** Only for a bottle of these colors: 'Lambrusco' is red sparkling. */
  colors?: string[];
};

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

/** What the reader liked, in the words of their answer. */
const LIKED: Readonly<Record<string, string>> = {
  "taste.sweetness": "단맛",
  "taste.acidity": "산미",
  "taste.bitterness": "쓴맛",
  "mouthfeel.light": "가벼운 질감",
  "mouthfeel.heavy": "묵직한 질감",
  "mouthfeel.smooth": "부드러운 목넘김",
  "mouthfeel.drying": "떫은맛",
  "mouthfeel.bubbles": "탄산",
  "mouthfeel.warmth": "알코올 열감",
  "finish.persistence": "긴 여운",
  "finish.clean": "깔끔한 마무리",
  "finish.aroma_echo": "코끝에 남는 잔향",
};

/** What the reader found a burden. */
const BURDENED: Readonly<Record<string, string>> = {
  "taste.sweetness": "단맛",
  "taste.acidity": "산미",
  "taste.bitterness": "쓴맛",
  "mouthfeel.drying": "떫은맛",
  "mouthfeel.heavy": "묵직함",
  "mouthfeel.light": "가벼움",
  "mouthfeel.bubbles": "탄산",
  "mouthfeel.warmth": "알코올 열감",
  "finish.persistence": "여운",
  "finish.off_flavor": "삼킨 뒤 올라오는 잡내",
};

function liked(subject: Subject): string | null {
  if (subject.domain === "aroma") {
    return `${AROMA_NAMES.get(subject.key) ?? subject.key} 향`;
  }
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
  }
  | { aroma: string };

/**
 * The band each kept or adjusted sensation should have in the next bottle.
 * An adjustment needs the record's own level to move away from; a kept one
 * stays at the record's level; an unmentioned one stays near it when any
 * style can (a dry drinker who wants softer bubbles is not sent to 모스카토
 * 다스티), and only a bottle unlike every style is sent further. A burden
 * the bottle already sits at the end of (a 40% whisky found hot) is kept at
 * that end: there is nothing lower to send the reader to, but the guide is
 * still written.
 */
function wanted(next: NextChoice, record: Levels): Want[] {
  const out: Want[] = [];
  for (const a of next.adjust) {
    const target = axisOf(a.subject);
    if (!target) continue;
    const from = target.band ?? record[target.axis];
    if (!from) continue;
    const up = a.direction === "higher";
    if (from === (up ? "high" : "low")) {
      out.push({ axis: target.axis, band: from, adjust: false, floor: true });
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
    const band = target && (target.band ?? record[target.axis]);
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

/**
 * How well a style fits: null when it cannot be shown to turn every burden
 * down, or sits two bands off a level the reader kept; two bands off a level
 * the reader did not mention costs [FAR].
 */
function fit(style: Style, wants: readonly Want[]): number | null {
  let kept = 0;
  for (const w of wants) {
    if ("aroma" in w) {
      if (style.aromas.includes(w.aroma)) kept++;
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
    } else if (band && Math.abs(RANK[band] - RANK[w.band]) > 1) {
      return null;
    }
  }
  return kept;
}

/** The first row whose levels all hold names the style's 결. */
const GYEOL: readonly {
  when: Readonly<Record<string, readonly Band[]>>;
  word: string;
}[] = [
  { when: { carbonation: ["high"] }, word: "기포가 톡 쏘는" },
  { when: { sweetness: ["high"] }, word: "달콤한" },
  { when: { astringency: ["high"], body: ["high"] }, word: "단단하고 묵직한" },
  { when: { body: ["high"] }, word: "묵직한" },
  { when: { acidity: ["high"], body: ["low", "mid"] }, word: "산뜻한" },
  { when: { finish_cleanliness: ["high"] }, word: "깔끔한" },
  { when: { smoothness: ["high"] }, word: "부드러운" },
  { when: { body: ["low"] }, word: "가벼운" },
  { when: { astringency: ["low"], body: ["mid"] }, word: "부드러운" },
  { when: { aroma_intensity: ["high"] }, word: "향이 진한" },
  { when: { aroma_intensity: ["low"] }, word: "향이 은은한" },
];

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

/**
 * The head names no sensation: the chips under it do. One sentence for every
 * kind (the user's wording, 2026-11-06): "좋았던 매력은 살리고 부담은 줄인 싱글
 * 몰트 위스키의 추천 키워드예요". Slots: {NB} what was turned, {K} kind.
 */
const HEAD_BURDEN = "좋았던 매력은 살리고 {NB} {K}의 추천 키워드예요.";
const HEAD_POSITIVE = "좋았던 매력을 이어갈 {K}의 추천 키워드예요.";
/** The balanced card (every taste 적당했어요): nothing to call liked. */
const HEAD_BALANCED =
  "이번 잔의 균형이 편안하셨다면, 그 균형 그대로 이어갈 {K}의 추천 키워드예요.";

/** Nothing liked, only burdens: "부담은 줄인 싱글 몰트 위스키의 추천 키워드예요". */
const HEAD_ONLY_BURDEN = "{NB} {K}의 추천 키워드예요.";

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
      if ("aroma" in w) continue;
      const band = bandFor(s, w.axis);
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
  while (region?.parent) {
    const parent: string = region.parent;
    region = regions.find((t) => t.key === parent);
  }
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
  slots: Record<string, string>,
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
  return guideOf(
    fill(headFor(adjust, isBalanced(facts), !!slots.P), {
      ...slots,
      K: "스파클링 와인",
    }),
    {
      picks: top.map((t) => pickOf(countryOfRegion(t), undefined, t.names.ko)),
      tip: levels.length ? WINE_TIP : null,
      levels,
      directions,
    },
  );
}

/** The country a region sits in: the root of its tree (its key is ISO 3166-1 alpha-2). */
function countryOfKey(
  key: string,
): { country: string; name: string } | undefined {
  const regions = terms("region");
  let row = regions.find((t) => t.key === key);
  while (row?.parent) {
    const parent: string = row.parent;
    row = regions.find((t) => t.key === parent);
  }
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
  const regions = terms("region");
  const pairs = grapes.flatMap((g) => {
    // "코르비나(발폴리첼라·아마로네)" reads "코르비나".
    const name = g.name.replace(/\(.*\)/, "").trim();
    const inRegions = g.bottledRegions.flatMap(({ region, bottles }) => {
      const row = regions.find((t) => t.key === region);
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

const WINE_TIP =
  "와인 라벨(앞·뒷면)이나 매장 설명 카드에서 이 특징을 찾아보세요!";
const SAKE_TIP =
  "이자카야 메뉴판이나 바틀 뒷면(라벨)에서 이 키워드를 찾아보세요!";
const CASK_TIP = "바(Bar) 메뉴판이나 바틀 라벨에서 위 단어를 찾아보세요!";
/** Traditional bottle shops print the same four bars under every product, and the label its 도수. */
const LABEL_TIP = "바틀 뒷면의 원재료 표기나 상품 맛 그래프를 확인해보세요!";

const WINE_SPEC: readonly [string, string][] = [
  ["sweetness", "당도"],
  ["acidity", "산도"],
  ["astringency", "타닌"],
  ["body", "바디"],
];
const SPARKLING_SPEC: readonly [string, string][] = [
  ["sweetness", "당도"],
  ["acidity", "산도"],
  ["carbonation", "탄산"],
  ["body", "바디"],
];
const TRADITIONAL_SPEC: readonly [string, string][] = [
  ["sweetness", "단맛"],
  ["acidity", "산미"],
  ["carbonation", "탄산"],
  ["body", "바디"],
];

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
): GuideLevel[] {
  const rows: GuideLevel[] = [];
  for (const [axis, label] of axes) {
    const v = levelOf(facts, axis);
    if (!v) continue;
    const a = adjust.find((x) => axisOf(x.subject)?.axis === axis);
    // Filled marks sit at the level to look for; the words give the range.
    const [mark, lo, hi] = aimAt(v, a, keptAxes.has(axis));
    rows.push({ label, mark, range: lo === hi ? `${lo}` : `${lo}~${hi}` });
  }
  return rows;
}

/** [mark, lo, hi]: the level to look for, and the range the words give. */
function aimAt(
  v: number,
  a: Adjust | undefined,
  kept: boolean,
): [number, number, number] {
  if (a) {
    const at = a.direction === "higher"
      ? Math.min(5, v + 1)
      : Math.max(1, v - 2);
    return [at, at, at];
  }
  if (kept) return [v, v, v];
  return v === 1 ? [1, 1, 2] : [v, v - 1, v];
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
): GuideLevel | null {
  const v = levelOf(facts.product_facts, "alcohol_presence");
  const found = abvBandsFor(facts.record.style_key, facts.record.category);
  if (!v || !found) return null;
  const a = adjust.find((x) => axisOf(x.subject)?.axis === "alcohol_presence");
  const bounds = found.bands.bounds;
  let [mark, lo, hi] = aimAt(v, a, keptAxes.has("alcohol_presence"));
  while (lo < 5 && kindMin !== null && kindMin >= bounds[lo - 1]) lo++;
  mark = Math.max(mark, lo);
  hi = Math.max(hi, lo);
  const floor = bounds[lo - 2];
  const ceiling = bounds[hi - 1];
  const range = floor !== undefined && ceiling !== undefined
    ? `${floor}~${ceiling}%`
    : ceiling !== undefined
    ? `${ceiling}% 미만`
    : `${floor}% 이상`;
  return { label: "도수", mark, range };
}

/**
 * Sake shelves and back labels carry no 1–5 marks: they print 일본주도 (plus
 * is dry) and 산도. The bands our five sweetness levels sit in, from the 985
 * bottles that carry both (medians +6, +3.5, +1, −2.8, −15), named as the
 * Japanese trade names the bands (±1.4, ±3.4, ±6) go by; and the 산도 range
 * our five acidity levels sit in (839 bottles: medians 1.05, 1.3, 1.5, 1.6, 2.5).
 */
const SMV_BANDS: readonly string[] = [
  "아주 드라이한 카라구치 (+6 이상)",
  "카라구치 (+3.5~+5.9)",
  "보통 (±1.4)",
  "살짝 단 아마구치 (-1.5~-3.4)",
  "단 아마구치 (-6 이하)",
];
const ACIDITY_BANDS: readonly string[] = [
  "1.1 이하",
  "1.2~1.4",
  "1.4~1.6",
  "1.6~1.9",
  "2.0 이상",
];

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
        .map((a, i) =>
          `${i === 0 && feel ? `${feel} ` : ""}${AROMA_NAMES.get(a)} 향`
        )
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

/**
 * Casks and methods to look for: the label word and one aroma it brings,
 * a liked one or one of its family first ("셰리 캐스크(Sherry Cask): 진하고 깊은
 * 말린 과일 향이 나요").
 */
function caskPicks(
  styles: readonly Style[],
  likedAromas: readonly string[],
  category: string,
): GuidePick[] {
  return styles.map((st) => {
    const row = terms("maturation", "process").find((t) => t.key === st.key);
    // Where its bottles cluster in our catalog: 피트 처리 맥아 -> 아일라섬.
    const region = (row?.hints as {
      bottled_regions?: { category: string; region: string }[];
    } | undefined)?.bottled_regions?.find((r) => r.category === category)
      ?.region;
    const label = (row?.hints as { label_words?: string[] } | undefined)
      ?.label_words?.find((w) => /[A-Za-z]/.test(w));
    const aroma = st.aromas.find((a) =>
      likedAromas.includes(a) ||
      likedAromas.some((l) =>
        AROMA_FAMILY.get(a) === l ||
        (!!AROMA_FAMILY.get(l) && AROMA_FAMILY.get(a) === AROMA_FAMILY.get(l))
      )
    ) ?? st.aromas.find((a) => AROMA_NAMES.has(a) && !a.endsWith("_character"));
    const said = aroma
      ? `${
        [st.feels[aroma], AROMA_NAMES.get(aroma)].filter(Boolean).join(" ")
      } 향이 나요`
      : null;
    return pickOf(
      undefined,
      region,
      `${st.name}${label ? `(${label})` : ""}`,
      said,
    );
  });
}

/** 이번 술을 기준으로: each liked thing kept, each burden turned. */
function directionsOf(next: NextChoice): GuideDirection[] {
  return [
    ...next.keep.flatMap((s) => {
      const word = liked(s);
      return word ? [{ word, change: "keep" as const }] : [];
    }),
    ...next.adjust.flatMap((a) => {
      // 베리 향 ↓ as well as 단맛 ↓: an aroma to turn is a direction too.
      const word = burden(a.subject) ??
        (a.subject.domain === "aroma" ? liked(a.subject) : null);
      if (!word) return [];
      return [{
        word,
        change: a.direction === "higher" ? "higher" as const : "lower" as const,
      }];
    }),
  ];
}

/** The guide for one card, or null when nothing in the dictionary fits it. */
export function writeGuide(facts: CardFacts): Guide | null {
  const next = facts.summary.next_choice;
  const record = recordLevels(facts.product_facts);
  const wants = wanted(next, record);
  const adjust = next.adjust.filter((a) => burden(a.subject));
  const adjusted = wants.flatMap((w) =>
    "axis" in w && (w.adjust || w.floor) ? [w] : []
  );
  if (adjust.length && !adjusted.length) return null;

  const likedWords = next.keep.flatMap((s) => liked(s) ?? []);
  if (!likedWords.length && !adjusted.length) return null;

  const styleKeys = facts.product_facts.flatMap((p) =>
    p.fact.type === "style" ? [p.fact.key] : []
  );
  const category = facts.record.category ?? "";
  const kindRow = terms("kind").find((t) => styleKeys.includes(t.key));
  const kind = kindRow ? styleOf(kindRow) : null;
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
    NB: turnedPhrase(adjust),
    K: kindRow?.names?.ko ?? "술",
  };

  let shape: Shape = SHAPES[category] ?? "E";
  // 증류식 소주 reads like a cask spirit: methods, the label word, directions.
  if (kindRow?.key === "distilled_soju") shape = "C";

  // 내 취향 기준: every kind shows what the reader keeps and turns.
  const directions = directionsOf(next);
  if (shape === "A" && styleKeys.some((k) => k.includes("sparkling"))) {
    return writeSparklingGuide(
      facts,
      styleKeys,
      wants,
      adjust,
      slots,
      directions,
    ) ?? labelGuide(
      fill(headFor(adjust, isBalanced(facts), !!slots.P), slots),
      cuePicks(chooseCues(next, record, adjust, cues, 2), slots, true),
      specLevels(
        facts.product_facts,
        adjust,
        new Set(
          wants.flatMap((w) =>
            "axis" in w && !w.adjust && !w.near ? [w.axis] : []
          ),
        ),
        SPARKLING_SPEC,
      ),
      directions,
      WINE_TIP,
    );
  }

  const skipAxes = new Set(adjusted.map((w) => w.axis));
  const skipAromas = new Set(
    next.keep.flatMap((s) => s.domain === "aroma" ? [s.key] : []),
  );
  const keptAxes = new Set(
    wants.flatMap((w) => "axis" in w && !w.adjust && !w.near ? [w.axis] : []),
  );
  let picked = null;
  let styles: Style[] = [];
  if (shape !== "E") {
    const all = pool(shape, category);
    const colors = new Set([
      ...all.filter((s) => styleKeys.includes(s.key)).flatMap((s) => s.colors),
      ...(kind?.colors ?? []),
    ]);
    styles = all
      .filter((s) => !styleKeys.includes(s.key))
      .filter((s) => !colors.size || s.colors.some((c) => colors.has(c)))
      .filter((s) => shape !== "A" || sameShape(s, styleKeys))
      .filter((s) => shape !== "B" || near(s.abv, kind?.abv ?? null))
      // A cask or method without aromas reads as a bare level ("묵직한 특징이 있어요").
      .filter((s) => shape !== "C" || s.aromas.length > 0);
    picked = shape === "C"
      ? chooseCasks(styles, wants, skipAromas)
      : choose(styles, wants, skipAxes, skipAromas);
  }
  const head = fill(headFor(adjust, isBalanced(facts), !!slots.P), slots);
  // Whisky and traditional labels always print the 도수; the marks say which to look for.
  const abvRow = shape === "C" || shape === "D"
    ? abvLevel(facts, adjust, keptAxes, kind?.abv?.[0] ?? null)
    : null;

  if (shape === "D") {
    // A chip is a word printed on the label; a number is the marks' job.
    const picks = chooseCues(
      next,
      record,
      adjust,
      cues,
      2,
      new Set(abvRow ? ["alcohol_presence"] : []),
    )
      .map((c) => labelWords(c))
      .filter((words) => words.includes("'"))
      .map((words) => pickOf(undefined, undefined, fill(words, slots)));
    const levels = [
      ...specLevels(facts.product_facts, adjust, keptAxes, TRADITIONAL_SPEC),
      ...(abvRow ? [abvRow] : []),
    ];
    if (!picks.length && !directions.length) return null;
    return guideOf(head, {
      picks,
      tip: levels.length ? LABEL_TIP : null,
      levels,
      directions,
    });
  }

  if (shape === "C") {
    const casks = picked
      ? [picked.first.s, ...(picked.second ? [picked.second.s] : [])]
      : [];
    // The 도수 mark already says the strength: no cue about it twice.
    const cueRows = chooseCues(
      next,
      record,
      adjust,
      cues,
      2 - casks.length,
      new Set(abvRow ? ["alcohol_presence"] : []),
    );
    const picks = [
      ...caskPicks(casks, [...skipAromas], category),
      ...cuePicks(cueRows, slots, casks.length === 0),
    ];
    if (!picks.length && !directions.length) return null;
    return guideOf(head, {
      picks,
      tip: picks.length ? CASK_TIP : null,
      levels: abvRow ? [abvRow] : [],
      directions,
    });
  }
  // A grade two bands off the bottle would send a 곡물 향 drinker to 긴조: the label numbers say it better.
  if (shape === "B" && picked && picked.first.score <= FAR / 2) picked = null;
  if (!picked) {
    if (shape !== "A" && shape !== "B") return null;
    // No grape or grade fits: the kind's own label words, then the marks.
    return labelGuide(
      shape === "B"
        ? fill(headFor(adjust, isBalanced(facts), !!slots.P), {
          ...slots,
          K: "사케",
        })
        : head,
      cuePicks(
        shape === "A"
          ? chooseCues(next, record, adjust, cues, 2)
          : sakeCues(next, record, adjust, cues),
        slots,
        true,
      ),
      shape === "B"
        ? sakeLevels(facts.product_facts, adjust)
        : specLevels(facts.product_facts, adjust, keptAxes, WINE_SPEC),
      directions,
      shape === "B" ? SAKE_TIP : WINE_TIP,
    );
  }

  if (shape === "A") {
    const levels = specLevels(facts.product_facts, adjust, keptAxes, WINE_SPEC);
    return guideOf(head, {
      picks: wineKeywords(styles, wants),
      tip: levels.length ? WINE_TIP : null,
      levels,
      directions,
    });
  }
  // B: the sister grades in one chip and the label bands.
  const top = [picked.first.s, ...(picked.second ? [picked.second.s] : [])];
  // The chip names other grades, so the head names the kind as a whole: 사케.
  return guideOf(
    fill(headFor(adjust, isBalanced(facts), !!slots.P), {
      ...slots,
      K: "사케",
    }),
    {
      picks: [gradePick(top, [...skipAromas])],
      tip: SAKE_TIP,
      levels: sakeLevels(facts.product_facts, adjust),
      directions,
    },
  );
}

/**
 * The label cues that answer the card: the burdens first, never a cue that
 * undoes one, then the liked levels that sit high or low. At most [limit], no
 * two with the same label words, none on an axis in [skipAxes].
 */
function chooseCues(
  next: NextChoice,
  record: Levels,
  adjust: readonly Adjust[],
  cues: readonly Cue[],
  limit: number,
  skipAxes: ReadonlySet<string> = new Set(),
): Cue[] {
  const asks: { axis: string; direction: "lower" | "higher" }[] = [];
  for (const a of adjust) {
    const axis = axisOf(a.subject)?.axis;
    if (axis) {
      asks.push({
        axis,
        direction: a.direction === "higher" ? "higher" : "lower",
      });
    }
  }
  for (const s of next.keep) {
    const target = axisOf(s);
    const band = target && (target.band ?? record[target.axis]);
    const dir = band && direction(band);
    if (target && dir && !asks.some((x) => x.axis === target.axis)) {
      asks.push({ axis: target.axis, direction: dir });
    }
  }
  const undoes = (c: Cue) =>
    cues.some((o) =>
      o.cue === c.cue &&
      asks.slice(0, adjust.length).some((x) =>
        x.axis === o.axis && x.direction !== o.direction
      )
    );
  const chosen: Cue[] = [];
  for (const ask of asks) {
    if (chosen.length >= limit) break;
    if (skipAxes.has(ask.axis)) continue;
    const cue = cues.find((c) =>
      c.axis === ask.axis && c.direction === ask.direction && !undoes(c) &&
      !chosen.some((o) => labelWords(o) === labelWords(c))
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
function sakeCues(
  next: NextChoice,
  record: Levels,
  adjust: readonly Adjust[],
  cues: readonly Cue[],
): Cue[] {
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
    const cue = cues.find((c) =>
      c.aroma && c.direction === ask.direction && kin(c.aroma, ask.aroma) &&
      !chosen.includes(c)
    );
    if (cue && chosen.length < 2) chosen.push(cue);
  }
  const words = cues.filter((c) => c.axis && !c.cue.includes("숫자"));
  for (const c of chooseCues(next, record, adjust, words, 2 - chosen.length)) {
    if (!chosen.some((o) => labelWords(o) === labelWords(c))) chosen.push(c);
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
