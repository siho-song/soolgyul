"""The dictionary tree holds each fact once and every link lands on a row."""

import collections
import json
import re
import unicodedata

import pytest

from tools.catalog.dictionary import project

AROMA_ORIGINS = {"material", "ripeness", "cask", "ageing", "yeast", "process", "added", "nuruk",
                 "surroundings", "soil", "unsaid"}
CLIMATES = {"cool", "moderate", "warm", "hot", None}
LEVEL_WORDS = {"low", "mid", "high"}


@pytest.fixture(scope="module")
def tree():
    return project.load()


def keys(rows) -> list[str]:
    return [r["key"] for r in rows]


def assert_unique(found: list[str], what: str) -> None:
    twice = [k for k, n in collections.Counter(found).items() if n > 1]
    assert not twice, (what, twice)


def test_every_file_is_written_in_the_dictionary_layout(tree):
    for drink in project.DRINKS:
        assert project.path(drink).read_text(encoding="utf-8") == project.render(tree["drinks"][drink]) + "\n"
    for part in project.PARTS:
        assert project.path(part).read_text(encoding="utf-8") == project.render(tree[part]) + "\n"


def test_rows_are_unique_where_they_are_named(tree):
    assert_unique([w["key"] for w, *_ in project.senses(tree)], "words for what is sensed")
    assert_unique(keys(tree["senses"]["families"]), "families")
    for d in project.DRINKS:
        assert_unique([n["key"] for n, _ in project.places(tree, d)], f"{d} places")
        for part in project.MAKING_PARTS:
            # A group may share its item's key (포도 the group holds 포도 the ingredient).
            assert_unique([i["key"] for i, _ in project.name_tags(tree, part, d)], f"{d} {part}")
            assert_unique(keys(tree["drinks"][d]["making"][part]), f"{d} {part} groups")
    kinds = [k["key"] for d in tree["drinks"].values() for k in d["kinds"]]
    assert_unique(kinds, "kinds")
    for drink in tree["drinks"].values():
        assert_unique([s["key"] for s, _ in project.styles(drink)], f"{drink['key']} styles")
        for part in ("grapes", "producers", "label_words"):
            assert_unique(keys(drink.get(part, [])), f"{drink['key']} {part}")


def test_every_link_lands_on_a_row(tree):
    # A line may name a whole family of aromas (과실, 흙) as well as one aroma.
    aromas = {w["key"] for w, t, *_ in project.senses(tree) if t == "aroma"} | set(keys(tree["senses"]["families"]))
    kinds = {k["key"] for d in tree["drinks"].values() for k in d["kinds"]}
    grapes = keys(tree["drinks"]["wine"]["grapes"])
    all_styles = {s["key"] for d in tree["drinks"].values() for s, _ in project.styles(d)}

    def lands(row: dict, drink: dict) -> None:
        axes = {a["key"] for a in drink["axes"]}
        assert set(row.get("taste", {})) <= axes, row["key"]
        for level in row.get("taste", {}).values():
            # "varies": the row runs several ways on this axis (a grape made dry to sweet), so it explains nothing there.
            assert level is None or level in LEVEL_WORDS or level in ("none", "varies") or level in range(1, 6), row["key"]
        assert set(row.get("aromas", {})) <= AROMA_ORIGINS, row["key"]
        held = [k for group in row.get("aromas", {}).values() for k in group]
        assert set(held) <= aromas, (row["key"], set(held) - aromas)
        assert set(row.get("always", [])) <= set(held), row["key"]
        assert set(row.get("replaces_aromas", [])) <= aromas, row["key"]

    for drink in tree["drinks"].values():
        # A drink's rows link to its own places and its own making.
        places = {n["key"] for n, _ in project.places(tree, drink["key"])}
        making = {i["key"] for part in ("processes", "maturations") for i, _ in project.name_tags(tree, part, drink["key"])}
        for kind in drink["kinds"]:
            lands(kind, drink)
        for style, kind in project.styles(drink):
            lands(style, drink)
            assert style["place"] is None or style["place"] in places, style["key"]
            assert set(style.get("find_in_places", [])) <= places, style["key"]
            assert set(style["grapes"]) <= set(grapes), style["key"]
            assert set(style["making"]) <= set(making), style["key"]
            assert set(style.get("also_of_kinds", [])) <= kinds, style["key"]
        for grape in drink.get("grapes", []):
            lands(grape, drink)
            assert set(grape.get("styles", [])) <= all_styles, grape["key"]
        for producer in drink["producers"]:
            lands(producer, drink)
        for word in drink["label_words"]:
            lands(word, drink)
        for part in project.MAKING_PARTS:
            for item, _ in project.name_tags(tree, part, drink["key"]):
                lands(item, drink)


