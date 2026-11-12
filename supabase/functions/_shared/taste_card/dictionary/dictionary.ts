// The one dictionary (catalog/dictionary/terms.json), read as the shapes the
// card code grew up with. Each view below is what the old knowledge file held
// for the parts the code uses; the dictionary is the only source now.
import dictionary from "../../../../../catalog/dictionary/terms.json" with {
  type: "json",
};

/* ------------------------------------------------------------- dictionary */

type TermTrait = {
  level: string;
  basis?: string;
  reason?: string;
  evidence?: string;
  detail?: string;
  sources?: string[];
};

type TermAroma = {
  key: string;
  basis?: string;
  reason?: string;
  source_kind?: string;
  source?: string;
  sources?: string[];
};

export type Term = {
  key: string;
  type: string;
  parent?: string | null;
  categories?: string[] | string;
  names: {
    ko: string;
    en?: string;
    aliases?: string[];
    label_patterns?: string[];
  };
  summary?: string;
  definition_en?: string;
  taste?: Record<string, TermTrait>;
  aromas?: TermAroma[];
  varies?: string;
  hints?: Record<string, unknown>;
  traits?: string[];
  app?: Record<string, unknown>;
  /** Where a fact came from: a reference (with its id) or collected evidence. */
  sources?: {
    id?: string;
    title?: string;
    url?: string;
    quote?: string;
    fields?: string[];
  }[];
  extra?: Record<string, unknown>;
};

const sourceIds = (t: Term): string[] =>
  (t.sources ?? []).flatMap((s) => (s.id ? [s.id] : []));

type Dictionary = {
  schema_version: number;
  versions: Record<string, unknown>;
  style_axes: string[];
  abv_levels: string[];
  app_categories: { key: string; label_ko: string }[];
  sources: Record<string, { title: string; url: string }>;
  trait_policy: string;
  expression_rules: ExpressionRule[];
  base_taxonomy: Record<string, unknown>;
  governance: Record<string, string>;
  source_mapping_policy: Record<string, unknown>;
  ingredient_roles: TaxonomyKind[];
  sensory_phases: string[];
  style_redirects: Record<string, string>;
  taxonomy_order: { kinds: string[]; descriptors: string[] };
  unplaced_descriptors: TaxonomyDescriptor[];
  terms: Term[];
};

const DICTIONARY = dictionary as unknown as Dictionary;

export function terms(...types: string[]): Term[] {
  return DICTIONARY.terms.filter((t) => types.includes(t.type));
}

/* ---------------------------------------------------------- regions */

/** Every region row by its key. */
export const regionByKey: ReadonlyMap<string, Term> = new Map(
  terms("region").map((t) => [t.key, t]),
);

/** The region line the card engine reads, rebuilt from the region tree:
 * '부르고뉴(Bourgogne) > 샤블리(Chablis)'. The country row is left out, as the
 * item carries its country code. */
export function regionPath(key: unknown): string | null {
  if (typeof key !== "string") return null;
  const parts: string[] = [];
  for (
    let term = regionByKey.get(key);
    term && term.parent;
    term = regionByKey.get(term.parent)
  ) {
    const { ko, en } = term.names;
    parts.unshift(en ? `${ko}(${en})` : ko);
  }
  return parts.length ? parts.join(" > ") : null;
}

/* ---------------------------------------------------------- style table */

type StyleTrait = {
  level: string;
  basis?: string;
  reason_ko?: string;
  evidence_ko?: string;
  detail_ko?: string;
  sources?: string[];
};

type StyleAroma = {
  key: string;
  basis?: string;
  reason_ko?: string;
  source_kind?: string;
  source_ko?: string;
  sources?: string[];
};

type StyleEntry = {
  key: string;
  name_ko: string;
  intro_ko: string;
  traits: Record<string, StyleTrait>;
  aromas: StyleAroma[];
  varies_ko: string;
  [extra: string]: unknown;
};

type GrapeEntry = StyleEntry & {
  colors: string[];
  match: { patterns: string[] };
};

