import type { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";

// The discovery events the app writes: who is counted, what a row may hold,
// what the client cannot do, and how a member's rows lose the account link.

const ids = {
  member: "a0000000-0000-4000-8000-000000000051",
  leaving: "a0000000-0000-4000-8000-000000000052",
  category: "c0000000-0000-4000-8000-000000000051",
  item: "e0000000-0000-4000-8000-000000000051",
};

function same(actual: unknown, expected: unknown, label: string) {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${label}: expected ${b}, received ${a}`);
}

async function rejects(
  work: () => Promise<unknown>,
  fragment: string,
  label: string,
) {
  try {
    await work();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!message.includes(fragment)) {
      throw new Error(
        `${label}: expected "${fragment}", received "${message}"`,
      );
    }
    return;
  }
  throw new Error(`${label}: expected rejection "${fragment}"`);
}

/** Runs `work` as a client role; `null` is a caller without a session. */
async function asRole(
  db: PGlite,
  role: "anon" | "authenticated",
  userId: string | null,
  work: () => Promise<void>,
) {
  await db.exec(`set role ${role};`);
  await db.query("select set_config('request.jwt.claims', $1, false)", [
    userId === null ? "" : JSON.stringify({ sub: userId }),
  ]);
  try {
    await work();
  } finally {
    await db.exec("reset role;");
    await db.query("select set_config('request.jwt.claims', '', false)");
  }
}

const record = (
  db: PGlite,
  kind: string,
  item: string | null,
  query: string | null,
  surface = "record",
) =>
  db.query("select public.soolgyul_record_discovery_event($1, $2, $3, $4)", [
    kind,
    surface,
    item,
    query,
  ]);

type EventRow = {
  kind: string;
  query_text: string | null;
  user_id: string | null;
  birth_year_band: number | null;
  gender: string | null;
};

async function events(db: PGlite) {
  const { rows } = await db.query<EventRow>(
    `select kind, query_text, user_id, birth_year_band, gender
     from public.drink_discovery_events order by id`,
  );
  return rows;
}

async function seed(db: PGlite) {
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${ids.member}', 'member@example.test', '{"provider":"kakao"}', now()),
      ('${ids.leaving}', 'leaving@example.test', '{"provider":"google"}', now());
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('${ids.category}', 'wine', '와인', 1);
    insert into public.alcohol_items (id, name_ko, alcohol_category_id, publish_status, published_at)
      values ('${ids.item}', '테스트 술', '${ids.category}', 'published', now());
  `);
  for (const [id, name] of [[ids.member, "남는이"], [ids.leaving, "떠날이"]]) {
    await asRole(db, "authenticated", id, async () => {
      await db.query(
        `select public.soolgyul_complete_my_profile(
           gen_random_uuid(), $1, date '1993-05-02', true, 'soolgyul-terms-v1',
           'soolgyul-privacy-v1', 'soolgyul-marketing-v1', true, true, false)`,
        [name],
      );
    });
  }
}

