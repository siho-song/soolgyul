/**
 * 핵심 요약 tags: the answers the two reason sections are about, so that the
 * tags, the subtitles and the texts of one card speak of the same things.
 *
 * A tag names the step that was answered (묵직한 바디감, 적은 단맛), not the
 * bare sense: 단맛 liked says nothing of whether a dry or a sweet glass was
 * liked. At most three, 잘 맞았던 before 아쉬웠던, each side that has an answer
 * keeping one. Within a side the answer each reason leads with comes first,
 * then what else the reasons explain, then the answers no reason was found
 * for; a middle step is a tag only when a reason is told of it.
 *
 * The one line under the tags says the same answers as a sentence: … 잘
 * 맞았지만, … 조금 부담스러웠어요. A minded answer is named as the section
 * names it (mindedName), and what was too little of, or neither here nor
 * there, is said to be missed (아쉬웠어요), not to weigh (부담스러웠어요).
 *
 *   liked    a heart
 *   less     minded and strong: an arrow down (강한 떫은맛)
 *   burden   minded otherwise: a prohibit sign (적은 단맛, 풀 향)
 */
import type { RecordReading } from "../../record_reading/read_record.ts";
import { TAGS_PER_CARD } from "../limits.ts";
import type { Section, Selection } from "../selection/selection.ts";
import type { TasteCardTag } from "../service/types.ts";
import { andJoin, josa } from "../../korean.ts";
import { mindedAsFaint } from "./reason_aroma.ts";
import { aromaTagName, mindedName, sideOf, tagName } from "./reason_words.ts";

/** The tags, and the one line that says them: 높은 산미와 쌀 향은 반갑지만, 묵직한 바디감은 아직 조금 버거워요. */
export type TagSummary = { tags: TasteCardTag[]; line: string | null };

export function writeTags(
  prepared: RecordReading,
  selection: Selection,
): TagSummary {
  const { gauges, aromas } = prepared.answers;
  /** A tag with its name spaced as a sentence says it, and whether a minded one was a lack. */
  type Named = TasteCardTag & { name: string; lack: boolean };
  const tagOf = (
    ref: string,
    section: Section,
    told: boolean,
  ): Named | null => {
    const g = gauges.find((x) => x.answer_ref === ref);
    if (g) {
      if (g.side === "middle" && !told) return null;
      const minded = section === "burden";
      const name = minded
        ? mindedName(g.axis, g.level)
        : tagName(g.axis, g.level);
      return {
        // The chip of a step set to none stays 단맛 없음, liked or minded.
        label: sideOf(g.axis, g.level) === "none"
          ? tagName(g.axis, g.level)
          : name,
        name,
        // Too little of it, or neither here nor there.
        lack: minded && g.side !== "high",
        kind: section === "liked"
          ? "liked"
          : g.side === "high"
          ? "less"
          : "burden",
      };
    }
    const a = aromas.find((x) => x.answer_ref === ref);
    if (!a) return null;
    const name = aromaTagName(a.aroma);
    const lack = section === "burden" && mindedAsFaint(a.aroma);
    return {
      label: name,
      // An aroma that was missed for being faint is said so in the one line
      // (옅은 레몬 향은 조금 아쉬웠어요); its tag is the aroma alone.
      name: lack ? `옅은 ${name}` : name,
      lack,
      kind: section === "liked" ? "liked" : "burden",
    };
  };
  const side = (section: Section): Named[] => {
    const { reasons, untold } = selection[section];
    const refs: [string, boolean][] = [
      ...reasons.map((r) => [r.answers[0], true] as [string, boolean]),
      ...reasons.flatMap((r) =>
        r.answers.slice(1).map((ref) => [ref, true] as [string, boolean])
      ),
      ...untold.map((ref) => [ref, false] as [string, boolean]),
    ];
    const out: Named[] = [];
    for (const [ref, told] of refs) {
      const tag = ref ? tagOf(ref, section, told) : null;
      if (tag && !out.some((t) => t.label === tag.label)) out.push(tag);
    }
    return out;
  };
  const sides = [side("liked"), side("burden")].filter((s) => s.length);
  const first = sides.map((s) => s[0]);
  // The second answer of each side before the third of any.
  const rest = [1, 2].flatMap((i) => sides.flatMap((s) => s[i] ?? []));
  const chosen = [...first, ...rest.slice(0, TAGS_PER_CARD - first.length)];
  const kept = sides.flat().filter((t) => chosen.includes(t));
  return {
    tags: kept.map((t) => ({
      // 정향 향 as a chip is 정향, not 정향향.
      label: t.label.replace(/향 향$/, "향").replaceAll(" ", ""),
      kind: t.kind,
    })),
    line: lineOf(
      kept.filter((t) => t.kind === "liked"),
      kept.filter((t) => t.kind !== "liked"),
    ),
  };
}

