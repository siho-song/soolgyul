// The card pipeline end to end: a request goes in, the three-part card comes
// out, is stored once, replays identically, converts, and fails closed.
import { withCardTerms } from "../../_shared/taste_card/writing/help_balloons.ts";
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
import flutterWire from "../fixtures/sensory_flutter_wire_v2.json" with {
  type: "json",
};
import envelopeFixture from "../fixtures/taste_card_envelope_v3.json" with {
  type: "json",
};
import { canonicalJson, sha256Hex } from "../../_shared/canonical.ts";
import type { TasteCardAttempt } from "../../_shared/taste_card/service/repository.ts";
import type { QuestionnaireAnswerInput } from "../../_shared/taste_card/service/types.ts";
import {
  type CatalogRows,
  ITEM,
  MemoryTasteCardRepository,
  tasteCardRequest as request,
  testDependencies,
} from "../helpers/taste_card_service.ts";
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
    finish_character: 3,
    aroma_tags: ["cherry", "oak", "vanilla"],
    palate_tags: [],
    finish_tags: [],
    level_sources: { sweetness: 2, acidity: 2, astringency: 2, body: 2 },
  }],
  media: [{ alcohol_item_id: ITEM, media_path: "wine/margaux.jpg" }],
  styles: [{ term_key: "red_wine", label_ko: "레드 와인" }],
};

/**
 * One record of 샤또 마고 with every question answered: cherry by the nose,
 * a bright acidity, tannin that gripped, cherry again in the mouth, a long finish
 * and oak that bothered after swallowing.
 */
const cherryAnswers = [
  "aroma:nose:cherry:liked",
  "level:acidity:4:liked",
  "level:tannin:4:disliked",
  "aroma:palate:cherry:liked",
  "level:finish_length:4:liked",
  "level:finish_character:4:liked",
  "aroma:finish:oak:disliked",
];
const answer = (
  question_key: string,
  selected_option_keys: string[],
): QuestionnaireAnswerInput => ({
  question_key,
  selected_option_keys,
  free_text: null,
});

Deno.test("generation: a catalog match becomes a three-part card written from the answers and the product", async () => {
  const repository = new MemoryTasteCardRepository(margaux);
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
  assert(view.bite.nickname === "롱 피니쉬 프루티 러버", view.bite.nickname);
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
  // 다음 방향 took the guide's place: a card written now carries no guide.
  same(view.bite.guide, null);
  assert(
    (view.bite.next?.lines.length ?? 0) >= 1 &&
      view.bite.next!.lines.every((line) => line.text.endsWith("요.")),
    JSON.stringify(view.bite.next),
  );
  assert(view.positive.length >= 1 && view.burden.length >= 1);
  for (const paragraph of [...view.positive, ...view.burden]) {
    assert(paragraph.answer && paragraph.text.endsWith("요."), paragraph.text);
  }
  assert(!JSON.stringify(view).includes("undefined"));
  assert(outcome.result.conversion !== null, "anonymous token issued");
  // The note holds what was set and named, by section.
  same(
    [
      view.note?.nose.length,
      view.note?.balance.map((row) => row.key),
      view.note?.flavor?.length,
      view.note?.texture,
      view.note?.finish_balance?.map((row) => row.key),
      view.note?.finish.length,
      view.note?.revisit,
    ],
    [
      1,
      ["sweetness", "acidity", "body", "tannin"],
      1,
      [],
      ["finish_length", "finish_character"],
      1,
      "있음",
    ],
  );
  // The private snapshot is what the card can be written again from: the
  // answers and the bottle as they were read, and nothing the engine concluded.
  const snapshot = repository.finalized!.semantic_snapshot;
  same(Object.keys(snapshot), ["engine_version", "record"]);
  same(snapshot.engine_version, "card-facts-v3");
  same(
    snapshot.record.gauges.map((g) => `${g.axis}:${g.level}:${g.reaction}`),
    [
      "acidity:4:liked",
      "tannin:4:burden",
      "finish_length:4:liked",
      "finish_character:4:liked",
    ],
  );
  assert(snapshot.record.product.levels.acidity === 4);
  same(snapshot.record.product.grapeVarietyKeys, [
    "cabernet_sauvignon",
    "merlot",
  ]);
  assert(
    snapshot.record.product.descriptors.some((d) => d.key === "cherry"),
    "catalog aromas read",
  );
  // The stored view carries no explanations and no redraw words; the served
  // one has the dictionary's and the note's.
  same(withNoteWords(withCardTerms(repository.finalized!.rendered_view)), view);
  assert(repository.finalized!.rendered_view.note?.words === undefined);
  assert(repository.catalogReads >= 1, "the catalog was read");
});

