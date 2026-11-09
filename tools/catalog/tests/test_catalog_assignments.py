import json
from pathlib import Path

import pytest

from tools.catalog.enrichment.assignments import (
    InvalidCatalogAssignment, assignment_registry,
    CatalogCategoryKey, CatalogStyleKey, CatalogIngredientKey, CatalogProcessKey,
)
from tools.catalog.enrichment.generate_assignment_contract import generated_files

ROOT = Path(__file__).resolve().parents[3]
CASES = json.loads((ROOT / "tests/fixtures/catalog_assignment_cases.json").read_text())


@pytest.mark.parametrize("case", CASES, ids=lambda c: c["name"])
def test_shared_assignment_contract(case):
    result = assignment_registry().validate(case["input"])
    assert sorted({i.code for i in result.issues}) == case["codes"]
    assert (result.value is not None) == (not case["codes"])


def test_deployment_contracts_are_generated_from_current_taxonomy():
    for path, expected in generated_files().items():
        assert path.read_text() == expected, str(path)


def test_actual_keys_are_enum_instances_with_unchanged_wire_values():
    value = assignment_registry().validate({'category_key': 'wine', 'style_key': 'red_wine',
        'ingredient_keys': ['grape'], 'production_process_keys': ['organic_certified']}).require_valid()
    assert value.category_key is CatalogCategoryKey.WINE
    assert value.style_key is CatalogStyleKey.RED_WINE
    assert value.ingredient_keys == (CatalogIngredientKey.GRAPE,)
    assert isinstance(value.ingredient_keys[0], CatalogIngredientKey)
    assert value.production_process_keys[0] is CatalogProcessKey.ORGANIC_CERTIFIED
    assert json.loads(json.dumps(value.to_wire()))['ingredient_keys'] == ['grape']
    with pytest.raises(ValueError):
        CatalogIngredientKey('not_registered')
