import { sensoryCatalog as catalog } from "../../_shared/taste_card/dictionary/dictionary.ts";
import {
  BURDEN_PROSE,
  LIKED_PROSE,
} from "../../_shared/taste_card/writing/prose.ts";
import { effectRow } from "../../_shared/taste_card/findings/findings.ts";
import { EFFECT_ROWS } from "../../_shared/taste_card/findings/knowledge.ts";
import {
  fill,
  type Section,
  writeSection,
} from "../../_shared/taste_card/writing/sections.ts";
import { josa } from "../../_shared/taste_card/writing/korean.ts";
import {
  catalogSamples,
  FIXTURE_DISPLAY_NAMES,
  fixtures,
  recordFrom,
} from "../helpers/card_fixture_record.ts";
import { writeCard } from "../../_shared/taste_card/writing/card_text.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
import { assert, same as equal } from "../helpers/assert.ts";

const PLACEHOLDERS = new Set([
  "name",
  "kind",
  "aroma",
  "aroma_short",
  "aromas",
  "aromas_short",
  "aromas_and",
  "aromas_a",
  "aromas_b",
  "aromas_a_short",
  "aromas_b_short",
  "aromas_short_and",
  "aromas_comma",
  "aromas_a_short_and",
  "aromas_b_short_and",
  "family_groups",
  "family_adj",
  "family_noun",
  "family_a_noun",
  "family_b_noun",
  "family_rest",
  "family_last",
  "given_aroma",
  "given_aromas",
  "liked_aromas",
  "burden_aromas",
  "flavour",
  "lingering_burden",
  "lack_body",
  "lack_name",
  "aroma_kind",
  "level",
  "strength",
  "strength_and",
  "level_acidity",
  "level_sweetness",
  "level_astringency",
  "style_fact",
  "style_reason",
  "subject_anchor",
  "subject_noun",
  "으로",
  "이고",
  "이나",
  "은",
  "이",
  "을",
  "과",
  "예요",
  "이라",
]);

Deno.test("card writing: every prose entry has a name and a body and only known placeholders", () => {
  const entries = [
    ...Object.entries(LIKED_PROSE),
    ...Object.entries(BURDEN_PROSE).map(([k, p]) =>
      [`burden:${k}`, p] as const
    ),
  ];
  for (const [key, prose] of entries) {
    for (const part of ["name", "body"] as const) {
      assert(prose[part].trim(), `${key}.${part} is empty`);
    }
    // A name is a short noun phrase: no sentence ending, no closing particle.
    const sample = prose.name.replace(/\{(은|이|을|과)\}/g, "$1").replace(
      /\{[^}]+\}/g,
      "체리 향",
    );
    assert(
      !/[요죠.]$|[은는이가을를]$/.test(sample) && sample.length <= 18,
      `${key}: name is not a short noun phrase: ${prose.name}`,
    );
    for (const text of Object.values(prose)) {
      if (text === undefined) continue;
      for (const m of text.matchAll(/\{([^}]+)\}/g)) {
        assert(PLACEHOLDERS.has(m[1]), `${key}: unknown placeholder {${m[1]}}`);
      }
    }
  }
});

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
  equal(
    fill("{name}{은} {kind}{예요}.", { name: "탱커레이", kind: "진" }),
    "탱커레이는 진이에요.",
    "fill then particles",
  );
});

