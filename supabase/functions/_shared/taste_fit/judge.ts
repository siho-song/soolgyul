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
 *
 * A gauge step is held on the catalog's 1 to 5 numbers themselves: a bottle
 * within one step of a liked one is inside, one two steps away is outside. An
 * aroma picked in the mouth or after swallowing is held against the bottle's
 * tags of that stage where it has any, otherwise against its nose. 피트 and
 * 스파이시 are held against whether the bottle carries the aroma at all (the
 * tag lines); a tag that is missing never counts against a bottle.
 */
import {
  type AromaFamily,
  familiesOfBottle,
  kindGroup,
  type PlaceAxis,
  placesOf,
  shareOfFamily,
} from "../taste_card/facts/kind_place.ts";
import type { AromaStage } from "../taste_card/facts/facts.ts";
import type { AxisLine, FamilyLine, Ledger, TagLine } from "./ledger.ts";

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
  /** The tags of the mouth and of the finish, where the catalog keeps them apart from the nose. */
  palate_tags?: readonly string[];
  finish_tags?: readonly string[];
  production_process_keys?: readonly string[];
};

/**
 * One thing the verdict rests on: a dimension at the bottle's third of its
 * kind, or an aroma family. `absent` says the bottle does not carry the
 * family (피트, 스파이시) and the verdict rests on that.
 */
export type Reason =
  | { axis: PlaceAxis; level: "low" | "mid" | "high" }
  | { family: AromaFamily; absent?: true };

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
/** A liked gauge step covers this many steps either side in full, and nothing one step further. */
const STEP_RANGE = 1;
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

/** The aroma family whose tags answer a 피트 or 스파이시 gauge. */
const TAG_FAMILY: Readonly<Record<TagLine["tag"], AromaFamily>> = {
  peat: "effect_smoke",
  spice: "effect_spice",
};
/**
 * A bottle that carries the 피트 or 스파이시 the reader liked the absence of
 * counts half of a dimension that lies far: a tag says the aroma is there,
 * never how much.
 */
const TAG_APART = 0.5;
/** A card from before the three pickers named its aromas by the nose. */
const NOSE: readonly AromaStage[] = ["nose"];

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

/**
 * 1 inside the like's reach, falling to 0 between NEAR and FAR. A gauge step
 * is counted on the catalog's numbers instead: 1 within STEP_RANGE of it, 0
 * a step further.
 */
function cover(
  line: AxisLine,
  position: number,
  level: number | null,
): number {
  if (line.byStep && level !== null) {
    const steps = stepsOutside(line, level);
    return Math.min(1, Math.max(0, STEP_RANGE + 1 - steps));
  }
  const distance = outside(line, position);
  return distance <= NEAR
    ? 1
    : distance >= FAR
    ? 0
    : (FAR - distance) / (FAR - NEAR);
}

/**
 * Whether a burden line speaks for the place. A gauge step speaks for the
 * numbers on the side it named, its own included; kind-wide, from one step
 * beyond its own.
 */
