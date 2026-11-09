from __future__ import annotations

from collections import Counter
import json
from pathlib import Path

import pytest

from tools.catalog.dictionary import project as dictionary
from tools.catalog.enrichment.materialize_catalog_terms import (
    FIXTURE_FIELDS,
    ROOT,
    fixture_bytes,
    generate_catalog_terms_sql,
    materialize_catalog_terms,
)
from tools.catalog.enrichment.taxonomy import TaxonomyValidationError
from tools.catalog.support import jsonl_bytes

FIXTURE_PATH = ROOT / "supabase/functions/_tests/fixtures/catalog_taxonomy_rows.json"

def test_materializes_all_service_terms_with_composite_identity() -> None:
    rows = materialize_catalog_terms()

    assert set(Counter(row["term_type"] for row in rows)) == {
        "style",
        "ingredient",
        "process",
        "maturation",
        "sensory_descriptor",
        "region",
    }
    identities = {(row["term_type"], row["term_key"]) for row in rows}
    assert len(identities) == len(rows)
    assert not any(row["term_type"] == "story_topic" for row in rows)
    assert ("process", "chill_filtration") in identities
    assert ("region", "fr") in identities and ("region", "fr_bordeaux") in identities


def test_term_rows_preserve_hierarchy_sections_and_normalized_metadata() -> None:
    rows = materialize_catalog_terms()
    by_identity = {(row["term_type"], row["term_key"]): row for row in rows}

    process = by_identity[("process", "chill_filtration")]
    assert process["applicable_sections"] == ["production"]
    assert process["metadata"]["excludes_term_keys"] == ["non_chill_filtered"]

    ingredient = next(
        row
        for row in rows
        if row["term_type"] == "ingredient" and row["parent_term_key"] is not None
    )
    assert ("ingredient", ingredient["parent_term_key"]) in by_identity
    assert ingredient["applicable_sections"] == ["ingredient"]

    sensory = by_identity[("sensory_descriptor", "fruit")]
    assert sensory["applicable_sections"] == ["aroma", "finish", "palate"]
    assert sensory["metadata"]["sensory_service"]["status"] == "pending"
    assert sensory["metadata"]["user_visible"] is False
    # Prose lives in the dictionary file only; the table keeps the skeleton.
    assert not any(
        key in row["metadata"] or key in row
        for row in rows
        for key in ("sensory_description", "sensory_trait_keys", "card_label_ko")
    )

    assert not any(term_type == "story_topic" for term_type, _ in by_identity)
    assert all(row["taxonomy_version"] == ("4.0.0" if row["term_type"] == "sensory_descriptor" else "2.0.0") for row in rows)
    assert all(row["sort_order"] > 0 and row["sort_order"] % 10 == 0 for row in rows)
    assert all(row["is_active"] is True for row in rows)


def test_term_projection_and_sql_are_byte_deterministic() -> None:
    first = materialize_catalog_terms()
    second = materialize_catalog_terms()

    assert jsonl_bytes(first) == jsonl_bytes(second)
    assert generate_catalog_terms_sql() == generate_catalog_terms_sql()


def test_sql_only_manages_the_single_catalog_taxonomy_table() -> None:
    sql = generate_catalog_terms_sql()

    assert sql.startswith("-- GENERATED FILE. DO NOT EDIT BY HAND.\n")
    assert f"-- Catalog terms: {len(materialize_catalog_terms())}" in sql
    assert sql.count("insert into public.") == 1
    assert "insert into public.catalog_taxonomy (" in sql
    assert "on conflict (term_type, term_key) do update" in sql
    assert "updated_at = now()" in sql
    assert "catalog_terms" not in sql
    assert "update public.catalog_taxonomy" not in sql
    assert sql.index("begin;") < sql.index("insert into public.catalog_taxonomy") < sql.index(
        "delete from public.catalog_taxonomy"
    )
    removal = sql.split("delete from public.catalog_taxonomy", 1)[1].split("commit;", 1)[0]
    for term_type in (
        "style",
        "ingredient",
        "process",
        "maturation",
        "sensory_descriptor",
    ):
        assert f"'{term_type}'" in removal
    assert "and updated_at < now();" in removal
    assert "chill_filtration" in sql
    assert sql.endswith("commit;\n")


def test_invalid_registry_duplicate_and_missing_collection_fail_closed(tmp_path: Path) -> None:
    registry = dictionary.view("taxonomy")
    registry["primary_styles"].append(dict(registry["primary_styles"][0]))
    duplicate_path = tmp_path / "duplicate.json"
    duplicate_path.write_text(json.dumps(registry, ensure_ascii=False), encoding="utf-8")

    with pytest.raises(TaxonomyValidationError):
        materialize_catalog_terms(duplicate_path)

    registry = dictionary.view("taxonomy")
    del registry["production"]
    missing_path = tmp_path / "missing.json"
    missing_path.write_text(json.dumps(registry, ensure_ascii=False), encoding="utf-8")

    with pytest.raises(TaxonomyValidationError):
        materialize_catalog_terms(missing_path)


def test_committed_fixture_matches_the_dictionary_projection() -> None:
    """A dictionary edit without regenerating the fixture fails here, not in CI's DB test."""
    rows = materialize_catalog_terms()
    expected = fixture_bytes(rows)

    assert FIXTURE_PATH.read_bytes() == expected, (
        "run python3 -m tools.catalog.enrichment.materialize_catalog_terms "
        "--format jsonl --output /dev/null --fixture-output "
        f"{FIXTURE_PATH.relative_to(ROOT).as_posix()}"
    )
    fixture = json.loads(expected)
    assert len(fixture) == len(rows)
    assert all(tuple(row) == FIXTURE_FIELDS for row in fixture)
    assert fixture == sorted(fixture, key=lambda row: (row["term_type"], row["term_key"]))
