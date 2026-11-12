import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";

// The 저장한 술결 카드 screen reads the owner's liked cards through one RPC:
// newest like first by default, one page plus the total, with the catalog
// name and interest key the client may not read itself. Other people's
// likes and other interests are left out. Each row carries
// the card's id and the line the list shows: its brief, else its summary.

const OWNER = "a0000000-0000-4000-8000-000000000061";
const STRANGER = "a0000000-0000-4000-8000-000000000062";
const WINE = "c0000000-0000-4000-8000-000000000011";
const SAKE = "c0000000-0000-4000-8000-000000000012";
const WINE_ITEM = "b0000000-0000-4000-8000-000000000011";
const SAKE_ITEM = "b0000000-0000-4000-8000-000000000012";

async function asUser(db: PGlite, user: string, work: () => Promise<void>) {
  await db.exec("set role authenticated;");
  await db.query("select set_config('request.jwt.claims', $1, false)", [
    JSON.stringify({ sub: user }),
  ]);
  try {
    await work();
  } finally {
    await db.exec("reset role;");
  }
}

let seq = 0;
async function likedRecord(
  db: PGlite,
  user: string,
  item: string,
  likedAt: string,
  options: { note?: string; brief?: string } = {},
): Promise<string> {
  seq += 1;
  const id = String(seq).padStart(12, "0");
  const recordId = `d0000000-0000-4000-8000-${id}`;
  await db.query(
    `insert into public.drink_records
       (id, user_id, alcohol_item_id, questionnaire_version, created_at, one_line_note)
     values ($1, $2, $3, 'sensory-questionnaire-v1', '2026-06-01T12:00:00Z', $4)`,
    [recordId, user, item, options.note ?? null],
  );
  await db.query(
    `insert into public.taste_cards (id, drink_record_id, snapshot_id, snapshot_ref, lifecycle,
       canonical_schema_version, semantic_snapshot, rendered_snapshot)
     values ($1, $2, gen_random_uuid(), $3, 'final', 'test', '{}'::jsonb, $4::jsonb)`,
    [
      `e0000000-0000-4000-8000-${id}`,
      recordId,
      id.padStart(64, "f"),
      JSON.stringify({
        bite: {
          summary: "**산미**가 마음에 들었어요.",
          ...(options.brief ? { brief: options.brief } : {}),
        },
      }),
    ],
  );
  await db.query(
    `insert into public.user_liked_drink_cards (user_id, drink_record_id, created_at)
     values ($1, $2, $3::timestamptz)`,
    [user, recordId, likedAt],
  );
  return recordId;
}

type Page = {
  total: number;
  cards: {
    drink_record_id: string;
    name: string;
    media_path: string | null;
    interest_key: string | null;
    note: string | null;
    recorded_at: string;
    result_id: string;
    brief: string | null;
    summary: string | null;
  }[];
};

async function page(
  db: PGlite,
  args: [string | null, boolean, number, number],
): Promise<Page> {
  const { rows } = await db.query<{ result: Page }>(
    "select public.soolgyul_my_liked_cards($1, $2, $3, $4) as result",
    args,
  );
  return rows[0].result;
}

