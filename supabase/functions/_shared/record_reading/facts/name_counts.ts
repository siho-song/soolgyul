/**
 * Whether a name may be said to have a taste: the one place that answers it,
 * and it answers from the catalog's own bottles.
 *
 * A name (a kind, a grape, a place, a cask, an ingredient) stands for many
 * bottles that differ. The dictionary keeps one value a name (부르고뉴: 흙
 * 향, 싱글 몰트 위스키: 묵직한 바디감); of the bottles the catalog holds, one
 * Burgundy red in six carries the earth and half the single malts are full.
 * So what a card says of a name, or sends the reader to look for, is asked
 * here first, and every number such an answer turns on is kept here.
 *
 * ./kind_spreads_build.ts counts the bottles each night; ./kind_place.ts
 * holds the count. What is counted at all is the count's own business and is
 * said there: a kind from 100 bottles, a name from MIN_NAMED_BOTTLES, a
 * grape on a shelf from MIN_GRAPE_BOTTLES (more than a name's thirty: to be
 * made one number when the shipped count is next rebuilt).
 */
import {
  aromasOfKind,
  bottlesCarrying,
  type Carried,
  levelsOfKind,
  MIN_NAMED_BOTTLES,
  tasteOfName,
} from "./kind_place.ts";

/** What fewer bottles of the kind than this carry is not worth looking for. */
export const ENOUGH_BOTTLES = MIN_NAMED_BOTTLES;
/** Nor what a smaller part of the kind than this carries. */
export const ENOUGH_SHARE = 0.005;
/** What more than this part of the kind's bottles carry tells nothing apart. */
export const EVERY_BOTTLE = 0.5;
/**
 * A name is mostly on a side when half its bottles or more are (the user's
 * word, 2026-11-23): 대체로 is not wrong of a half, and no number tells 59%
 * from 60%.
 */
export const MOST_OF_A_NAME = 0.5;

/**
 * A step is a kind's usual way when more than this part of the kind's
 * bottles sit on it: the same half. Nine red wines in ten are not sweet, so
 * a red that was not sweet says the reader met the kind, not this bottle.
 */
export const USUAL_SHARE = MOST_OF_A_NAME;
/**
 * A bottle stands out among its kind on a step no more than this part of
 * the kind (or of its makers) shares …
 */
export const STANDS_OUT_SHARE = 0.2;
/** … and that lies within this part of the kind's bottles at either end. */
export const STANDS_OUT_END = 0.1;

/** What the bottles say of a question: they bear it out, they do not, or they are not counted on it. */
export type Borne = "yes" | "no" | "uncounted";

/** A name as the catalog counts it: what kind of thing, and its key. */
export type Name = { what: Carried; key: string };

export type Side = "high" | "low";

/** How a name stands on a kind's shelf: on too few bottles to look for, on enough, or on so many it tells nothing apart. */
export type OnShelf = "uncounted" | "few" | "enough" | "everywhere";

export function onShelf(name: Name, shelf: string | null): OnShelf {
  const n = bottlesCarrying(name.what, name.key, shelf);
  if (!n || !n.of) return "uncounted";
  const share = n.bottles / n.of;
  if (n.bottles < ENOUGH_BOTTLES || share < ENOUGH_SHARE) return "few";
  return share > EVERY_BOTTLE ? "everywhere" : "enough";
}

const part = (steps: readonly number[], from: number, to: number) => {
  const all = steps.reduce((a, b) => a + b, 0);
  if (!all) return null;
  let on = 0;
  for (let step = from; step <= to; step++) on += steps[step - 1] ?? 0;
  return on / all;
};

/** The five steps of the name's bottles on a dimension; a kind's are its own bottles'. */
function stepsOf(
  name: Name,
  shelf: string | null,
  dimension: string,
): readonly number[] | null {
  return name.what === "kinds"
    ? levelsOfKind(dimension, name.key)
    : tasteOfName(name.what, name.key, shelf)?.levels[dimension] ?? null;
}

/**
 * The part of the name's bottles that stand on a side of a dimension (4 and
 * 5, or 1 and 2); null where its bottles are not counted on it.
 */
export function shareOnSide(
  name: Name,
  shelf: string | null,
  dimension: string,
  side: Side,
): number | null {
  const steps = stepsOf(name, shelf, dimension);
  return steps
    ? part(steps, ...(side === "high" ? [4, 5] : [1, 2]) as [number, number])
    : null;
}

/**
 * The part of the name's bottles that stand below (or above) a step: what
 * choosing the name does to a taste felt at that step.
 */
export function shareBeyond(
  name: Name,
  shelf: string | null,
  dimension: string,
  step: number,
  toward: "lower" | "higher",
): number | null {
  const steps = stepsOf(name, shelf, dimension);
  if (!steps) return null;
  return toward === "lower"
    ? part(steps, 1, step - 1)
    : part(steps, step + 1, 5);
}

/**
 * The part of the name's bottles that carry an aroma tag, beside the part of
 * the whole shelf that does: an aroma is the name's when its bottles carry
 * it clearly more often than the kind's do.
 */
export function shareWithAroma(
  name: Name,
  shelf: string | null,
  tag: string,
): { name: number; shelf: number } | null {
  const kind = aromasOfKind(shelf);
  const own = name.what === "kinds"
    ? aromasOfKind(name.key)
    : tasteOfName(name.what, name.key, shelf);
  if (!kind || !own || !own.bottles) return null;
  return {
    name: (own.aromas[tag] ?? 0) / own.bottles,
    shelf: (kind.aromas[tag] ?? 0) / kind.bottles,
  };
}

/** Whether most of the name's bottles stand on a side of a dimension: the name may be said to be so. */
export function mostlyOnSide(
  name: Name,
  shelf: string | null,
  dimension: string | null,
  side: Side,
): Borne {
  const share = dimension ? shareOnSide(name, shelf, dimension, side) : null;
  return share === null ? "uncounted" : share >= MOST_OF_A_NAME ? "yes" : "no";
}
