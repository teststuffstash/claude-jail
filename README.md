# claude-jail — Docker jails for coding agents

Host-side Docker harness for **Claude Code** and **native Codex**, with persistent
runtime state, host-owned workspace files, shared Devbox/Nix tooling, and a file-drop
upload inbox. Claude Code can also use the existing OpenRouter and OpenCode Go
project wrappers.

This checkout is itself `~/Projects`: other project repositories live beneath it.
The jail is a standalone repository; the homelab agent platform does not manage
its development lifecycle.

## Choose a session

Load the shortcuts with `source ~/Projects/.aliases`.

| Session | Runtime / provider route | Workspace |
|---|---|---|
| `main`, `homelab`, other project aliases | Claude Code, native Anthropic login | All Projects mounted; project aliases select a working directory |
| `sleep-tracking-or` | Claude Code through the project's OpenRouter wrapper | Same mono-jail mounts |
| `homelab-go` | Claude Code with a local model-routing shim for OpenCode Go/Zen | Same mono-jail mounts |
| `oracle`, `sleep-jail`, `platform-jail`, `circles` | Claude Code with stack-scoped provisioning | Selected repositories and read-only extras |
| `oracle-codex` | Native Codex with stack-scoped provisioning | Same Oracle repository/credential scope as `oracle` |
| `homelab-codex` | Native Codex, ChatGPT subscription login | All Projects mounted; working directory `/workspace/homelab` |
| `tools/codex-jail.sh --project DIR` | Native Codex | Selected project only, unless `--mono` is supplied |

