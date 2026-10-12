#!/usr/bin/env bash
# Sync native Codex session JSONL to the private jail-transcripts Garage bucket.
#
# Object layout:
#   s3://jail-transcripts/codex/<jail-name>/sessions/YYYY/MM/DD/rollout-*.jsonl
#
# Best-effort by design: the jail must remain usable when the cluster or Garage is
# unavailable. Every skip/failure is loud, but this script always exits zero so a
# later heartbeat or wind-down can retry it.
set -uo pipefail

say() { printf 'CODEX-TRANSCRIPTS-SYNC %s\n' "$*"; }
skip() { say "SKIPPED: $*"; exit 0; }

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SRC="${CODEX_TRANSCRIPTS_SRC:-$CODEX_HOME/sessions}"
JAIL_NAME="${JAIL_NAME:-main}"
BUCKET="${CODEX_TRANSCRIPTS_BUCKET:-jail-transcripts}"
ENDPOINT="${GARAGE_S3_ENDPOINT:-https://s3.teststuff.net}"
PREFIX="${CODEX_TRANSCRIPTS_PREFIX:-codex/$JAIL_NAME/sessions}"
HOMELAB_ROOT="${HOMELAB_ROOT:-/workspace/homelab}"

[[ $JAIL_NAME =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || skip "invalid jail name"
[ -d "$SRC" ] || skip "no native Codex session directory at $SRC"

KUBECTL="${KUBECTL:-$(command -v kubectl || true)}"
AWS="${AWS:-$(command -v aws || true)}"
[ -n "$KUBECTL" ] || KUBECTL="$HOMELAB_ROOT/.devbox/nix/profile/default/bin/kubectl"
[ -n "$AWS" ] || AWS="$HOMELAB_ROOT/.devbox/nix/profile/default/bin/aws"
[ -x "$AWS" ] || skip "no aws cli"

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  [ -x "$KUBECTL" ] || skip "no kubectl"
  KCFG="${KUBECONFIG:-$HOMELAB_ROOT/tofu/kubeconfig}"
  [ -f "$KCFG" ] || skip "no kubeconfig at $KCFG"
  sec="$($KUBECTL --kubeconfig "$KCFG" -n agent-coordinator \
    get secret jail-transcripts-s3 -o json 2>/dev/null)" || sec=""
  [ -n "$sec" ] || skip "connection Secret jail-transcripts-s3 unreadable"
  AWS_ACCESS_KEY_ID="$(printf '%s' "$sec" | jq -r '.data.rw_access_key_id // empty | @base64d')"
  AWS_SECRET_ACCESS_KEY="$(printf '%s' "$sec" | jq -r '.data.rw_secret_access_key // empty | @base64d')"
  [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ] || \
    skip "connection Secret missing rw key fields"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
fi

curl -s -o /dev/null --max-time 5 "$ENDPOINT" || skip "endpoint $ENDPOINT unreachable"
export AWS_REGION=garage AWS_DEFAULT_REGION=garage
CFG="$(mktemp)"
trap 'rm -f "$CFG"' EXIT
printf '[default]\ns3 =\n    addressing_style = path\n' > "$CFG"
export AWS_CONFIG_FILE="$CFG"

if out="$($AWS --endpoint-url "$ENDPOINT" s3 sync "$SRC" "s3://$BUCKET/$PREFIX" \
    --exclude '*' --include '*.jsonl' --no-progress 2>&1)"; then
  uploaded="$(printf '%s' "$out" | grep -c '^upload:' || true)"
  say "done — $uploaded file(s) uploaded to s3://$BUCKET/$PREFIX"
else
  say "FAILED: $(printf '%s' "$out" | tail -1)"
fi
exit 0
