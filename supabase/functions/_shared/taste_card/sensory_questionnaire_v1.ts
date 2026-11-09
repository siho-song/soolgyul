import { serviceVocabulary as vocabulary } from "./dictionary.ts";
import tasteBank from "../../../../catalog/sensory/palate-question-bank.json" with {
  type: "json",
};
import optionDefinitions from "../../../../catalog/sensory/answer-option-definitions.json" with {
  type: "json",
};
import type { QuestionnaireAnswerInputV1 } from "./types.ts";
import type { SensoryPhase } from "./sensory_record.ts";
import { sha256Hex } from "./canonical.ts";

/** Immutable wire vocabulary; client labels, catalog cues and feedback are not facts. */
export type CanonicalValue = boolean | number | string | readonly string[];
export type Reaction = "positive" | "burden" | "mixed" | "neutral" | "none";
export type AnswerState =
  | "answered"
  | "unknown"
  | "not_asked"
  | "skipped"
  | "not_applicable";

/** What one questionnaire option means, independent of its wording. */
export type SemanticOptionDefinition = {
  question_key: string;
  option_key: string;
  semantic_key: string;
  value_kind:
    | "boolean"
    | "ordinal"
    | "scalar"
    | "enum"
    | "descriptor"
    | "state";
  value: CanonicalValue;
  reaction: Reaction;
  answer_state: AnswerState;
  phase: SensoryPhase;
  granularity: "broad" | "specific" | "detail" | "not_applicable";
  expression_ceiling: "observation" | "possibility" | "repeated" | "stable";
};

export const SENSORY_QUESTIONNAIRE_VERSION = "sensory-questionnaire-v1";
export const SENSORY_MEANING_VERSION = "sensory-answer-meaning-v1";
// Existing options stay immutable; approved new aromas have separate hashes.
// 2026-10-24: 감칠맛·짠맛 left the taste question (no bottle data, confusing to
// readers), so the original set is hashed without their 22 options.
// 2026-10-25: the two observation-only finishes (떫음, 무게) became liked/burden
// pairs like the other finishes, so the set is hashed with 15 finish options,
// and tastes and mouthfeel gained a "적당했어요" reaction (nine neutral options).
// 2026-10-29: the catch-all aroma buttons lost their "기타" (곡물, 디저트, 차,
// 채소, 유제품, 스모키); the keys and the set are unchanged.
// 2026-10-29: tastes are always answered, so taste:unsure and
// taste:nothing_stood_out left the set.
// 2026-11-01: aroma buttons read as one plain noun (꽃, 베리, 과일, 디저트, 묵은
// 양주, 달콤함, 누룩·코지 …): the keys and the set are unchanged, the labels are.
// 2026-11-05: the "character" reason (맛 자체가 좋았어요 · 취향이 아니었어요) left
// every aroma and taste: the card never used it beyond what the bare reaction
// says, and choosing it hid the other reasons. Stored answers drop it by
// migration, so the sets are hashed without those reason options.
// 2026-11-06: the finish asks only what the drinking pages cannot (length,
// a cleared mouth, what came up the nose): the eleven lingering taste and
// mouthfeel finishes left, 잔향 and 잡내 joined. Stored answers drop the eleven
// by migration, so the set is hashed with six finish options.
export const SENSORY_REGISTRY_SHA256 =
  "e2e556fd88e2906b37318107ae46d468605738906370d3a0484feee381841481";
export const LEATHER_REGISTRY_SHA256 =
  "4583756d75581f955a67570d79f2b079f4507a033d748bd700e55bc629ad1a4f";
export const MUSK_REGISTRY_SHA256 =
  "7fbf82b437e103a6197e82f869df92312b09728119a0d8dcbb6b5a8c13837d7a";
