#!/usr/bin/env python3
"""git-audit — what did a jail session leave in a repo that git or an IDE would RUN on the host?

    git_audit.py snapshot <snapshot.json> <repo dir>...
    git_audit.py compare  <snapshot.json> <repo dir>...

Host-side, for tools/stack-jail.sh: a snapshot before the session, a compare after it. The stack
repos are the host's own checkouts mounted read-write, so a session steered by injected content
can leave something that executes outside the jail the next time host git or an IDE touches the
tree — and none of it shows up in `git diff`. `compare` prints one line per thing that appeared
or changed since the snapshot:

  - `.git` itself replaced (another inode, or no longer a directory)
  - a `.git/config` key added or changed, other than a branch's upstream (config is where
    `core.fsmonitor`, `core.sshCommand`, `core.hooksPath`, aliases, filter and diff drivers and
    `ext::` remote URLs live). Config stays writable in the jail on purpose: `push -u`, tracking
    branches and `gh pr checkout` write it all day
  - a hook added or changed (the launcher also mounts `.git/hooks` read-only; this is the net)
  - a rebase or sequencer left in progress (its todo runs `exec` lines at `--continue`)
  - a `commondir` or `config.worktree`, in the gitdir or in a linked worktree's
  - a repository planted inside the working tree (IDEs auto-detect those and run git in them
    with THEIR config)

The idea is the work variant's launch and exit audit (its tools/stack-jail.sh, docs/security.md);
that one trusts a host-side record of gitdirs, this one reports the difference over a session,
because here the trees are older than the audit and full of legitimate worktrees and clones.

Never runs git inside a repo: the only git call is `git config --file <path> --list`, which
parses that one file and executes nothing from it. Stdlib only. Exit 0; 2 on usage or a snapshot
that cannot be read.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

STATE_NAMES = ("rebase-merge", "rebase-apply", "sequencer", "config.worktree", "commondir")
# A branch's upstream: what `push -u`, `switch -c x origin/y` and `gh pr checkout` write.
BENIGN = re.compile(r"^branch\..*\.(remote|merge|pushremote|gh-merge-base|vscode-merge-base|github-pr-owner-number)$")


def sha(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as e:
        return f"unreadable: {e.strerror}"


def read_config(path: Path) -> dict[str, list[str]] | str:
    """The file's keys and values, or (when git cannot parse it) its checksum."""
    if not path.is_file():
        return {}
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "GIT_CONFIG_NOSYSTEM": "1", "HOME": "/nonexistent"}
    try:
        out = subprocess.run(  # noqa: S603  # fixed argv; parses one file, runs nothing from it
            ["git", "config", "--file", str(path), "--null", "--list"],  # noqa: S607
            capture_output=True,
            cwd="/",
            env=env,
            check=True,
        ).stdout.decode(errors="replace")
    except (OSError, subprocess.CalledProcessError):
        return "sha256:" + sha(path)
    conf: dict[str, list[str]] = {}
    for item in out.split("\0"):
        if item:
            key, _, value = item.partition("\n")
            conf.setdefault(key, []).append(value)
    return conf


def gitdir_state(gitdir: Path) -> dict[str, str]:
    """State files in a gitdir (or a linked worktree's): name → checksum, 'dir', or commondir's text."""
    state = {}
    for name in STATE_NAMES:
        p = gitdir / name
        if p.is_dir():
            state[name] = "dir"
        elif name == "commondir" and p.is_file() and not p.is_symlink():
            state[name] = p.read_text(errors="replace").strip()[:200]  # the text: "../.." is what a linked worktree has
        elif p.exists() or p.is_symlink():
            state[name] = sha(p)
    return state


