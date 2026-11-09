import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "./helpers/pglite_supabase.ts";

// Notices and FAQ answers: the site reads only what is published, an editor
// writes drafts only, an admin publishes and deletes.

const EDITOR = "a0000000-0000-4000-8000-000000000041";
const ADMIN = "a0000000-0000-4000-8000-000000000042";

async function as(
  db: PGlite,
  role: "anon" | "authenticated",
  user: string | null,
  work: () => Promise<void>,
) {
  await db.exec(`set role ${role};`);
  await db.query("select set_config('request.jwt.claims', $1, false)", [
    JSON.stringify(user ? { sub: user } : {}),
  ]);
  try {
    await work();
  } finally {
    await db.exec("reset role;");
  }
}

async function refused(work: () => Promise<unknown>) {
  try {
    await work();
  } catch {
    return true;
  }
  return false;
}

async function setUp() {
  const db = await createSupabaseLikeDatabase();
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${EDITOR}', 'editor@admin.soolgyul.com', '{"provider":"email"}', now()),
      ('${ADMIN}', 'admin@admin.soolgyul.com', '{"provider":"email"}', now());
    insert into public.admin_user_roles (user_id, role) values
      ('${EDITOR}', 'editor'), ('${ADMIN}', 'admin');
  `);
  return db;
}

Deno.test("the site reads the published FAQ answers in order", async () => {
  const db = await setUp();
  await db.exec(`
    insert into public.site_posts (kind, title, status) values
      ('notice', '초안 공지', 'draft'),
      ('notice', '내린 공지', 'withdrawn'),
      ('notice', '새 공지', 'published');
  `);
  await as(db, "anon", null, async () => {
    const { rows } = await db.query<{ kind: string; title: string }>(
      "select kind, title from public.site_posts order by kind, sort_order",
    );
    const titles = rows.map((row) => `${row.kind}:${row.title}`);
    const expected = [
      "faq:기록을 수정하거나 삭제할 수 있나요?",
      "faq:찾는 술이 없거나 술 정보가 틀려요.",
      "faq:다른 방법으로 로그인했더니 기록이 없어요.",
      "faq:탈퇴했는데 다시 쓰고 싶어요.",
      "notice:새 공지",
    ];
    if (JSON.stringify(titles) !== JSON.stringify(expected)) {
      throw new Error(`anon reads only published rows, got ${titles}`);
    }
    if (
      await refused(() =>
        db.exec(
          "insert into public.site_posts (kind, title) values ('notice', 'x')",
        )
      ) === false
    ) {
      throw new Error("anon cannot write");
    }
  });
  await db.close();
});

Deno.test("an editor writes drafts, an admin publishes and deletes", async () => {
  const db = await setUp();
  let id = "";
  await as(db, "authenticated", EDITOR, async () => {
    const { rows } = await db.query<{ id: string }>(
      "insert into public.site_posts (kind, title, body) values ('notice', '점검 안내', '본문') returning id",
    );
    id = rows[0].id;
    if (
      await refused(() =>
        db.query(
          "update public.site_posts set status = 'published' where id = $1",
          [id],
        )
      ) === false
    ) {
      throw new Error("an editor cannot publish");
    }
    await db.query("delete from public.site_posts where id = $1", [id]);
  });
  const count = async () =>
    (await db.query<{ n: number }>(
      "select count(*)::int as n from public.site_posts where id = $1",
      [id],
    )).rows[0].n;
  if (await count() !== 1) throw new Error("an editor cannot delete");

  await as(db, "authenticated", ADMIN, async () => {
    await db.query(
      "update public.site_posts set status = 'published' where id = $1",
      [id],
    );
  });
  const { rows } = await db.query<{ published_at: string | null }>(
    "select published_at from public.site_posts where id = $1",
    [id],
  );
  if (rows[0].published_at === null) {
    throw new Error("publishing stamps the time");
  }

  await as(db, "authenticated", EDITOR, async () => {
    const { affectedRows } = await db.query(
      "update public.site_posts set title = '바꿈' where id = $1",
      [id],
    );
    if (affectedRows) {
      throw new Error("an editor cannot change a published notice");
    }
  });
  await as(db, "authenticated", ADMIN, async () => {
    await db.query("delete from public.site_posts where id = $1", [id]);
  });
  if (await count() !== 0) throw new Error("an admin deletes");
  await db.close();
});
