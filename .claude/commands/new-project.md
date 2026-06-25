# New Project

Set up a new project directory, a remote repo on **GitHub or Forgejo**, a minimal
per-project devbox, and a shell alias — in one shot.

## Step 1 — gather inputs

Ask the user (can ask together):

1. **Forge** — `github` or `forgejo`?
   - `github` → repo lives at `teststuffstash/<name>` (uses `gh` + `GH_TOKEN`).
   - `forgejo` → self-hosted `forgejo.teststuff.net` (uses `tea`/API + `FORGEJO_TOKEN`,
     pushes over SSH). Ask which **owner**: an existing org, your user `rasmus`, or a
     **new org** (created if missing).
2. **Project name** — lowercase, hyphens allowed, no spaces (e.g. `my-app`).
3. **Visibility** — public or private?

If the project directory already exists with a local git repo (common — you may have
scaffolded a README first), skip the init bits and just add what's missing.

## Step 2 — create the directory and git repo

```bash
mkdir -p /workspace/<name>
cd /workspace/<name>
# IMPORTANT: /workspace is itself a git repo (claude-jail), so `git rev-parse --git-dir` walks UP
# and falsely reports "already a repo" — then every add/commit/remote/push silently runs against the
# parent jail repo (this happened once: a whole project got pushed to the wrong GitHub repo and the
# jail repo's origin got clobbered). Check for a `.git` in THIS directory only:
[ -d .git ] || git init
```

## Step 3 — create .gitignore

Ensure `/workspace/<name>/.gitignore` contains (append if it already exists):

```
.idea/
.claude/settings.local.json
uploads/
.devbox/
```

## Step 4 — create CLAUDE.md

If absent, write `/workspace/<name>/CLAUDE.md`:

```
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This project is in its early stages. Update this file as the architecture and tooling become established.

## Environment

Running inside a Docker jail — see `/workspace/CLAUDE.md` for container setup, permissions, and available tools.

## Tooling

Per-project CLI tools go in `devbox.json` (Nix-backed, shared host /nix store). Run them with
`devbox run -- <cmd>` or enter a shell with `devbox shell`. Add packages with `devbox add <pkg>`.
```

## Step 4b — create local Claude settings

So edits inside this project's `.claude/` don't prompt every time:

```bash
mkdir -p /workspace/<name>/.claude
```

Write `/workspace/<name>/.claude/settings.local.json`:

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
```

Gitignored (Step 3) — a per-machine convenience, not shared with the repo.

## Step 4c — scaffold a minimal devbox.json

Every project gets its own devbox so per-project tooling has a home from day one. Write a
minimal committed `/workspace/<name>/devbox.json`:

```json
{
  "$schema": "https://raw.githubusercontent.com/jetify-com/devbox/0.16.0/.schema/devbox.schema.json",
  "packages": [],
  "shell": {
    "init_hook": [],
    "scripts": {}
  }
}
```

Leave `packages` empty until the project actually needs something — then `devbox add <pkg>`
in the project dir, which also writes the committed `devbox.lock` for deterministic versions.
(Don't run `devbox install` here; an empty package set needs nothing.)

## Step 5 — create the remote repo

### GitHub

```bash
gh repo create teststuffstash/<name> --<public|private>
```

### Forgejo

Uses `FORGEJO_TOKEN` (from `.env`). For a **new org**, create it first (idempotent — a 422
means it already exists, which is fine):

```bash
curl -fsS -H "Authorization: token ${FORGEJO_TOKEN}" -H 'Content-Type: application/json' \
  -d '{"username":"<owner>","visibility":"<public|private>"}' \
  https://forgejo.teststuff.net/api/v1/orgs || true
```

Then the repo. If `tea` has no `forgejo` login yet, add it once (token-based, no password):

```bash
tea login add --name forgejo --url https://forgejo.teststuff.net --token "${FORGEJO_TOKEN}"
```

```bash
tea repos create --login forgejo --name <name> --owner <owner> \
  $( [ "<visibility>" = private ] && echo --private )
