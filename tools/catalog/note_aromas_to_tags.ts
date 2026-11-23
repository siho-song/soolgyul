/**
 * Lists, per bottle, the aroma names its notes state that its tag columns do
 * not hold yet, so they can be added to the tags before the note columns of
 * alcohol_tasting_profiles are dropped. The card used to read these names
 * out of the note text each time it was written; a bottle's aromas are its
 * tags alone now.
 *
 * Input: a JSON array of the profiles that have a note, one object each with
 *   id (alcohol_item_id), aroma_note, palate_note, finish_note,
 *   aroma_tags, palate_tags, finish_tags
 * and a JSON array of the tag names the database accepts, one object each
 * with term_key and applicable_sections (catalog_taxonomy rows of type
 * sensory_descriptor).
 *
 *   deno run --allow-read --allow-write tools/catalog/note_aromas_to_tags.ts <profiles.json> <taxonomy.json> <out.json>
 *
 * Output: a JSON array of { id, aroma_tags?, palate_tags?, finish_tags? }
 * holding only the names to add. A name is a reader's aroma name of the
 * dictionary, found as a whole word in a clause that is not a comparison, a
 * negation or a supposition. A bottle whose tags already hold the name, under
 * any of the words the dictionary keeps for it, gains nothing.
 */
import { senseChoices } from "../../supabase/functions/_shared/record_reading/dictionary/aromas.ts";

const SECTIONS = [
  ["aroma_note", "aroma_tags", "aroma"],
  ["palate_note", "palate_tags", "palate"],
  ["finish_note", "finish_tags", "finish"],
] as const;
const MAX_TAGS = 64;

const names = senseChoices().filter((group) => group.of === "descriptor")
  .flatMap((group) =>
    [
      ...new Set([
        group.label,
        ...group.found_by,
        // The other spelling of 요거트.
        ...(group.key === "lactic" ? ["요구르트"] : []),
      ]),
    ].map((label) => ({
      key: group.key,
      phases: group.said_of as readonly string[],
      // 머스크 before 멜론 names the melon, not the musk kept under 향신료.
      pattern: new RegExp(
        `(?:^|[\\s·,/()])${label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}${
          label === "머스크" ? "(?![\\s(（-]*(?:멜론|메론))" : ""
        }(?=$|[\\s·,/()]|향|풍미|은|는|이|가|와|과|을|를|의)`,
      ),
    }))
  );
/** A stored tag, under whichever word the dictionary keeps for it → its reader's name. */
const nameOfTag = new Map(
  senseChoices().flatMap((group) =>
    [group.key, ...group.tags].map((key) => [key, group.key] as const)
  ),
);

/** The aroma names a note states outright, for one section. */
export function namesInNote(note: string, section: string): string[] {
  const clauses = note.split(/[.!?。;\n]+/).filter((clause) =>
    !/없|아니(?!스)|않|못|무향|보다|대신|라면|같다면|\b(?:no|not|without|rather|if)\b/i
      .test(clause)
  );
  const found = new Set<string>();
  for (const clause of clauses) {
    for (const name of names) {
      if (name.phases.includes(section) && name.pattern.test(clause)) {
        found.add(name.key);
      }
    }
  }
  return [...found];
}

type Profile = Record<string, unknown> & { id: string };

export function tagsToAdd(
  profiles: readonly Profile[],
  accepted: ReadonlyMap<string, readonly string[]>,
): Record<string, unknown>[] {
  const out: Record<string, unknown>[] = [];
  for (const profile of profiles) {
    const add: Record<string, string[]> = {};
    for (const [noteColumn, tagColumn, section] of SECTIONS) {
      const note = typeof profile[noteColumn] === "string"
        ? (profile[noteColumn] as string).normalize("NFC").trim()
        : "";
      if (!note) continue;
      const stored = Array.isArray(profile[tagColumn])
        ? profile[tagColumn] as string[]
        : [];
      const held = new Set(
        stored.flatMap((tag) => [tag, nameOfTag.get(tag) ?? tag]),
      );
      const fresh = namesInNote(note, section).filter((name) =>
        !held.has(name) && accepted.get(name)?.includes(section)
      );
      if (fresh.length && stored.length + fresh.length <= MAX_TAGS) {
        add[tagColumn] = fresh;
      }
    }
    if (Object.keys(add).length) out.push({ id: profile.id, ...add });
  }
  return out;
}

if (import.meta.main) {
  const [profilesPath, taxonomyPath, outPath] = Deno.args;
  if (!profilesPath || !taxonomyPath || !outPath) {
    console.error(
      "usage: note_aromas_to_tags.ts <profiles.json> <taxonomy.json> <out.json>",
    );
    Deno.exit(2);
  }
  const profiles = JSON.parse(await Deno.readTextFile(profilesPath));
  const accepted = new Map<string, readonly string[]>(
    (JSON.parse(await Deno.readTextFile(taxonomyPath)) as {
      term_key: string;
      applicable_sections: string[];
    }[]).map((row) => [row.term_key, row.applicable_sections]),
  );
  const out = tagsToAdd(profiles, accepted);
  const total = (column: string) =>
    out.reduce(
      (sum, row) => sum + ((row[column] as string[] | undefined)?.length ?? 0),
      0,
    );
  await Deno.writeTextFile(outPath, JSON.stringify(out));
  console.log(
    `bottles ${out.length} · aroma +${total("aroma_tags")} · palate +${
      total("palate_tags")
    } · finish +${total("finish_tags")}`,
  );
}