type RegionEntry = StyleEntry & {
  color: string;
  match: {
    region_labels: string[];
    name_patterns: string[];
    style_keys?: string[];
  };
};

type ProcessEntry = {
  key: string;
  name_ko: string;
  intro_ko: string;
  traits?: Record<string, StyleTrait>;
  aromas: StyleAroma[];
  fact_ko?: string;
};

type StyleProfiles = {
  schemaVersion: number;
  dimensions: string[];
  styles: StyleEntry[];
  wine_grapes: GrapeEntry[];
  wine_regions: RegionEntry[];
  processes: ProcessEntry[];
};

const TRAIT_FIELDS: [keyof TermTrait, keyof StyleTrait][] = [
  ["level", "level"],
  ["basis", "basis"],
  ["reason", "reason_ko"],
  ["evidence", "evidence_ko"],
  ["detail", "detail_ko"],
  ["sources", "sources"],
];
const AROMA_FIELDS: [keyof TermAroma, keyof StyleAroma][] = [
  ["key", "key"],
  ["basis", "basis"],
  ["reason", "reason_ko"],
  ["source_kind", "source_kind"],
  ["source", "source_ko"],
  ["sources", "sources"],
];

function back<T>(obj: Record<string, unknown>, fields: [string, string][]): T {
  const out: Record<string, unknown> = {};
  for (const [from, to] of fields) {
    if (from in obj) out[to] = obj[from];
  }
  return out as T;
}

const styleTraits = (t: Term): Record<string, StyleTrait> =>
  Object.fromEntries(
    Object.entries(t.taste ?? {}).map((
      [axis, v],
    ) => [axis, back<StyleTrait>(v, TRAIT_FIELDS)]),
  );
const styleAromas = (t: Term): StyleAroma[] =>
  (t.aromas ?? []).map((a) => back<StyleAroma>(a, AROMA_FIELDS));
const extra = (t: Term, ...drop: string[]): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(t.extra ?? {}).filter(([k]) => !drop.includes(k)),
  );

function buildStyleProfiles(d: Dictionary): StyleProfiles {
  const styles = terms("kind").filter((t) => t.summary !== undefined).map((
    t,
  ): StyleEntry => ({
    key: t.key,
    name_ko: t.names.ko,
    intro_ko: t.summary!,
    traits: styleTraits(t),
    aromas: styleAromas(t),
    varies_ko: t.varies!,
    ...extra(t, "taxonomy"),
  }));
  const wine_grapes = terms("grape").map((t): GrapeEntry => ({
    key: t.key,
    name_ko: t.names.ko,
    intro_ko: t.summary!,
    colors: (t.hints?.colors as string[]) ?? [],
    match: { patterns: t.names.label_patterns ?? [] },
    traits: styleTraits(t),
    aromas: styleAromas(t),
    varies_ko: t.varies!,
    ...extra(t),
  }));
  const wine_regions = terms("regional_style").map((t): RegionEntry => {
    const match: RegionEntry["match"] = {
      region_labels: (t.hints?.region_labels as string[]) ?? [],
      name_patterns: t.names.label_patterns ?? [],
    };
    if (t.hints?.style_keys) match.style_keys = t.hints.style_keys as string[];
    return {
      key: t.key,
      name_ko: t.names.ko,
      color: t.hints?.color as string,
      intro_ko: t.summary!,
      match,
      traits: styleTraits(t),
      aromas: styleAromas(t),
      varies_ko: t.varies!,
      ...extra(t),
    };
  });
  // Only the rows the old style table carried; collected process knowledge
  // reaches the card through the dictionary itself, not this view.
  const processes = terms("process", "maturation")
    .filter((t) => t.extra?.style_table_order !== undefined)
    .sort((a, b) =>
      (a.extra!.style_table_order as number) -
      (b.extra!.style_table_order as number)
    )
    .map((t): ProcessEntry => {
      const entry: ProcessEntry = {
        key: t.key,
        name_ko: t.names.ko,
        intro_ko: t.summary!,
        aromas: styleAromas(t),
      };
      if (t.taste && Object.keys(t.taste).length) entry.traits = styleTraits(t);
      if (t.hints?.fact_label) entry.fact_ko = t.hints.fact_label as string;
      return entry;
    });
  return {
    schemaVersion: d.versions.style_profiles as number,
    dimensions: d.style_axes,
    styles,
    wine_grapes,
    wine_regions,
    processes,
  };
}

