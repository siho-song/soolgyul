import { readCard } from "../../_shared/taste_card/facts/reading.ts";
import { findCard } from "../../_shared/taste_card/findings/findings.ts";
import {
  type Example,
  KNOWLEDGE_ROWS,
} from "../../_shared/taste_card/findings/knowledge.ts";
import type { SensoryProduct } from "../../_shared/taste_card/record/sensory_record.ts";
import { recordFrom } from "../helpers/card_fixture_record.ts";

function exampleProduct(example: Example): SensoryProduct {
  return {
    name: "example",
    category: "wine",
    styleKey: example.style ?? null,
    abv: null,
    levels: example.levels ?? {},
    levelRefs: {},
    descriptors: [
      ...(example.aromas ?? []).map((key) => ({
        key,
        label: key,
        section: "aroma" as const,
        family: "test",
        traits: [],
        description: null,
        evidenceRefs: ["test"],
      })),
      ...(example.texture?.length
        ? [{
          key: "soft_texture",
          label: "질감",
          section: "texture" as const,
          family: "test",
          traits: [...example.texture],
          description: null,
          evidenceRefs: ["test"],
        }]
        : []),
    ],
  };
}

Deno.test("card findings: every knowledge row fires on its own example", () => {
  const silent: string[] = [];
  for (const [id, entry] of Object.entries(KNOWLEDGE_ROWS)) {
    const example = entry.example as Example;
    const answers = [...example.answers];
    if (!answers.some((key) => key.startsWith("revisit:"))) {
      answers.push("revisit:unsure");
    }
    const reading = readCard(recordFrom(id, answers, exampleProduct(example)));
    const findings = findCard(reading);
    if (!findings.some((finding) => finding.row === id)) {
      silent.push(
        `${id} (fired: ${findings.map((f) => f.row).join(", ") || "nothing"})`,
      );
    }
  }
  if (silent.length) {
    throw new Error(
      `rows whose example does not fire them:\n${silent.join("\n")}`,
    );
  }
});

const SUBJECT_ANSWERS: [string, string[]][] = [
  ["aroma liked", [
    "notice:aroma:cherry",
    "reaction:aroma:cherry:liked",
    "reason:aroma:cherry:liked:pronounced",
  ]],
  ["aroma burden", [
    "notice:aroma:cherry",
    "reaction:aroma:cherry:disliked",
    "reason:aroma:cherry:disliked:too_strong",
  ]],
  ["aroma masks", [
    "notice:aroma:cherry",
    "reaction:aroma:cherry:disliked",
    "reason:aroma:cherry:disliked:disharmony",
  ]],
  ...["sweetness", "acidity", "bitterness"].flatMap((
    taste,
  ): [string, string[]][] => [
    [`${taste} liked`, [`reaction:taste:${taste}:liked`]],
    [`${taste} too weak`, [
      `reaction:taste:${taste}:disliked`,
      `reason:taste:${taste}:disliked:too_weak`,
    ]],
    [`${taste} masks`, [
      `reaction:taste:${taste}:disliked`,
      `reason:taste:${taste}:disliked:disharmony`,
    ]],
    [`${taste} burden`, [
      `reaction:taste:${taste}:disliked`,
      `reason:taste:${taste}:disliked:unspecified`,
    ]],
  ]),
  ...["light", "heavy", "smooth", "drying", "bubbles", "warmth"].flatMap((
    key,
  ): [string, string[]][] => [
    [`${key} liked`, [
      `notice:mouthfeel:${key}`,
      `reaction:mouthfeel:${key}:liked`,
    ]],
    [`${key} burden`, [
      `notice:mouthfeel:${key}`,
      `reaction:mouthfeel:${key}:disliked`,
    ]],
  ]),
  ...["pleasantLength", "clean", "tooShort", "heavy", "aromaEcho", "offFlavor"]
    .map((key): [string, string[]] => [`finish ${key}`, [`finish:${key}`]]),
];
const PRODUCT_STATES: [string, Partial<SensoryProduct>][] = [
  ["no data", {}],
  ["all low", {
    levels: {
      sweetness: 1,
      acidity: 1,
      astringency: 1,
      body: 1,
      carbonation: 1,
      alcohol_presence: 1,
    },
  }],
  ["all mid", {
    levels: {
      sweetness: 3,
      acidity: 3,
      astringency: 3,
      body: 3,
      carbonation: 3,
      alcohol_presence: 3,
    },
  }],
  ["all high", {
    levels: {
      sweetness: 5,
      acidity: 5,
      astringency: 5,
      body: 5,
      carbonation: 5,
      alcohol_presence: 5,
    },
  }],
  ["style only", { styleKey: "junmai" }],
];

