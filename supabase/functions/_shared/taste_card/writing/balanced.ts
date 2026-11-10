// The balanced card: a record where nothing was liked or minded and every
// taste was 적당했어요. The bottle's own levels say what "적당" meant for this
// reader — a dry wine that did not feel thin, a brisk acidity that did not
// sting — so the card talks about the reader's comfort zone instead of
// repeating that nothing stood out.
import type { CardFacts } from "../facts/facts.ts";
import type { Summary } from "../summary/summary.ts";
import { josa } from "./korean.ts";
import { terms } from "../dictionary/dictionary.ts";
import type { TasteCardParagraph } from "../service/types.ts";

type TasteKey = "sweetness" | "acidity" | "bitterness";
const TASTES: readonly TasteKey[] = ["sweetness", "acidity", "bitterness"];
const TASTE_NAME: Readonly<Record<TasteKey, string>> = {
  sweetness: "단맛",
  acidity: "산미",
  bitterness: "쓴맛",
};

type Band = "low" | "mid" | "high";
type Fine = {
  key: TasteKey;
  level: number;
  band: Band;
  /** The level is the kind's usual value, not a reading of this bottle. */
  estimated: boolean;
};

/** Nothing liked or minded, and at least one 적당했어요. */
export function isBalanced(facts: CardFacts): boolean {
  const reacted = facts.reactions.filter((r) => r.reaction !== "unstated");
  return reacted.length > 0 && reacted.every((r) => r.reaction === "fine");
}

/** The tastes answered 적당했어요 whose level the bottle (or its kind) has. */
function fineTastes(facts: CardFacts): Fine[] {
  const out: Fine[] = [];
  for (const key of TASTES) {
    const fine = facts.reactions.some((r) =>
      r.reaction === "fine" && r.subject.domain === "taste" &&
      r.subject.key === key
    );
    if (!fine) continue;
    const fact = facts.product_facts.find((p) =>
      p.fact.type === "level" && p.fact.dimension === key
    )?.fact;
    if (!fact || fact.type !== "level") continue;
    const band: Band = fact.level <= 2
      ? "low"
      : fact.level >= 4
      ? "high"
      : "mid";
    out.push({
      key,
      level: fact.level,
      band,
      estimated: fact.estimated === true,
    });
  }
  return out;
}

/** 와인, 위스키 …: the category as the dictionary names it. */
function categoryWord(facts: CardFacts): string {
  const row = terms("category").find((t) => t.key === facts.record.category);
  return row?.names.ko ?? "술";
}

/** 레드 와인, 싱글 몰트 위스키 …: the kind, else the category. */
function kindWord(facts: CardFacts): string {
  const styleKeys = facts.product_facts.flatMap((p) =>
    p.fact.type === "style" ? [p.fact.key] : []
  );
  const row = terms("kind").find((t) => styleKeys.includes(t.key));
  return row?.names.ko ?? categoryWord(facts);
}

/** The tag label and the line phrase a notable level earns on the balanced card. */
const TRAIT_TAG: Readonly<Record<string, string>> = {
  "sweetness.low": "드라이",
  "sweetness.high": "달콤함",
  "acidity.high": "산뜻함",
  "acidity.low": "부드러움",
  "bitterness.high": "쌉쌀함",
  "bitterness.low": "순함",
};
const HIGH_TRAIT: Readonly<Record<TasteKey, string>> = {
  sweetness: "넉넉한 단맛",
  acidity: "또렷한 산미",
  bitterness: "쌉쌀한 쓴맛",
};

/**
 * 핵심 요약 of the balanced card: 밸런스 (적당) with the bottle's notable
 * levels as tags, and one line on how it went down (the user's wording,
 * 2026-11-03). A pronounced level the reader called 적당 is named in the
 * line; a low one reads as 부드럽고 담백.
 */
export function balancedSummary(
  facts: CardFacts,
  _productName: string,
): Summary {
  const notable = fineTastes(facts).filter((f) => f.band !== "mid");
  const tags = [
    "밸런스",
    ...notable.map((f) => TRAIT_TAG[`${f.key}.${f.band}`]),
  ].slice(0, 3).map((label) => ({ label, kind: "fine" as const }));
  const high = notable.filter((f) => f.band === "high").map((f) =>
    HIGH_TRAIT[f.key]
  );
  const line = high.length
    ? josa(
      `${
        high.length === 2 ? josa(`${high[0]}{과} ${high[1]}`) : high.join(", ")
      }{이} 튀지 않고 어우러져서, 부담 없이 편안하게 술술 넘어가요.`,
    )
    : notable.length
    ? "튀는 맛 없이 부드럽고 담백해서, 부담 없이 편안하게 술술 넘어가요."
    : "튀는 맛 없이 고르게 어우러져서, 부담 없이 편안하게 술술 넘어가요.";
  const brief = high.length
    ? josa(
      `${
        high.length === 2 ? josa(`${high[0]}{과} ${high[1]}`) : high.join(", ")
      }{이} 튀지 않고 편안하게 넘어가요.`,
    )
    : "튀는 맛 없이 편안하게 술술 넘어가요.";
  return { shape: "밸런스", tags, line, brief };
}

/* --------------------------------------------------------- paragraphs */

