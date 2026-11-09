"""Materialize the approved enrichment taxonomy into one catalog term surface.

This module is deliberately local-only. It validates the repository taxonomy,
normalizes every serving term, and can render deterministic JSONL, SQL or the
CI fixture for ``public.catalog_taxonomy`` without contacting Supabase.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import unicodedata
from typing import Any, Mapping, Sequence

from tools.catalog.enrichment.taxonomy import (
    DEFAULT_REGISTRY_PATH,
    DEFAULT_SCHEMA_PATH,
    TaxonomyValidationError,
    load_and_validate_taxonomy,
)
from tools.catalog.support import canonical_json, jsonl_bytes


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUTPUT_PATH = ROOT / "supabase/seeds/catalog_taxonomy.sql"

TERM_TYPES = (
    "style",
    "ingredient",
    "process",
    "maturation",
    "sensory_descriptor",
    "region",
)
SECTION_BY_TERM_TYPE = {
    "style": ("style",),
    "ingredient": ("ingredient",),
    "process": ("production",),
    "maturation": ("maturation",),
}


class CatalogTermMaterializationError(ValueError):
    """The taxonomy cannot be represented by the catalog_taxonomy contract."""


def _repository_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return str(path)


def _source_sha256(path: Path) -> str:
    """Hash JSON source text independently of Git checkout line endings."""

    normalized_text = path.read_text(encoding="utf-8")
    return hashlib.sha256(normalized_text.encode("utf-8")).hexdigest()


def _normalized_text(value: Any, *, location: str, optional: bool = False) -> str | None:
    if value is None and optional:
        return None
    if not isinstance(value, str) or not value.strip():
        raise CatalogTermMaterializationError(f"{location} must be a non-empty string")
    return unicodedata.normalize("NFC", " ".join(value.split()))


def _stable_strings(values: Any, *, location: str) -> list[str]:
    if not isinstance(values, (list, tuple)):
        raise CatalogTermMaterializationError(f"{location} must be an array")
    normalized: dict[str, str] = {}
    for index, value in enumerate(values):
        text = _normalized_text(value, location=f"{location}[{index}]")
        assert text is not None
        identity = text.casefold()
        if identity in normalized:
            raise CatalogTermMaterializationError(
                f"{location} contains a normalized duplicate: {text}"
            )
        normalized[identity] = text
    return [normalized[key] for key in sorted(normalized)]


def _metadata(value: Any, *, location: str) -> Any:
    """Normalize JSON metadata while treating string arrays as set-like values."""

    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        return _normalized_text(value, location=location)
    if isinstance(value, Mapping):
        result: dict[str, Any] = {}
        for key in sorted(value):
            if not isinstance(key, str) or not key:
                raise CatalogTermMaterializationError(
                    f"{location} contains an invalid object key"
                )
            result[key] = _metadata(value[key], location=f"{location}.{key}")
        return result
    if isinstance(value, (list, tuple)):
        if all(isinstance(item, str) for item in value):
            return _stable_strings(value, location=location)
        return [
            _metadata(item, location=f"{location}[{index}]")
            for index, item in enumerate(value)
        ]
    raise CatalogTermMaterializationError(
        f"{location} contains a non-JSON value: {type(value).__name__}"
    )


def _category_applicability(value: Any, categories: Sequence[str], *, location: str) -> list[str]:
    if value == "all":
        return sorted(categories)
    return _stable_strings(value, location=location)


def _row(
    *,
    term_type: str,
    term_key: Any,
    source: Mapping[str, Any],
    key_field: str,
    parent_term_key: str | None,
    applicable_sections: Sequence[str],
    metadata: Mapping[str, Any],
    taxonomy_version: str,
    sort_order: int,
) -> dict[str, Any]:
    key = _normalized_text(term_key, location=f"{term_type}.{key_field}")
    label_ko = _normalized_text(
        source.get("name_ko"), location=f"{term_type}.{key}.name_ko"
    )
    label_en = _normalized_text(
        source.get("name_en"),
        location=f"{term_type}.{key}.name_en",
        optional=True,
    )
    aliases = _stable_strings(
        source.get("aliases", []), location=f"{term_type}.{key}.aliases"
    )
    canonical_identities = {
        value.casefold() for value in (label_ko, label_en) if value is not None
    }
    duplicate_labels = [value for value in aliases if value.casefold() in canonical_identities]
    if duplicate_labels:
        raise CatalogTermMaterializationError(
            f"{term_type}.{key}.aliases repeat canonical labels: {duplicate_labels}"
        )

    return {
        "term_type": term_type,
        "term_key": key,
        "label_ko": label_ko,
        "label_en": label_en,
        "synonyms": aliases,
        "parent_term_key": parent_term_key,
        "applicable_sections": _stable_strings(
            applicable_sections,
            location=f"{term_type}.{key}.applicable_sections",
        ),
        "metadata": _metadata(metadata, location=f"{term_type}.{key}.metadata"),
        "taxonomy_version": taxonomy_version,
        "sort_order": sort_order,
        "is_active": True,
    }


def region_rows() -> list[dict[str, Any]]:
    """The dictionary's region tree: country rows (ISO code, lower case) at the
    root, every other row linked to the one above by parent_term_key."""
    from tools.catalog.dictionary import project as dictionary

    rows: list[dict[str, Any]] = []
    regions = [t for t in dictionary.load()["terms"] if t["type"] == "region"]
    for position, term in enumerate(regions, start=1):
        names = term["names"]
        rows.append(
            _row(
                term_type="region",
                term_key=term["key"],
                source={
                    "name_ko": names["ko"],
                    "name_en": names.get("en"),
                    "aliases": names.get("aliases", []),
                },
                key_field="key",
                parent_term_key=term.get("parent"),
                applicable_sections=["region"],
                metadata={},
                taxonomy_version="2.0.0",
                sort_order=position * 10,
            )
        )
    return rows


def materialize_catalog_terms(
    registry_path: str | Path = DEFAULT_REGISTRY_PATH,
    *,
    schema_path: str | Path = DEFAULT_SCHEMA_PATH,
    base_taxonomy_path: str | Path | None = None,
) -> list[dict[str, Any]]:
    """Return all service terms with unique ``(term_type, term_key)`` identities."""

    registry, summary = load_and_validate_taxonomy(
        registry_path,
        schema_path=schema_path,
        base_taxonomy_path=base_taxonomy_path,
    )
    taxonomy_version = _normalized_text(
        registry.get("taxonomy_version"), location="taxonomy_version"
    )
    assert taxonomy_version is not None
    categories = [str(row["category_key"]) for row in registry["categories"]]
    rows: list[dict[str, Any]] = []

    collection_specs: tuple[tuple[str, Sequence[Mapping[str, Any]], str], ...] = (
        ("style", registry["primary_styles"], "style_key"),
        ("ingredient", registry["ingredients"]["terms"], "ingredient_key"),
        ("process", registry["production"]["process_terms"], "term_key"),
        ("maturation", registry["production"]["maturation_terms"], "term_key"),
        ("sensory_descriptor", registry["sensory"]["descriptors"], "descriptor_key"),
    )
    for term_type, collection, key_field in collection_specs:
        for position, source in enumerate(collection, start=1):
            key = str(source[key_field])
            if term_type == "ingredient":
                parent_key = source.get("parent_ingredient_key")
            elif term_type == "sensory_descriptor":
                parent_key = source.get("parent_descriptor_key")
            elif term_type == "maturation":
                parent_key = source.get("parent_term_key")
            else:
                parent_key = None

            if term_type == "sensory_descriptor":
                sections = source["sensory_phases"]
            else:
                sections = SECTION_BY_TERM_TYPE[term_type]

            excluded_fields = {
                key_field,
                "name_ko",
                "name_en",
                "aliases",
                "parent_ingredient_key",
                "parent_descriptor_key",
                "parent_term_key",
                "sensory_phases",
                "section_type",
                "applies_to_categories",
            }
            metadata = {
                field: value
                for field, value in source.items()
                if field not in excluded_fields
            }
            metadata["applies_to_categories"] = _category_applicability(
                source["applies_to_categories"],
                categories,
                location=f"{term_type}.{key}.applies_to_categories",
            )

            rows.append(
                _row(
                    term_type=term_type,
                    term_key=key,
                    source=source,
                    key_field=key_field,
                    parent_term_key=(
                        _normalized_text(
                            parent_key,
                            location=f"{term_type}.{key}.parent_term_key",
                            optional=True,
                        )
                    ),
                    applicable_sections=sections,
                    metadata=metadata,
                    taxonomy_version=taxonomy_version,
                    sort_order=position * 10,
                )
            )

    expected_counts = {
        "style": summary["primary_styles"],
        "ingredient": summary["ingredient_terms"],
        "process": summary["process_terms"],
        "maturation": summary["maturation_terms"],
        "sensory_descriptor": summary["sensory_descriptors"],
    }
    actual_counts = {
        term_type: sum(row["term_type"] == term_type for row in rows)
        for term_type in expected_counts
    }
    if actual_counts != expected_counts:
        raise CatalogTermMaterializationError(
            f"term projection is incomplete: expected={expected_counts}, actual={actual_counts}"
        )

    identities: set[tuple[str, str]] = set()
    # ADR-113: the legacy taxonomy remains a collection/source registry. Never
    # resurrect its old sensory labels when rebuilding the current service seed.
    from tools.catalog.normalization.sensory_service_vocabulary import project_service_terms

    rows = [row for row in rows if row["term_type"] != "sensory_descriptor"]
    rows.extend(project_service_terms())
    rows.extend(region_rows())
    for row in rows:
        identity = (str(row["term_type"]), str(row["term_key"]))
        if identity in identities:
            raise CatalogTermMaterializationError(
                f"duplicate catalog term identity: {identity}"
            )
        identities.add(identity)
    for row in rows:
        parent_key = row["parent_term_key"]
        if parent_key is not None and (row["term_type"], parent_key) not in identities:
            raise CatalogTermMaterializationError(
                "catalog term parent is missing from the same type: "
                f"{row['term_type']}.{row['term_key']} -> {parent_key}"
            )

    return sorted(
        rows,
        key=lambda row: (
            TERM_TYPES.index(row["term_type"]),
            row["sort_order"],
            row["term_key"],
        ),
    )


def _sql_literal(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if not isinstance(value, str):
        raise TypeError(f"unsupported SQL literal type: {type(value).__name__}")
    return "'" + value.replace("'", "''") + "'"


def _sql_array(values: Sequence[str]) -> str:
    if not values:
        return "array[]::text[]"
    return "array[" + ", ".join(_sql_literal(value) for value in values) + "]::text[]"


def render_catalog_terms_sql(
    rows: Sequence[Mapping[str, Any]],
    *,
    source_path: str,
    source_sha256: str,
) -> str:
    if not rows:
        raise CatalogTermMaterializationError("catalog term seed requires at least one row")
    managed_term_types = _sql_array(TERM_TYPES)
    sensory_source = ""
    if any("sensory_service" in row.get("metadata", {}) for row in rows):
        from tools.catalog.dictionary.project import DICTIONARY

        sensory_source = (
            f"-- Sensory source: {_repository_path(DICTIONARY)} ({_source_sha256(DICTIONARY)})\n"
        )
    values: list[str] = []
    for row in rows:
        values.append(
            "(" + ", ".join(
                (
                    _sql_literal(row["term_type"]),
                    _sql_literal(row["term_key"]),
                    _sql_literal(row["label_ko"]),
                    _sql_literal(row["label_en"]),
                    _sql_array(row["synonyms"]),
                    _sql_literal(row["parent_term_key"]),
                    _sql_array(row["applicable_sections"]),
                    _sql_literal(canonical_json(row["metadata"])) + "::jsonb",
                    _sql_literal(row["taxonomy_version"]),
                    _sql_literal(row["sort_order"]),
                    _sql_literal(row["is_active"]),
                )
            ) + ")"
        )
    return f"""-- GENERATED FILE. DO NOT EDIT BY HAND.
