"""The merge cleanup hook removes only what a merged PR left behind."""

import json
import os
import subprocess
from pathlib import Path

import pytest

HOOK = Path(__file__).resolve().parents[2] / "tools" / "hooks" / "merge_cleanup.sh"


def git(folder, *args):
    done = subprocess.run(
        ["git", *args], cwd=folder, text=True, capture_output=True, check=True
    )
    return done.stdout.strip()


def commit(folder, name):
    (Path(folder) / name).write_text(name)
    git(folder, "add", name)
    git(folder, "commit", "-m", name)
    return git(folder, "rev-parse", "HEAD")


@pytest.fixture
def repo(tmp_path, monkeypatch):
    for key, value in {
        "GIT_AUTHOR_NAME": "t",
        "GIT_AUTHOR_EMAIL": "t@example.com",
        "GIT_COMMITTER_NAME": "t",
        "GIT_COMMITTER_EMAIL": "t@example.com",
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_SYSTEM": os.devnull,
    }.items():
        monkeypatch.setenv(key, value)
    monkeypatch.delenv("CLAUDE_PROJECT_DIR", raising=False)

    origin = tmp_path / "origin.git"
    subprocess.run(["git", "init", "--bare", "-b", "dev", str(origin)], check=True, capture_output=True)
    main = tmp_path / "main"
    subprocess.run(["git", "init", "-b", "dev", str(main)], check=True, capture_output=True)
    git(main, "remote", "add", "origin", str(origin))
    commit(main, "base")
    git(main, "push", "origin", "dev")

    # The fake gh answers `gh pr list` with the PRs the test wrote down.
    prs = tmp_path / "prs.json"
    prs.write_text("[]")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    gh = bin_dir / "gh"
    gh.write_text(f'#!/bin/sh\ncat "{prs}"\n')
    gh.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ['PATH']}")

    def tree(branch, slug):
        path = tmp_path / slug
        git(main, "worktree", "add", "-b", branch, str(path), "dev")
        return path, commit(path, slug)

    def merged(*heads):
        prs.write_text(json.dumps([
            {"number": 10 + i, "headRefName": name, "headRefOid": oid}
            for i, (name, oid) in enumerate(heads)
        ]))

    def hook(command, cwd=main):
        done = subprocess.run(
            ["bash", str(HOOK)],
            input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
            cwd=cwd, text=True, capture_output=True, check=True,
        )
        out = json.loads(done.stdout)
        return out.get("hookSpecificOutput", {}).get("additionalContext", "")

    def branches():
        return set(git(main, "for-each-ref", "refs/heads", "--format=%(refname:short)").split())

    return type("Repo", (), dict(main=main, tree=staticmethod(tree), merged=staticmethod(merged),
                                 hook=staticmethod(hook), branches=staticmethod(branches)))


def test_a_merged_branch_loses_its_worktree_and_itself(repo):
    path, tip = repo.tree("feat/done", "done")
    repo.merged(("feat/done", tip))

    said = repo.hook("gh pr merge 10 --merge", cwd=path)

    assert not path.exists()
    assert "feat/done" not in repo.branches()
    assert "removed" in said and "feat/done" in said


def test_a_worktree_with_unsaved_work_stays(repo):
    path, tip = repo.tree("feat/dirty", "dirty")
    (path / "notes.txt").write_text("not committed")
    repo.merged(("feat/dirty", tip))

    said = repo.hook("cd somewhere && gh pr merge 10 --merge")

    assert path.exists()
    assert "feat/dirty" in repo.branches()
    assert "left" in said and "uncommitted" in said


def test_a_branch_that_moved_on_after_its_pr_stays(repo):
    path, tip = repo.tree("feat/more", "more")
    commit(path, "later")
    repo.merged(("feat/more", tip))

    repo.hook("gh pr merge 10 --merge")

    assert path.exists()
    assert "feat/more" in repo.branches()


def test_dev_and_unmerged_work_are_never_touched(repo):
    path, _ = repo.tree("feat/open", "open")
    repo.merged(("dev", git(repo.main, "rev-parse", "dev")))

    repo.hook("gh pr merge 10 --merge")

    assert path.exists()
    assert {"dev", "feat/open"} <= repo.branches()


def test_a_tree_with_no_branch_is_reported_not_removed(repo):
    loose = repo.main.parent / "loose"
    git(repo.main, "worktree", "add", "--detach", str(loose), "dev")

    said = repo.hook("gh pr merge 10 --merge")

    assert loose.exists()
    assert str(loose) in said


def test_other_commands_do_nothing(repo):
    path, tip = repo.tree("feat/done", "done")
    repo.merged(("feat/done", tip))

    assert repo.hook("gh pr view 10") == ""
    assert path.exists()
