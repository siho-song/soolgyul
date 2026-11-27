/**
 * 글쓰기: the fourth stage of the 술결카드 생성 파이프라인. It says the
 * reasons 결과 선정 chose as the text of one section (잘 맞았던 이유,
 * 아쉬웠던 이유). It finds and chooses nothing.
 *
 * A section is a list (the user's form, 2026-11-22): one line a reason, two
 * at most, and a line that closes on them, a blank line between the lines.
 *
 *   **말벡**은 색소가 진하고 껍질이 두꺼워 **묵직한** 질감이 우러나, 한
 *   모금에도 입안이 든든하게 차요.
 *
 *   이 품종 특유의 **자두 향**이 새콤달콤하게 퍼지면서 무거움을 덜어 줘서
 *   끝까지 경쾌하게 마시기 좋아요.
 *
 *   묵직한 바디감과 자두 향이 균형을 이뤄서 입맛에 **잘 맞으셨던** 것 같아요.
 *
 *   a reason       {ground}, {what the taste does}. The second half is the
 *                  sentence the card has always said (FEEL). The first half
 *                  is a fact of the bottle that makes it easier to believe:
 *                  the cause and why it makes the taste (**말벡**은 … 우러나),
 *                  the cause named by what it is (**산 후안** 지역의 특성상
 *                  떫은맛이 또렷해), what was done (**버번 캐스크**에서
 *                  숙성해), or, with no fact, how it came across (이 와인에서는
 *                  …). The causes are set in ** so that the app opens the
 *                  dictionary's explanation.
 *   in this glass  a row of the table of senses that held (높은 산미가 함께
 *                  있어, …).
 *   an aroma       where it comes from, how it sat in the glass and what
 *                  that did.
 *   the closing    the reasons named again in two words and what they came
 *                  to; when the reader liked at the very end of the gauge
 *                  what sets the bottle apart among its kind, what that tells
 *                  of their taste.
 *
 * Nothing leads from one line to the next. A cause is named once a section.
 * When 결과 선정 chose fewer than two reasons, an answer no cause was found
 * for is told the same way from what was felt alone.
 *
 * This file puts a section together. Its parts:
 *   reason_taste.ts   a taste as a reason, with its cause or from what was felt
 *   reason_wine_sweetness.ts  a still wine's sweetness, from the bottle's own traits
 *   reason_aroma.ts   an aroma as a reason, and where it comes from
 *   reason_glass.ts   a row of the table of senses that held in the glass
 *   reason_causes.ts  how a cause is named (지역, 품종, 증류소, …)
 *   reason_words.ts   the words of a sense and of its steps
 *   reason_feel.ts    what a sense does in the mouth, liked or minded
 *   reason_marks.ts   the words of a line the dictionary explains
 *   reason_told.ts    the types passed between them
 */
import type { Cause, EvidenceResult } from "../evidence/evidence.ts";
import { shelfOfKind } from "../../record_reading/facts/kind_place.ts";
import {
  readWineSweetness,
  WINE_LEVELS,
} from "../../record_reading/facts/wine_sweetness.ts";
import type { RecordReading } from "../../record_reading/read_record.ts";
import type { Section, Selection } from "../selection/selection.ts";
import { standsOutIn } from "../selection/standing.ts";
import { LINES_PER_SECTION } from "../limits.ts";
import { josa } from "../../korean.ts";
import { KIND_LABEL, STYLE_KIND_LABEL } from "./words.ts";
import { aromaCause, tellAroma } from "./reason_aroma.ts";
import { usualAromaFor } from "./usual_aroma.ts";
import { bare, causeKey, same } from "./reason_causes.ts";
import { explainedWords } from "./reason_marks.ts";
import { tellFelt, tellReason } from "./reason_taste.ts";
import { type Card, type Told } from "./reason_told.ts";
import { AXIS, KIND_NOUN } from "./reason_words.ts";

export type WrittenReasons = {
  /**
   * The answers the section explains, each in two words: "낮은 타닌, 체리
   * 향"; "" when the section says nothing. It says which answers, not how
   * they felt: the text under it does that (the user's review, 2026-11-24).
   */
  title: string;
  /** The sentences of the section, the causes and sensations in ** marks. */
  text: string;
  /** How many sentences of reason the text tells. */
  reasons: number;
};

export type ReasonOptions = {
  /** Whether an answer no cause was found for is told from what was felt. */
  unexplained: boolean;
};

