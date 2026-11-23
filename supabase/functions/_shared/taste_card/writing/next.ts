/**
 * 다음 방향: the last numbered section of the card. Each line is one
 * sentence that says what to choose next and what choosing so does (the
 * user's review, 2026-11-23: no sub-headings, and never a choice without
 * what it brings).
 *
 *   what to look for again   the causes of the bottle the liked reasons were
 *                            told by, as a label shows them, and the liked
 *                            taste in a shop's word: 아르헨티나 말벡, 15%
 *                            전후 풀바디를 선택하시면, 좋았던 묵직한
 *                            바디감을 그대로 가져갈 수 있어요. What gave the
 *                            minded thing is left out of it.
 *   what to turn to          for what was minded most, two rows of the
 *                            dictionary: 프랑스의 보졸레나 … 와인을
 *                            선택하시면, 높은 산미와 체리 향은 그대로
 *                            살리면서 흙 향은 줄일 수 있어요.
 *   what gave it             with nothing liked or nothing to turn to, what
 *                            such a drink is mostly like: 키안티 와인이나
 *                            산지오베제 품종은 산미가 대체로 높은 편이에요.
 *                            Never a grape or a place few bottles carry.
 *   what is alike            with nothing minded, two alike in what was
 *                            liked.
 *
 * The names to look for are in bold; the served card explains each as it
 * does a reason's words. A country is said in words, not by a flag.
 *
 * A clue is one a label or a shelf can answer: a method or a cask only with a
 * word a label prints for it, and nothing every bottle of the kind has (쌀 of
 * a 막걸리). A change is a row enough bottles of the bottle's own kind carry,
 * so it never leads out of the kind (주정강화 for a red wine). A wine's
 * methods are not counted on its bottles, so a wine is changed by its grape
 * or its place.
 *
 * A change is never one that turns the liked taste over (a lighter grape for
 * a reader who liked the weight). Everything is read from the dictionary and
 * the catalog counts; a card with nothing to say has no section.
 */
import { regionByKey, type Term, terms } from "../dictionary/dictionary.ts";
import type { EvidenceResult } from "../evidence/evidence.ts";
import type { FactorKind } from "../evidence/identity.ts";
import { GAUGE_LEVEL_DIMENSION, type GaugeAxis } from "../facts/facts.ts";
import {
  bottlesCarrying,
  type Carried,
  shelfOfKind,
} from "../facts/kind_place.ts";
import {
  type Borne,
  carriesAroma,
  ENOUGH_BOTTLES,
  ENOUGH_SHARE,
  EVERY_BOTTLE,
  isCounted,
  mostlyOnSide,
  rarelyOnSide,
  sparesAroma,
} from "../facts/name_counts.ts";
import type { Prepared } from "../prepare/prepare.ts";
import type { Selection } from "../selection/selection.ts";
import type { TasteCardNext, TasteCardNextLine } from "../service/types.ts";
import { senseNoun, tagName } from "./reasons.ts";
import { andJoin, josa } from "./korean.ts";
import { short } from "./words.ts";

const MOST_KEPT = 3;
const MOST_CAUSES = 2;
const MOST_CHANGED = 2;

/** What the catalog counts a dictionary type as. */
const COUNTED: Readonly<Record<string, Carried>> = {
  grape: "grapes",
  regional_style: "styles",
  process: "made",
  maturation: "made",
  ingredient: "ingredients",
  kind: "kinds",
};

/** The dictionary type a cause of the bottle is a row of. */
const TYPE_OF: Readonly<Partial<Record<FactorKind, readonly string[]>>> = {
  grape: ["grape"],
  region_style: ["regional_style"],
  producer: ["producer"],
  cask: ["maturation", "process"],
  making: ["process", "maturation"],
  label_word: ["label_word"],
  kind: ["kind"],
  ingredient: ["ingredient"],
};

/** The dictionary's axis of a gauge. */
const DICT_AXIS: Readonly<Partial<Record<GaugeAxis, string>>> = {
  tannin: "astringency",
  sparkling: "carbonation",
};
const dictAxis = (axis: GaugeAxis) => DICT_AXIS[axis] ?? axis;

type Side = "high" | "low";

