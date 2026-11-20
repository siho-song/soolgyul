import { regionPath } from "../../_shared/taste_card/dictionary/dictionary.ts";
import {
  type Evidence,
  type EvidenceResult,
  findEvidence,
} from "../../_shared/taste_card/evidence/evidence.ts";
import {
  bottleIdentity,
  labelWordsOf,
} from "../../_shared/taste_card/evidence/identity.ts";
import { drinkFile } from "../../_shared/taste_card/dictionary/dictionary.ts";
import {
  bottleFacts,
  wineRegionKey,
} from "../../_shared/taste_card/prepare/bottle.ts";
import { prepareCard } from "../../_shared/taste_card/prepare/prepare.ts";
import { catalogProduct } from "../../_shared/taste_card/record/record_builder.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
import { assert, same } from "../helpers/assert.ts";
import { recordFrom } from "../helpers/card_fixture_record.ts";

function bottle(
  category: SensoryProduct["category"],
  styleKey: string,
  more: Partial<SensoryProduct> = {},
): SensoryProduct {
  return {
    name: "시험",
    category,
    styleKey,
    abv: null,
    levels: {},
    descriptors: [],
    ...more,
  };
}

function evidenceOf(keys: string[], product: SensoryProduct): EvidenceResult {
  return findEvidence(prepareCard(recordFrom("evidence", keys, product)));
}

/** "body:5 explain/clear grape:malbec+region_style:mendoza_red" */
function said(e: Evidence): string {
  const a = e.answer.kind === "gauge"
    ? `${e.answer.axis}:${e.answer.level}`
    : `aroma:${e.answer.aroma}`;
  return `${a} ${e.type}/${e.clarity} ${
    e.causes.map((c) => `${c.factor}:${c.key}`).join("+")
  }`;
}

const MALBEC = bottle("wine", "red_wine", {
  name: "멘델 말벡 2020",
  abv: 14.5,
  region: regionPath("ar_mendoza"),
  grapeVarietyKeys: ["malbec"],
});

Deno.test("근거 찾기: a new-world wine of its style's own grape is called by both and led by the grape", () => {
  const r = evidenceOf(
    ["level:body:5:liked", "aroma:nose:violet:liked"],
    MALBEC,
  );
  same(r.identity.identity_key, "combo:mendoza_red+malbec");
  same(r.identity.lead, "grape");
  same(r.identity.wine_case, "new_world_own_grape");
  same(r.evidence.map(said), [
    "body:5 explain/clear grape:malbec+region_style:mendoza_red+making:european_oak+abv:abv_high",
    "aroma:violet aroma_origin/clear grape:malbec+region_style:mendoza_red",
  ]);
  // A cause written only in the style's row is told apart from the label's.
  same(r.identity.causes.filter((c) => c.on === "style").map((c) => c.key), [
    "american_oak",
    "european_oak",
  ]);
});

Deno.test("근거 찾기: an answer across the identity's tendency is felt differently once, with every row that held, strongest first", () => {
  const r = evidenceOf(
    ["level:sweetness:3:liked", "level:body:5:liked"],
    MALBEC,
  );
  const felt = r.evidence.find((e) => e.type === "felt_differently");
  assert(felt, "felt differently");
  same(felt.claim_key, "felt:sweetness:middle");
  same(felt.causes.map((c) => `${c.factor}:${c.key}:${c.tendency?.step}`), [
    "grape:malbec:1",
  ]);
  const rows = felt.perception!.rules.map((x) => x.row);
  // The reader's own body answer (1) before the bottle's ABV (2) before tendencies (3).
  same(rows.slice(0, 2), ["가-4", "가-3"]);
  assert(rows.includes("가-2"), "warm Mendoza ripens the fruit");
  // Felt differently, the answer is not also explained a step off.
  same(
    r.evidence.filter((e) =>
      e.answer.kind === "gauge" && e.answer.axis === "sweetness"
    ).length,
    1,
  );
});

