# stack-jail-init — sourced (zsh/sh) inside a per-stack jail before exec'ing claude.
# Companion to tools/stack-jail.sh (host side), which injects the generic STACK_* env
# this consumes (normalized from .env.<stack> + the case block + the kube airlock):
#   STACK_NAME           stack name (kubeconfig context, messages)
#   STACK_PAT            stack fine-grained PAT (owner identity, stack repos only)
#   STACK_REPOS          space-separated repos the PAT covers (credential routing)
#   STACK_HOMELAB_TOKEN  optional branch+PR-only token for homelab pushes
#   STACK_KUBE_*         short-lived SA token + server + CA + ns (the airlock derivative)
# Everything here is per-session container state (credential store, kubeconfig,
# homelab clone, session card) — the container is ephemeral, nothing persists but ~/.claude.
# Sourced, not executed: exports GH_TOKEN into the claude process. Always returns 0.

_sj_warn() { echo "stack-jail-init: $*" >&2; }

# ── git identity + per-repo credential routing ─────────────────────────────────
# ~/.gitconfig is container-local: shared identity copied from the read-only base
# mount, then credential-store config appended. useHttpPath makes the store match
# per-repo, so the stack PAT and the homelab token route by URL — no credential
# ever embedded in a remote URL (the FU-002 lesson).
if [ -f /home/node/.gitconfig-base ]; then
  cp /home/node/.gitconfig-base "$HOME/.gitconfig"
else
  _sj_warn "no .gitconfig-base mount — set user.name/email manually"
fi
git config --global credential.helper "store --file $HOME/.git-credentials"
git config --global credential.https://github.com.useHttpPath true

: > "$HOME/.git-credentials"
chmod 600 "$HOME/.git-credentials"
_sj_cred() { # <token> <org/repo> — store entries with and without .git suffix
  printf 'https://x-access-token:%s@github.com/%s\nhttps://x-access-token:%s@github.com/%s.git\n' \
    "$1" "$2" "$1" "$2" >> "$HOME/.git-credentials"
}
if [ -n "${STACK_PAT:-}" ]; then
  # Split STACK_REPOS by newline, not by unquoted word-splitting: this file is
  # sourced under `zsh -c` (stack-jail.sh) and zsh does NOT word-split unquoted
  # expansions (SH_WORD_SPLIT is off), so `for r in $STACK_REPOS` iterated ONCE
  # over the whole string → a single malformed store entry (…/oracle-fleet
  # oracle-iac allure-…) that useHttpPath matches to no real repo. Proven 2026-07-15
  # in the oracle jail: oracle-iac had no credential (it lacks the incidental local
  # gh helper that masked the bug for the other repos). tr|read is cross-shell.
  echo "$STACK_REPOS" | tr ' ' '\n' | while IFS= read -r _sj_repo; do
    [ -n "$_sj_repo" ] && _sj_cred "$STACK_PAT" "teststuffstash/$_sj_repo"
  done
  export GH_TOKEN="$STACK_PAT"
else
  _sj_warn "STACK_PAT empty (fill ~/Projects/.env.${STACK_NAME:-<stack>}) — git push + gh will not work"
fi
if [ -n "${STACK_HOMELAB_TOKEN:-}" ]; then
  _sj_cred "$STACK_HOMELAB_TOKEN" teststuffstash/homelab
  # gh against homelab needs this token explicitly (GH_TOKEN is the stack PAT):
  #   GH_TOKEN=$(git credential fill <<< $'protocol=https\nhost=github.com\npath=teststuffstash/homelab' | sed -n 's/^password=//p') gh pr create -R teststuffstash/homelab ...
fi

# ── homelab context: shallow clone, never a host mount ─────────────────────────
# The host checkout carries gitignored secrets (tofu state, kubeconfig, tfvars);
# a clone excludes them by construction and is always fresh. Public repo → no token.
[ -w /workspace ] || sudo chown node:node /workspace
if [ ! -d /workspace/homelab ]; then
  git clone --depth 1 https://github.com/teststuffstash/homelab.git /workspace/homelab \
    || _sj_warn "homelab clone failed — ../homelab context missing"
fi

# ── kubectl: namespace-admin SA via the airlock token ──────────────────────────
if [ -n "${STACK_KUBE_TOKEN:-}" ] && [ -n "${STACK_KUBE_SERVER:-}" ]; then
  # Tokens/CA are single opaque strings; strip any whitespace that snuck in during
  # transport (a line-wrapped token once produced invalid kubeconfig YAML here).
  STACK_KUBE_TOKEN=$(printf '%s' "$STACK_KUBE_TOKEN" | tr -d '[:space:]')
  STACK_KUBE_CA=$(printf '%s' "${STACK_KUBE_CA:-}" | tr -d '[:space:]')
  mkdir -p "$HOME/.kube"
  cat > "$HOME/.kube/config" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: homelab
    cluster:
      server: ${STACK_KUBE_SERVER}
      certificate-authority-data: ${STACK_KUBE_CA}
