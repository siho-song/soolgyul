"""The one dictionary stays complete, consistent and up to date with its sources."""

import json

import pytest

from tools.catalog.dictionary import project
from tools.catalog.dictionary.build import OUT, TYPES, build


@pytest.fixture(scope="module")
def built():
    return build()


def test_dictionary_file_is_what_its_views_rebuild(built):
    dictionary, _ = built
    on_disk = json.loads(OUT.read_text(encoding="utf-8"))
    assert on_disk == dictionary, "run tools/catalog/dictionary/build.py"


def test_rows_are_unique_typed_and_named(built):
    dictionary, report = built
    terms = dictionary["terms"]
    keys = {(t["type"], t["key"]) for t in terms}
    assert len(keys) == len(terms)
    assert all(t["type"] in TYPES or t["type"] == "region" for t in terms)
    assert all(t["names"].get("ko") for t in terms)
    assert report["unresolved_parents"] == []


def test_every_catalog_key_has_a_row(built):
    """Keys the products point at (kinds, processes, ingredients) exist in the dictionary."""
    terms = built[0]["terms"]
    by_type = {}
    for t in terms:
        by_type.setdefault(t["type"], set()).add(t["key"])
    tax = project.view("taxonomy")
    assert {s["style_key"] for s in tax["primary_styles"]} <= by_type["kind"]
    assert {t["term_key"] for t in tax["production"]["process_terms"]} <= by_type["process"]
    assert {t["term_key"] for t in tax["production"]["maturation_terms"]} <= by_type["maturation"]
    assert {t["ingredient_key"] for t in tax["ingredients"]["terms"]} <= by_type["ingredient"]
    aroma_parents = {t.get("parent") for t in terms if t["type"] == "aroma"} - {None}
    assert aroma_parents <= by_type["aroma"] | by_type["aroma_family"]


def test_views_rebuild_the_same_dictionary():
    """Editing through a view and rebuilding changes nothing that was not edited."""
    current = project.load()
    assert project.rebuild({}) == current


def test_expression_rules_are_unique_and_target_existing_terms() -> None:
    catalog = project.view("catalog")
    rules = catalog["expression_rules"]
    descriptor_keys = {row["key"] for row in catalog["descriptors"]}
    texture_keys = {row["key"] for row in catalog["textures"]}
    finish_keys = {row["key"] for row in catalog["finish_characters"]}
    descriptor_phases = {row["key"]: row["phases"] for row in catalog["descriptors"]}
    texture_phases = {row["key"]: row["phases"] for row in catalog["textures"]}

    identities = [
        (row["source_key"], row["phase"], row["expression"])
        for row in rules
    ]
    assert len(identities) == len(set(identities))

    for row in rules:
        assert row["action"] in {"map", "handoff", "exclude", "hold"}
        if row["action"] in {"exclude", "hold"}:
            assert row["target"] is None
            continue

        target = row["target"]
        assert target is not None
        if target["domain"] == "descriptor":
            assert target["key"] in descriptor_keys
            assert row["phase"] in descriptor_phases[target["key"]]
        elif target["domain"] == "texture":
            assert target["key"] in texture_keys
            assert row["phase"] in texture_phases[target["key"]]
        elif target["domain"] == "finish_character":
            assert target["key"] in finish_keys
        else:
            assert target["domain"] in {
                "basic_taste",
                "finish_length",
                "level_metric",
            }


def test_card_terms_carry_a_summary_and_known_traits(built):
    """The card reads descriptions from the dictionary file: every term the DB
    can reference (app.db) and every scored axis must have one, and traits must
    come from the trait registry."""
    terms = built[0]["terms"]
    traits = {t["key"] for t in terms if t["type"] == "trait"}
    assert traits
    for t in terms:
        if t["type"] in {"aroma", "aroma_family", "texture", "finish_character"} and t.get("app", {}).get("db"):
            assert t.get("summary", "").strip(), t["key"]
            assert set(t.get("traits", [])) <= traits, t["key"]
        if t["type"] == "axis" and "taxonomy" in t.get("extra", {}):
            assert t.get("summary", "").strip(), t["key"]