/** The first place one of the words stands outside a mark, as [at, word]. */
function firstOf(
  text: string,
  words: readonly string[],
): [number, string] | null {
  let best: [number, string] | null = null;
  for (const w of words) {
    for (let at = text.indexOf(w); at >= 0; at = text.indexOf(w, at + 1)) {
      const inMark = (text.slice(0, at).split("**").length - 1) % 2 === 1;
      if (inMark) continue;
      if (
        !best || at < best[0] || (at === best[0] && w.length > best[1].length)
      ) {
        best = [at, w];
      }
      break;
    }
  }
  return best;
}

/**
 * A sentence with its sense in ** marks, once. Where the sentence names the
 * sense itself, that name is the word (묵직한 **바디감**은 …), not a word
 * that describes it (the user's review, 2026-11-22).
 */
function marked(
  text: string,
  marks: readonly string[],
  noun?: string,
): string {
  const hit = (noun ? firstOf(text, [noun]) : null) ?? firstOf(text, marks);
  if (!hit) return text;
  const [at, w] = hit;
  return `${text.slice(0, at)}**${w}**${text.slice(at + w.length)}`;
}

/**
 * 묵직해서, → 묵직해,: a line of the list says its first half in fewer words.
 * 퍼지면서 and 통에서 are other words, and a one-letter stem (세서) keeps it.
 */
const clipped = (text: string) =>
  text.replace(
    /(\S+)서, /g,
    (all, stem: string) =>
      stem.length >= 2 && !/[면에]$/.test(stem) ? `${stem}, ` : all,
  );

/** What a sentence is about, as one word: body:high, effect_sour_fruit. */
const about = (t: Told) =>
  t.of?.axis ? `${t.of.axis}:${t.of.side}` : t.of?.aroma ?? "";

const HEAVY = new Set(["body:high", "finish_character:high", "umami:high"]);

const DEEP = new Set([
  "body:high",
  "finish_character:high",
  "finish_length:high",
  "umami:high",
  "peat:high",
  "effect_grain_nut",
  "effect_roast",
  "effect_wood",
  "effect_smoke",
  "effect_earth",
  "effect_savory",
  "effect_aged",
]);

const LIFTS = new Set([
  "acidity:high",
  "sparkling:high",
  "effect_sour_fruit",
  "effect_fresh_fruit",
  "effect_floral",
  "effect_green",
  "effect_mineral",
]);

/**
 * What a section's second reason did to its first, where the two pull apart
 * (the user's example, 2026-11-22: … 새콤달콤하게 퍼지면서 무거움을 덜어 줘서
 * 끝까지 경쾌하게 마시기 좋아요), said in place of what the second did alone.
 * Which tastes weigh, lift or deepen is read here from the kind of taste.
 * Null for any other pair: each then says what it did itself.
 */
function linkOf(a: Told, b: Told, section: Section): string | null {
  const x = about(a);
  const y = about(b);
  if (section !== "liked" || !x || !y) return null;
  if (HEAVY.has(x) && LIFTS.has(y)) {
    // A body that was liked is not a weight to be lifted off.
    return `${
      x === "body:high" ? "입안을 산뜻하게 정리해 줘서" : "무거움을 덜어 줘서"
    } 끝까지 경쾌하게 마시기 좋아요`;
  }
  if (x === "body:low" && DEEP.has(y)) {
    return "가벼운 질감에 깊이를 더해 줘요";
  }
  return null;
}

/**
 * 글쓰기: the reasons 결과 선정 chose, as one subtitle and one text for each
 * section. Pure.
 */
export function writeReasons(
  prepared: RecordReading,
  found: EvidenceResult,
  selection: Selection,
  options: ReasonOptions = { unexplained: true },
): Record<Section, WrittenReasons> {
  const { category, style_key } = prepared.bottle;
  const kind = STYLE_KIND_LABEL[style_key ?? ""] ??
    KIND_NOUN[style_key ?? ""] ?? KIND_LABEL[style_key ?? ""] ??
    KIND_LABEL[category ?? ""] ??
    (category === "korean_traditional" ? "전통주" : "술");
  const card: Card = {
    kind,
    brewed: category === "sake" || category === "korean_traditional",
    wine: category === "wine",
    shelf: shelfOfKind(style_key, category),
    sweetness: readWineSweetness({
      style_key,
      category,
      levels: Object.fromEntries(
        WINE_LEVELS.flatMap((d) => {
          const read = prepared.bottle.levels[d];
          return read?.of === "bottle" ? [[d, read.level]] : [];
        }),
      ),
      aromas: prepared.bottle.tags.filter((t) => t.section === "aroma").map((
        t,
      ) => t.key).sort(),
    }),
    strong: found.identity.causes.some((c) => c.key === "abv_high"),
    usualAroma: usualAromaFor(prepared.bottle, found.identity),
    standsOut: standsOutIn(prepared.bottle),
  };
  const write = (section: Section) =>
    writeSection(section, prepared, found, selection, options, card);
  return { liked: write("liked"), burden: write("burden") };
}

