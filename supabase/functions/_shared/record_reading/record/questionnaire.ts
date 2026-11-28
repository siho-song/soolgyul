/**
 * The questionnaire a record is answered under: its version, the registry of
 * every option a request may choose, the check of one record's answers, and
 * the gauge sheet (which gauges a drink is asked, and their words).
 *
 * 2026-11-16: the questionnaire was rebuilt around five-step gauges and three
 * aroma pickers (nose, palate, finish). An option carries its own reaction,
 * so one answer is one option: `level:<axis>:<1-5>:<liked|disliked>`,
 * `aroma:<stage>:<key>:<liked|disliked>`. The questionnaire before it
 * (sensory-questionnaire-v1) is no longer read here: a record answered under
 * it keeps its stored card and cannot be re-answered.
 */
import {
  isAroma,
  senseChoiceOfTag,
  senseChoices,
} from "../dictionary/aromas.ts";
import {
  AROMA_STAGES,
  type AromaStage,
  GAUGE_AXES,
  type GaugeAxis,
} from "../facts/facts.ts";
import {
  GAUGE_FALLBACK,
  GAUGE_KINDS,
  type GaugeDefinition,
  PUBLISHED_GAUGE_SHEET,
} from "../dictionary/gauges.ts";
import { canonicalJson, sha256Hex } from "../../canonical.ts";
import type { SensoryScore } from "./sensory_record.ts";

/** One answered question as a request carries it. */
export type QuestionnaireAnswerInput = {
  question_key: string;
  selected_option_keys: string[];
  free_text: string | null;
};

export const SENSORY_QUESTIONNAIRE_VERSION = "sensory-questionnaire-v2";

/**
 * The registry and the gauge sheet as published: the option keys and their
 * meaning, and every word of catalog/sensory/gauge-definitions.json a reader
 * is shown. A change to either is a new questionnaire version, never an edit
 * of this one.
 */
const SENSORY_REGISTRY_SHA256 =
  "f6418cef635f5617ec199e931293bd41e74a217f9d4c614edcb290b7fe94cecd";

/** The gauges of each step, in the order of the axes: every axis some kind asks there. */
const levelAxes = (step: "palate" | "finish"): readonly GaugeAxis[] =>
  GAUGE_AXES.filter((axis) =>
    Object.values(GAUGE_KINDS).some((kind) =>
      kind[step].some((row) => row.axis === axis)
    )
  );
const LEVEL_QUESTIONS: Readonly<Record<string, readonly GaugeAxis[]>> = {
  sensory_palate_level: levelAxes("palate"),
  sensory_finish_level: levelAxes("finish"),
};

const AROMA_QUESTIONS: Readonly<Record<AromaStage, string>> = {
  nose: "sensory_nose_aroma",
  palate: "sensory_palate_aroma",
  finish: "sensory_finish_aroma",
};

const REVISIT_INTENTS = {
  wantAgain: "want_again",
  wouldAcceptAgain: "would_accept_again",
  doNotWantAgain: "do_not_want_again",
  unsure: "unknown",
} as const;

/** What one option says, read from its key alone. */
export type SensoryOption =
  & { question_key: string; option_key: string }
  & (
    | {
      kind: "revisit";
      intent: typeof REVISIT_INTENTS[keyof typeof REVISIT_INTENTS];
    }
    /** Step 1 skipped: no aroma was named by the nose. */
    | { kind: "unsure" }
    | {
      kind: "level";
      axis: GaugeAxis;
      level: SensoryScore;
      reaction: "liked" | "burden";
    }
    | {
      kind: "aroma";
      stage: AromaStage;
      aroma: string;
      reaction: "liked" | "burden";
    }
  );

/** An option's side as its key spells it, and as the engine reads it. */
const SIDES = [["liked", "liked"], ["disliked", "burden"]] as const;