The aliases and launchers are the source of truth for paths and ports. Provider
wrappers are described under [Alternative Claude provider routes](#alternative-claude-provider-routes).

## Shared container and host setup

The image uses `node:22-bookworm`. The non-root `node` user is remapped to the host
UID/GID so workspace writes retain host ownership. Passwordless sudo allows
container package installation; those installs disappear when the container is
removed. Put persistent image tools in [Dockerfile](Dockerfile), and use each
project's Devbox configuration for project tools.

The host supplies Docker with Compose, the Projects checkout, and the shared
`/nix` store. Codex's runtime env-file option requires Compose support for
`docker compose run --env-from-file`. The image includes Claude Code, git, gh,
tea, Python, zsh, sudo, and Devbox; the Codex target adds Codex **0.155.1**.
`.dockerignore` excludes sibling repositories and secrets from the image context.

Docker is the jail boundary. Mono sessions can read/write all mounted Projects
files; container sudo can also modify those host files. Claude stack launches
explicitly bypass Claude permission prompts. Claude mono launchers use the saved
Claude settings; Codex's launcher explicitly passes
`--dangerously-bypass-approvals-and-sandbox`, including for resume/exec commands.

### Prepare the existing host setup

```bash
cd ~/Projects
./setup-env.sh
source .aliases
```

`setup-env.sh` writes HOST_UID/HOST_GID into `.env`, creates missing Claude JSON,
shell-history and jail Git-identity files, and creates the `jail-browser` docker network.
There is no compose override file: every launcher passes `-f docker-compose.yml`, so
compose would never load one — timezone and terminal settings live in
`docker-compose.yml` itself.

The Claude services expect `.claude-data/.credentials.json` to exist as a **file**
for their shared login mount. The setup script does not create it; check this when
setting up a fresh host so Docker does not create a directory at that path.
Codex uses its own state directory and has no dependency on Claude login.

## Claude Code

### Build, launch, and log in

```bash
cd ~/Projects
docker compose build
main
# In Claude Code: /login
```

`main` publishes the Claude OAuth callback port `54545`. Authentication state is
shared through `.claude-data/.credentials.json`; subsequent mono and stack sessions
reuse it. A stack launcher also supports `--login` to publish the callback port,
provided another container is not already using it.

```bash
homelab       # working directory /workspace/homelab; all Projects visible
car-fleet
oracle        # scoped stack jail
oracle --login
oracle --second   # a second oracle jail beside the running one (homelab's second-jail rules)
```

`<stack> --second` launches a separate container for the same stack: its own credential
mints and OTLP identity `<stack>-stack-2`, sharing `.claude-data-<stack>/`. It publishes no
port (no upload UI, no `--login`), so any number of them can run at once.
The stack repos are the same host checkouts the primary works in, so its session card carries
homelab's `second-jail` skill (`.claude/skills/second-jail/SKILL.md`): work in a clone, PR lane
only, no shared records.

The default/final Docker target remains Claude. [docker-compose.yml](docker-compose.yml)
defines the `claude` mono service and the generic `stack` service. Use
[tools/stack-jail.sh](tools/stack-jail.sh) for stack sessions, not a direct
`docker compose run stack`.

The stack launcher derives repository membership from homelab's
`agents/stacks.json`, adds the jail-owned mount/port overlay, loads `.env.<stack>`,
and attempts to mint a bounded Kubernetes ServiceAccount token through host Devbox.
Its initializer creates per-repository Git credentials and a shallow homelab clone;
the host homelab checkout is not mounted into stack jails. Persistent Claude state
is separate per stack, while the Claude subscription credential file is shared.

### Alternative Claude provider routes

These are **Claude Code wrappers**, not separate agent runtimes or Codex provider
configurations. They depend on scripts and configuration in the mounted project
checkouts; the jail repository owns the launch aliases.

| Route | Launcher and dependencies | Behavior |
|---|---|---|
| OpenRouter | `sleep-tracking-or` → `sleep-tracking/claude-or`; project `.openrouter.env` | Sets Claude's API base URL to OpenRouter and uses the configured provider token/model overrides |
| OpenCode Go/Zen | `homelab-go` → `homelab/scripts/claude-go.sh` and `claude-model-shim.py`; optional `.opencode-go.env` | By default retains the native subscription for the main loop and routes subagent model slots through the shim |

The Go wrapper reads `opencode-go-api-key` from the KeePass wallet unless
`SHIM_GO_KEY` is supplied. Its `SLOT_HAIKU`, `SLOT_SONNET`, and `SLOT_OPUS` settings
control slot routing; `CLAUDE_GO_ALL=1` also routes the main model. Refer to the
wrapper and homelab's model-routing documentation for current model choices and
provider compatibility rather than duplicating a changing model/price list here.

`.aliases` also contains `idp-or`, but **`idp/claude-or` is absent in this host
checkout as of 2026-09-20**. That alias needs its project wrapper restored before
use. It publishes no upload port. Native Codex currently uses the configured
ChatGPT login path; neither of these Claude wrappers is wired into it.

## Native Codex

### Homelab mono session

```bash
source ~/Projects/.aliases
homelab-codex --build
homelab-codex --login
homelab-codex
# Later:
homelab-codex -- codex resume --last
```

Login uses ChatGPT device authentication; enable device-code login in your account
if required and follow the URL/code printed by Codex. No callback port or host
Codex-auth copy is used. See [official authentication documentation](https://learn.chatgpt.com/docs/auth).

The homelab alias selects `--mono`, loads `~/Projects/.env`, and enables
`--homelab-wallet`. Projects is mounted at `/workspace`, the working directory is
`/workspace/homelab`, and uploads are published on loopback port **8022**.

### Codex stack sessions

```bash
source ~/Projects/.aliases
oracle-codex --build
oracle-codex --login
oracle-codex
oracle-codex -- resume --last
# Other existing stacks use the same runtime selector:
tools/stack-jail.sh sleep --codex
```

`oracle-codex` runs in `/workspace/oracle-fleet`, publishes uploads at
`http://127.0.0.1:8037`, and persists its independent ChatGPT login and sessions in
`.codex-jail/stack-oracle`. It uses `.env.oracle`, the existing per-repository Git
credential routing, bounded Kubernetes token provisioning, scoped project mounts,
read-only extras, and per-stack handoff directory. It does not mount all Projects,
the host homelab checkout, the mono wallet, or either runtime's mono auth state.

The Codex stack service uses the same Codex image, with the shared stack initializer
running before Codex startup. Its rendered stack card is included in Codex's global
instructions; the selected project's Claude files are merged normally. No homelab
seat card or global homelab skill symlink is installed. Native repository
`.agents/skills` remain available through Codex's normal discovery.

`--login` uses device authentication, so no Claude callback port is needed.
Arguments after `--` are Codex arguments (unlike the standalone launcher, do not
repeat `codex`). Codex stack upload ports are the Claude stack ports plus 20:
Oracle 8037, sleep 8038, platform 8039, circles 8040. `--build` only builds the image
and does not mint operational credentials. Actual launches retain the existing
stack provisioning behavior, including its warning-and-continue path if the
Kubernetes token cannot be minted.

### Other projects and launch options

```bash
tools/codex-jail.sh --project /path/to/repo --name my-repo --build
tools/codex-jail.sh --project /path/to/repo --name my-repo --login
tools/codex-jail.sh --project /path/to/repo --name my-repo
```

| Option | Effect |
|---|---|
| `--project DIR` | Mount the project at `/workspace/<basename>` and work there; defaults to the invoking directory |
| `--name NAME` | Persistent state namespace; defaults to `main`; reusing a name for a different project is rejected |
| `--mono` | Mount the jail repository/Projects at `/workspace`; the selected project must be within it |
| `--port PORT` | Host loopback upload port; default 8021 |
| `--env-file FILE` | Explicit runtime environment; other invocations do not automatically load Claude's `.env` |
| `--homelab-wallet` | Mount the existing wallet and management SSH cache and persist other regenerated service files |
| `--shell` | Open zsh; Codex commands manually typed there do not receive the host launcher's bypass flag |
| `-- COMMAND…` | Forward a command and its arguments to the container |

[docker-compose.codex.yml](docker-compose.codex.yml) is standalone. Config is seeded once with ChatGPT-only login
and file credential storage. Model selection retains the CLI default. Set
`CODEX_VERSION` when building to deliberately override the pinned CLI version.

## Persistent state and credentials

| Host path under Projects | Container path | Scope |
|---|---|---|
| `.claude-data/` | `~/.claude/` | Claude mono settings, sessions, auth and service caches |
| `.claude-data.json` | `~/.claude.json` | Claude mono onboarding state |
| `.claude-data-<stack>/` and matching `.json` | `~/.claude/`, `~/.claude.json` | Per-stack Claude state |
| `.codex-jail/<name>/` | `~/.codex/` | Codex auth, configuration and sessions; created mode 0700 |
| `.codex-jail/<name>/service-credentials/` | `~/.claude/` | Codex with `--homelab-wallet`: regenerated service caches |
| `.claude-data/homelab-keepass/` | `~/.claude/homelab-keepass/` | Read-only overlay in wallet-enabled Codex sessions |
| `.claude-data/homelab-pve-ssh/` | `~/.claude/homelab-pve-ssh/` | Read-only management SSH-key overlay in wallet-enabled Codex sessions |
| `.claude-data.gitconfig` | `~/.gitconfig` | Jail Git identity: mono Claude and, when present, mono Codex; stack initializer copies a base mount |

The Claude service mounts `.env` variables through Compose; `homelab-codex`
explicitly loads that same file. `GH_TOKEN` supplies `gh` authentication and an
ephemeral Git credential helper. Configure the existing org-scoped token for the
repositories and operations needed; broad administration rights are not a baseline
requirement of the jail. Host `~/.gitconfig` is not mounted.

The wallet is canonical; file caches can be regenerated. If the launcher reports
missing management-key files, use the existing host procedure:

```bash
CLAUDE_CRED_DIR=~/Projects/.claude-data bash ~/Projects/homelab/scripts/wallet-files.sh
```

The wallet option checks for the database, keyfile and management SSH key before
launching. It does not mount every Claude service cache. Other files regenerated
inside wallet-enabled Codex sessions persist in the separate cache directory above.
Never commit runtime state or export the entire Codex home as a transcript archive:
it contains authentication data.

Forgejo git (mono Claude jail only): when homelab's `wallet-files.sh` has written
`.claude-data/homelab-forgejo/`, the entrypoint writes a container-local `~/.ssh/config`
entry for `forgejo.teststuff.net` (that key, host key pinned in
[tools/forgejo_known_hosts](tools/forgejo_known_hosts)), imports the GPG key, and signs
commits and tags in any repository with a Forgejo remote via `includeIf hasconfig` in a
container-local `GIT_CONFIG_GLOBAL` that includes the mounted `~/.gitconfig`. GitHub
repositories stay unsigned. Stack jails get none of this: the key reaches every personal
Forgejo repository, so a stack needing one gets a per-repository deploy key.

Claude jails persist zsh history (mono: `.claude-data.zsh_history`; stack:
`.claude-data-<stack>.zsh_history`) but mount no host shell dotfiles (plain zsh, no `.zshrc`).
Codex does not currently persist zsh history.

## Startup instructions and skills

Claude mono startup composes the shared [jail card](tools/jail-card.md) into
`/workspace/CLAUDE.local.md`, and homelab's `agents/jail-seat-card.md` into that
checkout's local card. Stack startup prepends a stack environment card and does
not install the homelab seat procedure.

Codex startup creates a small environment card in `$CODEX_HOME/AGENTS.md`, preserving
any user-owned file there. For the mono homelab seat, it refreshes `CLAUDE.local.md`
from the seat source first. Then it merges the selected project's `CLAUDE.md` and
`CLAUDE.local.md`, in that order, into a generated `AGENTS.md`, locally ignored via
`.git/info/exclude`. Missing seat sources or hand-written local cards stop the
refresh; native/tracked `AGENTS.md` files are preserved and used as-is.
`AGENTS.override.md` still takes precedence, and instruction-size limits apply.

When homelab skills are mounted, startup links container-local `~/.agents/skills`
to `/workspace/homelab/.claude/skills`, preserving any existing user skills directory.
The repository's `.agents` directory is untouched. This exposes skill definitions;
Claude-specific commands, hooks and tool assumptions still need Codex equivalents.

## Upload inbox and ports

Both entrypoints start the stdlib Python upload server on container port **8000**;
`tini` forwards stop signals to the runtime and server. Uploads land in the selected
project's `uploads/` inbox. Ensure that inbox is gitignored; move files out when they
belong in a commit. Logs are at `/tmp/upload-server.log`. See
[the upload README](tools/upload/README.md) for the API and manual operation.

| Alias | Host upload port | Claude OAuth callback |
|---|---|---|
| `main` | 8000 | 54545 |
| `car-fleet` | 8001 | — |
| `homelab` | 8002 | — |
| `life` | 8003 | — |
| `idp` | 8004 | — |
| `sleep-tracking` | 8005 | — |
| `snore-recorder` | 8006 | — |
| `teststuff` | 8007 | — |
| `games` | 8008 | — |
| `homelab-go` | 8012 | — |
| `sleep-tracking-or` | 8015 | — |
| `openrouter-operator` | 8016 | — |
| `oracle` | 8017 | With `--login` |
| `sleep-jail` | 8018 | With `--login` |
| `platform-jail` | 8019 | With `--login` |
| `circles` | 8020 | With `--login` |
| `oracle-codex` | 8037 | Device login; no callback port |
| `homelab-codex` | 8022 | Device login; no callback port |

Open `http://localhost:<port>`. A generic Codex launch defaults to **8021**.
Codex binds the published port to `127.0.0.1`; existing Claude aliases use Docker's
unspecified host binding. The upload server has no authentication or HTTPS, so
restrict host exposure accordingly. `idp-or` publishes no upload port.

## Integrations and current limits

Claude Compose supplies per-jail `OTEL_RESOURCE_ATTRIBUTES`; export configuration
and downstream services are separate runtime setup. Native Codex OTLP must be
configured in its own `config.toml`; see [official telemetry configuration](https://learn.chatgpt.com/docs/config-file/config-advanced).
A collector configuration alone does not establish successful delivery.

The `homelab-codex` launcher supplies native Codex's OTLP/HTTP log and metrics
exporters with the LAN collector at `http://192.168.40.29:4318`, tags the OTel
environment with the jail name, and leaves raw prompt export disabled. Generic
Codex project jails remain disconnected unless `CODEX_OTLP_BASE_ENDPOINT` is set.
Log receipt was verified in Loki on 2026-09-21, including redacted prompt content
and response token fields. Native metrics did not appear at the collector's
Prometheus exporter, so metrics delivery and dashboard reconciliation remain open.

The homelab Codex seat synchronizes native transcripts at startup (catch-up) and
normal wind-down. It can also be invoked explicitly during a long session:

```bash
bash /workspace/tools/codex-transcripts-sync.sh
```

The adapter uploads only `$CODEX_HOME/sessions/**/*.jsonl` to
`jail-transcripts/codex/<jail-name>/sessions/…`, preserving Codex's date partitions.
It obtains the existing bucket writer credential at run time from the homelab cluster
unless AWS credentials are already supplied. Like the Claude adapter, failures are
loud but best-effort so loss of Garage cannot prevent jail repair work. Automatic
scheduling is intentionally limited to the homelab seat; other mono projects and
scoped stack jails are not silently added to the sensitive archive. Real Garage
receipt/readback was verified from the homelab Codex jail on 2026-09-21. Never upload
`CODEX_HOME` wholesale: it holds `auth.json`.

Still open for Codex: native metrics delivery (above) and dashboard/usage
reconciliation; Claude-specific consumers — skill/tool hooks, transcript retrospective
readers, monitor/meta-event signals — have not been audited for Codex equivalents.
Implement only what standalone jail operation needs; platform coordination stays in
homelab.

The existing attended cross-jail file-drop protocol is described in
[tools/handoff.md](tools/handoff.md). Claude's `/handoff` and `/loop` commands are not
automatically implemented in Codex just because the shared directories are visible.

## Browser sidecar

Every jail has a browser without any jail image carrying one. The compose service `browser`
runs the upstream Playwright MCP image (`mcr.microsoft.com/playwright/mcp`, headless Chromium
+ the MCP server in one container) once per host, on the external docker network
`jail-browser`, with no published port — only containers on that network reach it, at
`http://jail-browser:8931/mcp`. The jail entrypoint registers that URL as the user-scope
`browser` MCP server in the jail's `~/.claude.json` (`tools/mcp-register.py`, idempotent),
so Claude Code sees `mcp__browser__*` tools in every session. Each MCP session gets a fresh
in-memory browser context; nothing persists between sessions. Design + the alternatives
weighed (bake into the Dockerfile, an in-cluster browser): claude-jail#5.

The Claude compose services `depends_on: browser` (with `required: false`, compose ≥ 2.20:
a sidecar that cannot start costs the session its browser, not the session), so a `docker
compose run` from any alias starts the sidecar if it is not running and leaves it running afterwards (no restart policy:
after a host reboot the next jail launch brings it back). `setup-env.sh` creates the network;
the first launch pulls the image (or prefetch it). Host-side verbs:

```bash
tools/jail-browser.sh up       # ensure network + start/update the sidecar (what the launchers call)
tools/jail-browser.sh status   # running since when, healthy?
tools/jail-browser.sh logs -f  # the MCP server's log
tools/jail-browser.sh down     # stop + remove it (next launch restarts it)
tools/jail-browser.sh pull     # prefetch the pinned image
```

The sidecar is hardened like a credential sidecar would be: read-only root, no capabilities,
no mounts, tmpfs for the profile and output, memory and pid caps. It has exactly the host's
egress — nothing a jail's own `curl` lacks — and `--allowed-origins`/`--blocked-origins` would
be politeness, not a boundary. Page content reaching the agent is untrusted input (the jail
card says so). Bump the image tag in `docker-compose.yml` by hand; this repo has no Renovate.
Offline tests: `python3 tools/test_mcp_register.py`.

Codex jails (mono and stack) use the same sidecar. Their compose project (`-p codex-jail`)
joins the external network, and their launchers run `tools/jail-browser.sh up` first and
pass `JAIL_BROWSER_MCP_URL` only when it succeeded. The Codex entrypoint registers it as
`[mcp_servers.browser] url = …` in the persistent `config.toml` (`tools/mcp-register.py
codex`, baked into the image), so a Codex session sees the same `browser` tools.

## Updates and validation

Restart containers for mount, environment or startup-card changes. Reload `.aliases`
after editing shortcuts. Rebuild when changing Dockerfile **or files copied into the
image**, including entrypoints, Codex context generation and its baked upload server.
Claude's upload script is read from the workspace mount. Re-running `setup-env.sh`
is safe; it also creates the `jail-browser` network a fresh host needs before the first
launch.

```bash
devbox run ci      # lint + every offline test (tools/test_*.py except the container ones)
devbox run lint    # shellcheck, hadolint, gitleaks (history + uncommitted), ruff check/format
devbox run fix     # the mechanical part: import order + ruff format
# After building the codex-jail-codex image; temporary fixtures, network disabled:
python3 tools/test_codex_container.py
python3 tools/test_codex_stack_container.py
```

`devbox.json` pins the lint tools; `tools/ci.sh` runs them over `git ls-files` only,
never a directory walk — the repo root is `~/Projects`, and a walk would lint and
secret-scan every sibling project. For the same reason the ruff config lives in
`tools/ruff.toml`, not the root. Run `devbox run ci` before pushing: this repo is
public, there is no CI workflow, and owner pushes to `master` bypass the PR rule.

The host build was validated with Codex 0.155.1 and Claude 2.1.278. These checks
cover launcher contracts, startup context, mock Git credentials, skills links,
persistence, uploads and shutdown; they do not imply live behavior. Inside-jail
acceptance was observed on 2026-09-21: ChatGPT auth, a real `codex exec`, native
transcript creation, cwd/sibling visibility, instructions, skills link, homelab Devbox
tools, Git identity and GitHub auth, and resuming the same session ID in a container
from a rebuilt image. The homelab seat's generated `AGENTS.md` (homelab `CLAUDE.md` +
seat card) was ~28 KB then; watch instruction-size limits as those sources grow.
