// The gauge sheet as it is written (catalog/sensory/gauge-definitions.json),
// read here only: the axes a gauge can ask, in the order a record keeps its
// answers, each with the name the catalog and the dictionary give it (a
// bottle's level, a row's taste: 타닌 is astringency there, 탄산감
// carbonation); and every kind's gauges, with the styles each is shown to.
// The app reads the same file.
import gaugeFile from "../../../../../catalog/sensory/gauge-definitions.json" with {
  type: "json",
};
import type { GaugeAxis } from "../facts/facts.ts";

export type GaugeDefinition = {
  axis: string;
  label_ko: string;
  levels: readonly { term: string; hint?: string }[];
  ends_ko?: readonly string[];
  show?: {
    styles?: readonly string[];
    except_styles?: readonly string[];
    unknown_style?: boolean;
  };
};
export type GaugeKind = {
  palate: readonly GaugeDefinition[];
  finish: readonly GaugeDefinition[];
};

/** Each axis and the catalog's name for it, in the order of the axes. */
export const GAUGE_AXIS_NAMES: readonly {
  axis: GaugeAxis;
  catalog: string;
}[] = gaugeFile.axes as { axis: GaugeAxis; catalog: string }[];

export const GAUGE_KINDS: Readonly<Record<string, GaugeKind>> = gaugeFile.kinds;

/** The kind whose plain gauges a drink of no known kind is asked. */
export const GAUGE_FALLBACK: { kind: string; palate_axes: readonly string[] } =
  gaugeFile.fallback;

/**
 * The sheet as the questionnaire was published with it: every word a reader
 * is shown. The axes' catalog names say nothing a reader is asked and were
 * written into the file after, so they are not part of it.
 */
export const PUBLISHED_GAUGE_SHEET = {
  version: gaugeFile.version,
  kinds: gaugeFile.kinds,
  fallback: gaugeFile.fallback,
};

{
  const axes = GAUGE_AXIS_NAMES.map((a) => a.axis as string);
  const names = GAUGE_AXIS_NAMES.map((a) => a.catalog);
  const rows = Object.values(GAUGE_KINDS).flatMap((kind) => [
    ...kind.palate,
    ...kind.finish,
  ]);
  if (
    gaugeFile.version !== 2 || !GAUGE_KINDS[GAUGE_FALLBACK.kind] ||
    new Set(axes).size !== axes.length ||
    new Set(names).size !== names.length ||
    rows.some((row) => !axes.includes(row.axis) || row.levels.length !== 5)
  ) throw new Error("sensory_gauge_definitions_invalid");
}
