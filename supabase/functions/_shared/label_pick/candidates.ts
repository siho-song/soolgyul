// The catalog drinks a label photo's candidates are, as the judge is told of
// them: read here and never taken from the caller, so the words that reach
// the model are the catalog's own.
import {
  boundedFetch,
  postgrestJson,
  serviceRoleHeaders,
} from "../supabase.ts";

export type LabelCandidate = {
  id: string;
  /** The English name without a vintage year at its end; the Korean name when it has none. */
  name: string;
  /** The maker's name in its own script, else in English, else in Korean; empty when the catalog names none. */
  maker: string;
  /** The public address of the catalog's photo of it; `null` without a published one. */
  photo_url: string | null;
};

export interface LabelCandidateRepository {
  /** The published drinks of [ids], in the order of [ids]. An id the catalog does not publish is left out. */
  loadCandidates(ids: readonly string[]): Promise<LabelCandidate[]>;
}

const CATALOG_IMAGE_BUCKET = "alcohol-product-images";
const VINTAGE_AT_END = /\s+(?:19|20)\d\d$/;

export class SupabaseLabelCandidateRepository
  implements LabelCandidateRepository {
  constructor(
    private readonly supabase_url: string,
    private readonly service_role_key: string,
    private readonly fetch_impl: typeof fetch = boundedFetch,
  ) {}

  async loadCandidates(ids: readonly string[]): Promise<LabelCandidate[]> {
    if (ids.length === 0) return [];
    const rows = await postgrestJson<Record<string, unknown>[]>(
      this.fetch_impl,
      `${this.supabase_url}/rest/v1/alcohol_items` +
        `?id=in.(${ids.map(encodeURIComponent).join(",")})` +
        "&publish_status=eq.published" +
        "&select=id,name_ko,name_en," +
        "producer:producers(name_ko,name_en,name_native)," +
        "photo:catalog_media_assets(media_path,publish_status)",
      { headers: serviceRoleHeaders(this.service_role_key) },
      (code, message) => new Error(`label_candidates_${code}: ${message}`),
    );
    const byId = new Map(rows.map((row) => [String(row.id), row]));
    return ids.flatMap((id) => {
      const row = byId.get(id);
      return row === undefined ? [] : [this.candidateFrom(row)];
    });
  }

  private candidateFrom(row: Record<string, unknown>): LabelCandidate {
    const producer = one(row.producer);
    const photo = one(row.photo);
    const path = photo?.publish_status === "published"
      ? text(photo.media_path)
      : "";
    return {
      id: String(row.id),
      name: text(row.name_en).replace(VINTAGE_AT_END, "") || text(row.name_ko),
      maker: text(producer?.name_native) || text(producer?.name_en) ||
        text(producer?.name_ko),
      photo_url: path
        ? `${this.supabase_url}/storage/v1/object/public/${CATALOG_IMAGE_BUCKET}/${
          path.split("/").map(encodeURIComponent).join("/")
        }`
        : null,
    };
  }
}

/** The row PostgREST embedded: itself, or the first of a list of them. */
function one(value: unknown): Record<string, unknown> | null {
  const row = Array.isArray(value) ? value[0] : value;
  return row && typeof row === "object" ? row as Record<string, unknown> : null;
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}
