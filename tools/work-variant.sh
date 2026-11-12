#!/usr/bin/env bash
# What has the work variant done since we last looked? Pull-only: the clone at
# ~/Projects/claude-jail-work is a read-only reference — we take what we like into this repo by
# hand and never write there (and the work side treats this repo the same way).
#   tools/work-variant.sh            log + changed files since the reviewed commit
#   tools/work-variant.sh <path>…    the diff of those paths since the reviewed commit
#   tools/work-variant.sh --mark     record the clone's HEAD as reviewed (commit the .rev file)
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLONE="${WORK_VARIANT_DIR:-$DIR/claude-jail-work}"
REV_FILE="$DIR/tools/work-variant.rev"
[ -d "$CLONE/.git" ] || { echo "no clone at $CLONE — git clone https://github.com/RasmusSoot/claude-jail-work" >&2; exit 2; }
git -C "$CLONE" pull --ff-only --quiet || echo "warning: could not update $CLONE; showing what is there" >&2
head=$(git -C "$CLONE" rev-parse HEAD)
if [ "${1:-}" = --mark ]; then
  echo "$head" > "$REV_FILE"; echo "reviewed up to $(git -C "$CLONE" log -1 --format='%h %ad %s' --date=short)"; exit 0
fi
rev=$(cat "$REV_FILE")
if [ "$rev" = "$head" ]; then echo "nothing new since $(git -C "$CLONE" log -1 --format='%h %ad' --date=short)"; exit 0; fi
if [ $# -gt 0 ]; then git -C "$CLONE" diff "$rev..$head" -- "$@"; exit 0; fi
git -C "$CLONE" log --reverse --format='%h %ad %s' --date=short "$rev..$head"
echo; git -C "$CLONE" diff --stat "$rev..$head"
