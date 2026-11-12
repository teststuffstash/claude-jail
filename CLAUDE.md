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
- The `browser` compose service: the **browser sidecar** — one headless Chromium +
  Playwright MCP container per host, on the external `jail-browser` network, which every
  jail's entrypoint registers as the `browser` MCP server (`tools/mcp-register.py`); host
  verbs in `tools/jail-browser.sh`. Nothing browser-related is baked into the jail image.
- `.aliases`: host-side launch shortcuts, one per session type. Each publishes its own
  upload port; only `main` maps the OAuth callback port 54545, so log in there once —
  every other session shares the token via the `.credentials.json` single-file mount.
- `tools/`: the entrypoint, the stack launcher/init pair, the upload server, the
  cross-jail handoff protocol (`tools/handoff.md`), and the jail card. The stack launcher's
  host-side helpers: `stack-lock.sh` (one launch per stack), `secret-cmd.sh` (`<NAME>_CMD`
  tokens from a wallet), `git_audit.py` (what a session left in `.git` that the host would
  run), `pin-aliases.sh` (`jail-pin`: the host shell sources a reviewed copy of `.aliases`).
- The image is `debian:trixie` with native Claude Code and Codex binaries and no Node runtime;
  the user is still called `node` because `/home/node` is in every mount and launcher.
- This directory doubles as the host's `~/Projects`: project repos are cloned
  side-by-side and gitignored here (see `.gitignore`'s cloned-projects block).
- The **work variant** (`RasmusSoot/claude-jail-work`, forked from here at `98051c0`) is a
  separate repo with its own Claude and its own rules. Changes move by **pull only**: each side
  reads the other and takes what it likes; neither writes to the other. Its clone at
  `claude-jail-work/` is a read-only reference; `tools/work-variant.sh` shows what is new there
  since the commit recorded in `tools/work-variant.rev`.
- Credential boundary (HARD RULE): no credential in any jail may reach beyond the
  `teststuffstash` org — fine-grained PATs with that resource owner, or App installation
  tokens.