/* ------------------------------------------------------- sensory catalog */

type SensoryEntry = {
  key: string;
  label_ko: string;
  label_en?: string;
  aliases: string[];
  parent_key: string | null;
  onboarding_selectable?: boolean;
  phases: string[];
  source_aliases: Record<string, string[]>;
  automatic?: boolean;
  closed_phrase?: string;
  family_key?: string;
  group_label_ko?: string;
  facet_keys?: string[];
  is_facet?: boolean;
  classification_note?: string;
};

type FinishCharacterEntry = {
  key: string;
  label_ko: string;
  label_en?: string;
  source_aliases: Record<string, string[]>;
  family_key?: string;
};

type ExpressionRule = {
  action: string;
  expression: string;
  phase: string;
  source_key: string;
  target: Record<string, unknown> | null;
};

type SensoryCatalog = {
  service_vocabulary: string;
  families: { key: string; label_ko: string; domain: string; kind: string }[];
  descriptors: SensoryEntry[];
  expression_rules: ExpressionRule[];
  finish_characters: FinishCharacterEntry[];
  textures: SensoryEntry[];
};

function sensoryEntry(t: Term): SensoryEntry {
  const entry: SensoryEntry = {
    key: t.key,
    label_ko: t.names.ko,
    aliases: t.names.aliases ?? [],
    parent_key: t.parent ?? null,
    phases: (t.app?.phases as string[] | undefined) ?? [],
    source_aliases: {},
  };
  if (t.names.en !== undefined) entry.label_en = t.names.en;
  if (t.app?.selectable !== undefined) {
    entry.onboarding_selectable = t.app.selectable as boolean;
  }
  Object.assign(entry, extra(t, "legacy_keys", "knowledge_only", "taxonomy"));
  return entry;
}

function finishEntry(t: Term): FinishCharacterEntry {
  const entry: FinishCharacterEntry = {
    key: t.key,
    label_ko: t.names.ko,
    source_aliases: {},
  };
  if (t.names.en !== undefined) entry.label_en = t.names.en;
  Object.assign(entry, extra(t, "legacy_keys", "knowledge_only", "taxonomy"));
  return entry;
}

const catalogRows = (type: string) =>
  terms(type).filter((t) => !t.extra?.knowledge_only);

function buildSensoryCatalog(d: Dictionary): SensoryCatalog {
  return {
    service_vocabulary: "catalog/sensory/service-vocabulary.json",
    families: terms("aroma_family").map((t) => ({
      key: t.key,
      label_ko: t.names.ko,
      domain: t.extra!.domain as string,
      kind: t.extra!.kind as string,
    })),
    descriptors: catalogRows("aroma").map((t) => sensoryEntry(t)),
    expression_rules: d.expression_rules,
    finish_characters: catalogRows("finish_character").map(finishEntry),
    textures: catalogRows("texture").map((t) => sensoryEntry(t)),
  };
}

/* ------------------------------------------------------- term knowledge */

type TermKnowledgeEntry = {
  catalog: {
    label_ko: string;
    applicable_sections: string[];
    user_visible: boolean;
    status: string;
    source_keys: string[];
  };
  sensory_description: string;
  sensory_trait_keys: string[];
  source_ids: string[];
};

type TermKnowledge = {
  version: string;
  trait_policy: string;
  traits: Record<string, string>;
  sources: Record<string, { title: string; url: string }>;
  terms: Record<string, TermKnowledgeEntry>;
  dimensions: Record<
    string,
    Omit<TermKnowledgeEntry, "catalog">
  >;
};

const SENSORY_TYPES = ["aroma_family", "aroma", "texture", "finish_character"];

