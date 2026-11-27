// The card store over HTTP: what a failed or odd PostgREST answer becomes,
// and that long lists are read whole.
import { errorResponse } from "../../_shared/errors.ts";
import { TasteCardRepositoryError } from "../../_shared/taste_card/service/errors.ts";
import { SupabaseTasteCardRepository } from "../../_shared/taste_card/service/repository.ts";
import { ITEM } from "../helpers/taste_card_service.ts";
import envelopeFixture from "../fixtures/taste_card_envelope_v3.json" with {
  type: "json",
};
import { assert, same } from "../helpers/assert.ts";

type Handler = (url: URL, init?: RequestInit) => Response | Promise<Response>;

/** A store whose every HTTP call is answered by [handler]; the URLs asked are kept. */
function storeAnswering(handler: Handler) {
  const urls: URL[] = [];
  const repository = new SupabaseTasteCardRepository(
    "https://db.test",
    "service",
    async (input, init) => {
      const url = new URL(String(input));
      urls.push(url);
      return await handler(url, init);
    },
  );
  return { repository, urls };
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status });

async function failureOf(work: () => Promise<unknown>): Promise<unknown> {
  try {
    await work();
  } catch (error) {
    return error;
  }
  throw new Error("expected a failure");
}

Deno.test("repository: an HTML gateway page, a timeout or a dropped connection is a transient store failure", async () => {
  const failures: Array<[string, Handler, string]> = [
    [
      "html 502",
      () => new Response("<html>Bad Gateway</html>", { status: 502 }),
      "http_502",
    ],
    ["plain 504", () => new Response("timeout", { status: 504 }), "http_504"],
    [
      "timeout",
      () => {
        throw new DOMException("signal timed out", "TimeoutError");
      },
      "timeout",
    ],
    [
      "network",
      () => {
        throw new TypeError("connection reset");
      },
      "network_unavailable",
    ],
    [
      "statement cancelled",
      () => json({ code: "57014", message: "canceling statement" }, 500),
      "57014",
    ],
  ];
  for (const [label, handler, code] of failures) {
    const { repository } = storeAnswering(handler);
    same(
      await repository.loadCatalog(ITEM),
      { status: "unavailable_transient" },
      label,
    );
    const error = await failureOf(() => repository.getProfileGate("user"));
    assert(error instanceof TasteCardRepositoryError, `${label}: ${error}`);
    same([error.code, error.transient], [code, true], label);
  }
});

Deno.test("repository: a refusal keeps the database code and is not transient", async () => {
  const { repository } = storeAnswering(() =>
    json({ code: "42501", message: "permission denied" }, 403)
  );
  const error = await failureOf(() => repository.getProfileGate("user"));
  assert(error instanceof TasteCardRepositoryError);
  same([error.code, error.transient], ["42501", false]);
  const unreadable = await failureOf(() =>
    storeAnswering(() => new Response("<html>ok</html>")).repository
      .getProfileGate("user")
  );
  assert(unreadable instanceof TasteCardRepositoryError);
  same(unreadable.code, "response_invalid");
});

Deno.test("repository: a stored card that does not read is an internal error, not the caller's", async () => {
  const { repository } = storeAnswering(() =>
    json({
      wire_schema_version: "taste-card-result-wire-v3",
      result_id: "40000000-0000-4000-8000-000000000001",
      record_id: null,
      snapshot_ref: "snapshot",
      ownership_state: "saved",
      alcohol_identification: {},
      rendered_snapshot: { not: "a view" },
      created_at: "2026-09-05T00:00:00.000Z",
    })
  );
  const error = await failureOf(() =>
    repository.getOwnedResult("40000000-0000-4000-8000-000000000001", "user")
  );
  assert(error instanceof TasteCardRepositoryError, String(error));
  same(error.code, "stored_result_invalid");
  const response = errorResponse(new Request("https://edge.test"), error);
  same(response.status, 500);
  same(await response.json(), { error_code: "internal_error" });
});

