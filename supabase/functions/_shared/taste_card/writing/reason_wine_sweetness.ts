/**
 * A still wine's sweetness as a reason, told from the bottle's own traits
 * (facts/wine_sweetness.ts): the tannin and acidity that stand high among
 * its kind and pull it dry, the ripe and sweet aromas, soft tannin, low
 * acidity or full body that make a dry wine feel sweet, and a mark that
 * stands high among its kind although the bare number is small.
 *
 * A trait is not named against what the reader set on its own gauge: a
 * tannin they found low is not what made the wine dry for them.
 */
import {
  drierCauses,
  raisedBy,
  type SweeterCause,
  type WineSweetness,
} from "../../record_reading/facts/wine_sweetness.ts";
import type { RecordReading } from "../../record_reading/read_record.ts";
import type { Section } from "../selection/selection.ts";
import { short } from "./words.ts";
import { type Feel } from "./reason_feel.ts";

/** A sentence names two aromas at most. */
const MAX_AROMAS = 2;

const DRIER: Readonly<Record<string, readonly [trait: string, by: string]>> = {
  tannin: ["타닌이 많은", "떫은 조임에 단맛이 뒤로 밀려나"],
  "tannin+acidity": [
    "타닌이 많고 산미도 높은",
    "떫은 조임과 산미에 단맛이 눌려",
  ],
  acidity: ["산미가 높은", "새콤한 산미에 단맛이 눌려"],
};

const SOFT: Readonly<Record<string, string>> = {
  soft_tannin: "타닌이 순한",
  low_acidity: "산미가 낮은",
  "soft_tannin+low_acidity": "타닌이 순하고 산미도 낮은",
};

/** The gauge whose answer a trait must not stand against, and the side that would. */
const AGAINST: Readonly<Record<string, readonly [axis: string, side: string]>> =
  {
    tannin: ["tannin", "low"],
    acidity: ["acidity", "low"],
    soft_tannin: ["tannin", "high"],
    low_acidity: ["acidity", "high"],
    body: ["body", "low"],
  };

export type WineSweetnessTold = {
  /** The reason's name where the trait gives it one. */
  name?: string;
  /** The sentence, without its period. */
  body: string;
};

/**
 * The sentence for a sweetness answer of a still wine, or null where the
 * bottle's traits say nothing of it: the answer is then told as it was felt.
 */
export function tellWineSweetness(
  /** The step the reader set, 1 to 5. */
  level: number,
  section: Section,
  feel: Feel,
  kind: string,
  wine: WineSweetness,
  /** The bottle's own sweetness mark, read for it. */
  mark: number | null,
  answers: RecordReading["answers"]["gauges"],
): WineSweetnessTold | null {
  const felt = (cause: string) => {
    const [axis, side] = AGAINST[cause] ?? [];
    return !answers.some((a) =>
      a.axis === axis && (a.side === "none" ? "low" : a.side) === side
    );
  };
  const drink = `이 ${kind}{은} 같은 종류 가운데`;

  // 더 있었으면: what stands high among the kind is what makes it dry.
  if (level < 3 && section === "burden") {
    const drier = DRIER[drierCauses(wine).filter(felt).join("+")];
    return drier
      ? {
        body: `${drink}서도 ${drier[0]} 편이라서, ${
          drier[1]
        } 한결 드라이하게 느껴져요`,
      }
      : null;
  }
  if (level <= 3) return null;

  // A mark of 2 or 3 that stands high among the kind is said so, never
  // "적은" as the bare number would read.
  if (wine.stored === "high") {
    return mark !== null && mark <= 3
      ? { body: `${drink}서는 단맛이 있는 편이라서, ${feel.long}` }
      : null;
  }

  // A dry wine that felt sweet: the aromas with whatever is soft beside
  // them, else what is soft, else a full body.
  // An aroma the dictionary has no name for cannot be said.
  const named = wine.sweetAromas.filter((key) => short(key) !== key);
  const causes: SweeterCause[] = raisedBy(wine).filter((c) =>
    felt(c) && (c !== "aroma" || named.length > 0)
  );
  if (!causes.length) return null;
  const liked = section === "liked";
  const aromas = named.slice(0, MAX_AROMAS).map((key) => `**${short(key)} 향**`)
    .join("{과} ");
  const soft =
    SOFT[causes.filter((c) => c !== "aroma" && c !== "body").join("+")];
  if (causes.includes("aroma")) {
    return {
      name: liked ? "달콤한 향이 채워 준 단맛" : "생각보다 달게 느껴진 단맛",
      body: soft
        ? `이 ${kind}{은} ${aromas}{을} 지닌 데다 같은 종류 가운데 ${soft} 편이라서, 달콤한 향이 단맛처럼 느껴지고 그 단맛을 누르는 맛도 적어요`
        : `이 ${kind}{은} ${aromas}{을} 지니고 있어서, 코로 들어온 달콤한 향이 단맛과 하나로 묶여 실제보다 ${
          liked ? "더" : "훨씬"
        } 달게 느껴져요`,
    };
  }
  if (soft) {
    return {
      name: liked ? "가려지지 않고 드러난 단맛" : "생각보다 달게 느껴진 단맛",
      body:
        `${drink} ${soft} 편이라서, 단맛을 누르는 맛이 적어 단맛이 가려지지 않고 또렷하게 드러나요`,
    };
  }
  return {
    name: liked ? "둥근 무게감이 채워 준 단맛" : "생각보다 달게 느껴진 단맛",
    body:
      `${drink} 묵직한 편이라서, 입안을 둥글게 채우는 무게감이 단맛처럼 느껴져요`,
  };
}
