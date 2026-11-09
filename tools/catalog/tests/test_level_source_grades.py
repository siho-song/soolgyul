from tools.catalog.sensory.level_source_grades import grade_of, grade_sources


def test_grades_follow_the_kind_of_evidence():
    assert grade_of("producer") == 1
    assert grade_of("retailer:thewhiskyexchange.com") == 2  # a ':' name is matched on its prefix
    assert grade_of("jizake-mie") == 2  # an unknown bare name is a shop quoting the maker
    assert grade_of("user_2026-10-24") == 3
    assert grade_of("style_median") == 4
    assert grade_of("term_map") is None
    assert grade_of("blog:someone.hatenablog.com") is None


def test_stored_grades_pass_through_and_no_evidence_drops_the_level():
    assert grade_of(2) == 2
    assert grade_of(7) is None
    assert grade_sources({"sweetness": 1, "acidity": "note", "body": "term_map"}) == {"sweetness": 1, "acidity": 2}
