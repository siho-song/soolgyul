import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";

// The home carousel reads the guide of the owner's latest cards through one
// RPC: newest first, only cards that have a guide, with the bottle's kind.

const OWNER = "a0000000-0000-4000-8000-000000000031";
const STRANGER = "a0000000-0000-4000-8000-000000000032";
const CATEGORY = "c0000000-0000-4000-8000-000000000001";
const RED = "b0000000-0000-4000-8000-000000000001";
const UNSTYLED = "b0000000-0000-4000-8000-000000000002";

const GUIDE = {
  head: "레드 와인을 품종과 산지 조합으로 준비했어요.",
  picks: [{
    country: "it",
    place: "이탈리아 피에몬테",
    keyword: "바르베라",
    note: null,
  }],
  tip: null,
  levels: [{ label: "당도", mark: 1, range: "1~2" }],
  directions: [],
};

/** JSON with object keys sorted, so jsonb's own key order does not matter. */
function canonical(value: unknown): string {
  return JSON.stringify(
    value,
    (_key, v) =>
      v !== null && typeof v === "object" && !Array.isArray(v)
        ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, v[k]]))
        : v,
  );
}

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

async function seed(db: PGlite) {
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${OWNER}', 'owner@example.test', '{"provider":"kakao"}', now()),
      ('${STRANGER}', 'stranger@example.test', '{"provider":"kakao"}', now());
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('${CATEGORY}', 'wine', '와인', 1);
    -- the style red_wine is seeded by migrations
    insert into public.alcohol_items
      (id, name_ko, alcohol_category_id, publish_status, published_at, style_key)
      values ('${RED}', '레드', '${CATEGORY}', 'published', now(), 'red_wine'),
             ('${UNSTYLED}', '어떤 와인', '${CATEGORY}', 'published', now(), null);
  `);
}

let recordSeq = 0;
async function card(
  db: PGlite,
  options: {
    user: string;
    item: string;
    createdAt: string;
    guide: unknown;
    deleted?: boolean;
  },
) {
  recordSeq += 1;
  const record = `d0000000-0000-4000-8000-${
    String(recordSeq).padStart(12, "0")
  }`;
  const result = `e0000000-0000-4000-8000-${
    String(recordSeq).padStart(12, "0")
  }`;
  await db.query(
    `insert into public.drink_records (id, user_id, alcohol_item_id, questionnaire_version, created_at, deleted_at)
     values ($1, $2, $3, 'sensory-questionnaire-v1', $4::timestamptz, case when $5 then now() end)`,
    [
      record,
      options.user,
      options.item,
      options.createdAt,
      options.deleted ?? false,
    ],
  );
  await db.query(
    `insert into public.taste_cards (id, drink_record_id, snapshot_id, snapshot_ref, lifecycle,
       canonical_schema_version, semantic_snapshot, rendered_snapshot)
     values ($1, $2, gen_random_uuid(), $4, 'final', 'test', '{}'::jsonb, $3::jsonb)`,
    [
      result,
      record,
      JSON.stringify({ bite: { guide: options.guide } }),
      String(recordSeq).padStart(64, "b"),
    ],
  );
  return result;
}

Deno.test("recent card guides come newest first, only with a guide, with the kind", async () => {
  const db = await createSupabaseLikeDatabase();
  await seed(db);
  const oldest = await card(db, {
    user: OWNER,
    item: RED,
    createdAt: "2026-01-01",
    guide: GUIDE,
  });
  await card(db, {
    user: OWNER,
    item: RED,
    createdAt: "2026-01-02",
    guide: null,
  });
  const unstyled = await card(db, {
    user: OWNER,
    item: UNSTYLED,
    createdAt: "2026-01-03",
    guide: GUIDE,
  });
  await card(db, {
    user: OWNER,
    item: RED,
    createdAt: "2026-01-04",
    guide: GUIDE,
    deleted: true,
  });
  const newest = await card(db, {
    user: OWNER,
    item: RED,
    createdAt: "2026-01-05",
    guide: GUIDE,
  });
  await card(db, {
    user: STRANGER,
    item: RED,
    createdAt: "2026-01-06",
    guide: GUIDE,
  });

  await asUser(db, OWNER, async () => {
    const { rows } = await db.query<
      {
        result: {
          result_id: string;
          kind_label: string;
          category_label: string;
          guide: unknown;
        }[];
      }
    >("select public.soolgyul_my_recent_card_guides() as result");
    const got = rows[0].result;
    const expected = [
      {
        result_id: newest,
        kind_label: "레드 와인",
        category_label: "와인",
        guide: GUIDE,
      },
      {
        result_id: unstyled,
        kind_label: "와인",
        category_label: "와인",
        guide: GUIDE,
      },
      {
        result_id: oldest,
        kind_label: "레드 와인",
        category_label: "와인",
        guide: GUIDE,
      },
    ];
    if (canonical(got) !== canonical(expected)) {
      throw new Error(`guides: ${JSON.stringify(got)}`);
    }
    const limited = await db.query<{ result: unknown[] }>(
      "select public.soolgyul_my_recent_card_guides(1) as result",
    );
    if (limited.rows[0].result.length !== 1) throw new Error("limit ignored");
  });
  await db.query("select set_config('request.jwt.claims', '', false)");
  const anonymous = await db.query<{ result: unknown[] }>(
    "select public.soolgyul_my_recent_card_guides() as result",
  );
  if (anonymous.rows[0].result.length !== 0) {
    throw new Error("anonymous saw guides");
  }
  await db.close();
});
