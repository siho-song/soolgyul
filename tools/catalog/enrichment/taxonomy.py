"""Load and validate the controlled Soolgyul enrichment taxonomy.

The taxonomy lives in the one dictionary (catalog/dictionary/terms.json); a
dictionary file is read through its taxonomy view, while a file already in
the registry shape (a test fixture) is read as it is.

The registry is intentionally stricter than a generic EAV dictionary.  This
module validates the JSON Schema, compatibility with the v1 catalog taxonomy,
database enum alignment, references, applicability, exclusions, and hierarchy
cycles before any downstream extractor or seed builder consumes the file.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from decimal import Decimal
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

try:
    from jsonschema import Draft202012Validator, FormatChecker
except ImportError:  # pragma: no cover - the repository test environment has it.
    Draft202012Validator = None  # type: ignore[assignment]
    FormatChecker = None  # type: ignore[assignment]


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_REGISTRY_PATH = REPOSITORY_ROOT / "catalog/dictionary/terms.json"
DEFAULT_SCHEMA_PATH = REPOSITORY_ROOT / "config/catalog/enrichment_taxonomy_v2.schema.json"
DEFAULT_BASE_TAXONOMY_PATH = REPOSITORY_ROOT / "config/catalog/taxonomy.json"

STABLE_KEY_PATTERN = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
DB_ALLOWED_TARGETS = {"product", "release", "both"}
DB_SELECTION_CARDINALITIES = {"single", "multiple"}
DB_DESCRIPTOR_FAMILIES = {
    "fruit",
    "floral",
    "herb",
    "spice",
    "grain",
    "roasted",
    "wood",
    "smoke",
    "fermentation",
    "earth",
    "mineral",
    "maritime",
    "sweet",
    "savory",
    "fresh",
    "texture",
    "finish",
    "other",
}
DB_INGREDIENT_TYPES = {"grape", "grain", "fruit", "botanical", "water", "additive", "other"}
DB_INGREDIENT_ROLES = {"base", "fermentable", "botanical", "additive", "water"}
DB_PROCESS_STAGES = {
    "preparation",
    "fermentation",
    "distillation",
    "maturation",
    "finishing",
    "blending",
    "filtration",
    "stabilization",
    "carbonation",
    "bottling",
    "other",
}
SENSORY_PHASES = {"aroma", "palate", "texture", "finish"}
SENSORY_VALUE_QUANTUM = Decimal("0.001")


class TaxonomyValidationError(ValueError):
    """Raised with all deterministic registry validation failures."""

    def __init__(self, errors: Sequence[str]) -> None:
        self.errors = tuple(errors)
        message = "enrichment taxonomy is invalid:\n- " + "\n- ".join(self.errors)
        super().__init__(message)


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise TaxonomyValidationError([f"missing JSON file: {path}"]) from error
    except json.JSONDecodeError as error:
        raise TaxonomyValidationError(
            [f"invalid JSON in {path}: line {error.lineno}, column {error.colno}: {error.msg}"]
        ) from error
    if not isinstance(value, dict):
        raise TaxonomyValidationError([f"JSON root must be an object: {path}"])
    return value


def _read_registry(path: Path) -> dict[str, Any]:
    value = _read_json(path)
    if "terms" in value and "primary_styles" not in value:
        from tools.catalog.dictionary.project import taxonomy

        return taxonomy(value)
    return value


def load_taxonomy_registry(path: str | Path = DEFAULT_REGISTRY_PATH) -> dict[str, Any]:
    """Load a registry without validating it, useful for explicit test mutation."""

    return _read_registry(Path(path))


def _normalise_text(value: str) -> str:
    # Match soolgyul_normalize_catalog_text: trim, collapse whitespace, lowercase.
    return " ".join(value.lower().split())


def _item_key(item: Mapping[str, Any], key_field: str) -> str:
    value = item.get(key_field)
    return value if isinstance(value, str) else repr(value)


def _check_unique_keys(
    items: Sequence[Mapping[str, Any]],
    key_field: str,
    namespace: str,
    errors: list[str],
) -> dict[str, Mapping[str, Any]]:
    result: dict[str, Mapping[str, Any]] = {}
    for index, item in enumerate(items):
        value = item.get(key_field)
        if not isinstance(value, str):
            errors.append(f"{namespace}[{index}].{key_field} must be a string")
            continue
        if value in result:
            errors.append(f"duplicate {namespace} {key_field}: {value}")
            continue
        result[value] = item
    return result


def _check_stable_keys(value: Any, path: str, errors: list[str]) -> None:
    if isinstance(value, Mapping):
        for field, child in value.items():
            child_path = f"{path}.{field}" if path else str(field)
            if (
                isinstance(field, str)
                and (field == "key" or field.endswith("_key"))
                and isinstance(child, str)
                and child != "all"
                and not STABLE_KEY_PATTERN.fullmatch(child)
            ):
                errors.append(f"invalid stable key at {child_path}: {child!r}")
            _check_stable_keys(child, child_path, errors)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _check_stable_keys(child, f"{path}[{index}]", errors)


def _category_set(
    value: Any,
    *,
    path: str,
    all_categories: set[str],
    errors: list[str],
) -> set[str]:
    if value == "all":
        return set(all_categories)
    if not isinstance(value, list) or not value:
        errors.append(f"{path} must be 'all' or a non-empty category-key list")
        return set()
    categories = {item for item in value if isinstance(item, str)}
    unknown = categories - all_categories
    if unknown:
        errors.append(f"{path} references unknown categories: {sorted(unknown)}")
    if len(categories) != len(value):
        errors.append(f"{path} contains duplicate or non-string category keys")
    return categories & all_categories


def _check_aliases(
    items: Sequence[Mapping[str, Any]],
    *,
    key_field: str,
    namespace: str,
    errors: list[str],
) -> None:
    claims: dict[str, str] = {}
    for item in items:
        key = _item_key(item, key_field)
        strings = [item.get("name_ko"), item.get("name_en"), *(item.get("aliases") or [])]
        seen_for_item: set[str] = set()
        for raw in strings:
            if not isinstance(raw, str) or not raw.strip():
                errors.append(f"{namespace}.{key} has an empty or non-string name/alias")
                continue
            normalised = _normalise_text(raw)
            if normalised in seen_for_item:
                errors.append(f"{namespace}.{key} repeats name/alias {raw!r}")
                continue
            seen_for_item.add(normalised)
            owner = claims.get(normalised)
            if owner is not None and owner != key:
                errors.append(
                    f"ambiguous name/alias in {namespace}: {raw!r} belongs to both {owner} and {key}"
                )
            else:
                claims[normalised] = key


def _check_cross_namespace_label_collisions(
    left_items: Sequence[Mapping[str, Any]],
    *,
    left_key_field: str,
    left_namespace: str,
    right_items: Sequence[Mapping[str, Any]],
    right_key_field: str,
    right_namespace: str,
    errors: list[str],
) -> None:
    """Keep a product-family label from also becoming a facet truth."""

    def claims(
        items: Sequence[Mapping[str, Any]], key_field: str
    ) -> dict[str, str]:
        result: dict[str, str] = {}
        for item in items:
            key = _item_key(item, key_field)
            values = [item.get("name_ko"), item.get("name_en"), *(item.get("aliases") or [])]
            for raw in values:
                if isinstance(raw, str) and raw.strip():
                    result.setdefault(_normalise_text(raw), key)
        return result

    left_claims = claims(left_items, left_key_field)
    right_claims = claims(right_items, right_key_field)
    for normalised in sorted(left_claims.keys() & right_claims.keys()):
        errors.append(
            "normalized label/alias collision between "
            f"{left_namespace}.{left_claims[normalised]} and "
            f"{right_namespace}.{right_claims[normalised]}: {normalised!r}"
        )


def _check_graph(
    items: Sequence[Mapping[str, Any]],
    *,
    key_field: str,
    parent_field: str,
    namespace: str,
    errors: list[str],
    same_group_field: str | None = None,
) -> None:
    by_key = _check_unique_keys(items, key_field, namespace, errors)
    parents: dict[str, str] = {}
    for key, item in by_key.items():
        parent = item.get(parent_field)
        if parent is None:
            continue
        if not isinstance(parent, str) or parent not in by_key:
            errors.append(f"{namespace}.{key}.{parent_field} references unknown key: {parent!r}")
            continue
        if parent == key:
            errors.append(f"{namespace}.{key} cannot be its own parent")
            continue
        if same_group_field and item.get(same_group_field) != by_key[parent].get(same_group_field):
            errors.append(
                f"{namespace}.{key} and parent {parent} must share {same_group_field}"
            )
        parents[key] = parent

    for start in parents:
        chain: list[str] = []
        positions: dict[str, int] = {}
        cursor = start
        while cursor in parents:
            if cursor in positions:
                cycle = chain[positions[cursor] :] + [cursor]
                errors.append(f"cycle in {namespace}: {' -> '.join(cycle)}")
                break
            positions[cursor] = len(chain)
            chain.append(cursor)
            cursor = parents[cursor]


def _check_exclusions(
    items: Sequence[Mapping[str, Any]],
    *,
    key_field: str,
    exclusion_field: str,
    namespace: str,
    errors: list[str],
) -> None:
    keys = {item.get(key_field) for item in items if isinstance(item.get(key_field), str)}
    for item in items:
        key = item.get(key_field)
        exclusions = item.get(exclusion_field, [])
        if not isinstance(exclusions, list):
            errors.append(f"{namespace}.{key}.{exclusion_field} must be a list")
            continue
        for excluded in exclusions:
            if excluded == key:
                errors.append(f"{namespace}.{key} cannot exclude itself")
            elif excluded not in keys:
                errors.append(
                    f"{namespace}.{key}.{exclusion_field} references unknown key: {excluded!r}"
                )


def _check_source_metadata(
    items: Iterable[Mapping[str, Any]], namespace: str, errors: list[str]
) -> None:
    for item in items:
        definition_source = item.get("definition_source")
        source_url = item.get("source_standard_url")
        if (definition_source is None) != (source_url is None):
            key = next(
                (
                    value
                    for field, value in item.items()
                    if field.endswith("_key") and isinstance(value, str)
                ),
                "unknown",
            )
            errors.append(
                f"{namespace}.{key} must provide definition_source and source_standard_url together"
            )


def _schema_errors(registry: Mapping[str, Any], schema: Mapping[str, Any]) -> list[str]:
    if Draft202012Validator is None or FormatChecker is None:
        return [
            "jsonschema with Draft 2020-12 format validation is required; "
            "taxonomy validation fails closed without it"
        ]
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = []
    for failure in sorted(validator.iter_errors(registry), key=lambda error: list(error.absolute_path)):
        location = "/".join(str(part) for part in failure.absolute_path) or "<root>"
        errors.append(f"schema {location}: {failure.message}")
    return errors


def validate_taxonomy_registry(
    registry: Mapping[str, Any],
    *,
    base_taxonomy: Mapping[str, Any],
    schema: Mapping[str, Any],
) -> dict[str, int]:
    """Validate the registry and return deterministic collection counts."""

    errors = _schema_errors(registry, schema)
    if errors:
        raise TaxonomyValidationError(errors)

    _check_stable_keys(registry, "", errors)

    categories = registry["categories"]
    category_map = _check_unique_keys(categories, "category_key", "categories", errors)
    category_keys = set(category_map)
    if len({category["sort_order"] for category in categories}) != len(categories):
        errors.append("categories.sort_order values must be unique")

    base_categories = base_taxonomy.get("categories", [])
    base_category_map = {category.get("category_key"): category for category in base_categories}
    if registry["base_taxonomy"]["taxonomy_version"] != base_taxonomy.get("taxonomy_version"):
        errors.append("base_taxonomy.taxonomy_version does not match config/catalog/taxonomy.json")
    if registry["base_taxonomy"]["style_relationship"] != "required_compatibility_subset":
        errors.append(
            "base_taxonomy.style_relationship must declare the legacy style registry as a required compatibility subset"
        )
    if registry["base_taxonomy"]["required_category_keys"] != [
        category.get("category_key") for category in base_categories
    ]:
        errors.append("base_taxonomy.required_category_keys must exactly preserve v1 category order")
    if category_keys != set(base_category_map):
        errors.append("categories must exactly preserve all v1 category keys")
    for key, base_category in base_category_map.items():
        category = category_map.get(key)
        if category is not None and dict(category) != dict(base_category):
            errors.append(f"category compatibility drift for {key}")

    styles = registry["primary_styles"]
    style_map = _check_unique_keys(styles, "style_key", "primary_styles", errors)
    for old, target in registry.get("style_redirects", {}).items():
        if old in style_map or target not in style_map:
            errors.append(f"invalid style redirect: {old} -> {target}")
    _check_aliases(styles, key_field="style_key", namespace="primary_styles", errors=errors)
    _check_source_metadata(styles, "primary_styles", errors)
    styles_by_category: dict[str, int] = defaultdict(int)
    for style in styles:
        key = style["style_key"]
        category = style["category_key"]
        applies = _category_set(
            style["applies_to_categories"],
            path=f"primary_styles.{key}.applies_to_categories",
            all_categories=category_keys,
            errors=errors,
        )
        if category not in category_keys:
            errors.append(f"primary_styles.{key} references unknown category_key: {category}")
        elif applies != {category}:
            errors.append(f"primary_styles.{key} must apply only to its category_key {category}")
        styles_by_category[category] += 1
    missing_style_categories = category_keys - set(styles_by_category)
    if missing_style_categories:
        errors.append(f"categories without a primary style: {sorted(missing_style_categories)}")

    base_styles = base_taxonomy.get("styles", [])
    expected_base_style_keys = [style.get("style_key") for style in base_styles]
    if registry["base_taxonomy"]["required_style_keys"] != expected_base_style_keys:
        errors.append("base_taxonomy.required_style_keys must exactly preserve v1 style order")
    if not set(expected_base_style_keys) < set(style_map):
        errors.append(
            "base taxonomy styles must be a strict compatibility subset of enrichment primary styles"
        )
    for base_style in base_styles:
        key = base_style["style_key"]
        current = style_map.get(key)
        if current is None:
            errors.append(f"missing v1-compatible primary style: {key}")
            continue
        for field in ("category_key", "name_ko", "name_en"):
            if current.get(field) != base_style.get(field):
                if field != "category_key" and _normalise_text(base_style[field]) in {
                    _normalise_text(alias) for alias in current.get("aliases", [])
                }:
                    continue
                errors.append(f"primary style compatibility drift for {key}.{field}")

    phases = set(registry["sensory"]["phase_keys"])
    if phases != SENSORY_PHASES:
        errors.append(f"sensory.phase_keys must exactly equal {sorted(SENSORY_PHASES)}")
    descriptors = registry["sensory"]["descriptors"]
    descriptor_map = _check_unique_keys(descriptors, "descriptor_key", "sensory.descriptors", errors)
    _check_aliases(
        descriptors,
        key_field="descriptor_key",
        namespace="sensory.descriptors",
        errors=errors,
    )
    _check_graph(
        descriptors,
        key_field="descriptor_key",
        parent_field="parent_descriptor_key",
        namespace="sensory.descriptors",
        same_group_field="descriptor_family",
        errors=errors,
    )
    _check_exclusions(
        descriptors,
        key_field="descriptor_key",
        exclusion_field="excludes_descriptor_keys",
        namespace="sensory.descriptors",
        errors=errors,
    )
    for descriptor_key, descriptor in descriptor_map.items():
        if descriptor["descriptor_family"] not in DB_DESCRIPTOR_FAMILIES:
            errors.append(f"sensory.descriptors.{descriptor_key} has non-DB descriptor_family")
        _category_set(
            descriptor["applies_to_categories"],
            path=f"sensory.descriptors.{descriptor_key}.applies_to_categories",
            all_categories=category_keys,
            errors=errors,
        )
        if not set(descriptor["sensory_phases"]) <= phases:
            errors.append(f"sensory.descriptors.{descriptor_key} has an unknown sensory phase")

    dimensions = registry["sensory"]["scalar_dimensions"]
    dimension_map = _check_unique_keys(
        dimensions, "dimension_key", "sensory.scalar_dimensions", errors
    )
    for dimension_key, dimension in dimension_map.items():
        minimum = dimension["minimum"]
        maximum = dimension["maximum"]
        if minimum != 0 or maximum != 1:
            errors.append(
                f"sensory.scalar_dimensions.{dimension_key} must use the DB-normalized 0..1 scale"
            )
        if minimum >= maximum:
            errors.append(f"sensory.scalar_dimensions.{dimension_key} minimum must be < maximum")
        _category_set(
            dimension["applies_to_categories"],
            path=f"sensory.scalar_dimensions.{dimension_key}.applies_to_categories",
            all_categories=category_keys,
            errors=errors,
        )
        band_keys: set[str] = set()
        previous_max: float | int | None = None
        for index, band in enumerate(dimension["bands"]):
            key = band["band_key"]
            if key in band_keys:
                errors.append(f"sensory.scalar_dimensions.{dimension_key} repeats band {key}")
            band_keys.add(key)
            if band["minimum"] >= band["maximum"]:
                errors.append(
                    f"sensory.scalar_dimensions.{dimension_key}.bands[{index}] minimum must be < maximum"
                )
            for boundary_name in ("minimum", "maximum"):
                boundary = Decimal(str(band[boundary_name]))
                if boundary != boundary.quantize(SENSORY_VALUE_QUANTUM):
                    errors.append(
                        f"sensory.scalar_dimensions.{dimension_key}.bands[{index}]."
                        f"{boundary_name} must use at most three decimal places"
                    )
            if index == 0 and band["minimum"] != minimum:
                errors.append(f"sensory.scalar_dimensions.{dimension_key} bands must start at minimum")
            if previous_max is not None and band["minimum"] != previous_max:
                errors.append(f"sensory.scalar_dimensions.{dimension_key} bands must be contiguous")
            previous_max = band["maximum"]
        if previous_max != maximum:
            errors.append(f"sensory.scalar_dimensions.{dimension_key} bands must end at maximum")

    ingredient_types = registry["ingredients"]["types"]
    ingredient_type_map = _check_unique_keys(ingredient_types, "key", "ingredients.types", errors)
    _check_aliases(
        ingredient_types,
        key_field="key",
        namespace="ingredients.types",
        errors=errors,
    )
    if set(ingredient_type_map) != DB_INGREDIENT_TYPES:
        errors.append(
            "ingredients.types keys must exactly match DB enum: "
            f"{sorted(DB_INGREDIENT_TYPES)}"
        )
    ingredient_roles = registry["ingredients"]["roles"]
    ingredient_role_map = _check_unique_keys(ingredient_roles, "key", "ingredients.roles", errors)
    _check_aliases(
        ingredient_roles,
        key_field="key",
        namespace="ingredients.roles",
        errors=errors,
    )
    if set(ingredient_role_map) != DB_INGREDIENT_ROLES:
        errors.append(
            "ingredients.roles keys must exactly match DB enum: "
            f"{sorted(DB_INGREDIENT_ROLES)}"
        )
    ingredients = registry["ingredients"]["terms"]
    ingredient_map = _check_unique_keys(ingredients, "ingredient_key", "ingredients.terms", errors)
    _check_aliases(
        ingredients,
        key_field="ingredient_key",
        namespace="ingredients.terms",
        errors=errors,
    )
    _check_graph(
        ingredients,
        key_field="ingredient_key",
        parent_field="parent_ingredient_key",
        namespace="ingredients.terms",
        same_group_field="ingredient_type_key",
        errors=errors,
    )
    for ingredient_key, ingredient in ingredient_map.items():
        if ingredient["ingredient_type_key"] not in ingredient_type_map:
            errors.append(
                f"ingredients.terms.{ingredient_key} references unknown ingredient_type_key"
            )
        _category_set(
            ingredient["applies_to_categories"],
            path=f"ingredients.terms.{ingredient_key}.applies_to_categories",
            all_categories=category_keys,
            errors=errors,
        )

    process_kinds = registry["production"]["process_kinds"]
    process_kind_map = _check_unique_keys(
        process_kinds, "key", "production.process_kinds", errors
    )
    if set(process_kind_map) != DB_PROCESS_STAGES:
        errors.append(
            "production.process_kinds keys must exactly match DB process_stage enum: "
            f"{sorted(DB_PROCESS_STAGES)}"
        )
    maturation_kinds = registry["production"]["maturation_kinds"]
    maturation_kind_map = _check_unique_keys(
        maturation_kinds, "key", "production.maturation_kinds", errors
    )
    all_production_kinds = [*process_kinds, *maturation_kinds]
    _check_unique_keys(
        all_production_kinds,
        "key",
        "production.kinds(global)",
        errors,
    )
    _check_aliases(
        all_production_kinds,
        key_field="key",
        namespace="production.kinds(global)",
        errors=errors,
    )
    process_terms = registry["production"]["process_terms"]
    maturation_terms = registry["production"]["maturation_terms"]
    _check_unique_keys(
        [*process_terms, *maturation_terms],
        "term_key",
        "production.terms(global)",
        errors,
    )
    _check_aliases(
        [*process_terms, *maturation_terms],
        key_field="term_key",
        namespace="production.terms(global)",
        errors=errors,
    )
    _check_graph(
        process_terms,
        key_field="term_key",
        parent_field="parent_term_key",
        namespace="production.process_terms",
        same_group_field="process_stage",
        errors=errors,
    )
    _check_graph(
        maturation_terms,
        key_field="term_key",
        parent_field="parent_term_key",
        namespace="production.maturation_terms",
        same_group_field="process_stage",
        errors=errors,
    )
    for namespace, terms, kinds, require_same_stage in (
        ("production.process_terms", process_terms, process_kind_map, True),
        ("production.maturation_terms", maturation_terms, maturation_kind_map, False),
    ):
        _check_exclusions(
            terms,
            key_field="term_key",
            exclusion_field="excludes_term_keys",
            namespace=namespace,
            errors=errors,
        )
        for term in terms:
            key = term["term_key"]
            if term["kind_key"] not in kinds:
                errors.append(f"{namespace}.{key} references unknown kind_key")
            if term["process_stage"] not in DB_PROCESS_STAGES:
                errors.append(f"{namespace}.{key} has non-DB process_stage")
            if require_same_stage and term["kind_key"] != term["process_stage"]:
                errors.append(f"{namespace}.{key} kind_key must equal DB process_stage")
            if namespace == "production.maturation_terms" and term["process_stage"] != "maturation":
                errors.append(
                    f"{namespace}.{key} process_stage must be maturation for the shared kind FK"
                )
            _category_set(
                term["applies_to_categories"],
                path=f"{namespace}.{key}.applies_to_categories",
                all_categories=category_keys,
                errors=errors,
            )

    mapping_policy = registry["source_mapping_policy"]
    for index, exclusion in enumerate(mapping_policy["exclusions"]):
        try:
            re.compile(exclusion["label_pattern"], flags=re.IGNORECASE)
        except re.error as error:
            errors.append(f"source_mapping_policy.exclusions[{index}] invalid regex: {error}")
    for index, redirect in enumerate(mapping_policy["redirects"]):
        for field in ("parent_label_pattern", "label_pattern"):
            try:
                re.compile(redirect[field], flags=re.IGNORECASE)
            except re.error as error:
                errors.append(
                    f"source_mapping_policy.redirects[{index}].{field} invalid regex: {error}"
                )
        if redirect["target_category_key"] not in category_keys:
            errors.append(
                f"source_mapping_policy.redirects[{index}] references unknown target category"
            )

    if errors:
        raise TaxonomyValidationError(sorted(set(errors)))

    return {
        "categories": len(categories),
        "primary_styles": len(styles),
        "sensory_descriptors": len(descriptors),
        "scalar_dimensions": len(dimensions),
        "ingredient_terms": len(ingredients),
        "process_terms": len(process_terms),
        "maturation_terms": len(maturation_terms),
    }


def load_and_validate_taxonomy(
    registry_path: str | Path = DEFAULT_REGISTRY_PATH,
    *,
    schema_path: str | Path = DEFAULT_SCHEMA_PATH,
    base_taxonomy_path: str | Path | None = None,
) -> tuple[dict[str, Any], dict[str, int]]:
    """Load the registry, schema and v1 taxonomy, then validate all contracts."""

    registry_path = Path(registry_path)
    registry = _read_registry(registry_path)
    schema = _read_json(Path(schema_path))

    declared_base = registry.get("base_taxonomy", {}).get("path")
    if base_taxonomy_path is None:
        if isinstance(declared_base, str):
            candidate = Path(declared_base)
            base_taxonomy_path = candidate if candidate.is_absolute() else REPOSITORY_ROOT / candidate
        else:
            base_taxonomy_path = DEFAULT_BASE_TAXONOMY_PATH
    base_taxonomy = _read_json(Path(base_taxonomy_path))
    summary = validate_taxonomy_registry(
        registry,
        base_taxonomy=base_taxonomy,
        schema=schema,
    )
    return registry, summary


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY_PATH)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA_PATH)
    parser.add_argument("--base-taxonomy", type=Path, default=None)
    parser.add_argument("--json", action="store_true", dest="as_json")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        _, summary = load_and_validate_taxonomy(
            args.registry,
            schema_path=args.schema,
            base_taxonomy_path=args.base_taxonomy,
        )
    except TaxonomyValidationError as error:
        print(str(error), file=sys.stderr)
        return 1

    payload = {
        "status": "valid",
        "taxonomy_version": load_taxonomy_registry(args.registry)["taxonomy_version"],
        **summary,
    }
    if args.as_json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    else:
        print(f"enrichment taxonomy {payload['taxonomy_version']} is valid")
        for key, value in summary.items():
            print(f"{key}: {value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