Deno.test("card findings: an aroma answer always carries what the aroma does, with the reader's reason as its frame", () => {
  const product = exampleProduct({ answers: [] });
  const frames = (answers: string[]) =>
    findCard(
      readCard(
        recordFrom(answers.join(), [...answers, "revisit:unsure"], product),
      ),
    )
      .filter((d) => d.thinking === "effect")
      .map((d) => `${d.row}#${d.frame}`);
  const cherry = ["notice:aroma:cherry"];
  const liked = [...cherry, "reaction:aroma:cherry:liked"];
  const disliked = [...cherry, "reaction:aroma:cherry:disliked"];
  const cases: [string[], string[]][] = [
    [liked, ["effect_sour_fruit#liked"]],
    [[...liked, "reason:aroma:cherry:liked:pronounced"], [
      "effect_sour_fruit#liked",
    ]],
    [[...liked, "reason:aroma:cherry:liked:gentle"], [
      "effect_sour_fruit#gentle",
    ]],
    [disliked, ["effect_sour_fruit#burden"]],
    [[...disliked, "reason:aroma:cherry:disliked:too_strong"], [
      "effect_sour_fruit#excessive",
    ]],
    [[...disliked, "reason:aroma:cherry:disliked:too_weak"], [
      "effect_sour_fruit#too_weak",
    ]],
    // 가렸어요 goes to the masking thinking, not to the aroma's effect.
    [[...disliked, "reason:aroma:cherry:disliked:disharmony"], []],
  ];
  for (const [answers, expected] of cases) {
    const got = frames(answers);
    if (JSON.stringify(got) !== JSON.stringify(expected)) {
      throw new Error(`${answers.at(-1)}: got ${got}, expected ${expected}`);
    }
  }
});

Deno.test("card findings: every answered sensation gets at least one finding in every product state", () => {
  const empty: string[] = [];
  for (const [label, answers] of SUBJECT_ANSWERS) {
    for (const [state, overrides] of PRODUCT_STATES) {
      const product = { ...exampleProduct({ answers: [] }), ...overrides };
      const findings = findCard(
        readCard(recordFrom(label, [...answers, "revisit:unsure"], product)),
      );
      if (findings.length === 0) empty.push(`${label} / ${state}`);
    }
  }
  if (empty.length) throw new Error(`no finding for:\n${empty.join("\n")}`);
});

Deno.test("card findings: a lingering finish speaks on its own, as a burden or as liked", () => {
  for (
    const [key, frame] of [
      ["heavy", "burden_alone"],
      ["offFlavor", "burden_alone"],
      ["aromaEcho", "liked"],
    ] as const
  ) {
    const findings = findCard(
      readCard(
        recordFrom(
          key,
          [`finish:${key}`, "revisit:unsure"],
          exampleProduct({ answers: [] }),
        ),
      ),
    );
    if (
      !findings.some((f) => f.thinking === "persistence" && f.frame === frame)
    ) {
      throw new Error(
        `${key}: expected a persistence finding framed ${frame}, got ${
          findings.map((f) => `${f.row}#${f.frame}`)
        }`,
      );
    }
  }
  // 텁텁함 pairs with the same mouthfeel minded while drinking; 잡내 and 잔향
  // pair with the aromas minded or liked while drinking (2026-11-06).
  for (
    const [key, answers, frame] of [
      ["heavy", [
        "notice:mouthfeel:heavy",
        "reaction:mouthfeel:heavy:disliked",
      ], "burden_after_burden"],
      ["offFlavor", [
        "notice:aroma:oak",
        "reaction:aroma:oak:disliked",
      ], "burden_after_burden"],
      ["aromaEcho", [
        "notice:aroma:cherry",
        "reaction:aroma:cherry:liked",
      ], "liked"],
    ] as const
  ) {
    const withAnswer = findCard(
      readCard(
        recordFrom(key, [
          `finish:${key}`,
          ...answers,
          "revisit:unsure",
        ], exampleProduct({ answers: [] })),
      ),
    );
    const hit = withAnswer.find((f) =>
      f.thinking === "persistence" && f.frame === frame
    );
    if (!hit || hit.reactions.length !== 2) {
      throw new Error(
        `${key}: the drinking answer should pair with the lingering finish`,
      );
    }
  }
});
