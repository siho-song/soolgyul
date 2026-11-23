/**
 * Rebuilds catalog/dictionary/kind_spreads.json, the copy of the catalog's
 * counts a function starts with before it reads the night's count from the
 * database. The counting itself is
 * supabase/functions/_shared/record_reading/facts/kind_spreads_build.ts, which
 * also says what a bottle of the input is.
 *
 *   deno run --allow-read --allow-write tools/catalog/build_kind_spreads.ts <bottles.json> <YYYY-MM-DD>
 */
import {
  buildKindSpreads,
  type CountedBottle,
} from "../../supabase/functions/_shared/record_reading/facts/kind_spreads_build.ts";

const [input, readOn] = Deno.args;
if (!input || !readOn) {
  console.error("usage: build_kind_spreads.ts <bottles.json> <YYYY-MM-DD>");
  Deno.exit(1);
}
const bottles = JSON.parse(await Deno.readTextFile(input)) as CountedBottle[];
const out = buildKindSpreads(bottles, readOn);
const lines = Object.entries(out.kinds).map(([key, value]) =>
  `    ${JSON.stringify(key)}: ${JSON.stringify(value)}`
);
await Deno.writeTextFile(
  new URL("../../catalog/dictionary/kind_spreads.json", import.meta.url),
  `{\n  "read_on": ${
    JSON.stringify(readOn)
  },\n  "bottles": ${out.bottles},\n  "kinds": {\n${
    lines.join(",\n")
  }\n  }\n}\n`,
);
console.log(
  `${Object.keys(out.kinds).length} kinds from ${out.bottles} bottles`,
);
