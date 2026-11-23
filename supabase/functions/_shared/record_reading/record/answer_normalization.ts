import { AROMA_STAGES, GAUGE_AXES, type GaugeAxis } from "../facts/facts.ts";
import type { SensoryOption } from "./questionnaire.ts";
import type { SensoryRecord } from "./sensory_record.ts";

/**
 * One record's chosen options as the engine reads them: the gauges in the
 * order of the axes, the aromas by picker and key. An option says everything
 * itself, so nothing is inferred and nothing is grouped. A gauge the drink's
 * kind does not ask ([asked]) is left out: the app never shows it, and a
 * sweetness step means nothing on an axis the sheet has no words for.
 */
export function normalizeSensoryAnswers(
  selected: readonly SensoryOption[],
  asked: ReadonlySet<GaugeAxis>,
): Pick<SensoryRecord, "revisit" | "gauges" | "aromas"> {
  let revisit: SensoryRecord["revisit"] = { intent: null, answerRefs: [] };
  const gauges: SensoryRecord["gauges"][number][] = [];
  const aromas: SensoryRecord["aromas"][number][] = [];
  for (const option of selected) {
    if (option.kind === "revisit") {
      revisit = { intent: option.intent, answerRefs: [option.option_key] };
    } else if (option.kind === "level") {
      if (!asked.has(option.axis)) continue;
      gauges.push({
        axis: option.axis,
        level: option.level,
        reaction: option.reaction,
        answerRef: option.option_key,
      });
    } else if (option.kind === "aroma") {
      aromas.push({
        stage: option.stage,
        key: option.aroma,
        reaction: option.reaction,
        answerRef: option.option_key,
      });
    }
  }
  return {
    revisit,
    gauges: gauges.sort((a, b) =>
      GAUGE_AXES.indexOf(a.axis) - GAUGE_AXES.indexOf(b.axis)
    ),
    aromas: aromas.sort((a, b) =>
      AROMA_STAGES.indexOf(a.stage) - AROMA_STAGES.indexOf(b.stage) ||
      a.key.localeCompare(b.key)
    ),
  };
}
