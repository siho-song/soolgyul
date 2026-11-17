import { oldCardReading } from "../../_shared/taste_card/facts/old_vocabulary.ts";
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
    category: example.category ?? "wine",
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
    const reading = oldCardReading(
      recordFrom(id, example.answers, exampleProduct(example)),
    );
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

/** One answer per sensation the reading can make, on the kind whose sheet asks it. */
const SUBJECT_ANSWERS: [string, string, Example["category"]?][] = [
  ["aroma liked", "aroma:nose:cherry:liked"],
  ["aroma burden", "aroma:nose:cherry:disliked"],
  ["palate aroma liked", "aroma:palate:cherry:liked"],
  ["palate aroma burden", "aroma:palate:cherry:disliked"],
  ...["sweetness", "acidity"].flatMap((
    taste,
  ): [string, string][] => [
    [`${taste} liked high`, `level:${taste}:4:liked`],
    [`${taste} liked low`, `level:${taste}:2:liked`],
    [`${taste} liked middle`, `level:${taste}:3:liked`],
    [`${taste} too much`, `level:${taste}:5:disliked`],
    [`${taste} too weak`, `level:${taste}:1:disliked`],
    [`${taste} burden middle`, `level:${taste}:3:disliked`],
  ]),
  ...["liked", "disliked"].flatMap((
    side,
  ): [string, string, Example["category"]?][] => [
    [`light ${side}`, `level:body:2:${side}`],
    [`heavy ${side}`, `level:body:4:${side}`],
    [`smooth ${side}`, `level:tannin:2:${side}`],
    [`drying ${side}`, `level:tannin:4:${side}`],
    [`warmth ${side}`, `level:spice:4:${side}`, "whisky"],
    [`peat ${side}`, `level:peat:4:${side}`, "whisky"],
    [`finish long ${side}`, `level:finish_length:4:${side}`],
    [`finish short ${side}`, `level:finish_length:2:${side}`],
    [`finish character ${side}`, `level:finish_character:4:${side}`],
    [`finish aroma ${side}`, `aroma:finish:cherry:${side}`],
  ]),
];
const PRODUCT_STATES: [string, Partial<SensoryProduct>][] = [
  ["no data", {}],
  ...([1, 3, 5] as const).map((level): [string, Partial<SensoryProduct>] => [
    `all ${level}`,
    {
      levels: {
        sweetness: level,
        acidity: level,
        astringency: level,
        body: level,
        carbonation: level,
        alcohol_presence: level,
        finish_length: level,
      },
    },
  ]),
];

Deno.test("card findings: an aroma answer always carries what the aroma does, framed by how it was taken", () => {
  const product = exampleProduct({ answers: [] });
  const frames = (answers: string[]) =>
    findCard(oldCardReading(recordFrom(answers.join(), answers, product)))
      .filter((d) => d.thinking === "effect")
      .map((d) => `${d.row}#${d.frame}`);
  // An aroma carries no strength: liked or a burden, by the nose or in the mouth.
  const cases: [string[], string[]][] = [
    [["aroma:nose:cherry:liked"], ["effect_sour_fruit#liked"]],
    [["aroma:palate:cherry:liked"], ["effect_sour_fruit#liked"]],
    [["aroma:nose:cherry:disliked"], ["effect_sour_fruit#burden"]],
    [["aroma:palate:cherry:disliked"], ["effect_sour_fruit#burden"]],
    // Named by the nose and in the mouth: one answer, one explanation.
    [["aroma:nose:cherry:liked", "aroma:palate:cherry:liked"], [
      "effect_sour_fruit#liked",
    ]],
    // What stayed after swallowing is the finish's to explain.
    [["aroma:finish:cherry:liked"], []],
  ];
  for (const [answers, expected] of cases) {
    const got = frames(answers);
    if (JSON.stringify(got) !== JSON.stringify(expected)) {
      throw new Error(`${answers}: got ${got}, expected ${expected}`);
    }
  }
});

