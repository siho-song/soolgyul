"""Origin of a level value (docs/specs/SENSORY_LEVEL_SOURCE_GRADES.md).

Both the local working copy and the served database store, under
``level_sources``, only whether each level was read for the bottle or copied
from its kind:

  1  병에서 읽음     the maker, a retailer, a critic or users described this bottle
  4  종류에서 가져옴  not this bottle's value (kind table, style/category median,
                     a sibling product, a fill)

Older rows may still hold 2 or 3 (the old outside-rating and user-vote grades);
they read as 1. A source that is no evidence (a single word read as a level,
one blog post) has no entry: the level is dropped with it.

Usage:
  python3 -m tools.catalog.sensory.level_source_grades            # distribution + unknown names
"""

from __future__ import annotations

import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DB = ROOT / "manual-import/fill-work/rows.sqlite3"

BOTTLE, KIND = 1, 4

# Source names of values that are not this bottle's own.
KIND_NAMES = {
    "table", "style_median", "category_median", "same_line", "fill", "abv", "style", "catalog",
    "thesool_ai", "fashionstore-rule", "1887", "3000",
}
# Source names that are no evidence: the level goes with them.
NO_EVIDENCE = {"term_map", "blog", "sakeblog"}


def grade_of(source: str | int) -> int | None:
    """1 or 4 for a source name or a stored grade, or None when the value is
    no evidence."""
    if isinstance(source, int):
        if source == KIND:
            return KIND
        return BOTTLE if 1 <= source <= 3 else None
    key = source.split(":", 1)[0]
    if key in NO_EVIDENCE or source in NO_EVIDENCE:
        return None
    if key in KIND_NAMES or source in KIND_NAMES:
        return KIND
    return BOTTLE


def grade_sources(level_sources: dict[str, str | int]) -> dict[str, int]:
    """level_sources with names → the 1 / 4 the served table stores; sources
    without a grade are left out (their level is dropped too)."""
    out = {}
    for axis, source in level_sources.items():
        grade = grade_of(source)
        if grade is not None:
            out[axis] = grade
    return out


def report() -> dict:
    con = sqlite3.connect(DB)
    grades: Counter = Counter()
    dropped: Counter = Counter()
    for (current,) in con.execute("select current from products"):
        row = json.loads(current)
        for axis, source in (row.get("level_sources") or {}).items():
            grade = grade_of(source)
            if grade is None:
                dropped[source] += 1
            else:
                grades[grade] += 1
    return {
        "grades": dict(sorted(grades.items())),
        "dropped": dict(dropped),
    }


def main() -> int:
    print(json.dumps(report(), ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
