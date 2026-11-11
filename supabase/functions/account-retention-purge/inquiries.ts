/** The support inbox's share of the scheduled job. An inquiry answered six
 * months ago loses its photos, then its reply address and owner; photos
 * uploaded for an inquiry that was never sent are removed after a day. The
 * database says what is due (soolgyul_due_support_inquiries,
 * soolgyul_stale_inquiry_uploads).
 */
export interface InquiryRetentionStore {
  listDueInquiries(): Promise<{ id: string; attachment_paths: string[] }[]>;
  listStaleInquiryUploads(): Promise<string[]>;
  // Through the Storage API: a row deleted in SQL leaves the file behind.
  deleteInquiryUploads(paths: string[]): Promise<void>;
  // RPC soolgyul_close_support_inquiry, which refuses while a photo remains.
  closeInquiry(id: string): Promise<void>;
}

export async function runInquiryRetention(
  store: InquiryRetentionStore,
): Promise<{ closed: number; failed: number; stale_uploads: number }> {
  let closed = 0, failed = 0;
  for (const inquiry of await store.listDueInquiries()) {
    try {
      await store.deleteInquiryUploads(inquiry.attachment_paths);
      await store.closeInquiry(inquiry.id);
      closed++;
    } catch {
      failed++;
    } // The next run tries it again; nothing is logged about the inquiry.
  }
  const stale = await store.listStaleInquiryUploads();
  await store.deleteInquiryUploads(stale);
  return { closed, failed, stale_uploads: stale.length };
}
