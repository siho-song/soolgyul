import { assertEquals } from "jsr:@std/assert@1";
import { terms } from "../../_shared/taste_card/dictionary/dictionary.ts";
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
    ...textTerms("**체리 향**과 **산미**, **떫은 조임**이 **긴 여운**으로"),
    tagTerm("체리향"),
    pickTerm("셰리 캐스크(Sherry Cask)"),
    ...terms("aroma", "aroma_family").map((t) => tagTerm(t.names.ko)),
    ...terms("process", "maturation").map((t) => pickTerm(t.names.ko)),
  ].filter((term) => term !== null);
  assertEquals(opened.length > 600, true);
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
