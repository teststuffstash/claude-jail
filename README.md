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
        CLAUDE(["claude CLI"])
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

```bash
docker compose run --rm claude
```

### 3. Log in

Inside Claude Code, run:

```
/login
```

This authenticates via your claude.ai account (Pro or Max). The session is persisted in `~/Projects/.claude-data/`.

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
| `/home/node/.zshrc` | `~/.zshrc` | Read-only. |
| `/home/node/.oh-my-zsh/` | `~/.oh-my-zsh/` | Read-write (plugin installs persist). |

## Re-running

```bash
docker compose run --rm claude
```

No rebuild needed unless you update the `Dockerfile`. Re-run `setup-env.sh` if your zsh dotfiles change.