def test_every_word_for_what_is_sensed_folds_into_an_offered_word_or_is_kept_back(tree):
    words = {w["key"]: w for w, *_ in project.senses(tree)}
    offered = {k for k, w in words.items() if "choice" in w}
    groups = {g["key"] for g in tree["senses"]["choice"]["groups"]}
    traits = {t["key"] for t in tree["senses"]["traits"]}
    orders = [w["choice"]["order"] for k, w in words.items() if k in offered]
    assert_unique([str(o) for o in orders], "choice order")
    for key, w in words.items():
        if "choice" in w:
            assert w["choice"]["group"] in groups, key
            assert set(w.get("search_related", [])) <= offered, key
        if "shown_as" in w:
            assert w["shown_as"] is None or w["shown_as"] in words, key
        assert set(w.get("traits", [])) <= traits, key
        assert (w.get("summary") or "").strip(), key


def test_the_db_term_contract_names_only_rows_the_dictionary_has(tree):
    tax = project.taxonomy()
    kinds = {k["key"] for d in tree["drinks"].values() for k in d["kinds"]}
    assert {s["style_key"] for s in tax["primary_styles"]} <= kinds
    assert set(tax["style_redirects"].values()) <= kinds
    for part, field in (("process_terms", "term_key"), ("maturation_terms", "term_key")):
        name = "processes" if part == "process_terms" else "maturations"
        assert {t[field] for t in tax["production"][part]} <= {i["key"] for i, _ in project.name_tags(tree, name)}
    assert {t["ingredient_key"] for t in tax["ingredients"]["terms"]} <= {
        i["key"] for i, _ in project.name_tags(tree, "ingredients")}


def test_a_label_spelling_is_what_a_label_prints(tree):
    """`label` is the spelling printed on a label, shown before the Korean name:
    every grape, sparkling style and sake grade has one, and it is never Korean."""
    rows = []
    for drink in tree["drinks"].values():
        for kind in drink["kinds"]:
            rows.append((kind, drink["key"] == "sake"))
            for style, _ in project.styles({"kinds": [kind]}):
                descriptive = style["key"] in ("new_world_traditional_sparkling", "cataluna_sparkling", "piemonte_sparkling")
                rows.append((style, kind["key"] == "sparkling_wine" and not descriptive))
        rows += [(g, True) for g in drink.get("grapes", [])]
        rows += [(w, False) for w in drink["label_words"]]
    rows += [(i, False) for part in ("ingredients", "processes", "maturations") for i, _ in project.name_tags(tree, part)]
    for row, named in rows:
        label = row.get("label")
        if named:
            assert label, row["key"]
        if label is None:
            continue
        assert label == label.strip() and label, row["key"]
        assert not any("가" <= ch <= "힣" for ch in label), row["key"]
        # A two-name term spells both names, in the order of its Korean name.
        assert label.count("·") == row["ko"].split("(")[0].count("·"), row["key"]


