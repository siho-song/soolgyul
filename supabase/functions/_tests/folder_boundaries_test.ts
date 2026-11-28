// The four parts that read a record stay apart: 기록 읽기 knows none of the
// three above it, and 취향 조각 and 맞는 술 찾기 know neither the card nor
// each other. A convenient import across a boundary fails here.
import { same as equal } from "./helpers/assert.ts";

const shared = new URL("../_shared/", import.meta.url);

/** Every relative import of the folder's files, as "from → to" under _shared. */
async function importsOf(folder: string): Promise<[string, string][]> {
  const found: [string, string][] = [];
  const walk = async (dir: URL) => {
    for await (const entry of Deno.readDir(dir)) {
      const url = new URL(entry.name + (entry.isDirectory ? "/" : ""), dir);
      if (entry.isDirectory) await walk(url);
      else if (entry.name.endsWith(".ts")) {
        const text = await Deno.readTextFile(url);
        for (
          const [, to] of text.matchAll(
            /(?:from|import)\s*\(?\s*"(\.{1,2}\/[^"]+)"/g,
          )
        ) {
          const target = new URL(to, url).pathname;
          if (!target.startsWith(shared.pathname)) continue;
          found.push([
            url.pathname.slice(shared.pathname.length),
            target.slice(shared.pathname.length),
          ]);
        }
      }
    }
  };
  await walk(new URL(folder, shared));
  return found;
}

/** The imports of `folder` that reach into one of `forbidden`. */
async function crossing(folder: string, forbidden: readonly string[]) {
  return (await importsOf(folder)).filter(([, to]) =>
    forbidden.some((other) => to.startsWith(other))
  ).map(([from, to]) => `${from} → ${to}`);
}

Deno.test("folders: 기록 읽기 imports nothing of the card, the taste letters or the fit", async () => {
  equal(
    await crossing("record_reading/", [
      "taste_card/",
      "taste_letters/",
      "taste_fit/",
    ]),
    [],
  );
});

Deno.test("folders: the dictionary's files are read through the dictionary folder", async () => {
  // Everything asks dictionary.ts, aromas.ts, term_help.ts or wine_label.ts.
  // The card's evidence alone weighs a bottle against its drink's own file.
  const reading = [
    ...await importsOf("record_reading/"),
    ...await importsOf("taste_card/"),
    ...await importsOf("taste_letters/"),
    ...await importsOf("taste_fit/"),
    ...await importsOf("glossary/"),
  ].filter(([, to]) => to === "record_reading/dictionary/files.ts")
    .map(([from]) => from)
    .filter((from) =>
      !from.startsWith("record_reading/dictionary/") &&
      !from.startsWith("taste_card/evidence/")
    );
  equal(reading, []);
});

Deno.test("folders: 나의 용어 사전 imports nothing of the card, the taste letters or the fit", async () => {
  equal(
    await crossing("glossary/", [
      "taste_card/",
      "taste_letters/",
      "taste_fit/",
    ]),
    [],
  );
});

Deno.test("folders: 취향 조각 and 맞는 술 찾기 import neither the card nor each other", async () => {
  equal(await crossing("taste_letters/", ["taste_card/", "taste_fit/"]), []);
  equal(await crossing("taste_fit/", ["taste_card/", "taste_letters/"]), []);
});

Deno.test("folders: the card's stages import neither the taste letters nor the fit; only its service refreshes the letters", async () => {
  const reaching = await crossing("taste_card/", [
    "taste_letters/",
    "taste_fit/",
  ]);
  equal(reaching.filter((line) => !line.startsWith("taste_card/service/")), []);
  equal(reaching.filter((line) => line.includes("taste_fit/")), []);
});

Deno.test("folders: a table several features read is read in one file of database/", async () => {
  // The account row, a published bottle and its tasting profile: whoever
  // needs one calls database/accounts.ts or database/bottles.ts.
  const readers: Record<string, string[]> = {
    "users?": [],
    "alcohol_items?": [],
    "alcohol_tasting_profiles?": [],
  };
  const walk = async (dir: URL) => {
    for await (const entry of Deno.readDir(dir)) {
      const url = new URL(entry.name + (entry.isDirectory ? "/" : ""), dir);
      if (entry.isDirectory) await walk(url);
      else if (entry.name.endsWith(".ts")) {
        const text = await Deno.readTextFile(url);
        for (const table of Object.keys(readers)) {
          if (text.includes(`\`${table}`) || text.includes(`"${table}`)) {
            readers[table].push(url.pathname.slice(shared.pathname.length));
          }
        }
      }
    }
  };
  await walk(shared);
  equal(readers, {
    "users?": ["database/accounts.ts"],
    "alcohol_items?": ["database/bottles.ts"],
    "alcohol_tasting_profiles?": ["database/bottles.ts"],
  });
});

Deno.test("folders: each file of the catalog is read by one module", async () => {
  const readers: Record<string, string[]> = {};
  const walk = async (dir: URL) => {
    for await (const entry of Deno.readDir(dir)) {
      const url = new URL(entry.name + (entry.isDirectory ? "/" : ""), dir);
      if (entry.isDirectory) await walk(url);
      else if (entry.name.endsWith(".ts")) {
        const text = await Deno.readTextFile(url);
        for (
          const [, file] of text.matchAll(
            /from\s*"[./]*\/((?:catalog|config)\/[^"]+\.json)"/g,
          )
        ) {
          (readers[file] ??= []).push(
            url.pathname.slice(shared.pathname.length),
          );
        }
      }
    }
  };
  await walk(shared);
  equal(
    Object.entries(readers).filter(([, modules]) => modules.length > 1),
    [],
  );
  equal(readers["catalog/sensory/gauge-definitions.json"], [
    "record_reading/dictionary/gauges.ts",
  ]);
});
