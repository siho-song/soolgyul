/**
 * Where does this bottle stand next to what the reader has recorded?
 *
 * The bottle is placed among its own kind on every dimension it has a value
 * for (kind_place.ts), and each place is held against the ledger lines of the
 * same group of kinds:
 *
 * - no record in the group: not judged, and the reader is told so;
 * - a place the reader called a burden, not outweighed by a like on the same
 *   place: 아쉬움;
 * - a strong character the reader has never met in this group (smoke), a
 *   place very far from every one they liked or found right, or far places
 *   that weigh more than what matches: 낯설 수 있음. This is a statement of difference, never of dislike.
 *   Far means about two steps of the 1 to 5 scale or more, read among the
 *   kind (Place.standing);
 * - several dimensions inside what the reader liked, weighing enough
 *   together: 딱 맞음. One match is never enough;
 * - otherwise 편안함: compared, and nothing stands out either way.
 *
 * A dimension the bottle or the kind has no value for is left out on both
 * sides, so a gap in the data never decides a verdict; a bottle that shares
 * no dimension with the reader's lines is not judged.
 */
import {
  type AromaFamily,
  familiesOfBottle,
  kindGroup,
  type PlaceAxis,
  placesOf,
  shareOfFamily,
} from "../taste_card/facts/kind_place.ts";
import type { AxisLine, Ledger } from "./ledger.ts";

export type TasteFitBadge =
  | "star"
  | "neutral"
  | "unfamiliar"
  | "caution"
  | "no_info";

type CandidateProduct = {
  abv_percent: number | null;
  style_key: string | null;
  category_key: string | null;
  /** Tasting-profile levels present on the bottle, 1–5. */
  levels: Readonly<Record<string, number>>;
  aroma_tags: readonly string[];
  production_process_keys?: readonly string[];
};

/** One thing the verdict rests on: a dimension at the bottle's third of its kind, or an aroma family. */
export type Reason =
  | { axis: PlaceAxis; level: "low" | "mid" | "high" }
  | { family: AromaFamily };

export type Verdict = {
  badge: TasteFitBadge;
  /** Why no badge is shown: the bottle has no data, the reader has no record of its kind, or the two share no dimension. */
  unjudged?: "no_data" | "no_record" | "nothing_shared";
  /** The group of kinds the bottle belongs to, as the reader would say it. */
  group: string | null;
  /** What the verdict rests on, heaviest first, at most three. */
  reasons: readonly Reason[];
  /** Up to three of the bottle's aroma tags, those of a family in the reasons first. */
  aromas: readonly string[];
};

/** A like covers a place fully within this distance of its reach … */
const NEAR = 0.15;
/** … and not at all beyond this one. */
const FAR = 0.35;
/** About three steps of the scale away: a difference that speaks whatever else matches. */
const STARK = 0.55;
/**
 * The same said on the scale itself. Where nearly a whole kind shares one
 * stored value (dry red wines), the kind's few other bottles sit crowded at
 * the top of its places, so the steps between the numbers are counted too.
 */
const STARK_STEPS = 2.5;
/** A burden line speaks for the drunk bottle's place and the side it named. */
const SAME_PLACE = 0.02;
/** Likes on a dimension must weigh this much before a far place counts as different. */
const SETTLED = 0.3;
/** A burden left after the likes on the same place are taken off. */
const BURDEN = 0.4;
/** What the matching dimensions and families must weigh together for 딱 맞음. */
const MATCH = 1.0;
/** A dimension or family counts as one of the "several" from this weight. */
const COUNTED = 0.15;
/** A family this common in the kind is no surprise to anyone who drinks it. */
const COMMON_FAMILY = 0.5;

/**
 * Aroma families whose character divides drinkers at first meeting. Smoke
 * is noticed at trace amounts and "반기는 쪽과 밀어내는 쪽이 갈려요"
 * (effect_smoke); a bottle that carries one the reader has never met in
 * the kind is called unfamiliar whatever else matches.
 */
