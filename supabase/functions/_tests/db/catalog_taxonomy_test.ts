import { assertEquals } from "jsr:@std/assert@1";
import { createSupabaseLikeDatabase } from "../helpers/pglite_supabase.ts";

// The dictionary file is the only place anyone edits terms. The DB table
// catalog_taxonomy is a projection of it for search and validation, written by
// migrations that tools/catalog/enrichment/materialize_catalog_terms.py
// renders. This test fails when the file changes and no migration follows:
// the committed fixture is regenerated from the file by a pytest, and the
// migrated table must match it row for row.

type Row = {
  term_type: string;
  term_key: string;
  label_ko: string;
  label_en: string | null;
  synonyms: string[];
  parent_term_key: string | null;
  applicable_sections: string[];
  is_active: boolean;
  metadata: Record<string, unknown>;
};

const FIXTURE = "supabase/functions/_tests/fixtures/catalog_taxonomy_rows.json";

/** JSON with object keys sorted at every depth; jsonb reorders nested keys. */
function sortedJson(value: unknown): string {
  return JSON.stringify(
    value,
    (_key, v) =>
      v !== null && typeof v === "object" && !Array.isArray(v)
        ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, v[k]]))
        : v,
  );
}

function canonical(row: Row): string {
  return sortedJson({
    term_type: row.term_type,
    term_key: row.term_key,
    label_ko: row.label_ko,
    label_en: row.label_en,
    synonyms: [...row.synonyms].sort(),
    parent_term_key: row.parent_term_key,
    applicable_sections: [...row.applicable_sections].sort(),
    is_active: row.is_active,
    metadata: row.metadata,
  });
}

Deno.test("catalog_taxonomy after every migration equals the dictionary's projection", async (t) => {
  const db = await createSupabaseLikeDatabase();
  try {
    const expected = JSON.parse(Deno.readTextFileSync(FIXTURE)) as Row[];
    const { rows } = await db.query<Row>(
      `select term_type, term_key, label_ko, label_en, synonyms,
              parent_term_key, applicable_sections, is_active, metadata
         from public.catalog_taxonomy
        order by term_type, term_key`,
    );

    await t.step("same identities", () => {
      const id = (r: Row) => `${r.term_type}:${r.term_key}`;
      const dbIds = rows.map(id);
      const fileIds = expected.map(id).sort();
      const missing = fileIds.filter((x) => !dbIds.includes(x));
      const extra = dbIds.filter((x) => !fileIds.includes(x));
      assertEquals({ missing, extra }, { missing: [], extra: [] });
    });

    await t.step("same labels, parents, sections and metadata", () => {
      const byId = new Map(
        expected.map((r) => [`${r.term_type}:${r.term_key}`, r]),
      );
      const differing = rows
        .filter((r) =>
          canonical(r) !== canonical(byId.get(`${r.term_type}:${r.term_key}`)!)
        )
        .map((r) => `${r.term_type}:${r.term_key}`);
      assertEquals(differing, []);
    });

    await t.step("no prose column survives in the table", async () => {
      const { rows: columns } = await db.query<{ column_name: string }>(
        `select column_name from information_schema.columns
          where table_schema = 'public' and table_name = 'catalog_taxonomy'`,
      );
      const names = columns.map((c) => c.column_name);
      assertEquals(names.includes("card_label_ko"), false);
      const { rows: prose } = await db.query<{ n: number }>(
        `select count(*)::int as n from public.catalog_taxonomy
          where metadata ? 'sensory_description' or metadata ? 'sensory_trait_keys'`,
      );
      assertEquals(prose[0].n, 0);
    });

    await t.step(
      "nothing in the schema still names catalog_terms",
      async () => {
        const { rows: functions } = await db.query<{ proname: string }>(
          `select p.proname from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.prosrc like '%catalog\\_terms%'`,
        );
        const { rows: tables } = await db.query<{ relname: string }>(
          `select c.relname from pg_class c
           join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public' and c.relname like '%catalog\\_terms%'`,
        );
        assertEquals(functions.map((f) => f.proname), []);
        assertEquals(tables.map((r) => r.relname), []);
      },
    );
  } finally {
    await db.close();
  }
});
