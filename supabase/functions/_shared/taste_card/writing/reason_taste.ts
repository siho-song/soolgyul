/** A taste as a reason: the cause it comes from and why, or, with no cause, how it came across. */
import type { Cause, Evidence } from "../evidence/evidence.ts";
import type { FactorKind } from "../evidence/identity.ts";
import {
  GAUGE_LEVEL_DIMENSION,
  type GaugeAxis,
} from "../../record_reading/facts/facts.ts";
import { aromaEffect } from "../../record_reading/facts/aroma_effects.ts";
import { type Carried } from "../../record_reading/facts/kind_place.ts";
import { mostlyOnSide } from "../../record_reading/facts/name_counts.ts";
import { readsSweet } from "../../record_reading/facts/wine_sweetness.ts";
import type { RecordReading } from "../../record_reading/read_record.ts";
import type { Reason, Section } from "../selection/selection.ts";
import { howOf, makes, reaches, reasonKindOf } from "../selection/causation.ts";
import { short } from "./words.ts";
import { aromaCause, tellAroma } from "./reason_aroma.ts";
import {
  bare,
  MADE,
  namedByPlace,
  ofStyleOnly,
  OWN_KIND,
  same,
  what,
  whose,
  word,
} from "./reason_causes.ts";
import { type Feel, feelOf, notably } from "./reason_feel.ts";
import { rowSentence, rowWords } from "./reason_glass.ts";
import { type Card, type Gauge, type Point, type Told } from "./reason_told.ts";
import { tellWineSweetness } from "./reason_wine_sweetness.ts";
import {
  aromaLabel,
  AXIS,
  mindedName,
  nameOf,
  type Side,
  sideOf,
  titleName,
  traitIn,
} from "./reason_words.ts";

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
export const source = (c: Cause, told: boolean, kind: string) =>
  IS.has(c.factor) || (c.factor === "grape" && !told) ||
    ((c.factor === "making" || c.factor === "cask") && OWN_KIND.has(c.key))
    ? `${whose(c, kind)}의 특징이에요`
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
  // Nor is it where the point opens on the taste (묵직한 바디감은 …에서
  // 나와요.): the why then only has to say why.
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
  const counted = COUNTED_AS[c.factor];
  const borne = counted && side !== "mid"
    ? mostlyOnSide(
      { what: counted, key: c.key },
      card.shelf,
      GAUGE_LEVEL_DIMENSION[axis],
      side === "high" ? "high" : "low",
    )
    : "uncounted";
  if (borne === "no" && (after || apart)) {
    const drink = c.factor === "kind" ||
        (c.factor === "region_style" && !namedByPlace(c))
      ? word(c)
      : `${word(c)} ${card.kind}`;
    return {
      cause: c,
      open: null,
      why: `이 ${drink}{은} ${after || apart}`,
    };
  }
  // What the style brings and the bottle does not state is said of the
  // style's wine, as usual of it (**지공다스** 지역 레드 와인의 긴 여운은 보통
  // **오크**에서 나와요): the bottle's own oak is not known.
  const usual = ofStyleOnly(c) ? card.styleDrink : null;
  // 여과하지 않은 술이라: what was done is not a thing a taste comes out of.
  if (link === null && MADE[c.key]) {
    const made = `${MADE[c.key](word(c))} 술이라 ${apart ?? trait}`;
    return {
      cause: c,
      open: null,
      why: usual ? `${usual}{은} 보통 ${made}` : made,
    };
  }
  if (usual && side !== "none") {
    return {
      cause: c,
      open: {
        taste: `${usual}의 ${taste}`,
        from: `보통 ${source(c, after !== "", card.kind)}`,
      },
      why: link || apart || "",
    };
  }
  return {
    cause: c,
    // Nothing comes out of a taste that is not there: its absence is the
    // cause's mark (단맛이 거의 없는 것은 증류식 소주의 특징이에요). The
    // subtitle and the tag call the step 옅은 단맛; the sentence says what
    // the reader answered (the user's review, 2026-11-24).
    open: side === "none"
      ? {
        taste: `${AXIS[axis].noun}{이} 거의 없는 것`,
        from: `${whose(c, card.kind)}의 특징이에요`,
      }
      : { taste, from: source(c, after !== "", card.kind) },
    why: link || apart || "",
  };
}