Deno.test("근거 찾기: the bottle's own level on the answer's side keeps it from being felt differently", () => {
  const r = evidenceOf(["level:sweetness:4:liked", "level:body:5:liked"], {
    ...MALBEC,
    levels: { sweetness: 4 },
    levelSources: { sweetness: 1 },
  });
  assert(
    !r.evidence.some((e) => e.type === "felt_differently"),
    "the bottle is sweet itself",
  );
});

Deno.test("근거 찾기: an old-world wine of its own grape is led by its style", () => {
  const r = evidenceOf(
    ["level:acidity:5:liked"],
    bottle("wine", "white_wine", {
      name: "샤블리 2022",
      region: regionPath("fr_chablis"),
      grapeVarietyKeys: ["chardonnay"],
    }),
  );
  same(r.identity.identity_key, "style:chablis_white");
  same(r.identity.lead, "region");
  same(r.evidence.map(said)[0].split(" ").slice(0, 2), [
    "acidity:5",
    "explain/clear",
  ]);
  same(r.evidence[0].causes[0].key, "chablis_white");
});

Deno.test("근거 찾기: a grape its style is not made of speaks for the taste, the style only for its climate", () => {
  const id = bottleIdentity(
    prepareCard(
      recordFrom(
        "combo",
        ["level:body:4:liked"],
        bottle("wine", "red_wine", {
          name: "보르도 시라",
          region: regionPath("fr_bordeaux"),
          grapeVarietyKeys: ["syrah"],
        }),
      ),
    ).bottle,
  )!;
  same(id.wine_case, "other_grape");
  same(id.identity_key, "combo:bordeaux_red+syrah");
  const style = id.factors.find((f) => f.factor === "region_style")!;
  same(style.taste, {});
  assert(style.climate, "the style keeps its climate");
});

Deno.test("근거 찾기: a label word on sweetness speaks before a grape that runs several ways; without one the answer is left with why", () => {
  const spaetlese = evidenceOf(
    ["level:sweetness:4:liked"],
    bottle("wine", "white_wine", {
      name: "닥터 루젠 리슬링 슈페트레제",
      region: regionPath("de_mosel"),
      grapeVarietyKeys: ["riesling"],
    }),
  );
  same(spaetlese.evidence.map(said), [
    "sweetness:4 explain/clear label_word:wine_spaetlese",
  ]);
  const plain = evidenceOf(
    ["level:sweetness:4:liked"],
    bottle("wine", "white_wine", {
      name: "어느 리슬링",
      region: regionPath("de_mosel"),
      grapeVarietyKeys: ["riesling"],
    }),
  );
  // The kind (white wine = dry) does not speak for an axis a cause runs several ways on.
  same(plain.evidence, []);
  same(plain.misses.map((m) => `${m.reason}:${m.by}`), [
    "varies:region_style:mosel_white",
  ]);
  same(plain.identity.varies.map((v) => v.axis).includes("sweetness"), true);
});

Deno.test("근거 찾기: a wine with only its kind is never felt differently by the kind's tendency", () => {
  const r = evidenceOf(
    ["level:sweetness:4:liked"],
    bottle("wine", "sparkling_wine", { name: "스푸만테", abv: 7 }),
  );
  same(r.identity.identity_key, "kind:sparkling_wine");
  assert(
    !r.evidence.some((e) => e.type === "felt_differently"),
    "no felt differently from the kind",
  );
});

Deno.test("근거 찾기: a whisky is read by kind, cask and distillery; a cause of the bottle explains against what its kind is usually like", () => {
  const r = evidenceOf(
    ["level:sweetness:4:liked", "level:peat:5:liked"],
    bottle("whisky", "single_malt_whisky", {
      name: "라프로익 10년",
      abv: 43,
      processes: ["ex_sherry_cask"],
      producer: "라프로익",
      ageStatementYears: 10,
    }),
  );
  same(r.identity.identity_key, "kind:single_malt_whisky+cask:ex_sherry_cask");
  same(r.identity.causes.map((c) => `${c.factor}:${c.key}`), [
    "kind:single_malt_whisky",
    "cask:ex_sherry_cask",
    "age:scotch_10_11",
    "producer:laphroaig",
  ]);
  same(r.evidence.map(said), [
    "sweetness:4 explain/clear cask:ex_sherry_cask",
    "peat:5 explain/clear producer:laphroaig",
  ]);
});

