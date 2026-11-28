// The gauge axes and the catalog's name for each, as the gauge sheet
// (catalog/sensory/gauge-definitions.json) gives them. The app and the tools
// pin the same pairs, so the three readers cannot drift.
import {
  catalogAxis,
  GAUGE_AXES,
  GAUGE_LEVEL_DIMENSION,
  gaugeOf,
} from "../../_shared/record_reading/facts/facts.ts";
import { GAUGE_SCALE } from "../../_shared/record_reading/answers.ts";
import { same as equal } from "../helpers/assert.ts";

const PAIRS = [
  ["sweetness", "sweetness"],
  ["acidity", "acidity"],
  ["umami", "umami"],
  ["body", "body"],
  ["tannin", "astringency"],
  ["sparkling", "carbonation"],
  ["spice", "spice"],
  ["peat", "peat"],
  ["finish_length", "finish_length"],
  ["finish_character", "finish_character"],
];

Deno.test("gauge axes: each axis, in the order a record keeps them, and the catalog's name for it", () => {
  equal(GAUGE_AXES.map((axis) => [axis, catalogAxis(axis)]), PAIRS);
  equal(GAUGE_AXES.map((axis) => gaugeOf(catalogAxis(axis))), GAUGE_AXES);
  // A name no gauge is drawn from stays as it is.
  equal(gaugeOf("bitterness"), "bitterness");
});

Deno.test("gauge axes: the sheet lists every axis the compiler knows, and no other", () => {
  equal([...GAUGE_AXES].sort(), Object.keys(GAUGE_SCALE).sort());
});

Deno.test("gauge axes: the catalog levels a gauge is compared with", () => {
  equal(GAUGE_LEVEL_DIMENSION, {
    sweetness: "sweetness",
    acidity: "acidity",
    umami: null,
    body: "body",
    tannin: "astringency",
    sparkling: "carbonation",
    spice: null,
    peat: null,
    finish_length: "finish_length",
    finish_character: null,
  });
});