function buildTermKnowledge(d: Dictionary): TermKnowledge {
  const entries: Record<string, TermKnowledgeEntry> = {};
  for (const t of terms(...SENSORY_TYPES)) {
    const db = t.app?.db as TermKnowledgeEntry["catalog"] | undefined;
    if (!db) continue;
    entries[t.key] = {
      catalog: db,
      sensory_description: t.summary!,
      sensory_trait_keys: t.traits ?? [],
      source_ids: sourceIds(t),
    };
  }
  const dimensions: TermKnowledge["dimensions"] = {};
  for (const t of terms("axis")) {
    if (t.summary === undefined) continue;
    dimensions[t.key] = {
      sensory_description: t.summary,
      sensory_trait_keys: t.traits ?? [],
      source_ids: sourceIds(t),
    };
  }
  return {
    version: d.versions.term_knowledge as string,
    trait_policy: d.trait_policy,
    traits: Object.fromEntries(
      terms("trait").map((t) => [t.key, t.summary!]),
    ),
    sources: d.sources,
    terms: entries,
    dimensions,
  };
}

/* --------------------------------------------------- service vocabulary */

type VocabularyGroup = {
  key: string;
  label_ko: string;
  category_key: string;
  domain: string;
  source_keys: string[];
  user_source_labels: string[];
  phases: string[];
  decision_origin: string;
};

type ServiceVocabulary = {
  schema_version: string;
  taxonomy_version: string;
  decision: string;
  categories: { key: string; label_ko: string }[];
  groups: VocabularyGroup[];
  hidden: { reason: string; source_keys: string[] }[];
  pending: { key: string; label_ko: string; reason: string }[];
  legacy_aliases: Record<string, string>;
};

type Shown = {
  order: number;
  label: string;
  category: string;
  domain: string;
  members: string[];
  source_labels: string[];
  phases: string[];
  decision_origin: string;
};

function buildServiceVocabulary(d: Dictionary): ServiceVocabulary {
  const sensory = terms(...SENSORY_TYPES);
  const groups = sensory
    .filter((t) => t.app?.shown)
    .sort((a, b) =>
      (a.app!.shown as Shown).order - (b.app!.shown as Shown).order
    )
    .map((t): VocabularyGroup => {
      const s = t.app!.shown as Shown;
      return {
        key: t.key,
        label_ko: s.label,
        category_key: s.category,
        domain: s.domain,
        source_keys: s.members,
        user_source_labels: s.source_labels,
        phases: s.phases,
        decision_origin: s.decision_origin,
      };
    });
  const hidden = new Map<string, string[]>();
  for (const t of sensory) {
    const reason = t.app?.hidden_reason as string | undefined;
    if (reason) hidden.set(reason, [...(hidden.get(reason) ?? []), t.key]);
  }
  const pending = sensory.filter((t) => t.app?.pending).map((t) => {
    const p = t.app!.pending as { label: string; reason: string };
    return { key: t.key, label_ko: p.label, reason: p.reason };
  });
  const legacy_aliases: Record<string, string> = {};
  for (const t of sensory) {
    for (const old of (t.extra?.legacy_keys as string[] | undefined) ?? []) {
      legacy_aliases[old] = t.key;
    }
  }
  const v = d.versions.service_vocabulary as {
    schema_version: string;
    taxonomy_version: string;
    decision: string;
  };
  return {
    schema_version: v.schema_version,
    taxonomy_version: v.taxonomy_version,
    decision: v.decision,
    categories: d.app_categories,
    groups,
    hidden: [...hidden].map(([reason, source_keys]) => ({
      reason,
      source_keys,
    })),
    pending,
    legacy_aliases,
  };
}

/* ------------------------------------------------------------ ABV bands */

type AbvBand = { bounds: number[]; verified: boolean; source: string };

type AbvBands = {
  description: string;
  levels: string[];
  categories: Record<string, AbvBand>;
  styles: Record<string, AbvBand>;
};

function buildAbvBands(d: Dictionary): AbvBands {
  const bands = (type: string): Record<string, AbvBand> =>
    Object.fromEntries(
      terms(type).filter((t) => t.hints?.abv_bounds).map((t) => [t.key, {
        bounds: t.hints!.abv_bounds as number[],
        verified: t.hints!.abv_verified as boolean,
        source: t.hints!.abv_source as string,
      }]),
    );
  return {
    description: d.versions.abv_bands as string,
    levels: d.abv_levels,
    categories: bands("category"),
    styles: bands("kind"),
  };
}

