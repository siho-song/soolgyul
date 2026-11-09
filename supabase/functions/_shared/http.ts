// Browser origin allow-list and JSON responses shared by every edge function.
// Native clients send no Origin header and need no CORS headers; a browser on
// an unknown origin gets no Access-Control-Allow-Origin at all.

const productionOrigins = ["https://soolgyul.com", "https://app.soolgyul.com"];

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
