// The card pipeline end to end: a request goes in, the three-part card comes
// out, is stored once, replays identically, converts, and fails closed.
import { withCardTerms } from "../_shared/taste_card/card_terms.ts";
import { ConversionTokenError } from "../_shared/taste_card/conversion_token.ts";
import {
  convertAnonymousTasteCardV1,
  createTasteCardResultV1,
  getOwnedTasteCardResultV1,
  TasteCardOrchestrationError,
} from "../_shared/taste_card/orchestrator.ts";
import {
  parseCreateTasteCardResultRequestV1,
  parseTasteCardResultEnvelope,
  TasteCardContractError,
} from "../_shared/taste_card/serialization.ts";
import {
  SENSORY_QUESTIONNAIRE_VERSION,
  SENSORY_QUESTIONS,
} from "../_shared/taste_card/sensory_questionnaire_v1.ts";
import type { CreateTasteCardResultRequestV1 } from "../_shared/taste_card/types.ts";
import flutterWire from "./fixtures/sensory_flutter_wire_v1.json" with {
  type: "json",
};
import envelopeFixture from "./fixtures/taste_card_envelope_v3.json" with {
  type: "json",
};
import {
  ActualQuestionnaireRepository,
  type CatalogRows,
  testDependencies,
} from "./fixtures/actual_questionnaire_v3.ts";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function same(actual: unknown, expected: unknown, message = "equality") {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${message}: ${a} != ${b}`);
}
/** The key structure of a value: objects by sorted keys, arrays by their elements, leaves by type. */
function keyShape(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(keyShape);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value as Record<string, unknown>).sort().map((
        key,
      ) => [key, keyShape((value as Record<string, unknown>)[key])]),
    );
  }
  return value === null ? "null" : typeof value;
}
async function rejects(operation: () => Promise<unknown>, code: string) {
  try {
    await operation();
  } catch (error) {
    const actual = error instanceof TasteCardOrchestrationError ||
        error instanceof ConversionTokenError ||
        error instanceof TasteCardContractError
      ? error.code
      : String(error);
    assert(actual === code, `expected ${code}, received ${actual}`);
    return;
  }
  throw new Error(`expected rejection ${code}`);
}

const ITEM = "30000000-0000-4000-8000-000000000001";
const ANON = "10000000-0000-4000-8000-000000000001";
const AUTH = "10000000-0000-4000-8000-000000000002";
const CONVERT = "10000000-0000-4000-8000-000000000003";

/** 샤또 마고 as the catalog serves it: a dry, acidic, tannic red with cherry and oak. */
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

const cherryAnswers = {
  sensory_aroma: [
    "notice:aroma:cherry",
    "reaction:aroma:cherry:liked",
    "reason:aroma:cherry:liked:pronounced",
  ],
  sensory_taste: [
    "reaction:taste:acidity:liked",
    "reason:taste:acidity:liked:pronounced",
  ],
  sensory_mouthfeel: [
    "notice:mouthfeel:drying",
    "reaction:mouthfeel:drying:disliked",
  ],
  sensory_finish: ["finish:heavy"],
};

function request(
  answers: Partial<Record<keyof typeof SENSORY_QUESTIONS, string[]>> = {},
  overrides: Partial<CreateTasteCardResultRequestV1> = {},
): CreateTasteCardResultRequestV1 {
  return {
    idempotency_key: ANON,
    anonymous_session_id: "anonymous-session-one",
    questionnaire_version: SENSORY_QUESTIONNAIRE_VERSION,
    alcohol_identification: {
      mode: "catalog_match",
      alcohol_item_id: ITEM,
      alcohol_name_snapshot: "샤또 마고",
      category: "wine",
    },
    answers: Object.keys(SENSORY_QUESTIONS).map((key) => ({
      question_key: key,
      selected_option_keys: answers[key as keyof typeof SENSORY_QUESTIONS] ??
        (key === "sensory_revisit" ? ["revisit:wantAgain"] : []),
      free_text: null,
    })),
    q7_free_text: null,
    photo_asset_id: null,
    ...overrides,
  };
}

Deno.test("generation: a catalog match becomes a three-part card written from the answers and the product", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const deps = testDependencies(repository);
  const outcome = await createTasteCardResultV1(
    deps,
    request(cherryAnswers),
    null,
  );
  assert(outcome.state === "final", "final card");
  const { view } = outcome.result;
  // What the app shows and nothing else.
  same(Object.keys(view), [
    "product",
    "bite",
    "positive",
    "burden",
    "balanced",
    "metadata",
  ]);
  same(view.balanced, []);
  same(view.product, {
    drink_name_snapshot: "샤또 마고",
    user_name: null,
    image_reference: {
      source: "catalog",
      reference:
        "https://offline.invalid/storage/v1/object/public/alcohol-product-images/wine/margaux.jpg",
    },
    category_label: "와인",
  });
  assert(view.bite.nickname === "선명한 프루티 러버", view.bite.nickname);
  assert(
    view.bite.tags.length >= 1 &&
      view.bite.tags[0].kind === "liked" &&
      view.bite.tags.every((t) => t.label.length > 0),
    JSON.stringify(view.bite.tags),
  );
  assert(
    !view.bite.summary.includes("\n") && view.bite.summary.endsWith("요."),
    view.bite.summary,
  );
  assert(
    (view.bite.guide?.picks.length ?? 0) >= 1 &&
      (view.bite.guide?.levels.length ?? 0) >= 1,
    "guide has its picks and levels",
  );
  assert(view.positive.length >= 1 && view.burden.length >= 1);
  for (const paragraph of [...view.positive, ...view.burden]) {
    assert(paragraph.answer && paragraph.text.endsWith("요."), paragraph.text);
  }
  assert(!JSON.stringify(view).includes("undefined"));
  assert(outcome.result.conversion !== null, "anonymous token issued");
  // The private snapshot reproduces the card: the record and the facts.
  const snapshot = repository.finalized!.semantic_snapshot;
  assert(snapshot.record.product.levels.acidity === 4);
  same(snapshot.record.product.grapeVarietyKeys, [
    "cabernet_sauvignon",
    "merlot",
  ]);
  assert(
    snapshot.record.product.descriptors.some((d) => d.key === "cherry"),
    "catalog aromas read",
  );
  assert(
    snapshot.facts.product_facts.some((p) =>
      p.fact.type === "level" && p.fact.dimension === "acidity" &&
      !p.fact.estimated
    ),
    "a read level is not marked as the kind's",
  );
  // The stored view carries no explanations; the served one has the dictionary's.
  same(withCardTerms(repository.finalized!.rendered_view), view);
  assert(repository.catalogReads >= 1, "the catalog was read");
});

Deno.test("generation: the same request replays the stored card without reading or writing again", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const deps = testDependencies(repository);
  const first = await createTasteCardResultV1(
    deps,
    request(cherryAnswers),
    null,
  );
  const reads = repository.catalogReads;
  const second = await createTasteCardResultV1(
    deps,
    request(cherryAnswers),
    null,
  );
  assert(first.state === "final" && second.state === "final");
  same(second.result.view, first.result.view);
  assert(second.result.result_id === first.result.result_id);
  assert(repository.catalogReads === reads && repository.finalizations === 1);
  await rejects(
    () =>
      createTasteCardResultV1(
        deps,
        request(cherryAnswers, { q7_free_text: "다른 메모" }),
        null,
      ),
    "idempotency_conflict",
  );
});

Deno.test("generation: an item the catalog no longer serves writes no card", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  await rejects(
    () =>
      createTasteCardResultV1(
        testDependencies(repository),
        request(cherryAnswers, {
          alcohol_identification: {
            mode: "catalog_match",
            alcohol_item_id: "30000000-0000-4000-8000-000000000009",
            alcohol_name_snapshot: "사라진 술",
            category: null,
          },
        }),
        null,
      ),
    "catalog_item_not_found",
  );
  assert(repository.finalizations === 0 && repository.results.size === 0);
});

Deno.test("generation: the production Flutter sample passes the real registry and writes a card", async () => {
  const input = parseCreateTasteCardResultRequestV1(flutterWire);
  const repository = new ActualQuestionnaireRepository(margaux);
  const outcome = await createTasteCardResultV1(
    testDependencies(repository),
    input,
    null,
  );
  assert(outcome.state === "final");
  same(repository.finalized!.request, input);
  const { view } = outcome.result;
  assert(view.positive.length >= 1 && view.burden.length >= 1);
  assert(!view.bite.summary.includes("undefined"));
});

Deno.test("generation: a reader for whom every taste was 적당했어요 gets the balanced card", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const outcome = await createTasteCardResultV1(
    testDependencies(repository),
    request({
      sensory_aroma: ["aroma:unsure"],
      sensory_taste: [
        "reaction:taste:sweetness:fine",
        "reaction:taste:acidity:fine",
      ],
      sensory_mouthfeel: ["mouthfeel:unsure"],
      sensory_finish: ["finish:unsure"],
      sensory_revisit: ["revisit:unsure"],
    }),
    null,
  );
  assert(outcome.state === "final");
  const { view } = outcome.result;
  assert(view.bite.nickname === "취향 탐색자", view.bite.nickname);
  // The bottle's own levels say what 적당 meant: dry, brisk acidity.
  same(view.bite.tags, [
    { label: "밸런스", kind: "fine", term: null },
    { label: "드라이", kind: "fine", term: null },
    { label: "산뜻함", kind: "fine", term: null },
  ]);
  assert(
    !view.bite.summary.includes("\n") && view.bite.summary.endsWith("요.") &&
      view.bite.summary.includes("산미") && !view.bite.summary.includes("**"),
    view.bite.summary,
  );
  assert(
    view.bite.guide?.head.startsWith("이번 잔의 균형이 편안하셨다면") &&
      !view.bite.guide.head.includes("좋으셨죠"),
    view.bite.guide?.head ?? "no guide",
  );
  same(view.positive, []);
  same(view.burden, []);
  same(view.balanced.map((p) => p.answer), [
    "단맛 없이도 적당하고 편안했어요",
    "산미가 튀지 않고 적당했어요",
  ]);
  // No level numbers and no closing advice: the guide already says what to pick.
  for (const p of view.balanced) {
    assert(!/\(|앞으로/.test(p.text), p.text);
  }
});

Deno.test("generation: a transient catalog failure stores only a retryable attempt", async () => {
  const repository = new ActualQuestionnaireRepository({ failWith: 503 });
  const outcome = await createTasteCardResultV1(
    testDependencies(repository),
    request(cherryAnswers),
    null,
  );
  assert(outcome.state === "retryable");
  assert(outcome.error_code === "catalog_unavailable");
  assert(outcome.retry_after_ms === 30_000);
  assert(repository.finalizations === 0 && repository.results.size === 0);
  const [attempt] = repository.attempts.values();
  assert(attempt.state === "retryable");
});

Deno.test("generation: the wrong questionnaire or invalid answers never reach the engine", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const deps = testDependencies(repository);
  await rejects(
    () =>
      createTasteCardResultV1(
        deps,
        request(cherryAnswers, {
          questionnaire_version: "adaptive-onboarding-v3",
        }),
        null,
      ),
    "questionnaire_contract_invalid",
  );
  await rejects(
    () =>
      createTasteCardResultV1(
        deps,
        request({
          ...cherryAnswers,
          sensory_aroma: ["reaction:aroma:cherry:liked"],
        }, { idempotency_key: AUTH }),
        null,
      ),
    "sensory_questionnaire_invalid",
  );
  assert(repository.finalizations === 0);
});

Deno.test("generation: a member's card is saved at once, reopened from storage, and gated on replay", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const deps = testDependencies(repository);
  const authenticated = request(cherryAnswers, {
    idempotency_key: AUTH,
    anonymous_session_id: null,
  });
  const created = await createTasteCardResultV1(deps, authenticated, {
    user_id: "user-one",
  });
  assert(created.state === "final");
  assert(created.result.ownership_state === "saved");
  assert(created.result.conversion === null);
  assert(created.result.view.product.user_name === "민지");
  const reads = repository.catalogReads;
  const reopened = await getOwnedTasteCardResultV1(
    deps,
    created.result.result_id,
    { user_id: "user-one" },
  );
  same(reopened.view, created.result.view, "stored view reused");
  assert(repository.catalogReads === reads, "detail reads no sources");
  await rejects(
    () =>
      getOwnedTasteCardResultV1(deps, created.result.result_id, {
        user_id: "user-two",
      }),
    "result_not_found",
  );
  await rejects(
    () =>
      createTasteCardResultV1(deps, authenticated, {
        user_id: "inactive-user",
      }),
    "active_account_required",
  );
  await rejects(
    () =>
      createTasteCardResultV1(
        deps,
        request(cherryAnswers, { idempotency_key: AUTH }),
        { user_id: "user-one" },
      ),
    "authenticated_anonymous_session_forbidden",
  );
});

Deno.test("generation: conversion keeps the card, rejects tampering, and ends the anonymous proof", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const deps = testDependencies(repository);
  const created = await createTasteCardResultV1(
    deps,
    request(cherryAnswers),
    null,
  );
  assert(created.state === "final" && created.result.conversion !== null);
  const conversion = {
    anonymous_session_id: "anonymous-session-one",
    result_id: created.result.result_id,
    conversion_token: created.result.conversion.conversion_token,
    idempotency_key: CONVERT,
  };
  const parts = conversion.conversion_token.split(".");
  parts[2] = (parts[2][0] === "a" ? "b" : "a") + parts[2].slice(1);
  await rejects(
    () =>
      convertAnonymousTasteCardV1(
        deps,
        { ...conversion, conversion_token: parts.join(".") },
        { user_id: "user-one" },
      ),
    "conversion_token_rejected",
  );
  const saved = await convertAnonymousTasteCardV1(deps, conversion, {
    user_id: "user-one",
  });
  assert(saved.result_id === created.result.result_id);
  assert(saved.snapshot_ref === created.result.snapshot_ref);
  same(saved.view, created.result.view);
  assert(saved.ownership_state === "saved" && saved.conversion === null);
  await rejects(
    () => createTasteCardResultV1(deps, request(cherryAnswers), null),
    "anonymous_result_claimed",
  );
});

Deno.test("generation: anonymous replays never extend the 30 day retention window", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const created = await createTasteCardResultV1(
    testDependencies(repository),
    request(cherryAnswers),
    null,
  );
  assert(created.state === "final" && created.result.conversion !== null);
  const nearEnd = testDependencies(
    repository,
    new Date("2026-10-04T23:50:00.000Z"),
  );
  const replay = await createTasteCardResultV1(
    nearEnd,
    request(cherryAnswers),
    null,
  );
  assert(replay.state === "final" && replay.result.conversion !== null);
  const claims = await nearEnd.token_signer.verify(
    replay.result.conversion.conversion_token,
  );
  same(
    claims.expires_at_epoch_seconds,
    Date.parse("2026-10-05T00:00:00.000Z") / 1000,
    "token capped at the window",
  );
  await rejects(
    () =>
      createTasteCardResultV1(
        testDependencies(repository, new Date("2026-10-05T00:00:00.000Z")),
        request(cherryAnswers),
        null,
      ),
    "anonymous_result_expired",
  );
});

Deno.test("wire: the public parser accepts exactly the stored envelope and fails closed on anything else", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const created = await createTasteCardResultV1(
    testDependencies(repository),
    request(cherryAnswers),
    null,
  );
  assert(created.state === "final");
  const envelope = JSON.parse(JSON.stringify(created.result));
  same(parseTasteCardResultEnvelope(envelope), created.result);
  const broken = (mutate: (copy: Record<string, unknown>) => void) => {
    const copy = structuredClone(envelope) as Record<string, unknown>;
    mutate(copy);
    return copy;
  };
  const view = (copy: Record<string, unknown>) =>
    copy.view as Record<string, unknown>;
  for (
    const [code, mutate] of [
      ["unknown_wire_schema_version", (c) => {
        c.wire_schema_version = "taste-card-result-wire-v2";
      }],
      ["wire_keys_mismatch", (c) => {
        c.semantic_snapshot = {};
      }],
      ["wire_keys_mismatch", (c) => {
        view(c).next_drink = { candidates: [] };
      }],
      ["wire_keys_mismatch", (c) => {
        (view(c).bite as Record<string, unknown>).facts = {};
      }],
      ["non_empty_string_required", (c) => {
        (view(c).bite as Record<string, unknown>).summary = "";
      }],
      ["schema_version_required", (c) => {
        (view(c).metadata as Record<string, unknown>).schema_version = 2;
      }],
      ["snapshot_ref_mismatch", (c) => {
        c.snapshot_ref = "other";
      }],
      ["conversion_ownership_mismatch", (c) => {
        c.conversion = null;
      }],
    ] as [string, (copy: Record<string, unknown>) => void][]
  ) {
    await rejects(
      () => Promise.resolve(parseTasteCardResultEnvelope(broken(mutate))),
      code,
    );
  }
});

Deno.test("wire: the generator's envelope has exactly the shared fixture's key structure", async () => {
  // fixtures/taste_card_envelope_v3.json is the contract Flutter's parser tests read too;
  // only the keys are pinned, so copy changes never touch it.
  const repository = new ActualQuestionnaireRepository(margaux);
  const created = await createTasteCardResultV1(
    testDependencies(repository),
    request(cherryAnswers),
    null,
  );
  assert(created.state === "final");
  const envelope = JSON.parse(JSON.stringify(created.result));
  same(
    keyShape(envelope),
    keyShape(envelopeFixture),
    "envelope key structure",
  );
  same(parseTasteCardResultEnvelope(envelopeFixture), envelopeFixture);
  assert(envelopeFixture.wire_schema_version === "taste-card-result-wire-v3");
});
