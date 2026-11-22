/**
 * The night's count of the catalog: reads the facts of every published
 * bottle, counts them as the card engine reads a bottle
 * (supabase/functions/_shared/taste_card/facts/kind_spreads_build.ts) and
 * replaces the row the functions read (catalog_kind_spreads).
 * .github/workflows/kind-spreads.yml runs it every night.
 *
 * It needs the project's URL and publishable key, and the job's own secret,
 * which opens only the two database functions it calls:
 *
 *   SUPABASE_URL=… SUPABASE_PUBLISHABLE_KEY=… KIND_SPREADS_JOB_SECRET=… \
 *     deno run --allow-env --allow-net --allow-read tools/catalog/refresh_kind_spreads.ts
 *
 * With --dry-run it counts and prints, and stores nothing.
 */
import {
  buildKindSpreads,
  type CountedBottle,
} from "../../supabase/functions/_shared/taste_card/facts/kind_spreads_build.ts";

const PAGE = 2000;

function need(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    console.error(`${name} is not set`);
    Deno.exit(1);
  }
  return value;
}
const url = need("SUPABASE_URL");
const key = need("SUPABASE_PUBLISHABLE_KEY");
const secret = need("KIND_SPREADS_JOB_SECRET");
const dryRun = Deno.args.includes("--dry-run");

async function call<T>(name: string, body: Record<string, unknown>) {
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ job_secret: secret, ...body }),
    signal: AbortSignal.timeout(60_000),
  });
  if (!response.ok) {
    // The answer may repeat the request; only its code is printed.
    const answer = await response.json().catch(() => ({}));
    throw new Error(`${name}: ${response.status} ${answer?.message ?? ""}`);
  }
  return await response.json() as T;
}

const bottles: (CountedBottle & { id: string })[] = [];
for (;;) {
  const page = await call<(CountedBottle & { id: string })[]>(
    "soolgyul_kind_spreads_bottles",
    { after_id: bottles.at(-1)?.id ?? null, page_size: PAGE },
  );
  bottles.push(...page);
  if (page.length < PAGE) break;
}

const spreads = buildKindSpreads(
  bottles,
  new Date().toISOString().slice(0, 10),
);
console.log(
  `${Object.keys(spreads.kinds).length} kinds from ${spreads.bottles} bottles`,
);
if (dryRun) {
  console.log("dry run: nothing stored");
} else {
  await call("soolgyul_store_kind_spreads", { new_spreads: spreads });
  console.log("stored");
}
