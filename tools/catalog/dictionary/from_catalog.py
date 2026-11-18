"""Facts the local catalog itself gives the dictionary.

Reads manual-import/fill-work/rows.sqlite3 (published items only) and writes
into the dictionary (catalog/dictionary):

  drinks       on places: the drinks bottled under the place, which
               나의 용어 사전 filters a saved region by
  abv.range    [10th, 90th percentile] of the items' ABV on a drink, its
               kinds and the wine grapes

Nothing here is knowledge someone wrote; it is counted, so it is regenerated
rather than edited. A region and a regional style carry no counts: how many
bottles a place has, and what they are like taken together, is asked of the
catalog when it is wanted.

Usage:
  python3 -m tools.catalog.dictionary.from_catalog
"""

from __future__ import annotations

import json
import os
import sqlite3
from collections import Counter, defaultdict
from pathlib import Path

from tools.catalog.dictionary import project

ROOT = Path(__file__).resolve().parents[3]
DB = Path(os.environ.get("SOOLGYUL_CATALOG_DB", ROOT / "manual-import/fill-work/rows.sqlite3"))


def published_items():
    con = sqlite3.connect(DB)
    for (current,) in con.execute("select current from products"):
        item = json.loads(current).get("item", {})
        if item.get("publish_status") == "withdrawn":
            continue
        yield item


def percentile_range(values: list[float]) -> list[float]:
    ordered = sorted(values)
    low = ordered[int(len(ordered) * 0.1)]
    high = ordered[max(int(len(ordered) * 0.9) - 1, 0)]
    return [low, high]


CATEGORY_ORDER = ("wine", "whisky", "sake", "korean_traditional")


def with_field(node: dict, name: str, value, after: str) -> None:
    """Sets (or with no value removes) a field of a node, keeping the field order."""
    rest = [(k, v) for k, v in node.items() if k != name]
    node.clear()
    if value and after not in dict(rest):
        node[name] = value
    for k, v in rest:
        node[k] = v
        if k == after and value:
            node[name] = value


def set_place_drinks(tree: dict, bottled: dict[str, set[str]]) -> None:
    """Writes each place's `drinks`: the drinks of the items under it.
    `bottled` maps an item's own region key to the drinks found there; a place
    also carries what the places inside it carry. A place with no bottles has none.
    """
    rows = list(project.places(tree))
    above = {node["key"]: parent for node, parent in rows}
    under: defaultdict[str, set[str]] = defaultdict(set)
    for key, drinks in bottled.items():
        while key is not None:
            under[key] |= drinks
            key = above[key]
    for node, _ in rows:
        drinks = [c for c in CATEGORY_ORDER if c in under[node["key"]]]
        with_field(node, "drinks", drinks, "climate" if "climate" in node else "summary")


def collect() -> tuple[dict[tuple[str, str], dict], dict[str, set[str]]]:
    region_drinks: defaultdict[str, set[str]] = defaultdict(set)
    abv: defaultdict[tuple[str, str], list[float]] = defaultdict(list)
    bottles: Counter = Counter()
    for item in published_items():
        category = (item.get("category") or {}).get("category_key")
        grapes = item.get("grape_variety_keys") or []
        if item.get("region_key") and category:
            region_drinks[item["region_key"]].add(category)
        for key in (("category", category), ("kind", item.get("style_key")), *[("grape", g) for g in grapes[:1]]):
            if key[1]:
                bottles[key] += 1
                if item.get("abv_percent"):
                    abv[key].append(float(item["abv_percent"]))
    derived: dict[tuple[str, str], dict] = {}
    for key in bottles:
        if len(abv[key]) >= 20:
            derived[key] = {"abv_range": percentile_range(abv[key])}
    return derived, region_drinks


def set_abv_range(node: dict, facts: dict | None) -> None:
    abv = dict(node.get("abv", {}))
    abv.pop("range", None)
    if facts:
        abv = {**({"bounds": abv.pop("bounds")} if "bounds" in abv else {}), "range": facts["abv_range"], **abv}
    with_field(node, "abv", abv, "summary")


def apply(tree: dict) -> dict:
    places = {node["key"] for node, _ in project.places(tree)}
    derived, region_drinks = collect()
    unknown = sorted(k for k in region_drinks if k not in places)
    if unknown:
        raise SystemExit(f"items point at region keys the dictionary lacks: {unknown[:10]}")
    set_place_drinks(tree, region_drinks)
    for drink in tree["drinks"].values():
        set_abv_range(drink, derived.get(("category", drink["key"])))
        for kind in drink["kinds"]:
            set_abv_range(kind, derived.get(("kind", kind["key"])))
        for grape in drink.get("grapes", []):
            set_abv_range(grape, derived.get(("grape", grape["key"])))
    return tree


def main() -> int:
    tree = apply(project.load())
    project.save(tree)
    places = sum(1 for _ in project.places(tree))
    ranged = sum(1 for d in tree["drinks"].values()
                 for row in [d, *d["kinds"], *d.get("grapes", [])] if "range" in row.get("abv", {}))
    print(json.dumps({"places": places, "rows_with_abv_range": ranged}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
