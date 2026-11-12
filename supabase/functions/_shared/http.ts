// Browser origin allow-list, JSON bodies and responses shared by every edge
// function.
// Native clients send no Origin header and need no CORS headers; a browser on
// an unknown origin gets no Access-Control-Allow-Origin at all.

/** A request refused with this status and public error code. */
export class SoolgyulHttpError extends Error {
  constructor(public status: number, public code: string) {
    super(code);
    this.name = "SoolgyulHttpError";
  }
}

const productionOrigins = [
  "https://soolgyul.com",
  "https://app.soolgyul.com",
  "https://admin.soolgyul.com",
];

export function allowedOrigin(request: Request): string | null {
  const origin = request.headers.get("Origin");
  if (origin === null) return null;
  const configured = (Deno.env.get("SOOLGYUL_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  return productionOrigins.includes(origin) || configured.includes(origin)
    ? origin
    : null;
}

export function corsHeaders(request: Request): Record<string, string> {
  const origin = allowedOrigin(request);
  return {
    ...(origin === null ? {} : { "Access-Control-Allow-Origin": origin }),
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
    Vary: "Origin",
  };
}

export function jsonResponse(
  request: Request,
  status: number,
  body: unknown,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...corsHeaders(request),
    },
  });
}

/**
 * Answers what comes before an endpoint's work: a CORS preflight, or a
 * method the endpoint does not take. `null` lets the request through.
 */
export function answerBeforeWork(
  request: Request,
  methods: readonly string[],
): Response | null {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(request) });
  }
  if (!methods.includes(request.method)) {
    return jsonResponse(request, 405, { error_code: "method_not_allowed" });
  }
  return null;
}

export async function readJsonBody(request: Request): Promise<unknown> {
  const maximumBytes = 64 * 1024;
  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    throw new SoolgyulHttpError(415, "json_body_required");
  }
  const declaredLength = Number(request.headers.get("Content-Length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new SoolgyulHttpError(413, "json_body_too_large");
  }
  try {
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (bytes.byteLength > maximumBytes) {
      throw new SoolgyulHttpError(413, "json_body_too_large");
    }
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch (error) {
    if (error instanceof SoolgyulHttpError) throw error;
    throw new SoolgyulHttpError(400, "invalid_json");
  }
}
