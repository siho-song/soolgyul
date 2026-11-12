import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { refusal } from "../helpers/db_session.ts";
import { handleRetentionJob } from "../../account-retention-purge/index.ts";

// Six months after its answer an inquiry is kept as its type and words only,
// once its photos are gone; photos no inquiry lists are due after a day.

const MEMBER = "a0000000-0000-4000-8000-000000000061";
const DUE = "b0000000-0000-4000-8000-000000000011";
const RECENT = "b0000000-0000-4000-8000-000000000012";
const OPEN = "b0000000-0000-4000-8000-000000000013";
const NEVER_SENT = "b0000000-0000-4000-8000-000000000014";
const DUE_PHOTO = `${MEMBER}/inquiries/${DUE}/0-a.jpg`;
const LEFT_PHOTO = `${MEMBER}/inquiries/${NEVER_SENT}/0-b.jpg`;
const FRESH_PHOTO = `${MEMBER}/inquiries/${NEVER_SENT}/1-c.jpg`;

async function setUp() {
  const db = await createSupabaseLikeDatabase();
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${MEMBER}', 'member@example.test', '{"provider":"google"}', now());
    insert into public.support_inquiries
      (id, user_id, inquiry_type, reply_email, content, attachment_paths,
       created_at, answered_at)
    values
      ('${DUE}', '${MEMBER}', 'bug', 'member@example.test', '앱이 멈춰요',
        array['${DUE_PHOTO}'], now() - interval '8 months', now() - interval '7 months'),
      ('${RECENT}', '${MEMBER}', 'usage', 'member@example.test', '기록은 어디서 봐요?',
        '{}', now() - interval '2 months', now() - interval '1 month'),
      ('${OPEN}', '${MEMBER}', 'other', 'member@example.test', '답을 기다려요',
        '{}', now() - interval '1 year', null);
    insert into storage.objects (bucket_id, name, created_at) values
      ('soolgyul-private', '${DUE_PHOTO}', now() - interval '8 months'),
      ('soolgyul-private', '${LEFT_PHOTO}', now() - interval '2 days'),
      ('soolgyul-private', '${FRESH_PHOTO}', now() - interval '1 hour'),
      ('soolgyul-private', '${MEMBER}/elsewhere/old.jpg', now() - interval '1 year');
  `);
  return db;
}

const close = (db: PGlite, id: string) =>
  db.query("select public.soolgyul_close_support_inquiry($1) as closed", [id]);

async function withOwn(work: (db: PGlite) => Promise<void>) {
  const db = await setUp();
  try {
    await work(db);
  } finally {
    await db.close();
  }
}

Deno.test("only an inquiry answered six months ago is due", () =>
  withOwn(async (db) => {
    const due = await db.query<{ id: string; attachment_paths: string[] }>(
      "select * from public.soolgyul_due_support_inquiries()",
    );
    if (
      due.rows.length !== 1 || due.rows[0].id !== DUE ||
      due.rows[0].attachment_paths.join() !== DUE_PHOTO
    ) {
      throw new Error(`due: ${JSON.stringify(due.rows)}`);
    }
    for (const id of [RECENT, OPEN]) {
      const message = await refusal(() => close(db, id));
      if (message !== "inquiry_not_due") throw new Error(`${id}: ${message}`);
    }
  }));

Deno.test("a due inquiry closes once its photos are gone, keeping type and words only", () =>
  withOwn(async (db) => {
    const early = await refusal(() => close(db, DUE));
    if (early !== "inquiry_storage_cleanup_required") {
      throw new Error(`closed with its photo still stored: ${early}`);
    }
    await db.query("delete from storage.objects where name = $1", [DUE_PHOTO]);
    await close(db, DUE);

    const left = await db.query<{ id: string }>(
      "select id from public.support_inquiries order by id",
    );
    if (left.rows.map((row) => row.id).join() !== `${RECENT},${OPEN}`) {
      throw new Error(`inbox after closing: ${JSON.stringify(left.rows)}`);
    }
    const kept = await db.query<Record<string, unknown>>(
      "select * from public.closed_support_inquiries",
    );
    if (
      kept.rows.length !== 1 ||
      Object.keys(kept.rows[0]).sort().join() !== "content,id,inquiry_type" ||
      kept.rows[0].id === DUE ||
      kept.rows[0].inquiry_type !== "bug" ||
      kept.rows[0].content !== "앱이 멈춰요"
    ) {
      throw new Error(`kept: ${JSON.stringify(kept.rows)}`);
    }
    // A second run finds nothing to close.
    const again = await close(db, DUE);
    if ((again.rows[0] as { closed: boolean }).closed !== false) {
      throw new Error("closing twice must do nothing");
    }
  }));

Deno.test("a photo no inquiry lists is due a day after its upload", () =>
  withOwn(async (db) => {
    const stale = await db.query<{ name: string }>(
      "select public.soolgyul_stale_inquiry_uploads() as name",
    );
    if (stale.rows.map((row) => row.name).join() !== LEFT_PHOTO) {
      throw new Error(`stale: ${JSON.stringify(stale.rows)}`);
    }
  }));

Deno.test("no client reads the kept inquiries or asks what is due", () =>
  withOwn(async (db) => {
    await db.exec("set role authenticated;");
    try {
      for (
        const statement of [
          "select * from public.closed_support_inquiries",
          "select * from public.soolgyul_due_support_inquiries()",
          "select public.soolgyul_stale_inquiry_uploads()",
          `select public.soolgyul_close_support_inquiry('${DUE}')`,
        ]
      ) {
        const message = await refusal(() => db.query(statement));
        if (!message?.includes("permission denied")) {
          throw new Error(`${statement}: ${message}`);
        }
      }
    } finally {
      await db.exec("reset role;");
    }
  }));

// The scheduled function run against the database: its calls are answered
// from the tables the way the REST and Storage APIs answer them.
function apiOver(db: PGlite) {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status });
  return (async (url: string | URL | Request, init?: RequestInit) => {
    const path = String(url);
    const body = init?.body ? JSON.parse(String(init.body)) : {};
    if (path.includes("/rest/v1/users?select=id&")) return json([]);
    if (path.endsWith("/rpc/soolgyul_due_support_inquiries")) {
      const due = await db.query(
        "select * from public.soolgyul_due_support_inquiries()",
      );
      return json(due.rows);
    }
    if (path.endsWith("/rpc/soolgyul_stale_inquiry_uploads")) {
      const stale = await db.query<{ name: string }>(
        "select public.soolgyul_stale_inquiry_uploads() as name",
      );
      return json(stale.rows.map((row) => row.name));
    }
    if (path.endsWith("/storage/v1/object/soolgyul-private")) {
      await db.query(
        "delete from storage.objects where bucket_id = 'soolgyul-private' and name = any($1)",
        [body.prefixes],
      );
      return json([]);
    }
    if (path.endsWith("/rpc/soolgyul_close_support_inquiry")) {
      try {
        await close(db, body.target_inquiry_id);
        return json(true);
      } catch (error) {
        return json({ message: (error as Error).message }, 400);
      }
    }
    throw new Error("unexpected call " + path);
  }) as typeof fetch;
}

Deno.test("the scheduled job closes the old inquiry and clears the photos nobody sent", () =>
  withOwn(async (db) => {
    const env = (name: string) =>
      ({
        ACCOUNT_RETENTION_JOB_SECRET: "scheduler",
        SUPABASE_URL: "https://db.test",
        SUPABASE_SERVICE_ROLE_KEY: "service",
      })[name];
    const run = () =>
      handleRetentionJob(
        new Request("https://edge.test", {
          method: "POST",
          headers: { Authorization: "Bearer scheduler" },
        }),
        env,
        apiOver(db),
      );
    const first = await run();
    const report = JSON.stringify(await first.json());
    if (
      first.status !== 200 ||
      report !==
        '{"completed":0,"failed":0,"inquiries":{"closed":1,"failed":0,"stale_uploads":1}}'
    ) {
      throw new Error(`first run: ${first.status} ${report}`);
    }
    const state = await db.query<
      { inbox: string; kept: string; files: string }
    >(`
    select
      (select string_agg(id::text, ',' order by id) from public.support_inquiries) as inbox,
      (select string_agg(inquiry_type || ':' || content, ',') from public.closed_support_inquiries) as kept,
      (select string_agg(name, ',' order by name) from storage.objects) as files`);
    const { inbox, kept, files } = state.rows[0];
    if (
      inbox !== `${RECENT},${OPEN}` || kept !== "bug:앱이 멈춰요" ||
      files !== `${MEMBER}/elsewhere/old.jpg,${FRESH_PHOTO}`
    ) {
      throw new Error(`after the run: ${JSON.stringify(state.rows[0])}`);
    }
    // The next hour finds nothing left to do.
    const second = JSON.stringify(await (await run()).json());
    if (!second.includes('"closed":0,"failed":0,"stale_uploads":0')) {
      throw new Error(`second run: ${second}`);
    }
  }));
