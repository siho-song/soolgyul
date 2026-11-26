import type { GaugeAxis } from "../../record_reading/facts/facts.ts";
import type { Answers, GaugeSide } from "../../record_reading/answers.ts";
import { groupOfAroma } from "../../record_reading/facts/aroma_groups.ts";
import {
  NAME_NOTHING_NAMED,
  NAME_ONLY_MINDED,
  type NameUnit,
  NICKNAME_CATALOG,
} from "./catalog.ts";

/**
 * What a liked step of a gauge is called. The middle step names no side, so
 * it names nothing, and 끝맛의 인상 lies between two characters a name has
 * no word for. 피트 is the 스모키 aroma at every step that has it.
 */
const GAUGE_UNITS: Readonly<
  Record<GaugeAxis, Partial<Record<GaugeSide, NameUnit>>>
> = {
  sweetness: { low: "dry", high: "sweet" },
  acidity: { low: "citrus_gentle", high: "citrus" },
  umami: { low: "umami_gentle", high: "umami_heavy" },
  body: { low: "light", high: "full_body" },
  tannin: { low: "silky", high: "tannin" },
  sparkling: { low: "sparkling_gentle", high: "sparkling" },
  spice: { low: "spicy_mild", high: "spicy" },
  peat: { low: "smoky", middle: "smoky", high: "smoky" },
  finish_length: { low: "finish_clean", high: "finish_long" },
  finish_character: {},
};

const FINISHES: ReadonlySet<NameUnit> = new Set([
  "finish_clean",
  "finish_long",
]);

/** What the liked answers are, for naming. An answer marked 아쉬웠어요 is never one. */
function likedUnits(said: Answers): Set<NameUnit> {
  const units = new Set<NameUnit>();
  for (const line of said.gauges) {
    const unit = GAUGE_UNITS[line.axis][line.side];
    if (line.reaction === "liked" && unit) units.add(unit);
  }
  for (const line of said.aromas) {
    if (line.reaction !== "liked") continue;
    // An aroma is its group, at whichever moment it was picked.
    const unit = groupOfAroma(line.aroma);
    if (unit) units.add(unit);
  }
  return units;
}

/**
 * The name of one card, from what its answers say and nothing else: the
 * first name of the catalogue every word of which was liked. A name of two
 * answers (a base with a finish or a mouthfeel) so goes before a name of one,
 * and among those an aroma before a taste before a mouthfeel. A finish alone
 * names the card only when nothing liked while drinking has a name. With no
 * name at all: 취향 유랑자 when something was marked 아쉬웠어요, 취향 탐색자
 * when nothing was.
 */
export function selectNickname(said: Answers): string {
  const liked = likedUnits(said);
  const whileDrinking = [...liked].some((unit) => !FINISHES.has(unit));
  const name = NICKNAME_CATALOG.find((entry) =>
    entry.needs.every((unit) => liked.has(unit)) &&
    !(entry.finish_alone && whileDrinking)
  );
  if (name) return name.label;
  const minded = [...said.gauges, ...said.aromas].some((line) =>
    line.reaction === "burden"
  );
  return minded ? NAME_ONLY_MINDED : NAME_NOTHING_NAMED;
}
