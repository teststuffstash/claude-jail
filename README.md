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
shell-history and jail Git-identity files, and **rewrites**
`docker-compose.override.yml` for the host's available zsh dotfiles. Its generator
currently writes only the `claude` service, even if your previous override also
contained a `stack` entry.

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
```

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

[docker-compose.codex.yml](docker-compose.codex.yml) is standalone and does not
load the Claude Compose override. Config is seeded once with ChatGPT-only login
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

Zsh dotfiles/history mounts are optional Claude override configuration. The aliases
use explicit `-f docker-compose.yml`, so they do not automatically load
`docker-compose.override.yml`; include both files explicitly if you want those
mounts. Codex does not currently persist zsh history or mount host shell dotfiles.

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
| `homelab-go` | 8012 | — |
| `sleep-tracking-or` | 8015 | — |
| `openrouter-operator` | 8016 | — |
| `oracle` | 8017 | With `--login` |
| `sleep-jail` | 8018 | With `--login` |
| `platform-jail` | 8019 | With `--login` |
| `circles` | 8020 | With `--login` |
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

Codex transcript upload to Garage, collector receipt, usage/accounting dashboards,
monitor events and Claude transcript consumers still need runtime integration and
verification. The tracked jail source has no transcript uploader to reuse directly.
Current build evidence and the inside-jail checklist live in
[CODEX-JAIL-HANDOFF.md](CODEX-JAIL-HANDOFF.md).

The existing attended cross-jail file-drop protocol is described in
[tools/handoff.md](tools/handoff.md). Claude's `/handoff` and `/loop` commands are not
automatically implemented in Codex just because the shared directories are visible.

## Updates and validation

Restart containers for mount, environment or startup-card changes. Reload `.aliases`
after editing shortcuts. Rebuild when changing Dockerfile **or files copied into the
image**, including entrypoints, Codex context generation and its baked upload server.
Claude's upload script is read from the workspace mount. Re-running `setup-env.sh`
rewrites the generated override; review local customizations first.

```bash
python3 tools/test_codex_jail.py
python3 tools/test_codex_context.py
# After building the codex-jail-codex image; temporary fixtures, network disabled:
python3 tools/test_codex_container.py
```

The host build was validated with Codex 0.155.1 and Claude 2.1.278. These checks
cover launcher contracts, startup context, mock Git credentials, skills links,
persistence, uploads and shutdown. Real login/resume and service integrations
remain the inside-jail acceptance work; they are not implied by the offline tests.
