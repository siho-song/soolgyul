#!/usr/bin/env bash
# UserPromptSubmit hook (Claude Code). A prompt containing "#live" opens remote
# writes for that turn only; any other prompt closes them. The mark lives in the shared git
# directory so every worktree of this repository sees the same turn.
set -euo pipefail
INPUT=$(cat)
python3 - "$INPUT" <<'PY'
import json, os, subprocess, sys, time
try:
    payload = json.loads(sys.argv[1] or "{}")
except json.JSONDecodeError:
    payload = {}
try:
    common = subprocess.check_output(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                     text=True, stderr=subprocess.DEVNULL).strip()
except Exception:
    sys.exit(0)
mark = os.path.join(common, "soolgyul-live-turn")
if "#live" in str(payload.get("prompt") or ""):
    with open(mark, "w") as f:
        json.dump({"session_id": payload.get("session_id"), "at": time.time()}, f)
elif os.path.exists(mark):
    try:
        with open(mark) as f:
            owner = json.load(f).get("session_id")
    except Exception:
        owner = None
    if not owner or owner == payload.get("session_id"):
        os.remove(mark)
PY