const DIVIDING_FAMILIES: readonly AromaFamily[] = ["effect_smoke"];

const third = (position: number): "low" | "mid" | "high" =>
  position < 1 / 3 ? "low" : position > 2 / 3 ? "high" : "mid";

/** How far the place lies outside what the line reaches, 0 inside it. */
function outside(line: AxisLine, position: number): number {
  return line.reach === "up"
    ? Math.max(0, line.position - position)
    : line.reach === "down"
    ? Math.max(0, position - line.position)
    : Math.abs(position - line.position);
}

/** The same on the 1 to 5 scale, in steps. */
function stepsOutside(line: AxisLine, level: number): number {
  const from = line.level as number;
  return line.reach === "up"
    ? Math.max(0, from - level)
    : line.reach === "down"
    ? Math.max(0, level - from)
    : Math.abs(level - from);
}

/** 1 inside the like's reach, falling to 0 between NEAR and FAR. */
function cover(line: AxisLine, position: number): number {
  const distance = outside(line, position);
  return distance <= NEAR
    ? 1
    : distance >= FAR
    ? 0
    : (FAR - distance) / (FAR - NEAR);
}

/** Whether a burden line speaks for the place. */
function minded(line: AxisLine, position: number): boolean {
  if (!line.kindWide) return outside(line, position) <= SAME_PLACE;
  return line.reach === "up"
    ? position >= line.position + NEAR
    : position <= line.position - NEAR;
}

type Weighed = { reason: Reason; weight: number };

function aromasFor(
  tags: readonly string[],
  processes: readonly string[],
  reasons: readonly Reason[],
): string[] {
  const families = reasons.flatMap((r) => "family" in r ? [r.family] : []);
  const own = tags.filter((tag) =>
    [...familiesOfBottle([tag])].some((family) => families.includes(family))
  );
  void processes;
  return [...own, ...tags.filter((tag) => !own.includes(tag))].slice(0, 3);
}