Deno.test("근거 찾기: an independent bottler is not a cause", () => {
  const id = bottleIdentity(
    prepareCard(
      recordFrom(
        "bottler",
        ["level:body:4:liked"],
        bottle("whisky", "single_malt_whisky", { producer: "앵거스 던디" }),
      ),
    ).bottle,
  )!;
  assert(!id.factors.some((f) => f.factor === "producer"), "bottler left out");
});

Deno.test("근거 찾기: sake umami felt high on a grade with little of it is explained by a rich making, with what it did in the glass (라-1)", () => {
  const r = evidenceOf(
    ["level:umami:4:liked"],
    bottle("sake", "daiginjo", { abv: 17, processes: ["undiluted"] }),
  );
  // 겐슈 is itself a cause of the umami, so the answer is not felt differently.
  same(r.evidence.map(said), ["umami:4 explain/clear making:undiluted"]);
  same(r.evidence[0].perception?.rules.map((rule) => rule.row), ["라-1"]);
  const junmai = evidenceOf(
    ["level:umami:4:liked"],
    bottle("sake", "junmai", {}),
  );
  same(junmai.evidence.map(said), ["umami:4 explain/clear kind:junmai"]);
});

Deno.test("근거 찾기: label words are read word by word, the longer of two overlapping wins, and sugar beats ripeness", () => {
  const wine = drinkFile("wine")!;
  const keys = (name: string, kind: string) =>
    labelWordsOf(wine, name, kind).map((w) => w.key);
  same(keys("샴페인 엑스트라-브뤼", "sparkling_wine"), [
    "sparkling_extra_brut",
  ]);
  same(keys("프로세코 브뤼", "sparkling_wine"), ["sparkling_brut"]);
  same(keys("리슬링 카비넷 트로켄", "white_wine"), ["wine_trocken"]);
  same(keys("리슬링 카비넷", "white_wine"), ["wine_kabinett"]);
  // A word meant for sparkling wine is not read on a still one.
  same(keys("브뤼", "white_wine"), []);
});

Deno.test("조회: an appellation is read in a name unless it stands inside a grape's name", () => {
  const red = (name: string) =>
    wineRegionKey({ ...bottle("wine", "red_wine"), name });
  same(red("다밀라노 바르베라 다스티"), "asti_red");
  same(
    wineRegionKey({
      ...bottle("wine", "sparkling_wine"),
      name: "브라이다 브라케토 다퀴",
    }),
    "brachetto_sparkling",
  );
  same(
    wineRegionKey({
      ...bottle("wine", "white_wine"),
      name: "melon de bourgogne",
    }),
    null,
  );
});

const SHERRY_AND_BOURBON = bottle("whisky", "single_malt_whisky", {
  name: "글렌피딕 12년",
  abv: 45,
  processes: ["ex_bourbon_cask", "ex_sherry_cask"],
});

Deno.test("근거 찾기: two causes of the bottle that say opposite things are both kept, whichever the answer", () => {
  const sides = (keys: string[]) =>
    evidenceOf(keys, SHERRY_AND_BOURBON).evidence.map((e) =>
      `${said(e)} | ${
        (e.against ?? []).map((c) => `${c.factor}:${c.key}`).join("+")
      }`
    );
  same(sides(["level:body:2:disliked"]), [
    "body:2 split/clear cask:ex_bourbon_cask | cask:ex_sherry_cask",
  ]);
  same(sides(["level:body:4:liked"]), [
    "body:4 split/clear kind:single_malt_whisky+cask:ex_sherry_cask | cask:ex_bourbon_cask",
  ]);
  // The kind is what bottles like it share: against it a cask explains, and
  // against a cask the kind alone does not.
  same(sides(["level:sweetness:4:liked"]), [
    "sweetness:4 explain/clear cask:ex_bourbon_cask+cask:ex_sherry_cask | ",
  ]);
  same(sides(["level:sweetness:2:disliked"]), [
    "sweetness:2 split/clear kind:single_malt_whisky | cask:ex_bourbon_cask+cask:ex_sherry_cask",
  ]);
});

