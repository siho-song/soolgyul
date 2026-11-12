import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { asUser, refusal } from "../helpers/db_session.ts";
import { same } from "../helpers/assert.ts";

// A marketing notification: only an admin starts one, it reaches the phones
// of active members whose marketing consent stands, the same send is not
// started twice, and closing it forgets the phones that are gone.

const ADMIN = "a0000000-0000-4000-8000-000000000061";
const EDITOR = "a0000000-0000-4000-8000-000000000062";
const AGREED = "a0000000-0000-4000-8000-000000000063";
const WITHDREW = "a0000000-0000-4000-8000-000000000064";
const NEVER = "a0000000-0000-4000-8000-000000000065";
const LEAVING = "a0000000-0000-4000-8000-000000000066";
const PUSH = "c0000000-0000-4000-8000-000000000001";

const token = (name: string) => name.padEnd(40, "-");

async function setUp() {
  const db = await createSupabaseLikeDatabase();
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${ADMIN}', 'admin@admin.soolgyul.com', '{"provider":"email","soolgyul_staff":"true"}', now()),
      ('${EDITOR}', 'editor@admin.soolgyul.com', '{"provider":"email","soolgyul_staff":"true"}', now()),
      ('${AGREED}', 'agreed@example.test', '{"provider":"google"}', now()),
      ('${WITHDREW}', 'withdrew@example.test', '{"provider":"google"}', now()),
      ('${NEVER}', 'never@example.test', '{"provider":"google"}', now()),
      ('${LEAVING}', 'leaving@example.test', '{"provider":"google"}', now());
    insert into public.admin_user_roles (user_id, role) values
      ('${ADMIN}', 'admin'), ('${EDITOR}', 'editor');
    insert into public.user_consents
      (user_id, consent_type, document_version, accepted_at, withdrawn_at)
    values
      ('${AGREED}', 'marketing', 'soolgyul-marketing-v1', now() - interval '2 days', null),
      ('${WITHDREW}', 'marketing', 'soolgyul-marketing-v1', now() - interval '2 days', now()),
      ('${LEAVING}', 'marketing', 'soolgyul-marketing-v1', now() - interval '2 days', null);
    insert into public.user_push_devices (token, user_id, platform) values
      ('${token("agreed-phone")}', '${AGREED}', 'ios'),
      ('${token("agreed-tablet")}', '${AGREED}', 'android'),
      ('${token("withdrew-phone")}', '${WITHDREW}', 'ios'),
      ('${token("never-phone")}', '${NEVER}', 'android'),
      ('${token("leaving-phone")}', '${LEAVING}', 'ios');
    update public.users set deletion_requested_at = now() where id = '${LEAVING}';
  `);
  return db;
}

const start = (
  db: PGlite,
  id = PUSH,
  title = "주말 한 잔",
  body = "새 글이 올라왔어요",
) =>
  db.query(
    "select public.soolgyul_admin_start_marketing_push($1, $2, $3)",
    [id, title, body],
  );

const overview = async (db: PGlite) =>
  (await db.query<{ overview: Record<string, unknown> }>(
    "select public.soolgyul_admin_marketing_push_overview() as overview",
  )).rows[0].overview;

Deno.test("a marketing notification reaches only active members whose consent stands", async () => {
  const db = await setUp();
  const { rows } = await db.query<{ token: string }>(
    "select token from public.soolgyul_marketing_push_devices()",
  );
  same(rows.map((row) => row.token), [
    token("agreed-phone"),
    token("agreed-tablet"),
  ]);
  const seen = await asUser(db, ADMIN, () => overview(db));
  same([seen.member_count, seen.device_count, seen.pushes], [1, 2, []]);
});

Deno.test("only an admin starts a send, and the same send only once", async () => {
  const db = await setUp();
  for (const caller of [EDITOR, AGREED]) {
    const refused = await refusal(() => asUser(db, caller, () => start(db)));
    same(refused, "admin_role_required", `start as ${caller}`);
    const hidden = await refusal(() => asUser(db, caller, () => overview(db)));
    same(hidden, "admin_role_required", `overview as ${caller}`);
  }
  for (
    const [title, body] of [["", "내용"], ["제목", " "], [
      "가".repeat(31),
      "내용",
    ], [
      "제목",
      "가".repeat(101),
    ]]
  ) {
    const refused = await refusal(() =>
      asUser(db, ADMIN, () => start(db, PUSH, title, body))
    );
    same(refused, "marketing_push_invalid", `"${title}" / "${body}"`);
  }
  await asUser(
    db,
    ADMIN,
    () => start(db, PUSH, "  주말 한 잔 ", "새 글이 올라왔어요"),
  );
  const again = await refusal(() => asUser(db, ADMIN, () => start(db)));
  if (again === null || !again.includes("marketing_pushes_pkey")) {
    throw new Error(`a repeated send is refused, got ${again}`);
  }
  const { rows } = await db.query(
    "select admin_user_id, title, finished_at from public.marketing_pushes",
  );
  same(rows, [{
    admin_user_id: ADMIN,
    title: "주말 한 잔",
    finished_at: null,
  }]);
});

Deno.test("closing a send keeps its counts and forgets the phones that are gone", async () => {
  const db = await setUp();
  await asUser(db, ADMIN, () => start(db));
  const finish = () =>
    db.query(
      "select public.soolgyul_finish_marketing_push($1, 2, 1, $2)",
      [PUSH, [token("agreed-tablet")]],
    );
  await finish();
  const left = await db.query<{ token: string }>(
    "select token from public.soolgyul_marketing_push_devices()",
  );
  same(left.rows.map((row) => row.token), [token("agreed-phone")]);
  const seen = await asUser(db, ADMIN, () => overview(db));
  const pushes = seen.pushes as Array<Record<string, unknown>>;
  same(
    [seen.device_count, pushes.length, pushes[0].id, pushes[0].body],
    [1, 1, PUSH, "새 글이 올라왔어요"],
  );
  same(
    [
      pushes[0].device_count,
      pushes[0].sent_count,
      pushes[0].finished_at !== null,
    ],
    [2, 1, true],
  );
  same(await refusal(finish), "marketing_push_not_open", "closing twice");
});

Deno.test("no client reads the sends or the phones, or closes a send", async () => {
  const db = await setUp();
  await asUser(db, ADMIN, () => start(db));
  for (
    const query of [
      "select * from public.marketing_pushes",
      "select * from public.soolgyul_marketing_push_devices()",
      `select public.soolgyul_finish_marketing_push('${PUSH}', 0, 0, '{}')`,
    ]
  ) {
    const refused = await refusal(() =>
      asUser(db, ADMIN, () => db.query(query))
    );
    if (refused === null || !refused.includes("permission denied")) {
      throw new Error(`${query}: expected a refusal, got ${refused}`);
    }
  }
});