function minded(
  line: AxisLine,
  position: number,
  level: number | null,
): boolean {
  if (line.byStep && level !== null) {
    const from = line.level as number;
    const beyond = line.reach === "up"
      ? level - from
      : line.reach === "down"
      ? from - level
      : -Math.abs(level - from);
    return beyond >= (line.kindWide ? 1 : 0);
  }
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
  const tagsAt: Record<AromaStage, readonly string[]> = {
    nose: product.aroma_tags,
    palate: product.palate_tags?.length
      ? product.palate_tags
      : product.aroma_tags,
    finish: product.finish_tags?.length
      ? product.finish_tags
      : product.aroma_tags,
  };
  const carriedAt: Record<AromaStage, Set<AromaFamily>> = {
    nose: familiesOfBottle(tagsAt.nose, processes),
    palate: familiesOfBottle(tagsAt.palate, processes),
    finish: familiesOfBottle(tagsAt.finish, processes),
  };
  /** Every family the bottle carries, at whatever stage. */
  const carried = new Set(Object.values(carriedAt).flatMap((at) => [...at]));
  const tags = [...new Set(Object.values(tagsAt).flat())];
  const unjudged = (why: NonNullable<Verdict["unjudged"]>): Verdict => ({
    badge: "no_info",
    unjudged: why,
    group: group?.name ?? null,
    reasons: [],
    aromas: [],
  });
  if (Object.keys(places).length === 0 && carried.size === 0) {
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
    // The number a line's steps are counted to: the stored one for a gauge
    // step, the one the place was read from (a still wine's felt sweetness)
    // for the older lines.
    const levelFor = (line: AxisLine) =>
      line.byStep ? product.levels[axis] ?? null : place.level;
    const covered = likes.reduce(
      (sum, line) => sum + line.weight * cover(line, at, levelFor(line)),
      0,
    );
    const mindedLines = lines.filter((line) =>
      line.side === "burden" && minded(line, at, levelFor(line))
    );
    const against = mindedLines.reduce((sum, line) => sum + line.weight, 0);
    if (against - covered >= BURDEN) {
      // Named by the side the reader minded (too little or too much), not
      // by the bottle's third: a middling place is still "too little" to a
      // reader who found a stronger one lacking. A burden that named no side
      // keeps the bottle's third.
      const named = (reach: AxisLine["reach"]) =>
        mindedLines.filter((line) => line.reach === reach)
          .reduce((sum, line) => sum + line.weight, 0);
      burdens.push({
        reason: {
          axis: axis as PlaceAxis,
          level: named("down") > against / 2
            ? "low"
            : named("up") >= against / 2
            ? "high"
            : reason.level,
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
    // Outside everything the reader liked on this dimension.
    const liked = likes.reduce((sum, line) => sum + line.weight, 0);
    if (liked >= SETTLED) {
      different.push({ reason, weight: liked });
      const veryFar = likes.every((line) => {
        const level = levelFor(line);
        return (!line.byStep && outside(line, at) >= STARK) ||
          (line.level !== undefined && level !== null &&
            stepsOutside(line, level) >= STARK_STEPS);
      });
      if (veryFar) stark = true;
    }
  }

  /** A picked aroma and a gauge that say the same of one family are one reason, the heavier. */
  const put = (
    items: Weighed[],
    reason: Extract<Reason, { family: AromaFamily }>,
    weight: number,
  ) => {
    const same = items.find(({ reason: other }) =>
      "family" in other && other.family === reason.family &&
      other.absent === reason.absent
    );
    if (same) same.weight = Math.max(same.weight, weight);
    else items.push({ reason, weight });
  };

  const stagesOf = (line: FamilyLine) => line.stages ?? NOSE;
  // A line is held against the bottle's tags of the stages it was picked in.
  const familyWeight = (family: AromaFamily, side: "like" | "burden") =>
    mine.families.filter((line) =>
      line.family === family && line.side === side &&
      stagesOf(line).some((stage) => carriedAt[stage].has(family))
    ).reduce((sum, line) => sum + line.weight, 0);
  // The bottle's aromas were held against the reader's aroma lines, met or not.
  if (
    mine.families.some((line) =>
      stagesOf(line).some((stage) => tagsAt[stage].length > 0)
    )
  ) compared++;
  for (const family of carried) {
    const reason = { family };
    const liked = familyWeight(family, "like");
    const minded = familyWeight(family, "burden");
    if (minded - liked >= BURDEN) {
      put(burdens, reason, minded - liked);
    } else if (liked > 0 && minded === 0) {
      const share = shareOfFamily(
        family,
        product.style_key,
        product.category_key,
      ) ?? 0;
      put(matches, reason, Math.min(1, liked) * (1 - share));
    } else if (
      DIVIDING_FAMILIES.includes(family) && carriedAt.nose.has(family) &&
      !mine.met.has(family) &&
      (shareOfFamily(family, product.style_key, product.category_key) ?? 0) <
        COMMON_FAMILY
    ) {
      stark = true;
      put(different, reason, 1);
    }
  }

  // 피트 and 스파이시: the bottle carries the aroma or it does not. A bottle
  // nobody tagged is left out, because no tags is not "no peat".
  for (const tag of ["peat", "spice"] as const) {
    const lines = mine.tags.filter((line) => line.tag === tag);
    const family = TAG_FAMILY[tag];
    const has = carried.has(family);
    if (lines.length === 0 || (!has && tags.length === 0)) continue;
    compared++;
    const weigh = (side: TagLine["side"], wants: TagLine["wants"]) =>
      lines.filter((line) => line.side === side && line.wants === wants)
        .reduce((sum, line) => sum + line.weight, 0);
    const liked = weigh("like", has ? "present" : "absent");
    const other = weigh("like", has ? "absent" : "present");
    const minded = has ? weigh("burden", "absent") : 0;
    const reason = has ? { family } : { family, absent: true as const };
    if (minded - liked >= BURDEN) {
      put(burdens, reason, minded - liked);
    } else if (minded > 0) {
      // A like and a burden on the same aroma cancel.
      continue;
    } else if (liked > 0) {
      // As a dimension: the part of the likes that this bottle meets, and
      // less the more of the kind's bottles are the same.
      const share = shareOfFamily(
        family,
        product.style_key,
        product.category_key,
      ) ?? 0;
      const all = liked + other;
      put(
        matches,
        reason,
        (liked / all) * Math.min(1, all) * (has ? 1 - share : share),
      );
    } else if (has && other >= SETTLED) {
      // Only a tag that is there counts against a bottle: a missing one may
      // be a short tag list.
      put(different, reason, Math.min(1, other) * TAG_APART);
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
      aromas: aromasFor(tags, processes, reasons),
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
