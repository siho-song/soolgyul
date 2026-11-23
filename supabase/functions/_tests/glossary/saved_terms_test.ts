import { assertEquals } from "jsr:@std/assert@1";
import { terms } from "../../_shared/record_reading/dictionary/dictionary.ts";
import {
  pickTerm,
  tagTerm,
  textTerms,
} from "../../_shared/taste_card/writing/terms.ts";
import { glossaryTerm } from "../../_shared/glossary/glossary.ts";
import { savedTermsForUser } from "../../_shared/glossary/service.ts";
import type {
  SavedTermRow,
  SavedTermsRepository,
} from "../../_shared/glossary/repository.ts";
import { handleSavedTermsRequest } from "../../saved-terms/index.ts";

/** A table of one reader's saved terms, in memory. */
class MemoryTerms implements SavedTermsRepository {
  rows: SavedTermRow[] = [];
  active = true;
  private clock = 0;
  accountActive = () => Promise.resolve(this.active);
  list = () =>
    Promise.resolve(
      [...this.rows].sort((a, b) => b.created_at.localeCompare(a.created_at)),
    );
  save(_user: string, key: string) {
    if (!this.rows.some((row) => row.term_key === key)) {
      this.clock += 1;
      this.rows.push({
        term_key: key,
        created_at: `2026-11-14T00:00:0${this.clock}Z`,
      });
    }
    return Promise.resolve();
  }
  remove(_user: string, key: string) {
    this.rows = this.rows.filter((row) => row.term_key !== key);
    return Promise.resolve();
  }
}

Deno.test("a term is filed under its kind and the drinks it belongs to", () => {
  const filed = (key: string) => {
    const term = glossaryTerm(key);
    return term && [term.label, term.kind, term.categories];
  };
  // A sensation is tasted in every drink.
  assertEquals(filed("aroma:cherry"), ["체리", "향", ["common"]]);
  assertEquals(filed("axis:sweetness"), ["체감 단맛", "맛", ["common"]]);
  assertEquals(filed("axis:astringency")?.[1], "질감");
  assertEquals(filed("axis:finish_length")?.[1], "여운");
  assertEquals(filed("texture:light_texture")?.slice(1), ["질감", ["common"]]);
  // A grape, a cask and a region carry the drinks the dictionary names.
  assertEquals(filed("grape:cabernet_sauvignon"), [
    "까베르네 소비뇽",
    "품종",
    ["wine"],
  ]);
  assertEquals(filed("maturation:ex_sherry_cask")?.slice(0, 2), [
    "셰리 캐스크",
    "제조·숙성",
  ]);
  assertEquals(filed("region:gb_speyside"), [
    "스페이사이드",
    "산지",
    ["whisky"],
  ]);
  assertEquals(filed("region:fr")?.[2], ["wine", "whisky"]);
  // A maker is filed under what it makes.
  assertEquals(filed("producer:allt_a_bhainne")?.slice(1), [
    "생산자",
    ["whisky"],
  ]);
  // Every drink at once is common; nothing else is.
  for (const type of ["process", "maturation", "grape", "region"]) {
    for (const term of terms(type)) {
      const categories = glossaryTerm(`${type}:${term.key}`)?.categories ?? [];
      assertEquals(categories.length < 4, true, term.key);
      assertEquals(
        categories.includes("common"),
        categories.length === 1 && categories[0] === "common",
        term.key,
      );
    }
  }
  assertEquals(glossaryTerm("aroma:no_such_scent"), null);
  assertEquals(glossaryTerm("kind:junmai"), null);
});

Deno.test("every explanation a card opens can be saved", () => {
  const opened = [
    ...textTerms("**피트 향**과 **산미**, **떫은 조임**이 **긴 여운**으로"),
    tagTerm("피트향"),
    pickTerm("셰리 캐스크(Sherry Cask)"),
    ...terms("aroma", "aroma_family").map((t) => tagTerm(t.names.ko)),
    ...terms("process", "maturation").map((t) => pickTerm(t.names.ko)),
  ].filter((term) => term !== null);
  // Only the aromas a card explains are among them (writing/terms.ts).
  assertEquals(opened.length > 90, true);
  for (const term of opened) {
    const saved = glossaryTerm(term.key!);
    assertEquals(
      [saved?.label, saved?.kind, saved?.description],
      [term.label, term.kind, term.description],
      term.word,
    );
  }
});

Deno.test("a reader saves terms, reads them newest first, and takes one out", async () => {
  const table = new MemoryTerms();
  const keys = async (change?: { key: string; saved: boolean }) =>
    (await savedTermsForUser(table, "reader", change)).terms.map((t) => t.key);

  assertEquals(await keys(), []);
  assertEquals(await keys({ key: "aroma:cherry", saved: true }), [
    "aroma:cherry",
  ]);
  assertEquals(await keys({ key: "grape:cabernet_sauvignon", saved: true }), [
    "grape:cabernet_sauvignon",
    "aroma:cherry",
  ]);
  // Saving again changes nothing.
  assertEquals(await keys({ key: "aroma:cherry", saved: true }), [
    "grape:cabernet_sauvignon",
    "aroma:cherry",
  ]);
  const { terms: [grape] } = await savedTermsForUser(table, "reader");
  assertEquals(
    [grape.label, grape.kind, grape.categories, grape.saved_at],
    ["까베르네 소비뇽", "품종", ["wine"], "2026-11-14T00:00:02Z"],
  );
  assertEquals(grape.description.length > 10, true);
  assertEquals(await keys({ key: "aroma:cherry", saved: false }), [
    "grape:cabernet_sauvignon",
  ]);
  // Taking out what is not there is no error.
  assertEquals(await keys({ key: "aroma:cherry", saved: false }), [
    "grape:cabernet_sauvignon",
  ]);

  // A key the dictionary dropped stays in the table and out of the list.
  table.rows.push({
    term_key: "aroma:gone",
    created_at: "2026-11-14T00:00:09Z",
  });
  assertEquals(await keys(), ["grape:cabernet_sauvignon"]);
});

