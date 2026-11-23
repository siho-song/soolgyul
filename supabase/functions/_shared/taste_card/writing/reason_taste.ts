/** A taste as a reason: the cause it comes from and why, or, with no cause, how it came across. */
import type { Cause, Evidence } from "../evidence/evidence.ts";
import type { FactorKind } from "../evidence/identity.ts";
import { GAUGE_LEVEL_DIMENSION, type GaugeAxis } from "../facts/facts.ts";
import { aromaEffect } from "../facts/aroma_effects.ts";
import { type Carried } from "../facts/kind_place.ts";
import { mostlyOnSide } from "../facts/name_counts.ts";
import { readsSweet } from "../facts/wine_sweetness.ts";
import type { Prepared } from "../prepare/prepare.ts";
import type { Reason, Section } from "../selection/selection.ts";
import { howOf, makes, reaches, reasonKindOf } from "../selection/causation.ts";
import { short } from "./words.ts";
import { aromaCause, aromaProse, tellAroma } from "./reason_aroma.ts";
import {
  bare,
  MADE,
  OWN_KIND,
  PLACES,
  same,
  what,
  word,
} from "./reason_causes.ts";
import { type Feel, feelOf, notably } from "./reason_feel.ts";
import { relation, rowWords } from "./reason_glass.ts";
import { type Card, type Gauge, type Point, type Told } from "./reason_told.ts";
import { tellWineSweetness } from "./reason_wine_sweetness.ts";
import { AXIS, nameOf, type Side, sideOf, traitOf } from "./reason_words.ts";

/** The names the catalog counts the bottles of, by the cause that names them. */
export const COUNTED_AS: Readonly<Partial<Record<FactorKind, Carried>>> = {
  kind: "kinds",
  grape: "grapes",
  region_style: "styles",
};

/** The causes that are what the drink is: a taste is a mark of them, not something that comes out of them. */
export const IS = new Set<FactorKind>([
  "region_style",
  "kind",
  "label_word",
  "producer",
]);

/**
 * Where a taste comes from, as the end of a point's first sentence. A grape
 * the point tells no why of is named as having the taste, not as making it.
 */
export const source = (c: Cause, told: boolean) =>
  IS.has(c.factor) || (c.factor === "grape" && !told) ||
    ((c.factor === "making" || c.factor === "cask") && OWN_KIND.has(c.key))
    ? `${what(c)}의 특징이에요`
    : `${what(c)}에서 나와요`;

/**
 * A cause as the first sentence of a point and the why of its second. With
 * `link`, the clause the dictionary's research wrote for the cause and the
 * taste; without, what sets the bottle apart among its kind (`apart`), or
 * nothing: the name is then the whole of the reason.
 */
export function pointOf(
  c: Cause,
  taste: string,
  trait: string,
  link: string | null,
  apart: string | null,
  axis: GaugeAxis,
  card: Card,
  side: Side = "mid",
): Omit<Point, "act"> {
  // 질감을 묵직하게 채워서 has reached the taste: it is not named after it.
  const after = link === null
    ? ""
    : reaches(axis, link)
    ? link
    : `${link.replace(/서$/, "")} ${trait}`;
  // 이 레드 와인은 레드 와인의 특징이에요 says nothing: the drink is the subject.
  if (c.ko === card.kind) {
    return {
      cause: null,
      open: null,
      why: `이 ${card.kind}{은} ${after || apart || trait}`,
    };
  }
  // A taste is a name's mark when most of the name's bottles have it, as
  // the catalog counts them: of the 준마이 다이긴조 a third are light, of
  // the 산지오베제 reds a quarter are high in tannin. Where they do not, the
  // taste in the glass is told as this bottle's, not as what the name is.
  const what = COUNTED_AS[c.factor];
  const borne = what && side !== "mid"
    ? mostlyOnSide(
      { what, key: c.key },
      card.shelf,
      GAUGE_LEVEL_DIMENSION[axis],
      side === "high" ? "high" : "low",
    )
    : "uncounted";
  if (borne === "no" && (after || apart)) {
    const drink = c.factor === "kind" ||
        (c.factor === "region_style" && !PLACES.has(c.ko))
      ? word(c)
      : `${word(c)} ${card.kind}`;
    return {
      cause: c,
      open: null,
      why: `이 ${drink}{은} ${after || apart}`,
    };
  }
  // 여과하지 않은 술이라: what was done is not a thing a taste comes out of.
  if (link === null && MADE[c.key]) {
    return {
      cause: c,
      open: null,
      why: `${MADE[c.key](word(c))} 술이라 ${apart ?? trait}`,
    };
  }
  return {
    cause: c,
    open: { taste, from: source(c, after !== "") },
    why: after || apart || "",
  };
}

