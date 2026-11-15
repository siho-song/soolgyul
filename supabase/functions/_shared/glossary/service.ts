import { SoolgyulHttpError } from "../http.ts";
import { type GlossaryTerm, glossaryTerm } from "./glossary.ts";
import type { SavedTermsRepository } from "./repository.ts";

export type SavedTerm = GlossaryTerm & { saved_at: string };

/** A save or its removal, as the app asks for it. */
export type SavedTermChange = { key: string; saved: boolean };

/**
 * The reader's 나의 용어 사전, newest first, after an optional [change]. A
 * key the dictionary no longer explains stays in the table and out of the
 * list.
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
  }
  const rows = await repository.list(userId);
  return {
    terms: rows.flatMap((row) => {
      const term = glossaryTerm(row.term_key);
      return term ? [{ ...term, saved_at: row.created_at }] : [];
    }),
  };
}