Deno.test("card findings: every answered sensation gets at least one finding in every product state", () => {
  const empty: string[] = [];
  for (const [label, answer, category] of SUBJECT_ANSWERS) {
    for (const [state, overrides] of PRODUCT_STATES) {
      const product = {
        ...exampleProduct({
          answers: [],
          category,
          style: category ? "single_malt_whisky" : "red_wine",
        }),
        ...overrides,
      };
      const reading = oldCardReading(recordFrom(label, [answer], product));
      if (reading.reactions.length === 0) {
        throw new Error(`${label}: the answer reads to no reaction`);
      }
      if (findCard(reading).length === 0) empty.push(`${label} / ${state}`);
    }
  }
  if (empty.length) throw new Error(`no finding for:\n${empty.join("\n")}`);
});

Deno.test("card findings: what stayed after swallowing speaks with the aromas that stayed, as a burden or as liked", () => {
  const product = exampleProduct({ answers: [], style: "red_wine" });
  const persistence = (answers: string[]) => {
    const reading = oldCardReading(
      recordFrom(answers.join(), answers, product),
    );
    const findings = findCard(reading).filter((f) =>
      f.thinking === "persistence"
    );
    return { reading, findings };
  };
  for (
    const [answers, row, frame] of [
      [["aroma:finish:cherry:liked"], "persistence_aroma_echo", "liked"],
      [["aroma:finish:oak:disliked"], "persistence_off_flavor", "burden"],
      [["level:finish_length:2:liked"], "persistence_clean", "liked"],
      [["level:finish_character:4:liked"], "persistence_character", "liked"],
      [
        ["level:finish_character:2:disliked"],
        "persistence_character",
        "burden",
      ],
    ] as const
  ) {
    const { findings } = persistence([...answers]);
    if (!findings.some((f) => f.row === row && f.frame === frame)) {
      throw new Error(
        `${answers}: expected ${row}#${frame}, got ${
          findings.map((f) => `${f.row}#${f.frame}`)
        }`,
      );
    }
  }
  // 잔향 and 잡내 are tied to the finish aromas themselves: the finding
  // stands on the aroma that stayed and on the finish answer it makes.
  for (
    const [answers, row] of [
      [
        ["aroma:finish:cherry:liked", "aroma:finish:vanilla:liked"],
        "persistence_aroma_echo",
      ],
      [
        ["aroma:finish:oak:disliked", "aroma:finish:smoke:disliked"],
        "persistence_off_flavor",
      ],
    ] as const
  ) {
    const { reading, findings } = persistence([...answers]);
    const hit = findings.find((f) => f.row === row);
    const subjects = (hit?.reactions ?? []).map((id) => {
      const r = reading.reactions.find((r) => r.id === id)!;
      return `${r.subject.domain}/${r.phase}`;
    }).sort();
    if (
      JSON.stringify(subjects) !==
        JSON.stringify(["aroma/finish", "aroma/finish", "finish/finish"])
    ) {
      throw new Error(`${row}: stands on ${subjects}`);
    }
  }
  // The same aroma while drinking keeps its own explanation beside it.
  const both = findCard(
    oldCardReading(
      recordFrom("both", [
        "aroma:nose:cherry:liked",
        "aroma:finish:cherry:liked",
      ], product),
    ),
  ).map((f) => f.row);
  if (
    !both.includes("effect_sour_fruit") ||
    !both.includes("persistence_aroma_echo")
  ) throw new Error(`drinking and finish: ${both}`);
  // The length of the finish is read as a strength: too long or too brief.
  for (
    const [answer, frame] of [
      ["level:finish_length:5:disliked", "lingering"],
      ["level:finish_length:1:disliked", "too_brief"],
    ] as const
  ) {
    const found = findCard(
      oldCardReading(recordFrom(answer, [answer], product)),
    );
    if (
      !found.some((f) =>
        f.row === "intensity_persistence" && f.frame.startsWith(frame)
      )
    ) {
      throw new Error(`${answer}: ${found.map((f) => `${f.row}#${f.frame}`)}`);
    }
  }
});