Deno.test("my liked cards pages the owner's live likes with catalog names", async () => {
  const db = await createSupabaseLikeDatabase();
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${OWNER}', 'owner@example.test', '{"provider":"kakao"}', now()),
      ('${STRANGER}', 'stranger@example.test', '{"provider":"kakao"}', now());
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order, interest_key) values
      ('${WINE}', 'wine', '와인', 1, 'wine'),
      ('${SAKE}', 'sake', '사케', 2, 'sake');
    insert into public.alcohol_items (id, name_ko, alcohol_category_id, publish_status, published_at) values
      ('${WINE_ITEM}', '샤토 테스트', '${WINE}', 'published', now()),
      ('${SAKE_ITEM}', '준마이 테스트', '${SAKE}', 'published', now());
    insert into public.catalog_media_assets (alcohol_item_id, media_path, publish_status, published_at) values
      ('${WINE_ITEM}', 'wine/${WINE_ITEM}.webp', 'published', now()),
      ('${SAKE_ITEM}', 'sake/${SAKE_ITEM}.webp', 'staging', null);
  `);
  const oldest = await likedRecord(
    db,
    OWNER,
    WINE_ITEM,
    "2026-06-03T12:00:00Z",
    {
      note: "부드러웠어요",
      brief: "산미가 마음에 들었어요.",
    },
  );
  const middle = await likedRecord(
    db,
    OWNER,
    SAKE_ITEM,
    "2026-06-10T12:00:00Z",
  );
  const newest = await likedRecord(
    db,
    OWNER,
    WINE_ITEM,
    "2026-06-20T12:00:00Z",
  );
  await likedRecord(db, STRANGER, WINE_ITEM, "2026-06-05T12:00:00Z");

  await asUser(db, OWNER, async () => {
    const all = await page(db, [null, true, 0, 30]);
    const got = all.cards.map((card) => ({
      id: card.drink_record_id,
      name: card.name,
      interest_key: card.interest_key,
      note: card.note,
    }));
    const expected = [
      { id: newest, name: "샤토 테스트", interest_key: "wine", note: null },
      { id: middle, name: "준마이 테스트", interest_key: "sake", note: null },
      {
        id: oldest,
        name: "샤토 테스트",
        interest_key: "wine",
        note: "부드러웠어요",
      },
    ];
    if (all.total !== 3 || JSON.stringify(got) !== JSON.stringify(expected)) {
      throw new Error(`all: ${JSON.stringify(all)}`);
    }
    // Only a published photo comes with the card.
    const photos = all.cards.map((card) => card.media_path);
    const photo = `wine/${WINE_ITEM}.webp`;
    if (JSON.stringify(photos) !== JSON.stringify([photo, null, photo])) {
      throw new Error(`photos: ${JSON.stringify(photos)}`);
    }
    const lines = all.cards.map((
      card,
    ) => [card.result_id, card.brief, card.summary]);
    const expectedLines = [
      [
        newest.replace("d0000000", "e0000000"),
        null,
        "**산미**가 마음에 들었어요.",
      ],
      [
        middle.replace("d0000000", "e0000000"),
        null,
        "**산미**가 마음에 들었어요.",
      ],
      [
        oldest.replace("d0000000", "e0000000"),
        "산미가 마음에 들었어요.",
        "**산미**가 마음에 들었어요.",
      ],
    ];
    if (JSON.stringify(lines) !== JSON.stringify(expectedLines)) {
      throw new Error(`card lines: ${JSON.stringify(lines)}`);
    }
    if (!all.cards[0].recorded_at.startsWith("2026-06-01")) {
      throw new Error(`recorded_at: ${all.cards[0].recorded_at}`);
    }

    const second = await page(db, [null, false, 1, 1]);
    if (
      second.total !== 3 ||
      second.cards.map((c) => c.drink_record_id).join() !== middle
    ) {
      throw new Error(`oldest-first page 2: ${JSON.stringify(second)}`);
    }

    const wine = await page(db, ["wine", true, 0, 30]);
    if (
      wine.total !== 2 ||
      wine.cards.map((c) => c.drink_record_id).join() !==
        [newest, oldest].join()
    ) {
      throw new Error(`wine: ${JSON.stringify(wine)}`);
    }

    const none = await page(db, ["whisky", true, 0, 30]);
    if (none.total !== 0 || none.cards.length !== 0) {
      throw new Error(`whisky: ${JSON.stringify(none)}`);
    }
  });

  await asUser(db, STRANGER, async () => {
    const mine = await page(db, [null, true, 0, 30]);
    if (mine.total !== 1 || mine.cards[0].name !== "샤토 테스트") {
      throw new Error(`stranger: ${JSON.stringify(mine)}`);
    }
  });
  await db.close();
});
