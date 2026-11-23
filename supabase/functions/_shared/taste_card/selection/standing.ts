/**
 * Whether a bottle stands out among the bottles of its kind on a gauge: a
 * taste few of them share. An answer on that side says something of the
 * reader (a whisky far smokier than most, and they liked exactly that); an
 * answer most bottles of the kind would have drawn says only that they met
 * the kind.
 *
 * It is read from the bottle's own level among the bottles of its kind
 * (facts/kind_place.ts), or, where no level is kept (피트, 감칠맛, 자극), from
 * its producer: a house style few producers of the kind share.
 */
import { terms } from "../dictionary/dictionary.ts";
import type { Cause } from "../evidence/evidence.ts";
import { GAUGE_LEVEL_DIMENSION, type GaugeAxis } from "../facts/facts.ts";
import {
  PLACE_DIMENSIONS,
  type PlaceDimension,
  placeOfLevel,
} from "../facts/kind_place.ts";
import { STANDS_OUT_END, STANDS_OUT_SHARE } from "../facts/name_counts.ts";
import type { Prepared } from "../prepare/prepare.ts";

/** The gauge an axis of the dictionary is asked on. */
const GAUGE_OF: Readonly<Record<string, GaugeAxis>> = {
  astringency: "tannin",
  carbonation: "sparkling",
};

type HouseStyle = {
  categories?: readonly string[];
  taste?: Readonly<Record<string, { step?: number }>>;
};

/** Of the producers of a category that have a house style on an axis, how many stand on each side. */
const HOUSES: ReadonlyMap<string, { high: number; low: number; all: number }> =
  (() => {
    const map = new Map<string, { high: number; low: number; all: number }>();
    for (const t of terms("producer") as readonly HouseStyle[]) {
      for (const category of t.categories ?? []) {
        for (const [axis, { step }] of Object.entries(t.taste ?? {})) {
          if (typeof step !== "number") continue;
          const key = `${category}:${GAUGE_OF[axis] ?? axis}`;
          const n = map.get(key) ?? { high: 0, low: 0, all: 0 };
          n.all++;
          if (step >= 4) n.high++;
          if (step <= 2) n.low++;
          map.set(key, n);
        }
      }
    }
    return map;
  })();

/** The level dimension a gauge is placed on among its kind, where one is kept. */
export function placeDimensionOf(axis: GaugeAxis): PlaceDimension | undefined {
  return PLACE_DIMENSIONS.find((d) => d === GAUGE_LEVEL_DIMENSION[axis]);
}

/**
 * The side on which the bottle stands out among its kind on a gauge, given
 * the causes that speak of that gauge.
 */
export function standsOutIn(
  bottle: Prepared["bottle"],
): (axis: GaugeAxis, causes: readonly Cause[]) => "high" | "low" | null {
  const { category, style_key, levels } = bottle;
  return (axis, causes) => {
    const dimension = placeDimensionOf(axis);
    const own = dimension ? levels[dimension] : undefined;
    if (dimension && own?.of === "bottle") {
      const place = placeOfLevel(dimension, style_key, category, own.level);
      if (!place || place.share > STANDS_OUT_SHARE) return null;
      return place.position >= 1 - STANDS_OUT_END
        ? "high"
        : place.position <= STANDS_OUT_END
        ? "low"
        : null;
    }
    // No level of the bottle: its producer's house style among the kind's producers.
    const step = causes.find((c) => c.factor === "producer")?.tendency?.step;
    const houses = HOUSES.get(`${category}:${axis}`);
    if (step === undefined || !houses || step === 3) return null;
    const side = step > 3 ? "high" : "low";
    return houses[side] / houses.all <= STANDS_OUT_SHARE ? side : null;
  };
}