Deno.test("repository: the look the store gives beside a card is marked on the card's note, as far as the note offers it", async () => {
  // The fixture is a card as sent; without the marks sending adds, its view
  // reads as a card as stored.
  // deno-lint-ignore no-explicit-any
  const stored = structuredClone(envelopeFixture.view) as any;
  for (const group of stored.note.appearance.groups) delete group.chosen;
  const row = (look: unknown) => ({
    wire_schema_version: "taste-card-result-wire-v3",
    result_id: envelopeFixture.result_id,
    record_id: envelopeFixture.record_id,
    snapshot_ref: envelopeFixture.snapshot_ref,
    ownership_state: "anonymous",
    alcohol_identification: envelopeFixture.alcohol_identification,
    rendered_snapshot: stored,
    ...(look === undefined ? {} : { look }),
    created_at: envelopeFixture.created_at,
  });
  const chosen = async (look: unknown) => {
    const { repository } = storeAnswering(() => json(row(look)));
    const card = await repository.getResultForAttempt("attempt");
    return card!.view.note!.appearance!.groups.map((group) => group.chosen);
  };
  same(await chosen({ appearance: "ruby", appearance_texture: "heavy" }), [
    "ruby",
    "heavy",
  ]);
  same(await chosen({ appearance_texture: "medium" }), [undefined, "medium"]);
  // A whisky's colour is no red wine's; a database before the look was
  // given, and a note with none, mark nothing.
  same(await chosen({ appearance: "mahogany" }), [undefined, undefined]);
  same(await chosen({}), [undefined, undefined]);
  same(await chosen(undefined), [undefined, undefined]);
  same(await chosen("ruby"), [undefined, undefined]);
});

Deno.test("repository: an attempt whose card is gone has no result", async () => {
  const { repository } = storeAnswering(() => new Response("null"));
  same(await repository.getResultForAttempt("attempt"), null);
});

Deno.test("repository: an attempt stored as history_unavailable reads as a general retry", async () => {
  const row = {
    attempt_ref: "attempt",
    idempotency_key: "10000000-0000-4000-8000-000000000001",
    request_digest: "digest",
    state: "retryable",
    reserved_record_id: "record",
    reserved_result_summary_id: "result",
    error_code: "history_unavailable",
    retry_after: "2026-09-05T00:00:30.000Z",
    result_summary_id: null,
    claim_snapshot_id: null,
    conversion_key_version: null,
    conversion_expires_at: null,
    created_at: "2026-09-05T00:00:00.000Z",
    updated_at: "2026-09-05T00:00:00.000Z",
  };
  const { repository } = storeAnswering(() => json([row]));
  const attempt = await repository.findAttempt(
    { kind: "authenticated", user_id: "user" },
    row.idempotency_key,
  );
  same(attempt?.error_code, "engine_temporarily_unavailable");
  const unknown = await failureOf(() =>
    storeAnswering(() => json([{ ...row, error_code: "made_up" }])).repository
      .findAttempt({ kind: "authenticated", user_id: "user" }, "key")
  );
  assert(unknown instanceof TasteCardRepositoryError);
  same(unknown.code, "attempt_error_invalid");
});

Deno.test("repository: the letters read every record past the API's 1000-row cap, from the records and not from their cards", async () => {
  const records = Array.from({ length: 2500 }, (_, index) => ({
    id: `record-${index}`,
    created_at: "2026-09-05T00:00:00Z",
    // No longer read: the record is listed and puts no mark.
    questionnaire_version: "sensory-questionnaire-v1",
    alcohol_item_id: "item",
    answers: [],
  }));
  const { repository, urls } = storeAnswering((url) => {
    // Like PostgREST, never more than 1000 rows in one answer.
    const offset = Number(url.searchParams.get("offset") ?? 0);
    const limit = Math.min(Number(url.searchParams.get("limit") ?? 1000), 1000);
    return json(records.slice(offset, offset + limit));
  });
  const source = await repository.loadTasteLetterRecords("user");
  same(source.source_record_ids.length, 2500);
  same(source.source_record_ids.at(-1), "record-2499");
  same(source.records, []);
  same(urls.length, 3);
  for (const url of urls) {
    same(url.pathname.split("/").at(-1), "drink_records");
    same(url.searchParams.get("order"), "created_at.asc,id.asc");
    assert(!url.search.includes("semantic_snapshot"));
  }
});
