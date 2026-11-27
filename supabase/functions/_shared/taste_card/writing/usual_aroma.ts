/** What an aroma usually comes from in the bottle's kind, where the bottle's own facts do not say otherwise. */
import type { EvidenceResult } from "../evidence/evidence.ts";
import type { BottleFacts } from "../../record_reading/bottle.ts";
import {
  placesUpFrom,
  regionalStyleByKey,
  regionLineUnder,
  usualAromaOf,
} from "../../record_reading/dictionary/dictionary.ts";

/** A cask named by what it held, or by its oak: what a bottle says of its own casks. */
const namesCask = (key: string) =>
  /^ex_.+_cask$/.test(key) || key === "new_oak_cask" || key === "mizunara_oak";

/**
 * The kind's usual cause of an aroma, as the dictionary's kind row says it
 * (블렌디드 위스키의 건포도 향은 보통 …). Null where the row says none, and
 * where the bottle states a fact the words do not fit: casks of its own and
 * none of those the words name, a place other than the one they are of, or a
 * process, an ingredient or a climate that makes them untrue. A fact the
 * bottle does not state says nothing against them.
 */
export function usualAromaFor(
  bottle: BottleFacts,
  identity: EvidenceResult["identity"],
): (aroma: string) => { kind: string; from: string } | null {
  const place = regionalStyleByKey(bottle.region_entry)?.region_key ?? null;
  const climate = placesUpFrom("wine", place).find((p) => p.climate)?.climate;
  const facts = new Set([
    ...bottle.processes,
    ...bottle.ingredients,
    ...identity.causes.map((c) => c.key),
    ...(climate ? [`climate:${climate}`] : []),
  ]);
  const casks = bottle.processes.filter(namesCask);
  return (aroma) => {
    const usual = usualAromaOf(bottle.style_key, aroma);
    if (!usual) return null;
    if (usual.unless?.some((fact) => facts.has(fact))) return null;
    if (
      usual.casks && casks.length &&
      !usual.casks.some((cask) => casks.includes(cask))
    ) return null;
    if (
      usual.under && bottle.region &&
      !regionLineUnder(bottle.region, usual.under)
    ) return null;
    return { kind: usual.kind, from: usual.from };
  };
}