def nested_repos(root: Path) -> list[str]:
    """Every .git entry (dir, file or link) below the top level of a working tree."""
    found = []
    for cur, dirs, files in os.walk(root, onerror=lambda e: found.append(f"unreadable: {e.filename}")):
        here = Path(cur)
        if ".git" in dirs or ".git" in files:
            if here != root:
                found.append(str(here.relative_to(root) / ".git"))
            if ".git" in dirs:
                dirs.remove(".git")  # never descend into a gitdir
    return sorted(found)


def snapshot_repo(repo: Path) -> dict:
    g = repo / ".git"
    if g.is_symlink():
        kind = "symlink"
    elif g.is_dir():
        kind = "dir"
    elif g.exists():
        kind = "file"
    else:
        kind = "none"
    snap: dict = {"kind": kind, "nested": nested_repos(repo) if repo.is_dir() else []}
    if kind != "dir":
        return snap
    snap["inode"] = g.stat().st_ino
    snap["config"] = read_config(g / "config")
    hooks = g / "hooks"
    snap["hooks"] = {p.name: sha(p) for p in sorted(hooks.iterdir()) if not p.name.endswith(".sample")} if hooks.is_dir() else {}
    snap["state"] = {"": gitdir_state(g)}
    worktrees = g / "worktrees"
    if worktrees.is_dir():
        for wt in sorted(worktrees.iterdir()):
            snap["state"][f"worktrees/{wt.name}"] = gitdir_state(wt)
    return snap


def compare_repo(name: str, old: dict, new: dict) -> list[str]:
    q = repr  # the jail picks names and values: an escape sequence must not erase a warning
    hits = []
    if old["kind"] != new["kind"]:
        hits.append(f"{name}/.git was {old['kind']}, is now {new['kind']}")
    elif new["kind"] == "dir" and old.get("inode") != new.get("inode"):
        hits.append(f"{name}/.git was replaced by another directory")
    for path in sorted(set(new["nested"]) - set(old["nested"])):
        hits.append(f"new nested repository: {q(name + '/' + path)}")
    if new["kind"] != "dir" or old["kind"] != "dir":
        return hits
    oc, nc = old["config"], new["config"]
    if isinstance(oc, str) or isinstance(nc, str):
        if oc != nc:
            hits.append(f"{name}/.git/config changed and git cannot parse it — read it before running git there")
    else:
        for key in sorted(nc):
            if nc[key] != oc.get(key) and not BENIGN.match(key):
                hits.append(f"{name}/.git/config: {q(key)} = {q(nc[key][-1])}")
    for hook, digest in sorted(new["hooks"].items()):
        if old["hooks"].get(hook) != digest:
            hits.append(f"hook added or changed: {q(name + '/.git/hooks/' + hook)}")
    for where, state in sorted(new["state"].items()):
        before = old["state"].get(where, {})
        gitdir = f"{name}/.git/{where}".rstrip("/")
        for item, digest in sorted(state.items()):
            if before.get(item) == digest:
                continue
            if item in ("config.worktree", "commondir"):
                if item == "commondir" and where and where not in old["state"] and digest == "../..":
                    continue  # a worktree added this session has exactly this one, by construction
                hits.append(f"{q(gitdir + '/' + item)} appeared or changed (it redirects where git reads config)")
            elif item not in before:
                hits.append(f"in-progress {item} in {q(gitdir)} — read its todo before any --continue")
    return hits


def main(argv: list[str]) -> int:
    if len(argv) < 4 or argv[1] not in ("snapshot", "compare"):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    snap_path, repos = Path(argv[2]), [Path(a) for a in argv[3:]]
    now = {str(r): snapshot_repo(r) for r in repos}
    if argv[1] == "snapshot":
        snap_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = snap_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(now))
        tmp.replace(snap_path)
        return 0
    try:
        before = json.loads(snap_path.read_text())
    except (OSError, ValueError) as e:
        print(f"git-audit: cannot read {snap_path}: {e}", file=sys.stderr)
        return 2
    for r in repos:
        if str(r) in before:
            for hit in compare_repo(r.name, before[str(r)], now[str(r)]):
                print(hit)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
