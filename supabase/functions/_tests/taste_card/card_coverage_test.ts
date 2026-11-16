/**
 * Every answer the questionnaire offers, on real catalog products: the card
 * never fails, never leaves an answer unspoken, never repeats a paragraph,
 * never calls the drink just 술, and never claims a reason it did not verify.
 * Every single answer is crossed with one sample bottle per kind; that keeps
 * the sweep under a second while still touching every option.
 */
import { assert } from "jsr:@std/assert@1";
import { buildCardFacts } from "../../_shared/taste_card/findings/conclusions.ts";
import { sensoryOptions } from "../../_shared/taste_card/record/questionnaire.ts";
import { writeSection } from "../../_shared/taste_card/writing/sections.ts";
import {
  type CatalogSample,
  catalogSamples,
  recordFrom,
  sampleProduct,
} from "../helpers/card_fixture_record.ts";

/**
 * Every single answer a reader can give: each aroma in each picker and each
 * step of each gauge, liked or 아쉬웠어요.
 */
function singleAnswers(): { label: string; keys: string[] }[] {
  return sensoryOptions().flatMap((option) =>
    option.kind === "aroma" || option.kind === "level"
      ? [{
        label: option.option_key,
        keys: [
          option.option_key,
          option.reaction === "liked"
            ? "revisit:wantAgain"
            : "revisit:doNotWantAgain",
        ],
      }]
      : []
  );
}

/**
 * The middle step of 단맛, 산미 or 산미·감칠맛 marked 아쉬웠어요 names no
 * side, so its strength explains nothing: the card's summary says it and no
 * paragraph is written (writing/sections.ts).
 */
const MIDDLE_STEP_MINDED = new Set([
  "level:sweetness:3:disliked",
  "level:acidity:3:disliked",
  "level:umami_acidity:3:disliked",
]);
/** 탄산감 or 스파이시 at its faint step, marked 아쉬웠어요: more of it was wanted. */
const FAINT_FEEL_MINDED = new Set([
  "level:sparkling:2:disliked",
  "level:spice:2:disliked",
]);

/** Everything wrong with the cards of these answers on these bottles. */
function sweep(
  sample: readonly CatalogSample[],
  answers: readonly { label: string; keys: string[] }[],
): string[] {
  const problems: string[] = [];
  for (const c of sample) {
    for (const { label, keys } of answers) {
      let facts;
      try {
        facts = buildCardFacts(
          recordFrom(`${label}|${c.id}`, keys, sampleProduct(c)),
        );
      } catch (e) {
        problems.push(`${c.name} / ${label}: 터짐 ${(e as Error).message}`);
        continue;
      }
      for (const r of facts.reactions) {
        if (!facts.findings.some((d) => d.reactions.includes(r.id))) {
          problems.push(`${c.name} / ${label}: 설명 없음`);
        }
      }
      const texts: string[] = [];
      for (const section of ["positive", "burden"] as const) {
        const w = writeSection(facts, section);
        for (const s of w.skipped) {
          const row = facts.findings.find((d) => d.id === s.finding)?.row ?? "";
          if (
            MIDDLE_STEP_MINDED.has(label) && section === "burden" &&
            row.startsWith("intensity_")
          ) continue;
          problems.push(`${c.name} / ${label}: 글 없음 ${s.reason}`);
        }
        for (const p of w.paragraphs) {
          const text = `${p.name} ${p.body}`;
          if (/[{}]|undefined|null|NaN| {2}/.test(text)) {
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
  return problems;
}

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
  assert(answers.length > 1000, `only ${answers.length} answers`);
  const problems = sweep(
    sample,
    answers.filter(({ label }) => !FAINT_FEEL_MINDED.has(label)),
  );
  assert(
    problems.length === 0,
    `${problems.length} problems, first:\n${problems.slice(0, 12).join("\n")}`,
  );
});

Deno.test("card coverage: 탄산감 or 스파이시 found too faint gets its paragraph on every bottle that is asked it", async () => {
  const asked = (await catalogSamples()).filter((c) =>
    c.category === "whisky" ||
    ["sparkling_wine", "takju", "yakju"].includes(c.style_key ?? "")
  );
  assert(asked.length > 10, `only ${asked.length} bottles`);
  const problems = sweep(
    asked,
    singleAnswers().filter(({ label }) => FAINT_FEEL_MINDED.has(label)),
  );
  assert(
    problems.length === 0,
    `${problems.length} problems, first:\n${problems.slice(0, 12).join("\n")}`,
  );
});