/**
 * What the taste did, after its ground. The ground has just named the taste,
 * so a sentence that opens on it again (떫은맛이 입안을 조이며 …) goes on
 * without it.
 */
export function actAfter(
  ground: string,
  act: string,
  marks: readonly string[],
): string {
  const again = [...marks].sort((x, y) => y.length - x.length)
    // 새콤함이 또렷해서, 새콤한 맛이 … is the same word; 피트 불길에 말려
    // has not named the 피트 향.
    .filter((m) =>
      marks.some((k) => k.slice(0, 2) === m.slice(0, 2) && ground.includes(k))
    )
    // 피트 향이 거의 없어서, 피트 향 없이 … says it twice too.
    .flatMap((m) =>
      ["이 ", "가 ", "은 ", "는 ", " 없이 "].map((p) => `${m}${p}`)
    )
    .find((open) => act.startsWith(open));
  // … 오크의 떫은맛이 또렷하게 우러나, 입안을 떫게 조이고 … says 떫 twice.
  const rest = (again ? act.slice(again.length) : act).replace(
    ground.includes("떫") ? "떫게 " : "\u0000",
    "",
  );
  // … 여운이 삼킨 뒤에도 길게 이어져서, 삼킨 뒤에도 … says when twice.
  const when = "삼킨 뒤에도 ";
  return ground.includes(when.trim()) && rest.startsWith(when)
    ? rest.slice(when.length)
    : rest;
}

/**
 * A taste in two words. One the reader wanted more of is named as thin (옅은
 * 끝맛: 깔끔한 끝맛 would praise what they minded), and a middle step that
 * was minded has only its own name (어중간한 단맛).
 */
export function briefOf(
  g: { axis: GaugeAxis; level: number; side: string },
  section: Section,
  feel: Feel,
): string {
  if (section === "burden" && g.side === "low") {
    return g.axis === "tannin" ? "낮은 타닌" : `옅은 ${AXIS[g.axis].noun}`;
  }
  return section === "burden" && sideOf(g.axis, g.level) === "mid"
    ? feel.name
    : nameOf(g.axis, g.level);
}

/**
 * A still wine's sweetness told from the bottle's own tannin, acidity and
 * aromas, where they explain the answer (reason_wine_sweetness.ts).
 */
function wineSweetness(
  g: Pick<Gauge, "axis" | "level">,
  section: Section,
  feel: Feel,
  prepared: Prepared,
  card: Card,
): { name: string; body: string } | null {
  if (g.axis !== "sweetness" || !card.sweetness) return null;
  const { gauges } = prepared.interpretation;
  const own = prepared.bottle.levels.sweetness;
  const told = tellWineSweetness(
    g.level,
    section,
    feel,
    card.kind,
    card.sweetness,
    own?.of === "bottle" ? own.level : null,
    gauges,
  );
  return told && { name: told.name ?? feel.name, body: told.body };
}

