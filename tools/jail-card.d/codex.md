
## Codex specifics

<!-- Runtime file for Codex sessions: appended after tools/jail-card.md by
tools/codex-context.py into the global ~/.codex/AGENTS.md. Only what is true for Codex
alone belongs here; a rule both runtimes need goes in the shared card. -->

- The host launcher bypasses Codex approvals and sandboxing; Docker is the boundary.
- Instructions: this file is the global `~/.codex/AGENTS.md`. A project's `AGENTS.md` is
  generated from its `CLAUDE.md` + `CLAUDE.local.md` unless the project has its own. Text
  written for Claude Code (slash commands, hooks, the Agent tool, `/workspace/CLAUDE.local.md`)
  needs a Codex equivalent; reading it does not implement it.
- Homelab skills, when mounted, are linked at `/home/node/.agents/skills`.
- Git and service access depend on provisioned credentials. Verify availability; do not
  assume a credential or service is present merely because a card mentions it.
