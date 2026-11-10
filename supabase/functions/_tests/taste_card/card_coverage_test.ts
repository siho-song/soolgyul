/**
 * Every answer the questionnaire offers, on real catalog products: the card
 * never fails, never leaves an answer unspoken, never repeats a paragraph,
 * never calls the drink just 술, and never claims a reason it did not verify.
 * Every single answer is crossed with one sample bottle per kind; that keeps
 * the sweep under a second while still touching every option.
 */
import { assert } from "jsr:@std/assert@1";
import { sensoryCatalog as catalog } from "../../_shared/taste_card/dictionary/dictionary.ts";
import { serviceVocabulary as vocabulary } from "../../_shared/taste_card/dictionary/dictionary.ts";
import { buildCardFacts } from "../../_shared/taste_card/findings/conclusions.ts";
import { writeSection } from "../../_shared/taste_card/writing/sections.ts";
import type {
  SensoryProduct,
  SensoryProductDescriptor,
} from "../../_shared/taste_card/record/sensory_record.ts";
import {
  type CatalogSample,
  catalogSamples,
  recordFrom,
} from "../helpers/card_fixture_record.ts";

const alias = new Map<string, string>();
for (
  const g of (vocabulary as {
    groups: { key: string; domain: string; source_keys: string[] }[];
  }).groups
) {
  if (g.domain !== "descriptor") continue;
  for (const k of [g.key, ...g.source_keys]) alias.set(k, g.key);
}

/** A candidate of the test pool as the product being recorded. */
function product(c: CatalogSample): SensoryProduct {
  const descriptors: SensoryProductDescriptor[] = [];
  for (const raw of c.aromas) {
    const key = alias.get(raw);
    if (!key || descriptors.some((d) => d.key === key)) continue;
    descriptors.push({
      key,
      label: key,
      section: "aroma",
      family: "test",
      traits: [],
      description: null,
      evidenceRefs: ["test"],
    });
  }
  return {
    name: c.name,
    category: c.category as SensoryProduct["category"],
    styleKey: c.style_key,
    region: null,
    abv: c.abv,
    ingredients: [...c.ingredients],
    processes: [...c.processes],
    grapeVarietyKeys: [],
    levels: c.levels,
    levelRefs: {},
    descriptors,
  };
}

const LIKED = ["gentle", "pronounced", "harmony", "unspecified"];
const DISLIKED = [
  "too_strong",
  "too_weak",
  "disharmony",
  "unspecified",
];
const TASTE = ["sweetness", "acidity", "bitterness"];
const MOUTH = ["light", "heavy", "smooth", "drying", "bubbles", "warmth"];
const FINISH = [
  "pleasantLength",
  "clean",
  "tooShort",
  "heavy",
  "aromaEcho",
  "offFlavor",
];
const rest = (answered: string) =>
  ["aroma", "taste", "mouthfeel", "finish"].filter((s) => s !== answered)
    .map((s) =>
      s === "taste" ? "reaction:taste:sweetness:fine" : `${s}:unsure`
    );