export function tellReason(
  reason: Reason,
  byId: ReadonlyMap<string, Evidence>,
  prepared: Prepared,
  card: Card,
): Told | null {
  const section = reason.section;
  // Nothing explains the answer: it is told as it was felt.
  if (!reason.evidence.length) {
    return tellFelt(reason.answers[0], section, prepared, card);
  }
  const all = reason.evidence.flatMap((id) => byId.get(id) ?? []).map((e) => ({
    ...e,
    causes: e.causes.map(bare),
  }));
  const first = all[0];
  if (!first) return null;
  const told = reason.told_by
    ? first.causes.find((c) => same(c, reason.told_by!)) ?? first.causes[0]
    : null;
  const rulesOf = (e: Evidence) => e.perception?.rules ?? [];

  if (first.answer.kind === "aroma") {
    const key = first.answer.aroma;
    if (first.type !== "aroma_effect") {
      return tellAroma(key, aromaCause(told, first.causes), section, card);
    }
    // What in the glass let the aroma through.
    const rule = rulesOf(first)[0];
    const abv = rule?.by.find((b) => b.said.startsWith("abv:"))?.said
      .split(":")[1];
    const aroma = `**${short(key)} 향**`;
    const body = rule?.name.startsWith("떫음이 적어")
      ? `타닌이 낮은 덕분에, ${aroma}{이} 가려지지 않고 또렷하게 피어올라요`
      : rule?.name.startsWith("도수가 높지 않아") && abv && !card.strong
      ? `도수가 ${abv}%로 높지 않은 덕분에, ${aroma}{이} 알코올에 묻히지 않고 또렷하게 피어올라요`
      : null;
    return body
      ? {
        name: aromaProse(key, section).name.replaceAll(
          "{aroma}",
          `${short(key)} 향`,
        ),
        brief: `${short(key)} 향`,
        body,
        whole: false,
        causes: [],
        marks: [],
        lack: false,
        of: { aroma: aromaEffect(key) ?? undefined, side: "high" },
      }
      : null;
  }

  const gauges = all.filter((e) => e.answer.kind === "gauge");
  const g = first.answer as Gauge;
  const feel = feelOf(g.axis, g.level, section);
  const marks = AXIS[g.axis].marks;
  const base = {
    name: feel.name,
    brief: briefOf(g, section, feel),
    marks,
    lack: section === "burden" && g.side === "low",
    of: { axis: g.axis, side: g.side as string },
  };
  /** The told cause's step on a gauge answer, as that answer's evidence holds it. */
  const stepOn = (e: Evidence, cause: Cause) =>
    e.causes.find((c) => same(c, cause))?.tendency?.step ??
      (e.answer as Gauge).level;
  // A row that only says one of the reason's own answers again adds nothing.
  const own = new Set(gauges.map((e) => `answer:${(e.answer as Gauge).axis}`));
  const row = rulesOf(first).flatMap((rule) => {
    const said = rule.by.filter((b) =>
      !own.has(b.said.split(":").slice(0, 2).join(":"))
    );
    const words = said.length ? rowWords({ ...rule, by: said }) : null;
    return words ? [{ rule, ...words }] : [];
  })[0];

  // What held in this glass (탄산이 함께 있어서, …).
  const inGlass: Told | null = row
    ? {
      ...base,
      body: `${row.head}, ${
        relation(row.does, feel.short, section, row.head, marks)
      }`,
      whole: false,
      causes: [],
      glass: {
        of: g.axis,
        by: row.rule.by.flatMap((b) =>
          b.said.startsWith("answer:") ? [b.said.split(":")[1]] : []
        ),
      },
    }
    : null;
  // A still wine's sweetness is told from the bottle's own tannin, acidity
  // and aromas before what held in the glass: they are why a dry wine felt
  // sweet, or drier than the reader wished.
  const ofWine = wineSweetness(g, section, feel, prepared, card);
  const ofBottle: Told | null = ofWine &&
    { ...base, ...ofWine, whole: true, causes: [] };
  if (first.type === "in_this_glass" || !told) return ofBottle ?? inGlass;
  // The cause is usually unlike what the reader felt: it is not brought in
  // to stand against the answer (the user's review, 2026-11-22: "억지로
  // 품종이나 산지 근거를 끌어다 붙이지 않고 이번 잔의 실제 인상으로"). What in
  // this glass turned the taste is told, or the taste as it was felt.
  if (first.type === "felt_differently") {
    return ofBottle ?? inGlass ??
      tellFelt(reason.answers[0], section, prepared, card);
  }
  if (first.type === "bottle_trait" && first.support) {
    return tellFelt(reason.answers[0], section, prepared, card);
  }
  // The same where only the kind says what the reader said and a way the
  // bottle was made makes the opposite (a peated blended malt that came
  // across faint): the kind's own reason would not be true of this bottle.
  const turned = first.type === "split" && told.factor === "kind" &&
    g.side !== "middle" &&
    (first.against ?? []).map(bare).some((c) =>
      (c.factor === "making" || c.factor === "cask") &&
      c.tendency !== undefined && howOf(c, g.axis) !== null
    );
  if (turned) return tellFelt(reason.answers[0], section, prepared, card);

  // 설명 · 엇갈림 · 종류 경향: what the cause makes the drink, and what that
  // did in the mouth.
  const says = (c: Cause) =>
    !same(c, told) && c.tendency !== undefined && makes(c, g.axis) &&
    sideOf(g.axis, c.tendency.step) === sideOf(g.axis, stepOn(first, told));
  const causes = [told, ...first.causes.filter((c) => says(c))];
  const out = card.standsOut(g.axis, causes);
  const stands_out = out && out === g.side ? out : null;
  // Why the cause makes the taste: the clause the dictionary's research
  // wrote for this cause and this taste (나무통에서 우러난 풍미가 질감을 둥글고
  // 묵직하게 채워서), one line of it (the user's standard, 2026-11-22: the
  // taste, what it comes from, then the principle in a line). A pair whose
  // clause only says the taste again is named and no more.
  const side = g.level > 3 ? "high" : "low";
  const kindOfReason = reasonKindOf(told, g.axis, side);
  const link = told.factor !== "abv" && g.level !== 3 &&
      kindOfReason !== null && kindOfReason !== "style_only"
    ? howOf(told, g.axis, side)
    : null;
  // A still wine's sweetness whose cause gives no why (옅은 단맛은 바롤로
  // 지역의 특징이에요: so it is of nine red wines in ten) is told from the
  // bottle's own traits where they explain it, and a wine that reads sweet
  // among its kind is not said to have little: it is told as it was felt.
  if (g.axis === "sweetness" && card.sweetness && !link) {
    if (ofBottle) return ofBottle;
    if (g.level < 3 && readsSweet(card.sweetness)) {
      return tellFelt(reason.answers[0], section, prepared, card);
    }
  }
  const trait = traitOf(g.axis, stepOn(first, told));
  // A middle step that was minded: nothing of it stood out.
  const vague = section === "burden" && sideOf(g.axis, g.level) === "mid";
  const point = pointOf(
    told,
    base.brief,
    vague ? feel.across : trait[2],
    link,
    stands_out && !link
      ? `같은 종류 가운데서도 ${notably(trait[1])} 편이라`
      : null,
    g.axis,
    card,
    sideOf(g.axis, g.level),
  );
  return {
    ...base,
    body: "",
    whole: true,
    point: {
      ...point,
      // A point that told why is long already: what it does is said in few words.
      act: actAfter(
        `${point.open?.taste ?? ""} ${point.why}`,
        link ? feel.short : feel.long,
        marks,
      ),
    },
    causes,
  };
}

