from copy import deepcopy

import pytest

from tools.catalog.dictionary import project as dictionary

from tools.catalog.normalization.sensory_service_vocabulary import (
    ServiceVocabulary, load_service_vocabulary, project_service_terms,
)


def test_every_source_has_exactly_one_explicit_outcome():
    vocabulary = load_service_vocabulary()
    assert {"cooked_vegetal", "angular_character", "persistent_character"} <= vocabulary.source.keys()
    assert {"angular_character", "persistent_character"} <= vocabulary.hidden
    assert vocabulary.source.keys() <= vocabulary.targets.keys()
    assert len(project_service_terms()) == len(vocabulary.groups) + len(vocabulary.hidden) + len(vocabulary.pending)


def test_hidden_and_pending_are_distinct_and_unknowns_fail_closed():
    vocabulary = load_service_vocabulary()
    assert vocabulary.normalize(["red_fruit", "clean_finish", "alcohol_aroma"]) == ["red_fruit", "clean_finish", "alcohol_aroma"]
    assert vocabulary.normalize(["red_fruit", "clean_finish", "alcohol_aroma"], visible_only=True) == []
    assert vocabulary.normalize(["cranberry", "rhubarb", "fruit"]) == ["cranberry", "rhubarb", "fruit"]
    assert vocabulary.normalize(["cranberry", "fruit", "apple"], visible_only=True) == ["cranberry", "apple"]
    with pytest.raises(ValueError, match="unreviewed"):
        vocabulary.normalize(["unknown_future_fruit"])


def test_conversion_is_idempotent_preserves_phase_and_non_tag_fields():
    vocabulary = load_service_vocabulary()
    original = {"id": "unchanged", "aroma_tags": ["green_apple", "apple", "red_fruit"],
                "palate_tags": ["quince"], "finish_tags": ["clean_finish", "cranberry"],
                "flavor_tags": ["green_apple", "apple", "red_fruit", "quince", "clean_finish",
                                "cranberry", "silky_texture", "warming_sensation", "tactile_prickle"],
                "sweetness": 0.25, "aroma_note": "original note", "source_basis": [{"source": "original"}]}
    before = deepcopy(original)
    result = vocabulary.normalize_profile(original)
    assert original == before
    assert result["aroma_tags"] == ["green_apple", "apple", "red_fruit"]
    assert result["palate_tags"] == ["quince"]
    assert result["finish_tags"] == ["clean_finish", "cranberry"]
    assert result["sweetness"] == 0.25
    assert result["source_basis"] == original["source_basis"]
    assert vocabulary.normalize_profile(result) == result


def test_current_profile_does_not_require_or_recreate_retired_flavor_tags():
    vocabulary = load_service_vocabulary()
    result = vocabulary.normalize_profile({"aroma_tags": ["ripe_apple"], "palate_tags": ["oak"]})
    assert result == {"aroma_tags": ["apple"], "palate_tags": ["oak"]}


def test_misconfigured_map_does_not_silently_lose_a_source():
    spec = dictionary.view("service_vocabulary")
    source = dictionary.view("catalog")
    next(group for group in spec["groups"] if group["key"] == "apple")["source_keys"].remove("apple")
    with pytest.raises(ValueError, match="unmapped"):
        ServiceVocabulary(spec, source)


def test_current_hierarchy_uses_the_same_service_map_not_obsolete_display_rules():
    from tools.catalog.normalization.sensory_hierarchy import SensoryHierarchy

    hierarchy = SensoryHierarchy.from_catalog(dictionary.view("catalog"))
    choices = hierarchy.questionnaire_choices(["apricot", "plum", "black_cherry", "red_fruit", "cranberry"], phase="aroma")
    assert [row.key for row in choices] == ["apricot", "plum", "cherry", "cranberry"]
    assert choices[2].catalog_descriptor_keys == ("black_cherry",)
    assert all(row.is_representative for row in choices)
    assert hierarchy.questionnaire_choices(["soft_texture"], phase="texture")[0].label_ko == "부드러운 질감"


def test_new_precise_descriptors_use_existing_representatives_without_losing_source_keys():
    vocabulary = load_service_vocabulary()
    keys = ["blood_orange", "wheatgrass", "custard", "slate"]
    representatives = ["orange_tangerine", "leaf", "dessert_aromatic", "wet_stone"]
    assert vocabulary.normalize(keys) == representatives
    assert vocabulary.normalize(keys, visible_only=True) == representatives
    rows = {row["term_key"]: row for row in project_service_terms()}
    for key, representative in zip(keys, representatives):
        assert key in vocabulary.source
        assert key in rows[representative]["metadata"]["sensory_service"]["source_keys"]
        assert key not in rows
    assert vocabulary.source["wheatgrass"]["phases"] == ["aroma"]
    assert vocabulary.questionnaire_choices(["wheatgrass"], phase="palate") == []
    assert vocabulary.questionnaire_choices(["wheatgrass"], phase="aroma")[0]["key"] == "leaf"
    assert vocabulary.normalize(["cedar", "sandalwood", "wood"]) == ["wood"]


def test_representative_projection_preserves_original_and_does_not_expand_it_back():
    vocabulary = load_service_vocabulary()
    original = {"aroma_note": "블러드 오렌지와 밀싹", "aroma_tags": ["blood_orange", "orange", "wheatgrass"],
                "finish_tags": ["custard", "musk"], "sweetness": 2}
    projected = vocabulary.normalize_profile(original)
    assert projected["aroma_tags"] == ["orange_tangerine", "leaf"]
    assert projected["finish_tags"] == ["dessert_aromatic", "musk"]
    assert projected["aroma_note"] == original["aroma_note"] and projected["sweetness"] == 2
    assert original["aroma_tags"] == ["blood_orange", "orange", "wheatgrass"]
    assert vocabulary.normalize_profile(projected) == projected
    assert vocabulary.normalize(["orange_tangerine"]) == ["orange_tangerine"]