def test_a_find_word_is_written_in_lower_case(tree):
    """Bottle names are lowered before a grape's or a style's find words are looked
    for in them, so a find word with a capital letter never matches."""
    for drink in tree["drinks"].values():
        rows = list(drink.get("grapes", [])) + [s for s, _ in project.styles(drink)]
        for row in rows:
            for word in row.get("find") or []:
                assert word == word.lower(), (row["key"], word)


def test_label_words_are_explained(tree):
    """A label word explains itself or names the row that does."""
    explained = {k["key"]: k for d in tree["drinks"].values() for k in d["kinds"]}
    explained |= {s["key"]: s for d in tree["drinks"].values() for s, _ in project.styles(d)}
    explained |= {i["key"]: i for part in ("ingredients", "processes", "maturations")
                  for i, _ in project.name_tags(tree, part)}
    for drink in tree["drinks"].values():
        for word in drink["label_words"]:
            target = word.get("explained_by")
            if target:
                assert "summary" not in word, word["key"]
                assert (explained[target.split(":")[1]].get("summary") or "").strip(), word["key"]
            else:
                assert (word.get("summary") or "").strip(), word["key"]


def test_a_shared_place_or_making_row_is_one_row(tree):
    """A place or a making row in two drink files is the same row: same names,
    same place above or group. Only what it says of each drink differs."""
    def same(rows_by_drink):
        first: dict[str, tuple] = {}
        for d, key, row in rows_by_drink:
            if key in first:
                assert row == first[key][1], (key, first[key][0], d)
            else:
                first[key] = (d, row)
    name_fields = ("ko", "en", "aliases", "label", "find", "on_labels", "stage")
    same((d, n["key"], ({f: n.get(f) for f in name_fields}, above))
         for d in project.DRINKS for n, above in project.places(tree, d))
    for part in project.MAKING_PARTS:
        same((d, i["key"], ({f: i.get(f) for f in name_fields}, g["key"]))
             for d in project.DRINKS for i, g in project.name_tags(tree, part, d))
        same((d, g["key"], {f: g.get(f) for f in ("ko", "en", "find")})
             for d in project.DRINKS for g in tree["drinks"][d]["making"][part])


def test_a_place_is_found_by_any_of_its_names_inside_its_country(tree):
    names = project.place_names(tree, "wine")
    assert project.find_place(names, "fr", "Burgundy") == "fr_bourgogne"
    assert project.find_place(names, "fr", "Bourgogne > Beaune") == "fr_beaune"
    assert project.find_place(names, "us", "Napa Valley AVA") == "us_napa_valley_ava"
    # The same name in another country is another place.
    assert project.find_place(names, "us", "Central Valley") == "us_central_valley"
    assert project.find_place(names, "cl", "Central Valley") == "cl_central_valley"
    assert project.find_place(names, "cl", "Toro") is None
    # Of places one inside the other, the narrowest, whichever is in brackets.
    assert project.find_place(names, "it", "Barolo DOCG (Piemonte)") == "it_barolo"
    assert project.find_place(names, "fr", "Bordeaux (Entre-Deux-Mers)") == "fr_entre_deux_mers"
    # Places side by side: the label's, outside the brackets, else the place
    # holding both, since the bottle is from one of them and which is not known.
    assert project.find_place(names, "fr", "Pays d'Oc (Corbières)") == "fr_pays_d_oc"
    assert project.find_place(names, "us", "California (Lodi / Clarksburg)") == "us_california"
    assert project.find_place(names, "es", "Rioja / Navarra") == "es"
    whisky = project.place_names(tree, "whisky")
    assert project.find_place(whisky, "us", "켄터키 (Bardstown, Kentucky)") == "us_bardstown"
    traditional = project.place_names(tree, "korean_traditional")
    assert project.find_place(traditional, "kr", "충북 충주") == "kr_chungju"
    # After a province, only a place inside it: 경기도 광주 is not 광주광역시.
    assert project.find_place(traditional, "kr", "경기도 광주") == "kr_gwangju_si"
    assert project.find_place(traditional, "kr", "광주") == "kr_gwangju"
    assert project.find_place(traditional, "kr", "경남 고성") == "kr_goseong_gyeongnam"
    assert project.find_place(traditional, "kr", "강원도 고성") == "kr_goseong"


