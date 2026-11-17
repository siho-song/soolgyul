"""Facts the local catalog itself gives the dictionary.

Reads manual-import/fill-work/rows.sqlite3 (published items only) and writes
into catalog/dictionary/terms.json:

  categories       on region rows: the drinks bottled under the row, which
                   나의 용어 사전 filters a saved region by
  hints.abv_range  [10th, 90th percentile] of the items' ABV on category,
                   kind and grape rows (+ hints.abv_bottles)
  extra.bottles    how many published items a category, kind or grape carries
  hints.bottled_regions  on grape rows: the regions (a country's direct
                   child) its bottles come from, most first, with counts

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


def set_region_categories(dictionary: dict, bottled: dict[str, set[str]]) -> None:
    """Writes each region row's `categories`: the drinks of the items under it.

    `bottled` maps an item's own region key to the drinks found there; a row
    also carries what the rows below it carry. A row with no bottles has none.
    """
    regions = {t["key"]: t for t in dictionary["terms"] if t["type"] == "region"}
    under: defaultdict[str, set[str]] = defaultdict(set)
    for key, drinks in bottled.items():
        while key is not None:
            under[key] |= drinks
            key = regions[key]["parent"]
    for key, t in regions.items():
        rest = [(k, v) for k, v in t.items() if k != "categories"]
        drinks = [c for c in CATEGORY_ORDER if c in under[key]]
        t.clear()
        for k, v in rest:
            t[k] = v
            if k == "parent" and drinks:
                t["categories"] = drinks


def collect() -> tuple[dict[tuple[str, str], dict], dict[str, Counter], dict[str, set[str]]]:
    region_drinks: defaultdict[str, set[str]] = defaultdict(set)
    abv: defaultdict[tuple[str, str], list[float]] = defaultdict(list)
    bottles: Counter = Counter()
    grape_regions: defaultdict[str, Counter] = defaultdict(Counter)
    for item in published_items():
        category = (item.get("category") or {}).get("category_key")
        grapes = item.get("grape_variety_keys") or []
        if item.get("region_key"):
            for g in grapes:
                grape_regions[g][item["region_key"]] += 1
            if category:
                region_drinks[item["region_key"]].add(category)
        for key in (("category", category), ("kind", item.get("style_key")), *[("grape", g) for g in grapes[:1]]):
            if key[1]:
                bottles[key] += 1
                if item.get("abv_percent"):
                    abv[key].append(float(item["abv_percent"]))
    derived: dict[tuple[str, str], dict] = {}
    for key, count in bottles.items():
        entry = {"bottles": count}
        if len(abv[key]) >= 20:
            entry["abv_range"] = percentile_range(abv[key])
            entry["abv_bottles"] = len(abv[key])
        derived[key] = entry
    return derived, grape_regions, region_drinks


def top_region(key: str, regions: dict) -> str:
    """The country's direct child above a region key (fr_pauillac -> fr_bordeaux); the country itself if none."""
    chain = [key]
    while regions[chain[-1]]["parent"]:
        chain.append(regions[chain[-1]]["parent"])
    return chain[-2] if len(chain) > 1 else chain[0]


def apply(dictionary: dict) -> dict:
    regions = {t["key"]: t for t in dictionary["terms"] if t["type"] == "region"}
    derived, grape_regions, region_drinks = collect()
    unknown = sorted(k for k in region_drinks if k not in regions)
    if unknown:
        raise SystemExit(f"items point at region keys the dictionary lacks: {unknown[:10]}")
    set_region_categories(dictionary, region_drinks)
    bottled: dict[str, list[dict]] = {}
    for grape, counts in grape_regions.items():
        rolled: Counter = Counter()
        for key, count in counts.items():
            rolled[top_region(key, regions)] += count
        bottled[grape] = [{"region": k, "bottles": n} for k, n in rolled.most_common()]
    for t in dictionary["terms"]:
        if t["type"] not in ("category", "kind", "grape"):
            continue
        facts = derived.get((t["type"], t["key"]))
        hints = t.setdefault("hints", {})
        extra = t.setdefault("extra", {})
        for stale in ("abv_range", "abv_bottles"):
            hints.pop(stale, None)
        if t["type"] == "grape":
            hints.pop("bottled_regions", None)
            if bottled.get(t["key"]):
                hints["bottled_regions"] = bottled[t["key"]]
        extra.pop("bottles", None)
        if facts:
            extra["bottles"] = facts["bottles"]
            if "abv_range" in facts:
                hints["abv_range"] = facts["abv_range"]
                hints["abv_bottles"] = facts["abv_bottles"]
        if not hints:
            del t["hints"]
        if not extra:
            del t["extra"]
    return dictionary


def main() -> int:
    dictionary = apply(project.load())
    project.save(dictionary)
    regions = sum(1 for t in dictionary["terms"] if t["type"] == "region")
    ranged = sum(1 for t in dictionary["terms"] if "abv_range" in t.get("hints", {}))
    print(json.dumps({"region_rows": regions, "rows_with_abv_range": ranged}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
