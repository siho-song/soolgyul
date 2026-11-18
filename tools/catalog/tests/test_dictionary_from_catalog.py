"""from_catalog counts the local catalog into the dictionary's drinks, kinds, grapes and places."""

import json
import sqlite3
from pathlib import Path

import pytest

from tools.catalog.dictionary import from_catalog, project

REGION_CHAIN = ("fr_pauillac", "fr_haut_medoc", "fr_medoc", "fr_bordeaux", "fr")


def _item(i: int, **overrides) -> dict:
    item = {
        "id": f"p{i}", "name_ko": f"샤토 테스트 {i}", "publish_status": "published",
        "category": {"category_key": "wine"}, "style_key": "red_wine", "region_key": REGION_CHAIN[0],
        "grape_variety_keys": ["cabernet_sauvignon"], "abv_percent": 10.0 + i,
    }
    item.update(overrides)
    return item


def test_published_bottles_are_counted_and_stale_facts_cleared(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    db = tmp_path / "rows.sqlite3"
    con = sqlite3.connect(db)
    con.execute("create table products (id text primary key, current text)")
    items = [_item(i) for i in range(25)] + [_item(99, publish_status="withdrawn")]
    con.executemany("insert into products values (?, ?)", [(it["id"], json.dumps({"item": it})) for it in items])
    con.commit()
    con.close()
    monkeypatch.setattr(from_catalog, "DB", db)

    tree = from_catalog.apply(project.load())
    places = {node["key"]: node for node, _ in project.places(tree)}

    for key in REGION_CHAIN:
        assert places[key]["drinks"] == ["wine"]
    assert not any("drinks" in node for key, node in places.items() if key not in REGION_CHAIN)
    # A place carries no counts: they are asked of the catalog when wanted.
    assert not any("abv" in node or "taste" in node for node in places.values())
    kinds = {k["key"]: k for d in tree["drinks"].values() for k in d["kinds"]}
    assert kinds["red_wine"]["abv"]["range"] == [12.0, 31.0]
    assert tree["drinks"]["wine"]["abv"]["range"] == [12.0, 31.0]
    # Counted from the real catalog before; nothing in this DB.
    assert "range" not in kinds["bourbon"].get("abv", {})
