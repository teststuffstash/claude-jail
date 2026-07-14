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
