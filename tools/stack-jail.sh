#!/usr/bin/env bash
# stack-jail — host-side launcher for a per-stack jail (the credential airlock).
#
#   stack-jail.sh <stack> [--login]
#
# Per-stack jails supersede launching everything through the mono claude-jail.
# Middle-ground permission model (decided 2026-07-12):
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
# ADDING A STACK (since 2026-08-03): REPOS/MOUNTS/KUBE_NS/SA/MAIN_DIR derive from
# homelab's agents/stacks.json (the claims mirror) — the case block below carries ONLY the
# jail-owned overlay: UPLOAD_PORT (host allocation) + private extra mounts (e.g. teststuff:ro),
# which must never appear in the public homelab repo. So: one overlay entry + `.env.<stack>`
# (created on first run) + the PAT mint. The compose service is generic (`stack`); everything
# stack-specific travels via `docker compose run -v/-e`. Definition of done:
# `devbox run stack-lint <stack>` in homelab.
#
# Login is shared with the mono jail (.credentials.json single-file mount — the
# proven login-once pattern; multiple jail sessions already share it live).
# --login: publish the OAuth callback port 54545 for re-auth edge cases only
# (collides with the mono jail's `main` session if that is running).
set -euo pipefail

PROJECTS="${HOME}/Projects"
STACK="${1:-}"; shift || true
LOGIN=0
[ "${1:-}" = "--login" ] && LOGIN=1

# ── Derived half: stacks.json is the authority for what a stack IS ──────────────────────────
STACKS_JSON="$PROJECTS/homelab/agents/stacks.json"
[ -f "$STACKS_JSON" ] || { echo "FATAL: $STACKS_JSON missing (homelab checkout is the stack authority)" >&2; exit 2; }
derived="$(python3 - "$STACK" "$STACKS_JSON" <<'PY'
import json, sys
name, path = sys.argv[1], sys.argv[2]
rows = [s for s in json.load(open(path))["stacks"] if s["name"] == name]
if not rows:
    known = " ".join(s["name"] for s in json.load(open(path))["stacks"])
    sys.exit(f"unknown stack {name!r} (stacks.json knows: {known})")
s = rows[0]
print(" ".join(s["repos"]))
PY
)" || { echo "$derived" >&2; exit 2; }
REPOS="$derived"
MOUNTS="$REPOS"

# ── Jail-owned overlay: port allocation, the PRIMARY (cwd) repo, PRIVATE mounts — the facts
# that are jail ergonomics or must never appear in the public homelab repo ──────────────────
case "$STACK" in
  oracle)
    UPLOAD_PORT=8017
    PRIMARY=oracle-fleet
    MOUNTS="$MOUNTS teststuff:ro"   # the private strategy repo rides along read-only
    ;;
  sleep)     UPLOAD_PORT=8018; PRIMARY=sleep-tracking ;;
  platform)  UPLOAD_PORT=8019; PRIMARY=openrouter-operator ;;
  circles)   UPLOAD_PORT=8020; PRIMARY=circles
    MOUNTS="$MOUNTS life:ro"        # the data repo (renamed from therapy 2026-08-03), read-only — jail only
    ;;
  *)
    echo "stack '$STACK' has no jail overlay yet — add a UPLOAD_PORT/PRIMARY (+ private mounts) case entry" >&2
    exit 2
    ;;
esac
MAIN_DIR="/workspace/$PRIMARY"
KUBE_NS="$PRIMARY"                  # workbench SA namespace (= the stack's primary-repo ns)
KUBE_SA="$STACK-workbench" 

ENV_FILE="$PROJECTS/.env.$STACK"
STATE_DIR="$PROJECTS/.claude-data-$STACK"
CLAUDE_JSON="$PROJECTS/.claude-data-$STACK.json"
PREFIX=$(printf '%s' "$STACK" | tr 'a-z-' 'A-Z_')

# Pre-create bind-mount targets so docker doesn't create them root-owned.
# .claude.json must be VALID JSON — an empty file reads as "corrupted: Unexpected
# EOF" and gets backed up + reset on every launch. Seed {} if missing/empty.
mkdir -p "$STATE_DIR"
[ -s "$CLAUDE_JSON" ] || echo '{}' > "$CLAUDE_JSON"
touch "$PROJECTS/.claude-data-$STACK.zsh_history"
# Cross-jail handoff channel (tools/handoff.md): only THIS stack's subtree is
# mounted, so a stack jail never sees another stack's traffic.
mkdir -p "$PROJECTS/.handoff/$STACK"/{inbox,doing,done}

