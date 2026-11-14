import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  FELT_SWEETNESS_CEILING,
  feltSweetness,
} from "../../_shared/taste_card/facts/felt_sweetness.ts";
import {
  familiesOfBottle,
  grapeLeans,
  kindGroup,
  placeOfAbv,
  placeOfLevel,
  placeOfSweetness,
} from "../../_shared/taste_card/facts/kind_place.ts";

const red = (
  levels: Record<string, number>,
  aromas: string[] = [],
  style = "red_wine",
) => ({ style_key: style, category_key: "wine", levels, aroma_tags: aromas });

Deno.test("place: the same number stands in a different place in each kind", () => {
  const at = (style: string, category: string) =>
    placeOfLevel("sweetness", style, category, 4)!;
  // Sweetness 4 is the middle of port, the top of red wine, high for a single malt.
  const port = at("port_wine", "wine");
  const redWine = at("red_wine", "wine");
  const malt = at("single_malt_whisky", "whisky");
  assertEquals(port.scope, "port_wine");
  assert(port.position > 0.25 && port.position < 0.6, `${port.position}`);
  assert(redWine.position > 0.95, `${redWine.position}`);
  assert(malt.position > 0.6 && malt.position < 0.9, `${malt.position}`);
  // How common the value is: nearly half of ports, under one red in a hundred.
  assert(port.share > 0.4 && redWine.share < 0.02);
  // Nine of ten reds sit on sweetness 1, so that value says little.
  assert(placeOfLevel("sweetness", "red_wine", "wine", 1)!.share > 0.9);
});

Deno.test("place: a small kind borrows its pool, a regional style reads as its kind", () => {
  assertEquals(
    placeOfLevel("body", "sherry_wine", "wine", 3)!.scope,
    "wine_fortified_other",
  );
  assertEquals(
    placeOfLevel("body", "tennessee_whisky", "whisky", 3)!.scope,
    "whisky_american",
  );
  assertEquals(
    placeOfLevel("body", "barolo_red", "wine", 4),
    placeOfLevel("body", "red_wine", "wine", 4),
  );
  // Whiskies carry no astringency level: nothing to place, so nothing to judge by.
  assertEquals(
    placeOfLevel("astringency", "single_malt_whisky", "whisky", 2),
    null,
  );
  // A strength is placed among the whole whisky shelf, the same for a malt and a blend.
  assertEquals(
    placeOfAbv("single_malt_whisky", "whisky", 40)!.position,
    placeOfAbv("blended_whisky", "whisky", 40)!.position,
  );
});

Deno.test("place: the groups a record carries over between", () => {
  assertEquals(kindGroup("red_wine", "wine")?.key, "wine");
  assertEquals(kindGroup("rioja_red", "wine")?.key, "wine");
  assertEquals(kindGroup("white_wine", "wine")?.key, "wine");
  assertEquals(kindGroup("sparkling_wine", "wine")?.key, "sparkling_wine");
  assertEquals(kindGroup("port_wine", "wine")?.key, "fortified_wine");
  assertEquals(kindGroup("bourbon", "whisky")?.key, "whisky");
  assertEquals(kindGroup("takju", "korean_traditional")?.key, "takju");
  assertEquals(kindGroup("yakju", "korean_traditional")?.key, "yakju");
  assertEquals(kindGroup(null, null), null);
});

Deno.test("felt sweetness: orders wines that share a stored value and never passes the next step", () => {
  const plain = feltSweetness(
    red({ sweetness: 1, acidity: 3, astringency: 3, body: 3 }),
  )!;
  const jammy = feltSweetness(
    red(
      { sweetness: 1, acidity: 2, astringency: 2, body: 4 },
      ["dried_fruit", "vanilla"],
    ),
  )!;
  const grippy = feltSweetness(
    red({ sweetness: 1, acidity: 4, astringency: 5, body: 4 }, ["cherry"]),
  )!;
  assert(grippy < plain && plain < jammy, `${grippy} ${plain} ${jammy}`);
  assert(jammy <= 1 + FELT_SWEETNESS_CEILING);
  assert(grippy >= 1);
  // The jammiest dry red still stands below any red stored a step sweeter.
  const offDry = feltSweetness(
    red({ sweetness: 2, acidity: 5, astringency: 5, body: 2 }),
  )!;
  assert(jammy < offDry);
  // Tannin takes no part in a white; a trait without a value adds nothing.
  assertEquals(
    feltSweetness(
      red({ sweetness: 1, acidity: 3, astringency: 5 }, [], "white_wine"),
    ),
    feltSweetness(red({ sweetness: 1, acidity: 3 }, [], "white_wine")),
  );
  // Sparkling, fortified and every other drink keep their stored number.
  for (const style of ["sparkling_wine", "port_wine", "takju"]) {
    assertEquals(feltSweetness(red({ sweetness: 1 }, [], style)), null);
  }
  // Among reds the jammy one stands above the grippy one, though both are stored as 1.
  const place = (levels: Record<string, number>, aromas: string[]) =>
    placeOfSweetness(red(levels, aromas))!.position;
  assert(
    place({ sweetness: 1, acidity: 2, astringency: 2, body: 4 }, ["vanilla"]) >
      place({ sweetness: 1, acidity: 4, astringency: 5, body: 4 }, []) + 0.3,
  );
});

Deno.test("aroma families: the making counts where it is certain, and grapes lean by share not count", () => {
  // Peated malt smells of smoke whether or not a note says so.
  assert(familiesOfBottle(["chocolate"], ["peated_malt"]).has("effect_smoke"));
  assert(!familiesOfBottle(["chocolate"], []).has("effect_smoke"));
  const leans = new Map(grapeLeans("red_wine").map((g) => [g.grape, g]));
  const sweeter = (grape: string) => leans.get(grape)!.sweeter;
  // Cabernet has the most bottles, yet a smaller part of them feels sweet than Primitivo's.
  assert(
    leans.get("cabernet_sauvignon")!.bottles > leans.get("primitivo")!.bottles,
  );
  assert(sweeter("primitivo") > sweeter("cabernet_sauvignon"));
  assert(sweeter("zinfandel") > sweeter("pinot_noir"));
  assert(leans.get("nebbiolo")!.drier > leans.get("nebbiolo")!.sweeter);
  assertEquals(grapeLeans("takju"), []);
});
