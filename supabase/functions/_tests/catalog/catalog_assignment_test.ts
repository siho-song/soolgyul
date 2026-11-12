import {
  CatalogAssignment,
  catalogAssignments,
  CatalogCategoryKey,
} from "../../_shared/catalog/assignment.ts";
import { same as equal } from "../helpers/assert.ts";
import cases from "../../../../tests/fixtures/catalog_assignment_cases.json" with {
  type: "json",
};

for (const row of cases) {
  Deno.test(`assignment parity: ${row.name}`, () => {
    const result = catalogAssignments.validate(row.input);
    equal([...new Set(result.issues.map((i) => i.code))].sort(), row.codes);
    equal(result.value !== null, row.codes.length === 0);
  });
}
Deno.test("assignment value is runtime immutable and requires validation", () => {
  const result = catalogAssignments.validate({ category_key: "wine" });
  if (
    !result.value || !Object.isFrozen(result.value) ||
    !Object.isFrozen(result.value.values.ingredient_keys)
  ) throw new Error("mutable assignment");
  let rejected = false;
  try {
    new CatalogAssignment(
      Symbol(),
      CatalogCategoryKey.Wine,
      null,
      "product" as never,
      {} as never,
    );
  } catch {
    rejected = true;
  }
  equal(rejected, true);
});
