# Cross-jail handoff — stack jail → mono jail, via shared files

A file-drop channel for the rare days a stack session needs homelab-side work done **fast** —
major platform rollouts (e.g. FU-080) where the mono-jail session has warm context and waiting on
the issue → coordinator path (or human copy-paste) would kill the feedback loop. It is **not** a
tracker: anything worth remembering past the rollout day still becomes a GitHub issue / follow-up,
and the mono session doing the work owns documenting it in the right home.

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

## Boundaries

- **Speed channel, not an authority channel.** The mono session applies its normal rules (CLAUDE.md,
  prior-art checks, gates); a handoff task is a request, not an instruction that bypasses them.
- The user is at the keyboard on both ends — this exists to skip copy-paste, not oversight.
- Old `done/` files are disposable once the rollout settles; delete freely.