function buildRegistry(): ReadonlyMap<string, SensoryOption> {
  const entries = new Map<string, SensoryOption>();
  const add = (option: SensoryOption) => {
    if (entries.has(option.option_key)) {
      throw new Error("sensory_registry_invalid");
    }
    entries.set(option.option_key, Object.freeze(option));
  };
  for (const [key, intent] of Object.entries(REVISIT_INTENTS)) {
    add({
      question_key: "sensory_revisit",
      option_key: `revisit:${key}`,
      kind: "revisit",
      intent,
    });
  }
  add({
    question_key: AROMA_QUESTIONS.nose,
    option_key: "nose:unsure",
    kind: "unsure",
  });
  for (const [question_key, axes] of Object.entries(LEVEL_QUESTIONS)) {
    for (const axis of axes) {
      for (const level of [1, 2, 3, 4, 5] as const) {
        for (const [side, reaction] of SIDES) {
          add({
            question_key,
            option_key: `level:${axis}:${level}:${side}`,
            kind: "level",
            axis,
            level,
            reaction,
          });
        }
      }
    }
  }
  for (const choice of senseChoices()) {
    if (choice.of !== "descriptor" || !choice.said_of.includes("aroma")) {
      continue;
    }
    for (const stage of AROMA_STAGES) {
      for (const [side, reaction] of SIDES) {
        add({
          question_key: AROMA_QUESTIONS[stage],
          option_key: `aroma:${stage}:${choice.key}:${side}`,
          kind: "aroma",
          stage,
          aroma: choice.key,
          reaction,
        });
      }
    }
  }
  return entries;
}

const registry = buildRegistry();
const questionKeys: ReadonlySet<string> = new Set(
  [...registry.values()].map((option) => option.question_key),
);

export function sensoryOptions(): readonly SensoryOption[] {
  return [...registry.values()];
}

/**
 * An option by its key. An aroma answered under a word that has since folded
 * into another (붉은 체리 into 체리) reads as the option of the word it is
 * shown as, so a record keeps what it said.
 */
export function sensoryOption(key: string): SensoryOption | undefined {
  const option = registry.get(key);
  if (option) return option;
  const [kind, stage, aroma, side, ...rest] = key.split(":");
  const shown = kind === "aroma" && rest.length === 0
    ? senseChoiceOfTag(aroma ?? "")
    : null;
  return shown ? registry.get(`aroma:${stage}:${shown}:${side}`) : undefined;
}

let registryVerification: Promise<void> | undefined;
export function verifySensoryRegistry(): Promise<void> {
  return registryVerification ??= (async () => {
    const options = [...registry.values()].sort((a, b) =>
      a.option_key < b.option_key ? -1 : 1
    );
    const published = canonicalJson({ options, gauges: PUBLISHED_GAUGE_SHEET });
    if (await sha256Hex(published) !== SENSORY_REGISTRY_SHA256) {
      throw new SensoryQuestionnaireError("immutable_registry_changed");
    }
  })();
}

/**
 * Whether [key] is an aroma option of [questionKey] whose word the
 * dictionary still holds but shows as no offered word (향신료, 초콜릿): a
 * record answered when it was offered keeps the key, and it says nothing.
 */
function unshownAroma(key: string, questionKey: string): boolean {
  const [kind, stage, aroma, side, ...rest] = key.split(":");
  return kind === "aroma" && rest.length === 0 &&
    AROMA_QUESTIONS[stage as AromaStage] === questionKey &&
    SIDES.some(([spelled]) => spelled === side) && isAroma(aroma ?? "");
}

export class SensoryQuestionnaireError extends Error {
  constructor(readonly code: string) {
    super(`sensory_questionnaire_invalid:${code}`);
  }
}
function reject(code: string): never {
  throw new SensoryQuestionnaireError(code);
}

/**
 * Checks what one record chose against the registry. 다시 마시고 싶은지 is
 * always answered, and any other question may be left out or empty, but not
 * all of them: a record says at least one thing that was sensed, an aroma or
 * a step on a gauge. Which gauges a drink is asked is not checked here: a
 * gauge its kind does not ask is left out when the record is built.
 */
