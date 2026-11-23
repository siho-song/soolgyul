/**
 * The words the app redraws a re-answered section with, before the card is
 * written again (TasteCardNoteWords): the groups a section's marks stand
 * under, and 재음용 의사 by its answer. A gauge's and an aroma's words are the
 * app's own, read from the same gauge sheet and dictionary as the server's.
 */
import { CARD_ENGINE_VERSION } from "../facts/facts.ts";
import { sensoryOptions } from "../record/questionnaire.ts";
import type { TasteCardNoteWords, TasteCardView } from "../service/types.ts";
import { FELT_GROUPS, REVISIT_SAID } from "./note_words.ts";

/** The same for every card. */
const NOTE_WORDS: TasteCardNoteWords = {
  groups: FELT_GROUPS.map(([felt, label]) => ({
    felt: felt as TasteCardNoteWords["groups"][number]["felt"],
    label,
  })),
  revisit: Object.fromEntries(
    sensoryOptions().flatMap((option) =>
      option.kind === "revisit"
        ? [[option.option_key, REVISIT_SAID[option.intent]] as const]
        : []
    ),
  ),
};

/**
 * The view with the redraw words on its note. Only a card of the current
 * engine gets them: a card written under the questionnaire before cannot be
 * re-answered, and the app reads a note without words as one that cannot.
 */
export function withNoteWords(view: TasteCardView): TasteCardView {
  return view.note &&
      view.metadata.engine_version === CARD_ENGINE_VERSION
    ? { ...view, note: { ...view.note, words: NOTE_WORDS } }
    : view;
}
