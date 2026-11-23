/**
 * Aroma names on one line of the catalog tree.
 *
 * The catalog's parent links say what each aroma name is a kind of. A reader's
 * answer and a data name (a style line or a product tag) are taken as the same
 * observation when one sits above the other on that line: the reader's
 * "복숭아" meets a style line "핵과", and a reader's "시트러스" meets a product tag
 * "lemon". A broad data name is never expanded into a narrower claim the reader
 * did not make; the matcher only recognises what the reader said.
 */
import { sensoryCatalog as catalog } from "./dictionary.ts";

const PARENT = new Map<string, string | null>(
  catalog.descriptors.map((row) => [row.key, row.parent_key ?? null]),
);

/** The name itself, then each ancestor up to the root. Unknown keys yield only themselves. */
export function aromaLine(key: string): string[] {
  const out: string[] = [];
  let current: string | null = key;
  while (current !== null && !out.includes(current)) {
    out.push(current);
    current = PARENT.get(current) ?? null;
  }
  return out;
}

/** True when the two names are equal or one is an ancestor of the other. */
export function sameAromaLine(a: string, b: string): boolean {
  return a === b || aromaLine(a).includes(b) || aromaLine(b).includes(a);
}
