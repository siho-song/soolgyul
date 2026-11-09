#!/usr/bin/env bash
# PreToolUse hook for Edit/Write (Claude Code). Reads the tool call as
# JSON on stdin. Denies edits to secret files (.env and its variants except templates, .key,
# .pem, credentials.json, service-account*.json) and to the hook files themselves.
set -euo pipefail
INPUT=$(cat)
python3 - "$INPUT" <<'PY'
import json, os, re, sys

try:
    payload = json.loads(sys.argv[1] or "{}")
except json.JSONDecodeError:
    print("{}"); sys.exit(0)
tool_input = payload.get("tool_input") or {}
paths = []
if isinstance(tool_input, dict):
    for key in ("file_path", "path"):
        if isinstance(tool_input.get(key), str):
            paths.append(tool_input[key])

TEMPLATES = {".env.example", ".env.sample", ".env.template"}

def is_secret(path):
    name = os.path.basename(path.replace("\\", "/"))
    return (name == ".env" or (name.startswith(".env.") and name not in TEMPLATES)
            or name == "credentials.json" or name.endswith((".key", ".pem"))
            or (name.startswith("service-account") and name.endswith(".json")))

def is_hook(path):
    return re.search(r"tools/hooks/|\.claude/settings\.json$", path.replace("\\", "/")) is not None

for path in paths:
    if is_secret(path):
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
              "permissionDecision": "deny",
              "permissionDecisionReason": f"Secret file is edited by the user, not by the agent: {path}"}}, ensure_ascii=False))
        sys.exit(0)
    if is_hook(path):
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
              "permissionDecision": "deny",
              "permissionDecisionReason": f"Hook files are edited by the user, not by the agent: {path}"}}, ensure_ascii=False))
        sys.exit(0)
print("{}")
PY