export function validateSensoryAnswers(
  answers: readonly QuestionnaireAnswerInput[],
): void {
  const questions = new Set<string>();
  let revisits = 0;
  let sensations = 0;
  for (const answer of answers) {
    if (
      !questionKeys.has(answer.question_key) ||
      questions.has(answer.question_key)
    ) reject("question_unknown_or_duplicate");
    questions.add(answer.question_key);
    if (answer.free_text !== null) reject("structured_answer_free_text");
    const chosen = new Set<string>();
    // One answer per gauge and per aroma: liked and disliked cannot both hold.
    // An aroma also stored under a word since folded into it says the same
    // option again, which is no conflict.
    const answered = new Map<string, string>();
    for (const id of answer.selected_option_keys) {
      const option = sensoryOption(id);
      if (!option && unshownAroma(id, answer.question_key)) continue;
      if (!option || option.question_key !== answer.question_key) {
        reject("option_unknown_or_wrong_question");
      }
      if (chosen.has(id)) reject("option_duplicate");
      chosen.add(id);
      if (option.kind === "revisit") revisits++;
      if (option.kind === "unsure" && answer.selected_option_keys.length > 1) {
        reject("exclusive_state");
      }
      if (option.kind === "level" || option.kind === "aroma") {
        const subject = option.kind === "level" ? option.axis : option.aroma;
        if (
          (answered.get(subject) ?? option.option_key) !== option.option_key
        ) {
          reject(`${option.kind}_conflict`);
        }
        answered.set(subject, option.option_key);
        sensations++;
      }
    }
  }
  if (revisits !== 1) reject("revisit_required");
  if (sensations === 0) reject("sensation_required");
}

/* ------------------------------------------------------- the gauge sheet */

/** One gauge as a drink's sheet shows it: its name and the word of each step. */
export type GaugeRow = {
  axis: GaugeAxis;
  /** 당도, 질감 · 무게감, 여운의 길이. */
  label: string;
  /** The five steps, 1 to 5: 본 드라이 … 스위트. */
  terms: readonly string[];
  /** What each step is like, as the sheet says under its word (단맛 없는 깔끔함); null where it says nothing. */
  hints: readonly (string | null)[];
  /** 끝맛의 인상 only: what its two ends lean to (드라이·미네랄, 과실·오크 풍미). */
  ends?: readonly [string, string];
};

/**
 * The gauges a drink is asked, in the sheet's order: 맛·질감 first, then 여운.
 * A gauge with a condition shows for the styles it names (타닌 for a red
 * wine), and where it says so for a drink whose style is unknown; or for
 * every style but the ones it excepts (a distilled soju is asked as a spirit,
 * on gauges of its own). A drink of no known kind is asked the fallback
 * kind's plain gauges.
 */
export function gaugeSheet(
  category: string | null,
  styleKey: string | null,
): { palate: readonly GaugeRow[]; finish: readonly GaugeRow[] } {
  const known = category ? GAUGE_KINDS[category] : undefined;
  const kind = known ?? GAUGE_KINDS[GAUGE_FALLBACK.kind];
  const shown = (row: GaugeDefinition) => {
    if (!known) return GAUGE_FALLBACK.palate_axes.includes(row.axis);
    if (!row.show) return true;
    if (row.show.styles) {
      return styleKey === null
        ? row.show.unknown_style === true
        : row.show.styles.includes(styleKey);
    }
    return styleKey === null ||
      !(row.show.except_styles ?? []).includes(styleKey);
  };
  const rowOf = (row: GaugeDefinition): GaugeRow => ({
    axis: row.axis as GaugeAxis,
    label: row.label_ko,
    terms: row.levels.map((level) => level.term),
    hints: row.levels.map((level) => level.hint ?? null),
    ...(row.ends_ko?.length === 2
      ? { ends: [row.ends_ko[0], row.ends_ko[1]] as const }
      : {}),
  });
  return {
    palate: kind.palate.filter(shown).map(rowOf),
    finish: kind.finish.map(rowOf),
  };
}