def test_a_place_names_its_climate_by_a_known_word(tree):
    for node, above in project.places(tree):
        if above is None:
            assert "climate" not in node, node["key"]
        else:
            assert node["climate"] in CLIMATES, node["key"]


APPELLATION_TAG = re.compile(
    r"(?<![A-Za-z])(AVA|AOC|AOP|DOCG|DOCa|DOC|DOQ|DOP|DO|IGT|IGP|GI|UGA|MGA|VQA|WO|DAC|PDO|PGI)(?![A-Za-z])")


def _name_key(name: str) -> str:
    """A name as a match sees it: no case, accents or punctuation."""
    name = "".join(c for c in unicodedata.normalize("NFKD", name) if not unicodedata.combining(c))
    return re.sub(r"[\s\-_/.,'’]+", " ", name.lower()).strip()


def test_a_place_has_one_korean_name_one_label_name_and_its_other_names(tree):
    """`ko` is the Korean spelling most used, `en` the name a label prints, and
    `aliases` every other spelling a bottle or a collected value may use (an
    English name, another Korean spelling, the name with its appellation tag).
    The two names carry no appellation tag (AVA, DOC, ...): that is a grade,
    not a name. Within one country no two places answer to the same name, so a
    name and a country find one place."""
    country: dict[str, str] = {}
    named: dict[tuple[str, str], set[str]] = collections.defaultdict(set)
    for node, above in project.places(tree):
        key = node["key"]
        country[key] = key if above is None else country[above]
        ko, en, aliases = node["ko"], node.get("en"), node.get("aliases", [])
        assert ko and not re.search(r"[A-Za-z()]", ko), (key, ko)
        assert en and not re.search(r"[가-힣()]", en), (key, en)
        assert not APPELLATION_TAG.search(ko) and not APPELLATION_TAG.search(en), (key, ko, en)
        # Case does not make another name (the term table refuses Orotava next to orotava).
        folded = [a.casefold() for a in aliases]
        assert len(set(folded)) == len(folded) and not {ko.casefold(), en.casefold()} & set(folded), key
        for name in (ko, en, *aliases):
            named[(country[key], _name_key(name))].add(key)
    twice = {name: keys for name, keys in named.items() if len(keys) > 1}
    assert not twice, twice


def test_evidence_names_only_rows_that_remain(tree):
    evidence = json.loads(project.EVIDENCE.read_text(encoding="utf-8"))
    rows = {f"region:{n['key']}" for n, _ in project.places(tree)}
    rows |= {f"{t}:{w['key']}" for w, t, *_ in project.senses(tree)}
    rows |= {f"aroma_family:{f['key']}" for f in tree["senses"]["families"]}
    rows |= {f"trait:{t['key']}" for t in tree["senses"]["traits"]}
    for part, type_ in (("ingredients", "ingredient"), ("processes", "process"), ("maturations", "maturation")):
        rows |= {f"{type_}:{i['key']}" for i, _ in project.name_tags(tree, part)}
        rows |= {f"{type_}_type:{g['key']}" for g in project.making_groups(tree, part)}
    rows |= {f"axis:{a['key']}" for a in tree["senses"]["axes"]}
    for drink in tree["drinks"].values():
        rows.add(f"category:{drink['key']}")
        rows |= {f"kind:{k['key']}" for k in drink["kinds"]}
        rows |= {f"regional_style:{s['key']}" for s, _ in project.styles(drink)}
        rows |= {f"grape:{g['key']}" for g in drink.get("grapes", [])}
        rows |= {f"producer:{p['key']}" for p in drink["producers"]}
        rows |= {f"label_word:{w['key']}" for w in drink["label_words"]}
    assert set(evidence["terms"]) <= rows, sorted(set(evidence["terms"]) - rows)[:10]
