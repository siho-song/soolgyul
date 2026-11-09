from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path

import pytest

from tools.catalog.dictionary import project as dictionary

from tools.catalog.normalization.sensory_hierarchy import (
    DescriptorGroup,
    SensoryHierarchy,
    SensoryHierarchyError,
    validate_sensory_catalog,
)


@pytest.fixture(scope="module")
def catalog() -> dict:
    return dictionary.view("catalog")


@pytest.fixture(scope="module")
def hierarchy(catalog: dict) -> SensoryHierarchy:
    return SensoryHierarchy.from_catalog(catalog)


def test_grouping_preserves_supplied_keys_and_first_seen_order(
    hierarchy: SensoryHierarchy,
) -> None:
    assert hierarchy.group_descriptors(
        ["tangerine", "apple", "lemon", "tangerine"], phase="aroma"
    ) == (
        DescriptorGroup("fruit", "citrus", "시트러스 계열", "aroma", ("tangerine", "lemon"), "과일"),
        DescriptorGroup("fruit", "orchard_fruit", "사과·배 계열", "aroma", ("apple",), "과일"),
    )


def test_broad_and_ungrouped_evidence_are_not_expanded(
    hierarchy: SensoryHierarchy,
) -> None:
    assert hierarchy.group_descriptors(
        ["citrus", "fresh_fruit", "oak", "smoke"], phase="aroma"
    ) == (
        DescriptorGroup("fruit", "citrus", "시트러스 계열", "aroma", ("citrus",), "과일"),
        DescriptorGroup("fruit", None, None, "aroma", ("fresh_fruit",), "과일"),
        DescriptorGroup("wood_resin", "wood", "나무 계열", "aroma", ("oak",), "나무·수지·향목"),
        DescriptorGroup("smoke_peat", "smoke", "연기 계열", "aroma", ("smoke",), "연기·피트·탄내"),
    )


@pytest.mark.parametrize("rows, message", [
    ([{"key": "a"}, {"key": "a"}], "duplicate descriptor key"),
    ([{"key": "a", "parent_key": "missing"}], "missing descriptor parent"),
    ([{"key": "a", "parent_key": "a"}], "descriptor parent cycle"),
    ([{"key": "a", "parent_key": "b"}, {"key": "b", "parent_key": "a"}], "descriptor parent cycle"),
    ([{"key": "a", "group_label_ko": " "}], "invalid group label"),
    ([{"key": "a", "group_label_ko": "계열"}], "intermediate group needs a parent"),
])
def test_invalid_hierarchies_are_rejected(rows: list[dict], message: str) -> None:
    with pytest.raises(SensoryHierarchyError, match=message):
        SensoryHierarchy(rows)


def test_unknown_keys_and_unsupported_phases_are_not_guessed(
    hierarchy: SensoryHierarchy,
) -> None:
    with pytest.raises(SensoryHierarchyError, match="unknown descriptor key"):
        hierarchy.group_descriptors(["not_a_descriptor"], phase="aroma")
    with pytest.raises(SensoryHierarchyError, match="unsupported descriptor phase"):
        hierarchy.group_descriptors(["apple"], phase="texture")  # type: ignore[arg-type]


def test_facets_do_not_replace_or_expand_observations(hierarchy: SensoryHierarchy) -> None:
    assert hierarchy.facet_keys_for("black_cherry") == ("black_fruit",)
    assert hierarchy.facet_keys_for("strawberry") == ("red_fruit",)
    assert hierarchy.facet_keys_for("cherry") == ()  # Colour wasn't specified.
    group = hierarchy.group_descriptors(["black_cherry"], phase="aroma")[0]
    assert group.group_key == "stone_fruit"
    assert group.descriptor_keys == ("black_cherry",)


def test_overall_impressions_and_unresolved_terms_are_explicitly_separated(
    hierarchy: SensoryHierarchy,
) -> None:
    keys = ["balanced_character", "complex_character", "refreshing_character",
            "black_mulberry", "lingonberry", "hawthorn"]
    assert hierarchy.group_descriptors(keys, phase="aroma") == ()
    groups = hierarchy.group_descriptors(keys, phase="aroma", include_non_sensory=True)
    assert [(g.kind, len(g.descriptor_keys)) for g in groups] == [("character", 3), ("unresolved", 3)]


def test_missing_family_and_ambiguous_alias_fail_validation(catalog: dict) -> None:
    broken = deepcopy(catalog)
    next(r for r in broken["descriptors"] if r["key"] == "fresh_fruit")["family_key"] = "missing"
    with pytest.raises(SensoryHierarchyError, match="missing descriptor family"):
        validate_sensory_catalog(broken)
    broken = deepcopy(catalog)
    next(r for r in broken["textures"] if r["key"] == "smooth_texture")["aliases"].append("원만한 질감")
    with pytest.raises(SensoryHierarchyError, match="ambiguous textures alias"):
        validate_sensory_catalog(broken)


def test_immediate_onset_remains_hidden_without_widening_flavour_phases() -> None:
    catalog = dictionary.view("catalog")
    validate_sensory_catalog(catalog)
    onset = next(row for row in catalog['descriptors'] if row['key'] == 'immediate_onset')
    assert onset['onboarding_selectable'] is False and 'texture' in onset['phases']
    for target in ['immediate_onset', 'apple']:
        broken = deepcopy(catalog)
        row = next(row for row in broken['descriptors'] if row['key'] == target)
        if target == 'immediate_onset':
            row['onboarding_selectable'] = True
        else:
            row['phases'].append('texture')
        with pytest.raises(SensoryHierarchyError, match='invalid descriptor phases'):
            validate_sensory_catalog(broken)


def test_selectable_names_must_be_sensory(catalog: dict) -> None:
    broken = deepcopy(catalog)
    row = next(r for r in broken["descriptors"] if r["key"] == "immediate_onset")
    row["phases"] = ["aroma"]
    row["onboarding_selectable"] = True
    with pytest.raises(SensoryHierarchyError):
        validate_sensory_catalog(broken)
