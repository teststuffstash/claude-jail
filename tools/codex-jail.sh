#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
usage() {
  cat <<'EOF'
Usage: codex-jail.sh [--project DIR] [--name NAME] [--port PORT] [--mono]
                     [--env-file FILE] [--homelab-wallet]
                     [--build | --login | --shell | -- COMMAND...]
Default: interactive Codex. --login uses ChatGPT device authentication.
--mono mounts the entire jail repository (Projects) at /workspace.
State: .codex-jail/NAME; one project per NAME prevents resume ambiguity.
Examples:
  tools/codex-jail.sh --project ../my-repo --name my-repo --build
  tools/codex-jail.sh --project ../my-repo --name my-repo --login
  tools/codex-jail.sh --project ../my-repo --name my-repo -- codex resume --last
EOF
}
project="$PWD" name=main port=8021 env_file='' mode=run mono=0 wallet=0
command=(codex)
while (($#)); do
  case "$1" in
    --project|--name|--port|--env-file)
      (($# >= 2)) || { usage >&2; exit 2; }
      case "$1" in
        --project) project=$2;; --name) name=$2;; --port) port=$2;;
        --env-file) env_file=$2;;
      esac
      shift 2;;
    --build) mode=build; shift;;
    --mono) mono=1; shift;;
    --homelab-wallet) wallet=1; shift;;
    --login) command=(codex login --device-auth); shift;;
    --shell) command=(zsh); shift;;
    --) shift; (($#)) || { usage >&2; exit 2; }; command=("$@"); break;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2;;
  esac
done
# Docker is the permission boundary for this jail, matching the Claude launchers.
# Apply to explicit Codex commands too, including resume and exec.
if [[ ${command[0]} == codex ]]; then
  command=(codex --dangerously-bypass-approvals-and-sandbox "${command[@]:1}")
fi
[[ $name =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || { echo 'Invalid jail name' >&2; exit 2; }
if ! [[ $port =~ ^[0-9]{1,5}$ ]] || ! ((10#$port > 0 && 10#$port < 65536)); then
  echo 'Invalid upload port' >&2; exit 2
fi
JAIL_PROJECT="$(cd -- "$project" && pwd -P)"
JAIL_WORKDIR="/workspace/$(basename -- "$JAIL_PROJECT")"
export JAIL_PROJECT JAIL_WORKDIR
export JAIL_MOUNT_SOURCE="$JAIL_PROJECT" JAIL_MOUNT_TARGET="$JAIL_WORKDIR"
if [[ $mono == 1 ]]; then
  case "$JAIL_PROJECT" in
    "$ROOT") JAIL_WORKDIR=/workspace;;
    "$ROOT"/*) JAIL_WORKDIR="/workspace/${JAIL_PROJECT#"$ROOT"/}";;
    *) echo '--mono requires a project inside the jail repository (Projects)' >&2; exit 2;;
  esac
  export JAIL_MOUNT_SOURCE="$ROOT" JAIL_MOUNT_TARGET=/workspace
fi
export JAIL_HOMELAB_SEAT=0
[[ $mono == 1 && $JAIL_PROJECT == "$ROOT/homelab" ]] && JAIL_HOMELAB_SEAT=1
export JAIL_STATE="$ROOT/.codex-jail/$name"
export JAIL_NAME="$name"
# The homelab seat has a provisioned LAN OTLP ingress. Keep generic project
# jails disconnected unless their launcher explicitly supplies an endpoint.
export CODEX_OTLP_BASE_ENDPOINT="${CODEX_OTLP_BASE_ENDPOINT:-}"
if [[ $JAIL_HOMELAB_SEAT == 1 && -z $CODEX_OTLP_BASE_ENDPOINT ]]; then
  CODEX_OTLP_BASE_ENDPOINT=http://192.168.40.29:4318
fi
JAIL_UID="$(id -u)" JAIL_GID="$(id -g)"
export JAIL_UID JAIL_GID
if [[ -n $env_file ]]; then
  [[ -f $env_file ]] || { echo 'Runtime env file does not exist' >&2; exit 2; }
  env_file="$(cd -- "$(dirname -- "$env_file")" && pwd -P)/$(basename -- "$env_file")"
fi
umask 077
mkdir -p "$JAIL_STATE"
if [[ -f $JAIL_STATE/project-path && $(<"$JAIL_STATE/project-path") != "$JAIL_PROJECT" ]]; then
  echo 'This jail name belongs to another project; choose a different --name.' >&2
  exit 2
fi
printf '%s\n' "$JAIL_PROJECT" > "$JAIL_STATE/project-path"
# /dev/null suppresses automatic .env loading; runtime credentials are opt-in.
compose=(docker compose --env-file /dev/null -p codex-jail -f "$ROOT/docker-compose.codex.yml")
if [[ $mode == build ]]; then
  exec "${compose[@]}" build codex
fi
opts=(run --rm -p "127.0.0.1:$port:8000")
if [[ $mono == 1 && -f "$ROOT/.claude-data.gitconfig" ]]; then
  opts+=(-v "$ROOT/.claude-data.gitconfig:/home/node/.gitconfig:ro")
fi
if [[ $wallet == 1 ]]; then
  for required in homelab-keepass/homelab.kdbx homelab-keepass/homelab.keyx homelab-pve-ssh/id_ed25519; do
    [[ -s "$ROOT/.claude-data/$required" ]] || {
      echo "Missing credential file: .claude-data/$required; restore the wallet and run homelab/scripts/wallet-files.sh" >&2
      exit 2
    }
  done
  mkdir -p "$JAIL_STATE/service-credentials"
  opts+=(-v "$JAIL_STATE/service-credentials:/home/node/.claude")
  for directory in homelab-keepass homelab-pve-ssh; do
    opts+=(-v "$ROOT/.claude-data/$directory:/home/node/.claude/$directory:ro")
  done
fi
[[ -z $env_file ]] || opts+=(--env-from-file "$env_file")
# Browser sidecar: shared with the Claude jails, started from the Claude compose project.
# A failure only costs this session its browser.
export JAIL_BROWSER_MCP_URL=""
if [[ -x $ROOT/tools/jail-browser.sh ]]; then
  if "$ROOT/tools/jail-browser.sh" up >&2; then
    JAIL_BROWSER_MCP_URL=http://jail-browser:8931/mcp
  else
    echo '⚠ browser sidecar did not come up; this session has no browser tool' >&2
  fi
fi
exec "${compose[@]}" "${opts[@]}" codex "${command[@]}"