# Bootstrap the stack jail's Claude config from the mono jail's solved state —
# otherwise every new stack jail re-runs onboarding (theme/trust prompts) and
# loses the bypass-permissions setup. Two pieces, both idempotent:
#  1. settings.json (permissions allow-list, skipDangerousModePermissionPrompt,
#     model, theme, statusline): copied ONCE if absent, so per-stack overrides
#     stick. The statusline script is copied alongside and the command repointed
#     (the mono path /workspace/.claude/statusline.sh doesn't exist in a stack
#     jail — only the stack dirs are mounted).
#  2. .claude.json: additive merge — set onboarding-done + trust flags for the
#     stack's dirs only where missing; never overwrites state the jail wrote.
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
TRUST_DIRS="/workspace/homelab"
for m in $MOUNTS; do TRUST_DIRS="$TRUST_DIRS /workspace/${m%%:*}"; done
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
  cat > "$ENV_FILE" <<EOF
# $STACK stack-jail credentials (gitignored; sourced by tools/stack-jail.sh).
# ${PREFIX}_PAT — fine-grained PAT, YOUR identity. Resource owner: teststuffstash.
#   Repository access: ONLY $REPOS.
#   Permissions: Contents R/W, Pull requests R/W, Issues R/W, Workflows R/W,
#   Actions R/W, Commit statuses R. (Workflows is required to push under
#   .github/workflows/; Actions for \`gh run watch\`/rerun. Known limit:
#   fine-grained PATs have NO Checks permission — that API is Apps-only — so
#   \`gh pr checks\` 403s; use \`gh run watch\` + PR mergeStateStatus instead.)
${PREFIX}_PAT=
# ${PREFIX}_HOMELAB_TOKEN — optional; enables pushing agent/* branches + PRs to
# homelab from inside the jail. Use a token that is branch+PR-only BY IDENTITY
# (minted from the homelab-agents App), NOT a PAT with your identity — your
# pushes bypass the rulesets everywhere. Read access is not needed (homelab is
# public; the clone is tokenless).
${PREFIX}_HOMELAB_TOKEN=
EOF
  chmod 600 "$ENV_FILE"
  echo "→ created $ENV_FILE — fill in the tokens, then re-run. Continuing without git credentials." >&2
fi

# Normalize the per-stack env names to the generic STACK_* contract that
# tools/stack-jail-init.sh consumes inside the jail.
set -a; . "$ENV_FILE"; set +a
pat_var="${PREFIX}_PAT"; hl_var="${PREFIX}_HOMELAB_TOKEN"
export STACK_NAME="$STACK"
export STACK_PAT="${!pat_var:-}"
export STACK_HOMELAB_TOKEN="${!hl_var:-}"
export STACK_REPOS="$REPOS"
export STACK_KUBE_NS="$KUBE_NS"
export UPLOAD_DIR="$MAIN_DIR/uploads"