Deno.test("discovery events", async (t) => {
  const db = await createSupabaseLikeDatabase();
  await seed(db);

  await t.step(
    "a member's event carries the account, a guest's none",
    async () => {
      await asRole(db, "authenticated", ids.member, async () => {
        await record(db, "search_pick", ids.item, "  샤또   마고 ");
        await record(db, "fit_view", ids.item, null, "taste_fit");
      });
      await asRole(db, "anon", null, async () => {
        await record(db, "search_empty", null, "없는 술");
        await record(db, "label_miss", null, "CHATEAU\nINCONNU");
      });
      same(
        (await events(db)).map((e) => [e.kind, e.query_text, e.user_id]),
        [
          ["search_pick", "샤또 마고", ids.member],
          ["fit_view", null, ids.member],
          ["search_empty", "없는 술", null],
          ["label_miss", "CHATEAU INCONNU", null],
        ],
        "rows",
      );
    },
  );

  await t.step("a row's shape is checked", async () => {
    await asRole(db, "authenticated", ids.member, async () => {
      await rejects(
        () => record(db, "search_empty", null, "   "),
        "discovery_event_invalid",
        "a miss without words",
      );
      await rejects(
        () => record(db, "label_pick", ids.item, null),
        "discovery_event_invalid",
        "a label pick without the words read",
      );
      await rejects(
        () => record(db, "label_pick", null, "읽은 글자"),
        "discovery_event_invalid",
        "a label pick without a drink",
      );
      await rejects(
        () => record(db, "fit_view", ids.item, "읽은 글자"),
        "discovery_event_invalid",
        "a view with words",
      );
      await rejects(
        () => record(db, "scroll", ids.item, null),
        "discovery_event_invalid",
        "an unknown kind",
      );
      await rejects(
        () =>
          record(db, "fit_view", "e0000000-0000-4000-8000-000000000099", null),
        "discovery_event_invalid",
        "a drink that does not exist",
      );
    });
  });

  await t.step(
    "a label read keeps its words with the bottle found and the one chosen",
    async () => {
      await asRole(db, "authenticated", ids.member, async () => {
        await record(db, "label_match", ids.item, "GRANT'S  TRIPLE WOOD");
        await record(db, "label_pick", ids.item, "GRANT'S TRIPLE WOOD");
        // An older app sends the likeliest bottle without the words.
        await record(db, "label_match", ids.item, null);
      });
      same(
        (await events(db)).slice(-3).map((e) => [e.kind, e.query_text]),
        [
          ["label_match", "GRANT'S TRIPLE WOOD"],
          ["label_pick", "GRANT'S TRIPLE WOOD"],
          ["label_match", null],
        ],
        "rows",
      );
      // The later steps count the member's rows from here.
      await db.query(
        "delete from public.drink_discovery_events where kind in ('label_match', 'label_pick')",
      );
    },
  );

  await t.step("clients cannot read or write the table directly", async () => {
    for (const role of ["anon", "authenticated"] as const) {
      await asRole(db, role, role === "anon" ? null : ids.member, async () => {
        await rejects(
          () => db.query("select * from public.drink_discovery_events"),
          "permission denied",
          `${role} read`,
        );
        await rejects(
          () =>
            db.query(
              "insert into public.drink_discovery_events (kind, surface) values ('fit_view', 'record')",
            ),
          "permission denied",
          `${role} insert`,
        );
        await rejects(
          () => db.query("select public.soolgyul_anonymize_discovery_events()"),
          "permission denied",
          `${role} anonymize`,
        );
      });
    }
  });

  await t.step("a reader on the way out is not counted", async () => {
    await db.query("select public.soolgyul_request_account_deletion($1)", [
      ids.leaving,
    ]);
    await asRole(db, "authenticated", ids.leaving, async () => {
      await record(db, "fit_view", ids.item, null);
    });
    same(
      (await events(db)).filter((e) => e.user_id === ids.leaving).length,
      0,
      "no row",
    );
  });

  await t.step("a member over 300 events an hour is dropped", async () => {
    await db.query(
      `insert into public.drink_discovery_events (kind, surface, alcohol_item_id, user_id)
       select 'fit_view', 'taste_fit', $1, $2 from generate_series(1, 298)`,
      [ids.item, ids.member],
    );
    await asRole(db, "authenticated", ids.member, async () => {
      await record(db, "fit_view", ids.item, null);
    });
    const counted = await db.query<{ n: number }>(
      "select count(*)::int as n from public.drink_discovery_events where user_id = $1",
      [ids.member],
    );
    same(counted.rows[0].n, 300, "capped at 300");
    await db.query(
      "delete from public.drink_discovery_events where user_id = $1 and kind = 'fit_view' and surface = 'taste_fit' and id > 2",
      [ids.member],
    );
  });

  await t.step(
    "after 13 months a member's events keep only day, band and consented gender",
    async () => {
      await db.query(
        `update public.users set gender = 'female', gender_consent_accepted_at = now(),
         gender_consent_version = 'soolgyul-gender-v1'
       where id = $1`,
        [ids.member],
      );
      await db.query(
        `update public.drink_discovery_events
       set occurred_at = timestamptz '2025-01-10 15:40:00+00'
       where user_id = $1 and kind = 'search_pick'`,
        [ids.member],
      );
      const changed = await db.query<{ n: number }>(
        "select public.soolgyul_anonymize_discovery_events() as n",
      );
      same(changed.rows[0].n, 1, "only the old row");
      const rows = await db.query<
        EventRow & { occurred_at: string }
      >(
        `select kind, user_id, birth_year_band, gender,
         to_char(occurred_at at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI') as occurred_at
       from public.drink_discovery_events where kind in ('search_pick', 'fit_view')
       order by id`,
      );
      same(
        rows.rows.map((
          r,
        ) => [
          r.kind,
          r.user_id,
          r.birth_year_band,
          r.gender,
          r.occurred_at.slice(11),
        ]),
        [
          ["search_pick", null, 1990, "female", "00:00"],
          [
            "fit_view",
            ids.member,
            null,
            null,
            rows.rows[1].occurred_at.slice(11),
          ],
        ],
        "old row anonymous, recent row linked",
      );
    },
  );

  await t.step("a daily job runs the anonymizer", async () => {
    const job = await db.query<{ command: string }>(
      "select command from cron.job where jobname = 'soolgyul-discovery-anonymize'",
    );
    same(
      job.rows.map((r) => r.command),
      ["select public.soolgyul_anonymize_discovery_events()"],
      "job",
    );
  });

  await db.close();
});
