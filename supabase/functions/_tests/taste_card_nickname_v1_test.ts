import { selectTasteNicknameV1 } from "../_shared/taste_card/nickname_selector_v1.ts";
import { sensoryOptionsV1 } from "../_shared/taste_card/sensory_questionnaire_v1.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}

Deno.test("nickname priority is specificity, positive reason, then stable order", () => {
  const base = [
    "reaction:aroma:cherry:liked",
    "reaction:taste:sweetness:liked",
  ];
  equal(selectTasteNicknameV1(base).label, "프루티 러버");
  const specific = [...base, "reaction:mouthfeel:smooth:liked"];
  const winner = selectTasteNicknameV1(specific);
  equal(winner.label, "실키 프루티 러버");
  equal(selectTasteNicknameV1([...specific].reverse()), winner);
  equal(selectTasteNicknameV1([...specific, ...specific]), winner);
});

Deno.test("nickname reasons remain attached to the original sensation", () => {
  const answers = [
    "reaction:aroma:cherry:liked",
    "reaction:aroma:apple:disliked",
    "reason:aroma:apple:disliked:too_weak",
    "reason:aroma:apple:liked:gentle",
  ];
  const nickname = selectTasteNicknameV1(answers);
  equal(nickname.label, "프루티 러버");
  equal(nickname.support_option_keys, ["reaction:aroma:cherry:liked"]);
  equal(nickname.additional_reason_count, 0);
  equal(
    selectTasteNicknameV1([...answers, "reason:aroma:cherry:liked:gentle"])
      .label,
    "은은한 프루티 러버",
  );
  equal(
    selectTasteNicknameV1(["reaction:aroma:vanilla:liked"]).label,
    "스위티 러버",
  );
  equal(
    selectTasteNicknameV1(["reaction:taste:sweetness:liked"]).label,
    "스위트 러버",
  );
});

Deno.test("nickname distinguishes unevaluated, disliked and finish-only positive answers", () => {
  equal(
    selectTasteNicknameV1(["notice:aroma:apple", "revisit:wantAgain"]).label,
    "취향 탐색자",
  );
  // 잡내 after swallowing is a burden (2026-11-06).
  equal(
    selectTasteNicknameV1([
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
  equal(selectTasteNicknameV1(negative).label, "취향 유랑자");
  equal(
    selectTasteNicknameV1([...negative, "finish:clean"]).label,
    "클린 피니쉬 러버",
  );
  // Every liked finish has a finish-only name; 잔향 was added last.
  equal(
    selectTasteNicknameV1(["finish:aromaEcho"]).label,
    "아로마 피니쉬 러버",
  );
  equal(
    selectTasteNicknameV1([...negative, "finish:aromaEcho"]).label,
    "아로마 피니쉬 러버",
  );
});

Deno.test("every questionnaire option alone yields a nickname", () => {
  // The selector throws only when something was liked and no name covers
  // it, so one liked option at a time is the whole exposure.
  for (const option of sensoryOptionsV1()) {
    const nickname = selectTasteNicknameV1([option.option_key]);
    if (!nickname.label) throw new Error(option.option_key);
  }
});