Deno.test("card writing: every chosen finding of the BP cards becomes one part of a section of the expected shape", async () => {
  for (const [file, facts] of await fixtures()) {
    const name = file.replace(".json", "");
    for (const section of ["positive", "burden"] as const) {
      const where = `${name} ${section}`;
      const written = writeSection(facts, section, {
        productName: FIXTURE_DISPLAY_NAMES[facts.record.product_name],
      });
      equal(written.skipped, [], `${where}: findings without prose`);
      // At most one paragraph per section finding, in order; a finding without
      // prose is written through another explanation of the same answer, and a
      // second explanation of answers already explained is left out, so every
      // answer of the section is spoken of by some paragraph.
      assert(
        written.paragraphs.length <= facts.sections[section].length,
        `${where}: paragraph count ${written.paragraphs.length}`,
      );
      const spoken = new Set(
        written.paragraphs.flatMap((p) =>
          facts.findings.find((d) => d.id === p.finding)!.reactions
        ),
      );
      for (const id of facts.sections[section]) {
        const chosen = facts.findings.find((d) => d.id === id)!;
        assert(
          chosen.reactions.some((r) => spoken.has(r)),
          `${where}: nothing written for ${chosen.id}`,
        );
      }
      if (!written.paragraphs.length) {
        equal([written.title, written.text], ["", ""], `${where}: empty`);
        continue;
      }
      const names = new Set<string>();
      written.paragraphs.forEach((p, i) => {
        assert(p.name && !/[{}]/.test(p.name), `${where}: name ${p.name}`);
        assert(!names.has(p.name), `${where}: name twice: ${p.name}`);
        names.add(p.name);
        assert(!/[{}]/.test(p.body), `${where}: unfilled ${p.body}`);
        assert(
          /[요죠]\.$/.test(p.body),
          `${where}: body does not end in 해요체: ${p.body}`,
        );
        // The second body on is led by 또한 (호감) / 게다가 (부담) and never
        // opens on the bottle again.
        assert(
          i === 0
            ? !/^(또한|게다가) /.test(p.body)
            : new RegExp(`^${section === "positive" ? "또한" : "게다가"} `)
              .test(p.body) &&
              !/^(또한|게다가) 이 (와인|막걸리|사케|위스키|진|소주|맥주)[은는] /
                .test(p.body),
          `${where}: lead of body ${i}: ${p.body}`,
        );
      });
      // The subtitle is the names joined; the text is the bodies and one
      // closing sentence (the user's shape, 2026-11-06).
      assert(
        written.paragraphs.every((p) => written.title.includes(p.name)),
        `${where}: title ${written.title}`,
      );
      const bodies = written.paragraphs.map((p) => p.body).join(" ");
      assert(
        written.text.replaceAll("**", "").startsWith(`${bodies} 이 `),
        `${where}: ${written.text}`,
      );
      assert(
        /\*\*(기분 좋은 매력\*\*으로 다가온|부담\*\*으로 다가온|아쉬움\*\*으로 남은) 것 같아요\.$/
          .test(
            written.text,
          ) && !written.text.includes("'"),
        `${where}: closing: ${written.text}`,
      );
    }
  }
});

Deno.test("card writing: BP-01 and BP-02 are written whole, in shape, and the same every time", async () => {
  const all = new Map(await fixtures());
  const write = (name: string, section: Section) => {
    const facts = all.get(`${name}.json`)!;
    return writeSection(facts, section, {
      productName: FIXTURE_DISPLAY_NAMES[facts.record.product_name],
    });
  };
  const cases: [string, Section, string[]][] = [
    ["bp-01", "positive", ["체리", "산미"]],
    ["bp-02", "positive", ["단맛", "산미"]],
    ["bp-01", "burden", ["떫"]],
    ["bp-02", "burden", ["무게", "무겁"]],
  ];
  for (const [name, section, terms] of cases) {
    const where = `${name} ${section}`;
    const written = write(name, section);
    const facts = all.get(`${name}.json`)!;
    equal(
      written.paragraphs.length,
      facts.sections[section].length,
      `${where}: one paragraph per finding`,
    );
    assert(written.title.length > 0, `${where}: title`);
    assert(!/[{}]|undefined|null/.test(written.text), `${where}: unfilled`);
    const marks = written.text.split("**").length - 1;
    assert(marks >= 2 && marks % 2 === 0, `${where}: bold pairs`);
    assert(
      terms.some((term) => written.text.includes(term)),
      `${where}: names ${terms.join("/")}: ${written.text}`,
    );
    assert(
      /\*\*(기분 좋은 매력|부담|아쉬움)\*\*으로 (다가온|남은) 것 같아요\.$/
        .test(
          written.text,
        ),
      `${where}: closing: ${written.text}`,
    );
    equal(write(name, section), written, `${where}: deterministic`);
  }
});

/* ------------------------------------------------------ 작용 글의 범위 */

