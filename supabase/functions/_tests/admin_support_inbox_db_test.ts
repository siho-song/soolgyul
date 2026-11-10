import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "./helpers/pglite_supabase.ts";

// The support inbox: only an admin reads it or marks an inquiry answered,
// every such read and mark is logged, and no client reads the log.

const MEMBER = "a0000000-0000-4000-8000-000000000051";
const EDITOR = "a0000000-0000-4000-8000-000000000052";
const ADMIN = "a0000000-0000-4000-8000-000000000053";
const OLD = "b0000000-0000-4000-8000-000000000001";
const NEW = "b0000000-0000-4000-8000-000000000002";

async function as<T>(
  db: PGlite,
  user: string,
  work: () => Promise<T>,
): Promise<T> {
  await db.exec("set role authenticated;");
  await db.query("select set_config('request.jwt.claims', $1, false)", [
    JSON.stringify({ sub: user }),
  ]);
  try {
    return await work();
  } finally {
    await db.exec("reset role;");
  }
}

async function refusal(work: () => Promise<unknown>) {
  try {
    await work();
  } catch (error) {
    return (error as Error).message;
  }
  return null;
}

async function setUp() {
  const db = await createSupabaseLikeDatabase();
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${MEMBER}', 'member@example.test', '{"provider":"google"}', now()),
      ('${EDITOR}', 'editor@admin.soolgyul.com', '{"provider":"email"}', now()),
      ('${ADMIN}', 'admin@admin.soolgyul.com', '{"provider":"email"}', now());
    insert into public.admin_user_roles (user_id, role) values
      ('${EDITOR}', 'editor'), ('${ADMIN}', 'admin');
    insert into public.support_inquiries
      (id, user_id, inquiry_type, reply_email, content, attachment_paths, created_at)
    values
      ('${OLD}', '${MEMBER}', 'bug', 'member@example.test', '앱이 멈춰요',
        array['${MEMBER}/inquiries/${OLD}/0-a.jpg'], now() - interval '2 days'),
      ('${NEW}', '${MEMBER}', 'usage', 'member@example.test', '기록은 어디서 봐요?',
        '{}', now() - interval '1 day');
  `);
  return db;
}

const list = (db: PGlite) =>
  db.query<{ id: string; answered_at: string | null }>(
    "select id, answered_at from public.soolgyul_admin_list_support_inquiries()",
  );

Deno.test("an admin lists open inquiries first and every read is logged", async () => {
  const db = await setUp();
  const first = await as(db, ADMIN, () => list(db));
  if (first.rows.map((row) => row.id).join() !== `${NEW},${OLD}`) {
    throw new Error(`newest first, got ${first.rows.map((row) => row.id)}`);
  }
  await as(db, ADMIN, () =>
    db.query(
      "select public.soolgyul_admin_set_support_inquiry_answered($1, true)",
      [NEW],
    ));
  const second = await as(db, ADMIN, () => list(db));
  if (
    second.rows.map((row) => row.id).join() !== `${OLD},${NEW}` ||
    second.rows[1].answered_at === null
  ) {
    throw new Error("an answered inquiry moves below the open ones");
  }
  await as(db, ADMIN, () =>
    db.query(
      "select public.soolgyul_admin_set_support_inquiry_answered($1, false)",
      [NEW],
    ));
  const { rows } = await db.query<
    { admin_user_id: string; action: string; inquiry_ids: string[] }
  >(
    "select admin_user_id, action, inquiry_ids from public.admin_access_logs order by id",
  );
  const logged = rows.map((row) =>
    `${row.admin_user_id === ADMIN} ${row.action} ${row.inquiry_ids.length}`
  );
  const expected = [
    "true list_support_inquiries 2",
    "true answer_support_inquiry 1",
    "true list_support_inquiries 2",
    "true reopen_support_inquiry 1",
  ];
  if (JSON.stringify(logged) !== JSON.stringify(expected)) {
    throw new Error(`log, got ${logged}`);
  }
});

Deno.test("a member or an editor cannot read the inbox or the log", async () => {
  const db = await setUp();
  for (const user of [MEMBER, EDITOR]) {
    const message = await as(db, user, () => refusal(() => list(db)));
    if (!message?.includes("admin_role_required")) {
      throw new Error(`${user} reads the inbox: ${message}`);
    }
    const mark = await as(db, user, () =>
      refusal(() =>
        db.query(
          "select public.soolgyul_admin_set_support_inquiry_answered($1, true)",
          [OLD],
        )
      ));
    if (!mark?.includes("admin_role_required")) {
      throw new Error(`${user} marks an inquiry: ${mark}`);
    }
  }
  const log = await as(
    db,
    ADMIN,
    () => refusal(() => db.query("select * from public.admin_access_logs")),
  );
  if (log === null) throw new Error("an admin reads the access log");
});

Deno.test("an admin may open inquiry photos, not other private files", async () => {
  const db = await setUp();
  await db.exec(`
    insert into storage.objects (bucket_id, name) values
      ('soolgyul-private', '${MEMBER}/inquiries/${OLD}/0-a.jpg'),
      ('soolgyul-private', '${MEMBER}/other/x.jpg');
  `);
  const names = (user: string) =>
    as(db, user, async () =>
      (await db.query<{ name: string }>(
        "select name from storage.objects order by name",
      )).rows.map((row) => row.name).join());
  if (await names(ADMIN) !== `${MEMBER}/inquiries/${OLD}/0-a.jpg`) {
    throw new Error(`admin sees ${await names(ADMIN)}`);
  }
  if (await names(EDITOR) !== "") {
    throw new Error(`editor sees ${await names(EDITOR)}`);
  }
});
