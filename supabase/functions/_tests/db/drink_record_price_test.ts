import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";
import { asUser, failsWith } from "../helpers/db_session.ts";

// 구입 가격 is written by its owner after the card, through one RPC that
// touches nothing else, and stays with a record kept without its owner.

const OWNER = "a0000000-0000-4000-8000-000000000051";
const STRANGER = "a0000000-0000-4000-8000-000000000052";
const CATEGORY = "c0000000-0000-4000-8000-000000000001";
const ITEM = "b0000000-0000-4000-8000-000000000001";
const RECORD = "d0000000-0000-4000-8000-000000000051";
const OTHER_RECORD = "d0000000-0000-4000-8000-000000000052";
const MISSING_RECORD = "d0000000-0000-4000-8000-000000000059";
const CARD = "e0000000-0000-4000-8000-000000000051";
const OTHER_CARD = "e0000000-0000-4000-8000-000000000052";

async function seed(db: PGlite) {
  await db.exec(`
    insert into auth.users (id, email, raw_app_meta_data, last_sign_in_at) values
      ('${OWNER}', 'owner@example.test', '{"provider":"kakao"}', now()),
      ('${STRANGER}', 'stranger@example.test', '{"provider":"kakao"}', now());
    update public.users set birth_date = '1993-04-12' where id = '${OWNER}';
    insert into public.alcohol_categories (id, category_key, name_ko, sort_order)
      values ('${CATEGORY}', 'wine', '와인', 1);
    insert into public.alcohol_items (id, name_ko, alcohol_category_id, publish_status, published_at)
      values ('${ITEM}', '테스트 술', '${CATEGORY}', 'published', now());
    insert into public.drink_records (id, user_id, alcohol_item_id, questionnaire_version, one_line_note)
      values
        ('${RECORD}', '${OWNER}', '${ITEM}', 'sensory-questionnaire-v1', '지울 메모'),
        ('${OTHER_RECORD}', '${OWNER}', '${ITEM}', 'sensory-questionnaire-v1', null);
    insert into public.taste_cards (id, drink_record_id, snapshot_id, snapshot_ref, lifecycle,
        canonical_schema_version, semantic_snapshot, rendered_snapshot)
      values
        ('${CARD}', '${RECORD}', gen_random_uuid(), repeat('a', 64), 'final',
          'test', '{}'::jsonb, '{}'::jsonb),
        ('${OTHER_CARD}', '${OTHER_RECORD}', gen_random_uuid(), repeat('b', 64), 'final',
          'test', '{}'::jsonb, '{}'::jsonb);
  `);
}

const setPrice = (
  db: PGlite,
  record: string,
  amount: number | null,
  unit: string | null,
) =>
  db.query("select public.soolgyul_update_my_drink_record_price($1, $2, $3)", [
    record,
    amount,
    unit,
  ]);

async function price(db: PGlite, record = RECORD) {
  const { rows } = await db.query<
    { purchase_price_won: number | null; purchase_price_unit: string | null }
  >(
    "select purchase_price_won, purchase_price_unit from public.drink_records where id = $1",
    [record],
  );
  return rows[0];
}

async function retained(db: PGlite) {
  const { rows } = await db.query<
    {
      purchase_price_won: number | null;
      purchase_price_unit: string | null;
      record_data: unknown;
    }
  >(
    "select purchase_price_won, purchase_price_unit, record_data from public.retained_drink_records order by purchase_price_won desc nulls last",
  );
  return rows;
}

