/**
 * 근거 찾기 · 정체: what the bottle is, as the causes of a taste. Every cause
 * is a row of the bottle's own drink file (its kind, wine style, grape, label
 * word, making, producer, age band), with what that row says the drink is
 * usually like. The rank says which causes speak first for this drink:
 *
 *   wine     the grape and the wine style lead, which one by the case (old
 *            world with its own grape: the style; new world: the grape; a
 *            grape the style is not made of: the grape, the style only its
 *            climate); then making and label words, the producer, the kind.
 *            A fortified wine is made sweet or dry by its making: the kind
 *            and the style come before the grape.
 *   whisky   the kind, label words and the casks, the age band, the
 *            distillery, the grain
 *   sake     the grade (kind), label words and the processes, the brewery,
 *            the rice
 *   전통주    the kind, label words and the ingredients, the processes and
 *            ageing, the maker
 *
 * The bottle's strength is a cause too, where it stands in the upper or the
 * lower bands of its kind: of the heat it leaves and of its weight. A whisky's
 * lower bands are its legal least (40%), so only its upper ones speak.
 *
 * A distilled drink keeps the aromas of what it was made from, not its sugar,
 * acid or weight: of a 소주's ingredients only the aromas are read.
 *
 * Nothing is guessed: a cause the bottle does not state, or that the
 * dictionary does not know, is not there. A cause must tell this bottle
 * from others of its drink: a making row every bottle of the drink has
 * (`given`) is none.
 *
 * The identity also holds the relations of the drink that this bottle
 * meets: every row a relation is of is the bottle's, and the bottle is old
 * or strong enough where the relation asks.
 */
import {
  type AgeNode,
  type DrinkFile,
  drinkFile,
  type GrapeNode,
  type KindNode,
  type LabelWordNode,
  type Level,
  placeOf,
  type ProducerNode,
  type Relation,
  type StyleNode,
  type TagNode,
} from "../dictionary/dictionary.ts";
import { alcoholLevelFromAbv } from "../facts/abv_levels.ts";
import type { BottleFacts } from "../prepare/bottle.ts";

export type FactorKind =
  | "kind"
  | "grape"
  | "region_style"
  | "label_word"
  | "making"
  | "cask"
  | "age"
  | "producer"
  | "ingredient"
  | "abv";

/** Where the cause is written: on the bottle, or only in its style's row. */
export type CauseOn = "bottle" | "style";

export type Side = "none" | "low" | "middle" | "high";

/** What a row says of one axis: a step, or that it runs several ways. */
export type Tendency =
  | { varies: false; step: number; side: Side }
  | { varies: true };

export type Factor = {
  factor: FactorKind;
  key: string;
  ko: string;
  rank: number;
  on: CauseOn;
  /** Its tendency by dictionary axis (astringency, carbonation, finish_character, …). */
  taste: Readonly<Record<string, Tendency>>;
  /** The aroma words the row names, by where they come from (material, cask, ripeness, …). */
  aromas: Readonly<Record<string, readonly string[]>>;
  /** How strongly it smells, when the row says. */
  aroma_strength?: Tendency;
  /** A wine style's place climate (cool, moderate, warm, hot). */
  climate?: string;
  /** A distillery's peat, a sake process's or a cask's own word, kept as said. */
  peat?: string;
  /** Why the row tastes so, as the dictionary says it. */
  why?: string;
  /** A grape from a cooler or a warmer place: which, and what it is like there. */
  in_climate?: { side: "cooler" | "warmer"; text: string };
};

export type WineCase =
  | "old_world_own_grape"
  | "new_world_own_grape"
  | "other_grape"
  | "grape_only"
  | "style_only"
  | "neither";

export type Lead = "grape" | "region" | "combo" | "kind";

export type Identity = {
  drink: string;
  kind: string | null;
  /** The name a card calls the bottle by: style, grape, both, or its kind. */
  identity_key: string;
  lead: Lead;
  wine_case?: WineCase;
  /** Every cause the bottle has, in rank order. */
  factors: readonly Factor[];
  /** The relations of the drink this bottle meets. */
  relations: readonly Relation[];
};

/** The countries whose wine is named first by its place (설계 8-4). */
const OLD_WORLD = new Set([
  "fr",
  "it",
  "es",
  "pt",
  "de",
  "at",
  "hu",
  "gr",
  "ge",
  "ch",
  "si",
]);

const FORTIFIED = new Set([
  "port_wine",
  "sherry_wine",
  "madeira_wine",
  "fortified_wine",
  "vermouth",
]);

