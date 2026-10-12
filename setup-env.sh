#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

set_env() {
  local key="$1" value="$2" file="$DIR/.env"
  touch "$file"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    echo "${key}=${value}" >> "$file"
  fi
}

set_env HOST_UID "$(id -u)"
set_env HOST_GID "$(id -g)"

# Bind-mounted files must exist on the host before `docker compose run`,
# otherwise docker creates an empty directory in their place.
CONFIG_FILE="$HOME/Projects/.claude-data.json"
[ -f "$CONFIG_FILE" ] || echo '{}' > "$CONFIG_FILE"
ZSH_HIST="$HOME/Projects/.claude-data.zsh_history"
[ -f "$ZSH_HIST" ] || touch "$ZSH_HIST"

# Jail-only git identity, mounted to /home/node/.gitconfig. Kept separate from
# the host ~/.gitconfig so jail commits can use a different author if desired.
GITCONFIG="$HOME/Projects/.claude-data.gitconfig"
[ -f "$GITCONFIG" ] || cat > "$GITCONFIG" <<'GITCFG'
# Jail git identity — uncomment and fill in for commits made inside the jail.
# This file is separate from your host ~/.gitconfig.
# [user]
# 	name = Your Name
# 	email = you@example.com
GITCFG

# The browser sidecar's docker network (docker-compose.yml `browser`, tools/jail-browser.sh).
# EXTERNAL to every compose project so the Claude project and a separately named Codex
# project can both join it — which means something outside compose has to create it: here,
# once per host (jail-browser.sh up does the same check before each launch it drives).
docker network inspect jail-browser >/dev/null 2>&1 || docker network create jail-browser >/dev/null

echo ".env written (UID=$(id -u), GID=$(id -g))."
