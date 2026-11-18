from copy import deepcopy

import pytest

from tools.catalog.dictionary import project as dictionary

from tools.catalog.normalization.sensory_service_vocabulary import (
    ServiceVocabulary, load_service_vocabulary, project_service_terms, vocabulary_views,
)


def test_every_source_has_exactly_one_explicit_outcome():
    vocabulary = load_service_vocabulary()
    assert {"red_fruit", "clean_finish", "alcohol_aroma"} <= vocabulary.hidden
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


def test_a_word_folds_into_the_offered_word_above_it_or_the_one_it_names():
    vocabulary = load_service_vocabulary()
    # 슬레이트 sits under 젖은 돌 in the tree; 실키 and 따끔함 name the texture they are offered as.
    assert vocabulary.normalize(["slate", "silky_texture", "tactile_prickle", "warming_sensation"]) == [
        "wet_stone", "soft_texture", "spicy_sensation"]


def test_conversion_is_idempotent_preserves_phase_and_non_tag_fields():
    vocabulary = load_service_vocabulary()
    original = {"id": "unchanged", "aroma_tags": ["green_apple", "apple", "red_fruit"],
                "palate_tags": ["quince"], "finish_tags": ["clean_finish", "cranberry"],
                "flavor_tags": ["green_apple", "apple", "red_fruit", "quince", "clean_finish",
                                "cranberry", "silky_texture", "warming_sensation", "tactile_prickle"],
                "sweetness": 0.25, "source_basis": [{"source": "original"}]}
    before = deepcopy(original)
    result = vocabulary.normalize_profile(original)
    assert original == before
    assert result["aroma_tags"] == ["green_apple", "apple", "red_fruit"]
    assert result["palate_tags"] == ["quince"]
    assert result["finish_tags"] == ["clean_finish", "cranberry"]
    assert result["sweetness"] == 0.25
    assert result["source_basis"] == original["source_basis"]
    assert vocabulary.normalize_profile(result) == result


def test_misconfigured_map_does_not_silently_lose_a_source():
    spec, source = vocabulary_views(dictionary.load())
    next(group for group in spec["groups"] if group["key"] == "apple")["source_keys"].remove("apple")
    with pytest.raises(ValueError, match="unmapped"):
        ServiceVocabulary(spec, source)


def test_an_offered_word_keeps_the_names_of_the_words_folded_away_as_synonyms():
    """A finer word that left the dictionary still finds the word it folded into."""
    rows = {row["term_key"]: row for row in project_service_terms()}
    assert "블러드 오렌지" in rows["orange"]["synonyms"]
    assert "blood_orange" not in rows["orange"]["metadata"]["sensory_service"]["source_keys"]
    assert "blood_orange" not in rows