```

(API fallback if `tea` is unavailable: `POST /api/v1/orgs/<owner>/repos` with
`{"name":"<name>","private":<bool>}` for an org, or `/api/v1/user/repos` for your user.)

## Step 6 — set the remote and push

### GitHub (HTTPS with token)

```bash
cd /workspace/<name>
git remote add origin "https://x-access-token:${GH_TOKEN}@github.com/teststuffstash/<name>.git"
git add -A && git commit -m "Initial commit" 2>/dev/null || true
git branch -M master
git push -u origin master
```

### Forgejo (SSH)

Forgejo is wired for SSH (key `~/.claude/homelab-forgejo/id_ed25519`, user `git`, port 22).
Push through that key explicitly so it works regardless of the jail's default SSH config:

```bash
cd /workspace/<name>
git remote add origin "git@forgejo.teststuff.net:<owner>/<name>.git"
git add -A && git commit -m "Initial commit" 2>/dev/null || true
git branch -M master
GIT_SSH_COMMAND="ssh -i ~/.claude/homelab-forgejo/id_ed25519 -o StrictHostKeyChecking=accept-new" \
  git push -u origin master
```

## Step 6b — CI & platform requirements (discover, don't inline)

The project **depends on** the homelab platform contract — don't copy its facts into this repo,
**reference** them. The catalog is [`homelab/SERVICES.md`](../homelab/SERVICES.md) (grep it — it lists
CI runners, S3, registries, Postgres, secrets, …). At *runtime* an in-cluster agent gets what it needs
**injected by the conductor** (model key via ESO, the repo, endpoints) — it does **not** clone homelab.

If the project has CI, scaffold a thin `.github/workflows/ci.yaml` that just calls `devbox run ci` on
the self-hosted runner (SERVICES.md → "CI runner — ephemeral"):

```yaml
jobs:
  ci:
    runs-on: homelab-ephemeral
    steps:
      - uses: actions/checkout@v4
      - name: Install xz (missing from the ARC runner image)
        run: sudo apt-get update -qq && sudo apt-get install -y -qq xz-utils
      - uses: cachix/install-nix-action@v31
        with: { install_options: --no-daemon, extra_nix_config: "experimental-features = nix-command flakes" }
      - uses: jetify-com/devbox-install-action@v0.13.0
        with: { skip-nix-installation: "true" }
      - run: devbox run ci
```

**One-time org prereq for a new repo** (see [`homelab/docs/github-setup.md`](../homelab/docs/github-setup.md)):
the org App + Default runner group already cover repos, but a **public** repo also needs the runner
group's **"Allow public repositories"** toggle — without it CI queues forever with no runner.

## Step 7 — add to jail .gitignore

The project is its own repo; the jail repo must not track it:

```bash
echo "<name>/" >> /workspace/.gitignore
git -C /workspace add .gitignore && git -C /workspace commit -m "Ignore <name>/"
```

## Step 8 — add shell alias

Allocate the **next free host port** (the upload UI is always container `8000`; each session
publishes a distinct host port). Check existing aliases for the highest `-p 80NN:8000` and add 1.

Append to `/workspace/.aliases` with a literal heredoc (substitute `<name>` and `<port>` first):

```bash
cat >> /workspace/.aliases <<'EOF'
alias <name>='UPLOAD_DIR=/workspace/<name>/uploads docker compose -f ~/Projects/docker-compose.yml run --rm -p <port>:8000 claude zsh -c "cd /workspace/<name> && exec claude"'
EOF
```

Then tell the user:

> Alias written to `~/Projects/.aliases`. If not already done, add `source ~/Projects/.aliases`
> to your host `~/.zshrc`, then `source ~/.zshrc`.

## Step 9 — done

Confirm what was created: forge + repo URL, local path, devbox.json, alias name + port.
