#!/usr/bin/env bash
# PreToolUse hook for Bash and Supabase MCP tools (Claude Code). Denies remote
# writes (live migrations, SQL writes, Edge Function deploys, Storage/REST writes, production
# web deploys) unless the user wrote "#live" in the current prompt. Reads stay open.
set -euo pipefail
INPUT=$(cat)
python3 - "$INPUT" <<'PY'
import json, os, re, subprocess, sys

try:
    payload = json.loads(sys.argv[1] or "{}")
except json.JSONDecodeError:
    print("{}"); sys.exit(0)
tool = str(payload.get("tool_name") or "")
tool_input = payload.get("tool_input") or {}
if not isinstance(tool_input, dict):
    tool_input = {}
command = str(tool_input.get("command") or tool_input.get("cmd") or "")
sql = str(tool_input.get("query") or "")

WRITE_SQL = r"\b(insert|update|delete|merge|upsert|alter|drop|create|truncate|grant|revoke|comment\s+on|refresh|vacuum|reindex|call)\b|\\copy\b[^\n]*\bfrom\b"

def remote_write():
    if tool.startswith("mcp__supabase__"):
        name = tool.rsplit("__", 1)[-1]
        if name in {"apply_migration", "deploy_edge_function", "create_branch", "delete_branch",
                    "merge_branch", "reset_branch", "rebase_branch", "pause_project", "restore_project"}:
            return f"Supabase MCP {name}"
        if name == "execute_sql" and re.search(WRITE_SQL, sql, re.I):
            return "SQL write through Supabase MCP"
        return None
    if not command:
        return None
    c = command
    if re.search(r"\bsupabase\s+(db\s+(push|reset)|migration\s+(repair|up|squash)|functions\s+(deploy|delete)|secrets\s+(set|unset)|storage\s+(cp|mv|rm)|seed\b)", c) \
            and not re.search(r"--dry-run|--local\b", c):
        return "Supabase CLI remote command"
    if re.search(r"\bpsql\b", c) and re.search(r"SUPABASE_DB_(POOLER_)?URL|supabase\.(co|com)", c) \
            and re.search(WRITE_SQL, c, re.I):
        return "SQL write to the live database"
    if re.search(r"\bcurl\b", c) and re.search(r"supabase\.co", c) \
            and re.search(r"-X\s*(POST|PATCH|PUT|DELETE)|--request\s+(POST|PATCH|PUT|DELETE)|--data|\s-d\s|--upload-file|-T\s", c):
        return "REST or Storage write to Supabase"
    if re.search(r"deploy_web\.sh[^\n;&|]*--prod|\bvercel\b[^\n;&|]*(--prod|\b(rm|remove|alias|promote|rollback)\b)", c):
        return "production web deploy"
    return None

touched = command + " " + str(tool_input.get("file_path") or tool_input.get("path") or "")
if "soolgyul-live-turn" in touched:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": "The #live mark is set only by the user's prompt."}}))
    sys.exit(0)

reason = remote_write()
if reason is None:
    print("{}"); sys.exit(0)

try:
    common = subprocess.check_output(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                     text=True, stderr=subprocess.DEVNULL).strip()
    with open(os.path.join(common, "soolgyul-live-turn")) as f:
        mark = json.load(f)
except Exception:
    mark = None
session = payload.get("session_id")
if mark and (not session or not mark.get("session_id") or mark.get("session_id") == session):
    print("{}"); sys.exit(0)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": f"{reason} needs '#live' in the user's current prompt. Finish locally and ask the user."}},
      ensure_ascii=False))
PY
