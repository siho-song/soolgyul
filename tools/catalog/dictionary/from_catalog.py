"""Facts the local catalog itself gives the dictionary.

Reads manual-import/fill-work/rows.sqlite3 (published items only) and writes
into catalog/dictionary/terms.json:

  region rows      extra.bottles = items under the row (item.region_key and
                   every parent above it); the rows themselves are edited
                   knowledge and are not generated here
  categories       on region rows: the drinks bottled under the row, which
                   나의 용어 사전 filters a saved region by
  hints.abv_range  [10th, 90th percentile] of the items' ABV on category,
                   kind, grape and regional-style rows (+ hints.abv_bottles)
  extra.bottles    how many published items a kind, grape, region or regional
                   style carries (a wine's regional style is the one the card
                   reads it as, see tools/catalog/sensory/style_profiles.py)
  hints.bottled_regions  on grape rows: the regions (a country's direct
                   child) its bottles come from, most first, with counts

Nothing here is knowledge someone wrote; it is counted, so it is regenerated
rather than edited.

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
from tools.catalog.sensory.style_profiles import StyleProfileResolver, load_style_profiles

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


def region_path(key: str | None, regions: dict) -> str:
    """The item's region line as the card reads it; empty for no region or a country."""
    return project.region_label(key, regions) if key and regions[key]["parent"] else ""


def regional_style(resolver: StyleProfileResolver, item: dict, regions: dict) -> str | None:
    """The deepest regional-style row the item falls in, as the card reads it."""
    entries = resolver.matching_entries(
        item.get("style_key"),
        item.get("name_ko") or item.get("name_en") or "",
        region_path(item.get("region_key"), regions),
        grape_keys=item.get("grape_variety_keys") or [],
    )
    matched = [entry["key"] for kind, entry in entries if kind == "region"]
    return matched[-1] if matched else None


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


def collect(regions: dict) -> tuple[Counter, dict[tuple[str, str], dict], dict[str, Counter], dict[str, set[str]]]:
    resolver = StyleProfileResolver(load_style_profiles())
    region_bottles: Counter = Counter()
    region_drinks: defaultdict[str, set[str]] = defaultdict(set)
    abv: defaultdict[tuple[str, str], list[float]] = defaultdict(list)
    bottles: Counter = Counter()
    grape_regions: defaultdict[str, Counter] = defaultdict(Counter)
    for item in published_items():
        category = (item.get("category") or {}).get("category_key")
        kind = item.get("style_key")
        grapes = item.get("grape_variety_keys") or []
        if item.get("region_key"):
            for g in grapes:
                grape_regions[g][item["region_key"]] += 1
        keys = [
            ("category", category),
            ("kind", kind),
            *[("grape", g) for g in grapes[:1]],
            ("regional_style", regional_style(resolver, item, regions)),
        ]
        for key in keys:
            if key[1]:
                bottles[key] += 1
                if item.get("abv_percent"):
                    abv[key].append(float(item["abv_percent"]))
        if item.get("region_key"):
            region_bottles[item["region_key"]] += 1
            if category:
                region_drinks[item["region_key"]].add(category)
    derived: dict[tuple[str, str], dict] = {}
    for key, count in bottles.items():
        entry = {"bottles": count}
        if len(abv[key]) >= 20:
            entry["abv_range"] = percentile_range(abv[key])
            entry["abv_bottles"] = len(abv[key])
        derived[key] = entry
    return region_bottles, derived, grape_regions, region_drinks


def top_region(key: str, regions: dict) -> str:
    """The country's direct child above a region key (fr_pauillac -> fr_bordeaux); the country itself if none."""
    chain = [key]
    while regions[chain[-1]]["parent"]:
        chain.append(regions[chain[-1]]["parent"])
    return chain[-2] if len(chain) > 1 else chain[0]


def apply(dictionary: dict) -> dict:
    regions = {t["key"]: t for t in dictionary["terms"] if t["type"] == "region"}
    region_bottles, derived, grape_regions, region_drinks = collect(regions)
    unknown = sorted(k for k in region_bottles if k not in regions)
    if unknown:
        raise SystemExit(f"items point at region keys the dictionary lacks: {unknown[:10]}")
    set_region_categories(dictionary, region_drinks)
    under: Counter = Counter()
    for key, count in region_bottles.items():
        while key is not None:
            under[key] += count
            key = regions[key]["parent"]
    bottled: dict[str, list[dict]] = {}
    for grape, counts in grape_regions.items():
        rolled: Counter = Counter()
        for key, count in counts.items():
            rolled[top_region(key, regions)] += count
        bottled[grape] = [{"region": k, "bottles": n} for k, n in rolled.most_common()]
    for t in dictionary["terms"]:
        if t["type"] == "region":
            facts = {"bottles": under[t["key"]]} if under[t["key"]] else None
        else:
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
