import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { asUser } from "../helpers/db_session.ts";
import { rejects, same } from "../helpers/assert.ts";

// A post is published only with a photo; the refusal is a message the
// administrator web can tell apart (P0001 article_photo_required).

const ADMIN = "a0000000-0000-4000-8000-000000000071";
const ARTICLE = "d0000000-0000-4000-8000-000000000071";

Deno.test("publishing a post needs a photo", async () => {
  const db = await createSupabaseLikeDatabase();
  try {
    await db.exec(`
      insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at)
        values ('${ADMIN}', 'admin@admin.soolgyul.com', '{"provider":"email","soolgyul_staff":"true"}', now());
      insert into public.admin_user_roles (user_id, role) values ('${ADMIN}', 'admin');
      insert into public.editorial_articles (id, body, status) values ('${ARTICLE}', '사진 없는 글', 'draft');
    `);
    const publish = () =>
      db.query("select public.soolgyul_admin_change_editorial_status($1, $2)", [
        ARTICLE,
        "published",
      ]);
    const status = async () =>
      (await db.query<{ status: string }>(
        "select status from public.editorial_articles where id = $1",
        [ARTICLE],
      )).rows[0].status;

    await asUser(db, ADMIN, async () => {
      let code: string | undefined;
      try {
        await publish();
      } catch (error) {
        code = (error as { code?: string }).code;
      }
      same(code, "P0001", "refusal code");
      await rejects(publish, "article_photo_required", "a post without photos");
    });
    same(await status(), "draft", "the post stays a draft");

    await db.exec(`
      insert into public.editorial_article_media_assets
        (article_id, storage_bucket, storage_object_path)
      values ('${ARTICLE}', 'soolgyul-editorial', 'articles/a/cover.webp');
    `);
    await asUser(db, ADMIN, () => publish().then());
    same(await status(), "published", "a post with a photo is published");

    await asUser(db, ADMIN, async () => {
      await rejects(
        () =>
          db.query(
            "select public.soolgyul_admin_change_editorial_status($1, 'published')",
            ["d0000000-0000-4000-8000-000000000099"],
          ),
        "article not found",
        "a post that does not exist",
      );
    });
  } finally {
    await db.close();
  }
});
