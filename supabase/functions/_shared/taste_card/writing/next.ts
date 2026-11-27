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
 *                            바디감을 그대로 가져갈 수 있어요. Left out of
 *                            it: what gave the minded thing, every name
 *                            아쉬웠던 맛의 정체 spoke of, and a cause that says
 *                            the opposite of the liked answer (카라구치 for
 *                            a sweetness that was liked).
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
import {
  grapeByKey,
  plainName,
  regionsUpFrom,
  type Term,
  termByKey,
  terms,
} from "../../record_reading/dictionary/dictionary.ts";
import type { EvidenceResult } from "../evidence/evidence.ts";
import type { FactorKind } from "../evidence/identity.ts";
import {
  GAUGE_LEVEL_DIMENSION,
  type GaugeAxis,
} from "../../record_reading/facts/facts.ts";
import {
  bottlesCarrying,
  type Carried,
  shelfOfKind,
} from "../../record_reading/facts/kind_place.ts";
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
} from "../../record_reading/facts/name_counts.ts";
import {
  NEXT_CAUSES_KEPT,
  NEXT_NAMES_KEPT,
  NEXT_OWN_NAMES,
} from "../limits.ts";
import type { RecordReading } from "../../record_reading/read_record.ts";
import type { Selection } from "../selection/selection.ts";
import type { TasteCardNext, TasteCardNextLine } from "../service/types.ts";
import { mindedAsFaint } from "./reason_aroma.ts";
import { namesAroma } from "../../record_reading/dictionary/aromas.ts";
import { MADE_THING } from "./reason_glass.ts";
import { mindedName, senseNoun, tagName, traitOf } from "./reason_words.ts";
import { andJoin, josa } from "../../korean.ts";
import { short } from "./words.ts";

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

/** The tastes a drink has or has not: none of it is another drink than a little. */
const NONE_OR_SOME: ReadonlySet<GaugeAxis> = new Set(["peat", "sparkling"]);

/** The kinds too wide to act on beside a grape or a place of their own. */
const WIDE_KINDS: ReadonlySet<string> = new Set([
  "red_wine",
  "white_wine",
  "rose_wine",
  "sparkling_wine",
]);

/** A liked taste as a shop says it. */
const SHOP_WORD: Readonly<
  Partial<Record<GaugeAxis, readonly [high: string | null, low: string | null]>>
> = {
  // Only words a label, a menu or a shop's filter carries: "여운이 긴 스타일"
  // cannot be looked for (the user's review, 2026-11-21).
  // 풀바디 and 라이트 바디 said the answer back and stand on no label; a
  // whisky is not sold as 드라이 (the returned review, res/4_1_129.md,
  // 2026-11-27).
  sweetness: [null, "드라이"],
  peat: ["피트 위스키", "논피트"],
};
/** The drinks a shop sorts by a word: 드라이 is a wine's. */
const SHOP_WORD_OF: Readonly<Partial<Record<GaugeAxis, readonly string[]>>> = {
  sweetness: ["wine"],
};

/** How more or less of a taste is said, where it is not a thing to add to: a finish is longer, not more. */
const CHANGED: Readonly<
  Partial<Record<GaugeAxis, readonly [more: string, less: string]>>
