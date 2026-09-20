# Codex jail — host build complete, runtime integration handoff

Updated 2026-09-20. Jail repository: `/home/rasmus/Projects` on the host,
`/workspace` inside the mono jail. Origin: teststuffstash/claude-jail.
The nested homelab checkout is a separate repository.

## Scope and workflow

The jail is standalone. Do not import homelab's issue lifecycle, worker queues,
review/merge rules, stint/tick-log process, watchers, or platform orchestration into
this build. The homelab seat card applies when operating on homelab, not to managing
the jail repository. Continue jail progress in this document.

User chose ChatGPT subscription authentication and full Codex permission bypass
inside Docker. Operational credentials are provisioned at runtime; do not copy
additional host secrets just to develop/test adapters. Use fixtures here and real
integration checks inside the jail. Do not call configuration proof of delivery.

## Host implementation delivered

- Shared image toolchain, UID/GID mapping, `/nix`, tini shutdown, and upload server.
  Default Docker target remains Claude; separate `codex` target pins Codex 0.155.1.
- `.dockerignore` restricts build context to required scripts, excluding secrets
  and sibling projects. Override CODEX_VERSION explicitly to test upgrades.
- `tools/codex-jail.sh` + `docker-compose.codex.yml`: standalone launcher,
  project/name validation, persistent CODEX_HOME, explicit runtime env file,
  loopback-only upload port, build/login/shell/arbitrary-command modes.
- `homelab-codex` alias: all Projects -> `/workspace`, cwd `/workspace/homelab`,
  state `.codex-jail/homelab-codex`, port 8022, existing `.env` provisioning.
- Host launcher supplies `--dangerously-bypass-approvals-and-sandbox` for Codex
  commands (including resume/exec). Manually typing codex in `--shell` does not
  go through that host argument rewrite.
- GitHub GH_TOKEN helper is container-local; mono mode mounts the existing jail
  `.claude-data.gitconfig` read-only if present.
- `--homelab-wallet` mounts wallet and management SSH directory read-only at
  matching `~/.claude` paths. Other in-jail regenerated credential caches persist
  in `.codex-jail/<name>/service-credentials`. It does not mount all Claude state.
- Before CLI startup, the mono homelab seat refreshes CLAUDE.local.md from
  agents/jail-seat-card.md; generated AGENTS.md merges CLAUDE.md then the local
  card. Atomic writes; local Git exclusion; no native/tracked AGENTS.md overwrite.
  Native AGENTS.md is used as-is with a notice, not a startup failure.
- Missing seat source or a hand-written CLAUDE.local.md fails clearly rather than
  using stale/overwritten context. Non-homelab projects get no homelab seat card.
- Small runtime facts card in CODEX_HOME/AGENTS.md, preserving user-owned global
  instructions. Existing AGENTS.override.md takes precedence as usual.
- Container-local ~/.agents/skills -> /workspace/homelab/.claude/skills when the
  source exists; preserves an existing user skills directory. Repo .agents untouched.

## Observed validation

- 4 launcher fixture tests: quoting/resume, env-file forwarding, mono paths,
  seat flag, wallet mounts/missing-file rejection, persistence, invalid inputs.
- 5 context fixture tests: fresh card/refresh, Git exclusion, native/tracked
  instruction preservation, custom global/local preservation, missing source,
  removal of stale generated context.
- Final pinned Docker image built successfully: codex-cli 0.155.1.
- Offline container acceptance test (`--network none`, temporary fixture mounts):
  fresh and updated seat card; global card; native AGENTS.md startup; skills link;
  mock Git credential lookup; logged-out auth status; state survival; HTTP upload
  server; graceful SIGTERM; preservation of command exit code 23.
- Shell syntax, Compose configuration, and git diff whitespace checks passed.
- Existing Claude target previously rebuilt/launched: Claude Code 2.1.278.
  Its entrypoint, compose and aliases' existing commands were not changed.
- Real wallet restoration script ran successfully; cache files already existed.
  Offline container checked wallet/keyfile readability and management SSH key
  validity without emitting secrets. No SSH connection or infrastructure apply.
- Current homelab CLAUDE.md + seat source total 28,436 bytes before small headers;
  monitor instruction-size limits as these sources grow.

Commands to repeat host checks:

```sh
python3 tools/test_codex_jail.py
python3 tools/test_codex_context.py
python3 tools/test_codex_container.py  # requires built image and Docker access
```

## Start the handoff session

The image is already rebuilt locally. Reload the alias and start a NEW container:

```sh
source ~/Projects/.aliases
homelab-codex
# If authentication is needed: homelab-codex --login
# Resume explicitly: homelab-codex -- codex resume --last
```

From inside, read `/workspace/CODEX-JAIL-HANDOFF.md`. The host has completed the
launcher/image/context work. Continue runtime integration in this jail repository
(`/workspace`); operate on homelab only when the relevant integration requires it.

## Remaining work — better done inside the jail

1. **Runtime acceptance:** confirm actual ChatGPT auth, create a small session,
   exit/restart/resume; confirm cwd/sibling visibility, expected instructions,
   `/skills` discovery, Devbox toolchain, Git identity and GitHub authentication.
   User reports demonstrate active use, but these end-to-end checks aren't yet
   recorded as passed. Inspect credential presence, never print values.
2. **Transcript synchronization:** inspect the existing runtime uploader and its
   destination/key naming, scheduling and wind-down contract. It is not implemented
   among this jail repository's tracked sources. Inspect a real native Codex
   transcript, build a format-specific adapter, test with sanitized fixtures, then
   verify a real object receipt/readback. Never upload CODEX_HOME wholesale (auth).
3. **Observability/accounting:** configure native Codex OTLP against the actual
   provisioned collector; observe received logs/metrics and jail/session identity.
   Reconcile Codex token/usage events with existing dashboards. Claude provider
   shim accounting is not automatically compatible. README has a config example,
   not an implemented or verified collector integration.
4. **Consumers and service connections:** audit Claude-specific skill/tool hooks,
   transcript retrospective readers, monitor/meta-events signals, and any extra
   credential caches. Implement only integrations that belong to standalone jail
   operation; don't import platform coordination to manage the build.
5. Record each result as fixture-tested, configured, or observed working. No real
   model call, transcript upload, collector delivery, live GitHub auth probe or
   management-box connection was made by this host build task.

## Git/worktree ownership

The original edits to tools/stack-jail.sh and tools/stack-jail-init.sh predate this
build and are excluded from the jail-build commit. Unrelated untracked directories
and files were left alone. No PR, push, deployment, watcher, or automation created.

## Codex stacks — 2026-09-20

Added stack-jail.sh --codex and oracle-codex, using the original scoped stack
provisioning. Codex state/auth is separate per stack (.codex-jail/stack-<name>);
Oracle upload port 8037, cwd /workspace/oracle-fleet. No mono wallet/auth or host
homelab mounts. The shared initializer supplies per-repo credentials and kubeconfig
before Codex startup; its rendered card is included in global context without
the Claude-specific shared tail. No homelab seat or skill symlink in Codex stacks.

4 additional launcher tests passed, including Claude regression and build without
provisioning. Rebuilt image passed both mono and stack offline container checks.
Stack fixture verified scoped Git (including rejection for an unrelated repo),
namespace kubeconfig, secret-free card, cwd, project context, and no homelab seat/
skill leakage. No real Oracle credentials, token mint, clone, GitHub call, or cluster
request used during validation. Live login and stack service access remain in-jail
checks. Read-only Oracle reference mounts that predate this work remain uncommitted.
