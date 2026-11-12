import { selectTasteNickname } from "../../_shared/taste_card/nickname/selector.ts";
import { sensoryOptions } from "../../_shared/taste_card/record/questionnaire.ts";
import { same as equal } from "../helpers/assert.ts";

Deno.test("nickname priority is specificity, positive reason, then stable order", () => {
  const base = [
    "reaction:aroma:cherry:liked",
    "reaction:taste:sweetness:liked",
  ];
  equal(selectTasteNickname(base).label, "프루티 러버");
  const specific = [...base, "reaction:mouthfeel:smooth:liked"];
  const winner = selectTasteNickname(specific);
  equal(winner.label, "실키 프루티 러버");
  equal(selectTasteNickname([...specific].reverse()), winner);
  equal(selectTasteNickname([...specific, ...specific]), winner);
});

Deno.test("nickname reasons remain attached to the original sensation", () => {
  const answers = [
    "reaction:aroma:cherry:liked",
    "reaction:aroma:apple:disliked",
    "reason:aroma:apple:disliked:too_weak",
    "reason:aroma:apple:liked:gentle",
  ];
  const nickname = selectTasteNickname(answers);
  equal(nickname.label, "프루티 러버");
  equal(nickname.support_option_keys, ["reaction:aroma:cherry:liked"]);
  equal(nickname.additional_reason_count, 0);
  equal(
    selectTasteNickname([...answers, "reason:aroma:cherry:liked:gentle"])
      .label,
    "은은한 프루티 러버",
  );
  equal(
    selectTasteNickname(["reaction:aroma:vanilla:liked"]).label,
    "스위티 러버",
  );
  equal(
    selectTasteNickname(["reaction:taste:sweetness:liked"]).label,
    "스위트 러버",
  );
});

Deno.test("nickname distinguishes unevaluated, disliked and finish-only positive answers", () => {
  equal(
    selectTasteNickname(["notice:aroma:apple", "revisit:wantAgain"]).label,
    "취향 탐색자",
  );
  // 잡내 after swallowing is a burden (2026-11-06).
  equal(
    selectTasteNickname([
      "notice:aroma:apple",
      "finish:offFlavor",
      "revisit:wantAgain",
    ]).label,
    "취향 유랑자",
  );
  const negative = [
    "reaction:taste:sweetness:disliked",
    "reason:taste:sweetness:disliked:too_weak",
  ];
  equal(selectTasteNickname(negative).label, "취향 유랑자");
  equal(
    selectTasteNickname([...negative, "finish:clean"]).label,
    "클린 피니쉬 러버",
  );
  // Every liked finish has a finish-only name; 잔향 was added last.
  equal(
    selectTasteNickname(["finish:aromaEcho"]).label,
    "아로마 피니쉬 러버",
  );
  equal(
    selectTasteNickname([...negative, "finish:aromaEcho"]).label,
    "아로마 피니쉬 러버",
  );
});

Deno.test("every questionnaire option alone yields a nickname", () => {
  // The selector throws only when something was liked and no name covers
  // it, so one liked option at a time is the whole exposure.
  for (const option of sensoryOptions()) {
    const nickname = selectTasteNickname([option.option_key]);
    if (!nickname.label) throw new Error(option.option_key);
  }
});
