// Temporary: refactor guard. Deleted with refactor_guard/ when the refactor ends.
//
// Writes what the card engine, the taste letters and the taste fit judge say
// for a fixed corpus of answers and products, one JSON line per case, so a
// refactor can prove it changed no word and no stored fact.
//
//   deno run --allow-read --allow-write --allow-env refactor_guard/card_corpus.ts <out dir>
import { writeCard } from "../supabase/functions/_shared/taste_card/card_text.ts";
import { withCardTerms } from "../supabase/functions/_shared/taste_card/card_terms.ts";
import { createTasteCardResultV1 } from "../supabase/functions/_shared/taste_card/orchestrator.ts";
import {
  computeTasteLetters,
  type LetterRecord,
  letterVotes,
} from "../supabase/functions/_shared/taste_card/taste_letters.ts";
import { sensoryCatalog } from "../supabase/functions/_shared/taste_card/dictionary.ts";
import { serviceVocabulary } from "../supabase/functions/_shared/taste_card/dictionary.ts";
import {
  SENSORY_QUESTIONNAIRE_VERSION,
  SENSORY_QUESTIONS,
} from "../supabase/functions/_shared/taste_card/sensory_questionnaire_v1.ts";
import type {
  SensoryProduct,
  SensoryProductDescriptor,
} from "../supabase/functions/_shared/taste_card/sensory_record.ts";
import type { CardFacts } from "../supabase/functions/_shared/taste_card/card_facts.ts";
import { buildLedger } from "../supabase/functions/_shared/taste_fit/ledger.ts";
import { judgeProduct } from "../supabase/functions/_shared/taste_fit/judge.ts";
import { composeCopy } from "../supabase/functions/_shared/taste_fit/copy.ts";
import {
  type CatalogSample,
  catalogSamples,
  fixtureRecord,
  fixtures,
  recordFrom,
} from "../supabase/functions/_tests/helpers/card_fixture_record.ts";
import {
  ActualQuestionnaireRepository,
  type CatalogRows,
  testDependencies,
} from "../supabase/functions/_tests/fixtures/actual_questionnaire_v3.ts";

const out = Deno.args[0] ?? "refactor_guard/out/cards";
await Deno.mkdir(out, { recursive: true });

/** Writes one file of cases; a case that throws is written as its error. */
async function write(
  name: string,
  cases: Iterable<[string, () => unknown]>,
): Promise<number> {
  const lines: string[] = [];
  for (const [label, run] of cases) {
    let value: unknown;
    try {
      value = await run();
    } catch (error) {
      value = { error: String((error as Error).message ?? error) };
    }
    lines.push(JSON.stringify({ case: label, value }));
  }
  await Deno.writeTextFile(`${out}/${name}.jsonl`, lines.join("\n") + "\n");
  return lines.length;
}