/**
 * What the taste did, after its ground: the sentence the point opened on
 * (`opened`) and the why that came next. The ground has just named the taste,
 * so a sentence that opens on it again (떫은맛이 입안을 조이며 …) goes on
 * without it.
 */
const SHORT_AFTER: Readonly<Record<string, string>> = {
  "단맛으로 감싸 줄 것이 없어 술이 메마르고 심심하게 느껴져요":
    "술이 메마르고 심심하게 느껴져요",
  "기분 좋은 단맛이 첫 모금을 부드럽고 포근하게 감싸 줘요":
    "첫 모금을 부드럽고 포근하게 감싸 줘요",
};

export function actAfter(
  opened: string,
  why: string,
  said: string,
  marks: readonly string[],
): string {
  const ground = `${opened} ${why}`;
  // After a ground that has named the sweetness the sentence goes on with
  // what it did alone (the returned review, 2026-11-27).
  said = /단맛/.test(ground) ? SHORT_AFTER[said] ?? said : said;
  // 그 온기가 points back at a word: where the ground has not said it, the
  // sentence names it plainly (… 도수에서 나와요. 따뜻한 온기가 향과 맛을 …);
  // 온기 alone at the head of a sentence reads cut off.
  const act = said.replace(
    /(^|\s)그 (\S\S)/g,
    (all, lead: string, word: string) =>
      ground.includes(word)
        ? all
        : `${lead}${word === "온기" ? "따뜻한 " : ""}${word}`,
  );
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
  const left = again ? act.slice(again.length) : act;
  // … 바닐라와 꿀 향이 우러나, 다른 맛을 누르고 혼자 앞으로 나서요 would
  // read as the aroma's doing, and … 단맛을 그대로 남겨, 다른 맛을 … as the
  // maker's: where the taste is not the why's own subject and the sentence
  // sets it against the others, the taste is named again.
  const others = again !== undefined && left.startsWith("다른 ") &&
    !marks.some((k) => why.includes(`${k}이 `) || why.includes(`${k}가 `));
  // … 오크의 떫은맛이 또렷하게 우러나, 입안을 떫게 조이고 … says 떫 twice.
  const rest = (others ? act : left).replace(
    ground.includes("떫") ? "떫게 " : "\u0000",
    "",
  );
  // … 여운이 삼킨 뒤에도 길게 이어져서, 삼킨 뒤에도 … says when twice.
  const when = "삼킨 뒤에도 ";
  const said_once = ground.includes(when.trim()) && rest.startsWith(when)
    ? rest.slice(when.length)
    : rest;
  // … 가볍게 넘어가, 입안에 머무는 느낌 없이 술술 넘어가요 says 넘어가 twice.
  return ground.includes("넘어가")
    ? said_once.replace(/술술 넘어가요$/, "목넘김이 매끄러워요")
    : said_once;
}

/** A taste in two words: its step's name, and a minded one as the whole card names it (mindedName). */
export function briefOf(
  g: { axis: GaugeAxis; level: number; side: string },
  section: Section,
): string {
  return section === "burden"
    ? mindedName(g.axis, g.level)
    : nameOf(g.axis, g.level);
}

/** A gauge answer as the section's subtitle names it. */
const titleOf = (
  g: Pick<Gauge, "axis" | "level">,
  section: Section,
  category: string | null,
) => titleName(g.axis, g.level, category, section === "burden");

/**
 * A still wine's sweetness told from the bottle's own tannin, acidity and
 * aromas, where they explain the answer (reason_wine_sweetness.ts).
 */
function wineSweetness(
  g: Pick<Gauge, "axis" | "level">,
  section: Section,
  feel: Feel,
  prepared: RecordReading,
  card: Card,
): { body: string } | null {
  if (g.axis !== "sweetness" || !card.sweetness) return null;
  const own = prepared.bottle.levels.sweetness;
  const told = tellWineSweetness(
    g.level,
    section,
    feel,
    card.kind,
    card.sweetness,
    own?.of === "bottle" ? own.level : null,
    prepared.answers,
  );
  return told && { body: told.body };
}

/**
 * Whether what a row of the table of senses is told by is an answer the
 * reader put on the other side: a sweetness they liked is not what made the
 * weight they minded, and an aroma they minded is not what made the
 * sweetness they liked (the user's word, 2026-11-21: one thing is not the
 * good and the bad of one card).
 */
