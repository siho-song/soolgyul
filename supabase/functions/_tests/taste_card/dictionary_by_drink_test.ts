import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  drinkFile,
  makingOf,
  placeOf,
  terms,
} from "../../_shared/taste_card/dictionary/dictionary.ts";

Deno.test("a place is read from its drink's file", () => {
  const bourgogne = placeOf("wine", "fr_bourgogne");
  assertEquals(bourgogne?.names.ko, "부르고뉴");
  assertEquals(bourgogne?.parent, "fr");
  assertEquals(bourgogne?.categories, ["wine"]);
  // A whisky has no Burgundy.
  assertEquals(placeOf("whisky", "fr_bourgogne"), null);
  // A country is above nothing.
  assertEquals(placeOf("wine", "fr")?.parent, null);
});

Deno.test("a making row says what it does to the drink asked of", () => {
  // Yeast is named for wine but said to do nothing there; for sake it leaves
  // the ginjo aroma.
  const wine = makingOf("wine", "yeast");
  const sake = makingOf("sake", "yeast");
  assertEquals(wine?.names.ko, sake?.names.ko);
  assertEquals(wine?.aromas, undefined);
  assert(sake?.aromas?.some((aroma) => aroma.key === "ginjo_aroma"));
  assertEquals(makingOf("whisky", "nuruk_starter"), null);
});

Deno.test("the flat list holds a shared row once, with every drink that has it", () => {
  const yeast = terms("ingredient").filter((t) => t.key === "yeast");
  assertEquals(yeast.length, 1);
  assertEquals(yeast[0].categories, [
    "wine",
    "whisky",
    "sake",
    "korean_traditional",
  ]);
  const bourgogne = terms("region").filter((t) => t.key === "fr_bourgogne");
  assertEquals(bourgogne.length, 1);
});

Deno.test("a wine's sweetness word says where its sweetness comes from", () => {
  const words = drinkFile("wine")!.label_words.filter((w) =>
    w.taste?.sweetness != null
  );
  assertEquals(words.length, 43);
  for (const w of words) assert(w.sweetness_from, w.key);
  const from = (key: string) =>
    words.find((w) => w.key === key)?.sweetness_from;
  assertEquals(from("wine_eiswein"), "concentration");
  assertEquals(from("wine_amabile"), "term");
  assertEquals(from("sparkling_brut"), "dosage");
  assertEquals(from("wine_vin_doux_naturel"), "fortification");
  // A sparkling wine's grade is its dosage, and only a sparkling wine's is.
  for (const w of words) {
    assertEquals(
      w.sweetness_from === "dosage",
      w.kinds?.includes("sparkling_wine") ?? false,
      w.key,
    );
  }
});
