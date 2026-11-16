import { readCard } from "../../_shared/taste_card/facts/reading.ts";
import { buildCardFacts } from "../../_shared/taste_card/findings/conclusions.ts";
import { selectTasteNickname } from "../../_shared/taste_card/nickname/selector.ts";
import { sensoryOptions } from "../../_shared/taste_card/record/questionnaire.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
import { same as equal } from "../helpers/assert.ts";
import { recordFrom } from "../helpers/card_fixture_record.ts";

const bottle = (
  category: SensoryProduct["category"],
  styleKey: string,
): SensoryProduct => ({
  name: "시험 병",
  category,
  styleKey,
  region: null,
  abv: null,
  levels: {},
  levelRefs: {},
  descriptors: [],
});
const RED = bottle("wine", "red_wine");
const WHISKY = bottle("whisky", "single_malt_whisky");

/** The name of a record answered with these options. */
const nickname = (keys: string[], product = RED) =>
  selectTasteNickname(
    readCard(recordFrom("nickname", keys, product)).reactions,
  );

Deno.test("nickname priority is specificity, a named strength, then stable order", () => {
  const base = ["aroma:nose:cherry:liked", "level:sweetness:3:liked"];
  equal(nickname(base).label, "프루티 러버");
  const specific = [...base, "level:tannin:2:liked"];
  const winner = nickname(specific);
  equal(winner.label, "실키 프루티 러버");
  equal(nickname([...specific].reverse()), winner);
  // The same aroma named again in the mouth changes nothing but its support.
  equal(
    nickname([...specific, "aroma:palate:cherry:liked"]).label,
    winner.label,
  );
});

Deno.test("nickname: the strength a gauge step names belongs to that sensation alone", () => {
  // 아쉬웠던 것 never names the card, whatever its step.
  const answers = [
    "aroma:nose:cherry:liked",
    "aroma:nose:apple:disliked",
    "level:acidity:2:disliked",
  ];
  const plain = nickname(answers);
  equal(plain.label, "프루티 러버");
  equal(plain.support_option_keys, ["aroma:nose:cherry:liked"]);
  equal(plain.additional_reason_count, 0);
  // A liked low step is 은은한, a liked high step 선명한, the middle neither.
  equal(nickname(["level:sweetness:2:liked"]).label, "은은한 스위트 러버");
  equal(nickname(["level:sweetness:4:liked"]).label, "선명한 스위트 러버");
  equal(nickname(["level:sweetness:3:liked"]).label, "스위트 러버");
  equal(nickname(["aroma:nose:vanilla:liked"]).label, "스위티 러버");
  // The gauges of a kind name their own sensations.
  equal(nickname(["level:body:4:liked"]).label, "풀바디 러버");
  equal(nickname(["level:spice:4:liked"], WHISKY).label, "쏘핫 러버");
  equal(nickname(["level:peat:4:liked"], WHISKY).label, "스모키 러버");
});

Deno.test("nickname distinguishes unevaluated, disliked and finish-only positive answers", () => {
  // A middle 바디 is kept as a gauge and names nothing.
  equal(nickname(["level:body:3:liked"]).label, "취향 탐색자");
  // An aroma that bothered after swallowing is a burden.
  equal(
    nickname(["aroma:finish:smoke:disliked", "revisit:wantAgain"]).label,
    "취향 유랑자",
  );
  const negative = ["level:sweetness:2:disliked"];
  equal(nickname(negative).label, "취향 유랑자");
  // Every liked finish has a finish-only name.
  equal(
    nickname([...negative, "level:finish_length:2:liked"]).label,
    "클린 피니쉬 러버",
  );
  equal(nickname(["level:finish_length:4:liked"]).label, "피니쉬 러버");
  equal(
    nickname([...negative, "aroma:finish:vanilla:liked"]).label,
    "아로마 피니쉬 러버",
  );
  // A liked aroma with a long finish carries both.
  equal(
    nickname(["aroma:palate:cherry:liked", "level:finish_length:4:liked"])
      .label,
    "롱 피니쉬 프루티 러버",
  );
});

Deno.test("every aroma and every gauge step alone yields a card with a name", () => {
  // No entry is named after a liked 끝맛의 인상 alone: the card keeps the
  // neutral name and never fails.
  equal(
    buildCardFacts(
      recordFrom("character", ["level:finish_character:4:liked"], RED),
    )
      .nickname,
    "취향 탐색자",
  );
  const kinds = [
    RED,
    bottle("wine", "sparkling_wine"),
    WHISKY,
    bottle("sake", "junmai"),
    bottle("korean_traditional", "takju"),
  ];
  for (const option of sensoryOptions()) {
    // 다시 마시고 싶은지 or a skipped nose alone makes no record.
    if (option.kind !== "aroma" && option.kind !== "level") continue;
    for (const product of kinds) {
      const facts = buildCardFacts(
        recordFrom(option.option_key, [option.option_key], product),
      );
      if (!facts.nickname) throw new Error(option.option_key);
    }
  }
});
