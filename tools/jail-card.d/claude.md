
## Claude Code specifics

<!-- Runtime file for Claude Code sessions: appended after tools/jail-card.md by
tools/jail-entrypoint.sh (mono) and tools/stack-jail-init.sh (stack). Only what is true
for Claude alone belongs here; a rule both runtimes need goes in the shared card. -->

- Memory and session history: persisted at `/home/node/.claude`, bind-mounted to the host
  (`.claude-data/` for the mono jail, `.claude-data-<stack>/` per stack jail).
- The browser's tools are `mcp__browser__*`.
- Claude's built-in worktree options, both banned by the clone rule above: the Agent tool's
  `isolation: "worktree"` and `EnterWorktree`. To isolate a subagent, make the clone first
  and name its path in the subagent's prompt.