/** A liked taste as a shop says it. */
const SHOP_WORD: Readonly<
  Partial<Record<GaugeAxis, readonly [high: string | null, low: string | null]>>
> = {
  // Only words a label, a menu or a shop's filter carries: "여운이 긴 스타일"
  // cannot be looked for (the user's review, 2026-11-21).
  sweetness: [null, "드라이"],
  body: ["풀바디", "라이트 바디"],
  peat: ["피트 위스키", "논피트"],
};

/** The slots a change is looked for in, by drink: the dictionary type and what the catalog counts it as. */
const SLOTS: Readonly<
  Record<string, readonly (readonly [type: string, counted: Carried])[]>
> = {
  wine: [["grape", "grapes"], ["regional_style", "styles"]],
  whisky: [["maturation", "made"], ["process", "made"]],
  sake: [["kind", "kinds"], ["process", "made"], ["ingredient", "ingredients"]],
};

/**
 * The drinks no direction is written for. The catalog tells the bottles of a
 * Korean traditional kind apart by nothing a shelf names: nearly every one is
 * made the same way of the same things, a brewery makes two of them, and the
 * only wider name is the kind itself. What was left to write was the answer
 * said back (풀바디 for a full body) or the kind just drunk (the user's
 * review, 2026-11-23).
 */
const UNTOLD: ReadonlySet<string> = new Set(["korean_traditional"]);

type Row = Term & {
  categories?: readonly string[];
  taste?: Readonly<Record<string, { level?: string }>>;
  hints?: {
    label_words?: readonly string[];
    color?: string;
    colors?: readonly string[];
  };
  extra?: { region_key?: string; country?: string };
};

const rowsOf = (type: string) => terms(type) as readonly Row[];
const ROW = new Map<string, Row>(
  Object.values(TYPE_OF).flat().flatMap((type) =>
    rowsOf(type).map((r) => [`${type}:${r.key}`, r] as const)
  ),
);

function rowOf(factor: FactorKind, key: string): Row | null {
  for (const type of TYPE_OF[factor] ?? []) {
    const row = ROW.get(`${type}:${key}`);
    if (row) return row;
  }
  return null;
}

/** The side a row's taste stands on, or null when it says nothing or the middle. */
function sideOn(row: Row, axis: GaugeAxis): Side | null {
  const level = row.taste?.[dictAxis(axis)]?.level;
  return level === "high"
    ? "high"
    : level === "low" || level === "none"
    ? "low"
    : null;
}

const bare = (name: string) => name.replace(/\s*\([^)]*\)/g, "").trim();
const latin = (word: string | undefined) =>
  word && /^[\x20-\x7eÀ-ɏ]+$/.test(word) ? word : null;

/** The places a wine style sits in, its own first and its country last. */
function placesOf(row: Row): string[] {
  const keys: string[] = [];
  let region = row.extra?.region_key
    ? regionByKey.get(row.extra.region_key)
    : undefined;
  for (; region; region = regionByKey.get(region.parent ?? "")) {
    keys.push(region.key);
  }
  return keys;
}

/** The country a wine style sits in: the root of its region's tree. */
function countryOfStyle(row: Row): string | null {
  const key = placesOf(row).at(-1);
  return key ? regionByKey.get(key)!.names.ko : null;
}

/** A row as a label shows it, its name in bold: **메를로**, **셰리 캐스크**(Sherry Cask). */
function nameOf(row: Row): string {
  const ko = bare(row.names.ko);
  const label = row.type === "process" || row.type === "maturation"
    ? latin(row.hints?.label_words?.[0])
    : null;
  return label ? `**${ko}**(${label})` : `**${ko}**`;
}

/** Something the reader answered that a row of the dictionary can carry: a taste on a side, or an aroma. */
type Thing =
  | { kind: "gauge"; axis: GaugeAxis; side: Side; level: number; name: string }
  | { kind: "aroma"; key: string; name: string };

/** Whether a row is such a drink: 타닌이 높은 품종, 흙 향이 대표 향인 산지. */
function carries(row: Row, thing: Thing): boolean {
  return thing.kind === "gauge"
    ? sideOn(row, thing.axis) === thing.side
    : (row.aromas ?? []).some((a) => a.key === thing.key);
}