type Template = {
  title: string;
  /** First sentence: this bottle's own level, or what such a kind usually is. */
  own: string;
  usual: string;
  rest: string;
};

// {name} bottle, {cat} category word, {kind} kind word.
const TEMPLATES: Readonly<Record<string, Template>> = {
  "acidity.high": {
    title: "산미가 튀지 않고 적당했어요",
    own: "사실 {name}{은} 일반 {cat}보다 산미가 꽤 높은 편에 속해요.",
    usual: "{kind}{은} 보통 산미가 꽤 높은 편이에요.",
    rest:
      "보통 산미가 이 정도로 높으면 시큼하게 튀어서 낯설어하는 분들도 많거든요. 그런데도 이 산미를 자극적이지 않고 ‘적당하다’고 느끼셨다면, 이미 선명한 산미를 편안하게 받아들일 만큼 입맛이 열려 있으신 거예요.",
  },
  "acidity.low": {
    title: "순한 산미가 적당했어요",
    own: "{name}{은} 산미가 낮은 편인 {cat}{예요}.",
    usual: "{kind}{은} 보통 산미가 낮은 편이에요.",
    rest:
      "산미가 이렇게 순하면 밋밋하거나 무겁다고 느끼는 분들도 있거든요. 그런데도 이 정도를 ‘적당하다’고 느끼셨다면, 새콤함이 앞서지 않는 둥근 결을 편안하게 즐기시는 입맛이에요.",
  },
  "sweetness.low": {
    title: "단맛 없이도 적당하고 편안했어요",
    own: "{name}{은} 단맛이 거의 없는 아주 드라이한 {cat}{예요}.",
    usual: "{kind}{은} 보통 단맛이 거의 없는 드라이한 쪽이에요.",
    rest:
      "단맛이 아예 없으면 입안이 허전하거나 밍밍하다고 느끼기 쉬운데, 이 정도 당도를 ‘적당하다’고 느끼셨다면 굳이 단맛의 도움을 받지 않아도 술 본연의 풍미를 온전히 즐기실 수 있는 입맛이에요.",
  },
  "sweetness.high": {
    title: "넉넉한 단맛이 과하지 않고 적당했어요",
    own: "{name}{은} 단맛이 꽤 넉넉한 편인 {cat}{예요}.",
    usual: "{kind}{은} 보통 단맛이 꽤 넉넉한 편이에요.",
    rest:
      "단맛이 이 정도면 물리거나 무겁다고 느끼는 분들도 많거든요. 그런데도 이 단맛을 과하지 않고 ‘적당하다’고 느끼셨다면, 달콤함이 앞서는 술을 부담 없이 즐기실 수 있는 입맛이에요.",
  },
  "bitterness.high": {
    title: "쓴맛이 튀지 않고 적당했어요",
    own: "{name}{은} 쓴맛이 꽤 있는 편인 {cat}{예요}.",
    usual: "{kind}{은} 보통 쓴맛이 꽤 있는 편이에요.",
    rest:
      "쓴맛이 이 정도면 거슬린다고 느끼는 분들도 많거든요. 그런데도 이 쓴맛을 자극적이지 않고 ‘적당하다’고 느끼셨다면, 쌉쌀한 결을 이미 편안하게 받아들이시는 입맛이에요.",
  },
  "bitterness.low": {
    title: "쓴맛 없이도 적당하고 편안했어요",
    own: "{name}{은} 쓴맛이 거의 없는 {cat}{예요}.",
    usual: "{kind}{은} 보통 쓴맛이 거의 없는 쪽이에요.",
    rest:
      "쓴맛이 없으면 싱겁다고 느끼는 분들도 있는데, 이 정도를 ‘적당하다’고 느끼셨다면 쓴맛의 긴장감 없이도 술의 풍미를 충분히 즐기시는 입맛이에요.",
  },
};

function midTemplate(key: TasteKey): Template {
  const taste = TASTE_NAME[key];
  return {
    title: `${taste}{은} 적당했어요`,
    own: `{name}{은} ${taste}{이} 보통 수준인 {cat}{예요}.`,
    usual: `{kind}{은} 보통 ${taste}{이} 중간 수준이에요.`,
    rest:
      `이 정도를 ‘적당하다’고 느끼셨다면, 이 술의 ${taste}{이} 그대로 기준점이 되는 입맛이에요.`,
  };
}

function render(text: string, vars: Readonly<Record<string, string>>): string {
  return josa(
    text.replace(/\{(name|cat|kind)\}/g, (m, k: string) => vars[k] ?? m),
  );
}

/** 왜 편안했을까요: one paragraph per 적당했어요 taste whose level is known. */
export function writeBalancedSection(
  facts: CardFacts,
  productName: string,
): TasteCardParagraph[] {
  const vars = {
    name: productName,
    cat: categoryWord(facts),
    kind: kindWord(facts),
  };
  return fineTastes(facts).map((f) => {
    const template = f.band === "mid"
      ? midTemplate(f.key)
      : TEMPLATES[`${f.key}.${f.band}`];
    return {
      answer: render(template.title, vars),
      text: `${render(f.estimated ? template.usual : template.own, vars)} ${
        render(template.rest, vars)
      }`,
    };
  });
}
