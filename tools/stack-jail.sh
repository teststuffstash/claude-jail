#!/usr/bin/env bash
# stack-jail — host-side launcher for a per-stack jail (the credential airlock).
#
#   stack-jail.sh <stack> [--login]
#
# The first per-stack jail (oracle) supersedes launching everything through the mono
# claude-jail. Middle-ground permission model (decided 2026-07-12):
#   - git: a per-stack fine-grained PAT with the OWNER's identity (resource owner
#     teststuffstash, ONLY the stack's repos, Contents+PRs+Issues+Workflows R/W) →
#     direct push to master works (owner bypasses rulesets). Plus an optional
#     homelab token that is branch+PR-only BY IDENTITY (minted from the agents App —
#     a single user PAT cannot be PR-only anywhere, the owner bypasses everything).
#   - filesystem: only the stack dirs are mounted; homelab is shallow-cloned inside
#     the jail (the host checkout holds gitignored secrets: tofu state, kubeconfigs).
#   - kubectl: a namespace-admin ServiceAccount; THIS script mints its short-lived
#     token with YOUR host kubeconfig and injects it — the privileged credential
#     never enters the jail, only the bounded (72h) derivative does.
# HARD RULE either way: no credential in any jail may reach beyond the teststuffstash
# org (fine-grained PAT with that resource owner, or an App installation token).
#
# --login: also publish the OAuth callback port 54545 so `/login` works (first run
# only; collides with the mono jail's `main` session if that is running). The token
# persists in .claude-data-<stack>/ afterwards.
set -euo pipefail

PROJECTS="${HOME}/Projects"
STACK="${1:-}"; shift || true
LOGIN=0
[ "${1:-}" = "--login" ] && LOGIN=1

case "$STACK" in
  oracle)
    SERVICE=oracle
    MAIN_DIR=/workspace/oracle-fleet
    UPLOAD_PORT=8017
    KUBE_NS=oracle-fleet
    KUBE_SA=oracle-workbench
    TRUST_DIRS="/workspace/oracle-fleet /workspace/oracle-iac /workspace/homelab /workspace/teststuff"
    ;;
  *)
    echo "usage: stack-jail.sh <stack> [--login]   (known stacks: oracle)" >&2
    exit 2
    ;;
esac

ENV_FILE="$PROJECTS/.env.$STACK"
STATE_DIR="$PROJECTS/.claude-data-$STACK"

# Pre-create bind-mount targets so docker doesn't create them root-owned.
# .claude.json must be VALID JSON — an empty file reads as "corrupted: Unexpected
# EOF" and gets backed up + reset on every launch. Seed {} if missing/empty.
mkdir -p "$STATE_DIR"
CLAUDE_JSON="$PROJECTS/.claude-data-$STACK.json"
[ -s "$CLAUDE_JSON" ] || echo '{}' > "$CLAUDE_JSON"
touch "$PROJECTS/.claude-data-$STACK.zsh_history"

# Bootstrap the stack jail's Claude config from the mono jail's solved state —
# otherwise every new stack jail re-runs onboarding (theme/trust prompts) and
# loses the bypass-permissions setup. Two pieces, both idempotent:
#  1. settings.json (permissions allow-list, skipDangerousModePermissionPrompt,
#     model, theme, statusline): copied ONCE if absent, so per-stack overrides
#     stick. The statusline script is copied alongside and the command repointed
#     (the mono path /workspace/.claude/statusline.sh doesn't exist in a stack
#     jail — only the stack dirs are mounted).
#  2. .claude.json: additive merge — set onboarding-done + trust flags for the
#     stack dirs only where missing; never overwrites state the jail wrote.
if [ ! -f "$STATE_DIR/settings.json" ] && [ -f "$PROJECTS/.claude-data/settings.json" ]; then
  python3 - "$PROJECTS/.claude-data/settings.json" "$STATE_DIR/settings.json" <<'PYEOF'
import json, sys
s = json.load(open(sys.argv[1]))
if "statusLine" in s:
    s["statusLine"]["command"] = "/home/node/.claude/statusline.sh"
json.dump(s, open(sys.argv[2], "w"), indent=2)
PYEOF
  if [ -f "$PROJECTS/.claude/statusline.sh" ]; then
    cp "$PROJECTS/.claude/statusline.sh" "$STATE_DIR/statusline.sh"
    chmod +x "$STATE_DIR/statusline.sh"
  fi
  echo "→ bootstrapped $STATE_DIR/settings.json from the mono jail"