/* ---------------------------------------------------- enrichment taxonomy */

type TaxonomyNamed = {
  name_ko: string;
  name_en: string;
  definition?: string;
  aliases?: string[];
  applies_to_categories?: string[] | string;
  [field: string]: unknown;
};
type TaxonomyKind = TaxonomyNamed & { key: string };
type TaxonomyCategory = {
  category_key: string;
  name_ko: string;
  name_en: string;
  sort_order: number;
};
type TaxonomyStyle = TaxonomyNamed & {
  style_key: string;
  category_key: string;
};
type TaxonomyIngredient = TaxonomyNamed & {
  ingredient_key: string;
  ingredient_type_key: string;
  parent_ingredient_key?: string;
};
type TaxonomyProductionTerm = TaxonomyNamed & {
  term_key: string;
  kind_key: string;
  process_stage: string;
  parent_term_key?: string;
  excludes_term_keys?: string[];
  applies_to_styles?: string[];
};
type TaxonomyDescriptor = TaxonomyNamed & {
  descriptor_key: string;
  descriptor_family: string;
  sensory_phases: string[];
  parent_descriptor_key?: string;
};
type TaxonomyDimension = {
  dimension_key: string;
  name_ko: string;
  name_en: string;
  definition: string;
  sensory_phase: string;
  minimum: number;
  maximum: number;
  unknown_allowed: boolean;
  supports_explicit_absence: boolean;
  applies_to_categories: string[] | string;
  bands: {
    band_key: string;
    name_ko: string;
    name_en: string;
    minimum: number;
    maximum: number;
  }[];
};
type Taxonomy = {
  $schema: string;
  taxonomy_version: string;
  base_taxonomy: Record<string, unknown>;
  ingredients: {
    types: TaxonomyKind[];
    roles: TaxonomyKind[];
    terms: TaxonomyIngredient[];
  };
  governance: Record<string, string>;
  source_mapping_policy: Record<string, unknown>;
  categories: TaxonomyCategory[];
  primary_styles: TaxonomyStyle[];
  sensory: {
    phase_keys: string[];
    descriptors: TaxonomyDescriptor[];
    scalar_dimensions: TaxonomyDimension[];
  };
  production: {
    process_kinds: TaxonomyKind[];
    process_terms: TaxonomyProductionTerm[];
    maturation_kinds: TaxonomyKind[];
    maturation_terms: TaxonomyProductionTerm[];
  };
  style_redirects: Record<string, string>;
};

const TERM_TAIL = [
  "parent_ingredient_key",
  "parent_term_key",
  "excludes_term_keys",
  "applies_to_styles",
];

/** One taxonomy item in its own field order; taxonomy-only fields come from extra.taxonomy. */
function taxonomyEntry(
  t: Term,
  fields: [string, unknown][],
): Record<string, unknown> {
  const rest = (t.extra?.taxonomy ?? {}) as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const [field, value] of fields) {
    if (value !== undefined && value !== null) out[field] = value;
    else if (field in rest) out[field] = rest[field];
  }
  return out;
}

function taxonomyTerm(
  t: Term,
  keyField: string,
  parentField?: string,
  middle: string[] = [],
): Record<string, unknown> {
  return taxonomyEntry(t, [
    [keyField, t.key],
    ...(parentField ? [[parentField, t.parent] as [string, unknown]] : []),
    ...middle.map((f): [string, unknown] => [f, undefined]),
    ["name_ko", t.names.ko],
    ["name_en", t.names.en],
    ["definition", t.definition_en],
    ["definition_source", undefined],
    ["source_standard_url", undefined],
    ["aliases", t.names.aliases ?? []],
    ["applies_to_categories", t.categories],
    ...TERM_TAIL.map((f): [string, unknown] => [f, undefined]),
  ]);
}

