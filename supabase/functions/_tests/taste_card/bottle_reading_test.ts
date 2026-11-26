import { regionPath } from "../../_shared/record_reading/dictionary/dictionary.ts";
import {
  bottleFacts,
  wineRegionKey,
} from "../../_shared/record_reading/bottle.ts";
import type { SensoryProduct } from "../../_shared/record_reading/record/sensory_record.ts";
import { same as equal } from "../helpers/assert.ts";

Deno.test("bottle reading: a level copied from the kind is the kind's, a read one the bottle's", () => {
  const product = (
    levelSources: SensoryProduct["levelSources"],
  ): SensoryProduct => ({
    name: "병",
    category: "wine",
    styleKey: "red_wine",
    region: null,
    abv: null,
    levels: { sweetness: 1, acidity: 4 },
    levelSources,
    levelRefs: {},
    descriptors: [],
  });
  const whose = (levelSources: SensoryProduct["levelSources"]) => {
    const { levels } = bottleFacts(product(levelSources));
    return [levels.sweetness, levels.acidity, levels.body].map((read) =>
      read && [read.of, read.source]
    );
  };
  // Read for the bottle; a dimension nobody read comes from the kind's table.
  equal(whose({ sweetness: 2, acidity: 2 }), [
    ["bottle", 2],
    ["bottle", 2],
    ["kind", "kind_table"],
  ]);
  // Grade 4 is the kind's usual value copied into the bottle.
  equal(whose({ sweetness: 4, acidity: 4 }), [
    ["kind", 4],
    ["kind", 4],
    ["kind", "kind_table"],
  ]);
  // A level the catalog states without a grade is the bottle's.
  equal(whose({}).slice(0, 2), [["bottle", "catalog"], ["bottle", "catalog"]]);
});

Deno.test("bottle reading: a sparkling wine from 샹파뉴 reads as 샴페인, the way the catalog stores it", () => {
  const product = (name: string, region: string | null) => ({
    name,
    category: "wine" as const,
    styleKey: "sparkling_wine",
    region,
    abv: null,
    levels: {},
    levelRefs: {},
    descriptors: [],
  });
  const cases: [string, string | null, string | null][] = [
    // the region label, or a sub-region with its own style
    ["모엣 샹동 브뤼 임페리얼", "샹빠뉴(Champagne)", "champagne_sparkling"],
    [
      "까띠에르 브뤼 블랑 드 블랑",
      "샹빠뉴(Champagne) > 꼬뜨 데 블랑(Côte des Blancs)",
      "cote_des_blancs_sparkling",
    ],
    // an appellation in the name when the region is blank
    ["니노 프랑코 루스티코 프로세코", null, "prosecco_sparkling"],
    // a new-world traditional-method region
    [
      "글로리아 페레 바 데 비 울트라 뀌베",
      "캘리포니아(California) > 소노마 카운티(Sonoma County)",
      "new_world_traditional_sparkling",
    ],
    [
      "미구엘 토레스 에스텔라도 로제",
      "센트럴 밸리(Central Valley)",
      "chile_central_valley_sparkling",
    ],
    // a sparkling wine from nowhere the table knows stays a plain sparkling wine
    ["그라함 벡 브뤼", "웨스턴 케이프(Western Cape)", null],
    // a Frizzante of Austria is no Sekt
    [
      "지게티 블랑 드 블랑 브뤼",
      "부르겐란트(Burgenland)",
      "austria_sekt_sparkling",
    ],
    ["지게티 프리잔테 로제", "부르겐란트(Burgenland)", null],
    // 람브루스코 is read from the name, wherever in Italy the bottle is from
    ["람부르스코 만토바", "롬바르디아(Lombardia)", "lambrusco_sparkling"],
    ["체치 말바시아 브뤼", "에밀리아 로마냐(Emilia-Romagna)", null],
  ];
  for (const [name, region, expected] of cases) {
    const got = wineRegionKey(product(name, region));
    if (got !== expected) throw new Error(`${name}: ${got} != ${expected}`);
  }
});

Deno.test("bottle reading: a place's own style is read for each kind that has one, an orange and a fortified wine too", () => {
  const product = (styleKey: string, place: string) => ({
    name: "병",
    category: "wine" as const,
    styleKey,
    region: regionPath(place),
    abv: null,
    levels: {},
    levelRefs: {},
    descriptors: [],
  });
  const cases: [string, string, string | null][] = [
    // a village reads its own style before the bank it lies on
    ["red_wine", "fr_pauillac", "fr_pauillac_red"],
    // a kind the place had no style for
    ["rose_wine", "fr_bourgogne", "fr_bourgogne_rose"],
    // an orange wine has a colour of its own, a fortified wine is matched by its kind
    ["orange_wine", "au_mclaren_vale", "au_mclaren_vale_orange"],
    ["fortified_wine", "au_heathcote", "au_heathcote_fortified"],
    // a fortified wine does not read the red style of its place
    ["fortified_wine", "fr_pauillac", null],
    // a kind its label word decides reads no place
    ["vermouth", "it_piemonte", null],
  ];
  for (const [styleKey, place, expected] of cases) {
    const got = wineRegionKey(product(styleKey, place));
    if (got !== expected) {
      throw new Error(`${styleKey} ${place}: ${got} != ${expected}`);
    }
  }
});
