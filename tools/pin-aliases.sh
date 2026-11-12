#!/usr/bin/env bash
# pin-aliases — review .aliases and pin a copy for the host shell. Host-side (`jail-pin`).
# Taken from the work variant's tools/pin-aliases.sh (tools/work-variant.sh).
#
# ~/Projects is writable from the mono jail, and a host shell that sources ~/Projects/.aliases
# runs whatever a session left there, at every shell start, unseen. Instead ~/.zshrc sources a
# pinned COPY that lives outside every jail mount and only changes here, after you saw the diff:
#
#   [ -f ~/.config/claude-jail/aliases.pinned ] && source ~/.config/claude-jail/aliases.pinned
#   cmp -s ~/Projects/.aliases ~/.config/claude-jail/aliases.pinned 2>/dev/null \
#     || print -u2 "⚠ jail .aliases differs from the pinned copy — review with: jail-pin"
#
# This covers the file the shell sources. The launchers the aliases call (tools/*.sh,
# docker-compose.yml) are still read from ~/Projects at launch: review those as diffs.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
src="$HERE/.aliases"
pin="${JAIL_PIN_FILE:-$HOME/.config/claude-jail/aliases.pinned}"

if [ -f "$pin" ] && cmp -s "$src" "$pin"; then
  echo "pinned copy is up to date ($pin)"
  exit 0
fi
snap=$(mktemp) && cp "$src" "$snap"                        # what is shown is what gets pinned: a jail can edit $src during the prompt
trap 'rm -f "$snap"' EXIT
if [ -f "$pin" ]; then
  diff -u --label "pinned" --label "repo .aliases" "$pin" "$snap" | cat -v || true   # -v: an escape sequence cannot hide a line from the reviewer
else
  echo "no pinned copy yet — full file:"; cat -v "$snap"
fi
echo
read -r -p "Pin this for every new host shell? [y/N] " answer
case "$answer" in
  y|Y) mkdir -p "$(dirname "$pin")"; install -m 644 "$snap" "$pin"; echo "pinned → $pin (new shells pick it up; current: source it)" ;;
  *)   echo "not pinned"; exit 1 ;;
esac
