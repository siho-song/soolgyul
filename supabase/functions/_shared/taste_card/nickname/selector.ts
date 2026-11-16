import type { ReactionFact } from "../facts/facts.ts";
import { NICKNAME_CATALOG, type NicknameCatalogEntry } from "./catalog.ts";

const NICKNAME_SELECTOR_VERSION = "taste-card-nickname-selector-v2";

type TasteNickname = {
  id: string;
  label: string;
  rule_version: typeof NICKNAME_SELECTOR_VERSION;
  matched_condition_count: number;
  additional_reason_count: number;
  support_option_keys: readonly string[];
};
type Candidate = TasteNickname & { priority: number };

/** The liked finish answers a name may carry, by the finish they speak of. */
const FINISH_NAMES: Readonly<Record<string, NicknameCatalogEntry["finish"]>> = {
  clean: "clean",
  persistence: "pleasantLength",
  aroma_echo: "aromaEcho",
};

/**
 * The name for one card, from its reactions: a liked aroma, taste or
 * mouthfeel while drinking is a base, the strength a gauge step named (은은한,
 * 선명한) and a liked finish modify it. Never from labels, prose or anything
 * the reader did not answer.
 */
export function selectTasteNickname(
  reactions: readonly ReactionFact[],
  options: { tanninConfirmed?: boolean } = {},
): TasteNickname {
  const liked = reactions.filter((r) => r.reaction === "liked");
  const positiveBases = liked.filter((r) =>
    r.phase === "drinking" && r.subject.domain !== "finish"
  );
  const positiveFinishes = liked.filter((r) =>
    r.subject.domain === "finish" && r.subject.key in FINISH_NAMES
  );
  const negative = reactions.filter((r) => r.reaction === "burden");
  const hasPositive = liked.length > 0;

  function candidate(entry: NicknameCatalogEntry): Candidate | null {
    if (entry.requires_tannin && !options.tanninConfirmed) return null;
    const base = positiveBases.filter((r) =>
      r.subject.domain === entry.related_sensory?.domain &&
      entry.related_sensory.keys.includes(r.subject.key)
    );
    const named = base.filter((r) => r.qualifier !== null);
    const finishes = positiveFinishes.filter((r) =>
      FINISH_NAMES[r.subject.key] === entry.finish
    );
    let support: ReactionFact[] = [...base];
    let conditionCount = 1;
    switch (entry.eligibility) {
      case "positive_base":
        if (base.length === 0) return null;
        if (entry.modifier_kind === "reason") {
          // The strength belongs to the very answer that is the base.
          support = base.filter((r) => r.qualifier === entry.reason);
          if (support.length === 0) return null;
          conditionCount = 2;
        } else if (entry.modifier_kind === "finish") {
          if (finishes.length === 0) return null;
          support.push(...finishes);
          conditionCount = 2;
        } else if (entry.modifier_kind === "mouthfeel") {
          const feel = positiveBases.filter((r) =>
            r.subject.domain === "mouthfeel" &&
            r.subject.key === entry.mouthfeel
          );
          if (feel.length === 0) return null;
          support.push(...feel);
          conditionCount = 2;
        }
        break;
      case "positive_finish_without_base":
        if (positiveBases.length > 0 || finishes.length === 0) return null;
        support = finishes;
        break;
      case "negative_without_positive":
        if (hasPositive || negative.length === 0) return null;
        support = negative;
        conditionCount = 0;
        break;
      case "no_sensory_reaction":
        if (hasPositive || negative.length > 0) return null;
        support = [];
        conditionCount = 0;
        break;
    }
    return {
      id: entry.id,
      label: !options.tanninConfirmed && entry.label_without_tannin !== null
        ? entry.label_without_tannin
        : entry.label,
      rule_version: NICKNAME_SELECTOR_VERSION,
      matched_condition_count: conditionCount,
      // One bonus per group for a base whose strength the reader named.
      additional_reason_count: named.length > 0 ? 1 : 0,
      support_option_keys: [...new Set(support.flatMap((r) => r.answer_refs))]
        .sort(),
      priority: entry.stable_priority,
    };
  }

  const candidates = NICKNAME_CATALOG.flatMap((entry) => {
    const matched = candidate(entry);
    return matched ? [matched] : [];
  });
  candidates.sort((a, b) =>
    b.matched_condition_count - a.matched_condition_count ||
    b.additional_reason_count - a.additional_reason_count ||
    a.priority - b.priority
  );
  const winner = candidates[0];
  // Only a liked answer no entry is named after (끝맛의 인상 alone).
  if (!winner) throw new Error("nickname_catalog_missing_registered_sensation");
  const { priority: _priority, ...result } = winner;
  return result;
}
