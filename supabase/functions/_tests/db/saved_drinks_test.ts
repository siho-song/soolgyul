import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { asRole, asUser, refusal, sortedJson } from "../helpers/db_session.ts";
import { same } from "../helpers/assert.ts";

// 저장한 술: a member who finished signing up saves a published bottle with
// the badge the fit page showed, takes it out again, and reads the list as
// search rows, newest first. Nobody else reads it, and no client writes the
// table itself.

const OWNER = "a0000000-0000-4000-8000-000000000071";
const STRANGER = "a0000000-0000-4000-8000-000000000072";
const UNFINISHED = "a0000000-0000-4000-8000-000000000073";
const WINE = "c0000000-0000-4000-8000-000000000021";
const SHOWN = "b0000000-0000-4000-8000-000000000021";
const SECOND = "b0000000-0000-4000-8000-000000000022";
const DRAFT = "b0000000-0000-4000-8000-000000000023";

async function setUp(): Promise<PGlite> {
  const db = await createSupabaseLikeDatabase();
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${OWNER}', 'owner@example.test', '{"provider":"kakao"}', now()),
      ('${STRANGER}', 'stranger@example.test', '{"provider":"kakao"}', now()),
      ('${UNFINISHED}', 'unfinished@example.test', '{"provider":"kakao"}', now());
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order, interest_key) values
      ('${WINE}', 'wine', '와인', 1, 'wine');
    insert into public.alcohol_items
      (id, name_ko, name_en, alcohol_category_id, abv_percent, country_code, publish_status, published_at)
    values
      ('${SHOWN}', '샤토 테스트', 'Chateau Test', '${WINE}', 13.5, 'FR', 'published', now()),
      ('${SECOND}', '두 번째 병', null, '${WINE}', null, null, 'published', now()),
      ('${DRAFT}', '아직 안 나온 병', null, '${WINE}', null, null, 'staging', null);
    insert into public.catalog_media_assets (alcohol_item_id, media_path, publish_status, published_at) values
      ('${SHOWN}', 'wine/${SHOWN}.webp', 'published', now());
  `);
  for (const [user, name] of [[OWNER, "주인장"], [STRANGER, "손님"]]) {
    await asUser(db, user, () =>
      db.query(
        `select public.soolgyul_complete_my_profile(
           gen_random_uuid(), $1, date '1990-03-21', true, 'soolgyul-terms-v1',
           'soolgyul-privacy-v1', 'soolgyul-marketing-v1', true, true, false)`,
        [name],
      ));
  }
  return db;
}

type Page = {
  total: number;
  drinks: {
    id: string;
    name_ko: string;
    name_en: string | null;
    category_key: string;
    style_label: string;
    abv_percent: number | null;
    media_path: string | null;
    country_code: string | null;
  }[];
};

const save = (db: PGlite, item: string, badge: string | null = null) =>
  db.query("select public.soolgyul_save_my_drink($1, $2)", [item, badge]);
const unsave = (db: PGlite, item: string) =>
  db.query("select public.soolgyul_unsave_my_drink($1)", [item]);
async function list(db: PGlite, offset = 0, limit = 30): Promise<Page> {
  const { rows } = await db.query<{ page: Page }>(
    "select public.soolgyul_my_saved_drinks($1, $2) as page",
    [offset, limit],
  );
  return rows[0].page;
}

Deno.test("a member saves a bottle with its badge, lists it and takes it out", async () => {
  const db = await setUp();
  try {
    await asUser(db, OWNER, async () => {
      await save(db, SHOWN, "star");
      // Saving again changes neither the day nor the badge shown first.
      await save(db, SHOWN, "caution");
      await save(db, SECOND);
    });
    await db.exec(`
      update public.user_saved_drinks set created_at = '2026-11-01T00:00:00Z'
        where alcohol_item_id = '${SHOWN}';
      update public.user_saved_drinks set created_at = '2026-11-02T00:00:00Z'
        where alcohol_item_id = '${SECOND}';
    `);
    const kept = await db.query<{ item: string; fit_badge: string | null }>(
      `select alcohol_item_id::text as item, fit_badge from public.user_saved_drinks
       order by created_at`,
    );
    same(kept.rows, [
      { item: SHOWN, fit_badge: "star" },
      { item: SECOND, fit_badge: null },
    ], "kept rows");

    await asUser(db, OWNER, async () => {
      const page = await list(db);
      same(page.total, 2, "total");
      same(
        page.drinks.map((drink) => drink.id),
        [SECOND, SHOWN],
        "newest first",
      );
      // jsonb hands the keys back in its own order.
      same(
        sortedJson(page.drinks[1]),
        sortedJson({
          id: SHOWN,
          saved_at:
            (page.drinks[1] as unknown as { saved_at: string }).saved_at,
          name_ko: "샤토 테스트",
          name_en: "Chateau Test",
          category_key: "wine",
          style_key: null,
          style_label: "와인",
          abv_percent: 13.5,
          media_path: `wine/${SHOWN}.webp`,
          country_code: "FR",
          region: null,
        }),
        "a search row",
      );
      same(
        (await list(db, 1, 1)).drinks.map((drink) => drink.id),
        [SHOWN],
        "second page",
      );

      // The owner reads the rows: the heart's state and the profile's count.
      const own = await db.query(
        "select alcohol_item_id from public.user_saved_drinks",
      );
      same(own.rows.length, 2, "owner reads own rows");

      await unsave(db, SECOND);
      await unsave(db, SECOND);
      same(
        (await list(db)).drinks.map((drink) => drink.id),
        [SHOWN],
        "taken out",
      );
    });

    // A bottle taken off the shelf leaves the list and comes back with it.
    await db.exec(
      `update public.alcohol_items set publish_status = 'withdrawn' where id = '${SHOWN}'`,
    );
    await asUser(db, OWNER, async () => {
      same((await list(db)).total, 0, "an unpublished bottle is not listed");
    });
  } finally {
    await db.close();
  }
});

Deno.test("saved bottles are the owner's alone, and only a finished sign-up saves", async () => {
  const db = await setUp();
  try {
    await asUser(db, OWNER, () => save(db, SHOWN, "neutral"));

    await asUser(db, STRANGER, async () => {
      same((await list(db)).total, 0, "a stranger's list is empty");
      const rows = await db.query("select * from public.user_saved_drinks");
      same(rows.rows.length, 0, "a stranger reads no rows");
      // Taking out what one never saved touches nobody else's.
      await unsave(db, SHOWN);
    });
    const still = await db.query("select 1 from public.user_saved_drinks");
    same(still.rows.length, 1, "the owner's row is still there");

    await asUser(db, OWNER, async () => {
      for (
        const [call, message] of [
          [() => save(db, DRAFT), "drink_not_found"],
          [
            () => save(db, "b0000000-0000-4000-8000-0000000000ff"),
            "drink_not_found",
          ],
          [() => save(db, SHOWN, "great"), "fit_badge_invalid"],
          // The table takes no write from a client, only the functions do.
          [
            () =>
              db.query(
                `insert into public.user_saved_drinks (user_id, alcohol_item_id)
                 values ('${OWNER}', '${SECOND}')`,
              ),
            "permission denied",
          ],
          [
            () => db.query("delete from public.user_saved_drinks"),
            "permission denied",
          ],
        ] as [() => Promise<unknown>, string][]
      ) {
        const refused = await refusal(call);
        if (!refused?.includes(message)) {
          throw new Error(`expected ${message}, got ${refused}`);
        }
      }
    });

    await asUser(db, UNFINISHED, async () => {
      const refused = await refusal(() => save(db, SHOWN));
      if (!refused?.includes("active_account_required")) {
        throw new Error(`an unfinished sign-up saved: ${refused}`);
      }
    });

    await asRole(db, "anon", null, async () => {
      for (
        const call of [
          () => save(db, SHOWN),
          () => unsave(db, SHOWN),
          () => list(db),
          () => db.query("select * from public.user_saved_drinks"),
        ]
      ) {
        const refused = await refusal(call);
        if (!refused?.includes("permission denied")) {
          throw new Error(`a visitor reached saved drinks: ${refused}`);
        }
      }
    });

    // The list goes with the account.
    await db.exec(`delete from auth.users where id = '${OWNER}'`);
    const left = await db.query("select 1 from public.user_saved_drinks");
    same(left.rows.length, 0, "the account's rows go with it");
  } finally {
    await db.close();
  }
});
