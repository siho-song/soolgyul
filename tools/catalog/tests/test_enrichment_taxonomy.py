from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest
import tools.catalog.enrichment.taxonomy as taxonomy_module

from tools.catalog.enrichment.taxonomy import (
    DEFAULT_BASE_TAXONOMY_PATH,
    DEFAULT_REGISTRY_PATH,
    DEFAULT_SCHEMA_PATH,
    TaxonomyValidationError,
    load_and_validate_taxonomy,
    load_taxonomy_registry,
    validate_taxonomy_registry,
)


def _json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def registry() -> dict[str, object]:
    return load_taxonomy_registry(DEFAULT_REGISTRY_PATH)


@pytest.fixture(scope="module")
def base_taxonomy() -> dict[str, object]:
    return _json(DEFAULT_BASE_TAXONOMY_PATH)


@pytest.fixture(scope="module")
def schema() -> dict[str, object]:
    return _json(DEFAULT_SCHEMA_PATH)


def _validate(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> dict[str, int]:
    return validate_taxonomy_registry(
        registry,
        base_taxonomy=base_taxonomy,
        schema=schema,
    )


def test_repository_registry_is_valid_and_comprehensive() -> None:
    _, summary = load_and_validate_taxonomy()

    assert set(summary) == {
        "categories",
        "primary_styles",
        "sensory_descriptors",
        "scalar_dimensions",
        "ingredient_terms",
        "process_terms",
        "maturation_terms",
    }
    assert all(value > 0 for value in summary.values())


def test_v1_categories_and_styles_are_preserved(
    registry: dict[str, object], base_taxonomy: dict[str, object]
) -> None:
    assert registry["base_taxonomy"]["style_relationship"] == "required_compatibility_subset"  # type: ignore[index]
    base_categories = {
        row["category_key"]: row for row in base_taxonomy["categories"]  # type: ignore[index]
    }
    categories = {
        row["category_key"]: row for row in registry["categories"]  # type: ignore[index]
    }
    assert categories == base_categories

    styles = {
        row["style_key"]: row for row in registry["primary_styles"]  # type: ignore[index]
    }
    for base_style in base_taxonomy["styles"]:  # type: ignore[index]
        style = styles[base_style["style_key"]]
        assert style["category_key"] == base_style["category_key"]
        assert base_style["name_ko"] in [style["name_ko"], *style["aliases"]]
        assert base_style["name_en"] in [style["name_en"], *style["aliases"]]


def test_base_style_registry_is_explicitly_a_compatibility_subset(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    mutated["base_taxonomy"].pop("style_relationship")  # type: ignore[index,union-attr]

    with pytest.raises(TaxonomyValidationError, match="style_relationship"):
        _validate(mutated, base_taxonomy, schema)


def test_duplicate_style_key_is_rejected(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    mutated["primary_styles"].append(copy.deepcopy(mutated["primary_styles"][0]))  # type: ignore[index,union-attr]

    with pytest.raises(TaxonomyValidationError, match="duplicate primary_styles style_key"):
        _validate(mutated, base_taxonomy, schema)


def test_v1_style_drift_is_rejected(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    next(
        style
        for style in mutated["primary_styles"]  # type: ignore[index]
        if style["style_key"] == "bourbon"
    )["name_ko"] = "다른 이름"

    with pytest.raises(TaxonomyValidationError, match="compatibility drift for bourbon.name_ko"):
        _validate(mutated, base_taxonomy, schema)


def test_primary_style_and_facet_labels_are_normalized_disjoint(
    registry: dict[str, object],
) -> None:
    normalize = lambda value: " ".join(value.lower().split())
    style_labels = {
        normalize(value)
        for row in registry["primary_styles"]  # type: ignore[index]
        for value in (row["name_ko"], row["name_en"], *row["aliases"])
    }
    production_labels = {
        normalize(value)
        for row in [*registry["production"]["process_terms"], *registry["production"]["maturation_terms"]]  # type: ignore[index]
        for value in (row["name_ko"], row["name_en"], *row["aliases"])
    }

    assert style_labels.isdisjoint(production_labels)


def test_unknown_category_reference_is_rejected(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    mutated["ingredients"]["terms"][0]["applies_to_categories"] = ["unknown_category"]  # type: ignore[index]

    with pytest.raises(TaxonomyValidationError, match="references unknown categories"):
        _validate(mutated, base_taxonomy, schema)


def test_descriptor_cycle_is_rejected(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    descriptors = {
        descriptor["descriptor_key"]: descriptor
        for descriptor in mutated["sensory"]["descriptors"]  # type: ignore[index]
    }
    descriptors["fruit"]["parent_descriptor_key"] = "citrus"

    with pytest.raises(TaxonomyValidationError, match="cycle in sensory.descriptors"):
        _validate(mutated, base_taxonomy, schema)


def test_descriptor_parent_must_share_db_family(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    lemon = next(
        descriptor
        for descriptor in mutated["sensory"]["descriptors"]  # type: ignore[index]
        if descriptor["descriptor_key"] == "lemon"
    )
    lemon["descriptor_family"] = "floral"

    with pytest.raises(TaxonomyValidationError, match="must share descriptor_family"):
        _validate(mutated, base_taxonomy, schema)


def test_ingredient_type_enum_drift_is_rejected(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    mutated["ingredients"]["types"].append(  # type: ignore[index,union-attr]
        {
            "key": "unbounded_custom_type",
            "name_ko": "임의 타입",
            "name_en": "Unbounded custom type",
            "definition": "Should not pass the DB enum gate.",
            "aliases": [],
        }
    )

    with pytest.raises(TaxonomyValidationError, match="must exactly match DB enum"):
        _validate(mutated, base_taxonomy, schema)


@pytest.mark.parametrize(
    ("collection_path", "namespace"),
    [
        (("ingredients", "types"), "ingredients.types"),
        (("ingredients", "roles"), "ingredients.roles"),
        (("production", "process_kinds"), r"production.kinds\(global\)"),
        (("production", "maturation_kinds"), r"production.kinds\(global\)"),
    ],
)
def test_named_vocabulary_alias_collisions_are_rejected(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
    collection_path: tuple[str, str],
    namespace: str,
) -> None:
    mutated = copy.deepcopy(registry)
    group, collection = collection_path
    rows = mutated[group][collection]  # type: ignore[index]
    rows[1]["aliases"] = [rows[0]["aliases"][0]]

    with pytest.raises(TaxonomyValidationError, match=namespace):
        _validate(mutated, base_taxonomy, schema)


def test_flat_named_vocabulary_rejects_unimplemented_parent_key(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    mutated["ingredients"]["types"][0]["parent_key"] = "grain"  # type: ignore[index]

    with pytest.raises(TaxonomyValidationError, match="parent_key"):
        _validate(mutated, base_taxonomy, schema)


def test_primary_style_exclusions_are_rejected_as_redundant_single_value_metadata(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    mutated["primary_styles"][0]["excludes_style_keys"] = [  # type: ignore[index]
        mutated["primary_styles"][1]["style_key"]  # type: ignore[index]
    ]

    with pytest.raises(TaxonomyValidationError, match="excludes_style_keys"):
        _validate(mutated, base_taxonomy, schema)


def test_process_stage_must_be_deterministic(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    mutated["production"]["process_terms"][0]["process_stage"] = "distillation"  # type: ignore[index]

    with pytest.raises(TaxonomyValidationError, match="kind_key must equal DB process_stage"):
        _validate(mutated, base_taxonomy, schema)


def test_maturation_terms_use_the_maturation_stage_required_by_the_kind_fk(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    mutated["production"]["maturation_terms"][0]["process_stage"] = "finishing"  # type: ignore[index]

    with pytest.raises(TaxonomyValidationError, match="process_stage must be maturation"):
        _validate(mutated, base_taxonomy, schema)


def test_production_term_keys_are_globally_unique_across_collections(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    production = mutated["production"]  # type: ignore[index]
    production["maturation_terms"][0]["term_key"] = production["process_terms"][0][
        "term_key"
    ]

    with pytest.raises(TaxonomyValidationError, match=r"production.terms\(global\)"):
        _validate(mutated, base_taxonomy, schema)


def test_production_term_aliases_are_globally_unambiguous_across_collections(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    production = mutated["production"]  # type: ignore[index]
    production["maturation_terms"][0]["aliases"] = [
        production["process_terms"][0]["aliases"][0]
    ]

    with pytest.raises(TaxonomyValidationError, match=r"production.terms\(global\)"):
        _validate(mutated, base_taxonomy, schema)


def test_scalar_bands_must_be_contiguous(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    mutated["sensory"]["scalar_dimensions"][0]["bands"][1]["minimum"] = 0.4  # type: ignore[index]

    with pytest.raises(TaxonomyValidationError, match="bands must be contiguous"):
        _validate(mutated, base_taxonomy, schema)


def test_scalar_dimensions_are_fixed_to_db_normalized_scale(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    dimension = mutated["sensory"]["scalar_dimensions"][0]  # type: ignore[index]
    dimension["maximum"] = 10
    dimension["bands"][-1]["maximum"] = 10

    with pytest.raises(TaxonomyValidationError, match="DB-normalized 0..1 scale"):
        _validate(mutated, base_taxonomy, schema)


def test_scalar_band_boundaries_fit_db_measurement_precision(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    bands = mutated["sensory"]["scalar_dimensions"][0]["bands"]  # type: ignore[index]
    bands[0]["maximum"] = 0.3333
    bands[1]["minimum"] = 0.3333

    with pytest.raises(TaxonomyValidationError, match="at most three decimal places"):
        _validate(mutated, base_taxonomy, schema)


def test_invalid_source_mapping_regex_is_rejected(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    mutated["source_mapping_policy"]["exclusions"][0]["label_pattern"] = "["  # type: ignore[index]

    with pytest.raises(TaxonomyValidationError, match="invalid regex"):
        _validate(mutated, base_taxonomy, schema)


def test_schema_rejects_unapproved_eav_field(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
) -> None:
    mutated = copy.deepcopy(registry)
    mutated["primary_styles"][0]["arbitrary_payload"] = {"anything": True}  # type: ignore[index]

    with pytest.raises(TaxonomyValidationError, match="arbitrary_payload"):
        _validate(mutated, base_taxonomy, schema)


def test_schema_dependency_absence_fails_closed(
    registry: dict[str, object],
    base_taxonomy: dict[str, object],
    schema: dict[str, object],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(taxonomy_module, "Draft202012Validator", None)
    monkeypatch.setattr(taxonomy_module, "FormatChecker", None)

    with pytest.raises(TaxonomyValidationError, match="fails closed"):
        _validate(registry, base_taxonomy, schema)
