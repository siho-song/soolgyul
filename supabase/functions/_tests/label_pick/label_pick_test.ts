import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  type LabelCandidate,
  type LabelCandidateRepository,
  SupabaseLabelCandidateRepository,
} from "../../_shared/label_pick/candidates.ts";
import {
  AnthropicLabelJudge,
  type LabelJudge,
  LabelJudgeUnavailable,
} from "../../_shared/label_pick/judge.ts";
import { pickDrinkOfLabel } from "../../_shared/label_pick/service.ts";
import { handleLabelPickRequest } from "../../label-pick/index.ts";

const FIRST = "11111111-1111-4111-8111-111111111111";
const SECOND = "22222222-2222-4222-8222-222222222222";
const PHOTO = "/9j/4AAQSkZJRg==";
const USAGE = { input_tokens: 1500, output_tokens: 150 };

function candidate(id: string, photo = true): LabelCandidate {
  return {
    id,
    name: `Wine ${id[0]}`,
    maker: "Maker",
    photo_url: photo ? `https://catalog.test/${id}.webp` : null,
  };
}

function catalogOf(...candidates: LabelCandidate[]): LabelCandidateRepository {
  return {
    loadCandidates: (ids) =>
      Promise.resolve(
        ids.flatMap((id) => candidates.filter((one) => one.id === id)),
      ),
  };
}

/** A judge that answers [pick] and [sure], and [same] of the catalog photo; `null` fails that question. */
function judgeSaying(
  pick: number | null,
  sure: boolean,
  same: boolean | null = false,
): LabelJudge & { asked: string[] } {
  const asked: string[] = [];
  return {
    asked,
    pickCandidate: () => {
      asked.push("pick");
      return pick === null
        ? Promise.reject(new LabelJudgeUnavailable("api_529"))
        : Promise.resolve({ pick, sure, usage: USAGE });
    },
    matchCatalogPhoto: (_photo, picked) => {
      asked.push(`catalog photo of ${picked.id}`);
      return same === null
        ? Promise.reject(new LabelJudgeUnavailable("api_529"))
        : Promise.resolve({ same, usage: USAGE });
    },
  };
}

Deno.test("a drink is shown only when the model, the catalog photo or the unchallenged app is sure of it", async () => {
  const cases: Array<{
    name: string;
    judge: ReturnType<typeof judgeSaying>;
    appSure?: boolean;
    photo?: boolean;
    shown: string | null;
    asked: string[];
  }> = [
    {
      name: "the model is sure of a candidate",
      judge: judgeSaying(2, true),
      shown: SECOND,
      asked: ["pick"],
    },
    {
      name: "the model's sure pick overrules the app's sure find",
      judge: judgeSaying(2, true),
      appSure: true,
      shown: SECOND,
      asked: ["pick"],
    },
    {
      name: "the model is sure none is it, whatever the app found",
      judge: judgeSaying(0, true),
      appSure: true,
      shown: null,
      asked: ["pick"],
    },
    {
      name: "the model only guesses, so the app's sure find stands",
      judge: judgeSaying(2, false, true),
      appSure: true,
      shown: FIRST,
      asked: ["pick"],
    },
    {
      name: "a guess the catalog photo confirms",
      judge: judgeSaying(2, false, true),
      shown: SECOND,
      asked: ["pick", `catalog photo of ${SECOND}`],
    },
    {
      name: "a guess the catalog photo does not confirm",
      judge: judgeSaying(2, false, false),
      shown: null,
      asked: ["pick", `catalog photo of ${SECOND}`],
    },
    {
      name: "a guess whose catalog photo could not be asked about",
      judge: judgeSaying(2, false, null),
      shown: null,
      asked: ["pick", `catalog photo of ${SECOND}`],
    },
    {
      name: "a guess at a drink without a catalog photo",
      judge: judgeSaying(2, false, true),
      photo: false,
      shown: null,
      asked: ["pick"],
    },
    {
      name: "a guess that none is it",
      judge: judgeSaying(0, false, true),
      shown: null,
      asked: ["pick"],
    },
  ];
  for (const { name, judge, appSure, photo, shown, asked } of cases) {
    const result = await pickDrinkOfLabel(
      catalogOf(candidate(FIRST), candidate(SECOND, photo ?? true)),
      judge,
      {
        photo: PHOTO,
        candidateIds: [FIRST, SECOND],
        appSure: appSure ?? false,
      },
    );
    assertEquals(result.drink_id, shown, name);
    assertEquals(judge.asked, asked, name);
  }
});

