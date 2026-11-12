// 나의 술결 네 글자: votes read from the BP cards, the replay over them, and
// the flip rule that keeps one record from turning a letter.
import {
  computeTasteLetters,
  type LetterAxis,
  type LetterRecord,
  type LetterVotes,
  letterVotes,
} from "../../_shared/taste_card/taste_letters.ts";
import { validateCardFacts } from "../../_shared/taste_card/facts/facts.ts";
import {
  convertAnonymousTasteCard,
  createTasteCardResult,
  deleteOwnedTasteCardRecord,
} from "../../_shared/taste_card/service/orchestrator.ts";
import {
  SENSORY_QUESTIONNAIRE_VERSION,
  SENSORY_QUESTIONS,
} from "../../_shared/taste_card/record/questionnaire.ts";
import type { CreateTasteCardResultRequest } from "../../_shared/taste_card/service/types.ts";
import {
  ActualQuestionnaireRepository,
  testDependencies,
} from "../fixtures/actual_questionnaire_v3.ts";

const dir = new URL("../fixtures/card_facts/", import.meta.url);

function same(actual: unknown, expected: unknown, message = "equality") {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${message}: ${a} != ${b}`);
}

async function bpRecords(): Promise<LetterRecord[]> {
  const names: string[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (entry.isFile && /^bp-\d+\.json$/.test(entry.name)) {
      names.push(entry.name);
    }
  }
  names.sort();
  const records: LetterRecord[] = [];
  for (const [index, name] of names.entries()) {
    const facts = validateCardFacts(
      JSON.parse(await Deno.readTextFile(new URL(name, dir))),
    );
    records.push({
      record_id: name,
      product_name: facts.record.product_name,
      recorded_at: new Date(Date.UTC(2025, 8, 1 + index * 11)).toISOString(),
      votes: letterVotes(facts),
    });
  }
  return records;
}

Deno.test("letters: the BP cards vote as the agreed table says", async () => {
  const byName = new Map(
    (await bpRecords()).map((record) => [record.record_id, record.votes]),
  );
  // 샤또 마고: cherry liked (fresh); the finish was not asked about the drying
  // any more (2026-11-06), so no finish vote.
  same(byName.get("bp-01.json"), {
    aroma: "F",
    sweetness: null,
    weight: null,
    finish: null,
  });
  // 해창 12도: the weight was a burden while drinking and after (light), so
  // the finish vote is clean; no aroma or sweetness vote.
  same(byName.get("bp-02.json"), {
    aroma: null,
    sweetness: null,
    weight: "L",
    finish: "C",
  });
  // 아벨라워 아부나흐: warmth welcome while drinking (heavy); the finish no
  // longer asks about warmth.
  same(byName.get("bp-07.json"), {
    aroma: "F",
    sweetness: null,
    weight: "H",
    finish: null,
  });
  // 센킨 니고리: the weight was a burden (light); sweetness was only asked
  // while drinking, where it was not minded.
  same(byName.get("bp-11.json"), {
    aroma: "F",
    sweetness: null,
    weight: "L",
    finish: null,
  });
});

Deno.test("letters: replaying the BP cards as one person's records", async () => {
  const { state, changes } = computeTasteLetters(await bpRecords());
  same(
    Object.fromEntries(
      Object.entries(state.axes).map(([axis, value]) => [axis, value.letter]),
    ),
    { aroma: "F", sweetness: "D", weight: "L", finish: "C" },
    "final letters",
  );
  same(state.axes.sweetness.vote_count, 2, "sweetness votes");
  same(state.axes.sweetness.left_share, 100, "sweetness share");
  // Every letter appears on the first record that voted for its axis; the
  // finish of these sixteen different drinkers swings while its votes are
  // few and even, and the letter swings with its shares.
  same(
    changes.map((change) =>
      `${change.record_id}:${change.axis}:${change.from_letter}>${change.to_letter}`
    ),
    [
      "bp-01.json:aroma:null>F",
      "bp-02.json:weight:null>L",
      "bp-02.json:finish:null>C",
      "bp-03.json:finish:C>P",
      "bp-04.json:finish:P>C",
      "bp-05.json:finish:C>P",
      "bp-06.json:finish:P>C",
      "bp-12.json:sweetness:null>D",
    ],
    "changes",
  );
});

function votesOnly(axis: LetterAxis, letter: string | null): LetterVotes {
  return {
    aroma: null,
    sweetness: null,
    weight: null,
    finish: null,
    [axis]: letter,
  };
}

function series(letters: readonly (string | null)[]): LetterRecord[] {
  return letters.map((letter, index) => ({
    record_id: `r${index + 1}`,
    product_name: `병 ${index + 1}`,
    recorded_at: new Date(Date.UTC(2026, 0, 1 + index)).toISOString(),
    votes: votesOnly("sweetness", letter),
  }));
}

Deno.test("letters: the letter is the heavier side, so it never contradicts its shares", () => {
  // 발베니 (긴 여운) then 화요 (깔끔): the recent record weighs a little more,
  // the shares lean 53 to 47 and the letter follows them.
  const { state, changes } = computeTasteLetters(series(["S", "D"]));
  same(state.axes.sweetness.letter, "D");
  same(state.axes.sweetness.left_share, 53, "D after one dry record");
  same(changes.map((c) => `${c.record_id}:${c.from_letter}>${c.to_letter}`), [
    "r1:null>S",
    "r2:S>D",
  ]);
});

Deno.test("letters: in every replay the letter's side holds at least half the shares", () => {
  const runs = [
    ["S", "S", "S", "S", "S", "D", "D", "D", "D", "D"],
    ["S", "D", "D"],
    ["D", "S", "D", "S", "S"],
    ["S", null, "D", null, "S", "D", "D"],
  ];
  for (const run of runs) {
    for (let n = 1; n <= run.length; n++) {
      const { state } = computeTasteLetters(series(run.slice(0, n)));
      const axis = state.axes.sweetness;
      if (axis.letter === null) continue;
      const own = axis.letter === "D" ? axis.left_share : axis.right_share;
      if (own < 50) {
        throw new Error(`${run.slice(0, n)}: ${axis.letter} at ${own}%`);
      }
    }
  }
});

Deno.test("letters: five sweet then five dry turns once the dry side outweighs", () => {
  const { state, changes } = computeTasteLetters(
    series(["S", "S", "S", "S", "S", "D", "D", "D", "D", "D"]),
  );
  same(state.axes.sweetness.letter, "D");
  same(changes.length, 2, "the reveal and one turn");
  if (changes[1].left_share <= 50) {
    throw new Error(`turned at ${changes[1].left_share}%`);
  }
});

Deno.test("letters: records without a vote keep the shares as they were", () => {
  const { state } = computeTasteLetters(series(["S", null, null, "S"]));
  same(state.axes.sweetness.vote_count, 2);
  same(state.axes.sweetness.right_share, 100);
  same(state.record_count, 4);
});

const ITEM = "30000000-0000-4000-8000-000000000001";
const AUTH = "10000000-0000-4000-8000-000000000002";
const CONVERT = "10000000-0000-4000-8000-000000000003";

function request(
  idempotencyKey: string,
  anonymous: boolean,
): CreateTasteCardResultRequest {
  const answers: Record<string, string[]> = {
    sensory_revisit: ["revisit:wantAgain"],
    sensory_aroma: [
      "notice:aroma:cherry",
      "reaction:aroma:cherry:liked",
      "reason:aroma:cherry:liked:pronounced",
    ],
    sensory_taste: [
      "reaction:taste:acidity:liked",
      "reason:taste:acidity:liked:pronounced",
    ],
    sensory_finish: ["finish:clean"],
  };
  return {
    idempotency_key: idempotencyKey,
    anonymous_session_id: anonymous ? "anonymous-session-one" : null,
    questionnaire_version: SENSORY_QUESTIONNAIRE_VERSION,
    alcohol_identification: {
      mode: "catalog_match",
      alcohol_item_id: ITEM,
      alcohol_name_snapshot: "샤또 마고",
      category: "wine",
    },
    answers: Object.keys(SENSORY_QUESTIONS).map((key) => ({
      question_key: key,
      selected_option_keys: answers[key] ?? [],
      free_text: null,
    })),
    q7_free_text: null,
    photo_asset_id: null,
  };
}

const margauxRows = {
  items: [{
    id: ITEM,
    name_ko: "샤또 마고",
    name_en: "Château Margaux",
    abv_percent: 13.5,
    style_key: "red_wine",
    region_key: null,
    ingredient_keys: [],
    production_process_keys: [],
    grape_variety_keys: ["cabernet_sauvignon"],
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
    aroma_tags: ["cherry", "oak"],
    palate_tags: [],
    finish_tags: [],
    aroma_note: null,
    palate_note: null,
    level_sources: { sweetness: 2, acidity: 2, astringency: 2, body: 2 },
  }],
  media: [],
};

Deno.test("letters: a saved card refreshes the account's letters, a converted one too", async () => {
  const repository = new ActualQuestionnaireRepository(margauxRows);
  const deps = testDependencies(repository);
  await createTasteCardResult(deps, request(AUTH, false), {
    user_id: "user-a",
  });
  const after = repository.letters.get("user-a");
  if (!after) throw new Error("letters not saved for the signed-in card");
  same(after.state.axes.aroma.letter, "F");
  same(after.state.axes.finish.letter, "C");
  same(after.state.axes.sweetness.letter, null);
  same(after.changes.length, 2);

  const anonymous = await createTasteCardResult(
    deps,
    request(CONVERT, true),
    null,
  );
  if (anonymous.state !== "final" || !anonymous.result.conversion) {
    throw new Error("anonymous card expected");
  }
  same(repository.letters.has("user-b"), false, "nothing before conversion");
  await convertAnonymousTasteCard(deps, {
    result_id: anonymous.result.result_id,
    anonymous_session_id: "anonymous-session-one",
    conversion_token: anonymous.result.conversion.conversion_token,
    idempotency_key: CONVERT,
  }, { user_id: "user-b" });
  same(repository.letters.get("user-b")?.state.record_count, 1);
});

Deno.test("letters: deleting a saved record recomputes the letters without it", async () => {
  const repository = new ActualQuestionnaireRepository(margauxRows);
  const deps = testDependencies(repository);
  const created = await createTasteCardResult(deps, request(AUTH, false), {
    user_id: "user-a",
  });
  if (created.state !== "final") throw new Error("saved card expected");
  const resultId = created.result.result_id;
  same(repository.letters.get("user-a")?.state.record_count, 1);

  let refused = "";
  try {
    await deleteOwnedTasteCardRecord(deps, resultId, { user_id: "user-b" });
  } catch (error) {
    refused = (error as { code?: string }).code ?? String(error);
  }
  same(refused, "result_not_found", "a stranger cannot delete the record");
  same(repository.letters.get("user-a")?.state.record_count, 1);

  same(
    await deleteOwnedTasteCardRecord(deps, resultId, { user_id: "user-a" }),
    { deleted: true },
  );
  const after = repository.letters.get("user-a");
  same(after?.state.record_count, 0);
  same(after?.state.axes.aroma.letter, null);
  same(after?.changes.length, 0);
  same(await repository.getOwnedResult(resultId, "user-a"), null);
});

Deno.test("letters: a refused save is read and computed again", async () => {
  class FlakyRepository extends ActualQuestionnaireRepository {
    failures = 2;
    override saveTasteLetters(
      ...args: Parameters<ActualQuestionnaireRepository["saveTasteLetters"]>
    ) {
      if (this.failures-- > 0) return Promise.reject(new Error("blip"));
      return super.saveTasteLetters(...args);
    }
  }
  const repository = new FlakyRepository(margauxRows);
  await createTasteCardResult(
    testDependencies(repository),
    request(AUTH, false),
    { user_id: "user-a" },
  );
  same(repository.letters.get("user-a")?.state.record_count, 1);
});