users:
  - name: ${STACK_NAME:-stack}-workbench
    user:
      token: ${STACK_KUBE_TOKEN}
contexts:
  - name: ${STACK_NAME:-stack}
    context: { cluster: homelab, user: ${STACK_NAME:-stack}-workbench, namespace: ${STACK_KUBE_NS:-default} }
current-context: ${STACK_NAME:-stack}
EOF
  chmod 600 "$HOME/.kube/config"
  # kubectl itself comes from a devbox (shared /nix store) — the stack's own
  # devbox.json where it declares kubectl (oracle-fleet does), else the homelab
  # clone's: cd /workspace/homelab && devbox run -- kubectl get pods
else
  _sj_warn "no kube token injected — kubectl unavailable this session"
fi

# ── session card: rendered stack env card + shared container card ──────────────
# claude-jail#1 two-recipe design: /workspace is container-local here (only tools/
# and the stack dirs are mounted into it), so the composed card is ephemeral and
# Claude Code's upward traversal loads it from every stack repo. Stack jails get
# NO homelab seat card BY DESIGN (the seat card's header states why): the shallow
# clone's facts-only CLAUDE.md is the right amount of homelab context. Tokens are
# referenced by PRESENCE only — no secret may be rendered into the card.
if [ -n "${STACK_HOMELAB_TOKEN:-}" ]; then
  # $(cat <<'EOF') keeps $(...) and backticks literal — this text must not execute.
  _sj_hl=$(cat <<'EOF'
A homelab push token is installed: `agent/*` branches + PRs ONLY (the token's App identity enforces it — direct pushes to master are structurally impossible). `gh` against homelab needs that token explicitly (`GH_TOKEN` is the stack PAT): `GH_TOKEN=$(git credential fill <<< $'protocol=https\nhost=github.com\npath=teststuffstash/homelab' | sed -n 's/^password=//p') gh pr create -R teststuffstash/homelab ...`
EOF
)
else
  _sj_hl="No homelab push credential this session — treat the clone as read-only."
fi
if [ -n "${STACK_KUBE_TOKEN:-}" ] && [ -n "${STACK_KUBE_SERVER:-}" ]; then
  _sj_kube=$(cat <<EOF
namespace-admin ServiceAccount \`${STACK_NAME}-workbench\` in namespace \`${STACK_KUBE_NS:-default}\`, via a short-lived token (72h bound) in \`~/.kube/config\`. The \`kubectl\` binary comes from a devbox (shared /nix store): the stack's own \`devbox.json\` if it declares kubectl, else \`cd /workspace/homelab && devbox run -- kubectl ...\`.
EOF
)
else
  _sj_kube="no kube token was injected this session — kubectl is unavailable."
fi
{
  cat <<EOF
# ${STACK_NAME:-stack} stack jail — session card
<!-- rendered at session start by tools/stack-jail-init.sh from the STACK_* env — edit the renderer (or tools/jail-card.md below), not this file -->

- **Stack: ${STACK_NAME:-?}.** Only this stack's repos are mounted under \`/workspace\` (plus any private read-only extras) — \`ls /workspace\` shows the full set.
- **git/gh**: the stack's fine-grained PAT (owner identity) covers ONLY: ${STACK_REPOS:-<none>}. Direct push to master works there (the owner bypasses rulesets). \`gh\` is authenticated via \`GH_TOKEN\`. Known limit: fine-grained PATs have no Checks permission — \`gh pr checks\` 403s; use \`gh run watch\` + the PR's \`mergeStateStatus\` instead.
- **homelab**: shallow clone at \`/workspace/homelab\`, never the host checkout (it holds gitignored secrets). Its facts-only \`CLAUDE.md\` is your homelab context — this jail gets no homelab seat card by design. ${_sj_hl}
- **kubectl**: ${_sj_kube}
- **uploads**: files dropped via the upload UI land in \`${UPLOAD_DIR:-/workspace/uploads}\` (a gitignored inbox) — move them out to commit them.
- **handoff**: \`/workspace/.handoff\` is this stack's cross-jail channel (protocol: \`tools/handoff.md\`); only this stack's subtree is mounted, other stacks' traffic is invisible here.

---
EOF
  if [ -f /workspace/tools/jail-card.md ]; then
    cat /workspace/tools/jail-card.md
  else
    _sj_warn "tools/jail-card.md missing — session card composed WITHOUT the container ground rules"
    echo "(tools/jail-card.md was missing at composition time — container ground rules absent)"
  fi
} > /workspace/CLAUDE.local.md
unset _sj_hl _sj_kube

unset STACK_PAT STACK_HOMELAB_TOKEN STACK_KUBE_TOKEN STACK_KUBE_SERVER STACK_KUBE_CA
unset -f _sj_warn _sj_cred 2>/dev/null
true
