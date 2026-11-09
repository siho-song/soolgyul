"""Grades of level-value evidence (docs/specs/SENSORY_LEVEL_SOURCE_GRADES.md).

Both the local working copy and the served database store only the grade of
the evidence behind each level under ``level_sources`` (since 2026-10-29; the
source names live in the collection folders that produced the values):

  1  제조사 공식        the maker's own statement (spec sheet, label, legal designation)
  2  외부 평가          someone else rated this bottle (monopoly clocks, retailer
                        scales, notes read into levels, critics, importers)
  3  사용자 평가 모음    aggregated user votes or our readers' answers
  4  종류 추정          not this bottle's value (kind table, style/category median,
                        a sibling product, a fill)

A source that is no evidence (a single word read as a level, one blog post)
has no grade: the level is dropped with it.

Usage:
  python3 -m tools.catalog.sensory.level_source_grades            # distribution + unknown names
  python3 -m tools.catalog.sensory.level_source_grades --sql      # the rule rows for a migration
"""

from __future__ import annotations

import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DB = ROOT / "manual-import/fill-work/rows.sqlite3"

PRODUCER, EXTERNAL, USERS, KIND = 1, 2, 3, 4

# Exact source names. A name with a ':' is matched on the part before it.
GRADES: dict[str, int | None] = {
    # 1 제조사 공식
    "producer": PRODUCER, "producer (quoting Vivino)": PRODUCER, "producer via retailer": PRODUCER,
    "brewery_site": PRODUCER, "sakenomy_spec": PRODUCER, "name": PRODUCER, "label": PRODUCER,
    "label_term": PRODUCER, "datagokr": PRODUCER, "prtimes": PRODUCER, "brand": PRODUCER,
    # 2 외부 평가
    "wine21_scale": EXTERNAL, "wine21_note": EXTERNAL, "wine21": EXTERNAL, "dailyshot": EXTERNAL,
    "dailyshot_words": EXTERNAL, "note": EXTERNAL, "note_modifier": EXTERNAL, "retailer": EXTERNAL,
    "critic": EXTERNAL, "vinmonopolet": EXTERNAL, "alko": EXTERNAL, "systembolaget": EXTERNAL,
    "saq": EXTERNAL, "lcbo": EXTERNAL, "importer": EXTERNAL, "sdh_note": EXTERNAL,
    "thesool_note": EXTERNAL, "thesool": EXTERNAL, "thesool_column": EXTERNAL, "urbansake": EXTERNAL,
    "tippsy": EXTERNAL, "tippsy_note": EXTERNAL, "shop_note": EXTERNAL, "sbsaq_note": EXTERNAL,
    "beercartel": EXTERNAL, "beerhunter": EXTERNAL, "twe": EXTERNAL, "press": EXTERNAL,
    "trade": EXTERNAL, "jetro": EXTERNAL, "meininger": EXTERNAL, "sieum": EXTERNAL,
    "review": EXTERNAL, "brewers_assoc": EXTERNAL, "research": EXTERNAL, "mottox": EXTERNAL,
    # 3 사용자 평가 모음
    "sakenomy": USERS, "user": USERS,
    # 4 종류 추정
    "table": KIND, "style_median": KIND, "category_median": KIND, "same_line": KIND, "fill": KIND,
    "abv": KIND, "style": KIND, "catalog": KIND, "thesool_ai": KIND, "fashionstore-rule": KIND,
    "1887": KIND, "3000": KIND,
    # no evidence: the level goes with it
    "term_map": None, "blog": None, "sakeblog": None,
}

# Every other bare name so far is a sake shop or retailer quoting the maker's
# tasting description: external evidence about that bottle.
DEFAULT_GRADE = EXTERNAL


def grade_of(source: str | int) -> int | None:
    """The grade of a source name, or None when the value is no evidence.
    A grade already stored (1–4) passes through."""
    if isinstance(source, int):
        return source if 1 <= source <= 4 else None
    key = source.split(":", 1)[0]
    if key.startswith("user_"):
        key = "user"
    if key in GRADES:
        return GRADES[key]
    if source in GRADES:
        return GRADES[source]
    return DEFAULT_GRADE


def is_known(source: str | int) -> bool:
    if isinstance(source, int):
        return 1 <= source <= 4
    key = source.split(":", 1)[0]
    return key in GRADES or source in GRADES or key.startswith("user_")


def grade_sources(level_sources: dict[str, str | int]) -> dict[str, int]:
    """level_sources with names → the grades the served table stores; sources
    without a grade are left out (their level is dropped too)."""
    out = {}
    for axis, source in level_sources.items():
        grade = grade_of(source)
        if grade is not None:
            out[axis] = grade
    return out


def sql_rule_rows() -> str:
    """VALUES rows (prefix, grade) for a migration; NULL grade = drop."""
    rows = []
    for name, grade in GRADES.items():
        rows.append(f"('{name.replace(chr(39), chr(39) * 2)}', {grade if grade is not None else 'null'})")
    return ",\n".join(rows)


def report() -> dict:
    con = sqlite3.connect(DB)
    grades: Counter = Counter()
    unknown: Counter = Counter()
    dropped: Counter = Counter()
    for (current,) in con.execute("select current from products"):
        row = json.loads(current)
        for axis, source in (row.get("level_sources") or {}).items():
            if not is_known(source):
                unknown[str(source).split(":", 1)[0]] += 1
            grade = grade_of(source)
            if grade is None:
                dropped[source] += 1
            else:
                grades[grade] += 1
    return {
        "grades": dict(sorted(grades.items())),
        "dropped": dict(dropped),
        "unknown_names_graded_as_external": len(unknown),
        "unknown_cells": sum(unknown.values()),
    }


def main() -> int:
    if "--sql" in sys.argv:
        print(sql_rule_rows())
        return 0
    print(json.dumps(report(), ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