Deno.test("card writing: every aroma a reader can pick has an effect text for each frame", () => {
  const selectable = (catalog as {
    descriptors: { key: string; onboarding_selectable?: boolean }[];
  }).descriptors.filter((d) => d.onboarding_selectable).map((d) => d.key);
  assert(selectable.length > 100, "selectable aromas");
  equal(
    selectable.filter((key) => effectRow(key) === null),
    [],
    "aromas without an effect row",
  );
  for (const row of Object.keys(EFFECT_ROWS)) {
    for (const key of [row, `${row}@gentle`]) {
      assert(key in LIKED_PROSE, `${key} has no liked text`);
    }
    for (const key of [row, `${row}@excessive`, `${row}@too_weak`]) {
      assert(key in BURDEN_PROSE, `${key} has no burden text`);
    }
  }
  // The nearest node on the aroma's line decides: 체리 hangs under 핵과 but is
  // sour fruit, 수박 under 멜론 but fresh, 코코넛 under 열대과일 but sweet.
  equal(
    ["peach", "cherry", "watermelon", "coconut", "toast", "juniper"].map(
      effectRow,
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

Deno.test("card writing: 더 있었으면 names the method and reads the lack against the other tastes", async () => {
  const samples = await catalogSamples();
  const soju = samples.find((c) =>
    c.style_key === "distilled_soju" && c.processes.includes("pot_distillation")
  )!;
  assert(soju, "no pot-distilled soju sample");
  const product = (
    levels: Record<string, number>,
    sources: Record<string, number>,
  ) =>
    ({
      name: soju.name,
      category: soju.category,
      styleKey: soju.style_key,
      abv: soju.abv,
      ingredients: soju.ingredients,
      processes: soju.processes,
      grapeVarietyKeys: [],
      levels,
      levelSources: sources,
      levelRefs: {},
      descriptors: soju.aromas.map((key) => ({
        section: "aroma" as const,
        key,
      })),
    }) as unknown as SensoryProduct;
  const answers = [
    "reaction:taste:sweetness:disliked",
    "reason:taste:sweetness:disliked:too_weak",
    "reaction:taste:acidity:fine",
    "reaction:taste:bitterness:fine",
    "aroma:unsure",
    "mouthfeel:unsure",
    "finish:unsure",
    "revisit:wouldAcceptAgain",
  ];
  const lackParagraph = (p: SensoryProduct) => {
    const card = writeCard(recordFrom("lack", answers, p), soju.name);
    const paragraph = card.burden.find((q) => q.answer.includes("아쉬운 단맛"));
    assert(paragraph, `no lack paragraph: ${JSON.stringify(card.burden)}`);
    assert(
      !/부담스러/.test(paragraph.answer + paragraph.text),
      `lack worded as burden: ${paragraph.text}`,
    );
    return paragraph.text.replaceAll("**", "");
  };
  // No reading of its own: the kind, named with its distillation, has little.
  const ofKind = lackParagraph(product({}, {}));
  assert(
    ofKind.includes("단식 증류로 내린 술이라 단맛이"),
    `method not named: ${ofKind}`,
  );
  assert(
    ofKind.endsWith("이 특징이 아쉬움으로 남은 것 같아요."),
    `a lack closed as a burden: ${ofKind}`,
  );
  // The bottle's own low numbers: the fact is the bottle's and the other
  // tastes are quiet.
  const own = lackParagraph(
    product({ sweetness: 2, acidity: 2, bitterness: 1 }, {
      sweetness: 3,
      acidity: 3,
      bitterness: 3,
    }),
  );
  assert(
    own.includes(
      "이 증류식 소주는 단맛이 낮고 산미도 쓴맛도 세지 않은 술이라서",
    ),
    `bottle fact missing: ${own}`,
  );
  // A sweet bottle (4) the reader still found lacking: never told it is sweet,
  // never told its kind lacks sweetness.
  const sweet = lackParagraph(
    product({ sweetness: 4, acidity: 2, bitterness: 3 }, {
      sweetness: 3,
      acidity: 3,
      bitterness: 3,
    }),
  );
  assert(
    !/단맛이 (적|거의 없|꽤)|본래/.test(sweet),
    `level said against the reader: ${sweet}`,
  );
  assert(
    sweet.includes("쓴맛이 어느 정도 있는"),
    `middling taste unused: ${sweet}`,
  );
});

Deno.test("card writing: a section says each thing once (2026-11-06 전수 점검)", async () => {
  const samples = await catalogSamples();
  const product = (category: string, aromas: readonly string[]) => {
    const c = samples.find((s) => s.category === category)!;
    return {
      name: c.name,
      category: c.category,
      styleKey: c.style_key,
      abv: c.abv,
      ingredients: c.ingredients,
      processes: c.processes,
      grapeVarietyKeys: [],
      levels: c.levels,
      levelSources: c.level_sources ?? {},
      levelRefs: {},
      descriptors: aromas.map((key) => ({ section: "aroma" as const, key })),
    } as unknown as SensoryProduct;
  };
  const fine = [
    "reaction:taste:sweetness:fine",
    "reaction:taste:acidity:fine",
    "reaction:taste:bitterness:fine",
  ];
  const quiet = ["mouthfeel:unsure", "finish:unsure"];
  // Two aromas with the same effect text (사과·시트러스 both 겉만 시원한): one paragraph about both.
  const twins = writeCard(recordFrom("twins", [
    "notice:aroma:apple",
    "notice:aroma:citrus",
    "notice:aroma:smoke",
    "reaction:aroma:apple:disliked",
    "reaction:aroma:citrus:disliked",
    "reaction:aroma:smoke:liked",
    "reason:aroma:smoke:liked:pronounced",
    ...fine,
    ...quiet,
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
    twinText.includes("**사과 향**") && twinText.includes("**시트러스 향**") &&
      twinText.split("사과").length === 2,
    `both named once: ${twinText}`,
  );
  // 더 또렷했으면 on an aroma: the effect made conditional, the wish, and the
  // closing run together ("…못했고, 이 특징이 아쉬움으로 남은 것 같아요.").
  const wish = writeCard(recordFrom("wish", [
    "notice:aroma:acacia",
    "reaction:aroma:acacia:disliked",
    "reason:aroma:acacia:disliked:too_weak",
    ...fine,
    ...quiet,
    "revisit:unsure",
  ], product("wine", ["acacia"])));
  equal(wish.burden.length, 1, JSON.stringify(wish.burden));
  assert(
    wish.burden[0].answer.includes("아카시아") &&
      wish.burden[0].answer.includes("아쉬운"),
    `wish name: ${wish.burden[0].answer}`,
  );
  const wishText = wish.burden[0].text;
  assert(
    wishText.includes("**아카시아꽃 향**") &&
      /못했고, 이 특징이 \*\*아쉬움\*\*으로 남은 것 같아요\.$/.test(wishText) &&
      !/부담스러/.test(wishText),
    `wish text: ${wishText}`,
  );
  // Both finish answers with no aroma named: the echo paragraph is not the
  // length told twice but a second, different meeting with the drink (2026-11-06).
  const echo = writeCard(recordFrom("echo", [
    ...fine,
    ...quiet.filter((k) => k !== "finish:unsure"),
    "finish:pleasantLength",
    "finish:aromaEcho",
    "revisit:wantAgain",
  ], product("whisky", [])));
  equal(echo.positive.length, 1, JSON.stringify(echo.positive));
  assert(
    echo.positive[0].answer.includes("여운") &&
      echo.positive[0].answer.includes("잔향"),
    `echo name: ${echo.positive[0].answer}`,
  );
  const echoText = echo.positive[0].text;
  const echoBold = echoText.match(/\*\*[^*]+\*\*/g) ?? [];
  assert(
    new Set(echoBold).size === 3 && echoText.includes("**여운**") &&
      echoText.includes("이 두 가지 특징이"),
    `two different meetings, named once each: ${echoText}`,
  );
  // The wish before a burden keeps its own full stop; only a last body runs into the closing.
  const wishThenBurden = writeCard(recordFrom("wish+burden", [
    "notice:aroma:acacia",
    "reaction:aroma:acacia:disliked",
    "reason:aroma:acacia:disliked:too_weak",
    "reaction:taste:sweetness:fine",
    "reaction:taste:acidity:disliked",
    "reason:taste:acidity:disliked:disharmony",
    "reaction:taste:bitterness:fine",
    ...quiet,
    "revisit:unsure",
  ], product("wine", ["acacia"])));
  const joined = wishThenBurden.burden[0].text;
  assert(
    /못했어요\. .+ 이 두 가지 특징이 \*\*부담\*\*으로 다가온 것 같아요\.$/.test(
      joined,
    ) && !joined.includes("못했고"),
    joined,
  );
  // One sensation, one explanation: 단맛 that covered 쌉쌀함 is not also
  // explained as 단맛 coming before 쌉쌀함.
  const once = writeCard(recordFrom("once", [
    "aroma:unsure",
    "reaction:taste:sweetness:disliked",
    "reason:taste:sweetness:disliked:disharmony",
    "reaction:taste:bitterness:liked",
    "reason:taste:bitterness:liked:pronounced",
    "reaction:taste:acidity:fine",
    ...quiet,
    "revisit:unsure",
  ], product("korean_traditional", [])));
  equal(once.burden.length, 1, JSON.stringify(once.burden));
  assert(
    once.burden[0].answer.includes("단맛") &&
      once.burden[0].answer.includes("쌉쌀"),
    `one explanation: ${once.burden[0].answer}`,
  );
});
