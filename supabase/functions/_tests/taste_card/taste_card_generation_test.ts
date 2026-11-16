// The card pipeline end to end: a request goes in, the three-part card comes
// out, is stored once, replays identically, converts, and fails closed.
import { withCardTerms } from "../../_shared/taste_card/writing/terms.ts";
import { withNoteWords } from "../../_shared/taste_card/summary/note_redraw.ts";
import {
  ConversionTokenError,
  TasteCardContractError,
  TasteCardOrchestrationError,
} from "../../_shared/taste_card/service/errors.ts";
import {
  convertAnonymousTasteCard,
  createTasteCardResult,
  getOwnedTasteCardAnswers,
  getOwnedTasteCardResult,
  reviseOwnedTasteCard,
} from "../../_shared/taste_card/service/orchestrator.ts";
import {
  parseCreateTasteCardResultRequest,
  parseTasteCardResultEnvelope,
} from "../../_shared/taste_card/service/serialization.ts";
import flutterWire from "../fixtures/sensory_flutter_wire_v1.json" with {
  type: "json",
};
import envelopeFixture from "../fixtures/taste_card_envelope_v3.json" with {
  type: "json",
};
import {
  ActualQuestionnaireRepository,
  type CatalogRows,
  ITEM,
  tasteCardRequest as request,
  testDependencies,
} from "../fixtures/actual_questionnaire_v3.ts";
import { assert, same } from "../helpers/assert.ts";

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
  styles: [{ term_key: "red_wine", label_ko: "레드 와인" }],
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

Deno.test("generation: a catalog match becomes a three-part card written from the answers and the product", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const deps = testDependencies(repository);
  const outcome = await createTasteCardResult(
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
    "note",
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
    style_label: "레드 와인",
    abv_percent: 13.5,
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
  // The stored view carries no explanations and no redraw words; the served
  // one has the dictionary's and the note's.
  same(withNoteWords(withCardTerms(repository.finalized!.rendered_view)), view);
  assert(repository.finalized!.rendered_view.note?.words === undefined);
  assert(repository.catalogReads >= 1, "the catalog was read");
});

