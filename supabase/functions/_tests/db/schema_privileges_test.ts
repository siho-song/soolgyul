import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { pg_trgm } from "npm:@electric-sql/pglite@0.3.14/contrib/pg_trgm";
import {
  applyMigrations,
  SUPABASE_LIKE_PRELUDE,
} from "../helpers/pglite_supabase.ts";

// Applies every migration to a database that mimics a fresh Supabase project
// (client roles, auth/storage/cron stubs and the permissive default
// privileges) and checks the privileges and policies the product relies on.

const CLIENT_FUNCTIONS = {
  anon: [
    "soolgyul_get_sensory_question_context",
    "soolgyul_record_discovery_event",
    "soolgyul_search_alcohol_catalog_batch",
    "soolgyul_search_alcohol_catalog_by_label",
    "soolgyul_search_catalog",
  ],
  authenticated: [
    "soolgyul_account_active",
    "soolgyul_admin_change_editorial_status",
    "soolgyul_admin_delete_editorial_draft",
    "soolgyul_admin_has_role",
    "soolgyul_admin_list_support_inquiries",
    "soolgyul_admin_save_editorial_article",
    "soolgyul_admin_set_support_inquiry_answered",
    "soolgyul_complete_my_profile",
    "soolgyul_editorial_object_editable",
    "soolgyul_get_marketing_consent",
    "soolgyul_get_my_deletion_state",
    "soolgyul_get_my_profile_preferences",
    "soolgyul_get_my_profile_status",
    "soolgyul_get_sensory_question_context",
    "soolgyul_my_account_ready",
    "soolgyul_my_drink_history",
    "soolgyul_my_liked_cards",
    "soolgyul_my_recent_card_guides",
    "soolgyul_private_upload_allowed",
    "soolgyul_record_discovery_event",
    "soolgyul_register_push_device",
    "soolgyul_replace_my_drink_interests",
    "soolgyul_restore_my_account",
    "soolgyul_search_alcohol_catalog_batch",
    "soolgyul_search_alcohol_catalog_by_label",
    "soolgyul_search_catalog",
    "soolgyul_set_marketing_consent",
    "soolgyul_submit_support_inquiry",
    "soolgyul_unregister_push_device",
    "soolgyul_update_my_display_name",
    "soolgyul_update_my_drink_record_note",
  ],
};

// Table privileges per client role; tables that are absent carry none.
const CLIENT_TABLE_PRIVILEGES: Record<string, Record<string, string>> = {
  anon: {
    app_gates: "SELECT",
    editorial_article_interests: "SELECT",
    editorial_article_media_assets: "SELECT",
    editorial_articles: "SELECT",
    site_posts: "SELECT",
  },
  authenticated: {
    admin_user_roles: "SELECT",
    app_gates: "SELECT",
    drink_records: "SELECT",
    editorial_article_interests: "DELETE,INSERT,SELECT",
    editorial_article_media_assets: "DELETE,INSERT,SELECT,UPDATE",
    editorial_articles: "DELETE,INSERT,SELECT,UPDATE",
    site_posts: "DELETE,INSERT,SELECT,UPDATE",
    taste_letter_changes: "SELECT",
    taste_letters: "SELECT",
    user_liked_drink_cards: "DELETE,INSERT,SELECT",
    user_saved_articles: "DELETE,INSERT,SELECT",
  },
};

const ids = {
  activeUser: "a0000000-0000-4000-8000-000000000001",
  scheduledUser: "a0000000-0000-4000-8000-000000000002",
  editor: "a0000000-0000-4000-8000-000000000003",
  admin: "a0000000-0000-4000-8000-000000000004",
  questionnaire: "sensory-questionnaire-v1",
  category: "c0000000-0000-4000-8000-000000000001",
  item: "e0000000-0000-4000-8000-000000000001",
  publishedArticle: "d0000000-0000-4000-8000-000000000001",
  draftArticle: "d0000000-0000-4000-8000-000000000002",
};

function assertEquals(actual: unknown, expected: unknown, label: string) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) {
    throw new Error(`${label}: expected ${right}, received ${left}`);
  }
}

async function assertRejects(
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
  }
}

async function rowCount(
  db: PGlite,
  sql: string,
  params: unknown[] = [],
): Promise<number> {
  const result = await db.query<{ count: number }>(
    `select count(*)::int as count from (${sql}) rows`,
    params,
  );
  return result.rows[0].count;
}

