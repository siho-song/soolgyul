import { createSupabaseLikeDatabase } from "./helpers/pglite_supabase.ts";

// The name search folds Korean transliteration variants: the SQL fold must
// equal the Python fold (fixture) and the RPC must find a product however the
// user spelled it.

const FIXTURE = "supabase/functions/_tests/fixtures/korean_sound_fold.json";

Deno.test("catalog search", async (t) => {
  const db = await createSupabaseLikeDatabase();

  await t.step(
    "soolgyul_fold_korean_sound matches the Python fold fixture",
    async () => {
      const fixture = JSON.parse(await Deno.readTextFile(FIXTURE)) as Record<
        string,
        string
      >;
      const mismatches: string[] = [];
      for (const [input, expected] of Object.entries(fixture)) {
        const { rows } = await db.query<{ folded: string }>(
          "select public.soolgyul_fold_korean_sound($1) as folded",
          [input],
        );
        if (rows[0].folded !== expected) {
          mismatches.push(
            `${JSON.stringify(input)}: sql=${rows[0].folded} py=${expected}`,
          );
        }
      }
      if (mismatches.length) {
        throw new Error(
          mismatches.slice(0, 10).join("\n"),
        );
      }
    },
  );

  await t.step(
    "search finds a product under other spellings of its name or its producer",
    async () => {
      await db.exec(`
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('c0000000-0000-4000-8000-000000000001', 'wine', '와인', 1);
    insert into public.producers (id, producer_key, name_ko, name_en) values
      ('d0000000-0000-4000-8000-000000000001', 'domaine_cuchon', '도멘 뀌숑', 'Domaine Cuchon'),
      ('d0000000-0000-4000-8000-000000000002', 'frei_brothers', '프레이 브라더스', 'Frei Brothers');
    insert into public.alcohol_items (id, name_ko, name_en, producer_id, alcohol_category_id, publish_status, published_at)
      values
      ('e0000000-0000-4000-8000-000000000001', '부르고뉴 루즈', 'Bourgogne Rouge', 'd0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', 'published', now()),
      ('e0000000-0000-4000-8000-000000000002', '프레이 브라더스 까베르네 소비뇽', 'Frei Brothers Cabernet Sauvignon', 'd0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000001', 'published', now()),
      ('e0000000-0000-4000-8000-000000000003', '하디스 키사이드 샤르도네', null, null, 'c0000000-0000-4000-8000-000000000001', 'published', now()),
      ('e0000000-0000-4000-8000-000000000004', '숨은 병 피노 누아', null, null, 'c0000000-0000-4000-8000-000000000001', 'staging', null),
      ('e0000000-0000-4000-8000-000000000005', '샤또 네넹', 'Chateau Nenin', null, 'c0000000-0000-4000-8000-000000000001', 'published', now()),
      ('e0000000-0000-4000-8000-000000000006', '프레이 브라더스 쇼비뇽 블랑', 'Frei Brothers Sauvignon Blanc', 'd0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000001', 'published', now());
    -- the style red_wine and the region tree (fr > fr_bourgogne) are seeded by migrations
    update public.alcohol_items set style_key = 'red_wine', country_code = 'FR', region_key = 'fr_bourgogne' where id = 'e0000000-0000-4000-8000-000000000001';
    insert into public.catalog_media_assets (alcohol_item_id, media_path, publish_status, published_at)
      values ('e0000000-0000-4000-8000-000000000001', 'wine/e0000000-0000-4000-8000-000000000001.webp', 'published', now());
  `);
      const names = async (query: string) => {
        const { rows } = await db.query<{ name_ko: string }>(
          "select name_ko from public.soolgyul_search_alcohol_catalog($1, 20)",
          [query],
        );
        return rows.map((row) => row.name_ko);
      };
      const expect = (actual: unknown, expected: unknown, label: string) => {
        if (JSON.stringify(actual) !== JSON.stringify(expected)) {
          throw new Error(
            `${label}: expected ${JSON.stringify(expected)}, received ${
              JSON.stringify(actual)
            }`,
          );
        }
      };
      expect(
        await names("퀴숑"),
        ["부르고뉴 루즈"],
        "tense/plain consonant, through the producer",
      );
      const { rows: labelled } = await db.query<
        { name_ko: string; style_label: string }
      >(
        "select name_ko, style_label from public.soolgyul_search_alcohol_catalog($1, 20) order by name_ko",
        ["샤"],
      );
      expect(
        labelled,
        [
          { name_ko: "샤또 네넹", style_label: "와인" },
          { name_ko: "하디스 키사이드 샤르도네", style_label: "와인" },
        ],
        "a style without a term falls back to the category name",
      );
      const { rows: styled } = await db.query<
        {
          style_label: string;
          media_path: string;
          country_code: string;
          region: string;
        }
      >(
        "select style_label, media_path, country_code, region from public.soolgyul_search_alcohol_catalog($1, 20)",
        ["부르고뉴"],
      );
      expect(
        styled,
        [{
          style_label: "레드 와인",
          media_path: "wine/e0000000-0000-4000-8000-000000000001.webp",
          country_code: "FR",
          region: "부르고뉴",
        }],
        "style term label, published photo path, country and region",
      );
      expect(await names("쿠숑"), [], "a different vowel stays different");
      expect(
        await names("카베르네소비뇽"),
        ["프레이 브라더스 까베르네 소비뇽"],
        "spacing and consonant",
      );
      expect(
        await names("까베네 소비뇽"),
        ["프레이 브라더스 까베르네 소비뇽"],
        "dropped 르",
      );
      expect(
        [...await names("소비뇽")].sort(),
        ["프레이 브라더스 까베르네 소비뇽", "프레이 브라더스 쇼비뇽 블랑"],
        "쇼비뇽 folds to 소비뇽, in either order",
      );
      const chardonnay = await names("샤도네이");
      expect(
        [...chardonnay].sort(),
        ["샤또 네넹", "하디스 키사이드 샤르도네"],
        "르 insertion and trailing 이",
      );
      if (
        chardonnay.indexOf("하디스 키사이드 샤르도네") >
          chardonnay.indexOf("샤또 네넹")
      ) {
        throw new Error(
          `a whole name word must outrank a substring across words: ${chardonnay}`,
        );
      }
      expect(await names("chardonnay"), [], "english does not fold to korean");
      expect(await names("Cuchon"), ["부르고뉴 루즈"], "english producer name");
      expect(
        await names("브라더스 블랑"),
        ["프레이 브라더스 쇼비뇽 블랑"],
        "every query word must appear, in the name or the producer",
      );
      expect(await names("프레이 소비뇽"), [
        "프레이 브라더스 쇼비뇽 블랑",
        "프레이 브라더스 까베르네 소비뇽",
      ], "words may come from the name in any order");
      expect(await names("피노 누아"), [], "unpublished rows stay hidden");
      expect(await names(""), [], "empty query");
      const page = async (limit: number, offset: number) => {
        const { rows } = await db.query<{ name_ko: string }>(
          "select name_ko from public.soolgyul_search_alcohol_catalog($1, $2, $3)",
          ["프레이", limit, offset],
        );
        return rows.map((row) => row.name_ko);
      };
      expect(
        [...await page(1, 0), ...await page(1, 1)],
        await page(20, 0),
        "an offset continues the same order without overlap",
      );
      expect(await page(20, 2), [], "an offset past the last match is empty");
    },
  );

  await t.step(
    "fuzzy fallback and producers' native names",
    async () => {
      const names = async (query: string) => {
        const { rows } = await db.query<{ name_ko: string }>(
          "select name_ko from public.soolgyul_search_alcohol_catalog($1, 20)",
          [query],
        );
        return rows.map((row) => row.name_ko);
      };
      const expect = (actual: unknown, expected: unknown, label: string) => {
        if (JSON.stringify(actual) !== JSON.stringify(expected)) {
          throw new Error(
            `${label}: expected ${JSON.stringify(expected)}, received ${
              JSON.stringify(actual)
            }`,
          );
        }
      };

      // A label photo read on the device misses a letter now and then; when no
      // product holds every word, nearly holding every word is enough.
      expect(
        await names("Domaime Cuchon"),
        ["부르고뉴 루즈"],
        "one wrong latin letter still finds the producer",
      );
      expect(
        await names("브라더수 블랑"),
        ["프레이 브라더스 쇼비뇽 블랑"],
        "one wrong jamo, every word still nearly present",
      );
      expect(
        await names("브라더수"),
        ["프레이 브라더스 쇼비뇽 블랑", "프레이 브라더스 까베르네 소비뇽"],
        "fuzzy rows rank by similarity, then name length",
      );
      expect(await names("zzqqxx"), [], "an unrelated word finds nothing");

      // A sake label shows the brand in Japanese; the producer's native name
      // joins its folded search text.
      await db.exec(`
        insert into public.producers (id, producer_key, name_ko, name_en, name_native)
          values ('d0000000-0000-4000-8000-000000000003', 'kaze_no_mori', '카제노모리', 'Kaze no Mori', '風の森');
        insert into public.alcohol_items (id, name_ko, name_en, producer_id, alcohol_category_id, publish_status, published_at)
          values ('e0000000-0000-4000-8000-000000000007', '카제노모리 아키츠호 657', 'Kaze no Mori Akitsuho 657', 'd0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000001', 'published', now());
      `);
      expect(
        await names("風の森"),
        ["카제노모리 아키츠호 657"],
        "the Japanese brand on the label finds the producer's products",
      );
      expect(
        await names("風の森 657"),
        ["카제노모리 아키츠호 657"],
        "a Japanese word and a number together",
      );
      expect(
        [...await names("소비뇽")].sort(),
        ["프레이 브라더스 까베르네 소비뇽", "프레이 브라더스 쇼비뇽 블랑"],
        "exact matches never mix with fuzzy ones",
      );
    },
  );

  await db.close();
});
