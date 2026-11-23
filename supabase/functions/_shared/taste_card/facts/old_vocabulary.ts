/**
 * The stages that are not rebuilt yet (근거 찾기, 결과 선정, 글쓰기, the
 * guide, the taste letters, the fit) still speak the vocabulary they were
 * written in: reactions (묵직함, 떫음, 은은한 단맛) and a flat list of
 * product facts. This file gives it to them from what 준비 made, and from
 * nothing else. It goes when the last of those stages reads 해석 결과 and
 * 술의 사실 itself.
 *
 * How a gauge line is called in that vocabulary:
 *   단맛·산미·감칠맛   taste; liked high pronounced, low gentle; minded high
 *                     excessive, low too_weak; the middle step names no side
 *   바디              low light, high heavy; the middle step makes no reaction
 *   타닌              low smooth, high drying; the middle step makes no reaction
 *   탄산 · 스파이시     bubbles, warmth, with the taste's qualifiers
 *   피트              the 피트 aroma
 *   여운의 길이        liked high a long finish, liked low a clean one; minded
 *                     low too brief, minded high lingering
 *   끝맛의 인상        its own finish subject at every step
 * "None" of 탄산 and 피트 makes no reaction. The nose and the mouth are one
 * aroma there, and the finish aromas also make one answer of the finish (잔향
 * liked, what bothered minded).
 */
import { alcoholLevelFromAbv } from "./abv_levels.ts";
import {
  type AnsweredCardFacts,
  AROMA_KEYS,
  AROMA_STAGES,
  type AromaStage,
  LEVEL_DIMENSIONS,
  MOUTHFEEL_KEYS,
  type ProductFact,
  type Qualifier,
  type ReactionFact,
  type Subject,
  TASTE_KEYS,
} from "./facts.ts";
import type { BottleFacts } from "../prepare/bottle.ts";
import type { GaugeLine, Interpretation } from "../prepare/interpretation.ts";
import { prepareCard, type Prepared } from "../prepare/prepare.ts";
import type { SensoryRecord } from "../record/sensory_record.ts";

export type CardReading = Omit<AnsweredCardFacts, "schema_version">;

/** One record in the old vocabulary. Pure; the same record always gives the same. */
export function oldCardReading(record: SensoryRecord): CardReading {
  return fromPrepared(prepareCard(record));
}

function fromPrepared({ interpretation, bottle }: Prepared): CardReading {
  return {
    record: {
      product_name: bottle.name,
      category: bottle.category,
      style_key: bottle.region_entry ?? bottle.style_key,
      revisit: interpretation.revisit,
    },
    gauges: interpretation.gauges.map((
      { axis, level, reaction, answer_ref },
    ) => ({ axis, level, reaction, answer_ref })),
    reactions: reactionsOf(interpretation),
    product_facts: productFactsOf(bottle),
  };
}

const unique = (values: readonly string[]) => [...new Set(values)].sort();

type Drafted = Omit<ReactionFact, "id"> & { order: number };

/** How the old vocabulary calls the side a step names. */
function strengthSaid(line: GaugeLine): Qualifier | null {
  if (line.side !== "low" && line.side !== "high") return null;
  const strong = line.side === "high";
  return line.reaction === "liked"
    ? (strong ? "pronounced" : "gentle")
    : (strong ? "excessive" : "too_weak");
}

