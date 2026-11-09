import json
from copy import deepcopy

import pytest

from tools.catalog.dictionary import project as dictionary

from tools.catalog.normalization.sync_service_vocabulary import (
    FREQUENCY_PATH, VocabularySyncError,
    check_spec, derive_memberships, folded_without_reason, reader_name, descriptor_rows, sync_spec,
)


def _spec():
    return dictionary.view("service_vocabulary")


def _catalog():
    return dictionary.view("catalog")


def test_committed_vocabulary_is_derived_from_the_catalog_tree():
    assert check_spec(_spec(), _catalog()) == []


def test_every_frequent_folded_name_has_a_written_reason():
    frequency = json.loads(FREQUENCY_PATH.read_text(encoding="utf-8"))["bottles"]
    assert folded_without_reason(_spec(), _catalog(), frequency) == []


def test_reader_name_is_the_nearest_selectable_name_on_the_line():
    rows = descriptor_rows(_catalog())
    assert reader_name("pickled_apricot", rows) == "apricot"
    assert reader_name("apricot", rows) == "apricot"
    assert reader_name("nectarine", rows) == "peach"
    assert reader_name("stone_fruit", rows) is None
    assert reader_name("kumquat_peel", rows) == "orange_tangerine"
    members = derive_memberships(_catalog())
    assert members["apricot"] == ["apricot", "pickled_apricot"]
    assert "stone_fruit" not in members["plum"]


def test_sync_moves_labels_and_hides_names_without_a_selectable_ancestor():
    catalog = _catalog()
    spec = _spec()
    rows = {r["key"]: r for r in catalog["descriptors"]}
    rows["black_plum"]["parent_key"] = "apricot"       # 검은 자두 now reads as 살구
    rows["cherry"]["onboarding_selectable"] = False    # 체리 stops being offered
    with pytest.raises(VocabularySyncError, match="no longer selectable"):
        sync_spec(spec, catalog)
    rows["cherry"]["onboarding_selectable"] = True
    derived = sync_spec(spec, catalog)
    groups = {g["key"]: g for g in derived["groups"]}
    assert "black_plum" in groups["apricot"]["source_keys"] and "black_plum" not in groups["plum"]["source_keys"]
    assert "검은 자두" in groups["apricot"]["user_source_labels"] and "검은 자두" not in groups["plum"]["user_source_labels"]
    rows["mint"]["onboarding_selectable"] = False
    rows["mint"]["parent_key"] = None
    rows["mint"]["family_key"] = "green_herbal"
    with pytest.raises(VocabularySyncError, match="no longer selectable"):
        sync_spec(spec, catalog)


def test_new_selectable_name_gets_a_group_after_its_parent_name():
    catalog = _catalog()
    rows = {r["key"]: r for r in catalog["descriptors"]}
    rows["blackberry"]["onboarding_selectable"] = True
    derived = sync_spec(_spec(), catalog)
    keys = [g["key"] for g in derived["groups"]]
    assert keys.index("blackberry") == keys.index("berry") + 1
    group = next(g for g in derived["groups"] if g["key"] == "blackberry")
    assert group["category_key"] == "fruit" and group["label_ko"] == "블랙베리"
    assert "blackberry" not in next(g for g in derived["groups"] if g["key"] == "berry")["source_keys"]
    rows["fresh_fruit"]["onboarding_selectable"] = True
    with pytest.raises(VocabularySyncError, match="root-level reader name"):
        sync_spec(_spec(), catalog)