Deno.test("generation: the same request replays the stored card without reading or writing again", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const deps = testDependencies(repository);
  const first = await createTasteCardResult(
    deps,
    request(cherryAnswers),
    null,
  );
  const reads = repository.catalogReads;
  const second = await createTasteCardResult(
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
      createTasteCardResult(
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
      createTasteCardResult(
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
  const input = parseCreateTasteCardResultRequest(flutterWire);
  const repository = new ActualQuestionnaireRepository(margaux);
  const outcome = await createTasteCardResult(
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

Deno.test("generation: a taste left unanswered is not on the card, and 적당했어요 is no answer", async () => {
  const card = async (taste: string[]) => {
    const outcome = await createTasteCardResult(
      testDependencies(new ActualQuestionnaireRepository(margaux)),
      request({
        sensory_aroma: ["aroma:unsure"],
        sensory_taste: taste,
        sensory_mouthfeel: ["mouthfeel:unsure"],
        sensory_finish: ["finish:unsure"],
        sensory_revisit: ["revisit:unsure"],
      }),
      null,
    );
    assert(outcome.state === "final");
    return outcome.result.view;
  };
  const tags = (view: Awaited<ReturnType<typeof card>>) =>
    view.bite.tags.map((tag) => `${tag.label} ${tag.kind}`);
  const said = (view: Awaited<ReturnType<typeof card>>, label: string) => {
    const row = view.note?.balance.find((row) => row.label === label);
    return row && [row.mark, row.felt, row.said];
  };

  const three = await card([
    "reaction:taste:sweetness:liked",
    "reaction:taste:acidity:liked",
    "reaction:taste:bitterness:disliked",
  ]);
  same(tags(three), ["단맛 liked", "산미 liked", "쓴맛 burden"]);
  same(said(three, "산도"), [4, "liked", "좋았어요"]);

  // The same record with 산미 left unanswered: the card says nothing of it,
  // and the sheet keeps the bottle's own level without a word of the reader's.
  const two = await card([
    "reaction:taste:sweetness:liked",
    "reaction:taste:bitterness:disliked",
  ]);
  same(tags(two), ["단맛 liked", "쓴맛 burden"]);
  same(said(two, "산도"), [4, null, null]);
  assert(!two.bite.summary.includes("산미"), two.bite.summary);
  for (const view of [three, two]) {
    same(view.balanced, []);
    assert(view.positive.length === 1 && view.burden.length === 1);
    assert(view.bite.nickname !== "취향 탐색자", view.bite.nickname);
  }

  // The answer the questions once had is an option the questionnaire does
  // not know: refused before an attempt exists.
  const repository = new ActualQuestionnaireRepository(margaux);
  await rejects(
    () =>
      createTasteCardResult(
        testDependencies(repository),
        request({
          sensory_taste: [
            "reaction:taste:sweetness:liked",
            "reaction:taste:acidity:fine",
          ],
        }),
        null,
      ),
    "sensory_questionnaire_invalid",
  );
  same(repository.attempts.size, 0, "no attempt for a refused request");
});

Deno.test("generation: a transient catalog failure stores only a retryable attempt", async () => {
  const repository = new ActualQuestionnaireRepository({ failWith: 503 });
  const outcome = await createTasteCardResult(
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
      createTasteCardResult(
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
      createTasteCardResult(
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
  const created = await createTasteCardResult(deps, authenticated, {
    user_id: "user-one",
  });
  assert(created.state === "final");
  assert(created.result.ownership_state === "saved");
  assert(created.result.conversion === null);
  assert(created.result.view.product.user_name === "민지");
  const reads = repository.catalogReads;
  const reopened = await getOwnedTasteCardResult(
    deps,
    created.result.result_id,
    { user_id: "user-one" },
  );
  same(reopened.view, created.result.view, "stored view reused");
  assert(repository.catalogReads === reads, "detail reads no sources");
  await rejects(
    () =>
      getOwnedTasteCardResult(deps, created.result.result_id, {
        user_id: "user-two",
      }),
    "result_not_found",
  );
  await rejects(
    () =>
      createTasteCardResult(deps, authenticated, {
        user_id: "inactive-user",
      }),
    "active_account_required",
  );
  await rejects(
    () =>
      createTasteCardResult(
        deps,
        request(cherryAnswers, { idempotency_key: AUTH }),
        { user_id: "user-one" },
      ),
    "authenticated_anonymous_session_forbidden",
  );
});

Deno.test("revision: corrected answers write the member's card again in place", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const deps = testDependencies(repository);
  const user = { user_id: "user-one" };
  const created = await createTasteCardResult(
    deps,
    request(cherryAnswers, {
      idempotency_key: AUTH,
      anonymous_session_id: null,
    }),
    user,
  );
  assert(created.state === "final");
  const card = created.result;
  const nose = (view: typeof card.view) =>
    view.note?.nose.flatMap((group) =>
      group.marks.map((mark) => `${group.label}:${mark.label}`)
    );
  same(nose(card.view), ["마음에 들었어요:체리"]);
  const aroma = (keys: string[]) => [{
    question_key: "sensory_aroma",
    selected_option_keys: keys,
    free_text: null,
  }];

  // Saying again what the record holds writes nothing.
  const unchanged = await reviseOwnedTasteCard(
    deps,
    card.result_id,
    aroma([...cherryAnswers.sensory_aroma].reverse()),
    user,
  );
  same(unchanged.view, card.view);
  same(repository.revisions, 0, "nothing rewritten");

  // The aroma is corrected: the note, the card and the letters follow, and
  // the questions not sent keep their answers.
  const revised = await reviseOwnedTasteCard(
    deps,
    card.result_id,
    aroma(["notice:aroma:cherry", "reaction:aroma:cherry:disliked"]),
    user,
  );
  same(repository.revisions, 1);
  same(nose(revised.view), ["부담됐어요:체리"]);
  same(revised.view.note?.texture, card.view.note?.texture);
  same(
    [revised.result_id, revised.record_id, revised.created_at],
    [card.result_id, card.record_id, card.created_at],
    "the same card",
  );
  assert(revised.snapshot_ref !== card.snapshot_ref, "written again");
  assert(revised.ownership_state === "saved" && revised.conversion === null);
  assert(revised.view.note?.words !== undefined, "served with its words");
  same(
    (await repository.loadRecordAnswers(card.record_id!))?.answers.find((a) =>
      a.question_key === "sensory_aroma"
    )?.selected_option_keys,
    ["notice:aroma:cherry", "reaction:aroma:cherry:disliked"],
  );
  same(
    (await getOwnedTasteCardResult(deps, card.result_id, user)).view,
    revised.view,
    "reopened as revised",
  );
  assert(repository.letters.has("user-one"), "letters recomputed");

  // A question answered with nothing is left unanswered.
  const emptied = await reviseOwnedTasteCard(deps, card.result_id, [{
    question_key: "sensory_finish",
    selected_option_keys: [],
    free_text: null,
  }], user);
  same(emptied.view.note?.finish, []);
  same(
    (await repository.loadRecordAnswers(card.record_id!))?.answers.some((a) =>
      a.question_key === "sensory_finish"
    ),
    false,
  );

  // Answers the questionnaire does not allow change nothing.
  await rejects(
    () =>
      reviseOwnedTasteCard(
        deps,
        card.result_id,
        aroma(["notice:aroma:cherry", "no:such:option"]),
        user,
      ),
    "sensory_questionnaire_invalid",
  );
  // Not another member's card, and not an account that left.
  await rejects(
    () =>
      reviseOwnedTasteCard(deps, card.result_id, aroma([]), {
        user_id: "user-two",
      }),
    "result_not_found",
  );
  await rejects(
    () =>
      reviseOwnedTasteCard(deps, card.result_id, aroma([]), {
        user_id: "inactive-user",
      }),
    "active_account_required",
  );
  same(repository.revisions, 2, "the refused ones wrote nothing");
});

Deno.test("revision: a record held with options the questionnaire dropped is read without them and can be corrected", async () => {
  // The record as it was once answered: a taste option and the only 질감
  // answer are ids the questionnaire no longer defines.
  const DROPPED = [
    "reaction:taste:bitterness:dropped",
    "reaction:mouthfeel:drying:dropped",
  ];
  class HeldFromBefore extends ActualQuestionnaireRepository {
    override async loadRecordAnswers(recordId: string) {
      const held = await super.loadRecordAnswers(recordId);
      // Once the card is written again the record holds the new answers.
      if (!held || this.revisions > 0) return held;
      return {
        ...held,
        answers: held.answers.map((answer) =>
          answer.question_key === "sensory_taste"
            ? {
              ...answer,
              selected_option_keys: [
                ...answer.selected_option_keys,
                DROPPED[0],
              ],
            }
            : answer.question_key === "sensory_mouthfeel"
            ? { ...answer, selected_option_keys: [DROPPED[1]] }
            : answer
        ),
      };
    }
  }
  const repository = new HeldFromBefore(margaux);
  const deps = testDependencies(repository);
  const user = { user_id: "user-one" };
  const created = await createTasteCardResult(
    deps,
    request(cherryAnswers, {
      idempotency_key: AUTH,
      anonymous_session_id: null,
    }),
    user,
  );
  assert(created.state === "final");
  const card = created.result;
  const keysOf = (
    answers: readonly {
      question_key: string;
      selected_option_keys: readonly string[];
    }[],
    question: string,
  ) => answers.find((a) => a.question_key === question)?.selected_option_keys;

  // What the member is shown to correct: the answers the questionnaire
  // still has, a question left with none being simply unanswered.
  const shown = await getOwnedTasteCardAnswers(deps, card.result_id, user);
  same(shown.revisable, true);
  same(keysOf(shown.answers, "sensory_taste"), cherryAnswers.sensory_taste);
  same(keysOf(shown.answers, "sensory_mouthfeel"), undefined);
  assert(
    shown.answers.every((a) =>
      a.selected_option_keys.every((key) => !DROPPED.includes(key))
    ),
    JSON.stringify(shown.answers),
  );

  // Saying again what is shown writes nothing.
  const taste = (keys: string[]) => [{
    question_key: "sensory_taste",
    selected_option_keys: keys,
    free_text: null,
  }];
  await reviseOwnedTasteCard(
    deps,
    card.result_id,
    taste(cherryAnswers.sensory_taste),
    user,
  );
  same(repository.revisions, 0, "nothing rewritten");

  // A dropped option is still no answer a client may send.
  await rejects(
    () =>
      reviseOwnedTasteCard(
        deps,
        card.result_id,
        taste([...cherryAnswers.sensory_taste, DROPPED[0]]),
        user,
      ),
    "sensory_questionnaire_invalid",
  );

  // Another question is corrected: the card is written again from the
  // answers the questionnaire has, and the record holds only those.
  const revised = await reviseOwnedTasteCard(deps, card.result_id, [{
    question_key: "sensory_aroma",
    selected_option_keys: [
      "notice:aroma:cherry",
      "reaction:aroma:cherry:disliked",
    ],
    free_text: null,
  }], user);
  same(repository.revisions, 1);
  assert(revised.snapshot_ref !== card.snapshot_ref, "written again");
  const held = (await repository.loadRecordAnswers(card.record_id!))!.answers;
  same(keysOf(held, "sensory_taste"), cherryAnswers.sensory_taste);
  same(keysOf(held, "sensory_mouthfeel"), undefined);
  same(revised.view.note?.texture, []);
  same(keysOf(held, "sensory_aroma"), [
    "notice:aroma:cherry",
    "reaction:aroma:cherry:disliked",
  ]);
});

Deno.test("generation: replaying a request whose card was deleted finds no result", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const deps = testDependencies(repository);
  const authenticated = request(cherryAnswers, {
    idempotency_key: AUTH,
    anonymous_session_id: null,
  });
  const created = await createTasteCardResult(deps, authenticated, {
    user_id: "user-one",
  });
  assert(created.state === "final");
  assert(
    await repository.deleteOwnedRecord(created.result.result_id, "user-one"),
  );
  await rejects(
    () => createTasteCardResult(deps, authenticated, { user_id: "user-one" }),
    "result_not_found",
  );
  assert(repository.finalizations === 1, "no second card is written");
});

Deno.test("generation: conversion keeps the card, rejects tampering, and ends the anonymous proof", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const deps = testDependencies(repository);
  const created = await createTasteCardResult(
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
      convertAnonymousTasteCard(
        deps,
        { ...conversion, conversion_token: parts.join(".") },
        { user_id: "user-one" },
      ),
    "conversion_token_rejected",
  );
  const saved = await convertAnonymousTasteCard(deps, conversion, {
    user_id: "user-one",
  });
  assert(saved.result_id === created.result.result_id);
  assert(saved.snapshot_ref === created.result.snapshot_ref);
  same(saved.view, created.result.view);
  assert(saved.ownership_state === "saved" && saved.conversion === null);
  await rejects(
    () => createTasteCardResult(deps, request(cherryAnswers), null),
    "anonymous_result_claimed",
  );
});

Deno.test("generation: anonymous replays never extend the 30 day retention window", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const created = await createTasteCardResult(
    testDependencies(repository),
    request(cherryAnswers),
    null,
  );
  assert(created.state === "final" && created.result.conversion !== null);
  const nearEnd = testDependencies(
    repository,
    new Date("2026-10-04T23:50:00.000Z"),
  );
  const replay = await createTasteCardResult(
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
      createTasteCardResult(
        testDependencies(repository, new Date("2026-10-05T00:00:00.000Z")),
        request(cherryAnswers),
        null,
      ),
    "anonymous_result_expired",
  );
});

Deno.test("wire: the public parser accepts exactly the stored envelope and fails closed on anything else", async () => {
  const repository = new ActualQuestionnaireRepository(margaux);
  const created = await createTasteCardResult(
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
  const created = await createTasteCardResult(
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
