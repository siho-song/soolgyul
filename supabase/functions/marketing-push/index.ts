// An admin's marketing notification, from the administrator web to the
// phones of the members who agreed to marketing. The rules a marketing
// message must keep are kept here, whatever the page sends: it is marked as
// an advertisement, says how to refuse, and is not sent at night.
import {
  allowedOrigin,
  answerBeforeWork,
  jsonResponse,
  readJsonBody,
  SoolgyulHttpError,
} from "../_shared/http.ts";
import { errorResponse } from "../_shared/errors.ts";
import { UUID_PATTERN } from "../_shared/contract.ts";
import {
  boundedFetch,
  callerHeaders,
  postgrestJson,
  readAllPages,
  serviceRoleHeaders,
} from "../_shared/supabase.ts";
import {
  fcmAccessToken,
  fcmAccountFrom,
  type FcmNotice,
  sendFcm,
} from "./fcm.ts";

type Environment = (name: string) => string | undefined;

/** How many phones are sent to at once. */
const SEND_BATCH = 50;

/** The notification a member sees for what the admin typed. */
export function marketingNotice(title: string, body: string): FcmNotice {
  return {
    title: `(광고) ${title}`,
    body: `${body}\n수신거부: 마이페이지 > 약관 및 정책`,
  };
}

/** Marketing messages go out from 8 in the morning to 9 at night, Korean time. */
export function marketingHoursOpen(now: Date): boolean {
  const hour = (now.getUTCHours() + 9) % 24;
  return hour >= 8 && hour < 21;
}

function sendFrom(body: unknown): { id: string; title: string; body: string } {
  const send = body !== null && typeof body === "object"
    ? body as Record<string, unknown>
    : {};
  const { id, title, body: text } = send;
  if (
    typeof id !== "string" || !UUID_PATTERN.test(id) ||
    typeof title !== "string" || typeof text !== "string"
  ) {
    throw new SoolgyulHttpError(400, "marketing_push_invalid");
  }
  return { id, title: title.trim(), body: text.trim() };
}

/** A database refusal as the answer the admin page gets. */
function refusal(code: string): SoolgyulHttpError {
  if (code === "42501") {
    return new SoolgyulHttpError(403, "admin_role_required");
  }
  if (code === "23505") {
    return new SoolgyulHttpError(409, "marketing_push_already_sent");
  }
  if (code === "22023") {
    return new SoolgyulHttpError(400, "marketing_push_invalid");
  }
  if (code === "http_401" || code.startsWith("PGRST3")) {
    return new SoolgyulHttpError(401, "authorization_rejected");
  }
  return new SoolgyulHttpError(503, "marketing_push_unavailable");
}

export async function handleMarketingPush(
  request: Request,
  env: Environment = Deno.env.get,
  fetcher: typeof fetch = boundedFetch,
  now: () => Date = () => new Date(),
): Promise<Response> {
  if (request.headers.has("Origin") && allowedOrigin(request) === null) {
    return jsonResponse(request, 403, { error_code: "origin_rejected" });
  }
  const early = answerBeforeWork(request, ["POST"]);
  if (early !== null) return early;
  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      throw new SoolgyulHttpError(401, "authorization_required");
    }
    const send = sendFrom(await readJsonBody(request));
    if (!marketingHoursOpen(now())) {
      throw new SoolgyulHttpError(409, "marketing_push_night_hours");
    }
    const url = env("SUPABASE_URL") ?? "";
    const anonKey = env("SUPABASE_ANON_KEY") ?? "";
    const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const account = fcmAccountFrom(env("FIREBASE_SERVICE_ACCOUNT"));
    if (!url || !anonKey || !serviceKey || account === null) {
      throw new SoolgyulHttpError(503, "marketing_push_unavailable");
    }
    let accessToken: string;
    try {
      accessToken = await fcmAccessToken(account, fetcher, now());
    } catch {
      throw new SoolgyulHttpError(503, "marketing_push_unavailable");
    }

    // The database decides whether the caller is an admin and whether this
    // send was already asked, and keeps it before anything goes out.
    await postgrestJson(
      fetcher,
      `${url}/rest/v1/rpc/soolgyul_admin_start_marketing_push`,
      {
        method: "POST",
        headers: callerHeaders(anonKey, authorization),
        body: JSON.stringify({
          p_id: send.id,
          p_title: send.title,
          p_body: send.body,
        }),
      },
      refusal,
    );

    const service = serviceRoleHeaders(serviceKey);
    const devices = await readAllPages((page) =>
      postgrestJson<Array<{ token: string }>>(
        fetcher,
        `${url}/rest/v1/rpc/soolgyul_marketing_push_devices?order=token${page}`,
        { headers: service },
        refusal,
      )
    );
    const tokens = [...new Set(devices.map((device) => device.token))];
    const notice = marketingNotice(send.title, send.body);
    let sent = 0;
    const gone: string[] = [];
    for (let start = 0; start < tokens.length; start += SEND_BATCH) {
      const batch = tokens.slice(start, start + SEND_BATCH);
      const outcomes = await Promise.all(
        batch.map((token) =>
          sendFcm(fetcher, account.project_id, accessToken, token, notice)
        ),
      );
      outcomes.forEach((outcome, index) => {
        if (outcome === "sent") sent += 1;
        if (outcome === "gone") gone.push(batch[index]);
      });
    }

    try {
      await postgrestJson(
        fetcher,
        `${url}/rest/v1/rpc/soolgyul_finish_marketing_push`,
        {
          method: "POST",
          headers: service,
          body: JSON.stringify({
            p_id: send.id,
            p_device_count: tokens.length,
            p_sent_count: sent,
            p_gone_tokens: gone,
          }),
        },
        refusal,
      );
    } catch {
      // The notifications are out; the admin is told how many, and the send
      // stays open in the history.
      console.error("marketing push: the send could not be closed");
    }
    return jsonResponse(request, 200, {
      device_count: tokens.length,
      sent_count: sent,
    });
  } catch (error) {
    return errorResponse(request, error);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleMarketingPush(request));
}
