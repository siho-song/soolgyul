import {
  NICKNAME_CATALOG_V1,
  type NicknameCatalogEntryV1,
} from "./nickname_catalog_v1.ts";
import {
  sensoryOptionsV1,
  type SensoryOptionV1,
} from "./sensory_questionnaire_v1.ts";

const NICKNAME_SELECTOR_VERSION_V1 = "taste-card-nickname-selector-v1";
const optionsByKey = new Map(sensoryOptionsV1().map((o) => [o.option_key, o]));

type TasteNicknameV1 = {
  id: string;
  label: string;
  rule_version: typeof NICKNAME_SELECTOR_VERSION_V1;
  matched_condition_count: number;
  additional_reason_count: number;
  support_option_keys: readonly string[];
};
type Candidate = TasteNicknameV1 & { priority: number };

/** Inputs are registered option IDs, never labels, prose or inferred likes. */
export function selectTasteNicknameV1(
  selectedOptionKeys: readonly string[],
  options: { tanninConfirmed?: boolean } = {},
): TasteNicknameV1 {
  const selected = [...new Set(selectedOptionKeys)].sort().flatMap((key) => {
    const definition = optionsByKey.get(key);
    return definition ? [definition] : [];
  });
  const reactions = selected.filter((o) => o.kind === "reaction");
  const positiveBases = reactions.filter((o) => o.side === "liked");
  const positiveFinishes = selected.filter((o) =>
    o.kind === "finish" && o.side === "liked"
  );
  const negative = selected.filter((o) =>
    (o.kind === "reaction" || o.kind === "finish") && o.side === "disliked"
  );
  const hasPositive = positiveBases.length > 0 || positiveFinishes.length > 0;

  function candidate(entry: NicknameCatalogEntryV1): Candidate | null {
    if (entry.requires_tannin && !options.tanninConfirmed) return null;
    const base = positiveBases.filter((o) =>
      o.section === entry.related_sensory?.domain &&
      entry.related_sensory.keys.includes(o.subject ?? "")
    );
    const reasons = selected.filter((o) =>
      o.kind === "reason" && o.side === "liked" && o.reason !== "unspecified" &&
      base.some((b) => b.section === o.section && b.subject === o.subject)
    );
    let support: SensoryOptionV1[] = [...base];
    let conditionCount = 1;
    switch (entry.eligibility) {
      case "positive_base":
        if (base.length === 0) return null;
        if (entry.modifier_kind === "reason") {
          const matchingReasons = reasons.filter((o) =>
            o.reason === entry.reason
          );
          if (matchingReasons.length === 0) return null;
          // Preserve the exact fruit/taste that supports the modifier.
          support = base.filter((b) =>
            matchingReasons.some((r) =>
              r.section === b.section && r.subject === b.subject
            )
          );
          support.push(...matchingReasons);
          conditionCount = 2;
        } else if (entry.modifier_kind === "finish") {
          const finish = positiveFinishes.filter((o) =>
            o.option_key === `finish:${entry.finish}`
          );
          if (finish.length === 0) return null;
          support.push(...finish);
          conditionCount = 2;
        } else if (entry.modifier_kind === "mouthfeel") {
          const feel = positiveBases.filter((o) =>
            o.section === "mouthfeel" && o.subject === entry.mouthfeel
          );
          if (feel.length === 0) return null;
          support.push(...feel);
          conditionCount = 2;
        }
        if (entry.modifier_kind !== "reason") support.push(...reasons);
        break;
      case "positive_finish_without_base":
        if (positiveBases.length > 0) return null;
        support = positiveFinishes.filter((o) =>
          o.option_key === `finish:${entry.finish}`
        );
        if (support.length === 0) return null;
        break;
      case "negative_without_positive":
        if (hasPositive || negative.length === 0) return null;
        support = negative;
        conditionCount = 0;
        break;
      case "no_sensory_reaction":
        if (hasPositive || negative.length > 0) return null;
        support = selected.filter((o) => o.section !== "revisit");
        conditionCount = 0;
        break;
    }
    return {
      id: entry.id,
      label: !options.tanninConfirmed && entry.label_without_tannin !== null
        ? entry.label_without_tannin
        : entry.label,
      rule_version: NICKNAME_SELECTOR_VERSION_V1,
      matched_condition_count: conditionCount,
      // One explanation bonus per group, not one per fruit or checkbox.
      additional_reason_count: reasons.length > 0 ? 1 : 0,
      support_option_keys: [...new Set(support.map((o) => o.option_key))]
        .sort(),
      priority: entry.stable_priority,
    };
  }

  const candidates = NICKNAME_CATALOG_V1.flatMap((entry) => {
    const matched = candidate(entry);
    return matched ? [matched] : [];
  });
  candidates.sort((a, b) =>
    b.matched_condition_count - a.matched_condition_count ||
    b.additional_reason_count - a.additional_reason_count ||
    a.priority - b.priority
  );
  const winner = candidates[0];
  if (!winner) throw new Error("nickname_catalog_missing_registered_sensation");
  const { priority: _priority, ...result } = winner;
  return result;
}
