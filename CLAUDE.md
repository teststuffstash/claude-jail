# Claude Code — Docker Jail

You are running inside a Docker container with full permissions. All actions are pre-approved — do not ask for confirmation before running commands, editing files, or installing packages.

## Environment

- Container base: `node:22-bookworm` (Debian, running as `node` user remapped to host UID/GID)
- The `node` user has **passwordless sudo** — install packages directly with `sudo apt-get install ...` (installs are ephemeral; add to the `Dockerfile` to persist them)
- **Project tooling is Devbox/Nix, not apt.** For per-project CLI tools (tofu, kubectl, talosctl, helm, …) prefer a committed `devbox.json` + `devbox shell` over ephemeral `sudo apt`/`curl` installs. The `/nix` store is bind-mounted from the host, so the same `devbox.json` works in the jail and on the host (and persists across rebuilds). `devbox.lock` is committed for deterministic versions.
- Workspace: `/workspace` — bind-mounted from the host's `~/Projects` directory (read-write)
- Memory and session history: persisted at `/home/node/.claude`, bind-mounted to `.claude-data/` on the host

## Homelab platform services (S3, DB, dashboards, …)

Many projects here build on the self-hosted **homelab** Kubernetes cluster. To discover what services
exist (and which are only planned), **read [`/workspace/homelab/SERVICES.md`](homelab/SERVICES.md) and
grep it** — that catalog is the source of truth. **Do not `kubectl` around the cluster to discover
services**, and do not assume a service exists until the catalog marks it `LIVE` (e.g. S3/Garage and
Postgres/CloudNativePG are both LIVE). Statuses change — **recheck the catalog, never repeat a
remembered status** (Postgres sat in this very sentence as "PLANNED" long after it went LIVE). How
to consume one is linked from the catalog.

## Behavior

- Run commands without asking for permission first.
- Prefer fixing things directly over explaining how to fix them.
- Be concise. Skip trailing summaries.
