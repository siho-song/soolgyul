import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";

// Drink interests are keys on alcohol_categories.interest_key, one per
// selectable category; the user RPCs
// and editorial links point at those keys.

const USER = "a0000000-0000-4000-8000-000000000011";
const ARTICLE = "72000000-0000-4000-8000-000000000001";

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

async function seed(db: PGlite) {
  await db.exec(`
    insert into public.alcohol_categories (category_key, name_ko, sort_order, is_active, interest_key) values
      ('wine', '와인', 10, true, 'wine'),
      ('sake', '사케', 100, true, 'sake'),
      ('old_group', '옛 묶음', 50, false, null),
      ('retired', '퇴역', 999, false, 'retired');
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at)
      values ('${USER}', 'active@example.test', '{"provider":"kakao"}', now());
    insert into public.editorial_articles (id, body, status, published_at)
    values ('${ARTICLE}', '본문', 'published', now() - interval '1 day');
  `);
}

Deno.test("drink interests", async (t) => {
  const db = await createSupabaseLikeDatabase();
  await seed(db);

  await t.step("are stored and returned by category interest key", async () => {
    await asUser(db, async () => {
      const { rows } = await db.query<
        { result: { interest_group_keys: string[] } }
      >(
        "select public.soolgyul_replace_my_drink_interests($1, gen_random_uuid()) as result",
        [["sake", "wine"]],
      );
      const keys = rows[0].result.interest_group_keys;
      if (JSON.stringify(keys) !== JSON.stringify(["wine", "sake"])) {
        throw new Error(
          `category sort order expected, received ${JSON.stringify(keys)}`,
        );
      }
      const stored = await db.query<{ interest_key: string }>(
        "select interest_key from public.user_drink_interests where user_id = $1 order by interest_key",
        [USER],
      );
      if (
        stored.rows.map((row) => row.interest_key).join() !== "sake,wine"
      ) {
        throw new Error(`stored keys: ${JSON.stringify(stored.rows)}`);
      }
      const preferences = await db.query<
        { result: { interest_group_keys: string[] } }
      >(
        "select public.soolgyul_get_my_profile_preferences() as result",
      );
      if (
        JSON.stringify(preferences.rows[0].result.interest_group_keys) !==
          JSON.stringify(["wine", "sake"])
      ) {
        throw new Error(
          `preferences: ${JSON.stringify(preferences.rows[0].result)}`,
        );
      }
      for (
        const bad of [
          ["wine", "retired"],
          ["wine", "old_group"],
          ["wine", "other"],
          ["wine", "wine"],
        ]
      ) {
        let rejected = false;
        try {
          await db.query(
            "select public.soolgyul_replace_my_drink_interests($1, gen_random_uuid())",
            [bad],
          );
        } catch (error) {
          rejected = String(error).includes("drink_interest_keys_invalid");
        }
        if (!rejected) {
          throw new Error(`${JSON.stringify(bad)} should be rejected`);
        }
      }
    });
  });

  await t.step(
    "editorial posts link to interests by key, the save RPC validates them, and no key means a general post",
    async () => {
      await db.exec(`
    insert into public.admin_user_roles (user_id, role) values ('${USER}', 'admin');
  `);
      const save = (keys: string[]) =>
        db.query(
          `select public.soolgyul_admin_save_editorial_article($1, '본문', 'published', $2)`,
          [ARTICLE, keys],
        );
      const links = async () => {
        const { rows } = await db.query<{ interest_key: string }>(
          "select interest_key from public.editorial_article_interests where article_id = $1 order by interest_key",
          [ARTICLE],
        );
        return rows.map((row) => row.interest_key).join();
      };
      await asUser(db, async () => {
        await save(["sake", "wine", "wine"]);
        if (await links() !== "sake,wine") {
          throw new Error(`links: ${await links()}`);
        }
        await save([]);
        if (await links() !== "") {
          throw new Error("a post with no interest keys keeps no links");
        }
        let rejected = false;
        try {
          await save(["beer"]);
        } catch (error) {
          rejected = String(error).includes("unknown interest key");
        }
        if (!rejected) {
          throw new Error(
            "an interest key no category offers should be rejected",
          );
        }
      });
      // The link table itself refuses keys no category carries.
      let fkRejected = false;
      try {
        await db.query(
          "insert into public.editorial_article_interests (article_id, interest_key) values ($1, 'other')",
          [ARTICLE],
        );
      } catch (error) {
        fkRejected = String(error).includes("foreign key");
      }
      if (!fkRejected) throw new Error("'other' is no longer an interest key");
    },
  );

  await t.step("profile preferences return the stored gender", async () => {
    const read = async () => {
      let gender: unknown = "unread";
      await asUser(db, async () => {
        const { rows } = await db.query<{ result: { gender: unknown } }>(
          "select public.soolgyul_get_my_profile_preferences() as result",
        );
        gender = rows[0].result.gender;
      });
      return gender;
    };
    if (await read() !== null) throw new Error("no gender reads as null");
    await db.query(
      `update public.users set gender = 'female', gender_consent_accepted_at = now(),
       gender_consent_version = 'soolgyul-gender-v1' where id = $1`,
      [USER],
    );
    const stored = await read();
    if (stored !== "female") throw new Error(`gender: ${stored}`);
  });

  await db.close();
});
