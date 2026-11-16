/**
 * 테이스팅 노트: one record laid out as a tasting sheet of its kind of drink
 * (the card's second tab). It holds only what the reader answered and what
 * the catalog states of the bottle: an aroma is listed as it was named, a
 * 맛 밸런스 mark is the level the catalog read for this bottle (never the
 * kind's usual one), and a section nobody answered stays empty.
 */
import {
  regionByKey,
  serviceVocabulary as vocabulary,
  terms,
} from "../dictionary/dictionary.ts";
import type { CardFacts, ReactionFact } from "../facts/facts.ts";
import { MOUTHFEEL_SUBJECTS } from "../facts/reading.ts";
import type { SensoryRecord } from "../record/sensory_record.ts";
import type {
  TasteCardNote,
  TasteCardNoteFelt,
  TasteCardNoteGauge,
  TasteCardNoteGroup,
  TasteCardNoteMark,
} from "../service/types.ts";
import { TRADITIONAL_LEVEL_WORDS, WINE_LEVEL_WORDS } from "./guide_words.ts";
import {
  AGE_VALUE,
  APPEARANCE_LABEL,
  BALANCE_ROWS,
  COLOR_CHOICES,
  COLOR_GROUP,
  COLOR_PROMPT,
  FACT_LABEL,
  FELT_GROUPS,
  FINISH_LABEL,
  REVISIT_SAID,
  SERVING,
  TASTE_SAID,
  TEXTURE_LABEL,
  TURBIDITY_CHOICES,
  TURBIDITY_GROUP,
  TURBIDITY_PROMPT,
  VISCOSITY_CHOICES,
  VISCOSITY_GROUP,
  VISCOSITY_PROMPT,
} from "./note_words.ts";

/** What the catalog states of the bottle beyond the record's product. */
export type NoteBottle = {
  /** 레드 와인, 준마이 긴조. */
  style_label: string | null;
  /** The name in its own language, as the catalog holds it. */
  name_en: string | null;
  producer: string | null;
  region_key: string | null;
  vintage_year: number | null;
  age_years: number | null;
  /** The grapes and the ingredients in the catalog's own order, the main one first. */
  grape_keys: readonly string[];
  ingredient_keys: readonly string[];
};

type Sheet = keyof typeof BALANCE_ROWS;

const AROMA_GROUPS = new Map(
  vocabulary.groups.map((
    group,
  ) => [group.key, group as { label_ko: string; category_key?: string }]),
);
const NAME_OF = new Map(
  terms("grape", "ingredient", "process", "maturation").map((
    term,
  ) => [`${term.type}:${term.key}`, term]),
);
/** A cask every whisky has says nothing on a sheet. */
const PLAIN_VESSELS = new Set(["wooden_cask"]);

export function writeNote(
  record: SensoryRecord,
  facts: CardFacts,
  bottle: NoteBottle,
): TasteCardNote {
  const sheet = sheetOf(record);
  return {
    original_name: originalName(record, bottle),
    facts: bottleRows(record, bottle, sheet),
    nose: nose(record, facts),
    balance: balance(facts, sheet, record.product),
    texture: grouped(textureMarks(record, facts)),
    finish: grouped(finishMarks(facts)),
    revisit: REVISIT_SAID[facts.record.revisit] ?? null,
    appearance: appearance(record),
    serving: serving(sheet),
  };
}

/** The catalog's own-language name, where it is not the name already shown. */
function originalName(
  record: SensoryRecord,
  bottle: NoteBottle,
): string | null {
  const name = bottle.name_en?.trim();
  return name && name !== record.product.name ? name : null;
}

function sheetOf(record: SensoryRecord): Sheet {
  const { category, styleKey } = record.product;
  if (category === "wine") {
    return styleKey?.includes("sparkling") ? "sparkling" : "wine";
  }
  if (category === "whisky") return "whisky";
  if (category === "sake") return "sake";
  return styleKey?.endsWith("_soju") ? "distilled" : "brewed";
}

/* ------------------------------------------- what the member fills in */