// 2026-10-20: thirteen aroma names offered on their own now that grouping
// follows the catalog tree (살구, 딸기, 홉, 아가베 …). Their options have one hash.
// 2026-11-01: seven more names leave their group (셰리, 토피, 바닷바람, 참외,
// 청포도, 건초, 매실): words readers actually use, whose group name changed the meaning.
export const TREE_AROMA_SUBJECTS: ReadonlySet<string> = new Set([
  "strawberry",
  "blueberry",
  "green_apple",
  "apricot",
  "quince",
  "raisin",
  "cranberry",
  "lychee",
  "toast",
  "yeast",
  "hop",
  "olive",
  "agave",
  "sherry",
  "toffee",
  "saline",
  "korean_melon",
  "green_grape",
  "hay",
  "ume",
]);
export const TREE_AROMA_REGISTRY_SHA256 =
  "772c18ff0ce8188597809133970e1069bfca36f323b91c7016ce7a95d5d3a060";
export const SENSORY_QUESTIONS = {
  sensory_revisit: "이 술, 다음에 또 마시고 싶나요?",
  sensory_aroma: "마시면서 어떤 향이 느껴졌나요?",
  sensory_taste: "맛은 어땠나요?",
  sensory_mouthfeel: "마실 때 입안에서 어떤 느낌이 들었나요?",
  sensory_finish: "술을 삼킨 뒤, 마무리는 어땠나요?",
} as const;
type Section = "aroma" | "taste" | "mouthfeel" | "finish" | "revisit";
type Side = "liked" | "disliked";
type Kind =
  | "notice"
  | "reaction"
  | "target"
  | "reason"
  | "finish"
  | "revisit"
  | "unknown";
export type SensoryOptionV1 = SemanticOptionDefinition & {
  label: string;
  kind: Kind;
  section: Section;
  subject: string | null;
  side: Side | null;
  reason: string | null;
  meaning: string;
};
const sides: readonly Side[] = ["liked", "disliked"];
type ReasonDefinition = {
  key: string;
  label_ko: string;
  meaning: string;
  taste_meanings?: Readonly<Record<string, string>>;
};

// JSON is the shared source. The immutable registry check below also protects
// the exact published wording, meaning, and IDs from accidental changes.
const reasonDefinitions: Readonly<Record<Side, readonly ReasonDefinition[]>> =
  optionDefinitions.reasons;
if (optionDefinitions.version !== 1) {
  throw new Error("sensory_option_definitions_invalid");
}
// Ordering flags used to rank the UI are deliberately absent here.
// Published labels stay fixed here even when the current UI wording changes.
const finishes: readonly [string, string, string, string, Side | null][] = [
  [
    "pleasantLength",
    "향이나 맛이 기분 좋게 이어졌어요",
    "persistence",
    "pleasantPersistence",
    "liked",
  ],
  [
    "clean",
    "입안이 금방 깔끔해져서 좋았어요",
    "cleanliness",
    "quickClearing",
    "liked",
  ],
  [
    "tooShort",
    "향이나 맛이 너무 빨리 사라졌어요",
    "length_short",
    "tooBrief",
    "disliked",
  ],
  [
    "heavy",
    "텁텁하고 무거운 느낌이 남아서 부담스러웠어요",
    "weight",
    "heavyResidue",
    "disliked",
  ],
  // 2026-11-06: what came up the nose after swallowing, which no drinking
  // page asks.
  [
    "aromaEcho",
    "삼킨 뒤 코끝으로 향이 올라와서 좋았어요",
    "aroma_echo",
    "lingeringAroma",
    "liked",
  ],
  [
    "offFlavor",
    "삼킨 뒤 잡미나 거슬리는 냄새가 올라왔어요",
    "off_flavor",
    "lingeringOffFlavor",
    "disliked",
  ],
];