Deno.test("근거 찾기: a making row every bottle of the drink has is no cause", () => {
  const wine = evidenceOf(
    ["level:tannin:4:liked"],
    bottle("wine", "red_wine", {
      name: "시험 레드",
      processes: ["cultured_fermentation", "oak_wood"],
    }),
  );
  same(wine.identity.causes.map((c) => `${c.factor}:${c.key}`), [
    "making:oak_wood",
    "kind:red_wine",
  ]);
  same(wine.evidence.map(said), ["tannin:4 explain/clear making:oak_wood"]);
  const sake = bottleIdentity(
    prepareCard(
      recordFrom(
        "given",
        ["level:body:4:liked"],
        bottle("sake", "junmai", {
          processes: ["parallel_multiple_fermentation", "undiluted"],
          ingredients: ["rice", "koji_starter"],
        }),
      ),
    ).bottle,
  )!;
  same(sake.factors.map((f) => `${f.factor}:${f.key}`), [
    "kind:junmai",
    "making:undiluted",
  ]);
});

Deno.test("근거 찾기: the bottle's strength is a cause of its heat and weight where it stands high or low in its kind", () => {
  const soju = (abv: number) =>
    evidenceOf(
      ["level:spice:4:disliked", "level:body:4:liked"],
      bottle("korean_traditional", "distilled_soju", {
        name: "시험 소주",
        abv,
      }),
    ).evidence.map(said);
  same(soju(41), [
    "body:4 explain/clear abv:abv_high",
    "spice:4 explain/clear abv:abv_high",
  ]);
  // The middle band of the kind says nothing.
  assert(
    soju(25).every((line) => !line.includes("abv:")),
    "25% is ordinary for a 증류식 소주",
  );
});

Deno.test("근거 찾기: a level read for the bottle that the answer agrees with is the bottle's own trait where its identity says otherwise", () => {
  const r = evidenceOf(
    ["level:sweetness:4:liked"],
    bottle("whisky", "rye_whisky", {
      name: "시험 라이",
      levels: { sweetness: 4 },
      levelSources: { sweetness: 1 },
    }),
  );
  same(r.evidence.map(said), [
    "sweetness:4 bottle_trait/clear kind:rye_whisky",
  ]);
  same(r.evidence[0].support, {
    axis: "sweetness",
    bottle: 4,
    same_side: true,
  });
  // A level copied from the kind is no reading of the bottle.
  const copied = evidenceOf(
    ["level:sweetness:4:liked"],
    bottle("whisky", "rye_whisky", {
      name: "시험 라이",
      levels: { sweetness: 4 },
      levelSources: { sweetness: 4 },
    }),
  );
  assert(
    copied.evidence.every((e) => e.type !== "bottle_trait"),
    "a copied level makes no trait of the bottle",
  );
});

Deno.test("근거 찾기: an explanation carries what the reader's other answers did in the glass, never what only a tendency suggests", () => {
  const r = evidenceOf(
    ["level:tannin:5:disliked", "level:acidity:4:disliked"],
    bottle("wine", "red_wine", {
      name: "시험 바롤로",
      region: regionPath("it_barolo"),
      grapeVarietyKeys: ["nebbiolo"],
    }),
  );
  const tannin = r.evidence.find((e) =>
    e.answer.kind === "gauge" && e.answer.axis === "tannin"
  )!;
  same(tannin.type, "explain");
  same(
    tannin.perception?.rules.map((rule) =>
      `${rule.row} ${rule.by.map((b) => b.said).join("+")}`
    ),
    ["가-6 answer:acidity:4"],
  );
  // Alone, the same answer has no other answer to lean on.
  const alone = evidenceOf(
    ["level:tannin:5:disliked"],
    bottle("wine", "red_wine", {
      name: "시험 바롤로",
      region: regionPath("it_barolo"),
      grapeVarietyKeys: ["nebbiolo"],
    }),
  );
  same(alone.evidence[0].perception, undefined);
});