/** A small seeded generator, so the corpus is the same on every run. */
function seeded(seed: number): () => number {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// --- products -------------------------------------------------------------

const alias = new Map<string, string>();
for (
  const g of (serviceVocabulary as {
    groups: { key: string; domain: string; source_keys: string[] }[];
  }).groups
) {
  if (g.domain !== "descriptor") continue;
  for (const k of [g.key, ...g.source_keys]) alias.set(k, g.key);
}

function product(c: CatalogSample): SensoryProduct {
  const descriptors: SensoryProductDescriptor[] = [];
  for (const raw of c.aromas) {
    const key = alias.get(raw);
    if (!key || descriptors.some((d) => d.key === key)) continue;
    descriptors.push({
      key,
      label: key,
      section: "aroma",
      family: "test",
      traits: [],
      description: null,
      evidenceRefs: ["test"],
    });
  }
  return {
    name: c.name,
    category: c.category as SensoryProduct["category"],
    styleKey: c.style_key,
    region: null,
    abv: c.abv,
    ingredients: [...c.ingredients],
    processes: [...c.processes],
    grapeVarietyKeys: [],
    levels: c.levels,
    levelRefs: {},
    levelSources: c.level_sources,
    descriptors,
  };
}

const pool = (await catalogSamples()).sort((a, b) => a.id.localeCompare(b.id));
const categories = [...new Set(pool.map((c) => c.category))].sort();
/** Two bottles per kind: the first and the last by id. */
const sample = categories.flatMap((category) => {
  const ofKind = pool.filter((c) => c.category === category);
  return [ofKind[0], ofKind[ofKind.length - 1]];
});

// --- answers ----------------------------------------------------------------

const LIKED = ["gentle", "pronounced", "harmony", "unspecified"];
const DISLIKED = ["too_strong", "too_weak", "disharmony", "unspecified"];
const TASTE = ["sweetness", "acidity", "bitterness"];
const MOUTH = ["light", "heavy", "smooth", "drying", "bubbles", "warmth"];
const FINISH = [
  "pleasantLength",
  "clean",
  "tooShort",
  "heavy",
  "aromaEcho",
  "offFlavor",
];
const REVISIT = ["wantAgain", "wouldAcceptAgain", "doNotWantAgain", "unsure"];
const selectable = (sensoryCatalog as {
  descriptors: { key: string; onboarding_selectable?: boolean }[];
}).descriptors.filter((d) => d.onboarding_selectable).map((d) => d.key)
  .sort();

type Unit = { section: string; keys: string[] };

function aromaUnit(a: string, side: "liked" | "disliked", r: string): Unit {
  return {
    section: "aroma",
    keys: [
      `notice:aroma:${a}`,
      `reaction:aroma:${a}:${side}`,
      `reason:aroma:${a}:${side}:${r}`,
    ],
  };
}
function tasteUnit(t: string, side: "liked" | "disliked", r: string): Unit {
  return {
    section: "taste",
    keys: [`reaction:taste:${t}:${side}`, `reason:taste:${t}:${side}:${r}`],
  };
}
function mouthUnit(m: string, side: string): Unit {
  return {
    section: "mouthfeel",
    keys: [`notice:mouthfeel:${m}`, `reaction:mouthfeel:${m}:${side}`],
  };
}
const finishUnit = (f: string): Unit => ({
  section: "finish",
  keys: [`finish:${f}`],
});

/** Answers of the given units, every section left unanswered said unsure. */
function answersOf(units: Unit[], revisit: string): string[] {
  const keys = units.flatMap((u) => u.keys);
  for (const section of ["aroma", "taste", "mouthfeel", "finish"]) {
    if (units.some((u) => u.section === section)) continue;
    keys.push(
      section === "taste"
        ? "reaction:taste:sweetness:fine"
        : `${section}:unsure`,
    );
  }
  keys.push(`revisit:${revisit}`);
  return keys;
}

/** Every single answer a reader can give, as the coverage test sweeps them. */
function singleAnswers(): [string, string[]][] {
  const out: [string, string[]][] = [];
  for (const a of selectable) {
    for (const r of LIKED) {
      out.push([
        `aroma ${a} liked ${r}`,
        answersOf([aromaUnit(a, "liked", r)], "wantAgain"),
      ]);
    }
    for (const r of DISLIKED) {
      out.push([
        `aroma ${a} disliked ${r}`,
        answersOf([aromaUnit(a, "disliked", r)], "doNotWantAgain"),
      ]);
    }
  }
  for (const t of TASTE) {
    for (const r of LIKED) {
      out.push([
        `taste ${t} liked ${r}`,
        answersOf([tasteUnit(t, "liked", r)], "unsure"),
      ]);
    }
    for (const r of DISLIKED) {
      out.push([
        `taste ${t} disliked ${r}`,
        answersOf([tasteUnit(t, "disliked", r)], "unsure"),
      ]);
    }
  }
  for (const m of MOUTH) {
    for (const side of ["liked", "disliked"]) {
      out.push([
        `mouthfeel ${m} ${side}`,
        answersOf([mouthUnit(m, side)], "unsure"),
      ]);
    }
  }
  for (const f of FINISH) {
    out.push([`finish ${f}`, answersOf([finishUnit(f)], "unsure")]);
  }
  return out;
}

/** Mixed answers: a few reactions per section, both sides, any revisit. */
function randomAnswers(count: number, seed: number): [string, string[]][] {
  const random = seeded(seed);
  const pick = <T>(items: readonly T[]): T =>
    items[Math.floor(random() * items.length)];
  const some = <T>(items: readonly T[], max: number): T[] => {
    const left = [...items];
    const taken: T[] = [];
    const n = Math.floor(random() * (max + 1));
    for (let i = 0; i < n && left.length; i++) {
      taken.push(left.splice(Math.floor(random() * left.length), 1)[0]);
    }
    return taken;
  };
  const side = (): "liked" | "disliked" =>
    random() < 0.55 ? "liked" : "disliked";
  const reason = (s: "liked" | "disliked") =>
    pick(s === "liked" ? LIKED : DISLIKED);
  const out: [string, string[]][] = [];
  for (let i = 0; i < count; i++) {
    const units: Unit[] = [];
    for (const a of some(selectable, 5)) {
      const s = side();
      units.push(aromaUnit(a, s, reason(s)));
    }
    for (const t of some(TASTE, 3)) {
      const s = side();
      units.push(tasteUnit(t, s, reason(s)));
    }
    for (const m of some(MOUTH, 3)) units.push(mouthUnit(m, side()));
    for (const f of some(FINISH, 2)) units.push(finishUnit(f));
    out.push([`random ${i}`, answersOf(units, pick(REVISIT))]);
  }
  return out;
}

const singles = singleAnswers();
const randoms = randomAnswers(1500, 20261109);

// --- cards ----------------------------------------------------------------

const counts: Record<string, number> = {};
const cards: CardFacts[] = [];
const cardCase = (label: string, run: () => ReturnType<typeof writeCard>) =>
  [label, () => {
    const card = run();
    cards.push(card.facts);
    return card;
  }] as [string, () => unknown];

counts.single = await write(
  "cards.single",
  sample.flatMap((c) =>
    singles.map(([label, keys]) =>
      cardCase(
        `${c.id} | ${label}`,
        () => writeCard(recordFrom(`${label}|${c.id}`, keys, product(c))),
      )
    )
  ),
);
counts.random = await write(
  "cards.random",
  randoms.map(([label, keys], i) => {
    const c = pool[i % pool.length];
    return cardCase(
      `${c.id} | ${label}`,
      () => writeCard(recordFrom(`${label}|${c.id}`, keys, product(c))),
    );
  }),
);
const named = await fixtures();
counts.fixtures = await write(
  "cards.fixtures",
  named.map(([name, facts]) =>
    cardCase(name, () => writeCard(fixtureRecord(name, facts)))
  ),
);

// --- the whole pipeline: request in, stored envelope and served view out --

const ITEM = "30000000-0000-4000-8000-000000000001";
const margaux: CatalogRows = {
  items: [{
    id: ITEM,
    name_ko: "샤또 마고",
    name_en: "Château Margaux",
    abv_percent: 13.5,
    style_key: "red_wine",
    region_key: null,
    ingredient_keys: [],
    production_process_keys: [],
    grape_variety_keys: ["cabernet_sauvignon", "merlot"],
    category: { category_key: "wine" },
  }],
  profiles: [{
    alcohol_item_id: ITEM,
    sweetness: 1,
    acidity: 4,
    bitterness: 2,
    astringency: 4,
    body: 4,
    carbonation: 1,
    aroma_intensity: 4,
    finish_length: 4,
    finish_cleanliness: 3,
    aroma_tags: ["cherry", "oak", "vanilla"],
    palate_tags: [],
    finish_tags: [],
    aroma_note: null,
    palate_note: null,
    level_sources: { sweetness: 2, acidity: 2, astringency: 2, body: 2 },
  }],
  media: [{ alcohol_item_id: ITEM, media_path: "wine/margaux.jpg" }],
};
const QUESTION_OF: Record<string, keyof typeof SENSORY_QUESTIONS> = {
  aroma: "sensory_aroma",
  taste: "sensory_taste",
  mouthfeel: "sensory_mouthfeel",
  finish: "sensory_finish",
  revisit: "sensory_revisit",
};
function questionOf(key: string): keyof typeof SENSORY_QUESTIONS {
  const [kind, section] = key.split(":");
  return QUESTION_OF[
    ["notice", "reaction", "reason"].includes(kind) ? section : kind
  ];
}
counts.pipeline = await write(
  "pipeline",
  [...singles.slice(0, 60), ...randoms.slice(0, 140)].flatMap((
    [label, keys],
    i,
  ) =>
    [false, true].map((anonymous) =>
      [`${label} | ${anonymous ? "anonymous" : "member"}`, async () => {
        const deps = testDependencies(
          new ActualQuestionnaireRepository(margaux),
        );
        const outcome = await createTasteCardResultV1(
          deps,
          {
            idempotency_key: `10000000-0000-4000-8000-${
              String(i).padStart(12, "0")
            }`,
            anonymous_session_id: anonymous ? "anonymous-session-one" : null,
            questionnaire_version: SENSORY_QUESTIONNAIRE_VERSION,
            alcohol_identification: {
              mode: "catalog_match",
              alcohol_item_id: ITEM,
              alcohol_name_snapshot: "샤또 마고",
              category: "wine",
            },
            answers: Object.keys(SENSORY_QUESTIONS).map((question) => ({
              question_key: question,
              selected_option_keys: keys.filter((k) =>
                questionOf(k) === question
              ),
              free_text: null,
            })),
            q7_free_text: null,
            photo_asset_id: null,
          } as Parameters<typeof createTasteCardResultV1>[1],
          anonymous ? null : { user_id: "user-one" },
        );
        return outcome.state === "final"
          ? { ...outcome, served: withCardTerms(outcome.result.view) }
          : outcome;
      }] as [string, () => unknown]
    )
  ),
);

// --- taste letters: one reader's records replayed, prefix by prefix -------

const letterRecords: LetterRecord[] = cards.slice(0, 400).map((facts, i) => ({
  record_id: `record-${String(i).padStart(4, "0")}`,
  product_name: facts.record.product_name,
  recorded_at: new Date(Date.UTC(2026, 0, 1) + i * 3_600_000).toISOString(),
  votes: letterVotes(facts),
}));
counts.letters = await write(
  "letters",
  [1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 400].flatMap((n) =>
    [0, 400 - n].map((start) =>
      [
        `${start}+${n}`,
        () => computeTasteLetters(letterRecords.slice(start, start + n)),
      ] as [string, () => unknown]
    )
  ),
);

// --- taste fit: each sampled bottle judged against several readers --------

type FitRow = Parameters<typeof judgeProduct>[0];
const fitProducts = (JSON.parse(
  await Deno.readTextFile(
    new URL(
      "../supabase/functions/_tests/fixtures/taste_fit_products.json",
      import.meta.url,
    ),
  ),
) as Record<string, unknown>[]).map((p, i) =>
  ({
    producer: null,
    grape_variety_keys: [],
    production_process_keys: [],
    region_key: null,
    ...p,
    id: `product-${i}`,
  }) as unknown as FitRow
);
const readers: [string, CardFacts[]][] = [
  ["fixtures", named.map(([, facts]) => facts)],
  ["random-a", cards.slice(0, 40)],
  ["random-b", cards.slice(40, 200)],
  ["random-c", cards.slice(200, 1200)],
];
counts.tasteFit = await write(
  "taste_fit",
  readers.flatMap(([reader, readerCards]) => {
    const ledger = buildLedger(readerCards);
    return [
      [`${reader} | ledger`, () => ledger] as [string, () => unknown],
      ...fitProducts.map((p) =>
        [`${reader} | ${(p as { id: string }).id}`, () => {
          const verdict = judgeProduct(p, ledger);
          return {
            verdict,
            named: composeCopy(
              verdict.badge,
              verdict.hits,
              verdict.aromas,
              "민지",
            ),
            anonymous: composeCopy(
              verdict.badge,
              verdict.hits,
              verdict.aromas,
              null,
            ),
          };
        }] as [string, () => unknown]
      ),
    ];
  }),
);

console.log(JSON.stringify(counts));
