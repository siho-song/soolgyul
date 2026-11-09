"""이름 표기 통일 적용기 (규칙 I4).

spellings.json의 변형 표기를 정본으로 바꾼다. 옛 표기는 검색의 소리 접기가 찾는다.
로컬 작업본에만 쓴다. 바꾸기 전에 백업 파일을 만든다.

    python -m tools.catalog.field_rules.apply_spellings --dry-run
    python -m tools.catalog.field_rules.apply_spellings --backup manual-import/fill-work/rows.before-spelling-2026-10-26.sqlite3
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
from pathlib import Path

from .check import DEFAULT_DB, SPELLINGS


def replacements() -> list[tuple[re.Pattern[str], str]]:
    table = json.loads(SPELLINGS.read_text(encoding="utf-8"))
    pairs = [(v, canon) for canon, vs in table.items() if not canon.startswith("_") for v in vs]
    # 긴 변형(여러 낱말, 긴 낱말)부터 바꿔야 짧은 변형이 먼저 끼어들지 않는다.
    pairs.sort(key=lambda p: -len(p[0]))
    return [(re.compile(r"(?<![가-힣])" + re.escape(v) + r"(?![가-힣])"), canon) for v, canon in pairs]


def canonical_name(name: str, rules) -> str:
    out = name
    for pat, canon in rules:
        out = pat.sub(canon, out)
    return out


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--db", type=Path, default=DEFAULT_DB)
    p.add_argument("--backup", type=Path, help="적용 전에 이 경로로 복사한다 (적용할 때 필수)")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--show", type=int, default=15)
    a = p.parse_args(argv)
    if not a.dry_run and not a.backup:
        p.error("--backup 없이 적용할 수 없어요")
    rules = replacements()
    conn = sqlite3.connect(a.db)
    changes: list[tuple[str, str, str, str]] = []
    for id_, current in conn.execute("select id, current from products"):
        row = json.loads(current)
        item = row["item"]
        name = item.get("name_ko") or ""
        new = canonical_name(name, rules)
        if new == name:
            continue
        item["name_ko"] = new
        changes.append((id_, name, new, json.dumps(row, ensure_ascii=False)))
    print(f"바꿀 이름 {len(changes):,}개")
    for id_, old, new, _ in changes[: a.show]:
        print(f"  {old}  →  {new}")
    if a.dry_run:
        return 0
    if a.backup.exists():
        p.error(f"백업 파일이 이미 있어요: {a.backup}")
    shutil.copyfile(a.db, a.backup)
    conn.execute("begin immediate")
    conn.executemany("update products set current = ? where id = ?", [(cur, id_) for id_, _, _, cur in changes])
    conn.commit()
    print(f"적용 완료. 백업: {a.backup}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
