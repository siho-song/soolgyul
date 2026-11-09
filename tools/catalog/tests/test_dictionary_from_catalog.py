"""from_catalog counts the local catalog into the dictionary's region, kind, grape and category rows."""

import json
import sqlite3
from pathlib import Path

import pytest

from tools.catalog.dictionary import from_catalog, project

REGION_CHAIN = ("fr_pauillac", "fr_bordeaux", "fr")


def _item(i: int, **overrides) -> dict:
    item = {
        "id": f"p{i}", "name_ko": f"샤토 테스트 {i}", "publish_status": "published",
        "category": {"category_key": "wine"}, "style_key": "red_wine", "region_key": REGION_CHAIN[0],
        "grape_variety_keys": ["cabernet_sauvignon"], "abv_percent": 10.0 + i,
    }
    item.update(overrides)
    return item


def test_published_bottles_are_counted_up_the_region_tree_and_stale_facts_cleared(
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

    rows = {(t["type"], t["key"]): t for t in from_catalog.apply(project.load())["terms"]}

    for key in REGION_CHAIN:
        assert rows[("region", key)]["extra"]["bottles"] == 25
    assert not any("bottles" in t.get("extra", {}) for (kind, key), t in rows.items()
                   if kind == "region" and key not in REGION_CHAIN)
    red_wine = rows[("kind", "red_wine")]
    assert red_wine["extra"]["bottles"] == 25
    assert red_wine["hints"]["abv_range"] == [12.0, 31.0] and red_wine["hints"]["abv_bottles"] == 25
    assert rows[("category", "wine")]["extra"]["bottles"] == 25
    assert rows[("grape", "cabernet_sauvignon")]["hints"]["bottled_regions"] == [{"region": "fr_bordeaux", "bottles": 25}]
    bourbon = rows[("kind", "bourbon")]  # counted from the real catalog before; nothing in this DB
    assert "bottles" not in bourbon.get("extra", {}) and "abv_range" not in bourbon.get("hints", {})
