import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  tagTerm,
  textTerms,
  withCardTerms,
} from "../_shared/taste_card/card_terms.ts";
import type { TasteCardView } from "../_shared/taste_card/types.ts";

Deno.test("bold sensation words carry the dictionary's explanation, verdict words do not", () => {
  const text =
    "이 와인은 향이 짙어서 **체리 향**이 또렷하게 피어올라요. 단맛이 거의 없어서 **산미** 특유의 산뜻함이 드러나요. " +
    "**떫은 조임**이 혀를 붙들어요. 이 특징이 **기분 좋은 매력**으로 다가온 것 같아요.";
  const terms = textTerms(text);
  assertEquals(terms.map((t) => [t.word, t.label, t.kind]), [
    ["체리 향", "체리", "향"],
    ["산미", "산미", "맛"],
    ["떫은 조임", "떫음", "질감"],
  ]);
  assert(terms.every((t) => t.description.length > 20));
});

Deno.test("a word set in bold twice is explained once; a text without marks has none", () => {
  assertEquals(
    textTerms("**단맛**과 **산미**, 그리고 다시 **단맛**.").map((t) => t.word),
    ["단맛", "산미"],
  );
  assertEquals(textTerms("아무 표시가 없는 글이에요."), []);
});

Deno.test("tags are looked up without their spaces; an unknown tag has no term", () => {
  assertEquals(tagTerm("체리향")?.label, "체리");
  assertEquals(tagTerm("떫은맛")?.label, "떫음");
  assertEquals(tagTerm("긴여운")?.kind, "여운");
  assertEquals(tagTerm("산미")?.kind, "맛");
  assertEquals(tagTerm("기분좋은매력"), null);
});

Deno.test("withCardTerms explains every section and tag and changes nothing else", () => {
  const view = {
    product: {
      drink_name_snapshot: "테스트",
      user_name: null,
      image_reference: null,
      category_label: "와인",
    },
    bite: {
      nickname: "별명",
      tags: [
        { label: "체리향", kind: "liked" },
        { label: "알코올열감", kind: "burden" },
      ],
      summary: "요약",
      guide: null,
    },
    positive: [{ answer: "답", text: "**체리 향**이 좋았어요." }],
    burden: [{ answer: "답", text: "**부담**이었어요." }],
    balanced: [],
    metadata: {
      snapshot_ref: "s",
      schema_version: 3,
      engine_version: "e",
      generated_at: "2026-11-07T00:00:00.000Z",
      generated_from_record_ref: "r",
    },
  } as unknown as TasteCardView;
  const served = withCardTerms(view);
  assertEquals(served.bite.tags[0].term?.label, "체리");
  assertEquals(served.bite.tags[1].term, null);
  assertEquals(served.positive[0].terms?.map((t) => t.word), ["체리 향"]);
  assertEquals(served.burden[0].terms, []);
  assertEquals(served.balanced, []);
  assertEquals(served.product, view.product);
  assertEquals(served.metadata, view.metadata);
  // The stored view is untouched.
  assertEquals("terms" in view.positive[0], false);
});
