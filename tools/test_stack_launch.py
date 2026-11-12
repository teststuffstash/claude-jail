"""Launcher helpers, offline: the git audit, the per-stack lock, <NAME>_CMD secrets. Stdlib only."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
GIT_ENV = {
    "PATH": os.environ["PATH"],
    "HOME": "/nonexistent",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.invalid",
}


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, env=GIT_ENV)  # noqa: S603, S607


def bash(script: str, **env: str) -> subprocess.CompletedProcess:
    return subprocess.run(  # noqa: S603
        ["bash", "-c", script],  # noqa: S607
        capture_output=True,
        text=True,
        env={"PATH": os.environ["PATH"], "TOOLS": str(TOOLS), **env},
    )


class GitAuditTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="git-audit-test-")
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "commit", "-q", "--allow-empty", "-m", "one")
        git(self.repo, "remote", "add", "origin", "https://example.invalid/x.git")
        self.snap = Path(self.tmp.name) / "state" / "snap.json"
        self.audit("snapshot")

    def audit(self, mode: str) -> list[str]:
        out = subprocess.run(  # noqa: S603
            [sys.executable, str(TOOLS / "git_audit.py"), mode, str(self.snap), str(self.repo)],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        return out.splitlines()

    def test_a_quiet_session_reports_nothing(self):
        (self.repo / "file.txt").write_text("work\n")
        git(self.repo, "add", "file.txt")
        git(self.repo, "commit", "-q", "-m", "two")
        self.assertEqual(self.audit("compare"), [])

    def test_branch_upstreams_and_new_worktrees_are_not_findings(self):
        git(self.repo, "config", "branch.main.remote", "origin")
        git(self.repo, "config", "branch.main.merge", "refs/heads/main")
        git(self.repo, "worktree", "add", "-q", str(Path(self.tmp.name) / "wt"), "-b", "side")
        self.assertEqual(self.audit("compare"), [])

    def test_config_keys_that_run_code_are_reported(self):
        git(self.repo, "config", "core.fsmonitor", "/tmp/x.sh")
        git(self.repo, "config", "core.hooksPath", "/tmp/hooks")
        git(self.repo, "config", "remote.origin.url", "ext::sh -c id")
        hits = "\n".join(self.audit("compare"))
        for key in ("core.fsmonitor", "core.hookspath", "remote.origin.url"):
            self.assertIn(key, hits)

    def test_a_hook_a_nested_repo_and_a_rebase_in_progress_are_reported(self):
        hook = self.repo / ".git" / "hooks" / "pre-commit"
        hook.parent.mkdir(exist_ok=True)
        hook.write_text("#!/bin/sh\n")
        nested = self.repo / "vendor" / "lib"
        nested.mkdir(parents=True)
        git(nested, "init", "-q")
        (self.repo / ".git" / "rebase-merge").mkdir()
        (self.repo / ".git" / "commondir").write_text("/tmp/elsewhere\n")
        hits = "\n".join(self.audit("compare"))
        self.assertIn("hook added or changed", hits)
        self.assertIn("new nested repository: 'repo/vendor/lib/.git'", hits)
        self.assertIn("in-progress rebase-merge", hits)
        self.assertIn("commondir", hits)

    def test_a_replaced_gitdir_is_reported(self):
        (self.repo / ".git").rename(self.repo / ".git-old")
        git(self.repo, "init", "-q")
        self.assertIn("repo/.git was replaced by another directory", self.audit("compare"))

    def test_escape_sequences_in_a_value_are_printed_quoted(self):
        git(self.repo, "config", "alias.x", "!echo \x1b[2K")
        (line,) = self.audit("compare")
        self.assertNotIn("\x1b", line)


class LockTest(unittest.TestCase):
    def test_a_live_holder_keeps_the_lock_and_a_dead_one_loses_it(self):
        with tempfile.TemporaryDirectory(prefix="lock-test-") as d:
            script = """
              . "$TOOLS/stack-lock.sh"
              lock_take "$L" || { echo "first take failed"; exit 1; }
              ( lock_take "$L" >/dev/null ) && { echo "a live lock was taken twice"; exit 1; }
              lock_release "$L"; [ ! -e "$L" ] || { echo "release left the lock"; exit 1; }
              mkdir "$L"; echo "999999 Thu Jan  1 00:00:00 1970" > "$L/owner"      # a holder that is gone
              lock_take "$L" 2>"$L.err" || { echo "stale lock not taken over"; exit 1; }
              grep -q "took over" "$L.err" || { echo "no takeover warning"; exit 1; }
              [ "$(cut -d" " -f1 "$L/owner")" = "$$" ] || { echo "owner not rewritten"; exit 1; }
            """
            r = bash(script, L=f"{d}/lock")
            self.assertEqual((r.returncode, r.stdout), (0, ""), r.stderr)


class SecretCmdTest(unittest.TestCase):
    def run_resolve(self, assignments: str) -> subprocess.CompletedProcess:
        return bash(f'. "$TOOLS/secret-cmd.sh"; {assignments}; resolve_secret_cmds X_PAT X_HOMELAB_TOKEN && echo "[$X_PAT]"')

    def test_a_command_becomes_the_value(self):
        r = self.run_resolve("X_PAT_CMD='printf s3cret'")
        self.assertEqual((r.returncode, r.stdout), (0, "[s3cret]\n"))

    def test_a_plain_value_is_left_alone(self):
        r = self.run_resolve("X_PAT=plain")
        self.assertEqual((r.returncode, r.stdout), (0, "[plain]\n"))

    def test_both_forms_a_failing_command_and_empty_output_are_refused(self):
        for assignments in ("X_PAT=a X_PAT_CMD='echo b'", "X_PAT_CMD='exit 3'", "X_PAT_CMD=true"):
            r = self.run_resolve(assignments)
            self.assertEqual((r.returncode, r.stdout), (2, ""), assignments)
            self.assertNotIn("s3cret", r.stderr)

    def test_a_command_not_named_by_the_caller_is_never_run(self):
        with tempfile.TemporaryDirectory(prefix="secret-test-") as d:
            r = self.run_resolve(f"OTHER_CMD='touch {d}/ran'")
            self.assertEqual(r.returncode, 0)
            self.assertFalse(Path(d, "ran").exists())


if __name__ == "__main__":
    unittest.main()