/** The look a member may note, for the kinds a sheet asks it of. */
function appearance(record: SensoryRecord): TasteCardNote["appearance"] {
  const { category, styleKey } = record.product;
  type Group = NonNullable<TasteCardNote["appearance"]>["groups"][number];
  const state = (
    label: string,
    prompt: string,
    choices: readonly (readonly [string, string, string])[],
  ): Group => ({
    key: "appearance_texture",
    label,
    prompt,
    options: choices.map(([key, name, icon]) => ({ key, label: name, icon })),
  });
  if (styleKey === "takju") {
    return {
      label: APPEARANCE_LABEL,
      groups: [state(TURBIDITY_GROUP, TURBIDITY_PROMPT, TURBIDITY_CHOICES)],
    };
  }
  if (category !== "wine" && category !== "whisky") return null;
  // A sparkling wine is read on the white palette.
  const colors = COLOR_CHOICES[
    category === "whisky"
      ? "whisky"
      : styleKey === "sparkling_wine"
      ? "white_wine"
      : styleKey ?? ""
  ];
  return {
    label: APPEARANCE_LABEL,
    groups: [
      ...(colors
        ? [{
          key: "appearance" as const,
          label: COLOR_GROUP,
          prompt: COLOR_PROMPT,
          options: colors.map(([key, name, swatch]) => ({
            key,
            label: name,
            swatch,
          })),
        }]
        : []),
      state(VISCOSITY_GROUP, VISCOSITY_PROMPT, VISCOSITY_CHOICES),
    ],
  };
}

function serving(sheet: Sheet): TasteCardNote["serving"] {
  const slot = SERVING[sheet];
  return slot
    ? {
      label: slot.label,
      prompt: slot.prompt,
      options: slot.choices.map(([key, label, short]) => ({
        key,
        label,
        ...(short === label ? {} : { short }),
      })),
    }
    : null;
}

/* ----------------------------------------------------------- the head */

function bottleRows(
  record: SensoryRecord,
  bottle: NoteBottle,
  sheet: Sheet,
): { label: string; value: string }[] {
  const { product } = record;
  const names = (type: string, keys: readonly string[] = []) =>
    [...new Set(keys)]
      .map((key) => NAME_OF.get(`${type}:${key}`)?.names.ko)
      .filter((name): name is string => !!name)
      .join(" · ");
  // A blend with a grape the dictionary cannot name is not listed short.
  const grapes = bottle.grape_keys.every((key) => NAME_OF.has(`grape:${key}`))
    ? names("grape", bottle.grape_keys)
    : null;
  const ingredients = names(
    "ingredient",
    bottle.ingredient_keys.filter((key) => product.ingredients?.includes(key)),
  );
  const processes = product.processes ?? [];
  const casks = names(
    "maturation",
    processes.filter((key) => !PLAIN_VESSELS.has(key)),
  );
  const distilling = names(
    "process",
    processes.filter((key) =>
      NAME_OF.get(`process:${key}`)?.parent === "distillation"
    ),
  );
  const rows: [string, string | null][] = [
    [FACT_LABEL.producer, bottle.producer],
  ];
  if (sheet === "wine" || sheet === "sparkling") {
    rows.push(
      [FACT_LABEL.grape, grapes],
      [FACT_LABEL.region, regionName(bottle.region_key)],
      [
        FACT_LABEL.vintage,
        bottle.vintage_year ? `${bottle.vintage_year}` : null,
      ],
    );
  } else if (sheet === "whisky") {
    rows.push(
      [FACT_LABEL.region, regionName(bottle.region_key)],
      [FACT_LABEL.age, bottle.age_years ? age(bottle.age_years) : null],
      [FACT_LABEL.cask, casks],
    );
  } else if (sheet === "sake") {
    rows.push([FACT_LABEL.region, regionName(bottle.region_key)]);
  } else {
    rows.push(
      [FACT_LABEL.region, regionName(bottle.region_key)],
      [FACT_LABEL.ingredient, ingredients],
    );
    if (sheet === "distilled") {
      rows.push([
        FACT_LABEL.making,
        [distilling, casks].filter(Boolean).join(" · "),
      ]);
    }
  }
  return rows.flatMap(([label, value]) => value ? [{ label, value }] : []);
}

const age = (years: number) => AGE_VALUE.replace("{N}", `${years}`);

/** 마고: the narrowest place the catalog names, without the country over it. */
function regionName(key: string | null): string | null {
  return (key ? regionByKey.get(key)?.names.ko : undefined) ?? null;
}

/* ----------------------------------------------------------- the nose */

/** Every aroma the reader named, by how it was taken. */
function nose(
  record: SensoryRecord,
  facts: CardFacts,
): TasteCardNote["nose"] {
  const marks: TasteCardNoteMark[] = [];
  for (const answer of record.answers) {
    if (answer.domain !== "aroma" || !answer.key.startsWith("aroma.")) continue;
    const key = answer.key.slice(6);
    const group = AROMA_GROUPS.get(key);
    if (!group) continue;
    const reaction = facts.reactions.find((r) =>
      r.subject.domain === "aroma" && r.subject.key === key
    );
    marks.push({
      label: group.label_ko,
      felt: reaction ? feltOf(reaction) : "liked",
    });
  }
  return grouped(marks);
}

