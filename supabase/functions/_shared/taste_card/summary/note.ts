/**
 * 테이스팅 노트: one record laid out as a tasting sheet of its kind of drink
 * (the card's second tab). It holds only what the reader answered and what
 * the catalog states of the bottle: an aroma is listed under the picker it
 * was named in, a gauge is shown at the step the reader set in the sheet's
 * own word, a 맛 밸런스 or 여운 밸런스 mark is the level the catalog read for
 * this bottle (never the kind's usual one), and a section nobody answered
 * stays empty.
 */
import { senseChoiceByKey } from "../../record_reading/dictionary/aromas.ts";
import {
  grapeByKey,
  ingredientByKey,
  regionByKey,
  type Term,
  termByKey,
} from "../../record_reading/dictionary/dictionary.ts";
import {
  type AromaStage,
  GAUGE_LEVEL_DIMENSION,
  type LevelDimension,
} from "../../record_reading/facts/facts.ts";
import type { BottleFacts } from "../../record_reading/bottle.ts";
import type { RecordReading } from "../../record_reading/read_record.ts";
import {
  type GaugeRow,
  gaugeSheet,
} from "../../record_reading/record/questionnaire.ts";
import type {
  SensoryGauge,
  SensoryRecord,
} from "../../record_reading/record/sensory_record.ts";
import type {
  RecordLook,
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
  COLOR_CHOICES,
  COLOR_GROUP,
  COLOR_PROMPT,
  FACT_LABEL,
  FELT_GROUPS,
  REVISIT_SAID,
  SERVING,
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

/** The kind of sheet the head rows and the serving slot are laid out by. */
type Sheet = "wine" | "sparkling" | "whisky" | "sake" | "brewed" | "distilled";

/** A cask every whisky has says nothing on a sheet. */
const PLAIN_VESSELS = new Set(["wooden_cask"]);

export function writeNote(
  record: SensoryRecord,
  reading: RecordReading,
  bottle: NoteBottle,
): TasteCardNote {
  const sheet = sheetOf(record);
  const gauges = gaugeSheet(record.product.category, record.product.styleKey);
  return {
    original_name: originalName(record, bottle),
    facts: bottleRows(record, bottle, sheet),
    nose: grouped(aromaMarks(record, "nose")),
    balance: balance(record, reading.bottle, gauges.palate),
    flavor: grouped(aromaMarks(record, "palate")),
    // 질감 is no section of its own since 2026-11-16: the mouthfeel gauges
    // are rows of 맛 밸런스. A card stored before keeps what it has.
    texture: [],
    finish_balance: balance(record, reading.bottle, gauges.finish),
    finish: grouped(aromaMarks(record, "finish")),
    revisit: REVISIT_SAID[reading.answers.revisit] ?? null,
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

/**
 * [look] as far as [note] offers it: a colour or texture is kept only when
 * it is one of the choices the note holds for its kind of drink. What a
 * caller sends beyond them, or for a kind that notes no look, is dropped;
 * the card is written all the same.
 */
export function lookOffered(
  note: TasteCardNote,
  look: RecordLook | undefined,
): RecordLook {
  const offered: RecordLook = {};
  for (const group of note.appearance?.groups ?? []) {
    const chosen = look?.[group.key];
    if (
      chosen !== undefined &&
      group.options.some((option) => option.key === chosen)
    ) {
      offered[group.key] = chosen;
    }
  }
  return offered;
}

/**
 * [note] with the look the record's note holds marked on its groups, each
 * as the group's `chosen`: what the app draws for a reader who cannot read
 * the record's note itself (a visitor's card, a card just claimed). A look
 * the note's groups do not offer marks nothing.
 */
export function withLookChosen(
  note: TasteCardNote,
  look: RecordLook,
): TasteCardNote {
  const held = lookOffered(note, look);
  if (!note.appearance || Object.keys(held).length === 0) return note;
  return {
    ...note,
    appearance: {
      ...note.appearance,
      groups: note.appearance.groups.map((group) => {
        const chosen = held[group.key];
        return chosen === undefined ? group : { ...group, chosen };
      }),
    },
  };
}

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
  /** The names the dictionary has for the keys, each once. */
  const names = (
    keys: readonly string[],
    byKey: (key: string) => Term | null,
  ) =>
    [...new Set(keys)]
      .map((key) => byKey(key)?.names.ko)
      .filter((name): name is string => !!name)
      .join(" · ");
  // A blend with a grape the dictionary cannot name is not listed short.
  const grapes = bottle.grape_keys.every((key) => grapeByKey(key))
    ? names(bottle.grape_keys, grapeByKey)
    : null;
  const ingredients = names(
    bottle.ingredient_keys.filter((key) => product.ingredients?.includes(key)),
    ingredientByKey,
  );
  const processes = product.processes ?? [];
  const casks = names(
    processes.filter((key) => !PLAIN_VESSELS.has(key)),
    (key) => termByKey("maturation", key),
  );
  const distilling = names(
    processes.filter((key) =>
      termByKey("process", key)?.parent === "distillation"
    ),
    (key) => termByKey("process", key),
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
  return regionByKey(key)?.names.ko ?? null;
}

/* ------------------------------------------------- aromas and gauges */

/** The aromas picked in one picker, by how each was taken. */
function aromaMarks(
  record: SensoryRecord,
  stage: AromaStage,
): TasteCardNoteMark[] {
  return record.aromas.flatMap((aroma) => {
    const choice = aroma.stage === stage ? senseChoiceByKey(aroma.key) : null;
    return choice
      ? [{
        label: choice.label,
        felt: aroma.reaction === "liked" ? "liked" as const : "burden" as const,
      }]
      : [];
  });
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

/**
 * How a gauge was taken, in the reading of the 핵심 요약 tags: minded at a
 * high step is less of it, at a low step more. 끝맛의 인상 is no strength, so
 * minded is only that.
 */
function feltOf(gauge: SensoryGauge): TasteCardNoteFelt {
  if (gauge.reaction === "liked") return "liked";
  if (gauge.axis === "finish_character" || gauge.level === 3) return "burden";
  return gauge.level > 3 ? "less" : "more";
}

/**
 * 맛 밸런스 and 여운 밸런스: the gauges of one step of the drink's sheet. A row
 * shows where the reader set the gauge or the catalog read the level for the
 * bottle; a gauge with neither has no row.
 */
function balance(
  record: SensoryRecord,
  bottle: BottleFacts,
  rows: readonly GaugeRow[],
): TasteCardNoteGauge[] {
  const { category } = record.product;
  const words = category === "wine"
    ? WINE_LEVEL_WORDS
    : category === "korean_traditional"
    ? TRADITIONAL_LEVEL_WORDS
    : {};
  return rows.flatMap((row) => {
    const gauge = record.gauges.find((g) => g.axis === row.axis);
    const dimension = GAUGE_LEVEL_DIMENSION[row.axis];
    const mark = dimension ? readLevel(bottle, dimension, category) : null;
    if (!gauge && mark === null) return [];
    return [{
      key: row.axis,
      label: row.label,
      mark,
      word: mark === null || !dimension
        ? null
        : words[dimension]?.[mark - 1] ?? null,
      felt: gauge ? feltOf(gauge) : null,
      said: gauge ? row.terms[gauge.level - 1] : null,
      ...(gauge ? { level: gauge.level } : {}),
      ...(row.ends ? { ends: [row.ends[0], row.ends[1]] } : {}),
    }];
  });
}

/**
 * The level the catalog read for this bottle. The kind's usual level copied
 * into a bottle is no reading; a whisky's 단맛 number is one the sources
 * disagree about, so no sheet marks it.
 */
function readLevel(
  bottle: BottleFacts,
  dimension: LevelDimension,
  category: string | null,
): number | null {
  if (category === "whisky" && dimension === "sweetness") return null;
  const read = bottle.levels[dimension];
  return read?.of === "bottle" ? read.level : null;
}