const WORD_STEP: Readonly<Record<string, number>> = {
  none: 1,
  low: 2,
  mid: 3,
  high: 4,
};

/** The side of a step, as an answer is read: 1–2 low, 3 middle, 4–5 high. */
export function sideOf(step: number): Side {
  return step < 3 ? "low" : step > 3 ? "high" : "middle";
}

/** A row's level as a tendency; null when it says nothing. */
export function tendencyOf(level: Level | undefined): Tendency | null {
  if (level === null || level === undefined) return null;
  if (level === "varies") return { varies: true };
  if (typeof level === "number") {
    return { varies: false, step: level, side: sideOf(level) };
  }
  const step = WORD_STEP[level];
  if (step === undefined) return null;
  return {
    varies: false,
    step,
    side: level === "none" ? "none" : sideOf(step),
  };
}

function tasteOf(
  taste: Readonly<Record<string, Level>> | undefined,
): Record<string, Tendency> {
  const out: Record<string, Tendency> = {};
  for (const [axis, level] of Object.entries(taste ?? {})) {
    const tendency = tendencyOf(level);
    if (tendency) out[axis] = tendency;
  }
  return out;
}

type Row = {
  key: string;
  ko: string;
  taste?: Readonly<Record<string, Level>>;
  aromas?: Readonly<Record<string, readonly string[]>>;
  aroma_strength?: Level;
  why?: string;
};

function factorOf(
  factor: FactorKind,
  row: Row,
  rank: number,
  on: CauseOn,
  extra: Partial<Factor> = {},
): Factor {
  const strength = tendencyOf(row.aroma_strength);
  return {
    factor,
    key: row.key,
    ko: row.ko,
    rank,
    on,
    taste: tasteOf(row.taste),
    aromas: row.aromas ?? {},
    ...(strength ? { aroma_strength: strength } : {}),
    ...(row.why ? { why: row.why } : {}),
    ...extra,
  };
}

/* ------------------------------------------------------------ lookups */

function kindOf(file: DrinkFile, key: string | null): KindNode | null {
  return file.kinds.find((k) => k.key === key) ?? null;
}

function styleOf(file: DrinkFile, key: string | null): StyleNode | null {
  if (!key) return null;
  for (const kind of file.kinds) {
    const style = kind.styles.find((s) => s.key === key);
    if (style) return style;
  }
  return null;
}

/** A grape by its key or one of the other keys the catalog writes it with. */
export function grapeOf(file: DrinkFile, key: string): GrapeNode | null {
  return (file.grapes ?? []).find((g) =>
    g.key === key || (g.also_keys ?? []).includes(key)
  ) ?? null;
}

const fold = (s: string) => s.trim().toLowerCase();

function producerOf(file: DrinkFile, name: string | null): ProducerNode | null {
  if (!name) return null;
  const wanted = fold(name);
  return file.producers.find((p) =>
    [p.ko, p.en].some((n) => n && fold(n) === wanted)
  ) ?? null;
}

/**
 * A making row of the drink as a cause, and the part it belongs to. Null
 * for a row the drink does not have or that every bottle of it has.
 */
function makingRow(
  file: DrinkFile,
  key: string,
): { item: TagNode; part: string } | null {
  for (const [part, groups] of Object.entries(file.making)) {
    for (const group of groups) {
      const item = group.items.find((i) => i.key === key);
      if (!item) continue;
      return item.given ? null : { item, part };
    }
  }
  return null;
}

/**
 * The bottle's stated strength as a cause, where it stands in the upper two
 * or the lower two of its kind's five bands: more alcohol leaves more heat
 * and more weight, less of it less. The middle band says nothing.
 */
function abvFactor(bottle: BottleFacts, rank: number): Factor | null {
  if (bottle.abv?.of !== "bottle") return null;
  const found = alcoholLevelFromAbv(
    bottle.abv.percent,
    bottle.style_key,
    bottle.category,
  );
  if (!found || found.level === 3) return null;
  const level = found.level > 3 ? "high" : "low";
  // A whisky is bottled at 40% unless its maker chose more: the least it may
  // be says nothing of the bottle, only a strength above the usual does.
  if (level === "low" && bottle.category === "whisky") return null;
  return factorOf(
    "abv",
    {
      key: `abv_${level}`,
      ko: `도수 ${bottle.abv.percent}%`,
      // A whisky bottled weak finishes sooner, one bottled strong lingers.
      taste: {
        spice: level,
        body: level,
        ...(bottle.category === "whisky" ? { finish_length: level } : {}),
      },
    },
    rank,
    "bottle",
  );
}