function buildRegistry(): ReadonlyMap<string, SensoryOptionV1> {
  const entries = new Map<string, SensoryOptionV1>();
  function add(input: {
    id: string;
    label: string;
    section: Section;
    kind: Kind;
    meaning: string;
    subject?: string;
    side?: Side | null;
    reason?: string;
    axis?: string;
    value?: string;
    phase?: SensoryPhase;
    unknown?: boolean;
    /** 적당했어요: an evaluation with no direction (2026-10-25). */
    neutral?: boolean;
  }) {
    if (entries.has(input.id) || !input.label.trim()) {
      throw new Error("sensory_registry_invalid");
    }
    const directional = ["reaction", "finish", "revisit"].includes(input.kind);
    const reaction: Reaction = input.neutral
      ? "neutral"
      : !directional || !input.side
      ? "none"
      : input.side === "liked"
      ? "positive"
      : "burden";
    const fact = input.kind === "reason" || input.kind === "target";
    entries.set(
      input.id,
      Object.freeze({
        question_key: `sensory_${input.section}`,
        option_key: input.id,
        label: input.label,
        kind: input.kind,
        section: input.section,
        subject: input.subject ?? null,
        side: input.side ?? null,
        reason: input.reason ?? null,
        meaning: input.meaning,
        semantic_key: input.axis ??
          `questionnaire.fact.${input.section}.${input.subject ?? "state"}.${
            input.side ?? "none"
          }.${input.kind}`,
        value_kind: input.kind === "notice" ? "descriptor" : "enum",
        value: input.value ?? input.meaning,
        reaction,
        answer_state: input.unknown ? "unknown" : "answered",
        phase: input.phase ??
          (input.section === "finish"
            ? "finish"
            : input.section === "revisit"
            ? "overall"
            : "mid"),
        granularity: fact ? "detail" : "specific",
        expression_ceiling: "observation",
      }),
    );
  }
  function sensation(
    section: "aroma" | "taste" | "mouthfeel",
    key: string,
    label: string,
    axis: string,
  ) {
    if (section !== "taste") {
      add({
        id: `notice:${section}:${key}`,
        label,
        section,
        kind: "notice",
        subject: key,
        meaning: "noticed",
        axis,
        value: key,
      });
    }
    for (const side of sides) {
      add({
        id: `reaction:${section}:${key}:${side}`,
        label,
        section,
        kind: "reaction",
        subject: key,
        side,
        meaning: "evaluated",
        axis,
        value: side,
      });
      if (section !== "mouthfeel") {
        add({
          id: `target:${section}:${key}:${side}`,
          label,
          section,
          kind: "target",
          subject: key,
          side,
          meaning: "reasonTargetSelected",
        });
      }
    }
    // 2026-10-25: tastes and mouthfeel can also be "적당했어요" — evaluated, but
    // neither liked nor a burden. No reason is asked; the card keeps that level.
    if (section !== "aroma") {
      add({
        id: `reaction:${section}:${key}:fine`,
        label,
        section,
        kind: "reaction",
        subject: key,
        meaning: "balanced",
        axis,
        value: "fine",
        neutral: true,
      });
    }
  }
  function reason(
    section: "aroma" | "taste",
    key: string,
    side: Side,
    code: string,
    label: string,
  ) {
    const definition = reasonDefinitions[side].find((item) =>
      item.key === code
    );
    const meaning = section === "taste"
      ? definition?.taste_meanings?.[key] ?? definition?.meaning
      : definition?.meaning;
    if (!meaning) throw new Error("sensory_reason_invalid");
    add({
      id: `reason:${section}:${key}:${side}:${code}`,
      label,
      section,
      kind: "reason",
      subject: key,
      side,
      reason: code,
      meaning,
    });
  }
  for (const group of vocabulary.groups) {
    if (group.domain !== "descriptor" || !group.phases.includes("aroma")) {
      continue;
    }
    sensation("aroma", group.key, group.label_ko, `aroma.${group.key}`);
    for (const side of sides) {
      for (const definition of reasonDefinitions[side]) {
        reason("aroma", group.key, side, definition.key, definition.label_ko);
      }
    }
  }
  const tasteKeys = ["sweetness", "acidity", "bitterness"];
  if (tasteBank.entries.length !== tasteKeys.length) {
    throw new Error("sensory_taste_bank_invalid");
  }
  for (const entry of tasteBank.entries) {
    if (!tasteKeys.includes(entry.key) || entry.kind !== "basic_taste") {
      throw new Error("sensory_taste_bank_invalid");
    }
    // UI copy may change without changing the published answer identity.
    const label = entry.published_label_ko ?? entry.label_ko;
    sensation("taste", entry.key, label, `taste.${entry.key}`);
    for (const side of sides) {
      const reasons: readonly {
        key: string;
        label_ko: string;
        published_label_ko?: string;
      }[] = side === "liked" ? entry.positive_reasons : entry.negative_reasons;
      if (reasons.length !== 4) throw new Error("sensory_taste_bank_invalid");
      for (const item of reasons) {
        const label = item.published_label_ko ?? item.label_ko;
        reason("taste", entry.key, side, item.key, label);
      }
    }
  }
  for (const option of optionDefinitions.mouthfeel) {
    sensation("mouthfeel", option.key, option.label_ko, option.axis);
  }
  for (const [key, label, axis, meaning, side] of finishes) {
    add({
      id: `finish:${key}`,
      label,
      section: "finish",
      kind: "finish",
      subject: axis,
      side,
      meaning,
      axis: `finish.${axis}`,
    });
  }
  const revisit = [
    [
      "wantAgain",
      "네, 다시 마시고 싶어요",
      "revisitDesired",
      "want_again",
      "liked",
    ],
    [
      "wouldAcceptAgain",
      "기회가 된다면 다시 마셔도 괜찮아요",
      "revisitAcceptable",
      "would_accept_again",
      null,
    ],
    [
      "doNotWantAgain",
      "아니요, 다시 마시고 싶지는 않아요",
      "revisitDeclined",
      "do_not_want_again",
      "disliked",
    ],
    ["unsure", "아직은 잘 모르겠어요", "unknown", "unknown", null],
  ] as const;
  for (const [key, label, meaning, value, side] of revisit) {
    add({
      id: `revisit:${key}`,
      label,
      section: "revisit",
      kind: "revisit",
      meaning,
      side,
      value,
      axis: "preference.revisit_intent",
      unknown: key === "unsure",
    });
  }
  // Tastes are always answered (좋았어요 · 적당했어요 · 아쉬웠어요 each); the
  // other sections may be left as 잘 모르겠어요.
  for (const section of ["aroma", "mouthfeel", "finish"] as const) {
    add({
      id: `${section}:unsure`,
      label: "잘 모르겠어요",
      section,
      kind: "unknown",
      meaning: "unknown",
      unknown: true,
    });
  }
  return entries;
}
const registry = buildRegistry();
export function sensoryOptionsV1(): readonly SensoryOptionV1[] {
  return [...registry.values()];
}
let registryVerification: Promise<void> | undefined;
export function verifySensoryRegistryV1(): Promise<void> {
  return registryVerification ??= (async () => {
    const sorted = [...registry.values()].sort((a, b) =>
      a.option_key.localeCompare(b.option_key)
    );
    const original = sorted.filter((option) =>
      option.subject !== "leather" && option.subject !== "musk" &&
      !TREE_AROMA_SUBJECTS.has(option.subject ?? "")
    );
    const leather = sorted.filter((option) => option.subject === "leather");
    const musk = sorted.filter((option) => option.subject === "musk");
    const tree = sorted.filter((option) =>
      TREE_AROMA_SUBJECTS.has(option.subject ?? "")
    );
    if (
      await sha256Hex(JSON.stringify(original)) !== SENSORY_REGISTRY_SHA256 ||
      await sha256Hex(JSON.stringify(leather)) !== LEATHER_REGISTRY_SHA256 ||
      await sha256Hex(JSON.stringify(musk)) !== MUSK_REGISTRY_SHA256 ||
      await sha256Hex(JSON.stringify(tree)) !== TREE_AROMA_REGISTRY_SHA256
    ) {
      throw new SensoryQuestionnaireError("immutable_registry_changed");
    }
  })();
}

