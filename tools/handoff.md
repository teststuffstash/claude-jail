# Cross-jail handoff — stack jail → mono jail, via shared files

A file-drop channel for the rare days a stack session needs homelab-side work done **fast** —
major platform rollouts (e.g. FU-080) where the mono-jail session has warm context and waiting on
the issue → coordinator path (or human copy-paste) would kill the feedback loop. It is **not** a
tracker: anything worth remembering past the rollout day still becomes a GitHub issue / follow-up,
and the mono session doing the work owns documenting it in the right home.

**Status (operator, 2026-10-26): a stopgap, kept honest.** The channel had one mission — a stack
files homelab-side work — and is now also used for the shapes below, so every assumption about it
is suspect. The direction is stack↔platform communication that needs no live seat (the
`platform-request` label on the stack repo is the shape); handoff + issues/PRs is good enough
until then. A useful antipattern: extend the protocol here, never grow machinery around it.

## Topology

Host `~/Projects/.handoff/<stack>/{inbox,doing,done}` (gitignored runtime data).

| Jail | Sees | As |
|---|---|---|
| mono (`main`) | every stack's subtree | `/workspace/.handoff/<stack>/…` |
| stack (e.g. oracle) | only its own subtree | `/workspace/.handoff/{inbox,doing,done}` |

The per-stack mount is wired by `tools/stack-jail.sh` (dirs pre-created there too). No network, no
credentials — same-host bind mounts only.

## Protocol

One task = one markdown file. Lifecycle: `inbox/` → `doing/` → `done/`, moved with `mv`
(atomic claim; never edit a file in place across the boundary except as described below).

**Filing (stack session):**

```bash
f="/workspace/.handoff/inbox/$(date +%Y%m%d-%H%M)-<slug>.md"
```

```markdown
# <one-line title>
from: oracle
repo: homelab            # best guess at where the work lands; mono session may know better

<What you need and why — symptoms, exact commands + output, what you already ruled out.
Write it like a good bug report: the reader has homelab context but not YOUR session.>
```

**Processing (mono session):** `/handoff` claims the oldest inbox file (`mv` to `doing/`), does the
work, appends a `## Result` section (what was done/answered, commits/PRs touched, or the question
if it needs more input), then `mv` to `done/`. Run it in a loop during rollout days:
`/loop /handoff` (self-paced) or `/loop 3m /handoff`.

**Reading the answer (stack session):** watch `done/` — `ls /workspace/.handoff/done/`. A result
that is a counter-question is answered by filing a fresh inbox task (files in `done/` are never
edited again; the filename ordering keeps the thread readable).

**Outbound notices (mono → stack):** a mono session that has something for a stack — a SHIPPED
notice for work the stack is waiting on, an answer nobody asked for yet, a heads-up — writes it
straight into that stack's `done/` as `<stamp>-<slug>.md` with the same header and a `## Result`
body (there is nothing to claim, so `inbox/`/`doing/` are skipped). The stack reads `done/` as
before; a reply is a fresh inbox task. (Improvised the same way three times in Oct 2026, GAPS
handoff-G4 — now the documented shape.)

**Durable records from a SECOND jail:** a secondary homelab session (`/second-jail`) may work and
answer handoff tasks but owns no shared record (tracker, meta-state, TICK-LOG). It writes the
`## Result`, moves the file to `done/`, and hands the durable record — the FU/issue the task
deserves — to the primary seat in its final message instead of filing it.

## Boundaries

- **Speed channel, not an authority channel.** The mono session applies its normal rules (CLAUDE.md,
  prior-art checks, gates); a handoff task is a request, not an instruction that bypasses them.
- The user is at the keyboard on both ends — this exists to skip copy-paste, not oversight.
- Old `done/` files are disposable once the rollout settles; delete freely.