Deno.test("근거 찾기: what two of the bottle's rows do together comes with the explanation of an axis the relation speaks of", () => {
  const r = evidenceOf(
    ["level:peat:4:liked", "level:body:4:liked"],
    bottle("whisky", "single_malt_whisky", {
      name: "시험 몰트 18년",
      processes: ["peated_malt", "ex_sherry_cask"],
      ageStatementYears: 18,
    }),
  );
  const of = (axis: string) =>
    r.evidence.find((e) => e.answer.kind === "gauge" && e.answer.axis === axis)
      ?.relations?.map((x) => `${x.of.join("+")}${x.age_from ?? ""}`);
  // Peat and sherry together, and what long years do to each.
  same(of("peat"), ["peated_malt+ex_sherry_cask", "peated_malt15"]);
  same(of("body"), ["peated_malt+ex_sherry_cask", "ex_sherry_cask15"]);
  // A young bottle meets no relation that asks for age.
  const young = evidenceOf(
    ["level:peat:4:liked"],
    bottle("whisky", "single_malt_whisky", {
      name: "시험 몰트",
      processes: ["peated_malt", "ex_sherry_cask"],
    }),
  );
  same(
    young.identity.relations.map((x) => x.of.join("+")),
    ["peated_malt+ex_sherry_cask"],
  );
});

Deno.test("근거 찾기: a blend meets the relation of its grapes, and a grape says what it is like in the bottle's climate and why", () => {
  const r = evidenceOf(
    ["level:tannin:4:liked"],
    bottle("wine", "red_wine", {
      name: "시험 보르도",
      region: regionPath("fr_bordeaux"),
      grapeVarietyKeys: ["cabernet_sauvignon", "merlot"],
    }),
  );
  same(r.identity.relations.map((x) => x.of.join("+")), [
    "cabernet_sauvignon+merlot",
  ]);
  const grape = bottleIdentity(
    prepareCard(recordFrom("climate", ["level:body:4:liked"], MALBEC)).bottle,
  )!.factors.find((f) => f.factor === "grape")!;
  same(grape.in_climate?.side, "warmer");
  assert(!!grape.why, "the grape says why it tastes so");
});

Deno.test("근거 찾기: a sake that prints dry or sweet on its name is read by that word before its grade", () => {
  const dry = evidenceOf(
    ["level:sweetness:1:liked"],
    bottle("sake", "junmai_ginjo", { name: "시험 준마이 긴조 초카라구치" }),
  );
  same(dry.evidence.map(said), [
    "sweetness:1 explain/clear label_word:chokarakuchi",
  ]);
  // The longer word wins: 초카라구치 is not also 카라구치.
  same(
    labelWordsOf(drinkFile("sake")!, "시험 초카라구치", "junmai").map((w) =>
      w.key
    ),
    ["chokarakuchi"],
  );
  // The grade is dry, but against the bottle's own word it does not stand.
  const sweet = evidenceOf(
    ["level:sweetness:4:liked"],
    bottle("sake", "junmai", { name: "시험 준마이 아마구치" }),
  );
  same(sweet.evidence.map(said), [
    "sweetness:4 explain/clear label_word:amakuchi",
  ]);
});

