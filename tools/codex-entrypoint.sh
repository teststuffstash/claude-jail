#!/bin/sh
# tini forwards stop signals to the runtime and upload server together.
set -eu
umask 077
: "${CODEX_HOME:=/home/node/.codex}"
export CODEX_HOME
if [ -n "${STACK_NAME:-}" ]; then
  # Shared credential airlock: per-repo PAT routing, bounded kube token, public clone.
  . /workspace/tools/stack-jail-init.sh
  cd "${STACK_MAIN_DIR:?Stack working directory missing}"
fi
mkdir -p "$CODEX_HOME"
# Never overwrite user config or copy desktop auth. Directory mounting permits
# Codex to atomically replace its own auth/session files.
if [ ! -e "$CODEX_HOME/config.toml" ]; then
  cat > "$CODEX_HOME/config.toml" <<'EOF'
forced_login_method = "chatgpt"
cli_auth_credentials_store = "file"
EOF
fi
# Expose homelab's shared skills only inside this container. The repository's
# .agents directory belongs to cluster workers and is left untouched.
if [ -z "${STACK_NAME:-}" ] && [ -d /workspace/homelab/.claude/skills ]; then
  mkdir -p "$HOME/.agents"
  if [ ! -e "$HOME/.agents/skills" ] && [ ! -L "$HOME/.agents/skills" ]; then
    ln -s /workspace/homelab/.claude/skills "$HOME/.agents/skills"
  elif [ "$(readlink "$HOME/.agents/skills" || true)" != /workspace/homelab/.claude/skills ]; then
    echo 'codex-entrypoint: existing ~/.agents/skills preserved; homelab skills not linked' >&2
  fi
fi
python3 /opt/jail/codex-context.py
python3 /opt/jail/upload.py --dir "${UPLOAD_DIR:-/workspace/project/uploads}" \
  --port 8000 --host 0.0.0.0 >/tmp/upload-server.log 2>&1 &
if [ "${JAIL_HOMELAB_SEAT:-0}" = 1 ] && [ -x /opt/jail/codex-transcripts-sync.sh ]; then
  # Capture anything a prior hard stop missed, then retry once more at normal
  # wind-down. tini uses process-group forwarding, so the foreground runtime and
  # this wrapper both receive termination signals; EXIT retains best-effort sync.
  /opt/jail/codex-transcripts-sync.sh
  trap '/opt/jail/codex-transcripts-sync.sh' EXIT
  sync_on_exit=1
fi
if [ -z "${STACK_NAME:-}" ] && [ -n "${GH_TOKEN:-}" ]; then
  printf 'https://x-access-token:%s@github.com\n' "$GH_TOKEN" > "$HOME/.git-credentials"
  # Append instead of overwriting any injected git configuration.
  count=${GIT_CONFIG_COUNT:-0}
  export "GIT_CONFIG_KEY_${count}=credential.helper"
  export "GIT_CONFIG_VALUE_${count}=store --file $HOME/.git-credentials"
  export GIT_CONFIG_COUNT=$((count + 1))
fi
if [ "${1:-}" = codex ] && [ -n "${CODEX_OTLP_BASE_ENDPOINT:-}" ]; then
  shift
  set -- codex \
    -c "otel.environment=\"${JAIL_NAME:-jail}\"" \
    -c "otel.exporter={ otlp-http = { endpoint = \"$CODEX_OTLP_BASE_ENDPOINT/v1/logs\", protocol = \"binary\" } }" \
    -c "otel.metrics_exporter={ otlp-http = { endpoint = \"$CODEX_OTLP_BASE_ENDPOINT/v1/metrics\", protocol = \"binary\" } }" \
    -c 'otel.log_user_prompt=false' \
    "$@"
fi
# Stay the parent only when the wind-down sync needs to run after the runtime;
# otherwise hand PID/exit status straight to it as before.
if [ "${sync_on_exit:-0}" = 1 ]; then
  "$@"
else
  exec "$@"
fi
