/**
 * The words the app redraws a re-answered section with, before the card is
 * written again (TasteCardNoteWords). Each answer is read alone by the
 * note's own functions, so the redraw says what the new card will say.
 */
import { MOUTHFEEL_SUBJECTS } from "../facts/reading.ts";
import { buildCardFacts } from "../findings/conclusions.ts";
import { sensoryOptions } from "../record/questionnaire.ts";
import { buildSensoryRecord } from "../record/record_builder.ts";
import type { SensoryProduct } from "../record/sensory_record.ts";
import type { TasteCardNoteWords, TasteCardView } from "../service/types.ts";
import { finishMarks, tasteSaid, textureMarks } from "./note.ts";
import { FELT_GROUPS, REVISIT_SAID } from "./note_words.ts";

/** No answer's words depend on the drink. */
const ANY_DRINK: SensoryProduct = {
  name: "",
  category: null,
  styleKey: null,
  region: null,
  abv: null,
  ingredients: [],
  grapeVarietyKeys: [],
  processes: [],
  levels: {},
  levelRefs: {},
  descriptors: [],
};

let words: TasteCardNoteWords | undefined;

/** The same for every card: read once. */
export function noteWords(): TasteCardNoteWords {
  return words ??= readWords();
}

/** The view with the redraw words on its note; a card without a note is as it was. */
export function withNoteWords(view: TasteCardView): TasteCardView {
  return view.note
    ? { ...view, note: { ...view.note, words: noteWords() } }
    : view;
}

function readWords(): TasteCardNoteWords {
  const options = sensoryOptions();
  const question = new Map(options.map((o) => [o.option_key, o.question_key]));
  /** The record of someone who chose only these answers. */
  const read = (...ids: string[]) => {
    const record = buildSensoryRecord(
      "note-words",
      ids.filter((id) => question.has(id)).map((id) => ({
        question_key: question.get(id)!,
        selected_option_keys: [id],
        free_text: null,
      })),
      ANY_DRINK,
    );
    return { record, facts: buildCardFacts(record) };
  };
  const finish: string[] = [];
  const noticed: string[] = [];
  const out: TasteCardNoteWords = {
    groups: FELT_GROUPS.map(([felt, label]) => ({
      felt: felt as TasteCardNoteWords["groups"][number]["felt"],
      label,
    })),
    marks: {},
    order: [],
    taste: {},
    revisit: {},
  };
  for (const { option_key: id, section, kind, subject, side } of options) {
    if (section === "mouthfeel" && (kind === "notice" || kind === "reaction")) {
      const { record, facts } = read(`notice:mouthfeel:${subject}`, id);
      const mark = textureMarks(record, facts)[0];
      if (mark) out.marks[id] = mark;
      if (mark && kind === "notice") noticed.push(id);
    } else if (section === "finish") {
      const mark = finishMarks(read(id).facts)[0];
      if (mark) out.marks[id] = mark;
      if (mark) finish.push(id);
    } else if (
      section === "taste" && (kind === "reaction" || kind === "reason")
    ) {
      // A reason is read with the reaction it explains.
      const { facts } = read(`reaction:taste:${subject}:${side}`, id);
      const said = subject ? tasteSaid(facts, subject) : null;
      if (said?.said) out.taste[id] = { felt: said.felt, said: said.said };
    } else if (section === "revisit") {
      const said = REVISIT_SAID[read(id).facts.record.revisit];
      if (said) out.revisit[id] = said;
    }
  }
  // Someone who chose every one of them: the order their marks come in.
  const sensations = read(...noticed).record.answers.flatMap((answer) => {
    const subject = MOUTHFEEL_SUBJECTS[answer.key];
    return subject ? [`notice:mouthfeel:${subject.key}`] : [];
  });
  const lingering = finishMarks(read(...finish).facts).flatMap((mark) =>
    finish.filter((id) => out.marks[id].label === mark.label)
  );
  out.order = [...sensations, ...lingering];
  return out;
}