// Rows an UPDATE or DELETE touched; RLS hides rows instead of raising.
async function affectedRows(db: PGlite, sql: string): Promise<number> {
  const result = await db.query<{ count: number }>(
    `with changed as (${sql}) select count(*)::int as count from changed`,
  );
  return result.rows[0].count;
}

async function seedFixtures(db: PGlite) {
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${ids.activeUser}', 'active@example.test', '{"provider":"kakao"}', now()),
      ('${ids.scheduledUser}', 'scheduled@example.test', '{"provider":"kakao"}', now()),
      ('${ids.editor}', 'editor@example.test', '{"provider":"google"}', now()),
      ('${ids.admin}', 'admin@admin.soolgyul.com', '{"provider":"email","soolgyul_staff":"true"}', now());
    update public.users
      set deletion_requested_at = now()
      where id = '${ids.scheduledUser}';
    insert into public.admin_user_roles (user_id, role) values
      ('${ids.editor}', 'editor'), ('${ids.admin}', 'admin');
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('${ids.category}', 'wine', '와인', 1);
    insert into public.alcohol_items (id, name_ko, alcohol_category_id, publish_status, published_at)
      values ('${ids.item}', '테스트 술', '${ids.category}', 'published', now());
    insert into public.editorial_articles (id, body, status, published_at)
    values
      ('${ids.publishedArticle}', '공개 글', 'published', now() - interval '1 day'),
      ('${ids.draftArticle}', '초안 글', 'draft', null);
    insert into public.editorial_article_media_assets
      (article_id, storage_bucket, storage_object_path)
    values
      ('${ids.publishedArticle}', 'soolgyul-editorial', 'articles/published/cover.webp'),
      ('${ids.draftArticle}', 'soolgyul-editorial', 'articles/draft/cover.webp');
    insert into storage.objects (bucket_id, name) values
      ('soolgyul-editorial', 'articles/published/cover.webp'),
      ('soolgyul-editorial', 'articles/draft/cover.webp'),
      ('soolgyul-editorial', 'articles/orphan.webp');
  `);
}

async function insertRecord(
  db: PGlite,
  input: {
    id: string;
    userId: string | null;
    anonymousSessionId: string | null;
    idempotencyKey: string;
    createdAt?: string;
  },
) {
  await db.query(
    `insert into public.drink_records
       (id, user_id, anonymous_session_id, questionnaire_version,
        alcohol_item_id, idempotency_key, created_at)
     values ($1, $2, $3, $4, $5, $6, coalesce($7::timestamptz, now()))`,
    [
      input.id,
      input.userId,
      input.anonymousSessionId,
      ids.questionnaire,
      ids.item,
      input.idempotencyKey,
      input.createdAt ?? null,
    ],
  );
  await db.query(
    `insert into public.drink_record_answers
       (drink_record_id, question_key)
     values ($1, 'aroma')`,
    [input.id],
  );
}

async function insertAttempt(
  db: PGlite,
  input: {
    ref: string;
    digest: string;
    address?: string;
    createdAt?: string;
    final?: { recordId: string; cardId: string; snapshotId: string };
  },
) {
  const key = crypto.randomUUID();
  if (input.final) {
    await db.query(
      `insert into public.taste_card_generation_attempts
         (attempt_ref, idempotency_key, anonymous_session_digest, request_digest,
          reserved_record_id, reserved_result_summary_id, state, result_summary_id,
          claim_snapshot_id, conversion_key_version, conversion_expires_at,
          completed_at, created_at)
       values ($1, $2, $3, repeat('a', 64), $4, $5, 'final', $5, $6, 'v1',
               now(), now(), coalesce($7::timestamptz, now()))`,
      [
        input.ref,
        key,
        input.digest,
        input.final.recordId,
        input.final.cardId,
        input.final.snapshotId,
        input.createdAt ?? null,
      ],
    );
    return;
  }
  await db.query(
    `insert into public.taste_card_generation_attempts
       (attempt_ref, idempotency_key, anonymous_session_digest, request_digest,
        created_at, client_address_digest)
     values ($1, $2, $3, repeat('a', 64), coalesce($4::timestamptz, now()), $5)`,
    [
      input.ref,
      key,
      input.digest,
      input.createdAt ?? null,
      input.address ?? null,
    ],
  );
}

Deno.test("applied migrations expose only the intended privileges and policies", async (t) => {
  const db = new PGlite({ extensions: { pg_trgm } });
  try {
    await db.exec(SUPABASE_LIKE_PRELUDE);
    await applyMigrations(db);
    await seedFixtures(db);

    await t.step(
      "client roles execute only the allow-listed functions",
      async () => {
        const result = await db.query<
          { proname: string; anon: boolean; authenticated: boolean }
        >(
          `select p.proname,
                has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
                has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated
         from pg_proc p
         where p.pronamespace = 'public'::regnamespace
         order by p.proname`,
        );
        for (const role of ["anon", "authenticated"] as const) {
          const exposed = result.rows.filter((row) => row[role]).map((row) =>
            row.proname
          );
          assertEquals(exposed, CLIENT_FUNCTIONS[role], `${role} functions`);
        }
        const serviceDenied = await db.query<{ proname: string }>(
          `select p.proname from pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and not has_function_privilege('service_role', p.oid, 'EXECUTE')`,
        );
        assertEquals(serviceDenied.rows, [], "service_role functions");
      },
    );

    await t.step(
      "client roles hold only the listed table privileges",
      async () => {
        const result = await db.query<
          { relname: string; anon: string | null; authenticated: string | null }
        >(
          `select c.relname,
           (select string_agg(privilege, ',' order by privilege)
              from unnest(array['SELECT','INSERT','UPDATE','DELETE']) privilege
             where has_table_privilege('anon', c.oid, privilege)) as anon,
           (select string_agg(privilege, ',' order by privilege)
              from unnest(array['SELECT','INSERT','UPDATE','DELETE']) privilege
             where has_table_privilege('authenticated', c.oid, privilege)) as authenticated
         from pg_class c
         where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v')
         order by c.relname`,
        );
        for (const role of ["anon", "authenticated"] as const) {
          const actual = Object.fromEntries(
            result.rows.filter((row) => row[role] !== null)
              .map((row) => [row.relname, row[role]]),
          );
          assertEquals(actual, CLIENT_TABLE_PRIVILEGES[role], `${role} tables`);
        }
        const cardColumns = await db.query<{ column_name: string }>(
          `select column_name from information_schema.column_privileges
         where table_schema = 'public' and table_name = 'taste_cards'
           and grantee = 'authenticated' and privilege_type = 'SELECT'
         order by column_name`,
        );
        assertEquals(
          cardColumns.rows.map((row) => row.column_name),
          ["drink_record_id", "id"],
          "authenticated taste_cards columns",
        );
      },
    );

    await t.step("every public table enforces row level security", async () => {
      const unprotected = await db.query<{ relname: string }>(
        `select relname from pg_class
         where relnamespace = 'public'::regnamespace and relkind = 'r' and not relrowsecurity`,
      );
      assertEquals(unprotected.rows, [], "tables without RLS");
    });

    await t.step(
      "signup trigger trusts only the app metadata flags",
      async () => {
        const forged = "e0000000-0000-4000-8000-000000000001";
        const synthetic = "e0000000-0000-4000-8000-000000000002";
        const unknown = "e0000000-0000-4000-8000-000000000003";
        const staff = "e0000000-0000-4000-8000-000000000004";
        await db.exec(`
        insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data) values
          ('${forged}', 'forged@example.test', '{"provider":"email"}', '{"soolgyul_test_user":"true","soolgyul_staff":"true"}'),
          ('${synthetic}', 'synthetic@example.test', '{"provider":"email","soolgyul_test_user":"true"}', '{}'),
          ('${unknown}', 'unknown@example.test', '{"provider":"github"}', '{}'),
          ('${staff}', 'staff@example.test', '{"provider":"email","soolgyul_staff":"true"}', '{}');
      `);
        const rows = await db.query<{ id: string; auth_provider: string }>(
          `select id, auth_provider from public.users where id in ($1, $2, $3, $4) order by id`,
          [forged, synthetic, unknown, staff],
        );
        // The admin API marks an account as staff right after creating it.
        const marked = "e0000000-0000-4000-8000-000000000005";
        await db.exec(`
        insert into auth.users (id, email, raw_app_meta_data) values
          ('${marked}', 'marked@example.test', '{"provider":"email"}');
        update auth.users
          set raw_app_meta_data = raw_app_meta_data || '{"soolgyul_staff":"true"}'
          where id = '${marked}';
      `);
        const markedRows = await db.query<{ auth_provider: string }>(
          `select auth_provider from public.users where id = $1`,
          [marked],
        );
        assertEquals(markedRows.rows, [{ auth_provider: "email" }], "marked");
        // Anyone can sign up by email and write their own user metadata, so
        // that account is no member. Only the flags the service writes make
        // a test account or a staff account (the administrator web's kind).
        assertEquals(
          rows.rows,
          [
            { id: synthetic, auth_provider: "test" },
            { id: staff, auth_provider: "email" },
          ],
          "provisioned users",
        );
      },
    );

    await t.step(
      "signup completes once and feeds the single adult-profile rule",
      async () => {
        const member = "a0000000-0000-4000-8000-000000000009";
        await db.exec(
          `insert into auth.users (id, email, raw_app_meta_data) values
        ('${member}', 'member@example.test', '{"provider":"google"}')`,
        );
        const complete = (name: string, gender: string | null) =>
          db.query<
            { result: { profile_complete: boolean; display_name: string } }
          >(
            `select public.soolgyul_complete_my_profile(
             gen_random_uuid(), $1, date '1990-03-21', true, 'soolgyul-terms-v1',
             'soolgyul-privacy-v1', 'soolgyul-marketing-v1', true, true, false,
             $2, $3) as result`,
            [name, gender, gender !== null],
          );
        await asRole(db, "authenticated", member, async () => {
          await assertRejects(
            () =>
              db.query(
                `select public.soolgyul_complete_my_profile(
                 gen_random_uuid(), '민지', (current_date - interval '1 year')::date, true,
                 'soolgyul-terms-v1', 'soolgyul-privacy-v1', 'soolgyul-marketing-v1',
                 true, true, false)`,
              ),
            "age_gate_required",
            "minor signup",
          );
          const first = await complete("민지", "female");
          assertEquals(
            first.rows[0].result.profile_complete,
            true,
            "first signup",
          );
          const retry = await complete("다른이름", null);
          assertEquals(
            retry.rows[0].result.display_name,
            "민지",
            "retry keeps the name",
          );
          const status = await db.query<
            { result: { profile_complete: boolean } }
          >(
            "select public.soolgyul_get_my_profile_status() as result",
          );
          assertEquals(status.rows[0].result.profile_complete, true, "status");
          await assertRejects(
            () =>
              db.query("select public.soolgyul_adult_profile_complete($1)", [
                member,
              ]),
            "permission denied",
            "rule is service-only",
          );
        });
        const stored = await db.query<
          { birth_date: string; gender: string; rule: boolean }
        >(
          `select birth_date::text, gender, public.soolgyul_adult_profile_complete(id) as rule
         from public.users where id = $1`,
          [member],
        );
        assertEquals(
          stored.rows,
          [{ birth_date: "1990-03-21", gender: "female", rule: true }],
          "stored profile",
        );
      },
    );

    await t.step(
      "writes wait for a finished sign-up, and pictures go only where an inquiry keeps them",
      async () => {
        // Finished signing up in the step above; the fixture member has not.
        const member = "a0000000-0000-4000-8000-000000000009";
        const inquiry = "b0000000-0000-4000-8000-000000000001";
        const picture = (owner: string, file = `0-${"a".repeat(64)}.jpg`) =>
          `${owner}/inquiries/${inquiry}/${file}`;
        const upload = (name: string) =>
          db.query(
            "insert into storage.objects (bucket_id, name) values ('soolgyul-private', $1)",
            [name],
          );
        const save = (owner: string) =>
          db.query(
            "insert into public.user_saved_articles (user_id, article_id) values ($1, $2)",
            [owner, ids.publishedArticle],
          );
        await asRole(db, "authenticated", ids.activeUser, async () => {
          await assertRejects(
            () => upload(picture(ids.activeUser)),
            "row-level security",
            "unfinished upload",
          );
          await assertRejects(
            () => save(ids.activeUser),
            "row-level security",
            "unfinished save",
          );
          await assertRejects(
            () =>
              db.query(
                `select public.soolgyul_submit_support_inquiry(
                   gen_random_uuid(), 'service', 'a@example.test', '문의 내용이에요')`,
              ),
            "active_account_required",
            "unfinished inquiry",
          );
        });
        await asRole(db, "authenticated", member, async () => {
          await upload(picture(member));
          await save(member);
          await assertRejects(
            () => upload(`${member}/anything.jpg`),
            "row-level security",
            "a path no inquiry uses",
          );
          await assertRejects(
            () => upload(picture(ids.activeUser)),
            "row-level security",
            "another member's folder",
          );
        });
        await db.query(
          `insert into storage.objects (bucket_id, name)
           select 'soolgyul-private', $1 || '/inquiries/earlier/' || n
           from generate_series(1, 59) as n`,
          [member],
        );
        await asRole(db, "authenticated", member, async () => {
          await assertRejects(
            () => upload(picture(member, `1-${"b".repeat(64)}.png`)),
            "row-level security",
            "the sixty-first of the day",
          );
        });
        await db.query("delete from storage.objects where name like $1", [
          member + "/%",
        ]);
        await db.query(
          "delete from public.user_saved_articles where user_id = $1",
          [member],
        );
      },
    );

    await t.step(
      "a finished member registers and forgets a phone's notification address; no client touches the table",
      async () => {
        const member = "a0000000-0000-4000-8000-000000000009";
        const other = "a0000000-0000-4000-8000-00000000000a";
        const phone = "p".repeat(140);
        await db.exec(
          `insert into auth.users (id, email, raw_app_meta_data) values
        ('${other}', 'other@example.test', '{"provider":"kakao"}')`,
        );
        await asRole(db, "authenticated", other, async () => {
          await db.query(
            `select public.soolgyul_complete_my_profile(
             gen_random_uuid(), '지호', date '1991-05-02', true, 'soolgyul-terms-v1',
             'soolgyul-privacy-v1', 'soolgyul-marketing-v1', true, true, false,
             null, false)`,
          );
        });
        const register = (token: string, platform = "android") =>
          db.query("select public.soolgyul_register_push_device($1, $2)", [
            token,
            platform,
          ]);
        const forget = (token: string) =>
          db.query("select public.soolgyul_unregister_push_device($1)", [
            token,
          ]);
        const stored = async () =>
          (await db.query<{ user_id: string; platform: string }>(
            `select user_id, platform from public.user_push_devices
             order by registered_at, token`,
          )).rows;

        await asRole(db, "authenticated", ids.activeUser, async () => {
          await assertRejects(
            () => register(phone),
            "active_account_required",
            "unfinished registration",
          );
        });
        await asRole(db, "anon", null, async () => {
          await assertRejects(
            () => register(phone),
            "permission denied",
            "visitor registration",
          );
        });
        await asRole(db, "authenticated", member, async () => {
          await register(phone);
          await register(phone, "ios");
          await assertRejects(
            () => register("short"),
            "push_token_invalid",
            "a token too short",
          );
          await assertRejects(
            () => register(phone, "web"),
            "push_platform_invalid",
            "a platform the app is not on",
          );
          for (
            const sql of [
              "select * from public.user_push_devices",
              `insert into public.user_push_devices (token, user_id, platform)
             values ('${"q".repeat(140)}', '${member}', 'android')`,
              "delete from public.user_push_devices",
            ]
          ) {
            await assertRejects(
              () => db.query(sql),
              "permission denied",
              "direct table access",
            );
          }
        });
        assertEquals(
          await stored(),
          [{ user_id: member, platform: "ios" }],
          "registered once",
        );

        // The next account on the same phone takes the address over, and
        // the one before cannot take it away again by forgetting.
        await asRole(db, "authenticated", other, () => register(phone).then());
        await asRole(db, "authenticated", member, () => forget(phone).then());
        assertEquals(
          await stored(),
          [{ user_id: other, platform: "android" }],
          "moved to the next account",
        );

        // Ten phones at most, the ones registered last.
        await asRole(db, "authenticated", other, async () => {
          for (let n = 0; n < 11; n++) {
            await register(String(n).padStart(2, "0").repeat(40));
          }
        });
        assertEquals((await stored()).length, 10, "ten phones at most");
        assertEquals(
          await rowCount(
            db,
            "select 1 from public.user_push_devices where token = $1",
            [phone],
          ),
          0,
          "the oldest phone is dropped",
        );

        // A member who is leaving can still be forgotten.
        const last = "10".repeat(40);
        await db.query(
          "update public.users set deletion_requested_at = now() where id = $1",
          [other],
        );
        await asRole(db, "authenticated", other, async () => {
          await assertRejects(
            () => register(phone),
            "active_account_required",
            "registration while leaving",
          );
          await forget(last);
        });
        assertEquals(
          await rowCount(
            db,
            "select 1 from public.user_push_devices where token = $1",
            [last],
          ),
          0,
          "forgotten while leaving",
        );

        // Removing the account removes its phones.
        await db.query("delete from auth.users where id = $1", [other]);
        assertEquals((await stored()).length, 0, "gone with the account");
      },
    );

    await t.step(
      "anyone reads the update and maintenance gate; no client changes it",
      async () => {
        for (const role of ["anon", "authenticated"] as const) {
          await asRole(
            db,
            role,
            role === "anon" ? null : ids.activeUser,
            async () => {
              const { rows } = await db.query<
                { platform: string; minimum_version: string; notice: null }
              >(
                `select platform, minimum_version, maintenance_message as notice
                 from public.app_gates order by platform`,
              );
              assertEquals(
                rows,
                ["android", "ios", "web"].map((platform) => ({
                  platform,
                  minimum_version: "0.0.0",
                  notice: null,
                })),
                `${role} reads the gate`,
              );
              await assertRejects(
                () =>
                  db.query(
                    "update public.app_gates set minimum_version = '9.0.0'",
                  ),
                "permission denied",
                `${role} raising the minimum`,
              );
            },
          );
        }
        await assertRejects(
          () =>
            db.query(
              "update public.app_gates set minimum_version = 'latest'",
            ),
          "app_gates_minimum_version_check",
          "a minimum that is not a version",
        );
      },
    );

    await t.step("owners read only their own active records", async () => {
      await insertRecord(db, {
        id: "f0000000-0000-4000-8000-000000000001",
        userId: ids.activeUser,
        anonymousSessionId: null,
        idempotencyKey: "key-active",
      });
      await insertRecord(db, {
        id: "f0000000-0000-4000-8000-000000000002",
        userId: ids.scheduledUser,
        anonymousSessionId: null,
        idempotencyKey: "key-scheduled",
      });
      await asRole(db, "authenticated", ids.activeUser, async () => {
        assertEquals(
          await rowCount(db, "select id from public.drink_records"),
          1,
          "active owner records",
        );
        // The app reads these through functions, never as tables.
        for (
          const table of [
            "drink_record_answers",
            "users",
            "user_consents",
            "user_drink_interests",
            "support_inquiries",
          ]
        ) {
          await assertRejects(
            () => db.query(`select * from public.${table}`),
            "permission denied",
            `owner reading ${table} directly`,
          );
        }
        const probe = (id: string) =>
          db.query<{ active: boolean }>(
            "select public.soolgyul_account_active($1) as active",
            [id],
          ).then((result) => result.rows[0].active);
        assertEquals(await probe(ids.activeUser), true, "asking about oneself");
        assertEquals(await probe(ids.editor), false, "asking about another");
        await assertRejects(
          () =>
            db.query(
              `insert into public.drink_records (user_id, questionnaire_version,
                 alcohol_item_id)
               values ($1, $2, $3)`,
              [ids.activeUser, ids.questionnaire, ids.item],
            ),
          "permission denied",
          "owner insert",
        );
      });
      await asRole(db, "authenticated", ids.scheduledUser, async () => {
        assertEquals(
          await rowCount(db, "select id from public.drink_records"),
          0,
          "scheduled owner records",
        );
        assertEquals(
          (await db.query<{ active: boolean }>(
            "select public.soolgyul_account_active($1) as active",
            [ids.scheduledUser],
          )).rows[0].active,
          false,
          "a leaving account is not active",
        );
      });
      await asRole(db, "anon", null, async () => {
        await assertRejects(
          () => db.query("select id from public.drink_records"),
          "permission denied",
          "anon records",
        );
        await assertRejects(
          () =>
            db.query("select public.soolgyul_account_active($1)", [
              ids.activeUser,
            ]),
          "permission denied",
          "anon account probe",
        );
      });
      // The server has no member of its own and asks about any account.
      assertEquals(
        (await db.query<{ active: boolean }>(
          "select public.soolgyul_account_active($1) as active",
          [ids.activeUser],
        )).rows[0].active,
        true,
        "the server asking about a member",
      );
    });

    await t.step(
      "the catalog is reached through the search, not read as tables",
      async () => {
        for (const role of ["anon", "authenticated"] as const) {
          await asRole(
            db,
            role,
            role === "anon" ? null : ids.activeUser,
            async () => {
              for (
                const sql of [
                  "select * from public.producers",
                  "select * from public.alcohol_categories",
                  "select * from public.alcohol_items",
                  "select * from public.catalog_media_assets",
                  "select * from public.soolgyul_search_alcohol_catalog('테스트', 5, 0)",
                ]
              ) {
                await assertRejects(
                  () => db.query(sql),
                  "permission denied",
                  `${role}: ${sql}`,
                );
              }
              const found = await db.query<{ result: { results: unknown[] } }>(
                "select public.soolgyul_search_catalog('테스트', 5, 0) as result",
              );
              assertEquals(
                found.rows[0].result.results.length,
                1,
                `${role} searching`,
              );
            },
          );
        }
      },
    );

    await t.step(
      "only the administrator web sees the post pictures' rows",
      async () => {
        const listed = () =>
          rowCount(
            db,
            "select name from storage.objects where bucket_id = 'soolgyul-editorial'",
          );
        await asRole(db, "anon", null, async () => {
          assertEquals(await listed(), 0, "a visitor listing");
        });
        await asRole(db, "authenticated", ids.activeUser, async () => {
          assertEquals(await listed(), 0, "a member listing");
        });
        await asRole(db, "authenticated", ids.editor, async () => {
          assertEquals(await listed(), 3, "an editor listing");
        });
      },
    );

    await t.step(
      "editors change only unpublished articles, media and objects",
      async () => {
        const update = (table: string, column: string, id: string) =>
          affectedRows(
            db,
            `update public.${table} set ${column} = ${column} where ${
              table === "editorial_articles" ? "id" : "article_id"
            } = '${id}' returning id`,
          );
        const deleteObject = (name: string) =>
          affectedRows(
            db,
            `delete from storage.objects where name = '${name}' returning id`,
          );
        await asRole(db, "authenticated", ids.editor, async () => {
          assertEquals(
            await update("editorial_articles", "body", ids.publishedArticle),
            0,
            "editor published article",
          );
          assertEquals(
            await update("editorial_articles", "body", ids.draftArticle),
            1,
            "editor draft article",
          );
          assertEquals(
            await update(
              "editorial_article_media_assets",
              "sort_order",
              ids.publishedArticle,
            ),
            0,
            "editor published media",
          );
          assertEquals(
            await update(
              "editorial_article_media_assets",
              "sort_order",
              ids.draftArticle,
            ),
            1,
            "editor draft media",
          );
          assertEquals(
            await deleteObject("articles/published/cover.webp"),
            0,
            "editor published object",
          );
          assertEquals(
            await deleteObject("articles/orphan.webp"),
            1,
            "editor orphan object",
          );
        });
        await asRole(db, "authenticated", ids.admin, async () => {
          assertEquals(
            await update("editorial_articles", "body", ids.publishedArticle),
            1,
            "admin published article",
          );
          assertEquals(
            await update(
              "editorial_article_media_assets",
              "sort_order",
              ids.publishedArticle,
            ),
            1,
            "admin published media",
          );
          assertEquals(
            await deleteObject("articles/published/cover.webp"),
            1,
            "admin published object",
          );
        });
        await asRole(db, "authenticated", ids.activeUser, async () => {
          assertEquals(
            await update("editorial_articles", "body", ids.draftArticle),
            0,
            "member article",
          );
          assertEquals(
            await deleteObject("articles/draft/cover.webp"),
            0,
            "member object",
          );
        });
      },
    );

    await t.step(
      "an anonymous card and a signed-in retry may share a client key",
      async () => {
        await insertRecord(db, {
          id: "f0000000-0000-4000-8000-000000000003",
          userId: null,
          anonymousSessionId: "session-shared",
          idempotencyKey: "shared-key",
        });
        await insertRecord(db, {
          id: "f0000000-0000-4000-8000-000000000004",
          userId: ids.activeUser,
          anonymousSessionId: null,
          idempotencyKey: "shared-key",
        });
      },
    );

    await t.step(
      "an anonymous session starts at most ten generations per day",
      async () => {
        const digest = "1".repeat(64);
        await insertAttempt(db, {
          ref: "limit-old",
          digest,
          createdAt: "2026-01-01T00:00:00Z",
        });
        for (let index = 0; index < 10; index += 1) {
          await insertAttempt(db, { ref: `limit-${index}`, digest });
        }
        await assertRejects(
          () => insertAttempt(db, { ref: "limit-overflow", digest }),
          "anonymous_generation_limit_reached",
          "eleventh attempt",
        );
        await insertAttempt(db, { ref: "limit-other", digest: "2".repeat(64) });
      },
    );

    await t.step(
      "one address starts at most five generations per day, whatever the session",
      async () => {
        const address = "c".repeat(64);
        const session = (index: number) => index.toString(16).padStart(64, "9");
        for (let index = 0; index < 5; index += 1) {
          await insertAttempt(db, {
            ref: `address-${index}`,
            digest: session(index),
            address,
          });
        }
        await assertRejects(
          () =>
            insertAttempt(db, {
              ref: "address-overflow",
              digest: session(5),
              address,
            }),
          "anonymous_generation_limit_reached",
          "sixth attempt from one address",
        );
        await insertAttempt(db, {
          ref: "address-other",
          digest: session(6),
          address: "d".repeat(64),
        });
      },
    );

    await t.step(
      "expired unclaimed anonymous data is purged in batches",
      async () => {
        const expiredRecord = "f0000000-0000-4000-8000-000000000011";
        const expiredCard = "f0000000-0000-4000-8000-000000000012";
        const expiredSnapshot = "f0000000-0000-4000-8000-000000000013";
        const recentRecord = "f0000000-0000-4000-8000-000000000014";
        const convertedRecord = "f0000000-0000-4000-8000-000000000015";
        const digest = "3".repeat(64);
        await insertRecord(db, {
          id: expiredRecord,
          userId: null,
          anonymousSessionId: "session-expired",
          idempotencyKey: "expired",
          createdAt: "2026-01-01T00:00:00Z",
        });
        await db.query(
          `insert into public.taste_cards
           (id, drink_record_id, lifecycle, snapshot_id, snapshot_ref,
            canonical_schema_version, semantic_snapshot, rendered_snapshot, snapshot_created_at)
         values ($1, $2, 'final', $3, 'snapshot-expired', 'v1', '{}', '{}', now())`,
          [expiredCard, expiredRecord, expiredSnapshot],
        );
        await insertAttempt(db, {
          ref: "purge-expired",
          digest,
          createdAt: "2026-01-01T00:00:00Z",
          final: {
            recordId: expiredRecord,
            cardId: expiredCard,
            snapshotId: expiredSnapshot,
          },
        });
        await insertRecord(db, {
          id: recentRecord,
          userId: null,
          anonymousSessionId: "session-recent",
          idempotencyKey: "recent",
        });
        await insertAttempt(db, {
          ref: "purge-recent",
          digest: "4".repeat(64),
        });
        await insertRecord(db, {
          id: convertedRecord,
          userId: ids.activeUser,
          anonymousSessionId: null,
          idempotencyKey: "converted",
          createdAt: "2026-01-01T00:00:00Z",
        });
        await insertAttempt(db, {
          ref: "purge-converted",
          digest: "5".repeat(64),
          createdAt: "2026-01-01T00:00:00Z",
        });

        const purged = await db.query<{ purged: number }>(
          "select public.soolgyul_purge_expired_anonymous_taste_cards() as purged",
        );
        assertEquals(purged.rows[0].purged, 1, "purged records");
        const remaining = await db.query<{ id: string }>(
          `select id from public.drink_records where id in ($1, $2, $3) order by id`,
          [expiredRecord, recentRecord, convertedRecord],
        );
        assertEquals(
          remaining.rows.map((row) => row.id),
          [recentRecord, convertedRecord],
          "remaining records",
        );
        assertEquals(
          await rowCount(
            db,
            `select id from public.drink_record_answers where drink_record_id = '${expiredRecord}'`,
          ),
          0,
          "expired answers",
        );
        assertEquals(
          await rowCount(
            db,
            `select id from public.taste_cards where id = '${expiredCard}'`,
          ),
          0,
          "expired card",
        );
        const attempts = await db.query<{ attempt_ref: string }>(
          `select attempt_ref from public.taste_card_generation_attempts
         where attempt_ref like 'purge-%' order by attempt_ref`,
        );
        assertEquals(
          attempts.rows.map((row) => row.attempt_ref),
          ["purge-recent"],
          "remaining attempts",
        );
        const job = await db.query<{ schedule: string; command: string }>(
          "select schedule, command from cron.job where jobname = 'soolgyul-anonymous-retention'",
        );
        assertEquals(
          job.rows,
          [{
            schedule: "20 * * * *",
            command:
              "select public.soolgyul_purge_expired_anonymous_taste_cards();",
          }],
          "retention job",
        );
      },
    );
  } finally {
    await db.close();
  }
});
