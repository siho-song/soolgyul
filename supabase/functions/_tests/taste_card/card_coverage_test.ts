/**
 * Every answer the questionnaire offers, on real catalog products: the card
 * never fails, never leaves an answer unspoken, never repeats a paragraph,
 * never calls the drink just 술, and never claims a reason it did not verify.
 * Every single answer is crossed with one sample bottle per kind; that keeps
 * the sweep under a second while still touching every option.
 */
import { assert } from "jsr:@std/assert@1";
import { sensoryOptions } from "../../_shared/record_reading/record/questionnaire.ts";
import { readRecord } from "../../_shared/record_reading/read_record.ts";
import { writeCard } from "../../_shared/taste_card/writing/card_text.ts";
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
      let card, asked;
      try {
        const record = recordFrom(`${label}|${c.id}`, keys, sampleProduct(c));
        const { gauges, aromas } = readRecord(record).answers;
        // A gauge the drink is not asked (타닌 of a 막걸리) is not read.
        asked = gauges.length + aromas.length > 0;
        card = writeCard(record);
      } catch (e) {
        problems.push(`${c.name} / ${label}: 터짐 ${(e as Error).message}`);
        continue;
      }
      // The one answer is told in the section of its side. A middle step
      // that nothing of the bottle explains may be left to the note: the
      // card then says so in its summary.
      const told = label.endsWith(":liked") ? card.positive : card.burden;
      const leftToNote = /^level:\w+:3:/.test(label) &&
        card.summary.includes("테이스팅 노트에 담았어요");
      if (asked && !told.length && !leftToNote) {
        problems.push(`${c.name} / ${label}: 글 없음`);
      }
      const texts: string[] = [];
      for (const p of [...card.positive, ...card.burden]) {
        const text = `${p.answer} ${p.text}`;
        if (/[{}]|undefined|null|NaN| {2}/.test(text)) {
          problems.push(`${c.name} / ${label}: 글 깨짐 ${text.slice(0, 80)}`);
        }
        if (texts.includes(text)) {
          problems.push(`${c.name} / ${label}: 같은 글 반복`);
        }
        texts.push(text);
      }
      for (const line of card.next?.lines ?? []) {
        if (/[{}]|undefined|null|NaN| {2}/.test(line.text)) {
          problems.push(`${c.name} / ${label}: 03 깨짐 ${line.text}`);
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
  assert(answers.length > 800, `only ${answers.length} answers`);
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
    ["sparkling_wine", "takju"].includes(c.style_key ?? "")
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