const WARMER = ["warm", "hot"];

/** What the grape is like in the bottle's climate, where the dictionary says. */
function inClimate(
  grape: GrapeNode,
  climate: string | undefined,
): Factor["in_climate"] {
  const by = grape.by_climate;
  if (!by || !climate) return undefined;
  const warmer = by.warmer_from === "hot"
    ? climate === "hot"
    : WARMER.includes(climate);
  return warmer
    ? { side: "warmer", text: by.warmer }
    : { side: "cooler", text: by.cooler };
}

/**
 * The relations of the drink the bottle meets: every row a relation is of
 * is one of the bottle's (its causes, its kind, every grape of its blend),
 * and the bottle is of the kind, the age and the strength it asks.
 */
function relationsOf(
  file: DrinkFile,
  bottle: BottleFacts,
  factors: readonly Factor[],
): Relation[] {
  const has = new Set<string>(factors.map((f) => f.key));
  if (bottle.style_key) has.add(bottle.style_key);
  for (const key of bottle.grapes) has.add(grapeOf(file, key)?.key ?? key);
  const abv = bottle.abv?.of === "bottle" ? bottle.abv.percent : null;
  return (file.relations ?? []).filter((r) =>
    r.of.every((key) => has.has(key)) &&
    (!r.kinds || r.kinds.includes(bottle.style_key ?? "")) &&
    (r.age_from === undefined ||
      (bottle.age_years !== null && bottle.age_years >= r.age_from)) &&
    (r.abv_from === undefined || (abv !== null && abv >= r.abv_from))
  );
}

/** The climate of a wine place, or of the nearest place above it that states one. */
function climateOf(key: string | null): string | undefined {
  for (let k = key; k;) {
    const place = placeOf("wine", k);
    if (!place) return undefined;
    const climate = place.hints?.climate;
    if (typeof climate === "string") return climate;
    k = place.parent ?? null;
  }
  return undefined;
}

function countryOf(key: string | null): string | null {
  let country: string | null = null;
  for (let k = key; k;) {
    const place = placeOf("wine", k);
    if (!place) break;
    country = k;
    k = place.parent ?? null;
  }
  return country;
}

/* --------------------------------------------------------- label words */

/** A name as a label word is looked for in it: hyphens and slashes are spaces. */
function labelText(s: string): string {
  return ` ${fold(s).replace(/[-/]/g, " ").replace(/\s+/g, " ")} `;
}

/** Where a word stands on a name, word by word (spaces and brackets bound it). */
function spansOf(text: string, word: string): [number, number][] {
  const out: [number, number][] = [];
  const w = labelText(word).trim();
  if (!w) return out;
  const bound = (c: string | undefined) =>
    c === undefined || /[\s()[\],.]/.test(c);
  for (let i = text.indexOf(w); i >= 0; i = text.indexOf(w, i + 1)) {
    if (bound(text[i - 1]) && bound(text[i + w.length])) {
      out.push([i, i + w.length]);
    }
  }
  return out;
}

/**
 * The label words a bottle's name prints. Where two overlap the longer wins
 * (extra dry is not dry); a word meant for other kinds is not read; of the
 * words that say sweetness, a grade of ripeness gives way to one of the
 * wine's sugar (Kabinett trocken is dry). 두 is never read: it is a word of
 * Portuguese names (Quinta do) as often as doux.
 */
export function labelWordsOf(
  file: DrinkFile,
  name: string,
  kind: string | null,
): LabelWordNode[] {
  const text = labelText(name);
  const found: { word: LabelWordNode; span: [number, number] }[] = [];
  for (const word of file.label_words) {
    if (word.kinds && (!kind || !word.kinds.includes(kind))) continue;
    const spellings = [word.ko, word.label, ...(word.find ?? [])]
      .filter((s): s is string => !!s && s !== "두");
    for (const spelling of spellings) {
      for (const span of spansOf(text, spelling)) found.push({ word, span });
    }
  }
  found.sort((a, b) => (b.span[1] - b.span[0]) - (a.span[1] - a.span[0]));
  const kept: typeof found = [];
  for (const f of found) {
    const overlaps = kept.some((k) =>
      f.span[0] < k.span[1] && k.span[0] < f.span[1]
    );
    if (!overlaps && !kept.some((k) => k.word.key === f.word.key)) kept.push(f);
  }
  const words = kept.map((k) => k.word);
  const sugar = words.some((w) =>
    !w.ripeness_grade && w.taste?.sweetness != null
  );
  return words.filter((w) => !(sugar && w.ripeness_grade));
}

