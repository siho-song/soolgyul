#!/usr/bin/env bash
# Temporary: refactor guard. Deleted with refactor_guard/ when the refactor ends.
# Draws every guarded screen and writes the card corpus into <out>.
#   bash refactor_guard/run.sh <out dir>
set -euo pipefail
out=$(mkdir -p "$1" && cd "$1" && pwd)
cd "$(dirname "$0")/.."
GUARD_OUT="$out/screens" flutter test refactor_guard
${DENO:-deno} run --node-modules-dir=none --allow-read --allow-write --allow-env refactor_guard/card_corpus.ts "$out/cards"
