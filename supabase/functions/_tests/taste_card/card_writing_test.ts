import { senseChoices } from "../../_shared/record_reading/dictionary/aromas.ts";
import { AROMA_SAID } from "../../_shared/taste_card/writing/reason_aroma.ts";
import {
  AROMA_EFFECTS,
  aromaEffect,
} from "../../_shared/record_reading/facts/aroma_effects.ts";
import { josa } from "../../_shared/korean.ts";
import {
  catalogSamples,
  recordFrom,
  sampleProduct,
} from "../helpers/card_fixture_record.ts";
import { writeCard } from "../../_shared/taste_card/writing/card_text.ts";
import type { SensoryProduct } from "../../_shared/record_reading/record/sensory_record.ts";
import { assert, same as equal } from "../helpers/assert.ts";

Deno.test("card writing: particles follow the syllable before them, including digits and quotes", () => {
  equal(
    josa("샤또 마고{은} 와인{예요}."),
    "샤또 마고는 와인이에요.",
    "no final consonant",
  );
  equal(
    josa("해창 12도{은} 막걸리{예요}."),
    "해창 12도는 막걸리예요.",
    "digit 2 has no final",
  );
  equal(
    josa("청명주 17{은} 약주{예요}."),
    "청명주 17은 약주예요.",
    "digit 7 has a final",
  );
  equal(
    josa("'드라이한 와인'{이} 맞아요"),
    "'드라이한 와인'이 맞아요",
    "looks past the quote",
  );
  equal(
    josa("진{이라} 맥주{과} 사케{을} 체리 향{을}"),
    "진이라 맥주와 사케를 체리 향을",
    "이라/과/을",
  );
});

Deno.test("card writing: every aroma a reader can pick has an effect text, liked and as a burden", () => {
  const selectable = senseChoices().filter((c) => c.of === "descriptor")
    .map((c) => c.key);
  assert(selectable.length > 100, "selectable aromas");
  equal(
    selectable.filter((key) => aromaEffect(key) === null),
    [],
    "aromas without an effect row",
  );
  // An aroma carries no strength: one text for liked, one for a burden.
  for (const row of Object.keys(AROMA_EFFECTS)) {
    assert(AROMA_SAID[row]?.liked, `${row} has no liked text`);
    assert(AROMA_SAID[row]?.burden, `${row} has no burden text`);
  }
  // The nearest node on the aroma's line decides: 체리 hangs under 핵과 but is
  // sour fruit, 수박 under 멜론 but fresh, 코코넛 under 열대과일 but sweet.
  equal(
    ["peach", "cherry", "watermelon", "coconut", "toast", "juniper"].map(
      aromaEffect,
    ),
    [
      "effect_ripe_fruit",
      "effect_sour_fruit",
      "effect_fresh_fruit",
      "effect_sweet_scent",
      "effect_grain_nut",
      "effect_green",
    ],
    "nearest node",
  );
});

Deno.test("card writing: 더 있었으면 is told as a lack and by the kind, never as a burden", async () => {
  const samples = await catalogSamples();
  const soju = samples.find((c) =>
    c.style_key === "distilled_soju" && c.processes.includes("pot_distillation")
  )!;
  assert(soju, "no pot-distilled soju sample");
  const product = (
    levels: SensoryProduct["levels"],
    sources: SensoryProduct["levelSources"],
  ): SensoryProduct => ({
    ...sampleProduct(soju),
    levels,
    levelSources: sources,
  });
  // 단맛 at a low step, marked 아쉬웠어요: more of it was wanted.
  const answers = ["level:sweetness:2:disliked", "revisit:wouldAcceptAgain"];
  const read = { sweetness: 3, acidity: 3, bitterness: 3 };
  for (
    const p of [
      // No reading of its own, its own low numbers, and a sweet bottle (4)
      // the reader still found lacking: the reader's low step is what the
      // kind is known for, so the kind tells it each time.
      product({}, {}),
      product({ sweetness: 2, acidity: 2, bitterness: 1 }, read),
      product({ sweetness: 4, acidity: 2, bitterness: 3 }, read),
    ]
  ) {
    const card = writeCard(recordFrom("lack", answers, p), soju.name);
    equal(card.tags, [{ label: "옅은단맛", kind: "burden" }]);
    equal(card.summary, "옅은 단맛은 조금 아쉬웠어요.");
    equal(card.burden.map((q) => q.answer), ["옅은 단맛"]);
    const text = card.burden[0].text.replaceAll("**", "");
    equal(
      text,
      "• 옅은 단맛은 증류식 소주의 특징이에요. 발효 후 증류 과정을 거치며 당분이 남지 않아, 술이 메마르고 심심하게 느껴져요.",
    );
    assert(!/부담스러/.test(text), `lack worded as burden: ${text}`);
    // 쓴맛 is no longer asked, so it is never named.
    assert(!text.includes("쓴맛"), `쓴맛 named: ${text}`);
  }
});

