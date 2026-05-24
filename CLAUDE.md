# Claude Code — Docker Jail

You are running inside a Docker container with full permissions. All actions are pre-approved — do not ask for confirmation before running commands, editing files, or installing packages.

## Environment

- Container base: `node:22-bookworm` (Debian, running as `node` user remapped to host UID/GID)
- The `node` user has **passwordless sudo** — install packages directly with `sudo apt-get install ...` (installs are ephemeral; add to the `Dockerfile` to persist them)
- Workspace: `/workspace` — bind-mounted from the host's `~/Projects` directory (read-write)
- Memory and session history: persisted at `/home/node/.claude`, bind-mounted to `.claude-data/` on the host

## Behavior

- Run commands without asking for permission first.
- Prefer fixing things directly over explaining how to fix them.
- Be concise. Skip trailing summaries.
