export function canonicalJson(value: unknown): string {
  return JSON.stringify(normalize(value));
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value.normalize("NFC")),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function stableId(
  namespace: string,
  value: unknown,
): Promise<string> {
  return `${namespace}:${await sha256Hex(canonicalJson(value))}`;
}

function normalize(value: unknown): unknown {
  if (typeof value === "string") return value.normalize("NFC");
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new TypeError("non_finite_number");
    return Object.is(value, -0) ? 0 : value;
  }
  if (value === null || typeof value === "boolean") return value;
  if (Array.isArray(value)) return value.map(normalize);
  if (typeof value === "object") {
    const object = value as Record<string, unknown>;
    return Object.fromEntries(
      Object.keys(object).sort().map((
        key,
      ) => [key.normalize("NFC"), normalize(object[key])]),
    );
  }
  throw new TypeError(`unsupported_canonical_value:${typeof value}`);
}
