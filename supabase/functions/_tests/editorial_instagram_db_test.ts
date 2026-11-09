import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "./helpers/pglite_supabase.ts";

// A post may link the same post on Instagram. The save RPC stores the
// address, drops a blank one, and the table refuses anything that is not an
// instagram.com address.

const USER = "a0000000-0000-4000-8000-000000000031";

async function asUser(db: PGlite, work: () => Promise<void>) {
  await db.exec("set role authenticated;");
  await db.query("select set_config('request.jwt.claims', $1, false)", [
    JSON.stringify({ sub: USER }),
  ]);
  try {
    await work();
  } finally {
    await db.exec("reset role;");
  }
}

Deno.test("the save RPC stores a post's Instagram address", async () => {
  const db = await createSupabaseLikeDatabase();
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at)
      values ('${USER}', 'admin@admin.soolgyul.com', '{"provider":"email"}', now());
    insert into public.admin_user_roles (user_id, role) values ('${USER}', 'admin');
  `);
  const instagramUrl = async (id: string) => {
    const { rows } = await db.query<{ instagram_url: string | null }>(
      "select instagram_url from public.editorial_articles where id = $1",
      [id],
    );
    return rows[0].instagram_url;
  };
  const save = (id: string | null, link: string | null) =>
    db.query<{ id: string }>(
      "select public.soolgyul_admin_save_editorial_article($1, '', 'draft', '{}', $2) as id",
      [id, link],
    );
  await asUser(db, async () => {
    const { rows } = await save(null, null);
    const id = rows[0].id;
    if (await instagramUrl(id) !== null) {
      throw new Error("a post saved without a link has none");
    }
    await save(id, "https://www.instagram.com/p/ABC123/");
    if (await instagramUrl(id) !== "https://www.instagram.com/p/ABC123/") {
      throw new Error("the Instagram address is stored as given");
    }
    await save(id, "  ");
    if (await instagramUrl(id) !== null) {
      throw new Error("a blank link clears the address");
    }
    let refused = false;
    try {
      await save(id, "https://example.com/p/ABC123/");
    } catch {
      refused = true;
    }
    if (!refused) {
      throw new Error("an address outside instagram.com is refused");
    }
  });
  await db.close();
});
