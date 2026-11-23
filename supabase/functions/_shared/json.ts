// Reading JSON whose shape is not yet known: a request body, a database row,
// a decoded token.

/** True for a JSON object: not null, not a list. */
export function isJsonObject(
  value: unknown,
): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** The strings of a list, in its own order; anything else in it is dropped, and a value that is no list is empty. */
export function stringsOf(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}