Deno.test("근거 찾기: 끝맛의 인상 meets the dictionary and the bottle on the scale it is asked on", () => {
  // Asked from clean (1) to rich (5), and held so by the dictionary and the catalog.
  const finish = (level: number, product: SensoryProduct) =>
    evidenceOf([`level:finish_character:${level}:liked`], product);
  const rich = finish(4, MALBEC);
  same(rich.evidence.map(said), [
    "finish_character:4 explain/clear grape:malbec+region_style:mendoza_red",
  ]);
  same(rich.evidence[0].causes[0].tendency, {
    axis: "finish_character",
    step: 4,
  });
  const chablis = bottle("wine", "white_wine", {
    region: regionPath("fr_chablis"),
    grapeVarietyKeys: ["chardonnay"],
  });
  same(finish(1, chablis).evidence.map(said), [
    "finish_character:1 explain/clear region_style:chablis_white",
  ]);
  // A rich finish is not what a Chablis is, and nothing says why it was felt.
  same(finish(5, chablis).evidence, []);
  // 누룩 leaves a finish that stays, 효모 a clean one: both on one bottle split.
  const takju = (ingredients: string[]) =>
    bottle("korean_traditional", "takju", { ingredients });
  same(finish(5, takju(["rice", "nuruk_starter"])).evidence.map(said), [
    "finish_character:5 explain/clear ingredient:nuruk_starter",
  ]);
  const both = finish(1, takju(["rice", "nuruk_starter", "yeast"])).evidence;
  same(both.map(said), ["finish_character:1 split/clear ingredient:yeast"]);
  same(both[0].against?.map((c) => c.key), ["nuruk_starter"]);
  // The level read for the bottle is on the same scale.
  const grain = evidenceOf(
    ["level:finish_character:5:liked"],
    bottle("whisky", "grain_whisky", {
      levels: { finish_character: 5 },
      levelSources: { finish_character: 1 },
    }),
  );
  same(grain.evidence.map((e) => [e.type, e.support?.same_side]), [
    ["bottle_trait", true],
  ]);
  // A sake's making says a finish stays where its grade alone says clean.
  const genshu = bottle("sake", "junmai_ginjo", { processes: ["undiluted"] });
  same(finish(5, genshu).evidence.map(said), [
    "finish_character:5 explain/clear making:undiluted",
  ]);
  same(
    finish(1, bottle("sake", "junmai", { name: "시험 준마이 카라구치" }))
      .evidence.map(said),
    ["finish_character:1 explain/clear label_word:karakuchi"],
  );
  // A whisky's cask says which way its finish goes; two casks split.
  const malt = (processes: string[]) =>
    bottle("whisky", "single_malt_whisky", { processes });
  same(finish(5, malt(["ex_sherry_cask"])).evidence.map(said), [
    "finish_character:5 explain/clear cask:ex_sherry_cask",
  ]);
  const two = finish(1, malt(["ex_sherry_cask", "ex_bourbon_cask"])).evidence;
  same(two.map(said), ["finish_character:1 split/clear cask:ex_bourbon_cask"]);
  same(two[0].against?.map((c) => c.key), ["ex_sherry_cask"]);
  // A minded rich finish asks for less of it, in the answer's own words.
  const port = evidenceOf(
    ["level:finish_character:5:disliked"],
    bottle("wine", "port_wine", { region: regionPath("pt_douro") }),
  );
  same(port.evidence.map((e) => [e.guide.direction, e.guide.axis]), [
    ["reduce", "finish_character"],
  ]);
});

Deno.test("근거 찾기: a maker's house style explains what its grade or kind does not", () => {
  // A 준마이 다이긴조 is not dry by its grade; 쿠보타 is by its house.
  const kubota = bottle("sake", "junmai_daiginjo", { producer: "쿠보타" });
  const dry = evidenceOf(
    ["level:sweetness:1:liked", "level:finish_length:1:liked"],
    kubota,
  );
  same(dry.evidence.map(said), [
    "sweetness:1 explain/clear producer:kubota",
    "finish_length:1 explain/clear producer:kubota",
  ]);
  assert(dry.evidence[0].causes[0].why, "the house style says why");
  const light = evidenceOf(
    ["level:body:2:liked", "level:finish_length:2:liked"],
    bottle("whisky", "single_malt_whisky", { producer: "글렌리벳" }),
  );
  same(light.evidence.map(said), [
    "body:2 explain/clear producer:glenlivet",
    "finish_length:2 explain/clear producer:glenlivet",
  ]);
  // A house that makes it several ways says nothing, and neither does its kind.
  const several = evidenceOf(
    ["level:sweetness:4:liked"],
    bottle("whisky", "single_malt_whisky", { producer: "벤리악" }),
  );
  same(several.evidence, []);
  same(several.misses, [{
    ref: "level:sweetness:4:liked",
    reason: "varies",
    by: "producer:benriach",
  }]);
});