export function judgeProduct(
  product: CandidateProduct,
  ledger: Ledger,
): Verdict {
  const group = kindGroup(product.style_key, product.category_key);
  const places = placesOf(product);
  const processes = product.production_process_keys ?? [];
  const families = familiesOfBottle(product.aroma_tags, processes);
  const unjudged = (why: NonNullable<Verdict["unjudged"]>): Verdict => ({
    badge: "no_info",
    unjudged: why,
    group: group?.name ?? null,
    reasons: [],
    aromas: [],
  });
  if (Object.keys(places).length === 0 && families.size === 0) {
    return unjudged("no_data");
  }
  const mine = group ? ledger.get(group.key) : undefined;
  if (!group || !mine) return unjudged("no_record");

  const burdens: Weighed[] = [];
  const matches: Weighed[] = [];
  const different: Weighed[] = [];
  let compared = 0;
  /** One difference large enough to speak whatever else matches. */
  let stark = false;

  for (const [axis, place] of Object.entries(places)) {
    const lines = mine.axes.filter((line) => line.axis === axis);
    if (lines.length === 0) continue;
    compared++;
    const at = place.standing;
    const reason: Reason = { axis: axis as PlaceAxis, level: third(at) };
    const likes = lines.filter((line) => line.side === "like");
    const covered = likes.reduce(
      (sum, line) => sum + line.weight * cover(line, at),
      0,
    );
    const mindedLines = lines.filter((line) =>
      line.side === "burden" && minded(line, at)
    );
    const against = mindedLines.reduce((sum, line) => sum + line.weight, 0);
    if (against - covered >= BURDEN) {
      // Named by the side the reader minded (too little or too much), not
      // by the bottle's third: a middling place is still "too little" to a
      // reader who found a stronger one lacking.
      const tooLittle = mindedLines.filter((line) => line.reach === "down")
        .reduce((sum, line) => sum + line.weight, 0);
      burdens.push({
        reason: {
          axis: axis as PlaceAxis,
          level: tooLittle > against / 2 ? "low" : "high",
        },
        weight: against - covered,
      });
      continue;
    }
    // A like and a burden on the same place cancel; the dimension says nothing.
    if (against > 0) continue;
    if (covered > 0) {
      // The part of the reader's likes on this dimension that reach the
      // place, so a long history weighs no more than a short one; and
      // meeting on a value most of the kind shares is weak evidence.
      const all = likes.reduce((sum, line) => sum + line.weight, 0);
      matches.push({
        reason,
        weight: (covered / all) * Math.min(1, all) * (1 - place.share),
      });
      continue;
    }
    // Outside everything the reader liked on this dimension. A 적당했어요 is
    // weaker word about taste than a 좋았어요: on its own it marks a
    // difference only when the place is very far.
    const weigh = (some: AxisLine[]) =>
      some.reduce((sum, line) => sum + line.weight, 0);
    const veryFar = likes.every((line) =>
      outside(line, at) >= STARK ||
      (line.level !== undefined && place.level !== null &&
        stepsOutside(line, place.level) >= STARK_STEPS)
    );
    const liked = likes.filter((line) => !line.fine);
    if (weigh(liked) >= SETTLED) {
      different.push({ reason, weight: weigh(liked) });
      if (veryFar) stark = true;
    } else if (weigh(likes) >= SETTLED && veryFar) {
      different.push({ reason, weight: weigh(likes) });
      stark = true;
    }
  }

  const familyWeight = (family: AromaFamily, side: "like" | "burden") =>
    mine.families.filter((line) => line.family === family && line.side === side)
      .reduce((sum, line) => sum + line.weight, 0);
  // The bottle's nose was held against the reader's aroma lines, met or not.
  if (product.aroma_tags.length > 0 && mine.families.length > 0) compared++;
  for (const family of families) {
    const reason: Reason = { family };
    const liked = familyWeight(family, "like");
    const minded = familyWeight(family, "burden");
    if (minded - liked >= BURDEN) {
      burdens.push({ reason, weight: minded - liked });
    } else if (liked > 0 && minded === 0) {
      const share = shareOfFamily(
        family,
        product.style_key,
        product.category_key,
      ) ?? 0;
      matches.push({ reason, weight: Math.min(1, liked) * (1 - share) });
    } else if (
      DIVIDING_FAMILIES.includes(family) && !mine.met.has(family) &&
      (shareOfFamily(family, product.style_key, product.category_key) ?? 0) <
        COMMON_FAMILY
    ) {
      stark = true;
      different.push({ reason, weight: 1 });
    }
  }

  const heaviest = (items: Weighed[]) =>
    [...items].sort((a, b) => b.weight - a.weight).slice(0, 3).map((item) =>
      item.reason
    );
  const total = (items: Weighed[]) =>
    items.reduce((sum, item) => sum + item.weight, 0);
  const verdict = (badge: TasteFitBadge, items: Weighed[]): Verdict => {
    const reasons = heaviest(items);
    return {
      badge,
      group: group.name,
      reasons,
      aromas: aromasFor(product.aroma_tags, processes, reasons),
    };
  };

  if (burdens.length > 0) return verdict("caution", burdens);
  if (compared === 0 && different.length === 0) {
    return unjudged("nothing_shared");
  }
  if (stark || total(different) > total(matches)) {
    return verdict("unfamiliar", different);
  }
  const counted = matches.filter((item) => item.weight >= COUNTED);
  // Aromas count once however many liked families the bottle carries: a
  // bottle is never a match on its nose alone.
  const features = counted.filter((item) => "axis" in item.reason).length +
    (counted.some((item) => "family" in item.reason) ? 1 : 0);
  const aroma = Math.max(
    0,
    ...matches.flatMap((item) => "family" in item.reason ? [item.weight] : []),
  );
  const weight = total(matches.filter((item) => "axis" in item.reason)) +
    aroma;
  if (weight >= MATCH && features >= 2 && different.length === 0) {
    return verdict("star", counted);
  }
  return verdict("neutral", counted);
}