Deno.test("card writing: a section names each thing once", async () => {
  const samples = await catalogSamples();
  const product = (category: string, aromas: readonly string[]) =>
    sampleProduct(samples.find((s) => s.category === category)!, aromas);
  const once = (text: string, word: string) =>
    text.split(`**${word}**`).length === 2;
  // Two aromas minded alike: one paragraph, a point each.
  const twins = writeCard(recordFrom("twins", [
    "aroma:nose:apple:disliked",
    "aroma:nose:citrus:disliked",
    "aroma:nose:smoke:liked",
    "revisit:wantAgain",
  ], product("wine", ["apple", "citrus", "smoke"])));
  equal(twins.burden.length, 1, JSON.stringify(twins.burden));
  const twinText = twins.burden[0].text;
  assert(
    twins.burden[0].answer.includes("사과") &&
      twins.burden[0].answer.includes("시트러스"),
    `twin name: ${twins.burden[0].answer}`,
  );
  assert(
    once(twinText, "사과 향") && once(twinText, "시트러스 향") &&
      twinText.split("\n\n").length === 2,
    `both named once: ${twinText}`,
  );
  // A long finish and an aroma that stayed in it: two points, each named once.
  const echo = writeCard(recordFrom("echo", [
    "level:finish_length:4:liked",
    "aroma:finish:vanilla:liked",
    "revisit:wantAgain",
  ], product("whisky", [])));
  equal(echo.positive.length, 1, JSON.stringify(echo.positive));
  assert(
    echo.positive[0].answer.includes("여운") &&
      echo.positive[0].answer.includes("바닐라 향"),
    `echo name: ${echo.positive[0].answer}`,
  );
  const echoText = echo.positive[0].text;
  const echoBold = echoText.match(/\*\*[^*]+\*\*/g) ?? [];
  assert(
    new Set(echoBold).size === echoBold.length && once(echoText, "여운") &&
      once(echoText, "바닐라 향") && echoText.split("\n\n").length === 2,
    `two different meetings, named once each: ${echoText}`,
  );
  // The same aroma by the nose and after swallowing is one point.
  const stayed = writeCard(recordFrom("stayed", [
    "aroma:nose:vanilla:liked",
    "aroma:finish:vanilla:liked",
  ], product("whisky", [])));
  equal(stayed.positive.length, 1, JSON.stringify(stayed.positive));
  assert(
    once(stayed.positive[0].text, "바닐라 향") &&
      !stayed.positive[0].text.includes("\n"),
    stayed.positive[0].text,
  );
  // Aromas that bothered after swallowing share one paragraph.
  const off = writeCard(recordFrom("off", [
    "aroma:finish:oak:disliked",
    "aroma:finish:smoke:disliked",
  ], product("whisky", [])));
  equal(off.burden.length, 1, JSON.stringify(off.burden));
  assert(
    once(off.burden[0].text, "오크 향") &&
      once(off.burden[0].text, "스모키 향") &&
      off.burden[0].text.split("오크").length === 2,
    off.burden[0].text,
  );
});

Deno.test("card writing: 끝맛의 인상 and a middle step are told from what was felt, tag and summary with them", async () => {
  const samples = await catalogSamples();
  const wine = sampleProduct(samples.find((s) => s.category === "wine")!, []);
  const liked = writeCard(
    recordFrom("character", ["level:finish_character:4:liked"], wine),
  );
  equal([liked.positive.length, liked.burden.length], [1, 0]);
  assert(
    !/[{}]|undefined/.test(liked.positive[0].text),
    liked.positive[0].text,
  );
  equal([liked.summary, liked.brief, liked.tags], [
    "진한 끝맛이 기분 좋게 잘 맞았어요.",
    "진한 끝맛이 기분 좋게 잘 맞았어요.",
    [{ label: "진한끝맛", kind: "liked" }],
  ]);
  const minded = writeCard(
    recordFrom("character", ["level:finish_character:1:disliked"], wine),
  );
  equal([minded.positive.length, minded.burden.length], [0, 1]);
  // A clean end that was minded is a lack, not too much, and is not named
  // by the word that praises it.
  equal([minded.summary, minded.tags], [
    "옅은 끝맛은 조금 아쉬웠어요.",
    [{ label: "옅은끝맛", kind: "burden" }],
  ]);
  // A middle step no cause explains is still what the reader answered.
  const middle = writeCard(recordFrom("middle", ["level:body:3:liked"], wine));
  equal(middle.positive.map((p) => p.answer), ["적당한 바디감"]);
  equal([middle.nickname, middle.summary, middle.tags], [
    "취향 탐색자",
    "적당한 바디감이 기분 좋게 잘 맞았어요.",
    [{ label: "적당한바디감", kind: "liked" }],
  ]);
});