/** The tags as one sentence, in the card's own wordings (2026-11-03). */
function lineOf(
  liked: readonly { name: string }[],
  minded: readonly { name: string; lack: boolean }[],
): string | null {
  if (!liked.length && !minded.length) return null;
  // A liked tag says 단맛 없음; a sentence says 단맛 없는 깔끔함, or 단맛
  // 없는 담백함 beside another name that says 깔끔 (깔끔한 끝맛). 담백 is a
  // word for sweetness alone: 탄산 없는 깔끔함 stays.
  // Two tastes that were liked for not being there are one cleanness.
  if (
    !minded.length && liked.length === 2 &&
    liked.every((t) => t.name.endsWith(" 없음"))
  ) {
    const [a, b] = liked.map((t) => t.name.slice(0, -3));
    return josa(
      `${a}{과} ${b}{이} 거의 없는 깔끔함이 잘 어울려 마음에 들었어요.`,
    );
  }
  const clean = liked.some((t) => t.name.includes("깔끔"));
  const l = liked.map((t) =>
    t.name.replace(
      / 없음$/,
      clean && t.name === "단맛 없음" ? " 없는 담백함" : " 없는 깔끔함",
    )
  );
  if (!minded.length) {
    return josa(
      l.length === 1
        ? `${l[0]}{이} 기분 좋게 잘 맞았어요.`
        : l.length === 2
        ? `${l[0]}{과} ${l[1]}{이} 잘 어울려 마음에 들었어요.`
        : `${l[0]}{과} ${l[1]}, ${l[2]}까지 고루 마음에 들었어요.`,
    );
  }
  // 애매한 단맛과 애매한 여운, 옅은 끝맛과 옅은 레몬 향: a word two names
  // open with is said once.
  const names = (tags: readonly { name: string }[]) =>
    andJoin(tags.map((t, i) => {
      const [head, ...rest] = t.name.split(" ");
      return i > 0 && rest.length && tags[i - 1].name.startsWith(`${head} `)
        ? rest.join(" ")
        : t.name;
    }));
  // 옅은 피트 향은 잘 맞았지만, 옅은 끝맛은 … says 옅은 of what was liked
  // and of what was missed: the liked one is 은은한.
  if (minded.some((t) => t.name.startsWith("옅은 "))) {
    l.forEach((name, i) => l[i] = name.replace(/^옅은 /, "은은한 "));
  }
  // 거의 없는 단맛은 조금 아쉬웠어요 is no sentence one says: 단맛이 거의
  // 없어 조금 아쉬웠어요 (the returned review, res/4_1_129.md, 2026-11-27).
  const NONE = "거의 없는 ";
  const missing = (tags: readonly { name: string }[]) =>
    tags.length > 0 && tags.every((t) => t.name.startsWith(NONE))
      ? `${
        andJoin(tags.map((t) => t.name.slice(NONE.length)))
      }{이} 거의 없어 조금 아쉬웠어요`
      : `${names(tags)}{은} 조금 아쉬웠어요`;
  // What weighed and what was missed are two things said two ways.
  const weighed = minded.filter((t) => !t.lack);
  const missed = minded.filter((t) => t.lack);
  const alone = !l.length;
  const felt = weighed.length && missed.length
    // 조금 once: of what was missed.
    ? `${names(weighed)}{은} 부담스러웠고, ${missing(missed)}`
    : missed.length
    ? missing(missed)
    : `${names(weighed)}{은} ${
      alone ? "조금 부담스럽게 느껴졌어요" : "조금 부담스러웠어요"
    }`;
  return josa(alone ? `${felt}.` : `${andJoin(l)}{은} 잘 맞았지만, ${felt}.`);
}
