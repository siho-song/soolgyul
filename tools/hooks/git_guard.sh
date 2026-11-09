#!/usr/bin/env bash
# PreToolUse hook for Bash (Claude Code). Reads the tool call as JSON on stdin.
# Branch flow: feature branches are cut from dev and merged into dev by PR;
# dev → main is a release PR the user opens and merges.
# Denies: commit/push/merge while on main, master or dev; any push that targets
# main/master/dev; deleting main/dev; any force push; `gh pr create` whose base
# is not dev; merging a PR whose base is main (or that would delete dev);
# and shell edits to the hook files or hook settings. Everything else passes "{}".
set -euo pipefail
INPUT=$(cat)
python3 - "$INPUT" <<'PY'
import json, re, shlex, subprocess, sys

try:
    payload = json.loads(sys.argv[1] or "{}")
except json.JSONDecodeError:
    print("{}"); sys.exit(0)
tool_input = payload.get("tool_input") or {}
command = str(tool_input.get("command") or tool_input.get("cmd") or "") if isinstance(tool_input, dict) else ""

PROTECTED_BRANCHES = {"main", "master", "dev"}
RELEASE_TARGETS = {"main", "master"}

def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason}}, ensure_ascii=False))
    sys.exit(0)

def tokens(text):
    try:
        return shlex.split(text, posix=True)
    except ValueError:
        return text.split()

def segments(text):
    # Split a shell line on ; && || | so each simple command is checked alone.
    return [s.strip() for s in re.split(r"\s*(?:;|&&|\|\||\|)\s*", text) if s.strip()]

def branch_of(ref):
    ref = ref.split(":")[-1]
    ref = re.sub(r"^refs/heads/", "", ref)
    return ref

PROTECTED_FILES = r"tools/hooks/|\.claude/settings\.json"
if re.search(PROTECTED_FILES, command) and re.search(r"(>|\bsed\s+-i|\brm\b|\bmv\b|\bcp\b|\btee\b|\bchmod\b|\bpython3?\b)", command):
    deny("Hook files are edited by the user, not by the agent.")

if not re.search(r"(^|[\s;&|])(git|gh)\s+", command):
    print("{}"); sys.exit(0)

if re.search(r"git\s+push\b.*(\s-f\b|--force\b|--force-with-lease\b)", command):
    deny("Force push is never allowed.")

try:
    current = subprocess.check_output(["git", "rev-parse", "--abbrev-ref", "HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
except Exception:
    current = ""

for seg in segments(command):
    toks = tokens(seg)
    # drop leading env assignments / cd prefixes handled by segments()
    while toks and "=" in toks[0] and not toks[0].startswith("-"):
        toks = toks[1:]
    if not toks:
        continue
    prog = toks[0]

    if prog == "git" and len(toks) > 1:
        sub = toks[1]
        if current in PROTECTED_BRANCHES and sub in {"commit", "push", "merge", "rebase", "cherry-pick", "revert", "reset"}:
            deny(f"On {current}: work happens on a feature branch cut from dev, merged by PR into dev. dev → main is the user's release PR.")
        if sub == "push":
            args = [t for t in toks[2:] if not t.startswith("-")]
            if "--delete" in toks or "-d" in toks:
                for a in args[1:]:
                    if branch_of(a) in PROTECTED_BRANCHES:
                        deny(f"Deleting {branch_of(a)} on the remote is not allowed.")
            for a in args[1:]:  # args[0] is the remote
                if a.startswith(":") and a[1:] and branch_of(a) in PROTECTED_BRANCHES:
                    deny(f"Deleting {branch_of(a)} on the remote is not allowed.")
                if branch_of(a) in PROTECTED_BRANCHES:
                    deny(f"Pushing to {branch_of(a)} is not allowed; open a PR into dev instead.")
            if len(args) <= 1 and current in PROTECTED_BRANCHES:
                deny(f"Pushing {current} is not allowed.")
        if sub == "branch" and any(t in {"-D", "-d", "--delete"} for t in toks):
            for a in toks[2:]:
                if a in PROTECTED_BRANCHES:
                    deny(f"Deleting the local {a} branch is not allowed.")

    if prog == "gh" and len(toks) > 2 and toks[1] == "pr":
        sub = toks[2]
        def option(names):
            for i, t in enumerate(toks):
                if t in names and i + 1 < len(toks):
                    return toks[i + 1]
                for n in names:
                    if t.startswith(n + "="):
                        return t.split("=", 1)[1]
            return None
        if sub in {"create", "edit"}:
            base = option({"--base", "-B"})
            if sub == "create" and base is None:
                deny("gh pr create needs --base dev; PRs into main are release PRs the user opens.")
            if base is not None and base != "dev":
                deny(f"PR base must be dev, not {base}. dev → main is the user's release PR.")
        if sub == "merge":
            if "--delete-branch" in toks or "-d" in toks:
                pass  # checked below against the head branch
            target = next((t for t in toks[3:] if not t.startswith("-")), None)
            view = ["gh", "pr", "view"] + ([target] if target else []) + ["--json", "baseRefName,headRefName"]
            try:
                info = json.loads(subprocess.check_output(view, text=True, stderr=subprocess.DEVNULL, timeout=20))
            except Exception:
                deny("Could not read the PR's base branch; merge it from the GitHub UI or retry with the PR number.")
            if info.get("baseRefName") in RELEASE_TARGETS:
                deny("PRs into main are release PRs; the user merges them.")
            if ("--delete-branch" in toks or "-d" in toks) and info.get("headRefName") in PROTECTED_BRANCHES:
                deny(f"Merging would delete {info.get('headRefName')}; drop --delete-branch.")

print("{}")
PY
