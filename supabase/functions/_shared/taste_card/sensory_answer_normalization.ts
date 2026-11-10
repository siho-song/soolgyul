import { serviceVocabulary as vocabulary } from "./dictionary.ts";
import { AROMA_TO_NICKNAME_GROUP_V1 } from "./nickname_catalog_v1.ts";
import type { SensoryKnowledgeRegistry } from "./sensory_knowledge.ts";
import type { SemanticOptionDefinition } from "./sensory_questionnaire_v1.ts";
import type {
  SensoryAnswer,
  SensoryDimension,
  SensoryDomain,
  SensoryObservation,
  SensoryResponseState,
} from "./sensory_record.ts";

/** One selected questionnaire option; its key is the answer's reference. */
type SelectedOption = Pick<
  SemanticOptionDefinition,
  | "option_key"
  | "semantic_key"
  | "value"
  | "reaction"
  | "answer_state"
  | "phase"
>;

const unique = (values: readonly string[]) => [...new Set(values)].sort();
const groups = new Map(
  vocabulary.groups.flatMap((group) =>
    [group.key, ...group.source_keys].map((key) => [key, group] as const)
  ),
);

const answerLabels: Record<
  string,
  [SensoryDomain, string, SensoryDimension | null]
> = {
  "taste.sweetness": ["taste", "단맛", "sweetness"],
  "taste.acidity": ["taste", "산미", "acidity"],
  "taste.bitterness": ["taste", "쓴맛", "bitterness"],
  "body.weight_light": ["mouthfeel", "가벼운 질감", "body"],
  "body.weight_full": ["mouthfeel", "묵직한 질감", "body"],
  "texture.smooth": ["mouthfeel", "매끄러운 질감", null],
  "texture.astringency": ["mouthfeel", "떫은 느낌", "astringency"],
  "carbonation.intensity": ["mouthfeel", "탄산", "carbonation"],
  "alcohol.heat": ["mouthfeel", "알코올의 열감", "alcohol_presence"],
  "finish.persistence": ["finish", "향과 맛의 여운", "finish_length"],
  "finish.cleanliness": ["finish", "깔끔한 마무리", "finish_cleanliness"],
  "finish.length_short": ["finish", "짧은 여운", "finish_length"],
  "finish.weight": ["finish", "남는 무게감", "finish_cleanliness"],
  "finish.aroma_echo": ["finish", "코로 올라오는 잔향", "aroma_intensity"],
  "finish.off_flavor": ["finish", "삼킨 뒤 올라오는 잡내", null],
};

const reasonObservations: Readonly<
  Record<string, SensoryObservation["meaning"]>
> = {
  gentleIntensityAccepted: "gentleIntensity",
  distinctIntensityAccepted: "pronouncedIntensity",
  excessiveIntensity: "excessiveIntensity",
  wantsMoreIntensity: "wantsMoreIntensity",
  harmonious: "harmonious",
  masksOtherSensations: "masksOtherSensations",
  disharmonious: "disharmonious",
};
const finishObservations = new Set<SensoryObservation["meaning"]>([
  "pleasantPersistence",
  "quickClearing",
  "tooBrief",
  "heavyResidue",
  "lingeringAroma",
  "lingeringOffFlavor",
]);

function emptySensoryResponseState(): SensoryResponseState {
  return {
    sectionStates: {
      aroma: { state: "unanswered", answerRefs: [] },
      taste: { state: "unanswered", answerRefs: [] },
      mouthfeel: { state: "unanswered", answerRefs: [] },
      finish: { state: "unanswered", answerRefs: [] },
    },
    revisit: { intent: null, answerRefs: [] },
  };
}

function answerIdentity(key: string, knowledge: SensoryKnowledgeRegistry) {
  if (key.startsWith("aroma.")) {
    const group = groups.get(key.slice(6));
    if (!group) return null;
    const definition = knowledge[`sensory_descriptor:${group.key}`];
    return {
      key: `aroma.${group.key}`,
      label: group.label_ko,
      domain: "aroma" as const,
      family: AROMA_TO_NICKNAME_GROUP_V1[group.key] ?? group.category_key,
      traits: definition?.sensory_trait_keys ?? [],
      description: definition?.sensory_description ?? null,
    };
  }
  const fields = answerLabels[key];
  if (!fields) return null;
  const [domain, label, dimension] = fields;
  const definition = knowledge[
    dimension
      ? `sensory_dimension:${dimension}`
      : "sensory_descriptor:soft_texture"
  ];
  return {
    key,
    domain,
    label,
    family: dimension ?? "soft_texture",
    traits: definition?.sensory_trait_keys ?? [],
    description: definition?.sensory_description ?? null,
  };
}

