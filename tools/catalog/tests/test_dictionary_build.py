"""The one dictionary stays complete, consistent and up to date with its sources."""

import json

import pytest

from tools.catalog.dictionary import project
from tools.catalog.dictionary.build import TYPES, build


@pytest.fixture(scope="module")
def built():
    return build()


def test_dictionary_file_is_what_its_views_rebuild(built):
    dictionary, _ = built
    assert project.load() == dictionary, "run tools/catalog/dictionary/build.py"


def test_evidence_is_kept_apart_from_what_the_app_and_the_functions_read():
    """terms.json carries no source; saving what was loaded writes the same two files."""
    file = json.loads(project.DICTIONARY.read_text(encoding="utf-8"))
    evidence = json.loads(project.EVIDENCE.read_text(encoding="utf-8"))
    assert "sources" not in file
    for t in project.flatten(file)["terms"]:
        assert all("sources" not in holder for _, _, holder in project.source_holders(t)), t["key"]
    terms, kept = project.without_evidence(project.load())
    assert (project.nest(terms), kept) == (file, evidence)


def test_every_row_sits_in_its_section_of_the_file():
    """The file states the sections the tools keep, and no row is left outside them."""
    file = json.loads(project.DICTIONARY.read_text(encoding="utf-8"))
    assert [(tuple(s["path"]), s["group"], s["item"], s["link"]) for s in file["layout"]] == list(project.SECTIONS)
    held = {s["item"]: tuple((h["under"], h["item"], h["names"]) for h in s["held"])
            for s in file["layout"] if "held" in s}
    assert held == project.HELD
    assert "terms" not in file
    assert project.nest(project.flatten(file)) == file


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


def test_label_spellings_sit_on_the_rows_a_guide_chip_names(built):
    """names.label is the spelling printed on a label, shown before the Korean
    name: every grape, sparkling style and sake grade has one, and it is
    never Korean. A cask or method keeps its spelling in hints.label_words."""
    terms = built[0]["terms"]
    for t in terms:
        label = t["names"].get("label")
        chip_named = (
            t["type"] == "grape"
            or (t["type"] == "kind" and t.get("parent") == "sake")
            # No one spelling is printed for a descriptive name (a region's sparkling wines taken together).
            or (t["type"] == "regional_style" and "sparkling" in t["key"]
                and t["key"] not in ("new_world_traditional_sparkling", "cataluna_sparkling", "piemonte_sparkling"))
        )
        if chip_named:
            assert label, t["key"]
        if label is None:
            continue
        assert t["type"] in {"grape", "regional_style", "kind", "ingredient", "label_word"}, t["key"]
        assert label == label.strip() and label, t["key"]
        assert not any("가" <= ch <= "힣" for ch in label), t["key"]
        # A two-name term spells both names, in the order of its Korean name.
        assert label.count("·") == t["names"]["ko"].split("(")[0].count("·"), t["key"]


def test_label_words_are_explained_and_say_how_far_they_are_checked(built):
    """A label_word row explains its word or names the row that does, and a
    text written without a checked source says so (문헌 근거 미확인)."""
    terms = built[0]["terms"]
    by_key = {f"{t['type']}:{t['key']}": t for t in terms}
    words = [t for t in terms if t["type"] == "label_word"]
    assert words
    for t in words:
        assert t.get("categories"), t["key"]
        target = t.get("extra", {}).get("explained_by")
        if target:
            assert "summary" not in t, t["key"]
            assert by_key[target].get("summary", "").strip(), t["key"]
            assert by_key[target]["type"] != "label_word", t["key"]
        else:
            assert t.get("summary", "").strip(), t["key"]
    written = words + [t for t in terms if t["type"] == "ingredient" and "summary" in t]
    for t in written:
        if "summary" not in t:
            continue
        # No text here was checked against a source when it was written; a
        # row with quotes carries what the dictionary already held for it.
        assert "문헌 근거 미확인" in t["extra"]["summary_note"], t["key"]
        if t.get("sources"):
            assert all(s.get("quote") and s.get("url") for s in t["sources"]), t["key"]
            assert t["extra"]["summary_grade"] == 3, t["key"]
        else:
            assert t["extra"]["summary_grade"] == 4, t["key"]


def test_a_place_names_its_climate_and_a_style_what_it_is_made_from_by_known_words(built):
    terms = built[0]["terms"]
    keys = {}
    for t in terms:
        keys.setdefault(t["type"], set()).add(t["key"])
    made_from = {"grapes": keys["grape"], "making": keys["process"] | keys["maturation"]}
    for t in terms:
        hints = t.get("hints", {})
        if "climate" in hints:
            assert t["type"] == "region" and hints["climate"] in project.CLIMATES, t["key"]
        for slot, known in made_from.items():
            if slot not in hints:
                continue
            link = hints[slot]
            assert t["type"] == "regional_style", t["key"]
            assert link["keys"] and set(link["keys"]) <= known, (t["key"], slot)
            assert link["by"] in project.LINK_BASES, (t["key"], slot)
            # Written from the style's own summary, checked against no source yet.
            assert set(link) <= {"keys", "by", "note"} and link.get("note", "문헌 근거 미확인") == "문헌 근거 미확인"


def test_a_taste_level_is_a_step_from_one_to_five_or_the_word_it_was_written_as(built):
    """A regional style and a grape state every level as a step; the rows whose
    steps are not collected yet still hold low, mid or high."""
    for t in built[0]["terms"]:
        for axis, line in t.get("taste", {}).items():
            level = line["level"]
            still = axis == "carbonation" and level == "none"
            if t["type"] in ("regional_style", "grape"):
                assert still or (type(level) is int and 1 <= level <= 5), (t["key"], axis, level)
            else:
                assert still or level in project.LEVEL_WORDS or (type(level) is int and 1 <= level <= 5), (t["key"], axis, level)
            assert project.level_word(axis, level) in (*project.LEVEL_WORDS, "none")
