# Handoff — process one cross-jail inbox task

Process the file-drop channel stack jails use to hand homelab-side work to this session
(protocol + boundaries: [`tools/handoff.md`](../../tools/handoff.md)). Designed to be looped
during platform-rollout days: `/loop /handoff` (self-paced) or `/loop 3m /handoff`.
**One task per invocation** — claim, finish, report, stop; the loop provides the cadence.

1. **Scan**: `ls /workspace/.handoff/*/inbox/*.md` (all stacks). Nothing there → say "handoff
   inbox empty" and stop. Never re-open `doing/` from a previous crashed run without saying so.
2. **Claim the oldest** (filename sort = time order): `mv` it to the sibling `doing/`. Announce
   what you picked up — the user is watching this session.
3. **Do the work** in the relevant repo with your warm context, under ALL the normal rules
   (CLAUDE.md, prior-art check, gates like `devbox run ci` where they exist). A handoff task is a
   request, not permission to skip anything. Destructive/irreversible actions still get asked
   about. If the task is unclear or bigger than a loop turn should absorb, don't grind — answer
   with what's blocking as the result and let the stack session refile with more detail; a fast
   counter-question IS the point of this channel.
4. **Record + hand back**: append a `## Result` section to the file (what was done or answered,
   commits/PRs/paths touched, or the counter-question), then `mv` to `done/`. If the work is
   worth remembering past the rollout day, also put it in its durable home (follow-up, issue,
   doc) — the handoff file is not a tracker.
5. **Report** to the user: task title, outcome, where the durable trace lives (if any).
