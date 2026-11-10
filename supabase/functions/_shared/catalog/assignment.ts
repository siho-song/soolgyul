import contract from "./assignment_contract.json" with { type: "json" };
import {
  CatalogCategoryKey,
  CatalogIngredientKey,
  CatalogProcessKey,
  CatalogStyleKey,
} from "./assignment_keys.g.ts";
export {
  CatalogCategoryKey,
  CatalogIngredientKey,
  CatalogProcessKey,
  CatalogStyleKey,
} from "./assignment_keys.g.ts";

export enum AssignmentTarget {
  Product = "product",
  Release = "release",
}
enum CatalogTermKind {
  Style = "style",
  Ingredient = "ingredient",
  Process = "process",
  Maturation = "maturation",
}
type AssignmentIssue = Readonly<
  { code: string; field: string; key: string }
>;
type Rule = Readonly<{
  kind: string;
  key: string;
  categories: readonly string[];
  styles: readonly string[];
  target: string;
  excludes: readonly string[];
}>;
type Contract = {
  schema_version: number;
  categories: readonly string[];
  terms: readonly Rule[];
};
const fields = ["ingredient_keys", "production_process_keys"] as const;
type AssignmentField = typeof fields[number];
const kinds: Record<AssignmentField, readonly string[]> = {
  ingredient_keys: [CatalogTermKind.Ingredient],
  production_process_keys: [
    CatalogTermKind.Process,
    CatalogTermKind.Maturation,
  ],
};
const token = Symbol("validated catalog assignment");
type AssignmentValues = {
  ingredient_keys: readonly CatalogIngredientKey[];
  production_process_keys: readonly CatalogProcessKey[];
};
const categoryEnumKeys = new Set<string>(Object.values(CatalogCategoryKey));
const termEnumKeys: Record<string, ReadonlySet<string>> = {
  style: new Set(Object.values(CatalogStyleKey)),
  ingredient: new Set(Object.values(CatalogIngredientKey)),
  process: new Set(Object.values(CatalogProcessKey)),
  maturation: new Set(Object.values(CatalogProcessKey)),
};

/** Immutable value object. Construction requires successful runtime validation. */
export class CatalogAssignment {
  readonly categoryKey: CatalogCategoryKey;
  readonly styleKey: CatalogStyleKey | null;
  readonly target: AssignmentTarget;
  readonly values: Readonly<AssignmentValues>;
  constructor(
    proof: symbol,
    category: CatalogCategoryKey,
    style: CatalogStyleKey | null,
    target: AssignmentTarget,
    values: Record<AssignmentField, string[]>,
  ) {
    if (proof !== token) {
      throw new TypeError("Use catalogAssignments.validate()");
    }
    this.categoryKey = category;
    this.styleKey = style;
    this.target = target;
    this.values = Object.freeze(
      Object.fromEntries(
        fields.map((f) => [f, Object.freeze([...values[f]])]),
      ) as AssignmentValues,
    );
    Object.freeze(this);
  }
}

class AssignmentRegistry {
  private readonly categories: ReadonlySet<string>;
  private readonly rules = new Map<string, Rule>();
  constructor(source: Contract) {
    if (source.schema_version !== 2) {
      throw new TypeError("Unsupported assignment contract");
    }
    this.categories = new Set(source.categories);
    if (source.categories.some((k) => !categoryEnumKeys.has(k))) {
      throw new TypeError("Category enum/contract mismatch; regenerate");
    }
    for (const row of source.terms) {
      const identity = `${row.kind}:${row.key}`;
      if (
        !termEnumKeys[row.kind]?.has(row.key) || this.rules.has(identity) ||
        !Object.values(CatalogTermKind).includes(row.kind as CatalogTermKind) ||
        !["product", "release", "both"].includes(row.target) ||
        !row.categories.length || row.categories.some((c) =>
          !this.categories.has(c)
        )
      ) {
        throw new TypeError(`Invalid assignment rule: ${identity}`);
      }
      this.rules.set(
        identity,
        Object.freeze({
          ...row,
          categories: Object.freeze([...row.categories]),
          styles: Object.freeze([...row.styles]),
          excludes: Object.freeze([...row.excludes]),
        }),
      );
    }
  }

  validate(
    raw: Record<string, unknown>,
  ): Readonly<
    { value: CatalogAssignment | null; issues: readonly AssignmentIssue[] }
  > {
    const issues: AssignmentIssue[] = [];
    const issue = (code: string, field: string, key = "") =>
      issues.push({ code, field, key });
    const category = raw.category_key;
    const style = raw.style_key ?? null;
    let target = Object.hasOwn(raw, "target")
      ? raw.target
      : AssignmentTarget.Product;
    if (
      target !== AssignmentTarget.Product && target !== AssignmentTarget.Release
    ) {
      issue("invalid_target", "target");
      target = AssignmentTarget.Product;
    }
    if (typeof category !== "string" || !this.categories.has(category)) {
      issue("unknown_category", "category_key");
    }
    const check = (rule: Rule, field: string) => {
      if (!rule.categories.includes(category as string)) {
        issue("wrong_category", field, rule.key);
      }
      if (rule.styles.length && !rule.styles.includes(style as string)) {
        issue("wrong_style", field, rule.key);
      }
      if (rule.target !== "both" && rule.target !== target) {
        issue("wrong_target", field, rule.key);
      }
    };
    if (style !== null) {
      const rule = typeof style === "string"
        ? this.rules.get(`style:${style}`)
        : undefined;
      if (!rule) {
        issue(
          "unknown_term",
          "style_key",
          typeof style === "string" ? style : "",
        );
      } else check(rule, "style_key");
    }
    const arrays = {} as Record<AssignmentField, string[]>;
    for (const field of fields) {
      const values = Object.hasOwn(raw, field) ? raw[field] : [];
      arrays[field] = [];
      if (!Array.isArray(values)) {
        issue("invalid_array", field);
        continue;
      }
      if (values.length > 64) issue("too_many_terms", field);
      const seen = new Set<string>();
      const selected: Rule[] = [];
      for (const key of values) {
        if (
          typeof key !== "string" || key.trim() !== key ||
          !/^[a-z][a-z0-9_]*$/.test(key)
        ) {
          issue("invalid_key", field);
          continue;
        }
        if (seen.has(key)) issue("duplicate_term", field, key);
        seen.add(key);
        const matches = kinds[field].flatMap((kind) => {
          const r = this.rules.get(`${kind}:${key}`);
          return r ? [r] : [];
        });
        if (matches.length !== 1) {
          issue(matches.length ? "ambiguous_term" : "unknown_term", field, key);
          continue;
        }
        check(matches[0], field);
        selected.push(matches[0]);
      }
      arrays[field] = [...seen].sort();
      for (const rule of selected) {
        if (rule.excludes.some((k) => seen.has(k))) {
          issue("excluded_combination", field, rule.key);
        }
      }
    }
    const unique = [
      ...new Map(
        issues.map((i) => [`${i.code}:${i.field}:${i.key}`, Object.freeze(i)]),
      ).values(),
    ]
      .sort((a, b) =>
        a.code.localeCompare(b.code) || a.field.localeCompare(b.field) ||
        a.key.localeCompare(b.key)
      );
    return Object.freeze({
      value: unique.length ? null : new CatalogAssignment(
        token,
        category as CatalogCategoryKey,
        style as CatalogStyleKey | null,
        target as AssignmentTarget,
        arrays,
      ),
      issues: Object.freeze(unique),
    });
  }
}

export const catalogAssignments = new AssignmentRegistry(contract);
