import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";

// The label word search folds text as the app and the models' training do
// (the fixture is the training side's fold), and finds a drink from a word
// read a letter off, with the rarity of each word of its names.

const FIXTURE = "test/fixtures/label_match.json";

const expect = (actual: unknown, expected: unknown, label: string) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${label}: expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
};

Deno.test("label word search", async (t) => {
  const db = await createSupabaseLikeDatabase();

  await t.step("soolgyul_label_fold matches the training fold", async () => {
    const folds = (JSON.parse(await Deno.readTextFile(FIXTURE)) as {
      folds: Record<string, string>;
    }).folds;
    const mismatches: string[] = [];
    for (const [input, expected] of Object.entries(folds)) {
      const { rows } = await db.query<{ folded: string }>(
        "select public.soolgyul_label_fold($1) as folded",
        [input],
      );
      if (rows[0].folded !== expected) {
        mismatches.push(
          `${JSON.stringify(input)}: sql=${rows[0].folded} py=${expected}`,
        );
      }
    }
    if (mismatches.length) throw new Error(mismatches.join("\n"));
  });

  await t.step(
    "a word read a letter off finds the drink, with its words' rarity",
    async () => {
      await db.exec(`
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('c0000000-0000-4000-8000-000000000001', 'wine', '와인', 1);
    insert into public.alcohol_items (id, name_ko, name_en, alcohol_category_id, publish_status, published_at)
      select ('e0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
        '와인 ' || n, 'Filler Wine ' || n,
        'c0000000-0000-4000-8000-000000000001', 'published', now()
      from generate_series(100, 160) as n;
    insert into public.alcohol_items (id, name_ko, name_en, alcohol_category_id, publish_status, published_at)
      values
      ('e0000000-0000-4000-8000-000000000001', '케이머스 까베르네 소비뇽 2019', 'Caymus Cabernet Sauvignon 2019', 'c0000000-0000-4000-8000-000000000001', 'published', now()),
      ('e0000000-0000-4000-8000-000000000002', '글렌 그란트 아르보랄리스', 'Glen Grant Arboralis', 'c0000000-0000-4000-8000-000000000001', 'published', now()),
      ('e0000000-0000-4000-8000-000000000003', '숨은 케이머스', 'Hidden Caymus', 'c0000000-0000-4000-8000-000000000001', 'staging', null);
    select public.soolgyul_refresh_label_words();
  `);
      const search = async (words: string[], also: string[] = []) => {
        const { rows } = await db.query<
          {
            name_ko: string;
            found: number;
            name_rarity: Record<string, number>;
          }
        >(
          "select name_ko, found, name_rarity from public.soolgyul_search_alcohol_catalog_by_label_words($1, $2)",
          [words, also],
        );
        return rows;
      };
      const caymus = await search(["CAYMU5", "napa", "valley"]);
      expect(
        caymus.map((row) => row.name_ko),
        ["케이머스 까베르네 소비뇽 2019"],
        "a word a letter off, the unpublished bottle left out",
      );
      expect(
        Object.keys(caymus[0].name_rarity).sort(),
        ["까베르네", "cabernet", "caymus", "sauvignon", "소비뇽", "케이머스"]
          .sort(),
        "every word of both names, the year left off",
      );
      if (!(caymus[0].found > 0)) throw new Error("found is not positive");

      expect(
        (await search(["glengrant"])).map((row) => row.name_ko),
        ["글렌 그란트 아르보랄리스"],
        "two name words read as one",
      );
      const also = await search(["zzzz"], [
        "e0000000-0000-4000-8000-000000000002",
      ]);
      expect(
        also.map((row) => [row.name_ko, row.found]),
        [["글렌 그란트 아르보랄리스", 0]],
        "a drink the line search found comes whatever its words",
      );
    },
  );

  await t.step(
    "the kept rarities equal the ones worked out, and a drink listed since is worked out",
    async () => {
      const { rows: kept } = await db.query<{ differing: number }>(`
        select count(*)::int as differing
        from public.catalog_label_name_rarity as kept
        join public.alcohol_items as item on item.id = kept.alcohol_item_id
        where kept.name_rarity is distinct from public.soolgyul_label_name_rarity(item.name_en, item.name_ko)
      `);
      expect(kept[0].differing, 0, "kept and worked out agree");
      await db.exec(`
        insert into public.alcohol_items (id, name_ko, name_en, alcohol_category_id, publish_status, published_at)
          values ('e0000000-0000-4000-8000-000000000004', '케이머스 스페셜 셀렉션', 'Caymus Special Selection', 'c0000000-0000-4000-8000-000000000001', 'published', now());
      `);
      const { rows } = await db.query<
        { name_ko: string; name_rarity: Record<string, number | null> }
      >(
        "select name_ko, name_rarity from public.soolgyul_search_alcohol_catalog_by_label_words($1, $2)",
        [["zzzz"], ["e0000000-0000-4000-8000-000000000004"]],
      );
      expect(
        rows.map((row) => [row.name_ko, Object.keys(row.name_rarity).sort()]),
        [[
          "케이머스 스페셜 셀렉션",
          [
            "caymus",
            "selection",
            "special",
            "셀렉션",
            "스페셜",
            "케이머스",
          ].sort(),
        ]],
        "its words come though the night's making has not seen it",
      );
    },
  );

  await t.step("only the word search is open to the app", async () => {
    const { rows: keptOpen } = await db.query<{ granted: boolean }>(
      "select has_table_privilege('anon', 'public.catalog_label_name_rarity', 'select') as granted",
    );
    expect(keptOpen[0].granted, false, "the kept rarities are not readable");

    const { rows } = await db.query<{ granted: boolean }>(
      "select has_table_privilege('anon', 'public.catalog_label_words', 'select') as granted",
    );
    expect(rows[0].granted, false, "the word table is not readable");
  });

  await db.close();
});
