/**
 * How sweet a still wine feels, next to other wines of the same stored
 * sweetness.
 *
 * Nine of ten red wines carry sweetness 1, so the stored number cannot tell
 * them apart, and yet people do call one dry red "sweeter" than another:
 * ripe-fruit and vanilla-like aromas raise the sweetness a drinker expects
 * (the principle lines of effect_ripe_fruit and effect_sweet_scent cite the
 * studies), while tannin and acidity pull the impression the other way. This
 * reading adds those to the stored number.
 *
 * The stored number stays the ground: the added part is held between 0 and
 * 0.9, so a wine never passes one whose stored sweetness is a step higher.
 * The reading therefore only orders the bottles that share a stored value.
 * The weights are a judgment, not a measurement: each trait moves a bottle by
 * about a third of a step at most, and the order they give was checked
 * against the catalog (Zinfandel and Primitivo above the red average, Médoc,
 * Chianti Classico and Barolo below it).
 *
 * Still wines only. A sparkling wine's sweetness is set by its dosage and a
 * fortified wine's by when the spirit stopped the ferment; their stored
 * numbers already spread across the scale.
 */
import { aromaLine } from "../dictionary/aroma_lineage.ts";
import { EFFECT_ROWS } from "../findings/knowledge.ts";
import { kindOfStyle } from "./kind_of_style.ts";

/** Styles the reading applies to, and whether tannin takes part. */
const STILL_WINES: Readonly<Record<string, { tannin: boolean }>> = {
  red_wine: { tannin: true },
  orange_wine: { tannin: true },
  white_wine: { tannin: false },
  rose_wine: { tannin: false },
};

/** The most the reading adds to the stored number. */
export const FELT_SWEETNESS_CEILING = 0.9;
/** Where a wine with no trait either way sits above its stored number. */
const BASE = 0.3;
const RIPE_FRUIT = 0.3;
const SWEET_SCENT = 0.3;
const PER_TANNIN_STEP = 0.15;
const PER_ACIDITY_STEP = 0.12;
/** Fullness reads as roundness only where tannin does not grip. */
const PER_BODY_STEP = 0.08;

type FeltSweetnessInput = {
  style_key: string | null | undefined;
  levels: Readonly<Record<string, number | undefined>>;
  aroma_tags: readonly string[];
};

const under = (tags: readonly string[], nodes: readonly string[]) =>
  tags.some((tag) => aromaLine(tag).some((name) => nodes.includes(name)));

export function hasFeltSweetness(styleKey: string | null | undefined) {
  const kind = kindOfStyle(styleKey);
  return !!kind && kind in STILL_WINES;
}

/** Whether tannin takes part in how sweet the kind feels (red and orange wine). */
export function tanninShapesSweetness(styleKey: string | null | undefined) {
  const kind = kindOfStyle(styleKey);
  return !!kind && STILL_WINES[kind]?.tannin === true;
}

/**
 * The stored sweetness plus what the wine's other traits add, or null for a
 * drink the reading does not apply to or a bottle without a stored sweetness.
 * A trait the bottle has no value for adds nothing.
 */
export function feltSweetness(bottle: FeltSweetnessInput): number | null {
  const kind = kindOfStyle(bottle.style_key);
  const style = kind ? STILL_WINES[kind] : undefined;
  const stored = bottle.levels.sweetness;
  if (!style || typeof stored !== "number") return null;
  const step = (dimension: string) => {
    const level = bottle.levels[dimension];
    return typeof level === "number" ? level - 3 : 0;
  };
  const tannin = style.tannin ? step("astringency") : 0;
  let added = BASE;
  if (under(bottle.aroma_tags, EFFECT_ROWS.effect_ripe_fruit.nodes)) {
    added += RIPE_FRUIT;
  }
  if (under(bottle.aroma_tags, EFFECT_ROWS.effect_sweet_scent.nodes)) {
    added += SWEET_SCENT;
  }
  added -= PER_TANNIN_STEP * tannin;
  added -= PER_ACIDITY_STEP * step("acidity");
  if (tannin <= 0) added += PER_BODY_STEP * step("body");
  return stored + Math.min(FELT_SWEETNESS_CEILING, Math.max(0, added));
}