fi
python3 - "$CLAUDE_JSON" "$PROJECTS/.claude-data.json" $TRUST_DIRS <<'PYEOF'
import json, os, sys
target, mono_path, dirs = sys.argv[1], sys.argv[2], sys.argv[3:]
d = json.load(open(target))
mono = json.load(open(mono_path)) if os.path.exists(mono_path) else {}
for k in ("hasCompletedOnboarding", "lastOnboardingVersion", "theme"):
    if k not in d and k in mono and mono[k] is not None:
        d[k] = mono[k]
projects = d.setdefault("projects", {})
for p in dirs:
    entry = projects.setdefault(p, {})
    entry.setdefault("hasTrustDialogAccepted", True)
    entry.setdefault("hasCompletedProjectOnboarding", True)
json.dump(d, open(target, "w"), indent=2)
PYEOF

if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<'EOF'
# oracle stack-jail credentials (gitignored; read by docker compose env_file).
# ORACLE_PAT — fine-grained PAT, YOUR identity. Resource owner: teststuffstash.
#   Repository access: ONLY oracle-fleet + oracle-iac.
#   Permissions: Contents R/W, Pull requests R/W, Issues R/W, Workflows R/W.
#   (Workflows is required to push changes under .github/workflows/.)
ORACLE_PAT=
# ORACLE_HOMELAB_TOKEN — optional; enables pushing agent/* branches + PRs to homelab
# from inside the jail. Use a token that is branch+PR-only BY IDENTITY (minted from
# the homelab-agents App: homelab/scripts/gh-app-runner-token.sh sibling flow), NOT
# a PAT with your identity — your pushes bypass the rulesets everywhere.
# Read access is not needed (homelab is public; the clone is tokenless).
ORACLE_HOMELAB_TOKEN=
EOF
  chmod 600 "$ENV_FILE"
  echo "→ created $ENV_FILE — fill in the tokens, then re-run. Continuing without git credentials." >&2
fi

# Kube token airlock: mint a short-lived SA token with the HOST-side homelab
# devbox — the SAME mechanism as `devbox run k9s` (devbox.json sets
# KUBECONFIG=$PWD/tofu/kubeconfig; regenerate it with `devbox run kubeconfig`).
# Degrades gracefully (warns + continues), but SHOWS the real kubectl error —
# "SA not found" (not deployed/synced yet) reads very differently from
# "connection refused" (cluster/kubeconfig problem).
ORACLE_KUBE_TOKEN="" ORACLE_KUBE_SERVER="" ORACLE_KUBE_CA=""
HOMELAB="$PROJECTS/homelab"
if [ -d "$HOMELAB" ]; then
  kdev() { (cd "$HOMELAB" && devbox run -- kubectl "$@"); }
  # 72h: sessions are sometimes left open for days; still a bounded derivative.
  kube_err=$(mktemp)
  if ORACLE_KUBE_TOKEN=$(kdev -n "$KUBE_NS" create token "$KUBE_SA" --duration=72h 2>"$kube_err"); then
    ORACLE_KUBE_SERVER=$(kdev config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
    ORACLE_KUBE_CA=$(kdev config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
    echo "→ minted 72h kube token for $KUBE_SA@$KUBE_NS"
  else
    ORACLE_KUBE_TOKEN=""
    echo "⚠ could not mint kube token for $KUBE_SA@$KUBE_NS; continuing without kubectl. kubectl said:" >&2
    sed 's/^/    /' "$kube_err" >&2
  fi
  rm -f "$kube_err"
else
  echo "⚠ $HOMELAB not found; continuing without kubectl" >&2
fi
export ORACLE_KUBE_TOKEN ORACLE_KUBE_SERVER ORACLE_KUBE_CA

PORTS=(-p "$UPLOAD_PORT:8000")
[ "$LOGIN" = 1 ] && PORTS+=(-p 54545:54545)

exec docker compose -f "$PROJECTS/docker-compose.yml" run --rm \
  "${PORTS[@]}" \
  -e ORACLE_KUBE_TOKEN -e ORACLE_KUBE_SERVER -e ORACLE_KUBE_CA \
  "$SERVICE" \
  zsh -c "source /workspace/tools/stack-jail-init.sh && cd $MAIN_DIR && exec claude"
