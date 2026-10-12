#!/usr/bin/env bash
# ci — lint and offline tests for this repo: `devbox run lint|fix|test|ci` (devbox.json pins the tools).
#
# The repo root doubles as the host's ~/Projects, so sibling project clones sit inside it
# (gitignored). Every check therefore runs over `git ls-files` or git history — never a
# directory walk, which would lint and secret-scan every other project on the host.
set -euo pipefail
cd "$(dirname "$0")/.."

lint() {
  local sh_files py_files
  # tools/stack-jail-init.sh has no shebang (it is sourced under zsh, see its header):
  # bash is the closest dialect shellcheck knows; zsh word-splitting still needs a human eye.
  mapfile -t sh_files < <(git ls-files '*.sh')
  mapfile -t py_files < <(git ls-files '*.py')
  shellcheck -x -s bash "${sh_files[@]}"
  hadolint Dockerfile
  # Public repo: no credential may ever land in it. History, then uncommitted tracked changes.
  gitleaks git --no-banner --redact .
  gitleaks git --pre-commit --no-banner --redact .
  ruff check "${py_files[@]}"
  ruff format --check "${py_files[@]}"
}

fix() {  # the mechanical part of lint: import order + formatting
  local py_files
  mapfile -t py_files < <(git ls-files '*.py')
  ruff check --fix-only "${py_files[@]}"
  ruff format "${py_files[@]}"
}

tests() {
  local t
  # The *_container tests need a built image and a docker socket; run those by hand (README).
  for t in $(git ls-files 'tools/test_*.py' | grep -v '_container\.py$'); do
    echo "→ $t"
    python3 "$t"
  done
}

case "${1:-}" in
  lint) lint ;;
  fix) fix ;;
  test) tests ;;
  *) echo "usage: $0 lint|fix|test" >&2; exit 2 ;;
esac
