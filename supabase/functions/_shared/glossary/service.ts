import { SoolgyulHttpError } from "../http.ts";
import { type Term, terms } from "../taste_card/dictionary/dictionary.ts";
import { styleKindLabel } from "../taste_card/writing/terms.ts";
import { type GlossaryTerm, glossaryTerm } from "./glossary.ts";
import type { SavedTermsRepository } from "./repository.ts";

/** One kind of drink a place makes, as the reader saved it: 산 후안의 레드. */
export type SavedStyle = {
  /** The key the balloon saves it by: regional_style:san_juan_red. */
  key: string;
  /** 레드, 화이트, 스파클링. */
  label: string;
  description: string;
  saved_at: string;
};

/**
 * A saved term. A place is one term however many of its styles the reader
 * saved: its own explanation first (`intro`), then each saved style
 * (`parts`). `description` says the same in one text, for an app that knows
 * no parts.
 */
export type SavedTerm = GlossaryTerm & {
  saved_at: string;
  /** The place's own explanation; null when the dictionary has none. */
  intro?: string | null;
  /** Whether the place itself was saved, apart from its styles. */
  own?: boolean;
  parts?: SavedStyle[];
};

/** A save or its removal, as the app asks for it. */
export type SavedTermChange = { key: string; saved: boolean };

const STYLE = "regional_style:";
const REGION = "region:";

const STYLE_BY_KEY: ReadonlyMap<string, Term> = new Map(
  terms("regional_style").map((t) => [t.key, t]),
);
const REGION_BY_KEY: ReadonlyMap<string, Term> = new Map(
  terms("region").map((t) => [t.key, t]),
);

/** The place a saved style is filed under, when the dictionary knows it. */
function placeOf(termKey: string): Term | null {
  if (!termKey.startsWith(STYLE)) return null;
  const style = STYLE_BY_KEY.get(termKey.slice(STYLE.length));
  return REGION_BY_KEY.get(String(style?.extra?.region_key)) ?? null;
}

/**
 * The saved rows as the list shows them, newest first: a style goes under
 * its place, and a place with nothing left under it is not there.
 */
function listed(
  rows: readonly { term_key: string; created_at: string }[],
): SavedTerm[] {
  const out: SavedTerm[] = [];
  const places = new Map<string, SavedTerm>();
  const placeTerm = (region: Term, at: string): SavedTerm => {
    const key = `${REGION}${region.key}`;
    const known = places.get(key);
    if (known) return known;
    const own = glossaryTerm(key);
    const made: SavedTerm = {
      key,
      label: region.names.ko,
      kind: "산지",
      categories: own?.categories ?? [],
      description: "",
      saved_at: at,
      intro: region.summary?.trim() || null,
      own: false,
      parts: [],
    };
    places.set(key, made);
    out.push(made);
    return made;
  };
  for (const row of rows) {
    const term = glossaryTerm(row.term_key);
    if (!term) continue;
    const region = placeOf(row.term_key) ??
      (row.term_key.startsWith(REGION)
        ? REGION_BY_KEY.get(row.term_key.slice(REGION.length)) ?? null
        : null);
    if (!region) {
      out.push({ ...term, saved_at: row.created_at });
      continue;
    }
    const place = placeTerm(region, row.created_at);
    if (row.term_key.startsWith(REGION)) {
      place.own = true;
      continue;
    }
    const style = STYLE_BY_KEY.get(row.term_key.slice(STYLE.length))!;
    place.parts!.push({
      key: row.term_key,
      label: styleKindLabel(style) ?? term.label,
      description: term.description,
      saved_at: row.created_at,
    });
    if (!place.categories.length) place.categories = term.categories;
  }
  for (const place of places.values()) {
    place.description = [
      place.intro,
      ...place.parts!.map((p) => `${p.label}: ${p.description}`),
    ].filter(Boolean).join("\n\n");
  }
  return out;
}

/**
 * The reader's 나의 용어 사전, newest first, after an optional [change]. A
 * key the dictionary no longer explains stays in the table and out of the
 * list. Taking a place out takes its saved styles out with it.
 */
export async function savedTermsForUser(
  repository: SavedTermsRepository,
  userId: string,
  change?: SavedTermChange,
): Promise<{ terms: SavedTerm[] }> {
  // Like every signed-in endpoint, only an active account is answered.
  if (!await repository.accountActive(userId)) {
    throw new SoolgyulHttpError(403, "active_account_required");
  }
  if (change?.saved) {
    if (glossaryTerm(change.key) === null) {
      throw new SoolgyulHttpError(400, "term_unknown");
    }
    await repository.save(userId, change.key);
  } else if (change) {
    await repository.remove(userId, change.key);
    if (change.key.startsWith(REGION)) {
      const under = (await repository.list(userId)).filter((row) =>
        `${REGION}${placeOf(row.term_key)?.key}` === change.key
      );
      for (const row of under) await repository.remove(userId, row.term_key);
    }
  }
  return { terms: listed(await repository.list(userId)) };
}