export class SensoryQuestionnaireError extends Error {
  constructor(readonly code: string) {
    super(`sensory_questionnaire_invalid:${code}`);
  }
}
function reject(code: string): never {
  throw new SensoryQuestionnaireError(code);
}

/** Validate explicit answer state, not product-based visibility/ranking. */
export function validateSensoryAnswersV1(
  answers: readonly QuestionnaireAnswerInputV1[],
): void {
  const questions = new Set<string>();
  const selected: SensoryOptionV1[] = [];
  for (const answer of answers) {
    if (
      !Object.hasOwn(SENSORY_QUESTIONS, answer.question_key) ||
      questions.has(answer.question_key)
    ) reject("question_unknown_or_duplicate");
    questions.add(answer.question_key);
    if (answer.selected_option_keys.length > 20) reject("option_count");
    if (answer.free_text !== null) reject("structured_answer_free_text");
    const unique = new Set<string>();
    for (const id of answer.selected_option_keys) {
      const option = registry.get(id);
      if (!option || option.question_key !== answer.question_key) {
        reject("option_unknown_or_wrong_question");
      }
      if (unique.has(id)) reject("option_duplicate");
      unique.add(id);
      selected.push(option);
    }
  }
  const revisit = selected.filter((entry) => entry.section === "revisit");
  if (revisit.length !== 1) reject("revisit_required");
  for (const section of ["aroma", "taste", "mouthfeel", "finish"] as const) {
    const entries = selected.filter((entry) => entry.section === section);
    if (
      entries.some((entry) => entry.kind === "unknown") && entries.length !== 1
    ) reject("exclusive_state");
    const notices = entries.filter((entry) => entry.kind === "notice");
    if (section === "aroma" && notices.length > 5) reject("aroma_limit");
    const reactions = entries.filter((entry) => entry.kind === "reaction");
    const reacted = new Set<string>();
    for (const entry of reactions) {
      if (reacted.has(entry.subject!)) reject("reaction_conflict");
      reacted.add(entry.subject!);
      if (
        section !== "taste" &&
        !notices.some((notice) => notice.subject === entry.subject)
      ) reject("reaction_without_notice");
    }
    const targets = entries.filter((entry) => entry.kind === "target");
    const reasons = entries.filter((entry) => entry.kind === "reason");
    if (section === "aroma" || section === "taste") {
      // No section asks a target any more, and no reason is required
      // (aromas 2026-11-04, tastes 2026-11-05): a taste takes its reasons on
      // the reaction page. The published options stay valid for answers
      // already stored: each needs the reaction it explains, a side keeps one
      // target at most, and 이유는 잘 모르겠어요 stands alone.
      for (const entry of [...targets, ...reasons]) {
        if (
          !reactions.some((reaction) =>
            reaction.subject === entry.subject && reaction.side === entry.side
          )
        ) reject("reason_without_parent");
      }
      for (const side of sides) {
        if (targets.filter((entry) => entry.side === side).length > 1) {
          reject("target_multiple");
        }
      }
      for (const reaction of reactions) {
        const own = reasons.filter((entry) =>
          entry.subject === reaction.subject && entry.side === reaction.side
        );
        if (
          own.some((entry) => entry.reason === "unspecified") &&
          own.length !== 1
        ) reject("reason_exclusive");
      }
    }
    if (section === "taste" && reactions.length === 0) reject("taste_required");
  }
}

export function sensoryDefinitionV1(
  id: string,
): SemanticOptionDefinition | undefined {
  const entry = registry.get(id);
  if (!entry) return undefined;
  const {
    question_key,
    option_key,
    semantic_key,
    value_kind,
    value,
    reaction,
    answer_state,
    phase,
    granularity,
    expression_ceiling,
  } = entry;
  return {
    question_key,
    option_key,
    semantic_key,
    value_kind,
    value,
    reaction,
    answer_state,
    phase,
    granularity,
    expression_ceiling,
  };
}
