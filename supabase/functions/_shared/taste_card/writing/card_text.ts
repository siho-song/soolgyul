// The card the engine writes for one record: 술결 한입 (별명 · 핵심 요약 ·
// 다음 술 가이드) and the paragraphs of 왜 잘 맞았을까요 / 왜 부담이었을까요.
import { buildCardFacts } from "../findings/conclusions.ts";
import { CARD_FACTS_SCHEMA_VERSION, type CardFacts } from "../facts/facts.ts";
import { writeGuide } from "../summary/guide.ts";
import { writeSummary } from "../summary/summary.ts";
import {
  balancedSummary,
  isBalanced,
  writeBalancedSection,
} from "./balanced.ts";
import { writeSection, type WrittenSection } from "./sections.ts";
import type { SensoryRecord } from "../record/sensory_record.ts";
import type {
  TasteCardGuide,
  TasteCardParagraph,
  TasteCardTag,
} from "../service/types.ts";

export const CARD_ENGINE_VERSION = CARD_FACTS_SCHEMA_VERSION;

type CardText = {
  facts: CardFacts;
  nickname: string;
  /** 핵심 요약: the tags (흙향 liked …) and the one line under them. */
  tags: readonly TasteCardTag[];
  summary: string;
  /** The summary with its dressing left off, for a record card's one line. */
  brief: string;
  /** 다음 술은 이렇게 골라보세요; null when nothing in the dictionary fits. */
  guide: TasteCardGuide | null;
  positive: TasteCardParagraph[];
  burden: TasteCardParagraph[];
  /** 왜 편안했을까요: only on the balanced card (every taste 적당했어요). */
  balanced: TasteCardParagraph[];
};

/** A section as the card shows it: its subtitle and its one text, or nothing. */
function sectionParagraphs(section: WrittenSection): TasteCardParagraph[] {
  return section.paragraphs.length
    ? [{ answer: section.title, text: section.text }]
    : [];
}

/** Writes the whole card for one record. */
export function writeCard(
  record: SensoryRecord,
  productName?: string,
): CardText {
  const facts = buildCardFacts(record);
  const options = productName ? { productName } : {};
  const positive = writeSection(facts, "positive", options);
  const burden = writeSection(facts, "burden", options);
  const name = productName ?? facts.record.product_name;
  const balanced = isBalanced(facts);
  const summary = balanced
    ? balancedSummary(facts, name)
    : writeSummary(facts, positive, burden, options)!;
  const guide = writeGuide(
    productName
      ? { ...facts, record: { ...facts.record, product_name: productName } }
      : facts,
  );
  return {
    facts,
    nickname: facts.nickname,
    tags: summary.tags,
    summary: summary.line,
    brief: summary.brief,
    guide,
    positive: sectionParagraphs(positive),
    burden: sectionParagraphs(burden),
    balanced: balanced ? writeBalancedSection(facts, name) : [],
  };
}
