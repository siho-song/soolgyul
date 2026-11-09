#!/usr/bin/env bash
# Back up the local catalog DB (manual-import/fill-work/rows.sqlite3) before a write job,
# then prune old backups.
#
#   tools/catalog/backup_local_db.sh "what the next job does"
#   tools/catalog/backup_local_db.sh --pin "live sync 2026-10-24"   # kept until the next --pin
#
# Backups live in manual-import/fill-work/backups/ as rows.YYYY-MM-DD-HHMM.sqlite3. The newest
# KEEP files stay, plus the one pinned file (the state right before the last live sync).
# Everything else is deleted. backups/index.tsv records when and why each backup was made.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK="${SOOL_FILL_WORK_DIR:-$ROOT/manual-import/fill-work}"  # override only for tests
DB="$WORK/rows.sqlite3"
DIR="$WORK/backups"
KEEP=7
mkdir -p "$DIR"

PIN=0
if [ "${1:-}" = "--pin" ]; then PIN=1; shift; fi
NOTE="${1:-}"
if [ -z "$NOTE" ]; then echo "usage: backup_local_db.sh [--pin] \"note\"" >&2; exit 2; fi

STAMP=$(date +%Y-%m-%d-%H%M)
OUT="$DIR/rows.$STAMP.sqlite3"
if [ -e "$OUT" ]; then OUT="$DIR/rows.$STAMP-$(date +%S).sqlite3"; fi

python3 - "$DB" "$OUT" <<'PY'
import sqlite3, sys
src = sqlite3.connect(sys.argv[1], timeout=300)
dst = sqlite3.connect(sys.argv[2])
src.backup(dst)
dst.close(); src.close()
PY

printf '%s\t%s\t%s\n' "$(basename "$OUT")" "$([ $PIN = 1 ] && echo pin || echo -)" "$NOTE" >> "$DIR/index.tsv"
if [ $PIN = 1 ]; then basename "$OUT" > "$DIR/pinned.txt"; fi

PINNED=$(cat "$DIR/pinned.txt" 2>/dev/null || true)
ls -1t "$DIR"/rows.*.sqlite3 | tail -n +$((KEEP + 1)) | while read -r f; do
  [ "$(basename "$f")" = "$PINNED" ] && continue
  rm -f "$f"
done
echo "$OUT"
