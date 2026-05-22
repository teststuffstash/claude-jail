# Claude Code — Docker Jail

Runs Claude Code in an isolated Docker container with full permissions, persistent memory, and host file access. Files written inside the container are owned by your host user.

## Architecture

```mermaid
graph LR
    subgraph host["Host Machine"]
        H1["~/Projects/"]
        H2["~/Projects/.claude-data/"]
        H3["~/Projects/.claude-data.json"]
        H4["~/Projects/.claude-data.zsh_history"]
        H5["~/.zshrc · ~/.oh-my-zsh/"]
        H6[".env: HOST_UID · HOST_GID · GH_TOKEN"]
        BROWSER["Browser"]
    end

    subgraph jail["Docker Jail — node:22-bookworm"]
        J1["/workspace"]
        J2["/home/node/.claude/"]
        J3["/home/node/.claude.json"]
        J4["/home/node/.zsh_history"]
        J5["shell config"]
        TINI(["tini · PID 1"])
        CLAUDE(["claude CLI"])
        UP["upload server :8000"]
        CB["OAuth listener :54545"]
    end

    subgraph ext["External"]
        AI(["claude.ai — Pro / Max"])
        GH(["GitHub — teststuffstash"])
    end

    H1 -- "rw" --> J1
    H2 -- "rw" --> J2
    H3 -- "rw" --> J3
    H4 -- "rw" --> J4
    H5 -- "ro" --> J5
    H6 -. "env vars" .-> CLAUDE
    TINI -- "spawns" --> CLAUDE
    TINI -- "spawns (bg)" --> UP
    BROWSER -- "drag / paste files" --> UP
    CLAUDE -- "1. /login opens" --> BROWSER
    BROWSER -- "2. authenticate" --> AI
    AI -- "3. redirect to localhost:54545" --> BROWSER
    BROWSER -- "4. callback" --> CB
    CB -- "5. token" --> CLAUDE
    CLAUDE -- "fine-grained PAT" --> GH
```

Claude runs as a non-root user with your host UID/GID — files created in `/workspace` appear on the host owned by you, no `chown` needed.

## Bootstrap

### 1. Build

```bash
./setup-env.sh
docker compose build
```

`setup-env.sh` writes your UID/GID to `.env` and generates `docker-compose.override.yml` with whichever zsh dotfiles exist on your host. Re-run it if your dotfiles change.

### 2. Run

Use the `main` alias from `.aliases` (it publishes the upload + OAuth ports):

```bash
main   # = docker compose run --rm -p 8000:8000 -p 54545:54545 claude
```

For project sessions use the other `.aliases` shortcuts (`car-fleet`, `homelab`, `therapy`) — see [Upload server & ports](#upload-server--ports). Compose itself declares no `ports:`; each alias publishes its own with `-p`.

### 3. Log in

From the **main** jail (it's the only session that maps the OAuth callback port `54545`), run:

```
/login
```

This authenticates via your claude.ai account (Pro or Max). The token is persisted in `~/Projects/.claude-data/` and reused by every other session — you only log in once.

### 4. GitHub CLI (optional)

GitHub doesn't support pre-selecting fine-grained token permissions via URL, so you'll need to configure these manually.

**First, enable fine-grained PATs in your org:**
`https://github.com/organizations/teststuffstash/settings/personal-access-tokens`
→ Allow access via fine-grained personal access tokens

**Then create the token:**
[Open token creation →](https://github.com/settings/personal-access-tokens/new?description=claude-jail&resource_owner=teststuffstash)

Configure it as follows:

| Field | Value |
|---|---|
| Resource owner | `teststuffstash` |
| Repository access | All repositories |
| Administration | Read and Write |
| Contents | Read and Write |
| Issues | Read and Write |
| Metadata | Read (auto) |
| Pull requests | Read and Write |
| Workflows | Read and Write |
| Everything else | No access |

Then add it to `.env`:

```bash
GH_TOKEN=github_pat_...
```

Repo deletions are recoverable — org owners can restore deleted repos via GitHub settings for 90 days.

## What's inside

| Path (container) | Path (host) | Notes |
|---|---|---|
| `/workspace` | `~/Projects` | Read-write. Your working directory. |
| `/home/node/.claude/` | `~/Projects/.claude-data/` | Memory, history, settings. |
| `/home/node/.claude.json` | `~/Projects/.claude-data.json` | Onboarding state (theme, startup count). |
| `/home/node/.zsh_history` | `~/Projects/.claude-data.zsh_history` | Shell history. |
| `/home/node/.gitconfig` | `~/Projects/.claude-data.gitconfig` | Jail-only git identity; host `~/.gitconfig` is intentionally not mounted. |
| `/home/node/.zshrc` | `~/.zshrc` | Read-only. |
| `/home/node/.oh-my-zsh/` | `~/.oh-my-zsh/` | Read-write (plugin installs persist). |

## Upload server & ports

`tini` runs as PID 1 and auto-starts the file-drop upload server (`tools/upload/upload.py`) in the background before launching `claude` — see `tools/jail-entrypoint.sh`. It lets you paste/drag screenshots and docs from the host into the jail. Dropped files land in each project's gitignored `uploads/` inbox; move them out of `uploads/` to commit. Details in `tools/upload/README.md`.

To run several sessions at once without port clashes, the **container** always serves the upload UI on `8000` while each alias publishes its own **host** port with `-p` (compose declares no `ports:`):

| Session | Upload UI (host) | OAuth (host) |
|---|---|---|
| `main` (`~/Projects`) | `localhost:8000` | `54545` ← log in here |
| car-fleet | `localhost:8001` | — |
| homelab | `localhost:8002` | — |
| therapy | `localhost:8003` | — |

The **main** jail runs from `~/Projects` for general/infra work and is the only session that maps the OAuth port, so it's the only one that can complete `/login` (the callback is fixed to `localhost:54545`). The project jails don't publish it at all. Log in once via `main`; the token persists in `.claude-data/` and works in every other session.

## Re-running

```bash
main        # general/infra jail (also where you /login)
car-fleet   # or homelab / therapy
```

No rebuild needed unless you update the `Dockerfile`. Re-run `setup-env.sh` if your zsh dotfiles change.