# Kube token airlock: mint a short-lived SA token with the HOST-side homelab
# devbox — the SAME mechanism as `devbox run k9s` (devbox.json sets
# KUBECONFIG=$PWD/tofu/kubeconfig; regenerate it with `devbox run kubeconfig`).
# Degrades gracefully (warns + continues), but SHOWS the real kubectl error —
# "SA not found" (not deployed/synced yet) reads very differently from
# "connection refused" (cluster/kubeconfig problem).
STACK_KUBE_TOKEN="" STACK_KUBE_SERVER="" STACK_KUBE_CA=""
HOMELAB="$PROJECTS/homelab"
if [ -d "$HOMELAB" ]; then
  # `devbox run` writes its own chatter to STDOUT, so a bare $(devbox run -- ...) capture can
  # swallow it into the value. It bit us on 2026-08-05: devbox's python plugin printed "Directory
  # exists but is not a valid virtual environment. Creating a new one..." (the venv is shared
  # between the host and the jails, and its bin/python symlink is an ABSOLUTE path into whichever
  # project root created it — fixed in homelab devbox.json by moving VENV_DIR under $HOME), the
  # line landed in front of the JWT, and the whitespace strip below then WELDED it into one
  # token-shaped string. -q silences devbox; `tail -1` keeps only the payload line whatever else
  # a future plugin decides to print.
  kdev() { (cd "$HOMELAB" && devbox run -q -- kubectl "$@" | tail -1); }
  # 72h: sessions are sometimes left open for days; still a bounded derivative.
  kube_err=$(mktemp)
  if STACK_KUBE_TOKEN=$(kdev -n "$KUBE_NS" create token "$KUBE_SA" --duration=72h 2>"$kube_err"); then
    # tr: the captured output has arrived line-wrapped in practice (2026-07-13 oracle
    # jail: token split across two lines → invalid kubeconfig YAML). Tokens/CA are
    # single opaque strings — strip ALL whitespace, whatever injected it.
    STACK_KUBE_TOKEN=$(printf '%s' "$STACK_KUBE_TOKEN" | tr -d '[:space:]')
    STACK_KUBE_SERVER=$(kdev config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}' | tr -d '[:space:]')
    STACK_KUBE_CA=$(kdev config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | tr -d '[:space:]')
    # SHAPE GATE, not a formality: a contaminated token still LOOKS like a string and produces a
    # kubeconfig that fails later with a bare 401 — which reads as "expired", sending you after
    # the wrong thing (2026-08-05). A k8s SA token is a JWT: three dot-separated base64url parts.
    if ! printf '%s' "$STACK_KUBE_TOKEN" | grep -qE '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$'; then
      echo "⚠ minted token is NOT a JWT — something wrote to stdout during the mint." >&2
      echo "    got: $(printf '%s' "$STACK_KUBE_TOKEN" | cut -c1-60)..." >&2
      echo "    continuing WITHOUT kubectl rather than shipping a kubeconfig that 401s." >&2
      STACK_KUBE_TOKEN=""
    else
      echo "→ minted 72h kube token for $KUBE_SA@$KUBE_NS"
    fi
  else
    STACK_KUBE_TOKEN=""
    echo "⚠ could not mint kube token for $KUBE_SA@$KUBE_NS; continuing without kubectl. kubectl said:" >&2
    sed 's/^/    /' "$kube_err" >&2
  fi
  rm -f "$kube_err"
else
  echo "⚠ $HOMELAB not found; continuing without kubectl" >&2
fi
export STACK_KUBE_TOKEN STACK_KUBE_SERVER STACK_KUBE_CA

# Shared-login mount source must EXIST as a file, or docker creates a root-owned
# directory at the target and login breaks in every jail.
if [ ! -f "$PROJECTS/.claude-data/.credentials.json" ]; then
  echo "⚠ $PROJECTS/.claude-data/.credentials.json missing — log in via the mono jail (main) first" >&2
  exit 1
fi

VOLS=(
  -v "$STATE_DIR:/home/node/.claude"
  -v "$CLAUDE_JSON:/home/node/.claude.json"
  -v "$PROJECTS/.claude-data-$STACK.zsh_history:/home/node/.zsh_history"
  -v "$PROJECTS/.handoff/$STACK:/workspace/.handoff"
)
for m in $MOUNTS; do
  dir="${m%%:*}"; suffix=""
  [ "$m" != "$dir" ] && suffix=":${m#*:}"
  VOLS+=(-v "$PROJECTS/$dir:/workspace/$dir$suffix")
done

PORTS=(-p "$UPLOAD_PORT:8000")
[ "$LOGIN" = 1 ] && PORTS+=(-p 54545:54545)

exec docker compose -f "$PROJECTS/docker-compose.yml" run --rm \
  "${PORTS[@]}" "${VOLS[@]}" \
  -e UPLOAD_DIR -e STACK_NAME -e STACK_PAT -e STACK_HOMELAB_TOKEN -e STACK_REPOS \
  -e STACK_KUBE_TOKEN -e STACK_KUBE_SERVER -e STACK_KUBE_CA -e STACK_KUBE_NS \
  stack \
  zsh -c "source /workspace/tools/stack-jail-init.sh && cd $MAIN_DIR && exec claude --dangerously-skip-permissions"
