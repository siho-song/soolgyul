"""from_catalog counts the local catalog into the dictionary's drinks, kinds, grapes and places."""

import json
import sqlite3
from pathlib import Path

import pytest

from tools.catalog.dictionary import from_catalog, project

REGION = "fr_pauillac"


def _item(i: int, **overrides) -> dict:
    item = {
        "id": f"p{i}", "name_ko": f"샤토 테스트 {i}", "publish_status": "published",
        "category": {"category_key": "wine"}, "style_key": "red_wine", "region_key": REGION,
        "grape_variety_keys": ["cabernet_sauvignon"], "abv_percent": 10.0 + i,
    }
    item.update(overrides)
    return item


def _catalog(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, items: list[dict]) -> None:
    db = tmp_path / "rows.sqlite3"
    con = sqlite3.connect(db)
    con.execute("create table products (id text primary key, current text)")
    con.executemany("insert into products values (?, ?)", [(it["id"], json.dumps({"item": it})) for it in items])
    con.commit()
    con.close()
    monkeypatch.setattr(from_catalog, "DB", db)


def test_published_bottles_are_counted_and_stale_facts_cleared(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    _catalog(tmp_path, monkeypatch, [_item(i) for i in range(25)] + [_item(99, publish_status="withdrawn")])

    tree = from_catalog.apply(project.load())
    places = {node["key"]: node for node, _ in project.places(tree)}

    # Which drinks a place is of is the file it sits in, not a field.
    assert not any("drinks" in node for node in places.values())
    # A place carries no counts: they are asked of the catalog when wanted.
    assert not any("abv" in node or "taste" in node for node in places.values())
    kinds = {k["key"]: k for d in tree["drinks"].values() for k in d["kinds"]}
    assert kinds["red_wine"]["abv"]["range"] == [12.0, 31.0]
    assert tree["drinks"]["wine"]["abv"]["range"] == [12.0, 31.0]
    # Counted from the real catalog before; nothing in this DB.
    assert "range" not in kinds["bourbon"].get("abv", {})


def test_a_bottle_at_a_place_its_drink_file_lacks_stops_the_run(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    # 포이악 is a wine place only; a whisky bottle there names no whisky place.
    _catalog(tmp_path, monkeypatch, [_item(1, category={"category_key": "whisky"})])
    with pytest.raises(SystemExit, match="fr_pauillac"):
        from_catalog.apply(project.load())