-- Source: {source_path}
-- Source SHA-256: {source_sha256}
{sensory_source}-- Catalog terms: {len(rows)}
-- Local deterministic seed; no network access and no product facts.

begin;

insert into public.catalog_taxonomy (
  term_type, term_key, label_ko, label_en, synonyms, parent_term_key,
  applicable_sections, metadata, taxonomy_version, sort_order, is_active
)
values
  {',\n  '.join(values)}
on conflict (term_type, term_key) do update
set label_ko = excluded.label_ko,
    label_en = excluded.label_en,
    synonyms = excluded.synonyms,
    parent_term_key = excluded.parent_term_key,
    applicable_sections = excluded.applicable_sections,
    metadata = excluded.metadata,
    taxonomy_version = excluded.taxonomy_version,
    sort_order = excluded.sort_order,
    is_active = excluded.is_active,
    updated_at = now();

-- Values no longer in the registry are deleted, not switched off. Every row
-- written above carries this transaction's now(); the parent key check is
-- deferred to commit.
delete from public.catalog_taxonomy
where term_type = any({managed_term_types})
  and updated_at < now();

commit;
"""


def generate_catalog_terms_sql(
    registry_path: str | Path = DEFAULT_REGISTRY_PATH,
    *,
    schema_path: str | Path = DEFAULT_SCHEMA_PATH,
    base_taxonomy_path: str | Path | None = None,
) -> str:
    registry = Path(registry_path)
    rows = materialize_catalog_terms(
        registry,
        schema_path=schema_path,
        base_taxonomy_path=base_taxonomy_path,
    )
    return render_catalog_terms_sql(
        rows,
        source_path=_repository_path(registry),
        source_sha256=_source_sha256(registry),
    )


FIXTURE_FIELDS = (
    "term_type",
    "term_key",
    "label_ko",
    "label_en",
    "synonyms",
    "parent_term_key",
    "applicable_sections",
    "is_active",
    "metadata",
)


def _sorted_keys(value: Any) -> Any:
    if isinstance(value, Mapping):
        return {key: _sorted_keys(value[key]) for key in sorted(value)}
    if isinstance(value, list):
        return [_sorted_keys(item) for item in value]
    return value


def fixture_rows(rows: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    """The rows a DB test compares against ``public.catalog_taxonomy``.

    Only the columns the table must agree with the dictionary on: sort_order
    is positional and taxonomy_version is a seed label, so neither is compared.
    Set-like arrays and object keys are sorted so the file is stable.
    """

    return [
        {
            field: (
                sorted(row[field])
                if field in ("synonyms", "applicable_sections")
                else _sorted_keys(row[field])
            )
            for field in FIXTURE_FIELDS
        }
        for row in sorted(rows, key=lambda row: (row["term_type"], row["term_key"]))
    ]


def fixture_bytes(rows: Sequence[Mapping[str, Any]]) -> bytes:
    return (json.dumps(fixture_rows(rows), ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY_PATH)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA_PATH)
    parser.add_argument("--base-taxonomy", type=Path, default=None)
    parser.add_argument("--format", choices=("sql", "jsonl"), default="sql")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--migration-output", type=Path, default=None)
    parser.add_argument(
        "--fixture-output",
        type=Path,
        default=None,
        help="also write the JSON fixture the DB tests compare against the table",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        if args.migration_output is not None and args.format != "sql":
            raise CatalogTermMaterializationError(
                "--migration-output is only valid with --format sql"
            )
        rows = materialize_catalog_terms(
            args.registry,
            schema_path=args.schema,
            base_taxonomy_path=args.base_taxonomy,
        )
        if args.format == "sql":
            payload = render_catalog_terms_sql(
                rows,
                source_path=_repository_path(args.registry),
                source_sha256=_source_sha256(args.registry),
            ).encode("utf-8")
        else:
            payload = jsonl_bytes(rows)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(payload)
        if args.migration_output is not None:
            args.migration_output.parent.mkdir(parents=True, exist_ok=True)
            args.migration_output.write_bytes(payload)
        if args.fixture_output is not None:
            args.fixture_output.parent.mkdir(parents=True, exist_ok=True)
            args.fixture_output.write_bytes(fixture_bytes(rows))
    except (CatalogTermMaterializationError, TaxonomyValidationError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(
        canonical_json(
            {
                "output": _repository_path(args.output),
                "migration_output": (
                    _repository_path(args.migration_output)
                    if args.migration_output is not None
                    else None
                ),
                "fixture_output": (
                    _repository_path(args.fixture_output)
                    if args.fixture_output is not None
                    else None
                ),
                "row_count": len(rows),
                "sha256": hashlib.sha256(payload).hexdigest(),
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