Deno.test("the app's sure find does not stand once the catalog no longer publishes it", async () => {
  const judge = judgeSaying(1, false, false);
  const result = await pickDrinkOfLabel(catalogOf(candidate(SECOND)), judge, {
    photo: PHOTO,
    candidateIds: [FIRST, SECOND],
    appSure: true,
  });
  assertEquals(result.drink_id, null);
  assertEquals(result.trace.app_sure, false);
  assertEquals(judge.asked, ["pick", `catalog photo of ${SECOND}`]);
});

Deno.test("no candidate left to judge asks the model nothing, and the trace adds up what was spent", async () => {
  const none = judgeSaying(1, true);
  const empty = await pickDrinkOfLabel(catalogOf(), none, {
    photo: PHOTO,
    candidateIds: [FIRST],
    appSure: true,
  });
  assertEquals(empty.drink_id, null);
  assertEquals(none.asked, []);

  const twice = await pickDrinkOfLabel(
    catalogOf(candidate(FIRST)),
    judgeSaying(1, false, true),
    { photo: PHOTO, candidateIds: [FIRST], appSure: false },
  );
  assertEquals(twice.trace, {
    candidates: 1,
    app_sure: false,
    picked: FIRST,
    model_sure: false,
    catalog_photo_same: true,
    input_tokens: 3000,
    output_tokens: 300,
  });
});

Deno.test("a model that does not answer the pick is a 503, not a find", async () => {
  await assertRejects(
    () =>
      pickDrinkOfLabel(catalogOf(candidate(FIRST)), judgeSaying(null, false), {
        photo: PHOTO,
        candidateIds: [FIRST],
        appSure: true,
      }),
    Error,
    "label_pick_unavailable",
  );
});

/** A Messages API that answers [text], and keeps what it was sent. */
function messagesApi(text: string, status = 200) {
  const sent: Record<string, unknown>[] = [];
  const fetchImpl = ((_url: unknown, init?: RequestInit) => {
    sent.push(JSON.parse(String(init?.body)));
    return Promise.resolve(
      new Response(
        JSON.stringify(
          status === 200
            ? {
              id: "msg_1",
              type: "message",
              role: "assistant",
              model: "claude-haiku-5-5",
              content: [{ type: "text", text }],
              stop_reason: "end_turn",
              stop_sequence: null,
              usage: USAGE,
            }
            : { type: "error", error: { type: "invalid_request_error" } },
        ),
        { status, headers: { "Content-Type": "application/json" } },
      ),
    );
  }) as typeof fetch;
  return { sent, fetchImpl };
}

Deno.test("the pick question sends the photo and the numbered candidates, and reads the answer", async () => {
  const api = messagesApi('{"read":"MUGA Reserva","pick":2,"sure":true}');
  const judge = new AnthropicLabelJudge("test-key", api.fetchImpl);
  const answer = await judge.pickCandidate(PHOTO, [
    candidate(FIRST),
    candidate(SECOND),
  ]);
  assertEquals(answer, { pick: 2, sure: true, usage: USAGE });
  const [body] = api.sent;
  assertEquals(body.model, "claude-haiku-5-5");
  assertEquals(
    (body.output_config as Record<string, unknown>).effort,
    "medium",
  );
  const content = (body.messages as { content: Record<string, unknown>[] }[])[0]
    .content;
  assertEquals(content[0].source, {
    type: "base64",
    media_type: "image/jpeg",
    data: PHOTO,
  });
  assertEquals(JSON.parse(String(content[1].text)), {
    candidates: [
      { n: 1, name: "Wine 1 | maker: Maker" },
      { n: 2, name: "Wine 2 | maker: Maker" },
    ],
  });
});

Deno.test("the catalog photo counts as the same product only when the model is sure", async () => {
  for (
    const [text, same] of [
      ['{"differs":"nothing","same":true,"sure":true}', true],
      ['{"differs":"too small to read","same":true,"sure":false}', false],
      ['{"differs":"rosé, not brut","same":false,"sure":true}', false],
    ] as const
  ) {
    const api = messagesApi(text);
    const judge = new AnthropicLabelJudge("test-key", api.fetchImpl);
    const picked = candidate(FIRST);
    const answer = await judge.matchCatalogPhoto(
      PHOTO,
      picked,
      picked.photo_url!,
    );
    assertEquals(answer.same, same, text);
    assertEquals(
      (api.sent[0].output_config as Record<string, unknown>).effort,
      "low",
    );
    const content =
      (api.sent[0].messages as { content: Record<string, unknown>[] }[])[0]
        .content;
    assertEquals(content[1].source, { type: "url", url: picked.photo_url });
  }
});

