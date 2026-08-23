# claude-jail — Docker jails for Claude Code sessions

Repo facts only. **Session ground rules do not live here** — they live in
[`tools/jail-card.md`](tools/jail-card.md), composed into `CLAUDE.local.md` at container
start (claude-jail#1, homelab FU-117): the mono jail's `tools/jail-entrypoint.sh` writes
the card to `/workspace/CLAUDE.local.md` and homelab's `agents/jail-seat-card.md` to
`/workspace/homelab/CLAUDE.local.md` (seat sessions only); a stack jail's
`tools/stack-jail-init.sh` prepends its rendered per-stack env card instead and gets no
seat card by design.

## What this repo is

- `Dockerfile` + `docker-compose.yml`: one image, two services — `claude` (the **mono
  jail**: all of the host's `~/Projects` mounted at `/workspace`) and `stack` (the
  **per-stack jails**: scoped mounts, per-stack tokens, SA-scoped kubectl; launcher
  `tools/stack-jail.sh`, in-container init `tools/stack-jail-init.sh`).
- `.aliases`: host-side launch shortcuts, one per session type. Each publishes its own
  upload port; only `main` maps the OAuth callback port 54545, so log in there once —
  every other session shares the token via the `.credentials.json` single-file mount.
- `tools/`: the entrypoint, the stack launcher/init pair, the upload server, the
  cross-jail handoff protocol (`tools/handoff.md`), and the jail card.
- This directory doubles as the host's `~/Projects`: project repos are cloned
  side-by-side and gitignored here (see `.gitignore`'s cloned-projects block).
- Credential boundary (HARD RULE): no credential in any jail may reach beyond the
  `teststuffstash` org — fine-grained PATs with that resource owner, or App installation
  tokens.