/** The grapes a regional style is made of. */
const grapesOfStyle = (row: Row): readonly string[] =>
  (row.hints as { grapes?: { keys?: readonly string[] } } | undefined)?.grapes
    ?.keys ?? [];

export function writeNext(
  prepared: Prepared,
  found: EvidenceResult,
  selection: Selection,
): TasteCardNext | null {
  const { category, style_key, abv } = prepared.bottle;
  if (category && UNTOLD.has(category)) return null;
  const byId = new Map(found.evidence.map((e) => [e.id, e]));
  const { gauges, aromas } = prepared.interpretation;
  const gaugeOf = (ref: string) => gauges.find((g) => g.answer_ref === ref);
  /** An answer as a thing a row can carry; a middle step is none. */
  const thingOf = (ref: string): Thing | null => {
    const g = gaugeOf(ref);
    if (g) {
      return g.side === "middle" ? null : {
        kind: "gauge",
        axis: g.axis,
        side: g.side as Side,
        level: g.level,
        name: tagName(g.axis, g.level),
      };
    }
    const a = aromas.find((x) => x.answer_ref === ref);
    return a
      ? { kind: "aroma", key: a.aroma, name: `${short(a.aroma)} 향` }
      : null;
  };
  const own = found.identity.causes;
  const ownRows = own.flatMap((c) => rowOf(c.factor, c.key) ?? []);
  const style = ownRows.find((r) => r.type === "regional_style");
  const country = style ? countryOfStyle(style) : null;
  const mainGrape = prepared.bottle.grapes[0];
  const shelf = shelfOfKind(style_key, category);
  /** The part of the kind's bottles that carry a row; null where they are not counted. */
  const shareOf = (row: Row) => {
    const counted = COUNTED[row.type];
    const n = counted ? bottlesCarrying(counted, row.key, shelf) : null;
    return n && n.of ? { bottles: n.bottles, share: n.bottles / n.of } : null;
  };
  /** A clue a label or a shelf can answer, and that not every bottle of the kind is. */
  const findable = (row: Row) => {
    if (!/[가-힣]/.test(row.names.ko)) return false;
    if (row.type === "process" || row.type === "maturation") {
      return !!row.hints?.label_words?.length;
    }
    if (row.type === "ingredient") {
      // An ingredient is a clue when its bottles are counted and are a small part of the kind.
      const n = shareOf(row);
      return !!n && n.share <= EVERY_BOTTLE / 2;
    }
    return true;
  };

  /**
   * What the catalog's bottles of a row say of a thing: that the row has it
   * (most of them, or an aroma clearly more often than the kind) or lacks it
   * (few of them). The dictionary's row is one value for all of them, so a
   * row is kept for a taste, or turned to from one, only when its bottles do
   * not say otherwise; on a taste the catalog keeps no number for (피트,
   * 감칠맛) the row stands.
   */
  const bottlesSay = (row: Row, thing: Thing, of: "has" | "lacks"): Borne => {
    const what = COUNTED[row.type];
    if (!what) return "uncounted";
    const name = { what, key: row.key };
    // A name whose bottles are too few to count bears nothing out.
    if (!isCounted(name, shelf)) return "no";
    if (thing.kind === "aroma") {
      return (of === "has" ? carriesAroma : sparesAroma)(
        name,
        shelf,
        thing.key,
      );
    }
    return (of === "has" ? mostlyOnSide : rarelyOnSide)(
      name,
      shelf,
      GAUGE_LEVEL_DIMENSION[thing.axis],
      thing.side,
    );
  };
  /** A row has a thing: its row of the dictionary says so and its bottles do not say otherwise. */
  const holds = (row: Row, thing: Thing) =>
    carries(row, thing) && bottlesSay(row, thing, "has") !== "no";
  /** A row is free of a thing, as far as its bottles say. */
  const spares = (row: Row, thing: Thing) =>
    bottlesSay(row, thing, "lacks") !== "no";

  /* -------------------------------------------- what was liked and minded */
  const likedThings = [
    ...selection.liked.reasons.flatMap((r) => r.answers),
    ...selection.liked.untold,
  ].flatMap((ref) => thingOf(ref) ?? []);
  const likedGauges = likedThings.flatMap((t) => t.kind === "gauge" ? [t] : []);
  const mindedThings = [
    ...selection.burden.reasons.flatMap((r) => r.answers.slice(0, 1)),
    ...selection.burden.untold,
  ].flatMap((ref) => thingOf(ref) ?? []);

  /* ------------------------------------------------- what to look for again */
  /** A clue, the row it names, and the liked thing it was kept for. */
  type Kept = {
    text: string;
    row: Row | null;
    plain?: string;
    of: Thing | null;
  };
  let keep: Kept[] = [];
  let strengthCaused = false;
  for (const reason of selection.liked.reasons) {
    const lead = byId.get(reason.evidence[0]);
    if (lead?.causes.some((c) => c.factor === "abv")) strengthCaused = true;
    // The maker that says the same of the taste comes before the cause the
    // reason was told by: 라프로익, then 피트 처리 맥아.
    const answer = lead?.answer.kind === "gauge" ? lead.answer : null;
    const named = (lead?.causes ?? []).filter((c) =>
      c.factor === "producer" &&
      (!answer || !c.tendency ||
        (c.tendency.step > 3 ? "high" : c.tendency.step < 3 ? "low" : "") ===
          answer.side)
    );
    for (
      const told of [...named, ...(reason.told_by ? [reason.told_by] : [])]
    ) {
      const row = rowOf(told.factor, told.key);
      // The kind just drunk is no direction: 싱글 몰트 위스키 is 1,774
      // bottles, a third of them with the vanilla that was liked.
      if (!row || !findable(row) || told.factor === "kind") continue;
      const plain = nameOf(row);
      // A grape is looked for with its country (아르헨티나 말벡), unless the
      // place is already a clue of its own.
      const placed = row.type === "grape" && country &&
        !keep.some((k) => k.row?.type === "regional_style");
      const text = placed ? `${country} ${plain}` : plain;
      if (keep.length < MOST_CAUSES && !keep.some((k) => k.plain === plain)) {
        keep.push({ text, row, plain, of: thingOf(reason.answers[0]) });
      }
    }
  }
  const liked = likedGauges[0];
  if (liked) {
    const word = SHOP_WORD[liked.axis]?.[liked.side === "high" ? 0 : 1];
    const strength = strengthCaused && abv?.of === "bottle"
      ? `${Math.round(abv.percent)}% 전후 `
      : "";
    if (word) {
      keep.push({ text: `${strength}**${word}**`, row: null, of: liked });
    }
  }

  /* ------------------------------------------------------ what to change by */
  const mine = new Set(own.map((c) => c.key));
  const colors = new Set(
    [
      style?.hints?.color,
      ...prepared.bottle.grapes.flatMap((key) =>
        ROW.get(`grape:${key}`)?.hints?.colors ?? []
      ),
    ].filter(Boolean),
  );
  const ofColor = (row: Row) =>
    !colors.size ||
    (row.type === "grape"
      ? (row.hints?.colors ?? []).some((c) => colors.has(c))
      : row.type !== "regional_style" || colors.has(row.hints?.color));
  /** The liked things a row carries, the minded taste's own gauge aside. */
  const keptBy = (row: Row, minded: Thing | null) =>
    likedThings.filter((t) =>
      !(minded?.kind === "gauge" && t.kind === "gauge" &&
        t.axis === minded.axis) && holds(row, t)
    );
  /** Never a row that turns a liked taste over. */
  const turnsNone = (row: Row, minded: Thing | null) =>
    likedGauges.every((g) => {
      const side = sideOn(row, g.axis);
      return (minded?.kind === "gauge" && g.axis === minded.axis) ||
        side === null || side === g.side;
    });
  type Ranked = {
    row: Row;
    kept: Thing[];
    same: number;
    near: number;
    bottles: number;
  };
  /** In how many tastes a row stands where the bottle's own of its slot does. */
  const nearOwn = (row: Row) => {
    const mine = ownRows.find((r) => r.type === row.type)?.taste ?? {};
    return Object.entries(mine).filter(([axis, t]) =>
      t.level && t.level === row.taste?.[axis]?.level
    ).length;
  };
  /**
   * The rows of a type to turn to, best first: enough bottles of the kind
   * carry each, a place making the bottle's own grape comes first, then the
   * one holding most of what was liked, then the one most like the bottle in
   * what was not answered (보졸레 before a 바롤로 for a 부르고뉴), then the
   * commonest.
   */
  const ranked = (
    type: string,
    fits: (row: Row) => boolean,
    minded: Thing | null,
  ): Ranked[] =>
    rowsOf(type).filter((row) =>
      (row.categories ?? []).includes(category ?? "") && !mine.has(row.key) &&
      ofColor(row) && turnsNone(row, minded) && fits(row) && findable(row)
    ).flatMap((row) => {
      const n = shareOf(row);
      return n && n.bottles >= ENOUGH_BOTTLES && n.share >= ENOUGH_SHARE &&
          n.share <= EVERY_BOTTLE
        ? [{
          row,
          bottles: n.bottles,
          kept: keptBy(row, minded),
          same: mainGrape && grapesOfStyle(row).includes(mainGrape) ? 1 : 0,
          near: nearOwn(row),
        }]
        : [];
    }).sort((a, b) =>
      b.same - a.same || b.kept.length - a.kept.length || b.near - a.near ||
      b.bottles - a.bottles
    );
  /**
   * Two that are one choice, not two: a place and the grape it is made of,
   * a place inside another (키안티, 토스카나), two places of one country that
   * are made of the same grape (보졸레, 보졸레 빌라주).
   */
  const oneChoice = (a: Row, b: Row) => {
    if (a === b) return true;
    const [ga, gb] = [grapesOfStyle(a), grapesOfStyle(b)];
    if (ga.includes(b.key) || gb.includes(a.key)) return true;
    if (a.type !== "regional_style" || b.type !== "regional_style") {
      return false;
    }
    const [pa, pb] = [placesOf(a), placesOf(b)];
    return pa.includes(pb[0]) || pb.includes(pa[0]) ||
      (ga[0] !== undefined && ga[0] === gb[0] && pa.at(-1) === pb.at(-1));
  };
  /**
   * Two to choose from. The first is the one that holds most of what was
   * liked, then what was felt most of it, of a row on the other side before
   * one that is only less and of an earlier slot before a later (a 그르나슈
   * that keeps the weight before a place that keeps only an aroma). The
   * second is the one that holds most of what the first holds, of the first's
   * own slot before another (메를로 before a place).
   */
  const twoOf = (
    pools: readonly Ranked[][],
    less: readonly Ranked[][] = [],
  ): Row[] => {
    // Among those that hold as many, the one that holds what was felt most.
    const lead = (x: Ranked) =>
      Math.min(Infinity, ...x.kept.map((t) => likedThings.indexOf(t)));
    const best = (lists: readonly Ranked[][]) =>
      lists.flat().reduce<Ranked | null>(
        (top, x) =>
          !top || x.kept.length > top.kept.length ||
            (x.kept.length === top.kept.length && lead(x) < lead(top))
            ? x
            : top,
        null,
      );
    const first = best(pools) ?? best(less);
    if (!first) return [];
    const rest = [...pools, ...less].flat().filter((x) =>
      !oneChoice(x.row, first.row)
    );
    const second = [
      ...rest.filter((x) => x.row.type === first.row.type),
      ...rest.filter((x) => x.row.type !== first.row.type),
    ].map((x) => {
      const shared = x.kept.filter((t) => first.kept.includes(t));
      return {
        x,
        shared: shared.length,
        // Among those that share as many, the one sharing what was felt most.
        lead: Math.min(Infinity, ...shared.map((t) => likedThings.indexOf(t))),
      };
    })
      .filter((s) => !first.kept.length || s.shared > 0)
      .sort((a, b) => b.shared - a.shared || a.lead - b.lead)[0];
    return second ? [first.row, second.x.row] : [first.row];
  };

  const slots = (SLOTS[category ?? ""] ?? []).map(([type]) => type);
  let minded: Thing | null = null;
  let change: Row[] = [];
  for (const thing of mindedThings) {
    const want: Side | null = thing.kind === "gauge"
      ? thing.side === "high" ? "low" : "high"
      : null;
    // Turned to only when few of its bottles have what was minded: of the
    // 캘리포니아 reds the dictionary calls low in acid, a third are high.
    const fits = (row: Row) =>
      spares(row, thing) &&
      (thing.kind === "gauge"
        ? sideOn(row, thing.axis) === want
        // A row without the aroma, that still holds something that was liked.
        : (row.aromas ?? []).length > 0 && !carries(row, thing) &&
          keptBy(row, thing).length > 0);
    // What carries the minded thing is what to change; then a slot nothing
    // was kept from; a slot a clue is kept from (말벡) last, so it is turned
    // from only when it keeps more of what was liked than the others do.
    const carried = new Set(
      ownRows.filter((r) => carries(r, thing)).map((r) => r.type),
    );
    const keptTypes = new Set(
      keep.flatMap((k) => k.row && !carries(k.row, thing) ? [k.row.type] : []),
    );
    // Less than the bottle's own is a change too: a row in the middle, where
    // the bottle's own of the slot stands on the minded side (네비올로 → 메를로).
    const less = (row: Row) =>
      thing.kind === "gauge" && carried.has(row.type) && spares(row, thing) &&
      row.taste?.[dictAxis(thing.axis)]?.level === "mid";
    // The place before the grape: the same grape from elsewhere changes less.
    const placeFirst = (a: string, b: string) =>
      Number(b === "regional_style") - Number(a === "regional_style");
    const order = [
      ...slots.filter((t) => carried.has(t)).sort(placeFirst),
      ...slots.filter((t) => !carried.has(t) && !keptTypes.has(t)),
      ...slots.filter((t) => !carried.has(t) && keptTypes.has(t)),
    ];
    change = twoOf(
      order.map((type) => ranked(type, fits, thing)),
      order.map((type) => ranked(type, less, thing)),
    );
    if (change.length) {
      minded = thing;
      break;
    }
  }
  minded ??= mindedThings[0] ?? null;

  // What gave the minded thing is not what to look for again (the oak that
  // gave the tannin, the place that gave the earth).
  const avoid = minded
    ? ownRows.filter((r) => carries(r, minded!) && findable(r)).slice(
      0,
      MOST_CHANGED,
    )
    : [];
  if (minded) keep = keep.filter((k) => !k.row || !carries(k.row, minded!));
  const placeChanged = change.some((r) => r.type === "regional_style");
  // Another place for the same grape: the grape is what stays.
  if (
    change.length && mainGrape && !keep.some((k) => k.row) &&
    change.every((r) =>
      r.type === "regional_style" && grapesOfStyle(r).includes(mainGrape)
    )
  ) {
    const grape = ROW.get(`grape:${mainGrape}`);
    if (grape && findable(grape)) {
      keep.unshift({ text: nameOf(grape), row: grape, of: null });
    }
  }
  // A grape kept with its country says no place when the place is changed.
  if (placeChanged) {
    keep = keep.map((k) =>
      k.row?.type === "grape" && k.plain ? { ...k, text: k.plain } : k
    );
  }

  /* ------------------------------------------------------------- the lines */
  const namesOf = (things: readonly Thing[]) =>
    andJoin([...new Set(things.map((t) => t.name))].slice(0, 2));
  /** What a row is, said after its name: 보졸레 와인, 그르나슈 품종. */
  const nounOf = (row: Row) =>
    row.type === "grape"
      ? " 품종"
      : row.type === "regional_style" && category === "wine" &&
          !row.names.ko.endsWith("와인")
      ? " 와인"
      : "";
  /**
   * Rows as one phrase: 프랑스의 **보졸레**나 이탈리아의 **발폴리첼라** 와인.
   * The bottle's own are said without a country: **키안티** 와인이나
   * **산지오베제** 품종.
   */
  const offered = (rows: readonly Row[], own = false) => {
    const countryOf = (row: Row) =>
      !own && row.type === "regional_style" ? countryOfStyle(row) : null;
    const oneNoun = rows.every((r) => nounOf(r) === nounOf(rows[0]));
    return rows.map((row, i) => {
      const from = countryOf(row);
      // A country is said once for two of its places, and not before a name that says it.
      const said = !from || row.names.ko.startsWith(from) ||
        (i > 0 && countryOf(rows[i - 1]) === from);
      const noun = oneNoun && i < rows.length - 1 ? "" : nounOf(row);
      return `${said ? "" : `${from}의 `}${nameOf(row)}${noun}`;
    }).join("{이나} ");
  };
  /** The liked things every one of the rows holds. */
  const heldBy = (rows: readonly Row[], m: Thing | null) =>
    likedThings.filter((t) => rows.every((r) => keptBy(r, m).includes(t)));
  /** What choosing so does: 묵직한 바디감은 그대로 살리면서 타닌은 줄일 수 있어요. */
  const turned = (m: Thing): string => {
    const still = heldBy(change, m);
    const stay = still.length ? `${namesOf(still)}{은} 그대로 살리면서 ` : "";
    const what = m.kind === "gauge" ? senseNoun(m.axis) : m.name;
    const does = m.kind === "gauge" && m.side === "low" ? "더할" : "줄일";
    return `${stay}${what}{${stay ? "은" : "을"}} ${does} 수 있어요.`;
  };
  const lines: TasteCardNextLine[] = [];
  const kept = keep.slice(0, MOST_KEPT);
  // A shop's word alone says the answer back (풀바디 for a full body): a line
  // is written when it names something of the bottle to look for.
  if (kept.some((k) => k.row)) {
    // What the clues were kept for; the grape that stays beside a changed
    // place is kept for whatever was liked.
    const held = kept.flatMap((k) => k.of ?? []);
    const brought = namesOf(held.length ? held : likedThings);
    lines.push({
      text: josa(
        `${
          kept.map((k) => k.text).join(", ")
        }{을} 선택하시면, 좋았던 ${brought}{을} 그대로 가져갈 수 있어요.`,
      ),
    });
  }
  if (minded && change.length) {
    lines.push({
      text: josa(`${offered(change)}{을} 선택하시면, ${turned(minded)}`),
    });
  }
  // Nothing to turn to, or nothing liked: what gave the minded thing is named,
  // as what such a drink is mostly like, not as an order to pass it by (the
  // user's review, 2026-11-23). A grape or a place few bottles carry is not
  // worth remembering for the next choice.
  const met = (row: Row) => {
    // A name is mostly so when most of its bottles are, as the catalog
    // counts them: its row of the dictionary is one value for all of them.
    // A kind is said so only by its count.
    const said = minded ? bottlesSay(row, minded, "has") : "uncounted";
    if (row.type === "kind") return said === "yes";
    if (said === "no") return false;
    const counted = COUNTED[row.type];
    const n = counted ? bottlesCarrying(counted, row.key, shelf) : null;
    return !n || !n.of ||
      (n.bottles >= ENOUGH_BOTTLES && n.bottles / n.of >= ENOUGH_SHARE);
  };
  const passed = avoid.filter(met);
  if (minded && passed.length && (!change.length || !likedThings.length)) {
    const noun = minded.kind === "gauge" ? senseNoun(minded.axis) : "";
    // 높은 산미 → 산미가 대체로 높은 편이에요.
    const mostly = minded.kind === "aroma"
      ? `${minded.name}{이} 대표 향으로 꼽혀요.`
      : minded.name.endsWith(` ${noun}`)
      ? `${noun}{이} 대체로 ${minded.name.slice(0, -noun.length - 1)} 편이에요.`
      : `${minded.name}{이} 대체로 두드러지는 편이에요.`;
    lines.splice(likedThings.length ? lines.length : 0, 0, {
      text: josa(`${offered(passed, true)}{은} ${mostly}`),
    });
  }
  // Nothing was minded: two more to try, alike in what was liked.
  if (!minded && likedThings.length && category) {
    const keptTypes = new Set(keep.flatMap((k) => k.row ? [k.row.type] : []));
    const alike = twoOf(
      [
        ...slots.filter((t) => keptTypes.has(t)),
        ...slots.filter((t) => !keptTypes.has(t)),
      ].map((type) =>
        ranked(type, (row) => keptBy(row, null).length > 0, null)
      ),
    );
    const shared = heldBy(alike, null);
    if (alike.length && shared.length) {
      lines.push({
        text: josa(
          `${offered(alike)}{을} 선택하시면, ${
            namesOf(shared)
          }{을} 비슷하게 즐길 수 있어요.`,
        ),
      });
    }
  }
  return lines.length ? { lines } : null;
}