/* -------------------------------------------------------------- drinks */

function wineIdentity(file: DrinkFile, bottle: BottleFacts): Identity {
  const kind = kindOf(file, bottle.style_key);
  const style = styleOf(file, bottle.region_entry);
  const grapeKey = bottle.grapes[0] ?? null;
  const grape = grapeKey ? grapeOf(file, grapeKey) : null;
  const fortified = FORTIFIED.has(bottle.style_key ?? "");
  const climate = climateOf(style?.place ?? null);
  const country = countryOf(style?.place ?? null);
  const ownGrape = !!(style && grape &&
    style.grapes.some((g) =>
      g === grape.key || (grape.also_keys ?? []).includes(g)
    ));

  let wineCase: WineCase;
  if (style && grape) {
    wineCase = !ownGrape
      ? "other_grape"
      : OLD_WORLD.has(country ?? "")
      ? "old_world_own_grape"
      : "new_world_own_grape";
  } else wineCase = grape ? "grape_only" : style ? "style_only" : "neither";

  const factors: Factor[] = [];
  const styleFactor = (rank: number) =>
    style &&
    factorOf("region_style", style, rank, "bottle", {
      ...(climate ? { climate } : {}),
      // Of a grape the style is not made of, the style says only its climate.
      ...(wineCase === "other_grape" ? { taste: {}, aromas: {} } : {}),
    });
  const grapeFactor = (rank: number) => {
    if (!grape) return null;
    const there = inClimate(grape, climate);
    return factorOf(
      "grape",
      grape,
      rank,
      "bottle",
      there ? { in_climate: there } : {},
    );
  };
  let lead: Lead;
  let identityKey: string;
  switch (wineCase) {
    case "old_world_own_grape":
      lead = "region";
      identityKey = `style:${style!.key}`;
      break;
    case "new_world_own_grape":
      lead = "grape";
      identityKey = `combo:${style!.key}+${grape!.key}`;
      break;
    case "other_grape":
      lead = "combo";
      identityKey = `combo:${style!.key}+${grape!.key}`;
      break;
    case "grape_only":
      lead = "grape";
      identityKey = `grape:${grape!.key}`;
      break;
    case "style_only":
      lead = "region";
      identityKey = `style:${style!.key}`;
      break;
    default:
      lead = "kind";
      identityKey = `kind:${bottle.style_key ?? "wine"}`;
  }
  if (fortified) {
    // The making decides a fortified wine: its kind and style speak before the grape.
    if (kind) factors.push(factorOf("kind", kind, 1, "bottle"));
    const s = styleFactor(1);
    if (s) factors.push(s);
    const g = grapeFactor(2);
    if (g) factors.push(g);
  } else {
    const styleFirst = lead === "region";
    const s = styleFactor(styleFirst ? 1 : 2);
    const g = grapeFactor(styleFirst ? 2 : 1);
    for (const f of styleFirst ? [s, g] : [g, s]) if (f) factors.push(f);
  }
  for (const word of labelWordsOf(file, bottle.name, bottle.style_key)) {
    factors.push(factorOf("label_word", word, 3, "bottle"));
  }
  for (const key of bottle.processes) {
    const row = makingRow(file, key);
    if (row) factors.push(factorOf("making", row.item, 3, "bottle"));
  }
  for (const key of style?.making ?? []) {
    if (bottle.processes.includes(key) || wineCase === "other_grape") continue;
    const row = makingRow(file, key);
    if (row) factors.push(factorOf("making", row.item, 3, "style"));
  }
  const abv = abvFactor(bottle, 3);
  if (abv) factors.push(abv);
  const producer = producerOf(file, bottle.producer);
  if (producer) factors.push(factorOf("producer", producer, 4, "bottle"));
  if (kind && !fortified) factors.push(factorOf("kind", kind, 5, "bottle"));
  return {
    drink: "wine",
    kind: bottle.style_key,
    identity_key: identityKey,
    lead,
    wine_case: wineCase,
    factors,
    relations: relationsOf(file, bottle, factors),
  };
}

/** The age band of a whisky's stated years, for its kind. */
function ageOf(
  file: DrinkFile,
  kind: string | null,
  years: number | null,
): AgeNode | null {
  if (years === null || !kind) return null;
  return (file.ages ?? []).find((a) =>
    a.kinds.includes(kind) &&
    (a.years[0] === null || years >= a.years[0]) &&
    (a.years[1] === null || years <= a.years[1])
  ) ?? null;
}

