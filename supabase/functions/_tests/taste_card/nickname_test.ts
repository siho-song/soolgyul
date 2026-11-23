import { groupOfAroma } from "../../_shared/taste_card/facts/aroma_groups.ts";
import {
  NICKNAME_BASE_GROUPS,
  NICKNAME_CATALOG,
} from "../../_shared/taste_card/nickname/catalog.ts";
import { selectNickname } from "../../_shared/taste_card/nickname/selector.ts";
import { interpretAnswers } from "../../_shared/taste_card/prepare/interpretation.ts";
import {
  gaugeSheet,
  sensoryOptions,
} from "../../_shared/taste_card/record/questionnaire.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
import { writeCard } from "../../_shared/taste_card/writing/card_text.ts";
import { same as equal } from "../helpers/assert.ts";
import { recordFrom } from "../helpers/card_fixture_record.ts";

const bottle = (
  category: SensoryProduct["category"],
  styleKey: string | null,
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
const SAKE = bottle("sake", "junmai");
const TAKJU = bottle("korean_traditional", "takju");
/** One bottle for every set of gauges a drink can be asked. */
const SHEETS = [
  RED,
  bottle("wine", "white_wine"),
  bottle("wine", "sparkling_wine"),
  WHISKY,
  SAKE,
  TAKJU,
  bottle("korean_traditional", "yakju"),
  bottle("korean_traditional", "distilled_soju"),
  bottle(null, null),
];

/** The name of a record answered with these options. */
const nickname = (keys: string[], product = RED) =>
  selectNickname(interpretAnswers(recordFrom("nickname", keys, product)));

Deno.test("nickname: a name of two answers goes before a name of one, then 향, 맛, 질감", () => {
  const base = ["aroma:nose:cherry:liked", "level:sweetness:4:liked"];
  equal(nickname(base), "프루티 러버");
  const specific = [...base, "level:tannin:2:liked"];
  equal(nickname(specific), "실키 프루티 러버");
  equal(nickname([...specific].reverse()), "실키 프루티 러버");
  // The same aroma named again in the mouth changes nothing.
  equal(
    nickname([...specific, "aroma:palate:cherry:liked"]),
    "실키 프루티 러버",
  );
  // A finish goes before a mouthfeel.
  equal(
    nickname([...specific, "level:finish_length:2:liked"]),
    "클린 피니쉬 프루티 러버",
  );
  // A strength name is a name of one answer: it never outranks the others.
  equal(nickname([...specific, "level:acidity:2:liked"]), "실키 프루티 러버");
  equal(
    nickname(["aroma:nose:cherry:liked", "level:acidity:2:liked"]),
    "프루티 러버",
  );
  equal(
    nickname([
      "level:umami:4:liked",
      "aroma:nose:melon:liked",
      "level:finish_length:2:liked",
    ], SAKE),
    "클린 피니쉬 프루티 러버",
  );
  equal(
    nickname(["level:sweetness:2:liked", "level:umami:4:liked"], SAKE),
    "드라이 러버",
  );
  equal(
    nickname(["level:acidity:2:liked", "level:umami:4:liked"], SAKE),
    "은은한 시트러스 러버",
  );
  equal(
    nickname(["level:spice:1:liked", "level:body:1:liked"], WHISKY),
    "라이트 러버",
  );
  equal(
    nickname(["level:acidity:2:liked", "level:body:1:liked"]),
    "은은한 시트러스 러버",
  );
});

Deno.test("nickname: each gauge names the side that was liked, and the middle step nothing", () => {
  const steps = (axis: string, product: SensoryProduct) =>
    [1, 2, 3, 4, 5].map((level) =>
      nickname([`level:${axis}:${level}:liked`], product)
    );
  const sides = (low: string, high: string, first = low) => [
    first,
    low,
    "취향 탐색자",
    high,
    high,
  ];
  equal(steps("sweetness", RED), sides("드라이 러버", "스위트 러버"));
  equal(steps("sweetness", SAKE), sides("드라이 러버", "스위트 러버"));
  equal(steps("acidity", RED), sides("은은한 시트러스 러버", "시트러스 러버"));
  equal(steps("umami", SAKE), sides("은은한 우마미 러버", "헤비 우마미 러버"));
  equal(steps("body", RED), sides("라이트 러버", "풀바디 러버"));
  equal(steps("tannin", RED), sides("실키 러버", "떫음 러버"));
  equal(
    steps("spice", WHISKY),
    sides("마일드 스파이시 러버", "스파이시 러버"),
  );
  equal(steps("finish_length", RED), sides("클린 피니쉬 러버", "피니쉬 러버"));
  // The first step of 탄산 and 피트 says there was none of it.
  equal(
    steps("sparkling", TAKJU),
    sides("은은한 스파클링 러버", "스파클링 러버", "취향 탐색자"),
  );
  // 피트 is the 스모키 aroma at every step that has it.
  equal(steps("peat", WHISKY), [
    "취향 탐색자",
    "스모키 러버",
    "스모키 러버",
    "스모키 러버",
    "스모키 러버",
  ]);
  // 끝맛의 인상 lies between two characters a name has no word for.
  equal(steps("finish_character", RED), Array(5).fill("취향 탐색자"));
});

Deno.test("nickname: 아쉬웠던 것 never names the card", () => {
  equal(
    nickname([
      "aroma:nose:cherry:liked",
      "aroma:nose:vanilla:disliked",
      "level:acidity:2:disliked",
      "level:body:5:disliked",
    ]),
    "프루티 러버",
  );
  equal(nickname(["level:sweetness:2:disliked"]), "취향 유랑자");
  // An aroma that bothered after swallowing is a burden too.
  equal(
    nickname(["aroma:finish:smoke:disliked", "revisit:wantAgain"]),
    "취향 유랑자",
  );
  // Liked answers that name nothing leave the burden as all the card says.
  equal(
    nickname(["level:body:3:liked", "level:sweetness:4:disliked"]),
    "취향 유랑자",
  );
  equal(nickname(["level:body:3:liked"]), "취향 탐색자");
});

Deno.test("nickname: a liked finish goes with a base, and alone only without one", () => {
  const minded = ["level:sweetness:2:disliked"];
  equal(
    nickname([...minded, "level:finish_length:2:liked"]),
    "클린 피니쉬 러버",
  );
  equal(
    nickname([...minded, "aroma:finish:vanilla:liked"]),
    "아로마 피니쉬 러버",
  );
  // The middle step liked is no base: the finish still names the card.
  equal(
    nickname(["level:sweetness:3:liked", "level:finish_length:4:liked"]),
    "피니쉬 러버",
  );
  equal(
    nickname(["aroma:palate:cherry:liked", "level:finish_length:4:liked"]),
    "롱 피니쉬 프루티 러버",
  );
  equal(
    nickname(["level:sweetness:1:liked", "level:finish_length:1:liked"]),
    "클린 피니쉬 드라이 러버",
  );
  // An aroma left after swallowing goes with no base.
  equal(
    nickname(["aroma:palate:cherry:liked", "aroma:finish:vanilla:liked"]),
    "프루티 러버",
  );
});

Deno.test("nickname: every name can come out, and every one or two liked answers have one", () => {
  const groupAroma = NICKNAME_BASE_GROUPS.filter((base) =>
    base.domain === "aroma"
  ).map((base) => `aroma:nose:${base.sensory_keys[0]}:liked`);
  const seen = new Set<string>();
  for (const product of SHEETS) {
    const sheet = gaugeSheet(product.category, product.styleKey);
    const answers = [
      ...[...sheet.palate, ...sheet.finish].flatMap((row) =>
        [1, 2, 3, 4, 5].map((level) => `level:${row.axis}:${level}:liked`)
      ),
      ...groupAroma,
      "aroma:finish:vanilla:liked",
    ];
    const axis = (key: string) => key.split(":").slice(0, 2).join(":");
    answers.forEach((first, i) => {
      seen.add(nickname([first], product));
      for (const second of answers.slice(i + 1)) {
        // One gauge takes one step.
        if (first.startsWith("level:") && axis(first) === axis(second)) {
          continue;
        }
        seen.add(nickname([first, second], product));
      }
    });
  }
  const never = NICKNAME_CATALOG.filter((entry) => !seen.has(entry.label));
  equal(never.map((entry) => entry.label), []);
});

Deno.test("nickname: every aroma and every gauge step alone yields a card with a name", () => {
  const kinds = [RED, bottle("wine", "sparkling_wine"), WHISKY, SAKE, TAKJU];
  for (const option of sensoryOptions()) {
    // 다시 마시고 싶은지 or a skipped nose alone makes no record.
    if (option.kind !== "aroma" && option.kind !== "level") continue;
    for (const product of kinds) {
      const record = recordFrom(
        option.option_key,
        [option.option_key],
        product,
      );
      if (!writeCard(record).nickname) throw new Error(option.option_key);
    }
  }
  // Every aroma a reader can pick belongs to a group a name is made of.
  const unnamed = sensoryOptions().flatMap((option) =>
    option.kind === "aroma" && option.stage === "nose" &&
      option.reaction === "liked" && !groupOfAroma(option.aroma)
      ? [option.aroma]
      : []
  );
  equal(unnamed, []);
});