> = {
  // A finish that was too long is not enjoyed shorter: it is lessened.
  finish_length: ["더 길게 즐길", "더 짧고 깔끔하게 줄일"],
  finish_character: ["더 진하게 즐길", "더 깔끔하게 줄일"],
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

type Row = Term;

/** The dictionary's row of a cause of the bottle. */
function rowOf(factor: FactorKind, key: string): Row | null {
  for (const type of TYPE_OF[factor] ?? []) {
    const row = termByKey(type, key);
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

const latin = (word: string | undefined) =>
  word && /^[\x20-\x7eÀ-ɏ]+$/.test(word) ? word : null;

/**
 * The oak of a wine as a label and a shelf say it. A wine's label does not
 * print Virgin Oak or a cask's wood: it says the wine was aged in oak.
 */
const WINE_OAK: ReadonlySet<string> = new Set([
  "new_oak_cask",
  "oak_wood",
  "wooden_cask",
  "american_oak",
  "european_oak",
  "toasted_cask",
]);
/** What every whisky has: a cask of oak. */
const EVERY_WHISKY: ReadonlySet<string> = new Set(["oak_wood", "wooden_cask"]);
const OAK_AGED = "**오크통 숙성**(Oak Aged) 와인";

/** The places a wine style sits in, its own first and its country last. */
function placesOf(row: Row): string[] {
  return regionsUpFrom(row.region_key).map((region) => region.key);
}

/** The country a wine style sits in: the root of its region's tree. */
function countryOfStyle(row: Row): string | null {
  return regionsUpFrom(row.region_key).at(-1)?.names.ko ?? null;
}

/** A row as a label shows it, its name in bold: **메를로**, **셰리 캐스크**(Sherry Cask). */
function nameOf(row: Row, drink?: string | null): string {
  if (drink === "wine" && WINE_OAK.has(row.key)) return OAK_AGED;
  const ko = plainName(row.names.ko);
  // The first word a label prints in letters: 無濾過 is not read out.
  const label = row.type === "process" || row.type === "maturation"
    ? (row.label_words ?? []).map(latin).find(Boolean) ?? null
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
    : (row.aromas ?? []).some((a) => namesAroma(a.key, thing.key));
}

/** The grapes a regional style is made of. */
const grapesOfStyle = (row: Row): readonly string[] => row.grape_keys ?? [];

export function writeNext(
  prepared: RecordReading,
  found: EvidenceResult,
  selection: Selection,
  /** The text of 아쉬웠던 맛의 정체, as the card shows it (writing/reasons.ts). */
  minded_text = "",
): TasteCardNext | null {
  const { category, style_key, abv } = prepared.bottle;
  if (category && UNTOLD.has(category)) return null;
  const byId = new Map(found.evidence.map((e) => [e.id, e]));
  const { gauges, aromas } = prepared.answers;
  const gaugeOf = (ref: string) => gauges.find((g) => g.answer_ref === ref);
  /**
   * An answer as a thing a row can carry; a middle step is none. It is named
   * as the one line under the tags names it: a liked 단맛 없음 is 단맛 없는
   * 깔끔함, a minded one 거의 없는 단맛.
   */
  const thingOf = (ref: string, minded = false): Thing | null => {
    const g = gaugeOf(ref);
    if (g) {
      return g.side === "middle" ? null : {
        kind: "gauge",
        axis: g.axis,
        // A step set to none is the low side: more of it is what is offered
        // for a minded one, never less.
        side: g.side === "high" ? "high" : "low",
        level: g.level,
        name: minded
          ? mindedName(g.axis, g.level)
          : tagName(g.axis, g.level).replace(/ 없음$/, " 없는 깔끔함"),
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
    // Every whisky is aged in a cask of oak: nothing to choose by.
    if (category === "whisky" && EVERY_WHISKY.has(row.key)) {
      return false;
    }
    if (row.type === "process" || row.type === "maturation") {
      return !!row.label_words?.length;
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
  ].flatMap((ref) => thingOf(ref, true) ?? [])
    // An aroma minded as too faint is nothing to have less of, and the card
    // has no way to offer more of an aroma.
    .filter((t) => !(t.kind === "aroma" && mindedAsFaint(t.key)));

  /* ------------------------------------------------- what to look for again */
  /** A clue, the row it names, and the liked thing it was kept for. */
  type Kept = {
    text: string;
    row: Row | null;
    plain?: string;
    of: Thing | null;
  };
  /**
   * A row 아쉬웠던 맛의 정체 spoke of, by its name: the place or the grape a
   * minded taste was said to come from, and the oak a minded aroma was said
   * to have soaked in from (… 숙성하는 오크통에서 밴 향이에요). The reader has
   * just read it as what gave what they minded, so it is not what to look
   * for again, whatever else it gives.
   */
  const spoken = minded_text.replaceAll("**", "");
  const blamed = (row: Row) =>
    spoken.includes(plainName(row.names.ko)) ||
    // 안쪽을 태운 오크통 is the 차링 캐스크.
    (MADE_THING[row.key] !== undefined && spoken.includes(MADE_THING[row.key]));
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
    // The cause a reason was found by may say the opposite of the answer (a
    // 카라구치 that came across sweet): the reason is then told as it was
    // felt, and the cause is no way back to what was liked.
    const agrees = (cause: { factor: FactorKind; key: string }) => {
      if (!answer) return true;
      if (lead?.type === "felt_differently") return false;
      const step = lead?.causes.find((c) =>
        c.factor === cause.factor && c.key === cause.key
      )?.tendency?.step;
      // None of it and a little of it are two drinks where the taste is
      // there or not (피트, 탄산): a maker that never peats is no way back to
      // a faint peat that was liked, nor a 프리잔테 to no bubbles.
      if (
        NONE_OR_SOME.has(answer.axis) && step !== undefined &&
        (step === 1) !== (answer.level === 1)
      ) return false;
      return step === undefined || step === 3 ||
        (step > 3) === (answer.side === "high");
    };
    for (
      const told of [
        ...named,
        ...(reason.told_by && agrees(reason.told_by) ? [reason.told_by] : []),
      ]
    ) {
      const row = rowOf(told.factor, told.key);
      // The kind just drunk is no direction: 싱글 몰트 위스키 is 1,774
      // bottles, a third of them with the vanilla that was liked.
      if (
        !row || !findable(row) || told.factor === "kind" || blamed(row)
      ) continue;
      // A clue that stands against another liked taste is no way back to
      // both (소비뇽 블랑 beside a sweetness that was liked).
      if (
        likedGauges.some((g) => {
          const side = sideOn(row, g.axis);
          return side !== null && side !== g.side;
        })
      ) continue;
      const plain = nameOf(row, category);
      // A grape is looked for with its country (아르헨티나 말벡), unless the
      // place is already a clue of its own.
      const placed = row.type === "grape" && country &&
        !keep.some((k) => k.row?.type === "regional_style");
      const text = placed ? `${country} ${plain}` : plain;
      if (
        keep.length < NEXT_CAUSES_KEPT && !keep.some((k) => k.plain === plain)
      ) {
        keep.push({ text, row, plain, of: thingOf(reason.answers[0]) });
      }
    }
  }
  const liked = likedGauges[0];
  if (liked) {
    const sold = SHOP_WORD_OF[liked.axis];
    const word = (!sold || sold.includes(category ?? "")) &&
        // 논피트 is no peat at all, not a faint one.
        !(liked.axis === "peat" && liked.side === "low" && liked.level !== 1)
      ? SHOP_WORD[liked.axis]?.[liked.side === "high" ? 0 : 1]
      : null;
    // 드라이, 드라이: the label's own word is already a clue, and so is a
    // row that says the same of the taste (라프로익 beside 피트 위스키).
    if (
      word && !keep.some((k) => k.plain === `**${word}**`) &&
      !keep.some((k) => k.row && carries(k.row, liked))
    ) {
      keep.push({ text: `**${word}**`, row: null, of: liked });
    }
    // The strength a liked weight came of is a clue a label prints.
    if (liked.axis === "body" && strengthCaused && abv?.of === "bottle") {
      keep.push({
        text: `알코올 도수 ${Math.round(abv.percent)}% 전후`,
        row: null,
        of: liked,
      });
    }
  }

  /* ------------------------------------------------------ what to change by */
  const mine = new Set(own.map((c) => c.key));
  const colors = new Set(
    [
      style?.color,
      ...prepared.bottle.grapes.flatMap((key) => grapeByKey(key)?.colors ?? []),
    ].filter(Boolean),
  );
  const ofColor = (row: Row) =>
    !colors.size ||
    (row.type === "grape"
      ? (row.colors ?? []).some((c) => colors.has(c))
      : row.type !== "regional_style" || colors.has(row.color));
  /** The liked things a row carries, the minded taste's own gauge aside. */
  const keptBy = (row: Row, minded: Thing | null) =>
    likedThings.filter((t) =>
      !(minded?.kind === "gauge" && t.kind === "gauge" &&
        t.axis === minded.axis) &&
      // An aroma liked at one moment and minded at another is not both kept
      // and had less of.
      !(minded?.kind === "aroma" && t.kind === "aroma" &&
        t.key === minded.key) &&
      holds(row, t)
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
    terms(type).filter((row) =>
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
    // 준마이나 준마이 긴조: one name holds the other.
    const [na, nb] = [plainName(a.names.ko), plainName(b.names.ko)];
    if (na.includes(nb) || nb.includes(na)) return true;
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
        // Only a grape or a place lists what it smells of: a cask or a way of
        // making that does not list an aroma is not known to be free of it.
        : category === "wine" && (row.aromas ?? []).length > 0 &&
          !carries(row, thing) && keptBy(row, thing).length > 0);
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
    // Of a wine alone: a cask or a way of making in the middle is not
    // another choice in place of the bottle's own.
    const less = (row: Row) =>
      category === "wine" &&
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
  const carrying = minded
    ? ownRows.filter((r) => carries(r, minded!) && findable(r))
    : [];
  // 포트 와인이나 포르투·도루 와인: a place's style filed under a kind that is
  // named beside it says the same drink twice.
  // A wide kind (화이트 와인) beside a grape or a place of its own names the
  // narrower twice over and is too wide to act on: the narrower stays.
  const narrower = carrying.some((r) => r.type !== "kind");
  const avoid = carrying.filter((r) =>
    !(r.type === "kind" && WIDE_KINDS.has(r.key) && narrower) &&
    !(r.type === "regional_style" &&
      carrying.some((k) =>
        k.type === "kind" && !WIDE_KINDS.has(k.key) &&
        [r.kind_key, ...(r.kind_keys ?? [])].includes(k.key)
      ))
  ).slice(0, NEXT_OWN_NAMES);
  if (minded) keep = keep.filter((k) => !k.row || !carries(k.row, minded!));
  const placeChanged = change.some((r) => r.type === "regional_style");
  // Another place for the same grape: the grape is what stays.
  if (
    change.length && mainGrape && !keep.some((k) => k.row) &&
    change.every((r) =>
      r.type === "regional_style" && grapesOfStyle(r).includes(mainGrape)
    )
  ) {
    const grape = grapeByKey(mainGrape);
    if (grape && findable(grape) && !blamed(grape)) {
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
  const offered = (rows: readonly Row[], own = false): string => {
    // A place and the grape it is made of are one drink: 미국 **오리건**의
    // **피노 누아** 와인, not 오리건 와인이나 피노 누아 품종.
    const place = rows.find((r) => r.type === "regional_style");
    const grape = rows.find((r) =>
      r.type === "grape" && place && grapesOfStyle(place).includes(r.key)
    );
    if (own && rows.length === 2 && place && grape) {
      const from = countryOfStyle(place);
      const said = !from || place.names.ko.includes(from);
      return `${said ? "" : `${from} `}${nameOf(place, category)}의 ${
        nameOf(grape, category)
      } 와인`;
    }
    const countryOf = (row: Row) =>
      !own && row.type === "regional_style" ? countryOfStyle(row) : null;
    const oneNoun = rows.every((r) => nounOf(r) === nounOf(rows[0]));
    return rows.map((row, i) => {
      const from = countryOf(row);
      // A country is said once for two of its places, and not before a name
      // that says it (프랑스의 남프랑스).
      const said = !from || row.names.ko.includes(from) ||
        (i > 0 && countryOf(rows[i - 1]) === from);
      const noun = oneNoun && i < rows.length - 1 ? "" : nounOf(row);
      return `${said ? "" : `${from}의 `}${nameOf(row, category)}${noun}`;
      // 피노 그리지오·피노 그리나 reads as a grape called 그리나: after a
      // name of two the next is joined by 또는.
    }).reduce(
      (all, name, i) =>
        i === 0
          ? name
          : `${all}${
            /·[^·]*$/.test(all.replaceAll("**", "")) && !/\)$/.test(all)
              ? " 또는 "
              : "{이나} "
          }${name}`,
      "",
    );
  };
  /** The liked things every one of the rows holds. */
  const heldBy = (rows: readonly Row[], m: Thing | null) =>
    likedThings.filter((t) => rows.every((r) => keptBy(r, m).includes(t)));
  /** What choosing so does: 묵직한 바디감은 그대로 살리면서 타닌은 줄일 수 있어요. */
  const turned = (m: Thing): string => {
    const still = heldBy(change, m);
    const stay = still.length ? `${namesOf(still)}{은} 그대로 살리면서 ` : "";
    const what = m.kind === "gauge" ? senseNoun(m.axis) : m.name;
    const [more, less] = (m.kind === "gauge" ? CHANGED[m.axis] : null) ??
      ["더할", "줄일"];
    const does = m.kind === "gauge" && m.side === "low" ? more : less;
    return `${stay}${what}{${stay ? "은" : "을"}} ${does} 수 있어요.`;
  };
  const lines: TasteCardNextLine[] = [];
  const kept = keep.slice(0, NEXT_NAMES_KEPT);
  // A shop's word alone says the answer back (풀바디 for a full body): a line
  // is written when it names something of the bottle to look for.
  // What the clues were kept for; the grape that stays beside a changed
  // place is kept for whatever was liked.
  const held = kept.flatMap((k) => k.of ?? []);
  const brought = namesOf(held.length ? held : likedThings);
  // Nothing liked that a clue carries (a middle step alone): there is nothing
  // to say the choice brings along.
  if (kept.some((k) => k.row) && brought) {
    lines.push({
      text: josa(
        `${
          andJoin(kept.map((k) => k.text))
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
      // 대체로 거의 없는 편 says "mostly" three times over.
      ? `${noun}{이} ${minded.name.startsWith("거의 없는") ? "" : "대체로 "}${
        minded.name.slice(0, -noun.length - 1)
      } 편이에요.`
      // 강한 알싸함 → 알싸한 자극이 대체로 센 편이에요.
      : `${
        traitOf(minded.axis, minded.level)[1].replace(
          /^(\S+(?: \S+)?[이가]) (?!거의 )/,
          "$1 대체로 ",
        )
      } 편이에요.`;
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
  // 단맛 없는 깔끔함 beside another 깔끔 in the line is 단맛 없는 담백함, as
  // in the one line under the tags.
  for (const line of lines) {
    if ((line.text.match(/깔끔/g) ?? []).length > 1) {
      line.text = line.text.replace("단맛 없는 깔끔함", "단맛 없는 담백함");
    }
  }
  return lines.length ? { lines } : null;
}