Deno.test("record purchase price", async (t) => {
  const db = await createSupabaseLikeDatabase();
  await seed(db);

  await t.step("the owner sets, changes and clears the price", async () => {
    await asUser(db, OWNER, async () => {
      await setPrice(db, RECORD, 38000, "bottle");
      let row = await price(db);
      if (
        row.purchase_price_won !== 38000 || row.purchase_price_unit !== "bottle"
      ) {
        throw new Error(`price not stored: ${JSON.stringify(row)}`);
      }
      await setPrice(db, RECORD, 12000, "glass");
      row = await price(db);
      if (
        row.purchase_price_won !== 12000 || row.purchase_price_unit !== "glass"
      ) {
        throw new Error(`price not changed: ${JSON.stringify(row)}`);
      }
      // No amount clears the unit too, whatever unit comes with it.
      await setPrice(db, RECORD, null, "glass");
      row = await price(db);
      if (row.purchase_price_won !== null || row.purchase_price_unit !== null) {
        throw new Error(`price not cleared: ${JSON.stringify(row)}`);
      }
      await failsWith(
        () => setPrice(db, MISSING_RECORD, 1000, "bottle"),
        "record_not_found",
      );
    });
  });

  await t.step("the 취향 tab's records carry the price", async () => {
    await asUser(db, OWNER, async () => {
      await setPrice(db, RECORD, 38000, "bottle");
      const { rows } = await db.query<{ history: Record<string, unknown>[] }>(
        "select public.soolgyul_my_drink_history(now() - interval '1 day', now() + interval '1 day') as history",
      );
      const byCard = new Map(
        rows[0].history.map((entry) => [entry.result_id, entry]),
      );
      const priced = byCard.get(CARD);
      const plain = byCard.get(OTHER_CARD);
      if (priced?.price_won !== 38000 || priced?.price_unit !== "bottle") {
        throw new Error(`history lost the price: ${JSON.stringify(priced)}`);
      }
      if (plain?.price_won !== null || plain?.price_unit !== null) {
        throw new Error(`history invented a price: ${JSON.stringify(plain)}`);
      }
    });
  });

  await t.step("a stranger cannot price another member's record", async () => {
    await asUser(db, STRANGER, async () => {
      await failsWith(
        () => setPrice(db, RECORD, 1000, "glass"),
        "record_not_found",
      );
    });
    const row = await price(db);
    if (row.purchase_price_won !== 38000) {
      throw new Error("a stranger changed the price");
    }
    await db.query("select set_config('request.jwt.claims', '', false)");
    await failsWith(
      () => setPrice(db, RECORD, 1000, "glass"),
      "authentication_required",
    );
  });

  await t.step("an amount or unit out of bounds is refused", async () => {
    await asUser(db, OWNER, async () => {
      for (const amount of [0, -500, 10000001]) {
        await failsWith(
          () => setPrice(db, RECORD, amount, "bottle"),
          "price_amount_invalid",
        );
      }
      for (const unit of [null, "", "can"]) {
        await failsWith(
          () => setPrice(db, RECORD, 1000, unit),
          "price_unit_invalid",
        );
      }
      await setPrice(db, OTHER_RECORD, 10000000, "glass");
      await setPrice(db, OTHER_RECORD, 1, "glass");
    });
    const row = await price(db);
    if (
      row.purchase_price_won !== 38000 || row.purchase_price_unit !== "bottle"
    ) {
      throw new Error("a refused price changed the record");
    }
    // The table refuses half a price written around the RPC.
    await failsWith(
      () =>
        db.query(
          "update public.drink_records set purchase_price_unit = null where id = $1",
          [RECORD],
        ),
      "drink_records_purchase_price_pair",
    );
  });

  await t.step(
    "a record kept without its owner keeps the price, not the memo",
    async () => {
      await db.query(
        "select public.soolgyul_delete_owned_drink_record($1, $2)",
        [CARD, OWNER],
      );
      let kept = await retained(db);
      if (kept.length !== 1) throw new Error(`kept ${kept.length} rows`);
      if (
        kept[0].purchase_price_won !== 38000 ||
        kept[0].purchase_price_unit !== "bottle"
      ) {
        throw new Error(
          `deleted card lost the price: ${JSON.stringify(kept[0])}`,
        );
      }
      if (JSON.stringify(kept[0].record_data).includes("지울 메모")) {
        throw new Error("kept row holds the memo");
      }

      // The account's remaining records go the same way at the purge.
      await db.query("select public.soolgyul_retain_drink_records($1)", [
        OWNER,
      ]);
      kept = await retained(db);
      if (kept.length !== 2) throw new Error(`kept ${kept.length} rows`);
      if (
        kept[1].purchase_price_won !== 1 ||
        kept[1].purchase_price_unit !== "glass"
      ) {
        throw new Error(
          `purged record lost the price: ${JSON.stringify(kept[1])}`,
        );
      }
    },
  );

  await db.close();
});