function writeSection(
  section: Section,
  prepared: RecordReading,
  found: EvidenceResult,
  selection: Selection,
  options: ReasonOptions,
  card: Card,
): WrittenReasons {
  const byId = new Map(found.evidence.map((e) => [e.id, e]));
  const chosen = selection[section];
  const told: Told[] = [];
  const add = (t: Told | null) => {
    if (
      t && told.length < LINES_PER_SECTION &&
      !told.some((x) => x.name === t.name)
    ) {
      told.push(t);
    }
  };
  for (const reason of chosen.reasons) {
    const t = tellReason(reason, byId, prepared, card);
    // 단맛이 적어서 산미가, 산미가 높아서 단맛이: said one way round only.
    const circular = t?.glass &&
      told.some((x) =>
        x.glass && x.glass.by.includes(t.glass!.of) &&
        t.glass!.by.includes(x.glass.of)
      );
    // A reason the sentence cannot say (or would say in a circle) is still
    // an answer the reader felt: it is told as it was felt.
    add(
      t && !circular ? t : tellFelt(reason.answers[0], section, prepared, card),
    );
  }
  const reasons = told.length;
  // An aroma a reason explains beside its taste is a sentence of its own
  // while there is room.
  for (const reason of chosen.reasons) {
    for (const id of reason.evidence.slice(1)) {
      const e = byId.get(id);
      if (e?.answer.kind !== "aroma" || e.type === "aroma_effect") continue;
      const causes = e.causes.map(bare);
      const cause = (reason.told_by &&
        causes.find((c) => same(c, reason.told_by!))) ?? causes[0] ?? null;
      add(
        tellAroma(e.answer.aroma, aromaCause(cause, causes), section, card),
      );
    }
  }
  if (options.unexplained) {
    for (const ref of chosen.untold) {
      add(tellFelt(ref, section, prepared, card));
    }
  }
  if (!told.length) return { title: "", text: "", reasons: 0 };

  // A cause is named once a section. The next section may name it again for
  // another taste: the grape that gave the weight the reader liked is also
  // what gave the tannin they minded.
  const named = new Set<string>();
  // What the section's sentences have said so far: a cause one of them has
  // spoken of is not named as new again.
  let spoken = "";
  const told_of = (c: Cause) => named.has(causeKey(c)) || spoken.includes(c.ko);
  const sentences = told.map((t, i) => {
    const text = sentence(t, i);
    spoken += ` ${text}`;
    return text;
  });

  // Each reason is a line of its own: nothing leads from one to the next.
  function sentence(t: Told, i: number): string {
    const link = i === 1 ? linkOf(told[0], t, section) : null;

    if (t.point) {
      // The taste and what it comes from, then why and what it does. What
      // the two reasons do together (무거움을 덜어 줘서 …) is said in place
      // of what this one does alone. A cause the section has told of already
      // gives this taste too (높은 산미도 …).
      const p = t.point;
      const again = p.cause !== null && told_of(p.cause);
      if (p.cause) named.add(causeKey(p.cause));
      const rest = [p.why, link ?? p.act].filter(Boolean).join(p.glue ?? ", ");
      // 단맛이 거의 없는 것은 is said as it is spoken: 없는 건.
      const topic = again
        ? `${p.open?.taste}도`
        : p.open?.taste.endsWith(" 것")
        ? `${p.open.taste.slice(0, -1)}건`
        : `${p.open?.taste}{은}`;
      return p.open ? `${topic} ${p.open.from}. ${rest}.` : `${rest}.`;
    }
    if (t.whole) {
      for (const c of t.causes) named.add(causeKey(c));
      return `${t.body}.`;
    }
    // What held in this glass (탄산이 함께 있어서, …).
    return `${t.body}.`;
  }

  // Every word of a line the dictionary explains is marked, the cause it is
  // told by or not (네비올로 껍질과 씨에서 …, 높은 산미가 함께 있어 …): the
  // reader can open it wherever it stands (the user's review, 2026-11-22).
  const own = found.evidence.flatMap((e) => e.causes).filter((c) =>
    c.factor !== "abv" && c.factor !== "age" && c.factor !== "kind"
  ).map((c) => bare(c).ko);
  const lines = sentences.map((text, i) =>
    explainedWords(
      marked(
        josa(clipped(text)),
        told[i].marks,
        told[i].of?.axis ? AXIS[told[i].of!.axis!].noun : undefined,
      ),
      own,
    )
  );

  return {
    title: told.map((t) => t.name).join(", "),
    // A point a reason, a blank line between two.
    text: lines.map((line) => `• ${line}`).join("\n\n"),
    reasons,
  };
}