/** An answer no cause was found for, told from what was felt alone. */
export function tellFelt(
  ref: string,
  section: Section,
  prepared: Prepared,
  card: Card,
): Told | null {
  const { gauges, aromas } = prepared.interpretation;
  const g = gauges.find((x) => x.answer_ref === ref);
  if (g) {
    // A middle step alone says too little to be a reason.
    if (g.side === "middle") return null;
    const feel = feelOf(g.axis, g.level, section);
    const marks = AXIS[g.axis].marks;
    const base = {
      name: feel.name,
      brief: briefOf(g, section, feel),
      body: "",
      whole: true,
      causes: [],
      marks,
      lack: section === "burden" && g.side === "low",
      of: { axis: g.axis, side: g.side as string },
    };
    const dimension = GAUGE_LEVEL_DIMENSION[g.axis];
    const own = dimension ? prepared.bottle.levels[dimension] : undefined;
    // A still wine's sweetness, from the bottle's own tannin, acidity and
    // aromas where they explain it.
    const wine = g.axis === "sweetness" ? card.sweetness : null;
    const ofWine = wineSweetness(g, section, feel, prepared, card);
    if (ofWine) return { ...base, ...ofWine };
    // The bottle's own level, read for it, on the side the reader set: the
    // drink is such a drink, as the card has always said of it (이 와인은
    // 묵직해서, …). A wine that reads sweet among its kind is not said to
    // have little sweetness.
    const side = g.level > 3 ? "high" : "low";
    const drink = `이 ${card.kind}{은}`;
    if (
      own?.of === "bottle" && own.level !== 3 &&
      (own.level > 3 ? "high" : "low") === side &&
      !(wine && side === "low" && readsSweet(wine))
    ) {
      const apart = card.standsOut(g.axis, []) === side;
      const trait = traitOf(g.axis, g.level);
      const why = `${drink} ${
        apart ? `같은 종류 가운데서도 ${notably(trait[1])} 편이라` : trait[2]
      }`;
      return {
        ...base,
        point: {
          cause: null,
          open: null,
          why,
          act: actAfter(why, feel.long, marks),
        },
      };
    }
    const act = actAfter(feel.across, feel.long, marks);
    // The level read for the bottle stands two steps or more the other way:
    // that it came across so in this glass is what there is to tell.
    if (
      own?.of === "bottle" && own.level !== 3 &&
      (own.level > 3 ? "high" : "low") !== side &&
      Math.abs(own.level - g.level) >= 2
    ) {
      return {
        ...base,
        body: `표기된 스타일은 ${
          traitOf(g.axis, own.level)[1]
        } 편이지만 이번 잔에서는 ${feel.across}, ${act}`,
      };
    }
    // No fact of the bottle stands behind it: 이 와인에서는 단맛이 적당히
    // 감돌아서, …
    return {
      ...base,
      point: {
        cause: null,
        open: null,
        why: `이 ${card.kind}에서는 ${feel.across}`,
        act,
      },
    };
  }
  const a = aromas.find((x) => x.answer_ref === ref);
  return a ? tellAroma(a.aroma, null, section, card) : null;
}
