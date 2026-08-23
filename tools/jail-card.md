# Jail card — container ground rules for every jail session

<!-- The ONE versioned home for jail-session ground rules (claude-jail#1, homelab FU-117).
Composed into the session at container start — never hand-pasted, never edited at the
composition target (edit THIS file):
  - mono jail: tools/jail-entrypoint.sh writes it to /workspace/CLAUDE.local.md, and
    additionally composes homelab's agents/jail-seat-card.md to
    /workspace/homelab/CLAUDE.local.md (homelab-scoped, seat sessions only);
  - stack jail: tools/stack-jail-init.sh prepends its rendered per-stack env card and
    writes the pair to /workspace/CLAUDE.local.md (container-local). Stack jails get NO
    homelab seat card by design — see the seat card's header for why. -->

You are running inside a Docker container with full permissions. All actions are
pre-approved — do not ask for confirmation before running commands, editing files, or
installing packages.

## Environment

- Container base: `node:22-bookworm` (Debian, running as `node` user remapped to host
  UID/GID)
- The `node` user has **passwordless sudo** — install packages directly with
  `sudo apt-get install ...` (installs are ephemeral; add to claude-jail's `Dockerfile`
  to persist them)
- **Project tooling is Devbox/Nix, not apt.** For per-project CLI tools (tofu, kubectl,
  talosctl, helm, …) prefer a committed `devbox.json` + `devbox shell` over ephemeral
  `sudo apt`/`curl` installs. The `/nix` store is bind-mounted from the host, so the same
  `devbox.json` works in the jail and on the host (and persists across rebuilds).
  `devbox.lock` is committed for deterministic versions.
- Memory and session history: persisted at `/home/node/.claude`, bind-mounted to the host
  (`.claude-data/` for the mono jail, `.claude-data-<stack>/` per stack jail)
- Two jail classes share this card. The **mono jail** mounts all of the host's
  `~/Projects` at `/workspace` (read-write). A **stack jail** mounts only its stack's
  repos plus `tools/`, and shallow-clones homelab inside the container — its session card
  (prepended above this one) carries the per-stack facts: credentials, kubectl, ports.

## Homelab platform services (S3, DB, dashboards, …)

Many projects here build on the self-hosted **homelab** Kubernetes cluster. To discover
what services exist (and which are only planned), **read
[`/workspace/homelab/SERVICES.md`](/workspace/homelab/SERVICES.md) and grep it** — that
catalog is the source of truth. **Do not `kubectl` around the cluster to discover
services**, and do not assume a service exists until the catalog marks it `LIVE` (e.g.
S3/Garage and Postgres/CloudNativePG are both LIVE). Statuses change — **recheck the
catalog, never repeat a remembered status** (Postgres sat in this very sentence as
"PLANNED" long after it went LIVE). How to consume one is linked from the catalog.

## Behavior

- Run commands without asking for permission first.
- Prefer fixing things directly over explaining how to fix them.
- Be concise. Skip trailing summaries.
- **Prior-art check before creating anything named** (a doc, script, tracker entry, ADR,
  manifest): these projects are heavily documented — assume the concern already has an
  owner. Grep the project's docs/trackers/memory by topic keywords and state what you
  found ("nothing matches <keywords>") before writing. If a related artifact exists,
  extend it, never create a parallel one.
- **Resolve references before acting on them.** When the user names a thing ("the
  credential helper", "that follow-up", "the leaked PAT"), it exists — grep for it and
  act on what you find, not on a reconstruction. Questions like "is this already tracked
  somewhere?" are retrieval requests (the user half-remembers, without the exact
  place/id), not decisions delegated to you.
