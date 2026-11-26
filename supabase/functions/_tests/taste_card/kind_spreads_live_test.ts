import { assert, assertEquals } from "jsr:@std/assert@1";
import shipped from "../../../../catalog/dictionary/kind_spreads.json" with {
  type: "json",
};
import {
  bottlesCarrying,
  useKindSpreads,
} from "../../_shared/record_reading/facts/kind_place.ts";
import {
  buildKindSpreads,
  type CountedBottle,
} from "../../_shared/record_reading/facts/kind_spreads_build.ts";
import {
  forgetCatalogKindSpreads,
  useCatalogKindSpreads,
} from "../../_shared/record_reading/facts/kind_spreads_live.ts";

/** The shipped count with one more red wine place on its shelf. */
function newer(place: string, bottles: number) {
  const count = structuredClone(shipped) as unknown as {
    bottles: number;
    kinds: Record<string, { carried: { styles: Record<string, number> } }>;
  };
  count.kinds.red_wine.carried.styles[place] = bottles;
  return count;
}

const onShelf = (place: string) =>
  bottlesCarrying("styles", place, "red_wine")!.bottles;

const env = (name: string) =>
  ({ SUPABASE_URL: "https://db.test", SUPABASE_SERVICE_ROLE_KEY: "key" })[name];

/** A database that answers the row read with [body], and counts the reads. */
function database(body: () => unknown, status = 200) {
  const seen = { reads: 0 };
  const fetcher = ((input: string | URL | Request) => {
    seen.reads++;
    assert(String(input).includes("/rest/v1/catalog_kind_spreads?"));
    return Promise.resolve(
      new Response(JSON.stringify(body()), { status }),
    );
  }) as typeof fetch;
  return { seen, fetcher };
}

Deno.test("kind spreads: a newer count is used in place of the shipped one, and null goes back", () => {
  assertEquals(onShelf("zz_new_place_red"), 0);
  assert(useKindSpreads(newer("zz_new_place_red", 321)));
  assertEquals(onShelf("zz_new_place_red"), 321);
  assert(useKindSpreads(null));
  assertEquals(onShelf("zz_new_place_red"), 0);
});

Deno.test("kind spreads: a count that is not one is left aside", () => {
  const broken = newer("zz_new_place_red", 321) as unknown as {
    bottles: number;
    kinds: Record<string, Record<string, unknown>>;
  };
  for (
    const count of [
      undefined,
      "text",
      {},
      { bottles: shipped.bottles, kinds: {} },
      // Fewer than half the shipped bottles: a read that went wrong.
      { ...broken, bottles: Math.floor(shipped.bottles / 3) },
      { ...broken, kinds: { red_wine: { bottles: 10 } } },
      {
        ...broken,
        kinds: {
          red_wine: { ...broken.kinds.red_wine, levels: { body: [1, 2] } },
        },
      },
    ]
  ) {
    assertEquals(
      useKindSpreads(count),
      false,
      JSON.stringify(count)?.slice(0, 80),
    );
  }
  assertEquals(onShelf("zz_new_place_red"), 0);
});

Deno.test("kind spreads: a function reads the night's count once an hour", async () => {
  forgetCatalogKindSpreads();
  let clock = 1_000_000;
  let place = 100;
  const { seen, fetcher } = database(
    () => [{ spreads: newer("zz_new_place_red", place) }],
  );
  const look = () => useCatalogKindSpreads(env, fetcher, () => clock);
  // Two requests that arrive together wait on one read.
  await Promise.all([look(), look()]);
  assertEquals(seen.reads, 1);
  assertEquals(onShelf("zz_new_place_red"), 100);
  place = 200;
  clock += 59 * 60 * 1000;
  await look();
  assertEquals(seen.reads, 1);
  clock += 2 * 60 * 1000;
  await look();
  assertEquals(seen.reads, 2);
  assertEquals(onShelf("zz_new_place_red"), 200);
  forgetCatalogKindSpreads();
});