function buildTaxonomy(d: Dictionary): Taxonomy {
  const byKey = new Map(d.terms.map((t) => [`${t.type}:${t.key}`, t]));
  const kindsOnly = (type: string) =>
    terms(type).map((t) => taxonomyTerm(t, "key")) as TaxonomyKind[];
  const unplaced = new Map(
    d.unplaced_descriptors.map((x) => [x.descriptor_key, x]),
  );
  const descriptor = (key: string): TaxonomyDescriptor => {
    const t = ["aroma", "texture", "finish_character", "aroma_family"]
      .map((type) => byKey.get(`${type}:${key}`))
      .find((t) => t !== undefined)!;
    const x = t.extra!.taxonomy as Record<string, unknown>;
    const out: Record<string, unknown> = {
      descriptor_key: key,
      descriptor_family: x.descriptor_family,
      name_ko: x.name_ko,
      name_en: x.name_en,
      definition: t.definition_en,
    };
    for (
      const f of [
        "aliases",
        "sensory_phases",
        "applies_to_categories",
        "parent_descriptor_key",
      ]
    ) {
      if (f in x) out[f] = x[f];
    }
    return out as TaxonomyDescriptor;
  };
  const productionTerms = (type: string) =>
    terms(type).map((t) =>
      taxonomyTerm(t, "term_key", "kind_key", ["process_stage"])
    ) as TaxonomyProductionTerm[];
  const version = d.versions.taxonomy as { schema: string; version: string };
  return {
    $schema: version.schema,
    taxonomy_version: version.version,
    base_taxonomy: d.base_taxonomy,
    ingredients: {
      types: kindsOnly("ingredient_type"),
      roles: d.ingredient_roles,
      terms: terms("ingredient").map((t) =>
        taxonomyTerm(t, "ingredient_key", "ingredient_type_key")
      ) as TaxonomyIngredient[],
    },
    governance: d.governance,
    source_mapping_policy: d.source_mapping_policy,
    categories: terms("category").map((t) =>
      taxonomyEntry(t, [
        ["category_key", t.key],
        ["name_ko", t.names.ko],
        ["name_en", t.names.en],
        ["sort_order", undefined],
      ])
    ) as TaxonomyCategory[],
    primary_styles: d.taxonomy_order.kinds.map((k) =>
      taxonomyTerm(byKey.get(`kind:${k}`)!, "style_key", "category_key")
    ) as TaxonomyStyle[],
    sensory: {
      phase_keys: d.sensory_phases,
      descriptors: d.taxonomy_order.descriptors.map((k) =>
        unplaced.get(k) ?? descriptor(k)
      ),
      scalar_dimensions: terms("axis")
        .filter((t) => t.extra?.taxonomy !== undefined)
        .map((t) =>
          taxonomyEntry(t, [
            ["dimension_key", t.key],
            ["name_ko", t.names.ko],
            ["name_en", t.names.en],
            ["definition", t.definition_en],
            ...[
              "sensory_phase",
              "minimum",
              "maximum",
              "unknown_allowed",
              "supports_explicit_absence",
              "applies_to_categories",
              "bands",
            ].map((f): [string, unknown] => [f, undefined]),
          ])
        ) as TaxonomyDimension[],
    },
    production: {
      process_kinds: kindsOnly("process_kind"),
      process_terms: productionTerms("process"),
      maturation_kinds: kindsOnly("maturation_kind"),
      maturation_terms: productionTerms("maturation"),
    },
    style_redirects: d.style_redirects,
  };
}

/* ---------------------------------------------------------------- views */

export const styleProfiles: StyleProfiles = buildStyleProfiles(DICTIONARY);
export const sensoryCatalog: SensoryCatalog = buildSensoryCatalog(DICTIONARY);
export const termKnowledge: TermKnowledge = buildTermKnowledge(DICTIONARY);
export const serviceVocabulary: ServiceVocabulary = buildServiceVocabulary(
  DICTIONARY,
);
export const abvBands: AbvBands = buildAbvBands(DICTIONARY);
export const taxonomy: Taxonomy = buildTaxonomy(DICTIONARY);
