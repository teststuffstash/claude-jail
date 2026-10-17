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
  # Direct-master lint tripwire (operator direction 2026-08-30, homelab seat-card §How
  # changes land): the jail's OrgAdmin master pushes bypass CI, so homelab's committed
  # githooks/pre-push is the lane's only lint gate — wire it on every container start so a
  # rebuilt container (fresh .git/config never happens — .git rides the host bind-mount —
  # but a fresh CLONE would) cannot silently lose the hook.
  if [ -d /workspace/homelab/githooks ]; then
    git -C /workspace/homelab config core.hooksPath githooks || true
  fi

  # Forgejo git identity — MONO jail only, and only when homelab's wallet-files.sh has
  # materialized the key cache into this jail's ~/.claude (homelab CLAUDE.md §Secrets). That
  # key reaches every personal Forgejo repo, so stack jails never get it (their ~/.claude
  # has no cache by design); a stack needing one repo gets a per-repo deploy key instead.
  # Before this, each checkout carried its own hand-set core.sshCommand (or none) and no
  # jail had the GPG key imported, so pushes and signing broke per clone.
  #   ssh: one Host block, the cached key, the host key pinned in tools/forgejo_known_hosts.
  #   gpg: the cached key imported into the container-local keyring; commits/tags to a
  #        Forgejo remote are signed (includeIf hasconfig — GitHub repos are untouched).
  # ~/.gitconfig is a busy bind-mount (EBUSY on rewrite, see the credential block below), so
  # the include lives in a container-local GIT_CONFIG_GLOBAL that includes the mounted file.
  FJ=/home/node/.claude/homelab-forgejo
  if [ -f "$FJ/id_ed25519" ]; then
    mkdir -p /home/node/.ssh && chmod 700 /home/node/.ssh
    ( umask 077; cat > /home/node/.ssh/config <<EOF
Host forgejo.teststuff.net
  User git
  IdentityFile $FJ/id_ed25519
  IdentitiesOnly yes
  UserKnownHostsFile /workspace/tools/forgejo_known_hosts
  StrictHostKeyChecking yes
EOF
    )
  fi
  if [ -f "$FJ/gpg-private.asc" ] && gpg --batch --quiet --import "$FJ/gpg-private.asc" 2>/dev/null; then
    FJ_KEY=$(gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '$1 == "sec" { print $5; exit }')
    printf '[user]\n\tsigningkey = %s\n[commit]\n\tgpgsign = true\n[tag]\n\tgpgsign = true\n' "$FJ_KEY" \
      > /home/node/.gitconfig-forgejo-signing
    { printf '[include]\n\tpath = /home/node/.gitconfig\n'
      for url in 'ssh://git@forgejo.teststuff.net/**' 'git@forgejo.teststuff.net:*/**' 'https://forgejo.teststuff.net/**'; do
        printf '[includeIf "hasconfig:remote.*.url:%s"]\n\tpath = /home/node/.gitconfig-forgejo-signing\n' "$url"
      done
    } > /home/node/.gitconfig-jail
    export GIT_CONFIG_GLOBAL=/home/node/.gitconfig-jail
  elif [ -f "$FJ/gpg-private.asc" ]; then
    echo "jail-entrypoint: Forgejo GPG key import failed — Forgejo commits will be UNSIGNED" >&2
  fi
fi

# Browser MCP server (claude-jail#5): the compose service `browser` (a headless Chromium +
# Playwright MCP sidecar shared by every jail on the host) is handed in as a URL and
# registered as the user-scope `browser` server in ~/.claude.json — the bind-mounted file
# (mono: .claude-data.json, stack: .claude-data-<stack>.json), so the registration
# persists and the next start is a no-op. Idempotent, never clobbers an unparsable file,
# leaves a user-edited entry alone (tools/mcp-register.py). Both jail classes run THIS
# entrypoint, so one hook covers them. Empty/unset URL = no browser, no registration.
if [ -n "${JAIL_BROWSER_MCP_URL:-}" ]; then
  python3 /workspace/tools/mcp-register.py claude /home/node/.claude.json browser "$JAIL_BROWSER_MCP_URL" \
    || echo "jail-entrypoint: browser MCP registration failed — this session has NO browser tool" >&2
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
