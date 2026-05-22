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

# Generate docker-compose.override.yml with whichever zsh dotfiles
# actually exist on the host. Read-only mounts for configs; RW for history
# and frameworks (so plugin installs/updates persist).
OVERRIDE="$DIR/docker-compose.override.yml"
{
  echo "services:"
  echo "  claude:"
  echo "    environment:"
  echo "      TZ: ${TZ:-Europe/Tallinn}"
  echo "      TERM: xterm-256color"
  echo "      COLORTERM: truecolor"
  echo "    volumes:"
  [ -f "$HOME/.zshrc" ]      && echo "      - $HOME/.zshrc:/home/node/.zshrc:ro"
  [ -d "$HOME/.oh-my-zsh" ]  && echo "      - $HOME/.oh-my-zsh:/home/node/.oh-my-zsh"
  [ -d "$HOME/.config/zsh" ] && echo "      - $HOME/.config/zsh:/home/node/.config/zsh"
  [ -f "$HOME/.p10k.zsh" ]   && echo "      - $HOME/.p10k.zsh:/home/node/.p10k.zsh:ro"
  echo "      - $ZSH_HIST:/home/node/.zsh_history"
} > "$OVERRIDE"

echo ".env + docker-compose.override.yml written (UID=$(id -u), GID=$(id -g))."
