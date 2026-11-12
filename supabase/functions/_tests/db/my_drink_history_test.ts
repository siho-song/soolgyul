import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { asUser } from "../helpers/db_session.ts";

// The 취향 tab reads the owner's saved records of one month through one RPC:
// oldest first, other people's records left out, with the card
// id to open and the 핵심 요약 tag labels.

const OWNER = "a0000000-0000-4000-8000-000000000051";
const STRANGER = "a0000000-0000-4000-8000-000000000052";
const CATEGORY = "c0000000-0000-4000-8000-000000000001";
const ITEM = "b0000000-0000-4000-8000-000000000001";

let seq = 0;
async function record(
  db: PGlite,
  user: string,
  createdAt: string,
  options: { note?: string; brief?: boolean } = {},
): Promise<string> {
  seq += 1;
  const id = String(seq).padStart(12, "0");
  const recordId = `d0000000-0000-4000-8000-${id}`;
  const resultId = `e0000000-0000-4000-8000-${id}`;
  await db.query(
    `insert into public.drink_records
       (id, user_id, alcohol_item_id, questionnaire_version, created_at, one_line_note)
     values ($1, $2, $3, 'sensory-questionnaire-v1', $4::timestamptz, $5)`,
    [
      recordId,
      user,
      ITEM,
      createdAt,
      options.note ?? null,
    ],
  );
  await db.query(
    `insert into public.taste_cards (id, drink_record_id, snapshot_id, snapshot_ref, lifecycle,
       canonical_schema_version, semantic_snapshot, rendered_snapshot)
     values ($1, $2, gen_random_uuid(), $3, 'final', 'test', '{}'::jsonb, $4::jsonb)`,
    [
      resultId,
      recordId,
      id.padStart(64, "f"),
      JSON.stringify({
        bite: {
          tags: [{ label: "산뜻함", kind: "liked" }, {
            label: "",
            kind: "liked",
          }],
          summary: "**산뜻함**이 마음에 쏙 들었어요.",
          // A card made before the brief was written has no such key.
          ...(options.brief ? { brief: "산뜻함이 마음에 쏙 들었어요." } : {}),
        },
      }),
    ],
  );
  return resultId;
}

type Row = {
  result_id: string;
  name: string;
  media_path: string | null;
  category_key: string;
  category_label: string;
  note: string | null;
  summary: string;
  brief: string | null;
  tags: { label: string; kind: string }[];
};

Deno.test("my drink history lists one month of the owner's live records", async () => {
  const db = await createSupabaseLikeDatabase();
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${OWNER}', 'owner@example.test', '{"provider":"kakao"}', now()),
      ('${STRANGER}', 'stranger@example.test', '{"provider":"kakao"}', now());
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('${CATEGORY}', 'wine', '와인', 1);
    insert into public.alcohol_items (id, name_ko, alcohol_category_id, publish_status, published_at)
      values ('${ITEM}', '샤토 테스트', '${CATEGORY}', 'published', now());
    insert into public.catalog_media_assets (alcohol_item_id, media_path, publish_status, published_at)
      values ('${ITEM}', 'wine/${ITEM}.webp', 'published', now());
  `);
  const second = await record(db, OWNER, "2026-06-20T12:00:00Z");
  const first = await record(db, OWNER, "2026-06-03T12:00:00Z", {
    note: "부드러웠어요",
    brief: true,
  });
  await record(db, OWNER, "2026-07-01T12:00:00Z");
  await record(db, STRANGER, "2026-06-05T12:00:00Z");

  const june = ["2026-06-01T00:00:00Z", "2026-07-01T00:00:00Z"];
  await asUser(db, OWNER, async () => {
    const { rows } = await db.query<{ result: Row[] }>(
      "select public.soolgyul_my_drink_history($1, $2) as result",
      june,
    );
    const got = rows[0].result.map((row) => ({
      result_id: row.result_id,
      name: row.name,
      category_key: row.category_key,
      category_label: row.category_label,
      note: row.note,
      summary: row.summary,
      brief: row.brief,
      tags: row.tags,
    }));
    const expected = [
      {
        result_id: first,
        name: "샤토 테스트",
        category_key: "wine",
        category_label: "와인",
        note: "부드러웠어요",
        summary: "**산뜻함**이 마음에 쏙 들었어요.",
        brief: "산뜻함이 마음에 쏙 들었어요.",
        tags: [{ kind: "liked", label: "산뜻함" }],
      },
      {
        result_id: second,
        name: "샤토 테스트",
        category_key: "wine",
        category_label: "와인",
        note: null,
        summary: "**산뜻함**이 마음에 쏙 들었어요.",
        brief: null,
        tags: [{ kind: "liked", label: "산뜻함" }],
      },
    ];
    if (JSON.stringify(got) !== JSON.stringify(expected)) {
      throw new Error(`history: ${JSON.stringify(got)}`);
    }
    // Each row carries the product's published photo, so the list needs no
    // second call for photos.
    const photos = rows[0].result.map((row) => row.media_path);
    const photo = `wine/${ITEM}.webp`;
    if (JSON.stringify(photos) !== JSON.stringify([photo, photo])) {
      throw new Error(`history photos: ${JSON.stringify(photos)}`);
    }
    const tooWide = await db.query<{ result: unknown[] }>(
      "select public.soolgyul_my_drink_history($1, $2) as result",
      ["2026-01-01T00:00:00Z", "2026-07-01T00:00:00Z"],
    );
    if (tooWide.rows[0].result.length !== 0) {
      throw new Error("a range over 45 days was served");
    }
  });

  await asUser(db, STRANGER, async () => {
    const { rows } = await db.query<{ result: Row[] }>(
      "select public.soolgyul_my_drink_history($1, $2) as result",
      june,
    );
    if (rows[0].result.length !== 1) throw new Error("stranger saw others");
  });
  await db.close();
});
