import type { GaugeAxis } from "../facts/facts.ts";
import type { GaugeSide, Interpretation } from "../prepare/interpretation.ts";
import {
  AROMA_TO_NICKNAME_GROUP,
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
  "finish_aroma",
]);

/** What the liked answers are, for naming. An answer marked 아쉬웠어요 is never one. */
function likedUnits(said: Interpretation): Set<NameUnit> {
  const units = new Set<NameUnit>();
  for (const line of said.gauges) {
    const unit = GAUGE_UNITS[line.axis][line.side];
    if (line.reaction === "liked" && unit) units.add(unit);
  }
  for (const line of said.aromas) {
    if (line.reaction !== "liked") continue;
    // An aroma that stayed after swallowing is the 잔향, whichever it was.
    const unit = line.stage === "finish"
      ? "finish_aroma"
      : AROMA_TO_NICKNAME_GROUP[line.aroma];
    if (unit) units.add(unit);
  }
  return units;
}

/**
 * The name of one card, from what its answers say and nothing else. Among
 * the names every word of which was liked, one of two words goes before a
 * base alone, and the catalogue's order decides the rest. A finish alone
 * names the card only when nothing liked while drinking has a name. With no
 * name at all: 취향 유랑자 when something was marked 아쉬웠어요, 취향 탐색자
 * when nothing was.
 */
export function selectNickname(said: Interpretation): string {
  const liked = likedUnits(said);
  const whileDrinking = [...liked].some((unit) => !FINISHES.has(unit));
  const fits = NICKNAME_CATALOG.filter((entry) =>
    entry.needs.every((unit) => liked.has(unit)) &&
    !(entry.finish_alone && whileDrinking)
  );
  const name = fits.find((entry) => entry.words === 2) ?? fits[0];
  if (name) return name.label;
  const minded = [...said.gauges, ...said.aromas].some((line) =>
    line.reaction === "burden"
  );
  return minded ? NAME_ONLY_MINDED : NAME_NOTHING_NAMED;
}
