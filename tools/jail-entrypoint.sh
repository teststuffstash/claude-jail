#!/bin/sh
# Run as PID 1 by tini. Launches the upload server in the background, then
# hands the terminal off to the main command (claude). tini reaps the
# background server and forwards signals to the whole process group on stop.
set -e

# Upload server: always binds container port 8000. The host-side port is
# decided by docker-compose (per-project, see UPLOAD_PORT in .aliases).
# UPLOAD_DIR picks the target folder for dropped files.
python3 /workspace/tools/upload/upload.py \
  --dir "${UPLOAD_DIR:-/workspace}" \
  --port 8000 \
  --host 0.0.0.0 \
  >/tmp/upload-server.log 2>&1 &

# Session card composition (claude-jail#1, homelab FU-117) — MONO jail only; a
# stack jail (STACK_NAME set by tools/stack-jail.sh) composes its own card, with
# the rendered per-stack env card prepended, in tools/stack-jail-init.sh. Both
# targets are static content shared by concurrent sessions (the mono /workspace
# is a host mount), so nothing per-session may be rendered into them here.
# Missing sources degrade loudly (the ground-rules donor pattern): a session
# without its card is a real defect, not a default.
if [ -z "${STACK_NAME:-}" ]; then
  if [ -f /workspace/tools/jail-card.md ]; then
    { echo '<!-- composed at container start by tools/jail-entrypoint.sh from tools/jail-card.md — edit THAT file, not this one -->'
      cat /workspace/tools/jail-card.md
    } > /workspace/CLAUDE.local.md
  else
    echo "jail-entrypoint: tools/jail-card.md missing — this session has NO container ground-rules card" >&2
  fi
  if [ -f /workspace/homelab/agents/jail-seat-card.md ]; then
    { echo '<!-- composed at container start by tools/jail-entrypoint.sh from agents/jail-seat-card.md — edit THAT file, not this one -->'
      cat /workspace/homelab/agents/jail-seat-card.md
    } > /workspace/homelab/CLAUDE.local.md
  elif [ -d /workspace/homelab ]; then
    echo "jail-entrypoint: homelab agents/jail-seat-card.md missing (homelab PR#773 unmerged or checkout stale?) — homelab seat sessions run WITHOUT the seat card" >&2
  fi
fi

# Git credential store (FU-002): keep the GitHub PAT out of remote URLs. The mono
# jail (whole ~/Projects mounted) has a single GH_TOKEN covering all teststuffstash
# repos, so one host-level github.com entry suffices — no useHttpPath needed. The
# store file is container-local (not a mounted path) → ephemeral, rebuilt each start
# from .env. The helper is injected via GIT_CONFIG_* env, NOT `git config --global`:
# /home/node/.gitconfig is a busy bind-mount here, so git config's rename-replace
# would EBUSY. Guarded on GH_TOKEN so oracle's stack jail is a no-op — it carries no
# GH_TOKEN at entrypoint and builds its own per-repo store in stack-jail-init.sh.
if [ -n "${GH_TOKEN:-}" ]; then
  ( umask 077; printf 'https://x-access-token:%s@github.com\n' "$GH_TOKEN" > /home/node/.git-credentials )
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=credential.helper
  export GIT_CONFIG_VALUE_0='store --file /home/node/.git-credentials'
fi

exec "$@"