Deno.test("saved-terms answers members only and refuses a key the dictionary lacks", async () => {
  const table = new MemoryTerms();
  const call = (
    method: string,
    body?: unknown,
    user: string | null = "reader",
  ) =>
    handleSavedTermsRequest(
      new Request("https://example.test/functions/v1/saved-terms", {
        method,
        headers: { "Content-Type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body),
      }),
      table,
      () => Promise.resolve(user === null ? null : { user_id: user }),
    );
  const code = async (
    response: Response,
  ) => [response.status, (await response.json()).error_code];

  assertEquals(await code(await call("GET", undefined, null)), [
    401,
    "authorization_required",
  ]);
  assertEquals(
    await code(await call("POST", { key: "aroma:nothing", saved: true })),
    [400, "term_unknown"],
  );
  for (
    const body of [{}, { key: "aroma:cherry" }, { key: 3, saved: true }, [], {
      key: "",
      saved: true,
    }]
  ) {
    assertEquals(await code(await call("POST", body)), [
      400,
      "term_change_invalid",
    ]);
  }
  assertEquals(table.rows, []);

  const saved = await call("POST", { key: "aroma:cherry", saved: true });
  assertEquals(saved.status, 200);
  assertEquals((await saved.json()).terms.map((t: { key: string }) => t.key), [
    "aroma:cherry",
  ]);
  const listed = await (await call("GET")).json();
  assertEquals(Object.keys(listed.terms[0]).sort(), [
    "categories",
    "description",
    "key",
    "kind",
    "label",
    "saved_at",
  ]);

  table.active = false;
  assertEquals(await code(await call("GET")), [403, "active_account_required"]);
  assertEquals(
    await code(await call("POST", { key: "aroma:plum", saved: true })),
    [403, "active_account_required"],
  );
});

Deno.test("a place's styles are saved under the place, one kind at a time", async () => {
  const table = new MemoryTerms();
  const list = async (change?: { key: string; saved: boolean }) =>
    (await savedTermsForUser(table, "reader", change)).terms;
  const red = "regional_style:san_juan_red";
  const white = "regional_style:ar_san_juan_white";

  // The red a reader saved from a red's card: one term, the place.
  const [place] = await list({ key: red, saved: true });
  assertEquals(
    [place.key, place.label, place.kind, place.own, place.categories],
    ["region:ar_san_juan", "산 후안", "산지", false, ["wine"]],
  );
  assertEquals(place.parts?.map((p) => [p.key, p.label]), [[red, "레드"]]);
  assertEquals(place.parts![0].description, glossaryTerm(red)!.description);

  // The white of the same place joins it, newest first; still one term.
  const both = await list({ key: white, saved: true });
  assertEquals(both.map((t) => t.key), ["region:ar_san_juan"]);
  assertEquals(both[0].parts?.map((p) => p.label), ["화이트", "레드"]);
  // An app that knows no parts reads the same in one text.
  assertEquals(both[0].description.includes("화이트: "), true);
  assertEquals(both[0].description.includes("레드: "), true);

  // Taking one kind out leaves the other; the last one takes the place out.
  const one = await list({ key: red, saved: false });
  assertEquals(one[0].parts?.map((p) => p.key), [white]);
  assertEquals(await list({ key: white, saved: false }), []);

  // Taking the place out takes every style saved under it.
  await list({ key: red, saved: true });
  await list({ key: white, saved: true });
  await list({ key: "aroma:cherry", saved: true });
  const left = await list({ key: "region:ar_san_juan", saved: false });
  assertEquals(left.map((t) => t.key), ["aroma:cherry"]);
  assertEquals(table.rows.map((row) => row.term_key), ["aroma:cherry"]);
});

Deno.test("a card's help opens the style of the card's own kind, and says which", () => {
  const opened = (kind: string) =>
    textTerms(
      "**보르도** 특성상 **새콤함**이 또렷해서, 입안을 깨워 줬어요.",
      kind,
    )
      .find((term) => term.word === "보르도")!;
  assertEquals(
    [opened("red_wine").key, opened("red_wine").kind],
    ["regional_style:bordeaux_red", "산지 스타일 · 레드"],
  );
  assertEquals(
    [opened("white_wine").key, opened("white_wine").kind],
    ["regional_style:bordeaux_white", "산지 스타일 · 화이트"],
  );
  assertEquals(
    opened("red_wine").description === opened("white_wine").description,
    false,
  );
  // The balloon's own save is the style's: a red and a white are two saves.
  assertEquals(glossaryTerm(opened("white_wine").key!)?.label, "보르도");
});
