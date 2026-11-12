import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { rejects, same } from "../helpers/assert.ts";

// The seed deletes terms that left the dictionary. A term a product or a
// tasting profile still uses cannot go; the check runs at commit, so a seed
// may add the new key, move the products and delete the old key in any order.

const CATEGORY = "c0000000-0000-4000-8000-000000000081";
const ITEM = "e0000000-0000-4000-8000-000000000081";

Deno.test("a catalog term still in use cannot be deleted", async (t) => {
  const db = await createSupabaseLikeDatabase();
  try {
    const { rows: [{ aroma }] } = await db.query<{ aroma: string }>(
      `select term.term_key as aroma from public.catalog_taxonomy term
       where term.term_type = 'sensory_descriptor' and term.is_active
         and 'aroma' = any(term.applicable_sections)
         and not exists (
           select 1 from public.catalog_taxonomy child
           where child.term_type = term.term_type
             and child.parent_term_key = term.term_key)
       order by term.term_key limit 1`,
    );
    await db.exec(`
      insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
        values ('${CATEGORY}', 'wine', '와인', 1);
      insert into public.alcohol_items
        (id, name_ko, alcohol_category_id, style_key, region_key)
        values ('${ITEM}', '테스트 와인', '${CATEGORY}', 'red_wine', 'fr_chiroubles');
      insert into public.alcohol_tasting_profiles (alcohol_item_id, aroma_tags)
        values ('${ITEM}', array['${aroma}']);
    `);
    const remove = (type: string, key: string) =>
      db.query(
        "delete from public.catalog_taxonomy where term_type = $1 and term_key = $2",
        [type, key],
      );
    const exists = async (type: string, key: string) =>
      (await db.query<{ n: number }>(
        `select count(*)::int as n from public.catalog_taxonomy
         where term_type = $1 and term_key = $2`,
        [type, key],
      )).rows[0].n === 1;

    await t.step("a product's style, region and aroma stay", async () => {
      for (
        const [type, key] of [
          ["style", "red_wine"],
          ["region", "fr_chiroubles"],
          ["sensory_descriptor", aroma],
        ]
      ) {
        await rejects(
          () => remove(type, key),
          "is still used by the catalog",
          `${type}:${key}`,
        );
        same(await exists(type, key), true, `${type}:${key} kept`);
      }
    });

    await t.step("a term nobody uses can be deleted", async () => {
      await remove("style", "white_wine");
      same(await exists("style", "white_wine"), false, "deleted");
    });

    await t.step(
      "a renamed key passes when the products move in the same transaction",
      async () => {
        await db.exec(`
          begin;
          delete from public.catalog_taxonomy
            where term_type = 'region' and term_key = 'fr_chiroubles';
          insert into public.catalog_taxonomy
            (term_type, term_key, label_ko, parent_term_key, applicable_sections,
             taxonomy_version)
            values ('region', 'fr_chiroubles_cru', '시루블', 'fr_beaujolais',
                    array['region'], '2.0.0');
          update public.alcohol_items set region_key = 'fr_chiroubles_cru'
            where id = '${ITEM}';
          commit;
        `);
        same(await exists("region", "fr_chiroubles"), false, "old key gone");
      },
    );
  } finally {
    await db.close();
  }
});
