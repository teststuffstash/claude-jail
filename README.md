# Claude Code — Docker Jail

Runs Claude Code in an isolated Docker container with full permissions, persistent memory, and host file access. Files written inside the container are owned by your host user.

## Bootstrap

### 1. API Key

Get a key from [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys), then store it:

```bash
echo 'sk-ant-...' > ~/.claude/api_key
chmod 600 ~/.claude/api_key
```

### 2. Build

```bash
./setup-env.sh
docker compose build
```

`setup-env.sh` reads your API key and UID/GID from the host and writes them to `.env`. Re-run it if you rotate your key.

### 3. Run

```bash
docker compose run --rm claude
```

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
| `/home/node/.claude` | `~/Projects/.claude-data` | Persists memory, history, settings. |

Claude runs as a non-root user with your host UID/GID — files created in `/workspace` appear on the host owned by you, no `chown` needed.

## Re-running

Just `docker compose run --rm claude`. No rebuild needed unless you update the `Dockerfile`.

## Rotating the API key

```bash
echo 'sk-ant-new-key' > ~/.claude/api_key
./setup-env.sh
```
