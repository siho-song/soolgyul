import { assert } from "jsr:@std/assert@1";
import { buildCardFacts } from "../_shared/taste_card/card_conclusions.ts";
import { writeSection } from "../_shared/taste_card/card_writing.ts";
import type { SensoryProduct } from "../_shared/taste_card/sensory_record.ts";
import {
  fixtureProduct,
  fixtures,
  recordFrom,
} from "./helpers/card_fixture_record.ts";

Deno.test("card provenance: a level copied from the kind's table is marked, spoken of the kind, and never the 경험형 cause", async () => {
  const [[, bp01]] = await fixtures();
  const answers = [
    "reaction:taste:acidity:liked",
    "reason:taste:acidity:liked:pronounced",
  ];
  const base: SensoryProduct = {
    ...fixtureProduct(bp01),
    levels: { sweetness: 1, acidity: 4 },
  };

  const read = buildCardFacts(
    recordFrom("read", answers, {
      ...base,
      levelSources: { sweetness: 2, acidity: 2 },
    }),
  );
  // The two read numbers are facts of this bottle; alcohol presence is read
  // from the ABV; the dimensions nobody read come from the kind's table and
  // are marked as the kind's.
  const readDims = ["sweetness", "acidity"];
  assert(
    read.product_facts.every((p) =>
      p.fact.type !== "level" ||
      (readDims.includes(p.fact.dimension)
        ? !p.fact.estimated
        : p.fact.dimension === "alcohol_presence"
        ? !p.fact.estimated && p.source.startsWith("catalog:abv_band:")
        : p.fact.estimated && p.source.startsWith("catalog:style_table:"))
    ),
  );
  const readText = writeSection(read, "positive").paragraphs[0];
  assert(readText.prose === "exposure_acidity_by_sweetness");
  const readBody = readText.body;
  assert(readBody.startsWith("이 와인은 "), readBody);

  const copied = buildCardFacts(
    recordFrom("copied", answers, {
      ...base,
      levelSources: { sweetness: 4, acidity: 4 },
    }),
  );
  const levels = copied.product_facts.filter((p) =>
    p.fact.type === "level" && readDims.includes(p.fact.dimension)
  );
  assert(
    levels.length === 2 &&
      levels.every((p) => p.fact.type === "level" && p.fact.estimated),
  );
  assert(levels.every((p) => p.source.startsWith("catalog:levels:")));
  const copiedText = writeSection(copied, "positive").paragraphs[0];
  assert(copiedText.prose === "exposure_acidity_by_sweetness");
  const fact = copiedText.body;
  assert(fact.startsWith("이런 와인은 보통 "), fact);
  assert(!fact.includes(bp01.record.product_name), fact);
});

Deno.test("card provenance: between two explanations of one answer, the one standing on a read number wins", async () => {
  const [[, bp01]] = await fixtures();
  const answers = ["reaction:taste:acidity:liked"];
  // Acidity read for the bottle, sweetness copied from the table: the strength
  // explanation (acidity) outranks the exposure explanation (sweetness low).
  const product: SensoryProduct = {
    ...fixtureProduct(bp01),
    levels: { sweetness: 1, acidity: 4 },
    levelSources: { sweetness: 4, acidity: 2 },
  };
  const facts = buildCardFacts(recordFrom("mixed", answers, product));
  const chosen = facts.findings.find((d) =>
    d.id === facts.sections.positive[0]
  )!;
  assert(chosen.row === "intensity_acidity", chosen.row);
});
