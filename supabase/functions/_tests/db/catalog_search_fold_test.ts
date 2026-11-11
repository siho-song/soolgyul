import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";

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
      expect(
        await names("프레이 소비뇽"),
        [
          "프레이 브라더스 까베르네 소비뇽",
          "프레이 브라더스 쇼비뇽 블랑",
        ],
        "words may come from the name in any order; the name spelled as typed first",
      );
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

  await t.step(
    "the order of matches, the kind of drink said, guesses and drinks not carried",
    async () => {
      const wine = "c0000000-0000-4000-8000-000000000001";
      const whisky = "c0000000-0000-4000-8000-000000000002";
      const item = (n: number) =>
        `f0000000-0000-4000-8000-0000000000${String(n).padStart(2, "0")}`;
      await db.exec(`
        insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
          values ('${whisky}', 'whisky', '위스키', 2);
        insert into public.alcohol_items (id, name_ko, name_en, alcohol_category_id, vintage_year, publish_status, published_at) values
          ('${
        item(1)
      }', '발렌타인 12년', 'Ballantine''s 12', '${whisky}', null, 'published', now()),
          ('${
        item(2)
      }', '발렌타인 마스터스', 'Ballantine''s Master''s', '${whisky}', null, 'published', now()),
          ('${
        item(3)
      }', '발렌타인 파이니스트', 'Ballantine''s Finest', '${whisky}', null, 'published', now()),
          ('${
        item(4)
      }', '미스 발렌타인 로제', 'Miss Valentine Rose', '${wine}', null, 'published', now()),
          ('${
        item(5)
      }', '샤또 마고 2019', 'Chateau Margaux', '${wine}', 2019, 'published', now()),
          ('${
        item(6)
      }', '샤또 마고 2021', 'Chateau Margaux', '${wine}', 2021, 'published', now()),
          ('${
        item(7)
      }', '둘롱 보르도', 'Dulong Bordeaux', '${wine}', null, 'published', now()),
          ('${
        item(8)
      }', '포도 막걸리', null, '${wine}', null, 'published', now()),
          ('${
        item(9)
      }', '잭 다니엘스 테네시 라이', 'Jack Daniel''s Tennessee Rye', '${whisky}', null, 'published', now()),
          ('${
        item(10)
      }', '테라 나뚜라', 'Terra Natura', '${wine}', null, 'published', now()),
          ('${
        item(11)
      }', '카스텔로 반피', 'Castello Banfi', '${wine}', null, 'published', now());
        insert into public.catalog_search_signals (alcohol_item_id, known)
          values ('${item(1)}', true);
      `);
      const found = async (query: string) =>
        (await db.query<{ name_ko: string; match_kind: string }>(
          "select name_ko, match_kind from public.soolgyul_search_alcohol_catalog($1, 20)",
          [query],
        )).rows;
      const names = async (query: string) =>
        (await found(query)).map((row) => row.name_ko);
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
        await names("발렌타인"),
        [
          "발렌타인 12년",
          "발렌타인 마스터스",
          "발렌타인 파이니스트",
          "미스 발렌타인 로제",
        ],
        "the known bottle, then names that begin with the word, then names that only hold it",
      );
      expect(await found("보르도"), [
        { name_ko: "둘롱 보르도", match_kind: "exact" },
        { name_ko: "포도 막걸리", match_kind: "sound" },
      ], "the name spelled as typed before the one that only sounds alike");
      expect(
        await names("샤또 마고"),
        ["샤또 마고 2021", "샤또 마고 2019"],
        "of one wine the recent year first",
      );

      expect(
        await names("발렌타인 위스키"),
        ["발렌타인 12년", "발렌타인 마스터스", "발렌타인 파이니스트"],
        "a kind of drink said with a name narrows the search",
      );
      expect(
        await names("위스키"),
        ["발렌타인 12년"],
        "a kind of drink alone lists the known bottles of that kind",
      );
      expect(
        await names("포도 위스키"),
        [],
        "no bottle of that kind, and none named so either",
      );

      expect(
        await found("발렌타임"),
        [
          { name_ko: "발렌타인 12년", match_kind: "near" },
          { name_ko: "발렌타인 마스터스", match_kind: "near" },
          { name_ko: "미스 발렌타인 로제", match_kind: "near" },
          { name_ko: "발렌타인 파이니스트", match_kind: "near" },
        ],
        "a slip of one letter is answered as a guess: the known bottle, then the shorter name",
      );
      expect(
        await names("헤네시"),
        [],
        "a word that differs in its first letter is not a guess",
      );

      expect(
        (await found("샤떠 마고")).map((row) => [row.name_ko, row.match_kind])
          .sort(),
        [["샤또 마고 2019", "near"], ["샤또 마고 2021", "near"]],
        "one slip in a short word of a longer name is still a guess",
      );
      expect(
        await names("마거"),
        [],
        "a short word alone is not guessed from one slip",
      );

      const screen = async (query: string) =>
        (await db.query<
          {
            answer: {
              not_carried: string | null;
              results: { name_ko: string; match_kind: string }[];
            };
          }
        >("select public.soolgyul_search_catalog($1) as answer", [query]))
          .rows[0].answer;
      const whiskies = await screen("발렌타인");
      expect(whiskies.not_carried, null, "a carried drink is not announced");
      expect(
        whiskies.results.map((row) => [row.name_ko, row.match_kind]),
        (await found("발렌타인")).map((row) => [row.name_ko, row.match_kind]),
        "the screen's answer holds the search's rows in order",
      );
      const brandy = await screen("헤네시 xo");
      expect(
        [brandy.not_carried, brandy.results],
        ["brandy", []],
        "a drink the catalog does not carry is named by its kind",
      );
      const beer = await screen("맥주 보르도");
      expect(beer.not_carried, "beer", "the first word names the kind");
      expect(
        beer.results.map((row) => row.name_ko),
        [],
        "nothing is spelled with both words",
      );
      const missing = await screen("이강주");
      expect(
        [missing.not_carried, missing.results],
        ["not_listed", []],
        "a well-known bottle the catalog lacks is said to be not listed yet",
      );
      const cass = await screen("카스");
      expect(
        [cass.not_carried, cass.results],
        ["beer", []],
        "said alone, it is not answered with a name that only holds the word",
      );
      const cassAndMore = await screen("카스 반피");
      expect(
        [
          cassAndMore.not_carried,
          cassAndMore.results.map((row) => row.name_ko),
        ],
        ["beer", ["카스텔로 반피"]],
        "with more words, bottles spelled with all of them are answered",
      );
      expect(
        (await screen("테라")).not_carried,
        null,
        "a word that leads a carried bottle's name is never on the list",
      );

      // Members who pick a bottle raise it; a visitor does not.
      const member = "a0000000-0000-4000-8000-0000000000aa";
      await db.exec(`
        insert into auth.users (id, email, raw_app_meta_data)
          values ('${member}', 'picker@example.test', '{"provider":"kakao"}');
        insert into public.drink_discovery_events (kind, surface, alcohol_item_id, user_id) values
          ('search_pick', 'taste_fit', '${item(3)}', '${member}'),
          ('fit_view', 'taste_fit', '${item(3)}', '${member}'),
          ('search_pick', 'taste_fit', '${item(2)}', null);
        select public.soolgyul_refresh_catalog_search_picks();
      `);
      expect(
        (await db.query(
          `select alcohol_item_id::text as id, picks from public.catalog_search_signals
           where picks > 0`,
        )).rows,
        [{ id: item(3), picks: 1 }],
        "one member counts once, a visitor not at all",
      );
      expect(
        (await names("발렌타인")).slice(0, 3),
        ["발렌타인 12년", "발렌타인 파이니스트", "발렌타인 마스터스"],
        "a picked bottle comes before one nobody picked",
      );
      await db.exec(`
        delete from public.drink_discovery_events where user_id = '${member}';
        select public.soolgyul_refresh_catalog_search_picks();
      `);
      expect(
        (await db.query(
          "select count(*)::int as n from public.catalog_search_signals where picks > 0",
        )).rows,
        [{ n: 0 }],
        "picks that aged out are forgotten",
      );
    },
  );

  await t.step(
    "words inside a name, words said another way, countries and styles",
    async () => {
      const wine = "c0000000-0000-4000-8000-000000000001";
      const whisky = "c0000000-0000-4000-8000-000000000002";
      const item = (n: number) =>
        `f0000000-0000-4000-8000-0000000000${String(n).padStart(2, "0")}`;
      const traditional = "c0000000-0000-4000-8000-000000000003";
      await db.exec(`
        insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
          values ('${traditional}', 'korean_traditional', '전통주', 3);
        insert into public.alcohol_items (id, name_ko, name_en, alcohol_category_id, country_code, style_key, publish_status, published_at) values
          ('${
        item(21)
      }', '원소주 스피릿', 'Won Soju Spirit', '${whisky}', 'KR', null, 'published', now()),
          ('${
        item(22)
      }', '지평탁주', null, '${traditional}', 'KR', 'takju', 'published', now()),
          ('${
        item(23)
      }', '몬테스 알파 M', 'Montes Alpha M', '${wine}', 'CL', null, 'published', now()),
          ('${
        item(24)
      }', '조니워커 블랙 라벨', 'Johnnie Walker Black Label', '${whisky}', 'GB', null, 'published', now()),
          ('${
        item(25)
      }', '닛카 프롬 더 배럴', 'Nikka From the Barrel', '${whisky}', 'JP', null, 'published', now()),
          ('${
        item(26)
      }', '카테나 니카시아 말벡', 'Catena Nicasia Malbec', '${wine}', 'AR', null, 'published', now()),
          ('${
        item(27)
      }', '화요 41', 'Hwayo 41', '${whisky}', 'KR', null, 'published', now());
        insert into public.alcohol_items (id, name_ko, alcohol_category_id, publish_status, published_at) values
          ('${item(28)}', '와일드 터키 81', '${whisky}', 'published', now()),
          ('${item(29)}', '와일드 터키 101', '${whisky}', 'published', now());
        insert into public.catalog_search_signals (alcohol_item_id, known, staple) values
          ('${item(23)}', true, false), ('${item(25)}', true, false),
          ('${item(28)}', true, false), ('${item(29)}', true, true);
      `);
      const found = async (query: string) =>
        (await db.query<{ name_ko: string; match_kind: string }>(
          "select name_ko, match_kind from public.soolgyul_search_alcohol_catalog($1, 20)",
          [query],
        )).rows.map((row) => [row.name_ko, row.match_kind]);
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
        await found("주스"),
        [],
        "a word is not pieced from the end of one name word and the start of the next",
      );
      expect(
        await found("조니워커블랙"),
        [["조니워커 블랙 라벨", "exact"]],
        "a name run together is found from the start of a word",
      );
      expect(
        await found("블랙라벨"),
        [["조니워커 블랙 라벨", "exact"]],
        "also from the start of a later word",
      );
      expect(
        await found("더 조니워커"),
        [["조니워커 블랙 라벨", "exact"]],
        "'더' before a name is not looked for",
      );
      expect(
        await found("화요 41도"),
        [["화요 41", "exact"]],
        "a number is found without what is added to it",
      );
      expect(
        await found("몬테스 알파 엠"),
        [["몬테스 알파 M", "exact"]],
        "a letter is found by its Korean name",
      );
      expect(
        await found("조니블랙"),
        [["조니워커 블랙 라벨", "near"]],
        "two shortened words run together are a guess",
      );
      expect(
        await found("지평 막걸리"),
        [["지평탁주", "exact"]],
        "a style said with a name is met by the bottle's style",
      );
      expect(
        await found("칠레 와인"),
        [["몬테스 알파 M", "exact"]],
        "a country and a kind list that country's known bottles",
      );
      expect(
        await found("아르헨티나 말벡"),
        [["카테나 니카시아 말벡", "exact"]],
        "a country said with a name narrows the search",
      );
      expect(
        await found("니카"),
        [["닛카 프롬 더 배럴", "sound"], ["카테나 니카시아 말벡", "exact"]],
        "a known bottle that begins as the word sounds comes before a stray spelling",
      );
      expect(
        await found("와턱"),
        [["와일드 터키 101", "exact"], ["와일드 터키 81", "exact"]],
        "a nickname is looked for as what it means, the everyday bottle first",
      );
      expect(
        (await found("화")).map((row) => row[0]),
        ["화요 41"],
        "a single syllable has to begin a word",
      );
    },
  );

  await t.step(
    "several searches in one call answer each as the single search does",
    async () => {
      const queries = ["소비뇽", "zzqqxx", "부르고뉴 루즈"];
      const { rows } = await db.query<
        { query_index: number; name_ko: string; media_path: string | null }
      >(
        "select query_index, name_ko, media_path from public.soolgyul_search_alcohol_catalog_batch($1, 20)",
        [queries],
      );
      for (let index = 0; index < queries.length; index++) {
        const single = await db.query<{ name_ko: string }>(
          "select name_ko from public.soolgyul_search_alcohol_catalog($1, 20)",
          [queries[index]],
        );
        const batched = rows.filter((row) => row.query_index === index + 1);
        if (
          JSON.stringify(batched.map((row) => row.name_ko)) !==
            JSON.stringify(single.rows.map((row) => row.name_ko))
        ) {
          throw new Error(
            `query ${queries[index]}: ${JSON.stringify(batched)}`,
          );
        }
      }
      const photo = rows.find((row) => row.name_ko === "부르고뉴 루즈");
      if (
        photo?.media_path !== "wine/e0000000-0000-4000-8000-000000000001.webp"
      ) {
        throw new Error(`photo: ${JSON.stringify(photo)}`);
      }
    },
  );

  await db.close();
});
