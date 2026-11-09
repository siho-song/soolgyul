import { assertEquals } from "jsr:@std/assert@1";
import { abvBands } from "../_shared/taste_card/dictionary.ts";
import {
  abvBandsFor,
  alcoholLevelFromAbv,
} from "../_shared/taste_card/abv_levels.ts";

Deno.test("abv levels: five bands per kind, from the kind's legal minimum and trade conventions", () => {
  // Whisky: under the 40% minimum, 40–43 standard, 43–47 premium strength, 47–50 high, cask strength from 50.
  assertEquals(
    [38, 40, 43, 46, 48, 50, 60].map((abv) =>
      alcoholLevelFromAbv(abv, "single_malt_whisky", "whisky")?.level
    ),
    [1, 2, 3, 3, 4, 5, 5],
  );
  // Wine: 9% ice wine, 11% light white, 13% table wine, 14.5% ripe red, 15.5% high.
  assertEquals(
    [9, 11, 13, 14.5, 15.5].map((abv) =>
      alcoholLevelFromAbv(abv, "red_wine", "wine")?.level
    ),
    [1, 2, 3, 4, 5],
  );
  // Sake: 15–16 standard, genshu from 17.
  assertEquals(
    [8, 13, 15.5, 17, 19].map((abv) =>
      alcoholLevelFromAbv(abv, "junmai", "sake")?.level
    ),
    [1, 2, 3, 4, 5],
  );
  // Takju: 6도 ordinary, 12도 premium, 17도 very high.
  assertEquals(
    [4, 5.5, 6, 9, 17].map((abv) =>
      alcoholLevelFromAbv(abv, "takju", "korean_traditional")?.level
    ),
    [1, 2, 3, 4, 5],
  );
});

Deno.test("abv levels: a style the table lacks falls back to its category, and no ABV gives no level", () => {
  assertEquals(abvBandsFor("some_new_style", "whisky")?.scope, "whisky");
  assertEquals(
    alcoholLevelFromAbv(48, "blended_whisky", "whisky")?.scope,
    "whisky",
  );
  assertEquals(alcoholLevelFromAbv(null, "red_wine", "wine"), null);
  assertEquals(alcoholLevelFromAbv(40, null, null), null);
});

Deno.test("abv bands: every row has four ascending edges and names its source", () => {
  const rows = [
    ...Object.entries(abvBands.categories),
    ...Object.entries(abvBands.styles),
  ];
  for (const [key, row] of rows) {
    assertEquals(row.bounds.length, 4, key);
    assertEquals([...row.bounds].sort((a, b) => a - b), row.bounds, key);
    assertEquals(typeof row.verified, "boolean", key);
    assertEquals(row.source.length > 0, true, key);
  }
});