Deno.test("generation: the look sent with the answers is kept as far as the card's kind offers it", async () => {
  const kept = async (
    look: Record<string, string> | undefined,
    catalog: CatalogRows = margaux,
  ) => {
    const repository = new MemoryTasteCardRepository(catalog);
    const outcome = await createTasteCardResult(
      testDependencies(repository),
      request(cherryAnswers, look === undefined ? {} : { look }),
      null,
    );
    assert(outcome.state === "final", "the card is written whatever the look");
    return repository.finalized!.look;
  };
  // A red wine's colour and how it clings to the glass.
  same(await kept({ appearance: "garnet", appearance_texture: "medium" }), {
    appearance: "garnet",
    appearance_texture: "medium",
  });
  same(await kept({ appearance_texture: "heavy" }), {
    appearance_texture: "heavy",
  });
  // A whisky's colour and a 탁주's cloudiness are no red wine's: dropped.
  same(await kept({ appearance: "mahogany", appearance_texture: "milky" }), {});
  // Nothing sent, nothing kept.
  same(await kept(undefined), {});
  // A kind that notes no look keeps none.
  const sake: CatalogRows = {
    ...margaux,
    items: [{
      ...margaux.items![0],
      style_key: "junmai",
      grape_variety_keys: [],
      category: { category_key: "sake" },
    }],
    styles: [{ term_key: "junmai", label_ko: "준마이" }],
  };
  same(
    await kept({ appearance: "garnet", appearance_texture: "medium" }, sake),
    {},
  );
});

Deno.test("generation: the look kept with a visitor's card is marked on the note of the card as it is sent, made, replayed and claimed", async () => {
  const repository = new MemoryTasteCardRepository(margaux);
  const deps = testDependencies(repository);
  const asked = request(cherryAnswers, {
    look: { appearance: "garnet", appearance_texture: "heavy" },
  });
  const chosen = (view: { note?: unknown }) =>
    (view.note as {
      appearance: { groups: { key: string; chosen?: string }[] };
    }).appearance.groups.map((group) => [group.key, group.chosen]);
  const marked = [["appearance", "garnet"], ["appearance_texture", "heavy"]];

  const created = await createTasteCardResult(deps, asked, null);
  assert(created.state === "final" && created.result.conversion !== null);
  same(chosen(created.result.view), marked);
  // The card as stored holds none: the note is kept apart from it.
  same(chosen(repository.finalized!.rendered_view), [
    ["appearance", undefined],
    ["appearance_texture", undefined],
  ]);
  // What is sent reads back through the public parser.
  const sent = JSON.parse(JSON.stringify(created.result));
  same(parseTasteCardResultEnvelope(sent), created.result);

  const replayed = await createTasteCardResult(deps, asked, null);
  assert(replayed.state === "final");
  same(chosen(replayed.result.view), marked);

  const claimed = await convertAnonymousTasteCard(deps, {
    anonymous_session_id: "anonymous-session-one",
    result_id: created.result.result_id,
    conversion_token: created.result.conversion.conversion_token,
    idempotency_key: CONVERT,
  }, { user_id: "user-one" });
  same(chosen(claimed.view), marked);

  // A card made with no look marks nothing.
  const plain = await createTasteCardResult(
    testDependencies(new MemoryTasteCardRepository(margaux)),
    request(cherryAnswers),
    null,
  );
  assert(plain.state === "final");
  same(chosen(plain.result.view), [
    ["appearance", undefined],
    ["appearance_texture", undefined],
  ]);
});