/** Preserve one record's answers. No product inference or copy. */
export function normalizeSensoryAnswers(
  selected: readonly SelectedOption[],
  knowledge: SensoryKnowledgeRegistry,
): SensoryResponseState & { answers: SensoryAnswer[] } {
  const state = emptySensoryResponseState();
  const grouped = new Map<string, {
    identity: NonNullable<ReturnType<typeof answerIdentity>>;
    options: SelectedOption[];
  }>();
  for (const option of selected) {
    const key = option.semantic_key;
    if (key === "preference.revisit_intent") {
      const intent = option.value;
      if (
        intent === "want_again" || intent === "would_accept_again" ||
        intent === "do_not_want_again" || intent === "unknown"
      ) {
        state.revisit = { intent, answerRefs: [option.option_key] };
      }
      continue;
    }
    const identity = answerIdentity(key, knowledge);
    const domain = identity?.domain ??
      /^questionnaire\.fact\.(aroma|taste|mouthfeel|finish)\./.exec(key)?.[1] as
        | SensoryDomain
        | undefined;
    if (domain) {
      const section = state.sectionStates[domain];
      section.answerRefs = unique([...section.answerRefs, option.option_key]);
      if (option.answer_state === "unknown") section.state = "unknown";
      else if (
        option.answer_state === "answered" && section.state === "unanswered"
      ) {
        section.state = "answered";
      }
    }
    if (!identity || option.answer_state !== "answered") continue;
    const groupKey = `${identity.key}:${option.phase}`;
    const group = grouped.get(groupKey) ?? { identity, options: [] };
    group.options.push(option);
    grouped.set(groupKey, group);
  }

  const answers: SensoryAnswer[] = [];
  for (const group of grouped.values()) {
    const phase = group.options[0].phase;
    // 적당했어요 (value "fine") is an evaluation with no direction; a legacy
    // "neutral" on a notice stays an ungraded observation.
    const isEvaluation = (option: SelectedOption) =>
      option.reaction === "positive" || option.reaction === "burden" ||
      (option.reaction === "neutral" && option.value === "fine");
    const evaluated = group.options.filter(isEvaluation);
    const reactions = evaluated.length
      ? unique(evaluated.map((option) => option.reaction))
      : ["none"];
    for (
      const reaction
        of reactions as ("positive" | "burden" | "neutral" | "none")[]
    ) {
      // Notice and its evaluation are one answer. Opposite evaluations remain separate.
      const sourceOptions = group.options.filter((option) =>
        option.reaction === reaction || !isEvaluation(option)
      );
      const side = reaction === "positive"
        ? "liked"
        : reaction === "burden"
        ? "disliked"
        : null;
      const relatedOptions = side
        ? selected.filter((option) =>
          option.answer_state === "answered" && option.phase === phase &&
          [
            `questionnaire.fact.${group.identity.key}.${side}.reason`,
            `questionnaire.fact.${group.identity.key}.${side}.target`,
          ].includes(option.semantic_key)
        )
        : [];
      const reasonOptions = relatedOptions.filter((option) =>
        option.semantic_key.endsWith(".reason") &&
        typeof option.value === "string"
      );
      const observations = new Map<SensoryObservation["meaning"], string[]>();
      const observe = (meaning: SensoryObservation["meaning"], ref: string) => {
        observations.set(
          meaning,
          unique([...(observations.get(meaning) ?? []), ref]),
        );
      };
      for (const option of sourceOptions) {
        const value = option.value as SensoryObservation["meaning"];
        if (
          group.identity.domain === "finish" && finishObservations.has(value)
        ) {
          observe(value, option.option_key);
        } else {
          observe("noticed", option.option_key);
        }
      }
      for (const option of reasonOptions) {
        const meaning = reasonObservations[String(option.value)];
        if (meaning) observe(meaning, option.option_key);
      }
      answers.push({
        ...group.identity,
        phase,
        observations: [...observations].sort(([a], [b]) => a.localeCompare(b))
          .map(([meaning, answerRefs]) => ({ meaning, answerRefs })),
        reaction,
        reasons: unique(reasonOptions.map((option) => String(option.value))),
        answerRefs: unique(
          [
            ...sourceOptions,
            ...relatedOptions.filter((option) =>
              option.semantic_key.endsWith(".target")
            ),
          ].map((option) => option.option_key),
        ),
        reasonRefs: unique(reasonOptions.map((option) => option.option_key)),
      });
    }
  }
  return {
    ...state,
    answers: answers.sort((a, b) =>
      a.key.localeCompare(b.key) || a.phase.localeCompare(b.phase) ||
      a.reaction.localeCompare(b.reaction)
    ),
  };
}
