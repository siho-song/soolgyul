// The card the engine writes for one record: 술결 한입 (별명 · 핵심 요약 ·
// 다음 술 가이드) and the paragraphs of 왜 잘 맞았을까요 / 왜 부담이었을까요.
import { CARD_FACTS_SCHEMA_VERSION } from "../facts/facts.ts";
import { findEvidence } from "../evidence/evidence.ts";
import { selectNickname } from "../nickname/selector.ts";
import { prepareCard, type Prepared } from "../prepare/prepare.ts";
import { selectReasons } from "../selection/selection.ts";
import { writeReasons, type WrittenReasons } from "./reasons.ts";
import { writeNext } from "./next.ts";
import { writeTags } from "./tags.ts";
import type { SensoryRecord } from "../record/sensory_record.ts";
import type {
  TasteCardNext,
  TasteCardParagraph,
  TasteCardTag,
} from "../service/types.ts";

export const CARD_ENGINE_VERSION = CARD_FACTS_SCHEMA_VERSION;

type CardText = {
  /** What the record was read to: its answers and its bottle. */
  reading: Prepared;
  nickname: string;
  /** 핵심 요약: the tags (흙향 liked …) and the one line under them. */
  tags: readonly TasteCardTag[];
  summary: string;
  /** The summary with its dressing left off, for a record card's one line. */
  brief: string;
  /** 다음 방향; null when there is nothing to say. */
  next: TasteCardNext | null;
  positive: TasteCardParagraph[];
  burden: TasteCardParagraph[];
};

/**
 * The one line of a card whose answers name nothing the summary can say:
 * no sensation at all (only 다시 마시고 싶은지), or only steps the summary
 * has no words for (a middle 바디, 끝맛의 인상), which the note still shows.
 */
const NOTHING_CHOSEN = "이번 기록에는 고른 감각이 없어요.";
const KEPT_IN_NOTE = "이번에 고른 감각은 테이스팅 노트에 담았어요.";

/** A section as the card shows it: its subtitle and its one text, or nothing. */
function sectionParagraphs(section: WrittenReasons): TasteCardParagraph[] {
  return section.text ? [{ answer: section.title, text: section.text }] : [];
}

/** Writes the whole card for one record. */
export function writeCard(
  record: SensoryRecord,
  // The name the reader gave the bottle: no sentence of the card says it now.
  _productName?: string,
): CardText {
  // 준비 → 근거 찾기 → 결과 선정 → 글쓰기: the two reason sections.
  const prepared = prepareCard(record);
  const found = findEvidence(prepared);
  const selection = selectReasons(prepared, found);
  const { liked: positive, burden } = writeReasons(
    prepared,
    found,
    selection,
  );
  const summary = writeTags(prepared, selection);
  const { gauges, aromas } = prepared.interpretation;
  const plain = gauges.length || aromas.length ? KEPT_IN_NOTE : NOTHING_CHOSEN;
  return {
    reading: prepared,
    nickname: selectNickname(prepared.interpretation),
    tags: summary.tags,
    summary: summary.line ?? plain,
    brief: summary.line ?? plain,
    next: writeNext(prepared, found, selection),
    positive: sectionParagraphs(positive),
    burden: sectionParagraphs(burden),
  };
}
