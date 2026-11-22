import type { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { asRole, refusal } from "../helpers/db_session.ts";

// The night's count of the catalog: the job's secret opens the published
// bottles' facts and the one row the functions read, and nothing else does.

const SECRET = "night-job-secret";
const WINE = "c0000000-0000-4000-8000-000000000001";
const item = (n: number) =>
  `e0000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

async function setUp() {
  const db = await createSupabaseLikeDatabase();
  await db.exec(`
    create schema vault;
    create table vault.decrypted_secrets (name text primary key, decrypted_secret text);
    insert into vault.decrypted_secrets values ('kind_spreads_job_secret', '${SECRET}');
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('${WINE}', 'wine', '와인', 1);
    insert into public.alcohol_items
      (id, name_ko, alcohol_category_id, publish_status, published_at, style_key, region_key, abv_percent, grape_variety_keys)
    values
      ('${
    item(1)
  }', '부르고뉴 루즈', '${WINE}', 'published', now(), 'red_wine', 'fr_bourgogne', 13, '{pinot_noir}'),
      ('${
    item(2)
  }', '숨은 병', '${WINE}', 'staging', null, 'red_wine', null, null, '{}'),
      ('${
    item(3)
  }', '키안티', '${WINE}', 'published', now(), 'red_wine', null, 13.5, '{sangiovese}'),
      ('${
    item(4)
  }', '샤블리', '${WINE}', 'published', now(), 'white_wine', null, null, '{}');
    insert into public.alcohol_tasting_profiles (alcohol_item_id, sweetness, acidity, finish_character, aroma_tags)
      values ('${item(1)}', 1, 4, 2, '{cherry}');
  `);
  return db;
}

type Bottle = Record<string, unknown> & { id: string };

const page = (db: PGlite, secret: string, after: string | null, size: number) =>
  asRole(db, "anon", null, async () =>
    (await db.query<{ page: Bottle[] }>(
      "select public.soolgyul_kind_spreads_bottles($1, $2, $3) as page",
      [secret, after, size],
    )).rows[0].page);

const store = (db: PGlite, secret: string, spreads: unknown) =>
  asRole(
    db,
    "anon",
    null,
    () =>
      db.query("select public.soolgyul_store_kind_spreads($1, $2::jsonb)", [
        secret,
        JSON.stringify(spreads),
      ]),
  );

const count = (bottles: number) => ({
  read_on: "2026-11-23",
  bottles,
  kinds: { red_wine: { bottles } },
});

const held = async (db: PGlite) =>
  (await db.query<{ bottles: number; spreads: { bottles: number } }>(
    "select bottles, spreads from public.catalog_kind_spreads",
  )).rows;

const expect = (actual: unknown, expected: unknown, label: string) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${label}: expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
};

Deno.test("catalog kind spreads", async (t) => {
  const db = await setUp();

  await t.step(
    "the job reads the published bottles a page at a time, in id order",
    async () => {
      const first = await page(db, SECRET, null, 2);
      expect(first.map((b) => b.id), [item(1), item(3)], "first page");
      expect(
        [
          first[0].category_key,
          first[0].style_key,
          first[0].region_key,
          first[0].grapes,
          first[0].sweetness,
          first[0].finish_character,
          first[0].aroma_tags,
        ],
        ["wine", "red_wine", "fr_bourgogne", ["pinot_noir"], 1, 2, ["cherry"]],
        "a bottle's facts",
      );
      // A bottle without a profile is counted, its levels empty.
      expect(first[1].sweetness, null, "no profile");
      const second = await page(db, SECRET, first[1].id, 2);
      expect(second.map((b) => b.id), [item(4)], "second page");
      expect(await page(db, SECRET, item(4), 2), [], "past the last");
    },
  );

  await t.step(
    "without the job's secret nothing is read or stored",
    async () => {
      for (const secret of ["wrong", ""]) {
        expect(
          await refusal(() => page(db, secret, null, 2)),
          "kind_spreads_job_refused",
          "read",
        );
        expect(
          await refusal(() => store(db, secret, count(100))),
          "kind_spreads_job_refused",
          "store",
        );
      }
      expect(
        await refusal(() => page(db, SECRET, null, 0)),
        "page_size_invalid",
        "page size",
      );
      // No client reads the row, and a signed-in member cannot call the job's functions.
      for (const role of ["anon", "authenticated"] as const) {
        const message = await refusal(() =>
          asRole(
            db,
            role,
            null,
            () => db.query("select 1 from public.catalog_kind_spreads"),
          )
        );
        if (!message?.includes("permission denied")) {
          throw new Error(`${role} read the row: ${message}`);
        }
      }
      const member = await refusal(() =>
        asRole(db, "authenticated", null, () =>
          db.query(
            "select public.soolgyul_store_kind_spreads($1, '{}'::jsonb)",
            [
              SECRET,
            ],
          ))
      );
      if (!member?.includes("permission denied")) {
        throw new Error(`a member stored a count: ${member}`);
      }
    },
  );

  await t.step(
    "a count replaces the one held; a broken or shrunken one is refused",
    async () => {
      expect(await held(db), [], "empty at first");
      await store(db, SECRET, count(1000));
      await store(db, SECRET, count(1200));
      const rows = await held(db);
      expect(
        rows.map((r) => [r.bottles, r.spreads.bottles]),
        [[1200, 1200]],
        "one row, the newest",
      );
      for (
        const broken of [
          "text",
          {},
          { bottles: 1200, kinds: {} },
          { kinds: { red_wine: {} } },
        ]
      ) {
        expect(
          await refusal(() => store(db, SECRET, broken)),
          "kind_spreads_invalid",
          JSON.stringify(broken),
        );
      }
      // Fewer than half the bottles of the count it would replace.
      expect(
        await refusal(() => store(db, SECRET, count(599))),
        "kind_spreads_too_few_bottles",
        "shrunken",
      );
      await store(db, SECRET, count(600));
      expect((await held(db)).map((r) => r.bottles), [600], "half is taken");
    },
  );

  await t.step("with no secret in the vault the job is refused", async () => {
    await db.exec("delete from vault.decrypted_secrets");
    expect(
      await refusal(() => page(db, SECRET, null, 2)),
      "kind_spreads_job_refused",
      "no vault secret",
    );
  });
});