export function onOtherSide(
  said: string,
  section: Section,
  answers: RecordReading["answers"],
): boolean {
  const p = said.split(":");
  if (p[0] === "answer") {
    return answers.gauges.some((g) =>
      g.axis === p[1] && g.reaction !== section
    );
  }
  // A picked aroma (aroma:melon), or one the bottle's own row lists
  // (kind:junmai_ginjo:melon): the reader may have picked that one too.
  const aroma = p[0] === "aroma" ? p[1] : p.length === 3 ? p[2] : null;
  return aroma !== null &&
    answers.aromas.some((a) => a.aroma === aroma && a.reaction !== section);
}

/**
 * A peat the reader found faint and liked, told by a cause that uses none
 * (피트 연기 없이 말린 보리 맥아로 만들어): what it did is then what no peat
 * does, not what a little of it adds (… 깊이만 더해 줘요).
 */
function unpeated(g: Gauge, section: Section, link: string): string | null {
  return g.axis === "peat" && g.level < 3 && section === "liked" &&
      /없이|않|배제/.test(link)
    ? feelOf("peat", 1, section).short
    : null;
}

/**
 * Whether the why of a cause speaks of something the reader put on the other
 * side of the card: 누룩에서 온 구수한 풍미와 산미가 뒷맛에 진하게 남아
 * blames, for a finish that was minded, the acidity that was liked. The
 * taste is then told by the cause's name alone.
 */
/** The words a why names each gauge's taste by: the taste itself, not what describes any taste (부드럽게, 깔끔하게). */
const NAMED_AS: Readonly<Record<GaugeAxis, RegExp>> = {
  sweetness: /단맛|달콤|당분/,
  acidity: /산미|산도|신맛|새콤/,
  umami: /감칠맛/,
  body: /바디감|무게감|묵직/,
  tannin: /타닌|떫/,
  spice: /알싸|열감|자극/,
  sparkling: /탄산|기포/,
  peat: /피트|스모키|훈연/,
  finish_length: /여운/,
  finish_character: /끝맛/,
};

/** Words that say a taste is strong, or faint, right before its name: 짙은 단맛, 옅은 산미. */
const STRONG = /(짙은|진한|풍부한|높은|강한|뚜렷한|넉넉한|묵직한|두터운) ?$/;
const FAINT = /(적은|낮은|옅은|가벼운|약한|은은한) ?$/;

/**
 * Whether a why calls a taste the reader answered strong where they said
 * there was little of it, or faint where they said it was strong (진한 끝맛
 * … 짙은 단맛이 마무리까지 남아, of a port they found not sweet).
 */
function saysOtherwise(
  why: string,
  own: GaugeAxis,
  answers: RecordReading["answers"],
): boolean {
  return answers.gauges.some((g) => {
    if (g.axis === own || g.level === 3) return false;
    const named = new RegExp(NAMED_AS[g.axis].source, "g");
    for (const m of why.matchAll(named)) {
      const before = why.slice(Math.max(0, m.index! - 6), m.index);
      if (g.level < 3 && STRONG.test(before)) return true;
      if (g.level > 3 && FAINT.test(before)) return true;
    }
    return false;
  });
}

function blamesOtherSide(
  why: string,
  own: GaugeAxis,
  section: Section,
  answers: RecordReading["answers"],
): boolean {
  return saysOtherwise(why, own, answers) ||
    answers.gauges.some((g) =>
      g.axis !== own && g.reaction !== section && NAMED_AS[g.axis].test(why)
    ) ||
    answers.aromas.some((a) =>
      a.reaction !== section && short(a.aroma) !== a.aroma &&
      why.includes(short(a.aroma))
    );
}