Deno.test("generation: the same request replays the stored card without reading or writing again", async () => {
  const repository = new MemoryTasteCardRepository(margaux);
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
  const repository = new MemoryTasteCardRepository(margaux);
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

Deno.test("generation: the request the app sends, shared with the Flutter suite, passes the real registry and writes a card", async () => {
  const input = parseCreateTasteCardResultRequest(flutterWire);
  const repository = new MemoryTasteCardRepository(margaux);
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

Deno.test("generation: a gauge left unanswered is not on the card, and an option the questionnaire does not know is refused", async () => {
  const card = async (keys: string[]) => {
    const outcome = await createTasteCardResult(
      testDependencies(new MemoryTasteCardRepository(margaux)),
      request(["nose:unsure", "revisit:unsure", ...keys]),
      null,
    );
    assert(outcome.state === "final");
    return outcome.result.view;
  };
  const tags = (view: Awaited<ReturnType<typeof card>>) =>
    view.bite.tags.map((tag) => `${tag.label} ${tag.kind}`);
  const said = (view: Awaited<ReturnType<typeof card>>, key: string) => {
    const row = view.note?.balance.find((row) => row.key === key);
    return row && [row.mark, row.level ?? null, row.felt, row.said !== null];
  };

  const three = await card([
    "level:sweetness:2:liked",
    "level:acidity:4:liked",
    "level:tannin:4:disliked",
  ]);
  // A tag names the step that was answered.
  same(tags(three), ["적은단맛 liked", "높은산미 liked", "높은타닌 less"]);
  same(said(three, "acidity"), [4, 4, "liked", true]);

  // The same record with 산미 left unanswered: the card says nothing of it,
  // and the sheet keeps the bottle's own level without a word of the reader's.
  const two = await card([
    "level:sweetness:2:liked",
    "level:tannin:4:disliked",
  ]);
  same(tags(two), ["적은단맛 liked", "높은타닌 less"]);
  same(said(two, "acidity"), [4, null, null, false]);
  assert(!two.bite.summary.includes("산미"), two.bite.summary);
  for (const view of [three, two]) {
    same(view.balanced, []);
    assert(view.positive.length === 1 && view.burden.length === 1);
    assert(view.bite.nickname !== "취향 탐색자", view.bite.nickname);
  }

  // An option the questionnaire does not know is refused before an attempt
  // exists: an answer of the questions before the gauges, a third way to
  // take a step, two steps of one gauge.
  for (
    const answers of [
      [answer("sensory_taste", ["reaction:taste:sweetness:liked"])],
      [answer("sensory_palate_level", ["level:acidity:4:fine"])],
      [
        answer("sensory_palate_level", [
          "level:acidity:2:liked",
          "level:acidity:4:liked",
        ]),
      ],
    ]
  ) {
    const repository = new MemoryTasteCardRepository(margaux);
    const refused = request();
    await rejects(
      () =>
        createTasteCardResult(
          testDependencies(repository),
          { ...refused, answers: [...refused.answers, ...answers] },
          null,
        ),
      "sensory_questionnaire_invalid",
    );
    same(repository.attempts.size, 0, "no attempt for a refused request");
  }
});

Deno.test("generation: 다시 마시고 싶은지 alone, or with a skipped nose, makes no card", async () => {
  for (
    const keys of [
      ["revisit:wouldAcceptAgain"],
      ["revisit:wantAgain", "nose:unsure"],
    ]
  ) {
    const repository = new MemoryTasteCardRepository(margaux);
    await rejects(
      () =>
        createTasteCardResult(
          testDependencies(repository),
          request(keys),
          null,
        ),
      "sensory_questionnaire_invalid",
    );
    same(repository.attempts.size, 0, "no attempt for a refused request");
  }
});

Deno.test("generation: a transient catalog failure stores only a retryable attempt", async () => {
  const repository = new MemoryTasteCardRepository({ failWith: 503 });
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
  const repository = new MemoryTasteCardRepository(margaux);
  const deps = testDependencies(repository);
  for (
    const version of ["adaptive-onboarding-v3", "sensory-questionnaire-v1"]
  ) {
    await rejects(
      () =>
        createTasteCardResult(
          deps,
          request(cherryAnswers, { questionnaire_version: version }),
          null,
        ),
      "questionnaire_contract_invalid",
    );
  }
  const twice = request(cherryAnswers, { idempotency_key: AUTH });
  await rejects(
    () =>
      createTasteCardResult(deps, {
        ...twice,
        answers: twice.answers.map((a) =>
          a.question_key === "sensory_nose_aroma"
            ? answer("sensory_nose_aroma", [
              "aroma:nose:cherry:liked",
              "aroma:nose:cherry:disliked",
            ])
            : a
        ),
      }, null),
    "sensory_questionnaire_invalid",
  );
  assert(repository.finalizations === 0 && repository.attempts.size === 0);
});

Deno.test("generation: an attempt opened under the questionnaire before, tried again now, ends without a card", async () => {
  // The request as an app of the old questionnaire sent it; its attempt was
  // left retryable and the app tries it again after the gauges shipped.
  const old = {
    ...request(),
    questionnaire_version: "sensory-questionnaire-v1",
    answers: [
      answer("sensory_revisit", ["revisit:wantAgain"]),
      answer("sensory_taste", ["reaction:taste:sweetness:liked"]),
    ],
  };
  const digest = await sha256Hex(canonicalJson(old));
  class InFlight extends MemoryTasteCardRepository {
    override findAttempt(
      principal: Parameters<MemoryTasteCardRepository["findAttempt"]>[0],
      idempotencyKey: string,
    ): Promise<TasteCardAttempt> {
      return Promise.resolve({
        attempt_ref: "attempt-opened-before",
        principal,
        idempotency_key: idempotencyKey,
        request_digest: digest,
        reserved_record_id: "90000000-0000-4000-8000-000000000101",
        reserved_result_summary_id: "90000000-0000-4000-8000-000000000102",
        state: "retryable",
        error_code: "catalog_unavailable",
        retry_after: "2026-09-04T00:00:00.000Z",
        result_summary_id: null,
        claim_snapshot_id: null,
        conversion_key_version: null,
        conversion_expires_at: null,
        created_at: "2026-09-04T00:00:00.000Z",
        updated_at: "2026-09-04T00:00:00.000Z",
      });
    }
  }
  const repository = new InFlight(margaux);
  await rejects(
    () => createTasteCardResult(testDependencies(repository), old, null),
    "questionnaire_contract_invalid",
  );
  assert(repository.finalizations === 0 && repository.catalogReads === 0);
});

Deno.test("generation: a member's card is saved at once, reopened from storage, and gated on replay", async () => {
  const repository = new MemoryTasteCardRepository(margaux);
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
  const repository = new MemoryTasteCardRepository(margaux);
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
  const aroma = (keys: string[]) => [answer("sensory_nose_aroma", keys)];

  // What the member is shown to correct is what the record holds.
  const shown = await getOwnedTasteCardAnswers(deps, card.result_id, user);
  same(shown.revisable, true);
  same(
    shown.answers,
    request(cherryAnswers).answers.map((
      { question_key, selected_option_keys },
    ) => ({ question_key, selected_option_keys })),
  );

  // Saying again what the record holds writes nothing, in whatever order.
  const unchanged = await reviseOwnedTasteCard(
    deps,
    card.result_id,
    [answer("sensory_palate_level", [
      "level:tannin:4:disliked",
      "level:acidity:4:liked",
    ])],
    user,
  );
  same(unchanged.view, card.view);
  same(repository.revisions, 0, "nothing rewritten");

  // The aroma is corrected: the note, the card and the letters follow, and
  // the questions not sent keep their answers.
  const revised = await reviseOwnedTasteCard(
    deps,
    card.result_id,
    aroma(["aroma:nose:cherry:disliked"]),
    user,
  );
  same(repository.revisions, 1);
  same(nose(revised.view), ["부담됐어요:체리"]);
  same(revised.view.note?.balance, card.view.note?.balance);
  same(revised.view.note?.flavor, card.view.note?.flavor);
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
      a.question_key === "sensory_nose_aroma"
    )?.selected_option_keys,
    ["aroma:nose:cherry:disliked"],
  );
  same(
    (await getOwnedTasteCardResult(deps, card.result_id, user)).view,
    revised.view,
    "reopened as revised",
  );
  assert(repository.letters.has("user-one"), "letters recomputed");

  // A part answered again sends its questions, an emptied one with nothing:
  // the finish gauges are cleared and its aroma stays.
  const emptied = await reviseOwnedTasteCard(deps, card.result_id, [
    answer("sensory_finish_level", []),
  ], user);
  same(emptied.view.note?.finish_balance?.map((row) => row.said), [
    null,
  ]);
  same(emptied.view.note?.finish, card.view.note?.finish);
  same(
    (await repository.loadRecordAnswers(card.record_id!))?.answers.some((a) =>
      a.question_key === "sensory_finish_level"
    ),
    false,
  );

  // Answers the questionnaire does not allow change nothing.
  await rejects(
    () =>
      reviseOwnedTasteCard(
        deps,
        card.result_id,
        aroma(["aroma:nose:cherry:liked", "no:such:option"]),
        user,
      ),
    "sensory_questionnaire_invalid",
  );
  // 다시 마시고 싶은지 cannot be emptied.
  await rejects(
    () =>
      reviseOwnedTasteCard(
        deps,
        card.result_id,
        [answer("sensory_revisit", [])],
        user,
      ),
    "sensory_questionnaire_invalid",
  );
  // Nor can every sensation: the record would say nothing that was sensed.
  await rejects(
    () =>
      reviseOwnedTasteCard(
        deps,
        card.result_id,
        [
          "sensory_nose_aroma",
          "sensory_palate_level",
          "sensory_palate_aroma",
          "sensory_finish_level",
          "sensory_finish_aroma",
        ].map((question) => answer(question, [])),
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

Deno.test("revision: a record answered under the questionnaire before keeps its card and cannot be re-answered", async () => {
  // The record as it was answered then, and its card as it was stored then.
  class HeldFromBefore extends MemoryTasteCardRepository {
    override async loadRecordAnswers(recordId: string) {
      const held = await super.loadRecordAnswers(recordId);
      return held && {
        questionnaire_version: "sensory-questionnaire-v1",
        answers: [
          answer("sensory_revisit", ["revisit:wantAgain"]),
          answer("sensory_aroma", [
            "notice:aroma:cherry",
            "reaction:aroma:cherry:liked",
          ]),
          answer("sensory_taste", ["reaction:taste:acidity:liked"]),
        ],
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
  const stored = repository.results.get(card.result_id)!;
  stored.view.metadata.engine_version = "card-facts-v2";

  // The card is shown as it was stored, without the words a re-answer needs.
  const reopened = await getOwnedTasteCardResult(deps, card.result_id, user);
  same(reopened.view.positive, card.view.positive);
  assert(reopened.view.note !== undefined && reopened.view.note !== null);
  same(reopened.view.note.words, undefined);

  // Nothing is given to correct, and nothing sent is taken.
  same(await getOwnedTasteCardAnswers(deps, card.result_id, user), {
    revisable: false,
    answers: [],
  });
  for (
    const answers of [
      [answer("sensory_nose_aroma", ["aroma:nose:cherry:disliked"])],
      [answer("sensory_aroma", ["notice:aroma:cherry"])],
      [],
    ]
  ) {
    await rejects(
      () => reviseOwnedTasteCard(deps, card.result_id, answers, user),
      "questionnaire_contract_invalid",
    );
  }
  same(repository.revisions, 0, "nothing rewritten");
  same(
    (await getOwnedTasteCardResult(deps, card.result_id, user)).view,
    reopened.view,
  );
});

Deno.test("generation: replaying a request whose card was deleted finds no result", async () => {
  const repository = new MemoryTasteCardRepository(margaux);
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
  const repository = new MemoryTasteCardRepository(margaux);
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
  const repository = new MemoryTasteCardRepository(margaux);
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
  const repository = new MemoryTasteCardRepository(margaux);
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
  // only the keys are pinned, so copy changes never touch it. The fixture
  // is a card whose look was chosen, so the note's groups carry `chosen`.
  const repository = new MemoryTasteCardRepository(margaux);
  const created = await createTasteCardResult(
    testDependencies(repository),
    request(cherryAnswers, {
      look: { appearance: "ruby", appearance_texture: "heavy" },
    }),
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
