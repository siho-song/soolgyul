from pathlib import Path

from tools.catalog.field_rules.check import Vocab, check

ROOT = Path(__file__).resolve().parents[3]


def _row(**item):
    base = {
        "id": item.get("id", "p1"), "name_ko": "글렌파클라스 12년", "name_en": "Glenfarclas 12",
        "category": {"category_key": "whisky"},
        "style_key": "single_malt_whisky", "country_code": "GB", "producer_key": "glenfarclas",
        "abv_percent": 43.0, "abv_source": "producer",
        "age_statement_years": 12, "publish_status": "published", "published_at": "2026-01-01",
    }
    base.update(item)
    return {
        "item": base, "level_sources": {"body": "note"}, "body": 4, "aroma_tags": ["vanilla"],
    }


def test_clean_row_breaks_no_rule():
    report = check([_row()], Vocab.load())
    assert {rule for rule in report.hits if report.hits[rule]} == set()


def test_each_rule_catches_its_own_violation():
    vocab = Vocab.load()
    cases = {
        "I1": _row(name_ko=" 글렌파클라스  12년"),
        "I2": _row(name_ko="글렌파클라스, 12년"),
        "I3": _row(name_ko="글렌파클라스 12년 700ml"),
        "I4": _row(name_ko="프레이 브라더스 카베르네 소비뇽", age_statement_years=None),
        "I5": _row(name_en="글렌파클라스 12"),
        "I9": _row(age_statement_years=15),
        "I10": _row(name_ko="제임스 E.페퍼 버번"),
        "I13": _row(name_en="GLENFARCLAS 12 YEARS OLD"),
        "I12": _row(name_ko="글렌파클라스 12년 에디션", name_en="Glenfarclas 12"),
        "C1": _row(style_key="red_wine"),
        "C2": _row(ingredient_keys=["cherry"]),
        "C3": _row(ingredient_keys=["barley", "barley"]),
        "N1": _row(abv_percent=95.0),
        "N2": _row(abv_source=None),
        "N3": _row(name_ko="글렌파클라스 150년", age_statement_years=150),
        "N4": _row(country_code="gb"),
        "N5": _row(producer_key=None),
        "N6": _row(region_key="fr_nowhere"),
        "S3": _row(category={"category_key": "wine"}, style_key="white_wine", abv_percent=12.0, age_statement_years=None),
    }
    cases["S3"]["carbonation"] = 3
    for rule, row in cases.items():
        report = check([row], vocab)
        assert report.count(rule) == 1, (rule, dict(report.hits))


def test_identity_duplicates_and_sensory_rules():
    vocab = Vocab.load()
    twins = [_row(id="a"), _row(id="b")]
    assert check(twins, vocab).count("I8") == 2
    bad = _row()
    bad["level_sources"] = {}
    bad["aroma_tags"] = ["과일", None]
    report = check([bad], vocab)
    assert report.count("S1") == 1 and len(report.hits["S2"]) == 2


def test_search_fold_matches_the_db_fixture():
    import json
    from tools.catalog.field_rules.check import search_fold
    fixture = json.loads((ROOT / "supabase/functions/_tests/fixtures/korean_sound_fold.json").read_text(encoding="utf-8"))
    assert fixture, "fixture empty"
    assert {t: search_fold(t) for t in fixture} == fixture
    assert search_fold("퀴숑") == search_fold("뀌숑")
    assert search_fold("샤도네이") == search_fold("샤르도네")
    assert search_fold("피노 누아") == search_fold("피노누아")
    assert search_fold("쇼비뇽") == search_fold("소비뇽")
    assert search_fold("셰리") == search_fold("쉐리") == search_fold("세리")
    assert search_fold("쿠숑") != search_fold("퀴숑")
