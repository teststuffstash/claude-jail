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
