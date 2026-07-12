# stack-jail-init — sourced (zsh/sh) inside a per-stack jail before exec'ing claude.
# Companion to tools/stack-jail.sh (host side), which injects the env this consumes:
#   ORACLE_PAT            stack fine-grained PAT (owner identity, stack repos only)
#   ORACLE_HOMELAB_TOKEN  optional branch+PR-only token for homelab pushes
#   ORACLE_KUBE_*         short-lived SA token + server + CA (the airlock derivative)
# Everything here is per-session container state (credential store, kubeconfig,
# homelab clone) — the container is ephemeral, nothing persists but ~/.claude.
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
if [ -n "${ORACLE_PAT:-}" ]; then
  _sj_cred "$ORACLE_PAT" teststuffstash/oracle-fleet
  _sj_cred "$ORACLE_PAT" teststuffstash/oracle-iac
  export GH_TOKEN="$ORACLE_PAT"
else
  _sj_warn "ORACLE_PAT empty (fill ~/Projects/.env.oracle) — git push + gh will not work"
fi
if [ -n "${ORACLE_HOMELAB_TOKEN:-}" ]; then
  _sj_cred "$ORACLE_HOMELAB_TOKEN" teststuffstash/homelab
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
if [ -n "${ORACLE_KUBE_TOKEN:-}" ] && [ -n "${ORACLE_KUBE_SERVER:-}" ]; then
  mkdir -p "$HOME/.kube"
  cat > "$HOME/.kube/config" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: homelab
    cluster:
      server: ${ORACLE_KUBE_SERVER}
      certificate-authority-data: ${ORACLE_KUBE_CA}
users:
  - name: oracle-workbench
    user:
      token: ${ORACLE_KUBE_TOKEN}
contexts:
  - name: oracle
    context: { cluster: homelab, user: oracle-workbench, namespace: oracle-fleet }
current-context: oracle
EOF
  chmod 600 "$HOME/.kube/config"
  # kubectl itself comes from the homelab clone's devbox (shared /nix store):
  #   cd /workspace/homelab && devbox run -- kubectl get pods
else
  _sj_warn "no kube token injected — kubectl unavailable this session"
fi

unset ORACLE_PAT ORACLE_HOMELAB_TOKEN ORACLE_KUBE_TOKEN ORACLE_KUBE_SERVER ORACLE_KUBE_CA
unset -f _sj_warn _sj_cred 2>/dev/null
true