/** The 전통주 kinds that are distilled. */
const DISTILLED = new Set(["distilled_soju", "diluted_soju"]);

const PEAT_STEP: Readonly<Record<string, number>> = {
  none: 1,
  light: 2,
  medium: 3,
  heavy: 4,
};

function otherIdentity(file: DrinkFile, bottle: BottleFacts): Identity {
  const drink = file.key;
  const kind = kindOf(file, bottle.style_key);
  const distilled = DISTILLED.has(bottle.style_key ?? "");
  const factors: Factor[] = [];
  if (kind) factors.push(factorOf("kind", kind, 1, "bottle"));
  // What the name prints of the bottle (카라구치, 하이 라이) is its own fact.
  for (const word of labelWordsOf(file, bottle.name, bottle.style_key)) {
    factors.push(factorOf("label_word", word, 2, "bottle"));
  }
  const rows = (keys: readonly string[]) =>
    keys.map((k) => makingRow(file, k)).filter((
      r,
    ): r is NonNullable<typeof r> => !!r);
  let casks: string[] = [];
  if (drink === "whisky") {
    for (const { item, part } of rows(bottle.processes)) {
      const isCask = part === "maturations";
      if (isCask) casks.push(item.key);
      factors.push(
        factorOf(isCask ? "cask" : "making", item, isCask ? 2 : 3, "bottle"),
      );
    }
    const age = ageOf(file, bottle.style_key, bottle.age_years);
    if (age) {
      factors.push(factorOf(
        "age",
        {
          key: age.key,
          ko: age.ko,
          aromas: age.aromas_more?.length ? { ageing: age.aromas_more } : {},
        },
        2.5,
        "bottle",
      ));
    }
    const producer = producerOf(file, bottle.producer);
    if (producer && !producer.bottler) {
      const peat = producer.peat ?? undefined;
      const step = peat ? PEAT_STEP[peat] : undefined;
      const taste: Record<string, Level> = { ...(producer.taste ?? {}) };
      if (peat === "varies") taste.peat = "varies";
      else if (step !== undefined) taste.peat = step;
      factors.push(
        factorOf(
          "producer",
          { ...producer, taste },
          3,
          "bottle",
          peat ? { peat } : {},
        ),
      );
    }
    for (const { item } of rows(bottle.ingredients)) {
      factors.push(factorOf("ingredient", item, 4, "bottle"));
    }
  } else if (drink === "sake") {
    for (const { item } of rows(bottle.processes)) {
      factors.push(factorOf("making", item, 2, "bottle"));
    }
    const producer = producerOf(file, bottle.producer);
    if (producer) factors.push(factorOf("producer", producer, 3, "bottle"));
    for (const { item } of rows(bottle.ingredients)) {
      factors.push(factorOf("ingredient", item, 4, "bottle"));
    }
  } else {
    for (const { item } of rows(bottle.ingredients)) {
      factors.push(
        distilled
          ? factorOf(
            "ingredient",
            {
              key: item.key,
              ko: item.ko,
              aromas: item.aromas,
            },
            2,
            "bottle",
          )
          : factorOf("ingredient", item, 2, "bottle"),
      );
    }
    for (const { item } of rows(bottle.processes)) {
      factors.push(factorOf("making", item, 3, "bottle"));
    }
    const producer = producerOf(file, bottle.producer);
    if (producer) factors.push(factorOf("producer", producer, 4, "bottle"));
  }
  const abv = abvFactor(bottle, 2);
  if (abv) factors.push(abv);
  factors.sort((a, b) => a.rank - b.rank);
  const kindKey = bottle.style_key ?? drink;
  casks = [...new Set(casks)];
  return {
    drink,
    kind: bottle.style_key,
    identity_key: drink === "whisky" && casks.length
      ? `kind:${kindKey}+cask:${casks[0]}`
      : `kind:${kindKey}`,
    lead: "kind",
    factors,
    // What two ingredients do together is of the taste they no longer give.
    relations: relationsOf(
      file,
      bottle,
      factors.filter((f) => !(distilled && f.factor === "ingredient")),
    ),
  };
}

/** The bottle's causes, from its own drink's file. Null for a bottle of no known drink. */
export function bottleIdentity(bottle: BottleFacts): Identity | null {
  const file = bottle.category ? drinkFile(bottle.category) : null;
  if (!file) return null;
  return file.key === "wine"
    ? wineIdentity(file, bottle)
    : otherIdentity(file, bottle);
}