/** The marks of a section under 마음에 들었어요 and 부담됐어요. */
function grouped(marks: readonly TasteCardNoteMark[]): TasteCardNoteGroup[] {
  const side = (felt: TasteCardNoteFelt) =>
    felt === "less" || felt === "more" || felt === "burden" ? "missed" : felt;
  return FELT_GROUPS.flatMap(([key, label]) => {
    const own = marks.filter((mark) => side(mark.felt) === key);
    return own.length ? [{ label, marks: own }] : [];
  });
}

/** What stayed after swallowing, each as a line of the sheet. */
export function finishMarks(facts: CardFacts): TasteCardNoteMark[] {
  return facts.reactions
    .filter((r) => r.phase === "finish")
    .flatMap((r) => mark(FINISH_LABEL[`${r.subject.key}:${r.reaction}`], r));
}

/** What the mouth felt while drinking, in the record's order. */
export function textureMarks(
  record: SensoryRecord,
  facts: CardFacts,
): TasteCardNoteMark[] {
  return record.answers.flatMap((answer) => {
    const subject = MOUTHFEEL_SUBJECTS[answer.key];
    const label = subject && TEXTURE_LABEL[subject.key];
    if (!label) return [];
    const reaction = facts.reactions.find((r) =>
      r.subject.domain === "mouthfeel" && r.subject.key === subject.key &&
      r.phase === "drinking"
    );
    return [{ label, felt: reaction ? feltOf(reaction) : "liked" }];
  });
}

/* --------------------------------------------------------- the palate */

function balance(
  facts: CardFacts,
  sheet: Sheet,
  { category, styleKey }: SensoryRecord["product"],
): TasteCardNoteGauge[] {
  const words = sheet === "wine" || sheet === "sparkling"
    ? WINE_LEVEL_WORDS
    : category === "korean_traditional"
    ? TRADITIONAL_LEVEL_WORDS
    : {};
  const rows: TasteCardNoteGauge[] = [];
  for (const [axis, label] of BALANCE_ROWS[sheet]) {
    const said = tasteSaid(facts, axis);
    const level = shown(sheet, axis, styleKey)
      ? readLevel(facts, axis, category)
      : null;
    if (!said && level === null) continue;
    rows.push({
      key: axis,
      label,
      mark: level,
      word: level === null ? null : words[axis]?.[level - 1] ?? null,
      felt: said?.felt ?? null,
      said: said?.said ?? null,
    });
  }
  return rows;
}

/** What the reader said of one taste: how it was taken, and in which words. */
export function tasteSaid(
  facts: CardFacts,
  axis: string,
): { felt: TasteCardNoteFelt; said: string | null } | null {
  const said = facts.reactions.find((r) =>
    r.subject.domain === "taste" && r.subject.key === axis &&
    r.phase === "drinking"
  );
  if (!said) return null;
  return {
    felt: feltOf(said),
    said: TASTE_SAID[`${said.reaction}:${said.qualifier}`] ??
      TASTE_SAID[said.reaction] ?? null,
  };
}

/** A white or rosé sheet has no 타닌 row. */
const NO_TANNIN = new Set(["white_wine", "rose_wine"]);

/** Whether the bottle's level on the axis belongs on its sheet. */
function shown(sheet: Sheet, axis: string, styleKey: string | null): boolean {
  return !(sheet === "wine" && axis === "astringency" &&
    NO_TANNIN.has(styleKey ?? ""));
}

/**
 * The level the catalog read for this bottle. The kind's usual level copied
 * into a bottle is no reading; a whisky's 단맛 number is one the sources
 * disagree about, so no sheet marks it.
 */
function readLevel(
  facts: CardFacts,
  axis: string,
  category: string | null,
): number | null {
  if (category === "whisky" && axis === "sweetness") return null;
  for (const { fact } of facts.product_facts) {
    if (fact.type === "level" && fact.dimension === axis && !fact.estimated) {
      // A still sake's 탄산 1 says nothing; the row is for one that fizzes.
      return category === "sake" && axis === "carbonation" && fact.level < 2
        ? null
        : fact.level;
    }
  }
  return null;
}

/* -------------------------------------------------------------- marks */

function mark(
  label: string | undefined,
  reaction: ReactionFact,
): TasteCardNoteMark[] {
  return label ? [{ label, felt: feltOf(reaction) }] : [];
}

/**
 * The same reading as the 핵심 요약 tags: too much is less, too little more.
 * A thing was liked or it was not: a thing only named reads as liked.
 */
function feltOf(r: ReactionFact): TasteCardNoteFelt {
  if (r.reaction === "liked" || r.reaction === "unstated") return "liked";
  if (r.qualifier === "too_weak" || r.qualifier === "too_brief") return "more";
  return r.subject.domain === "mouthfeel" || r.qualifier === "excessive" ||
      r.qualifier === "lingering"
    ? "less"
    : "burden";
}
