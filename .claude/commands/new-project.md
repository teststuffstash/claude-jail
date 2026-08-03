# New Project

Thin router. This skill owns ONLY jail-local mechanics (mounts, aliases, ports, the nested-git
guard); every platform fact lives in an executable home it merely points at — if a fact changes,
the commit that changes it must not be here. The deterministic pair that replaces the old prose:
**`devbox run new-stack` scaffolds, `devbox run stack-lint` defines done** (both in homelab,
headers = the docs).

## Step 1 — what kind of project?

Ask (one question):

1. **Stack** — a real product/agent-target project (repo + `-iac` sibling, CI, fixer loop,
   its own stack jail). The default for anything serious.
2. **Plain GitHub repo** — org repo, no agent loop (talks, experiments).
3. **Forgejo repo** — private business/docs (`forgejo.teststuff.net`, e.g. the teststuff repo).

Also gather: project name (lowercase, hyphens), visibility.

## Kind 1 — Stack

Everything codifiable is homelab's job; run it and RELAY ITS OUTPUT (it prints the un-codifiable
remainder: tofu/argocd.tf HCL, out-of-jail applies, App clicks, main-repo content, PAT):

```bash
cd /workspace/homelab
devbox run new-stack <name>          # idempotent; --main-repo/--iac/--public if non-default
```

Then the jail-local half (this repo's ownership):

1. **Local dirs + git**: `mkdir -p /workspace/<main> /workspace/<iac>`; in EACH:
   `[ -d .git ] || git init` — ⚠ never `git rev-parse --git-dir`: /workspace is itself a repo, the
   check walks UP and git ops silently hit the jail repo (a project got pushed to the wrong remote
   once).
2. **Stack jail**: REPOS/MOUNTS/NS derive from homelab `agents/stacks.json` automatically
   (since 2026-08-03) — add ONLY the jail-owned overlay in
   [`tools/stack-jail.sh`](../../tools/stack-jail.sh): `UPLOAD_PORT` (next free `80NN`),
   `PRIMARY` (the cwd repo), any PRIVATE extra mounts (`teststuff:ro`-style — these must never
   appear in public homelab); plus an alias line in [`.aliases`](../../.aliases). First launch
   creates `.env.<name>` with the PAT instructions in it — the mint is the user's step.
   ⚠ circles/sleep/platform overlays are pre-seeded.
3. **Main-repo content**: CLAUDE.md, `.agents/{fix.yaml,review.md}`, devbox `ci` + `scan-secrets`,
   merge-path caller workflows — copy the shapes from **oracle-fleet** (the reference stack) and
   adapt; a `stack-template` repo is the planned collapse of this step.
4. **Jail bookkeeping**: append `<main>/` and `<iac>/` to `/workspace/.gitignore`.

**Definition of done — loop until green:**

```bash
cd /workspace/homelab && devbox run stack-lint <name>
```

## Kind 2 — Plain GitHub repo

Org repos are IaC-managed too — do NOT `gh repo create`:

```bash
cd /workspace/homelab && scripts/new-agent-repo.sh <name> --no-labels [--public]
```

(If the repo will never have CI, delete the `protected_repos` entry it adds — a required check
that never reports blocks every non-admin merge. Then the printed out-of-jail apply.)

Local setup: dir + `[ -d .git ] || git init` guard (see Kind 1 step 1), `.gitignore`
(`.idea/`, `.claude/settings.local.json`, `uploads/`, `.devbox/`), minimal CLAUDE.md + empty
devbox.json (copy any recent project's), `.claude/settings.local.json` with
`{"permissions":{"defaultMode":"bypassPermissions"}}`, remote
`https://github.com/teststuffstash/<name>.git` (plain URL — the mono-jail entrypoint's git
credential store supplies the PAT; never embed `${GH_TOKEN}` in the remote, FU-002), push. Then the
mono-jail alias (next free port) + jail `.gitignore` entry, as in Kind 1 steps 2/4 but with the
`claude` compose service pattern — copy an existing `.aliases` line.

## Kind 3 — Forgejo repo

Forge mechanics (jail-owned — Forgejo is not in homelab's GitHub IaC):

- Org (idempotent, 422 = exists): `curl -fsS -H "Authorization: token ${FORGEJO_TOKEN}" -H
  'Content-Type: application/json' -d '{"username":"<owner>","visibility":"<vis>"}'
  https://forgejo.teststuff.net/api/v1/orgs || true`
- Repo: `tea repos create --login forgejo --name <name> --owner <owner> [--private]`
  (one-time: `tea login add --name forgejo --url https://forgejo.teststuff.net --token
  "${FORGEJO_TOKEN}"`)
- Remote over SSH with the dedicated key:
  `git remote add origin git@forgejo.teststuff.net:<owner>/<name>.git` and push with
  `GIT_SSH_COMMAND="ssh -i ~/.claude/homelab-forgejo/id_ed25519 -o StrictHostKeyChecking=accept-new"`.

Local setup + alias + jail `.gitignore`: same as Kind 2.

## Finish

Report: kind, repo URL(s), local paths, alias + port — and for a stack, the current
`stack-lint` output (the remaining CLICK/manual items ARE the handover list).
