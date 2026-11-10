/** Real adapter operations must use trusted server credentials, never client IDs.
 * No scheduler/HTTP route is enabled by importing this module.
 */
/** Days an account stays restorable after its deletion request. The database
 * applies the same window in soolgyul_deletion_due_at. */
export const RETENTION_DAYS = 30;

/** Epoch milliseconds of the purge deadline; NaN when no request exists. */
function deletionDueAt(requestedAt: string | null): number {
  return Date.parse(requestedAt ?? "") + RETENTION_DAYS * 24 * 60 * 60 * 1000;
}

export interface WithdrawalPurgeStore {
  // Read from users; requested_at and now must not originate in a client payload.
  getAccount(userId: string): Promise<
    {
      account_status: string;
      deletion_requested_at: string | null;
      purged_at: string | null;
    } | null
  >;
  // Must include provider-required revocation (notably Apple). Fail closed when
  // the required credential/integration is unavailable; never silently skip it.
  revokeProviderAccess(userId: string): Promise<void>;
  // Delete actual objects through Storage API, including all paginated folders.
  deletePrivateStorage(userId: string): Promise<void>;
  // Atomic RPC: soolgyul_finalize_withdrawn_account_data(target_user_id).
  preserveRecordsAndClearAccount(userId: string): Promise<number>;
  // Auth Admin hard deletion; cascades product account and its remaining relations.
  // Treat already absent as success. On failure users.purged_at permits retry.
  deleteAuthAccount(userId: string): Promise<void>;
}

export async function finalizeWithdrawnAccount(
  store: WithdrawalPurgeStore,
  userId: string,
  now = new Date(),
): Promise<{ retained_records: number; already_absent: boolean }> {
  const account = await store.getAccount(userId);
  if (!account) return { retained_records: 0, already_absent: true };
  let retained = 0;
  if (!account.purged_at) {
    const deadline = deletionDueAt(account.deletion_requested_at);
    if (
      account.account_status !== "scheduled_deletion" ||
      !Number.isFinite(deadline) || !Number.isFinite(now.getTime()) ||
      deadline > now.getTime()
    ) {
      throw new Error("account_purge_not_due");
    }
    await store.revokeProviderAccess(userId);
    await store.deletePrivateStorage(userId);
    retained = await store.preserveRecordsAndClearAccount(userId);
  }
  await store.deleteAuthAccount(userId);
  return { retained_records: retained, already_absent: false };
}