Deno.test("근거 찾기: a whisky at its legal least is not a weak bottle, one bottled strong is a strong one", () => {
  const malt = (abv: number) =>
    evidenceOf(
      ["level:body:4:liked", "level:spice:4:disliked"],
      bottle("whisky", "single_malt_whisky", { name: "시험 몰트", abv }),
    );
  same(malt(40).identity.causes.map((c) => `${c.factor}:${c.key}`), [
    "kind:single_malt_whisky",
  ]);
  same(malt(40).evidence.map(said), [
    "body:4 explain/clear kind:single_malt_whisky",
  ]);
  same(malt(58).evidence.map(said), [
    "body:4 explain/clear kind:single_malt_whisky+abv:abv_high",
    "spice:4 explain/clear abv:abv_high",
  ]);
});

Deno.test("근거 찾기: a distilled 소주 keeps the aromas of what it is made from, not its sweetness or weight", () => {
  const made = (kind: string) =>
    evidenceOf(
      [
        "level:body:4:liked",
        "level:sweetness:4:liked",
        "aroma:nose:rice:liked",
      ],
      bottle("korean_traditional", kind, {
        name: "시험 술",
        ingredients: ["nuruk_starter", "glutinous_rice"],
      }),
    );
  const soju = made("distilled_soju");
  assert(
    soju.evidence.filter((e) => e.answer.kind === "gauge").every((e) =>
      e.causes.every((c) => c.factor !== "ingredient")
    ),
    "no ingredient explains a taste of a distilled drink",
  );
  same(
    soju.evidence.filter((e) => e.answer.kind === "aroma").map(said),
    [
      "aroma:rice aroma_origin/clear kind:distilled_soju+ingredient:glutinous_rice+ingredient:nuruk_starter",
    ],
  );
  same(soju.identity.relations.length, 0);
  // The same ingredients in a drink that is not distilled still explain.
  const takju = made("takju");
  same(takju.evidence.filter((e) => e.answer.kind === "gauge").map(said), [
    "sweetness:4 explain/clear ingredient:glutinous_rice",
    "body:4 explain/clear ingredient:glutinous_rice+ingredient:nuruk_starter",
  ]);
  assert(takju.identity.relations.length > 0, "a 탁주 meets its relations");
});

Deno.test("근거 찾기: one step off a middle tendency is as expected, one step off a pronounced one is felt differently", () => {
  const kabinett = (level: number) =>
    evidenceOf(
      [`level:sweetness:${level}:liked`],
      bottle("wine", "white_wine", {
        name: "시험 리슬링 카비넷",
        grapeVarietyKeys: ["riesling"],
      }),
    ).evidence.map(said);
  same(kabinett(4), ["sweetness:4 explain/weak label_word:wine_kabinett"]);
  same(kabinett(5), [
    "sweetness:5 felt_differently/clear label_word:wine_kabinett",
  ]);
  // A 브뤼 is dry: a step up from it is already not what the label says.
  same(
    evidenceOf(
      ["level:sweetness:3:liked", "aroma:nose:peach:liked"],
      bottle("wine", "sparkling_wine", { name: "시험 브뤼" }),
    ).evidence.map(said),
    ["sweetness:3 felt_differently/clear label_word:sparkling_brut"],
  );
});

Deno.test("근거 찾기: a sake's dry word is read where the name glues it to another word or spells it 가라구치", () => {
  const sake = drinkFile("sake")!;
  const read = (name: string, kind: string) =>
    labelWordsOf(sake, name, kind).map((w) => w.key);
  same(read("바칸 카라쿠치긴죠", "ginjo"), ["karakuchi"]);
  same(read("킷도 준마이 긴죠 카라구치킷도", "junmai_ginjo"), ["karakuchi"]);
  same(read("이찌노쿠라 무칸사 초가라구치", "honjozo"), ["chokarakuchi"]);
  same(read("나가라가와 쥰마이쵸카라구치", "junmai"), ["chokarakuchi"]);
});

