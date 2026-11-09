"""backup_local_db.sh copies the working DB, then keeps the newest KEEP backups plus the pinned one."""

import os
import sqlite3
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools/catalog/backup_local_db.sh"
KEEP = 7


def _work_dir(tmp_path: Path) -> Path:
    con = sqlite3.connect(tmp_path / "rows.sqlite3")
    con.execute("create table products (id text primary key, current text)")
    con.execute("insert into products values ('p1', '{}')")
    con.commit()
    con.close()
    return tmp_path


def _backup(work: Path, *args: str) -> Path:
    env = {**os.environ, "SOOL_FILL_WORK_DIR": str(work)}
    done = subprocess.run(["bash", str(SCRIPT), *args], env=env, capture_output=True, text=True, check=True)
    return Path(done.stdout.strip())


def _older_backups(backups: Path, count: int, newest_age_seconds: float) -> list[Path]:
    """Fake earlier backups, oldest first, all older than anything the script makes now."""
    files = [backups / f"rows.2026-01-{i + 1:02d}-0000.sqlite3" for i in range(count)]
    base = time.time() - newest_age_seconds - 60 * count
    for i, f in enumerate(files):
        f.write_bytes(b"")
        os.utime(f, (base + 60 * i, base + 60 * i))
    return files


def test_backup_is_a_readable_copy_and_prune_keeps_newest_plus_pinned(tmp_path: Path) -> None:
    work = _work_dir(tmp_path)
    backups = work / "backups"
    backups.mkdir()
    old = _older_backups(backups, 9, newest_age_seconds=600)
    (backups / "pinned.txt").write_text(old[0].name + "\n")

    out = _backup(work, "before the next job")

    assert out.parent == backups
    assert sqlite3.connect(out).execute("select id from products").fetchall() == [("p1",)]
    survivors = {p.name for p in backups.glob("rows.*.sqlite3")}
    assert survivors == {old[0].name, *(f.name for f in old[-(KEEP - 1):]), out.name}
    assert (backups / "index.tsv").read_text().splitlines()[-1] == f"{out.name}\t-\tbefore the next job"


def test_pin_marks_the_new_backup_and_it_survives_later_prunes(tmp_path: Path) -> None:
    work = _work_dir(tmp_path)
    backups = work / "backups"

    pinned = _backup(work, "--pin", "live sync")
    assert (backups / "pinned.txt").read_text().strip() == pinned.name
    assert (backups / "index.tsv").read_text().splitlines()[-1] == f"{pinned.name}\tpin\tlive sync"

    long_ago = time.time() - 100_000
    os.utime(pinned, (long_ago, long_ago))
    newer = _older_backups(backups, KEEP + 1, newest_age_seconds=600)
    latest = _backup(work, "another job")

    survivors = {p.name for p in backups.glob("rows.*.sqlite3")}
    assert survivors == {pinned.name, *(f.name for f in newer[-(KEEP - 1):]), latest.name}
