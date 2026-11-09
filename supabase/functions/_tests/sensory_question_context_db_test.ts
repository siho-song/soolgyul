import { createSupabaseLikeDatabase } from "./helpers/pglite_supabase.ts";

// The questionnaire loads its product context through this RPC. It must keep
// working after every column migration.

Deno.test("soolgyul_get_sensory_question_context returns the published product with its levels", async () => {
  const db = await createSupabaseLikeDatabase();
  await db.exec(`
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('c0000000-0000-4000-8000-000000000001', 'wine', '와인', 1);
    insert into public.alcohol_items (id, name_ko, name_en, alcohol_category_id, abv_percent, publish_status, published_at)
      values
      ('e0000000-0000-4000-8000-000000000001', '하디스 키사이드 샤르도네', 'Hardys Quayside Chardonnay', 'c0000000-0000-4000-8000-000000000001', 13.5, 'published', now()),
      ('e0000000-0000-4000-8000-000000000002', '숨은 병', null, 'c0000000-0000-4000-8000-000000000001', 12, 'staging', null);
    insert into public.alcohol_tasting_profiles (alcohol_item_id, sweetness, acidity, body)
      values ('e0000000-0000-4000-8000-000000000001', 2, 4, 3);
  `);
  const context = async (id: string) => {
    const { rows } = await db.query<
      { context: Record<string, unknown> | null }
    >(
      "select public.soolgyul_get_sensory_question_context($1) as context",
      [id],
    );
    return rows[0].context;
  };
  const published = await context("e0000000-0000-4000-8000-000000000001");
  if (!published) throw new Error("published product has no context");
  const expected = {
    id: "e0000000-0000-4000-8000-000000000001",
    name: "하디스 키사이드 샤르도네",
    category: "wine",
    target: "product",
    abv_percent: 13.5,
    sensory_scale: 5,
    levels: { sweetness: 2, acidity: 4, body: 3 },
    aroma_keys: [],
    texture_keys: [],
  };
  const canonical = (value: unknown): string =>
    JSON.stringify(
      value,
      (_key, inner) =>
        inner && typeof inner === "object" && !Array.isArray(inner)
          ? Object.fromEntries(Object.entries(inner).sort())
          : inner,
    );
  for (const [key, value] of Object.entries(expected)) {
    if (canonical(published[key]) !== canonical(value)) {
      throw new Error(
        `${key}: expected ${JSON.stringify(value)}, received ${
          JSON.stringify(published[key])
        }`,
      );
    }
  }
  if (await context("e0000000-0000-4000-8000-000000000002") !== null) {
    throw new Error("staging product must have no context");
  }
  await db.close();
});