Deno.test("근거 찾기: with no cause on the answer's side, another answer of the reader says what happened in the glass", () => {
  const red = bottle("wine", "red_wine", { name: "이름만 있는 병" });
  // A red is of middle grip: the kind only places the answer. The reader
  // found no sweetness, which lets the grip show.
  const r = evidenceOf(
    ["level:sweetness:1:liked", "level:tannin:4:liked"],
    red,
  );
  const glass = r.evidence.find((e) => e.type === "in_this_glass");
  assert(glass, "in this glass");
  same(glass.causes, []);
  same(glass.answer.kind === "gauge" && glass.answer.axis, "tannin");
  assert(
    glass.perception!.rules.every((rule) =>
      rule.by.every((b) => b.strength === 1)
    ),
    "only what the reader answered",
  );
  // Without the other answer nothing is said of the glass.
  const alone = evidenceOf(["level:tannin:4:liked"], red);
  assert(
    !alone.evidence.some((e) => e.type === "in_this_glass"),
    "no row holds on the bottle's tendency alone",
  );
  // An answer a cause explains needs no such row.
  const explained = evidenceOf(
    ["level:sweetness:1:liked", "level:tannin:5:liked"],
    bottle("wine", "red_wine", {
      name: "바롤로 2019",
      region: regionPath("it_barolo"),
      grapeVarietyKeys: ["nebbiolo"],
    }),
  );
  assert(
    !explained.evidence.some((e) => e.type === "in_this_glass"),
    "the grape explains the grip",
  );
});

Deno.test("근거 찾기: what the reader answered elsewhere says why a finish felt short or long", () => {
  const red = bottle("wine", "red_wine", { name: "이름만 있는 병" });
  const rows = (keys: string[], product = red) =>
    evidenceOf(keys, product).evidence
      .filter((e) =>
        e.answer.kind === "gauge" && e.answer.axis === "finish_length"
      )
      .flatMap((e) => e.perception?.rules ?? [])
      .filter((rule) => rule.by.some((b) => b.strength === 1))
      .map((rule) => rule.name);
  // A light, dry glass with no grip: each is a reason the finish was short.
  same(
    rows([
      "level:finish_length:1:disliked",
      "level:body:2:liked",
      "level:sweetness:1:liked",
      "level:tannin:2:liked",
    ]),
    [
      "가벼운 바디 → 짧은 여운",
      "단맛이 적음 → 짧은 여운",
      "떫음이 적음 → 짧은 여운",
    ],
  );
  // Sharp acidity keeps a finish going: it is no reason for a short one.
  same(rows(["level:finish_length:1:disliked", "level:acidity:5:liked"]), []);
  same(rows(["level:finish_length:5:liked", "level:acidity:5:liked"]), [
    "높은 산미 → 긴 여운",
  ]);
  // Peat is asked of whisky alone, and acidity says nothing of a whisky's finish.
  same(
    rows(
      [
        "level:finish_length:5:liked",
        "level:peat:5:liked",
        "level:body:4:liked",
      ],
      bottle("whisky", "blended_whisky", { name: "블렌디드" }),
    ),
    ["묵직한 바디 → 긴 여운", "피트 → 긴 여운"],
  );
});

Deno.test("근거 찾기: a blend's grapes stay in the catalog's order, main grape first", () => {
  const product = catalogProduct(
    {
      name_ko: "포이약 블렌드",
      style_key: "red_wine",
      category: { category_key: "wine" },
      grape_variety_keys: ["merlot", "cabernet_sauvignon", "cabernet_franc"],
    },
    null,
    {},
  );
  same(product.grapeVarietyKeys, [
    "merlot",
    "cabernet_sauvignon",
    "cabernet_franc",
  ]);
  same(bottleFacts(product).grapes[0], "merlot");
});