Deno.test("an answer outside the candidates, unreadable or refused by the API is no answer", async () => {
  const outside = new AnthropicLabelJudge(
    "test-key",
    messagesApi('{"read":"","pick":3,"sure":true}').fetchImpl,
  );
  await assertRejects(
    () => outside.pickCandidate(PHOTO, [candidate(FIRST)]),
    LabelJudgeUnavailable,
    "pick_out_of_range",
  );
  const unreadable = new AnthropicLabelJudge(
    "test-key",
    messagesApi("pick 1").fetchImpl,
  );
  await assertRejects(
    () => unreadable.pickCandidate(PHOTO, [candidate(FIRST)]),
    LabelJudgeUnavailable,
    "answer_unreadable",
  );
  const refused = new AnthropicLabelJudge(
    "test-key",
    messagesApi("", 400).fetchImpl,
  );
  await assertRejects(
    () => refused.pickCandidate(PHOTO, [candidate(FIRST)]),
    LabelJudgeUnavailable,
    "api_400",
  );
});

Deno.test("candidates are read in the order asked, named in English without the year, by the maker's own name", async () => {
  let asked = "";
  const repository = new SupabaseLabelCandidateRepository(
    "https://project.test",
    "service-key",
    ((url: unknown) => {
      asked = String(url);
      return Promise.resolve(
        new Response(JSON.stringify([
          {
            id: SECOND,
            name_ko: "마스미 긴센",
            name_en: null,
            producer: {
              name_ko: "미야사카",
              name_en: null,
              name_native: "真澄",
            },
            photo: { media_path: "sake/a b.webp", publish_status: "staging" },
          },
          {
            id: FIRST,
            name_ko: "무가 레세르바",
            name_en: "Muga Reserva 2019",
            producer: { name_ko: "무가", name_en: "Bodegas Muga" },
            photo: [{
              media_path: "wine/a b.webp",
              publish_status: "published",
            }],
          },
        ])),
      );
    }) as typeof fetch,
  );
  assertEquals(await repository.loadCandidates([FIRST, SECOND]), [
    {
      id: FIRST,
      name: "Muga Reserva",
      maker: "Bodegas Muga",
      photo_url:
        "https://project.test/storage/v1/object/public/alcohol-product-images/wine/a%20b.webp",
    },
    { id: SECOND, name: "마스미 긴센", maker: "真澄", photo_url: null },
  ]);
  assertEquals(
    asked.includes(`id=in.(${FIRST},${SECOND})&publish_status=eq.published`),
    true,
  );
});

function labelPickCall(body: unknown): Request {
  return new Request("https://example.test/functions/v1/label-pick", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("the endpoint answers a signed-in member the drink, and refuses anyone else and a malformed call", async () => {
  const member = () => Promise.resolve({ user_id: "member" });
  const catalog = catalogOf(candidate(FIRST));
  const answered = await handleLabelPickRequest(
    labelPickCall({ photo: PHOTO, candidate_ids: [FIRST], app_sure: false }),
    catalog,
    judgeSaying(1, true),
    member,
  );
  assertEquals(answered.status, 200);
  assertEquals(await answered.json(), { drink_id: FIRST });

  const anonymous = await handleLabelPickRequest(
    labelPickCall({ photo: PHOTO, candidate_ids: [FIRST] }),
    catalog,
    judgeSaying(1, true),
    () => Promise.resolve(null),
  );
  assertEquals(anonymous.status, 401);

  const refusals: Array<[unknown, string]> = [
    [{ photo: "not a photo", candidate_ids: [FIRST] }, "photo_invalid"],
    [{ photo: PHOTO, candidate_ids: [] }, "candidate_ids_invalid"],
    [{ photo: PHOTO, candidate_ids: [FIRST, FIRST] }, "candidate_ids_invalid"],
    [{ photo: PHOTO, candidate_ids: ["drink"] }, "candidate_ids_invalid"],
  ];
  for (const [body, code] of refusals) {
    const response = await handleLabelPickRequest(
      labelPickCall(body),
      catalog,
      judgeSaying(1, true),
      member,
    );
    assertEquals(response.status, 400, code);
    assertEquals(await response.json(), { error_code: code });
  }

  const down = await handleLabelPickRequest(
    labelPickCall({ photo: PHOTO, candidate_ids: [FIRST] }),
    catalog,
    judgeSaying(null, false),
    member,
  );
  assertEquals(down.status, 503);
  assertEquals(await down.json(), { error_code: "label_pick_unavailable" });
});