export function tellReason(
  reason: Reason,
  byId: ReadonlyMap<string, Evidence>,
  prepared: RecordReading,
  card: Card,
): Told | null {
  const section = reason.section;
  const { category } = prepared.bottle;
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
    // What in the glass let the aroma through. A taste the reader put on the
    // other side is not what did it: a low tannin they minded is not thanked
    // for the aroma they liked.
    const rule = rulesOf(first).find((rule) =>
      rule.by.every((b) => !onOtherSide(b.said, section, prepared.answers))
    );
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
        name: aromaLabel(key),
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
    name: titleOf(g, section, category),
    brief: briefOf(g, section),
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
      !own.has(b.said.split(":").slice(0, 2).join(":")) &&
      !onOtherSide(b.said, section, prepared.answers)
    );
    const first = said.length ? rowWords({ ...rule, by: said }) : null;
    return first ? [{ rule, first }] : [];
  })[0];

  // What held in this glass (탄산이 함께 있어서, …).
  const inGlass: Told | null = row
    ? {
      ...base,
      body: rowSentence(row.first, feel.short, marks),
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
  const why = told.factor !== "abv" && g.level !== 3 &&
      kindOfReason !== null && kindOfReason !== "style_only"
    ? howOf(told, g.axis, side)
    : null;
  const link =
    why && !blamesOtherSide(why, g.axis, section, prepared.answers) &&
      // 진한 단맛 … 은은한 단맛을 내서: a why that calls faint what the
      // reader found strong is not said.
      !(side === "high" && why.includes("은은"))
      ? why
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
  const trait = traitIn(g.axis, stepOn(first, told), section === "burden");
  // A middle step that was minded: nothing of it stood out, and that is no
  // mark of a kind or a place (애매한 단맛은 준마이의 특징이에요). It is
  // told as it was felt.
  if (section === "burden" && sideOf(g.axis, g.level) === "mid") {
    return {
      ...base,
      body: "",
      whole: true,
      causes: [],
      point: {
        cause: null,
        open: null,
        why: `이 ${card.kind}{은} ${feel.across}`,
        act: feel.long,
      },
    };
  }
  // 피트 향이 거의 없는 건 … 은은하게만 입혀: a cause that gives a little of
  // the taste is not the mark of none of it, so the point opens on the low
  // step. And a peat the reader found faint, from a cause that uses none
  // (피트를 쓰지 않은 맥아로 빚어 피트 향이 없어), opens as none.
  const answered = sideOf(g.axis, g.level);
  const opened: Side = link && answered === "none" &&
      /은은|약하게|살짝|소량/.test(link)
    ? "low"
    : link && g.axis === "peat" && answered === "low" &&
        /쓰지 않|없어서|없이|배제/.test(link)
    ? "none"
    : answered;
  const point = pointOf(
    told,
    opened === "low" && answered === "none"
      ? briefOf({ ...g, level: 2 }, section)
      : base.brief,
    trait[2],
    link,
    // A strength is already said to be high for its kind.
    stands_out && !link && told.factor !== "abv"
      ? `같은 종류 가운데서도 ${notably(trait[1])} 편이라`
      : null,
    g.axis,
    card,
    opened,
  );
  return {
    ...base,
    body: "",
    whole: true,
    point: {
      ...point,
      // A point that told why is long already: what it does is said in few
      // words, whether the why is the cause's own or what sets the bottle
      // apart (같은 종류 가운데서도 유난히 산미가 높은 편이라, …).
      act: actAfter(
        point.open?.taste ?? "",
        point.why,
        link
          ? (unpeated(g, section, link) ?? feel.short)
          // 그 조임이 with no 조임 before it: the short form names the taste.
          : point.why || /(^|\s)그 조임/.test(feel.long)
          ? feel.short
          : feel.long,
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
  prepared: RecordReading,
  card: Card,
): Told | null {
  const { gauges, aromas } = prepared.answers;
  const { category } = prepared.bottle;
  const g = gauges.find((x) => x.answer_ref === ref);
  if (g) {
    // A middle step alone says too little to be a reason.
    if (g.side === "middle") return null;
    const feel = feelOf(g.axis, g.level, section);
    const marks = AXIS[g.axis].marks;
    const base = {
      name: titleOf(g, section, category),
      brief: briefOf(g, section),
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
      const trait = traitIn(g.axis, g.level, section === "burden");
      const why = `${drink} ${
        apart ? `같은 종류 가운데서도 ${notably(trait[1])} 편이라` : trait[2]
      }`;
      return {
        ...base,
        point: {
          cause: null,
          open: null,
          why,
          // After the long ground what it did is said in few words.
          act: actAfter("", why, apart ? feel.short : feel.long, marks),
        },
      };
    }
    const act = actAfter("", feel.across, feel.long, marks);
    // Where the level read for the bottle stands the other way, the answer
    // is still told as it was felt in this glass and nothing is set against
    // it (the user's word, 2026-11-22: the glass's own impression).
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
