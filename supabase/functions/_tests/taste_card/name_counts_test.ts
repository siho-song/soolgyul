import spreads from "../../../../catalog/dictionary/kind_spreads.json" with {
  type: "json",
};
import {
  tasteOfName,
  useKindSpreads,
} from "../../_shared/record_reading/facts/kind_place.ts";
import {
  buildKindSpreads,
  type CountedBottle,
} from "../../_shared/record_reading/facts/kind_spreads_build.ts";
import {
  onShelf,
  shareBeyond,
  shareOnSide,
  shareWithAroma,
} from "../../_shared/record_reading/facts/name_counts.ts";
import { assert, same } from "../helpers/assert.ts";

const near = (value: number | null | undefined, wanted: number) =>
  typeof value === "number" && Math.abs(value - wanted) < 0.02;

Deno.test("name counts: the nightly count says what the bottles of each name are like, from thirty bottles", () => {
  const whisky = (
    n: number,
    processes: string[],
    body: number,
    aroma_tags: string[],
  ): CountedBottle[] =>
    Array.from({ length: n }, () => ({
      style_key: "single_malt_whisky",
      category_key: "whisky",
      body,
      processes,
      aroma_tags,
    }));
  const out = buildKindSpreads([
    ...whisky(60, ["ex_sherry_cask"], 5, ["raisin"]),
    ...whisky(50, ["ex_bourbon_cask"], 2, ["vanilla"]),
    ...whisky(10, ["ex_port_cask"], 4, []),
  ], "2026-11-23");
  // deno-lint-ignore no-explicit-any
  const kind = out.kinds.single_malt_whisky as any;
  same(kind.named.made.ex_sherry_cask, {
    bottles: 60,
    levels: { body: [0, 0, 0, 0, 60] },
    aromas: { raisin: 60 },
  });
  same(kind.named.made.ex_bourbon_cask.levels.body, [0, 50, 0, 0, 0]);
  // Ten bottles say nothing countable of a name.
  same(kind.named.made.ex_port_cask, undefined);
  same(kind.aromas, { raisin: 60, vanilla: 50 });
  // A category counts its kinds as names too.
  // deno-lint-ignore no-explicit-any
  const all = out.kinds.whisky as any;
  same(all.named.kinds.single_malt_whisky.bottles, 120);
});

Deno.test("name counts: a name is asked of its own bottles, not of its row of the dictionary", () => {
  const pinot = { what: "grapes", key: "pinot_noir" } as const;
  // Two Pinot Noir reds in three are high in acid; one in seven carries earth,
  // twice as often as a red does.
  assert(near(shareOnSide(pinot, "red_wine", "acidity", "high"), 0.68));
  const earth = shareWithAroma(pinot, "red_wine", "earth");
  assert(near(earth?.name, 0.15) && near(earth?.shelf, 0.07));
  // What choosing it does to a tannin felt at step 4: most of its bottles are below.
  assert(
    (shareBeyond(pinot, "red_wine", "astringency", 4, "lower") ?? 0) > 0.9,
  );
  // A kind is asked of its own bottles: a third of the 준마이 다이긴조 are light.
  assert(
    near(
      shareOnSide(
        { what: "kinds", key: "junmai_daiginjo" },
        null,
        "body",
        "low",
      ),
      0.36,
    ),
  );
  // A name the count does not hold, or a dimension its bottles do not carry.
  same(
    shareOnSide(
      { what: "grapes", key: "no_such" },
      "red_wine",
      "body",
      "high",
    ),
    null,
  );
  same(shareOnSide(pinot, "red_wine", "carbonation", "high"), null);
});

Deno.test("name counts: a name is looked for when enough bottles of the kind carry it, and not every one", () => {
  same(onShelf({ what: "grapes", key: "pinot_noir" }, "red_wine"), "enough");
  same(
    onShelf({ what: "ingredients", key: "grape" }, "red_wine"),
    "everywhere",
  );
  same(onShelf({ what: "grapes", key: "no_such" }, "red_wine"), "few");
  same(onShelf({ what: "grapes", key: "pinot_noir" }, null), "uncounted");
});

Deno.test("name counts: a night's count made before names were counted is answered by the shipped one", () => {
  const older = {
    bottles: spreads.bottles,
    kinds: Object.fromEntries(
      Object.entries(spreads.kinds).map(([key, kind]) => {
        const { named: _named, aromas: _aromas, ...rest } = kind as Record<
          string,
          unknown
        >;
        return [key, rest];
      }),
    ),
  };
  try {
    assert(useKindSpreads(older));
    assert(
      (tasteOfName("grapes", "pinot_noir", "red_wine")?.bottles ?? 0) > 1000,
    );
    // A count whose names are not counts is not taken.
    assert(
      !useKindSpreads({
        ...older,
        kinds: {
          ...older.kinds,
          red_wine: {
            ...older.kinds.red_wine,
            named: { grapes: { pinot_noir: { bottles: "many" } } },
          },
        },
      }),
    );
  } finally {
    useKindSpreads(null);
  }
});
