/** A member's account row, as every signed-in endpoint asks of it. */
import type { ServiceRest } from "./service_rest.ts";

export type Account = {
  /** False for a withdrawn or unknown account: only an active account is answered. */
  active: boolean;
  /** Null before the profile is complete. */
  display_name: string | null;
};

export async function readAccount(
  rest: ServiceRest,
  userId: string,
): Promise<Account> {
  const rows = await rest<Record<string, unknown>[]>(
    `users?id=eq.${encodeURIComponent(userId)}` +
      "&select=display_name,account_status&limit=1",
  );
  const name = rows[0]?.display_name;
  return {
    active: rows[0]?.account_status === "active",
    display_name: typeof name === "string" && name.trim() ? name.trim() : null,
  };
}
