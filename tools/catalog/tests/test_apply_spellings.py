"""apply_spellings rewrites variant name_ko spellings to the canonical one, on a backed-up DB only."""

import json
import sqlite3
from pathlib import Path

import pytest

from tools.catalog.field_rules.apply_spellings import main
from tools.catalog.field_rules.check import SPELLINGS

CANON, VARIANT = "소비뇽", "쇼비뇽"


def _db(path: Path, names: list[str]) -> None:
    con = sqlite3.connect(path)
    con.execute("create table products (id text primary key, current text)")
    rows = [(f"p{i}", json.dumps({"item": {"id": f"p{i}", "name_ko": name}, "body": 3}, ensure_ascii=False))
            for i, name in enumerate(names)]
    con.executemany("insert into products values (?, ?)", rows)
    con.commit()
    con.close()


def _rows(path: Path) -> dict[str, dict]:
    con = sqlite3.connect(path)
    return {id_: json.loads(current) for id_, current in con.execute("select id, current from products order by id")}


def _names(path: Path) -> list[str]:
    return [row["item"]["name_ko"] for row in _rows(path).values()]


def test_variants_become_canonical_only_at_word_boundaries_after_a_backup(tmp_path: Path) -> None:
    assert VARIANT in json.loads(SPELLINGS.read_text(encoding="utf-8"))[CANON], "pick a pair that is in spellings.json"
    db, backup = tmp_path / "rows.sqlite3", tmp_path / "before.sqlite3"
    names = [f"프레이 {VARIANT} 블랑", f"프레이 {CANON} 블랑", f"가{VARIANT}"]
    _db(db, names)

    assert main(["--db", str(db), "--dry-run"]) == 0
    assert _names(db) == names and not backup.exists()
    with pytest.raises(SystemExit):
        main(["--db", str(db)])  # applying without --backup is refused
    assert _names(db) == names

    assert main(["--db", str(db), "--backup", str(backup)]) == 0
    assert _names(db) == [f"프레이 {CANON} 블랑", f"프레이 {CANON} 블랑", f"가{VARIANT}"]
    assert _rows(db)["p0"]["body"] == 3  # the rest of the row is untouched
    assert _names(backup) == names