/** Every single answer a reader can give, as the questionnaire accepts it. */
function singleAnswers(): { label: string; keys: string[] }[] {
  const selectable = (catalog as {
    descriptors: { key: string; onboarding_selectable?: boolean }[];
  }).descriptors.filter((d) => d.onboarding_selectable).map((d) => d.key);
  const out: { label: string; keys: string[] }[] = [];
  for (const a of selectable) {
    for (const r of LIKED) {
      out.push({
        label: `aroma ${a} liked ${r}`,
        keys: [
          `notice:aroma:${a}`,
          `reaction:aroma:${a}:liked`,
          `reason:aroma:${a}:liked:${r}`,
          ...rest("aroma"),
          "revisit:wantAgain",
        ],
      });
    }
    for (const r of DISLIKED) {
      out.push({
        label: `aroma ${a} disliked ${r}`,
        keys: [
          `notice:aroma:${a}`,
          `reaction:aroma:${a}:disliked`,
          `reason:aroma:${a}:disliked:${r}`,
          ...rest("aroma"),
          "revisit:doNotWantAgain",
        ],
      });
    }
  }
  for (const t of TASTE) {
    for (
      const [side, reasons] of [["liked", LIKED], [
        "disliked",
        DISLIKED,
      ]] as const
    ) {
      for (const r of reasons) {
        out.push({
          label: `taste ${t} ${side} ${r}`,
          keys: [
            `reaction:taste:${t}:${side}`,
            `reason:taste:${t}:${side}:${r}`,
            ...rest("taste"),
            "revisit:unsure",
          ],
        });
      }
    }
  }
  for (const m of MOUTH) {
    for (const side of ["liked", "disliked"]) {
      out.push({
        label: `mouthfeel ${m} ${side}`,
        keys: [
          `notice:mouthfeel:${m}`,
          `reaction:mouthfeel:${m}:${side}`,
          ...rest("mouthfeel"),
          "revisit:unsure",
        ],
      });
    }
  }
  for (const f of FINISH) {
    out.push({
      label: `finish ${f}`,
      keys: [`finish:${f}`, ...rest("finish"), "revisit:unsure"],
    });
  }
  return out;
}

/** The only answer that may stay unexplained: a lingering 텁텁함 with no drinking answer. */
const UNEXPLAINED_BY_DESIGN = new Set(["finish heavy"]);

Deno.test("card coverage: every single answer gets a paragraph on every kind of product, and the card never fails", async () => {
  const pool = await catalogSamples();
  // Two products per category of the test pool: the first and the last by id.
  const sample: CatalogSample[] = [];
  for (const category of new Set(pool.map((c) => c.category))) {
    const ofKind = pool.filter((c) => c.category === category)
      .sort((a, b) => a.id.localeCompare(b.id));
    sample.push(ofKind[0], ofKind[ofKind.length - 1]);
  }
  const answers = singleAnswers();
  // 2026-11-05: the character reason left, so each aroma and taste lost two.
  assert(answers.length > 1000, `only ${answers.length} answers`);
  const problems: string[] = [];
  for (const c of sample) {
    for (const { label, keys } of answers) {
      let facts;
      try {
        facts = buildCardFacts(
          recordFrom(`${label}|${c.id}`, keys, product(c)),
        );
      } catch (e) {
        problems.push(`${c.name} / ${label}: 터짐 ${(e as Error).message}`);
        continue;
      }
      // 적당했어요 is kept as it is and explains nothing by design.
      const reacted = facts.reactions.filter((r) =>
        r.reaction !== "unstated" && r.reaction !== "fine"
      );
      for (const r of reacted) {
        if (UNEXPLAINED_BY_DESIGN.has(label)) continue;
        if (!facts.findings.some((d) => d.reactions.includes(r.id))) {
          problems.push(`${c.name} / ${label}: 설명 없음`);
        }
      }
      const texts: string[] = [];
      for (const section of ["positive", "burden"] as const) {
        const w = writeSection(facts, section);
        for (const s of w.skipped) {
          problems.push(`${c.name} / ${label}: 글 없음 ${s.reason}`);
        }
        for (const p of w.paragraphs) {
          const text = `${p.name} ${p.body}`;
          if (/[{}]|undefined|null|NaN|  /.test(text)) {
            problems.push(`${c.name} / ${label}: 글 깨짐 ${text.slice(0, 80)}`);
          }
          if (/(?<!중국 )술이에요\.|(?<!중국 )술보다는/.test(text)) {
            problems.push(
              `${c.name} / ${label}: 종류 이름 없음 ${text.slice(0, 80)}`,
            );
          }
          if (texts.includes(text)) {
            problems.push(`${c.name} / ${label}: 같은 글 반복`);
          }
          texts.push(text);
        }
      }
    }
  }
  assert(
    problems.length === 0,
    `${problems.length} problems, first:\n${problems.slice(0, 12).join("\n")}`,
  );
});
