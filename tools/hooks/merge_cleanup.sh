#!/usr/bin/env bash
# PostToolUse hook for Bash (Claude Code). Reads the tool call as JSON on stdin.
# After a `gh pr merge` command it tidies what merged work leaves behind:
# every local branch that is the head of a PR already merged into dev (same
# name, same tip commit) loses its worktree and then the branch itself.
# A worktree with uncommitted or untracked files is left alone and reported,
# and main, master and dev are never touched. The remote branch is GitHub's
# to delete (the repository deletes head branches on merge).
# What was removed, what was left, and the worktrees that have no branch go
# back to the agent as context. Any other command passes "{}".
set -euo pipefail
INPUT=$(cat)
python3 - "$INPUT" <<'PY'
import json, os, re, subprocess, sys

PROTECTED_BRANCHES = {"main", "master", "dev"}

def done(context=None):
    if context:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": context}}, ensure_ascii=False))
    else:
        print("{}")
    sys.exit(0)

def run(args, timeout=60):
    try:
        return subprocess.run(args, text=True, capture_output=True, timeout=timeout)
    except Exception as error:
        return subprocess.CompletedProcess(args, 1, "", str(error))

def git(*args):
    return run(["git", *args])

try:
    payload = json.loads(sys.argv[1] or "{}")
except json.JSONDecodeError:
    done()
tool_input = payload.get("tool_input") or {}
command = str(tool_input.get("command") or "") if isinstance(tool_input, dict) else ""
if not re.search(r"(^|[\s;&|(])gh\s+pr\s+merge\b", command):
    done()

# The session may have moved out of the repository; fall back to the project folder.
for folder in (os.getcwd(), os.environ.get("CLAUDE_PROJECT_DIR") or ""):
    if folder and os.path.isdir(folder):
        os.chdir(folder)
        if git("rev-parse", "--git-dir").returncode == 0:
            break
else:
    done()

def worktrees():
    trees = []
    for block in git("worktree", "list", "--porcelain").stdout.strip().split("\n\n"):
        tree = {"path": None, "branch": None}
        for line in block.splitlines():
            if line.startswith("worktree "):
                tree["path"] = line[len("worktree "):]
            elif line.startswith("branch refs/heads/"):
                tree["branch"] = line[len("branch refs/heads/"):]
        if tree["path"]:
            trees.append(tree)
    return trees

trees = worktrees()
if not trees:
    done()
main_checkout = trees[0]["path"]
os.chdir(main_checkout)  # the folder this hook started in may be the one removed

listed = run(["gh", "pr", "list", "--state", "merged", "--base", "dev", "--limit", "200",
              "--json", "number,headRefName,headRefOid"])
try:
    merged_heads = {(pr["headRefName"], pr["headRefOid"]): pr["number"]
                    for pr in json.loads(listed.stdout)}
except Exception:
    done("merge_cleanup: could not read the merged PRs from GitHub, so nothing was removed. "
         "Remove the merged branch and its worktree by hand.")

removed, left = [], []
branches = git("for-each-ref", "refs/heads", "--format=%(refname:short) %(objectname)").stdout
for line in branches.splitlines():
    name, _, tip = line.partition(" ")
    number = merged_heads.get((name, tip))
    if number is None or name in PROTECTED_BRANCHES:
        continue
    tree = next((t for t in trees if t["branch"] == name), None)
    if tree and tree["path"] == main_checkout:
        left.append(f"{name} (PR #{number}): checked out in the main checkout")
        continue
    if tree:
        result = git("worktree", "remove", tree["path"])
        if result.returncode != 0:
            left.append(f"{tree['path']} on {name} (PR #{number}): it has uncommitted or "
                        "untracked files; save or drop them, then remove the worktree and the branch")
            continue
        removed.append(f"worktree {tree['path']}")
    if git("branch", "-D", name).returncode == 0:
        removed.append(f"branch {name} (PR #{number})")

git("worktree", "prune")
run(["git", "fetch", "origin", "--prune", "--quiet"], timeout=30)

no_branch = [t["path"] for t in worktrees()[1:] if t["branch"] is None]

report = []
if removed:
    report.append("removed " + ", ".join(removed))
if left:
    report.append("left " + "; ".join(left))
if no_branch:
    report.append("worktrees with no branch still here: " + ", ".join(no_branch)
                  + " (remove the ones this session made once their task is done)")
done("merge_cleanup: " + ". ".join(report) + "." if report else None)
PY
