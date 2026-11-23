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
 * The one line under the tags says the same answers as a sentence, in the
 * wordings the card has always used (… 반갑지만, … 아직 조금 버거워요).
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
import { aromaTagName, tagName } from "./reason_words.ts";

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
      const name = tagName(g.axis, g.level);
      return {
        label: name,
        name,
        lack: section === "burden" && g.side === "low",
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
    return {
      label: name,
      name,
      lack: false,
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
      label: t.label.replaceAll(" ", ""),
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
  // A tag says 단맛 없음; a sentence says 단맛 없는 깔끔함.
  const said = (t: { name: string }) =>
    t.name.replace(/ 없음$/, " 없는 깔끔함");
  const names = (tags: readonly { name: string }[]) => andJoin(tags.map(said));
  const l = liked.map(said);
  // What was wanted more of is missed, not too much.
  const weighs = minded.every((t) => t.lack)
    ? "조금 아쉬웠어요"
    : "조금 부담스럽게 느껴졌어요";
  if (!l.length && !minded.length) return null;
  if (!minded.length) {
    return josa(
      l.length === 1
        ? `${l[0]}{이} 기분 좋게 잘 맞았어요.`
        : l.length === 2
        ? `${l[0]}{과} ${l[1]}{이} 잘 어울려 마음에 들었어요.`
        : `${l[0]}{과} ${l[1]}, ${l[2]}까지 고루 마음에 들었어요.`,
    );
  }
  if (!l.length) return josa(`${names(minded)}{은} ${weighs}.`);
  return josa(
    `${names(liked)}{은} 잘 맞았지만, ${names(minded)}{은} ${
      minded.every((t) => t.lack) ? "조금 아쉬웠어요" : "조금 부담스러웠어요"
    }.`,
  );
}