/** What one gauge line is in the old vocabulary, or null for a step it has no word for. */
function gaugeReaction(
  line: GaugeLine,
): Pick<Drafted, "subject" | "phase" | "qualifier" | "order"> | null {
  const { axis, side, reaction } = line;
  const taste = (key: typeof TASTE_KEYS[number]) => ({
    subject: { domain: "taste", key } as Subject,
    phase: "drinking" as const,
    qualifier: strengthSaid(line),
    order: 100 + TASTE_KEYS.indexOf(key),
  });
  const mouthfeel = (
    key: typeof MOUTHFEEL_KEYS[number],
    qualifier: Qualifier | null,
  ) => ({
    subject: { domain: "mouthfeel", key } as Subject,
    phase: "drinking" as const,
    qualifier,
    order: 200 + MOUTHFEEL_KEYS.indexOf(key),
  });
  const finish = (
    key: "persistence" | "clean" | "character",
    qualifier: Qualifier | null,
    order: number,
  ) => ({
    subject: { domain: "finish", key } as Subject,
    phase: "finish" as const,
    qualifier,
    order,
  });
  switch (axis) {
    case "sweetness":
      return taste("sweetness");
    case "acidity":
      return taste("acidity");
    case "umami":
      return taste("umami");
    case "body":
      return side === "middle"
        ? null
        : mouthfeel(side === "low" ? "light" : "heavy", null);
    case "tannin":
      return side === "middle"
        ? null
        : mouthfeel(side === "low" ? "smooth" : "drying", null);
    case "sparkling":
      return side === "none" ? null : mouthfeel("bubbles", strengthSaid(line));
    case "spice":
      return mouthfeel("warmth", strengthSaid(line));
    case "peat":
      // Read as the 피트 aroma; an aroma carries no strength.
      return side === "none" ? null : {
        subject: { domain: "aroma", key: "peat" },
        phase: "drinking",
        qualifier: null,
        order: 0,
      };
    case "finish_length":
      if (side === "middle") return null;
      if (reaction === "liked") {
        return side === "high"
          ? finish("persistence", null, 300)
          : finish("clean", null, 301);
      }
      return finish(
        "persistence",
        side === "high" ? "lingering" : "too_brief",
        300,
      );
    case "finish_character":
      return finish("character", null, 302);
  }
}

function reactionsOf(said: Interpretation): ReactionFact[] {
  const drafted: Drafted[] = [];
  for (const line of said.gauges) {
    const called = gaugeReaction(line);
    if (called) {
      drafted.push({
        kind: "reaction",
        ...called,
        reaction: line.reaction,
        answer_refs: [line.answer_ref],
      });
    }
  }
  for (const line of said.aromas) {
    const finish = line.stage === "finish";
    drafted.push({
      kind: "reaction",
      subject: { domain: "aroma", key: line.aroma },
      phase: finish ? "finish" : "drinking",
      reaction: line.reaction,
      qualifier: null,
      stages: [line.stage],
      answer_refs: [line.answer_ref],
      order: finish ? 310 : 0,
    });
  }
  // What stayed in the nose after swallowing, as one answer of the finish: the
  // liked finish aromas are the 잔향, the minded ones what bothered there.
  for (
    const [reaction, key, order] of [
      ["liked", "aroma_echo", 320],
      ["burden", "off_flavor", 321],
    ] as const
  ) {
    const stayed = said.aromas.filter((line) =>
      line.stage === "finish" && line.reaction === reaction
    );
    if (stayed.length) {
      drafted.push({
        kind: "reaction",
        subject: { domain: "finish", key },
        phase: "finish",
        reaction,
        qualifier: "lingering",
        answer_refs: unique(stayed.map((line) => line.answer_ref)),
        order,
      });
    }
  }
  // One aroma taken one way while drinking is one reaction, whichever of the
  // nose, the mouth and the 피트 gauge named it.
  const merged: Drafted[] = [];
  for (const draft of drafted) {
    const same = draft.subject.domain === "aroma"
      ? merged.find((other) =>
        other.subject.domain === "aroma" &&
        other.subject.key === draft.subject.key &&
        other.phase === draft.phase && other.reaction === draft.reaction
      )
      : undefined;
    if (!same) {
      merged.push({ ...draft });
      continue;
    }
    same.answer_refs = unique([...same.answer_refs, ...draft.answer_refs]);
    const stages = [...(same.stages ?? []), ...(draft.stages ?? [])];
    if (stages.length) {
      same.stages = AROMA_STAGES.filter((stage: AromaStage) =>
        stages.includes(stage)
      );
    }
  }
  merged.sort((a, b) =>
    a.order - b.order || a.subject.key.localeCompare(b.subject.key) ||
    // A liked answer precedes the minded one of the same sensation.
    b.reaction.localeCompare(a.reaction)
  );
  return merged.map(({ order: _order, ...fact }, i) => ({
    id: `r${i + 1}`,
    ...fact,
  }));
}