Deno.test("kind spreads: a read that fails keeps the count in use and is tried again in a few minutes", async () => {
  forgetCatalogKindSpreads();
  let clock = 1_000_000;
  for (
    const failing of [
      database(() => ({ message: "relation does not exist" }), 404),
      database(() => []),
      database(() => [{ spreads: { bottles: 1, kinds: {} } }]),
      {
        seen: { reads: 0 },
        fetcher: (() => Promise.reject(new Error("down"))) as typeof fetch,
      },
    ]
  ) {
    forgetCatalogKindSpreads();
    assert(useKindSpreads(newer("zz_new_place_red", 55)));
    const look = () => useCatalogKindSpreads(env, failing.fetcher, () => clock);
    await look();
    assertEquals(onShelf("zz_new_place_red"), 55);
    clock += 4 * 60 * 1000;
    await look();
    clock += 2 * 60 * 1000;
    await look();
    if (failing.seen.reads) assertEquals(failing.seen.reads, 2);
  }
  // Without the project's address and key nothing is read.
  forgetCatalogKindSpreads();
  const none = database(() => []);
  await useCatalogKindSpreads(() => undefined, none.fetcher, () => clock);
  assertEquals(none.seen.reads, 0);
  forgetCatalogKindSpreads();
});

Deno.test("kind spreads: the count is of the bottles as the engine reads them, and the engine takes it", () => {
  const bottle = (
    i: number,
    more: Partial<CountedBottle> = {},
  ): CountedBottle => ({
    style_key: "red_wine",
    category_key: "wine",
    name_ko: `시험 ${i}`,
    abv_percent: "13.5",
    region_key: "fr_bourgogne",
    grapes: ["pinot_noir"],
    processes: [],
    ingredients: [],
    sweetness: "1",
    acidity: String(3 + i % 2),
    body: 3,
    aroma_tags: ["cherry"],
    ...more,
  });
  const bottles = [
    ...Array.from({ length: 120 }, (_, i) => bottle(i)),
    ...Array.from(
      { length: 30 },
      (_, i) => bottle(i, { region_key: "it_chianti", grapes: ["sangiovese"] }),
    ),
    // Too few to be a kind of their own; counted in the category.
    ...Array.from(
      { length: 5 },
      (_, i) => bottle(i, { style_key: "rose_wine", grapes: [] }),
    ),
  ];
  const count = buildKindSpreads(bottles, "2026-11-23") as unknown as {
    read_on: string;
    bottles: number;
    kinds: Record<string, {
      bottles: number;
      levels: Record<string, number[]>;
      carried: Record<string, Record<string, number>>;
    }>;
  };
  assertEquals(count.read_on, "2026-11-23");
  assertEquals(count.bottles, 155);
  assertEquals(Object.keys(count.kinds), ["red_wine", "wine", "wine_still"]);
  const red = count.kinds.red_wine;
  assertEquals(red.bottles, 150);
  assertEquals(red.levels.acidity, [0, 0, 75, 75, 0]);
  assertEquals(red.levels.body, [0, 0, 150, 0, 0]);
  // Nothing was read for bitterness, so the dimension is not written.
  assertEquals("bitterness" in red.levels, false);
  assertEquals(red.carried.grapes, { pinot_noir: 120 });
  assertEquals(red.carried.styles, { burgundy_red: 120, chianti_red: 30 });
  assertEquals(count.kinds.wine.carried.kinds, { red_wine: 150, rose_wine: 5 });
  // A whole count the engine takes; this small one is under half the shipped bottles.
  assertEquals(useKindSpreads(count), false);
  assert(useKindSpreads({ ...count, bottles: shipped.bottles }));
  assertEquals(bottlesCarrying("styles", "chianti_red", "red_wine"), {
    bottles: 30,
    of: 150,
  });
  useKindSpreads(null);
});