function productFactsOf(bottle: BottleFacts): ProductFact[] {
  const facts: { fact: ProductFact["fact"]; source: string }[] = [];
  // The old stages read the bottle's strength as a level against its kind's
  // usual one, from the ABV the catalog states.
  const fromAbv = alcoholLevelFromAbv(
    bottle.abv?.of === "bottle" ? bottle.abv.percent : null,
    bottle.style_key,
    bottle.category,
  );
  for (const dimension of LEVEL_DIMENSIONS) {
    if (dimension === "alcohol_presence" && fromAbv !== null) {
      facts.push({
        fact: { type: "level", dimension, level: fromAbv.level },
        source: `catalog:abv_band:${fromAbv.scope}`,
      });
      continue;
    }
    const read = bottle.levels[dimension];
    if (!read) continue;
    const { level, of, source } = read;
    facts.push({
      fact: of === "kind"
        ? { type: "level", dimension, level, estimated: true }
        : { type: "level", dimension, level },
      source: source === "kind_table"
        ? `catalog:style_table:${bottle.style_key}`
        : source === "catalog"
        ? "catalog:levels"
        : `catalog:levels:${source}`,
    });
  }
  const sectionOrder = ["aroma", "palate", "finish", "texture"] as const;
  for (const section of sectionOrder) {
    const tags = bottle.tags.filter((tag) => tag.section === section)
      .sort((a, b) => a.key.localeCompare(b.key));
    for (const tag of tags) {
      // A texture word among the palate or finish tags (smooth_texture,
      // firm_structure) is no flavour; it counts by its traits, as the texture
      // section does.
      if (section === "texture" || !AROMA_KEYS.has(tag.key)) {
        for (const trait of unique(tag.traits)) {
          facts.push({
            fact: { type: "trait", key: trait },
            source: "catalog:texture_text",
          });
        }
      } else {
        facts.push({
          fact: { type: "descriptor", key: tag.key, section },
          source: section === "aroma" ? "catalog:aromas" : `catalog:${section}`,
        });
      }
    }
  }
  if (bottle.abv?.of === "bottle") {
    facts.push({
      fact: { type: "abv", value: bottle.abv.percent },
      source: "catalog:abv",
    });
  }
  if (bottle.style_key) {
    facts.push({
      fact: { type: "style", key: bottle.style_key },
      source: "catalog:style",
    });
  }
  // Grape entries (까베르네 소비뇽) and a wine region entry (샴페인, 보르도
  // 좌안) refine the base style; they come after it so the narrower entry
  // wins where both speak.
  for (const key of bottle.grapes) {
    facts.push({ fact: { type: "style", key }, source: "catalog:grape" });
  }
  if (bottle.region_entry) {
    facts.push({
      fact: { type: "style", key: bottle.region_entry },
      source: "catalog:region",
    });
  }
  for (const key of bottle.ingredients) {
    facts.push({
      fact: { type: "ingredient", key },
      source: "catalog:ingredients",
    });
  }
  for (const key of bottle.processes) {
    facts.push({
      fact: { type: "production", key },
      source: "catalog:production",
    });
  }
  const seen = new Set<string>();
  return facts.filter(({ fact }) => {
    const signature = JSON.stringify(fact);
    if (seen.has(signature)) return false;
    seen.add(signature);
    return true;
  }).map((entry, i) => ({ id: `p${i + 1}`, kind: "product", ...entry }));
}
