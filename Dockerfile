# Plain Debian, no Node: Claude Code and Codex are native binaries, and project tooling (node
# included) comes from each project's devbox.json. A session that needs a bare `node`/`npx`
# adds it with devbox (or `sudo apt-get install nodejs` for the session).
FROM debian:trixie AS jail-base
# pipefail: several RUNs pipe a download into its consumer (`curl | bash`, `curl | dd`);
# without it a failed download is masked by the consumer's exit 0 and the build "succeeds".
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG HOST_UID=1000
ARG HOST_GID=1000

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates git jq curl gpg tini python3 sudo xz-utils ipmitool procps && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# tea — the Forgejo/Gitea CLI, the Forgejo counterpart to gh. No apt repo exists
# for it, so we pin a release binary and verify its sha256. Kept here (baked into
# the image, jail-wide) alongside gh on purpose: both are forge CLIs, not
# per-project tooling. Bump TEA_VERSION + TEA_SHA256 together (checksums at
# https://dl.gitea.com/tea/<ver>/tea-<ver>-linux-amd64.sha256).
ARG TEA_VERSION=0.14.1
ARG TEA_SHA256=3cf7c5d1c20808c9ba2efb9ac125cee10d969daf398e653ea2b33cde201ea317
RUN curl -fsSL "https://dl.gitea.com/tea/${TEA_VERSION}/tea-${TEA_VERSION}-linux-amd64" -o /usr/local/bin/tea && \
    echo "${TEA_SHA256}  /usr/local/bin/tea" | sha256sum -c - && \
    chmod 0755 /usr/local/bin/tea

# The 'node' user, with the host UID/GID so files created in mounted volumes are owned by the
# host user. Login shell bash: the Bash tool and Codex run every command through it, and agents
# write bash (zsh's no-word-splitting caused real bugs; taken from the work variant, f028a0c).
# The NAME is history (the image used to be node:22, whose user this was): /home/node is in
# every mount target, launcher and saved permission rule, so it stays. A host GID Debian
# already uses (macOS staff = 20 = dialout) reuses that group.
RUN (getent group "${HOST_GID}" >/dev/null || groupadd -g "${HOST_GID}" node) && \
    useradd -l -u "${HOST_UID}" -g "${HOST_GID}" -m -s /bin/bash node

# Passwordless sudo for 'node' so software can be apt-installed mid-session.
RUN echo 'node ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/node && \
    chmod 0440 /etc/sudoers.d/node && \
    visudo -cf /etc/sudoers.d/node

# Devbox (Jetify): declarative, Nix-backed toolchain shared with the host. Only the
# devbox binary is baked in — packages resolve from the host's /nix store, which is
# bind-mounted at runtime (see docker-compose.yml). The same per-project devbox.json
# then works identically in the jail and on the host. Run `devbox install` on the host
# to populate the shared store; the jail consumes it via `devbox shell`.
RUN curl -fsSL https://get.jetify.com/devbox | bash -s -- -f && \
    chmod 0755 /usr/local/bin/devbox
# The install script ships a LAUNCHER that runs whatever devbox is latest that day — and every
# devbox release bakes its own plugin versions, which it rewrites into devbox.lock on ANY
# `devbox run` (nodejs plugin 0.0.4 up to 0.18.1, 0.0.5 from 0.18.2). An unpinned jail therefore
# dirties every project's lock the day upstream releases (homelab FU-240: the lock flip-flopped
# 0.0.4<->0.0.5 four times in a week). Pin the launcher to the SAME version the CI runner image
# bakes (homelab docker/arc-runner/Dockerfile ARG DEVBOX_VERSION) — CI's weekly `devbox update`
# is what writes the committed lock. Bump both in one change, with the lock.
ENV DEVBOX_USE_VERSION=0.18.3
ENV PATH="/nix/var/nix/profiles/default/bin:${PATH}"

# Nix multi-user build users. devbox's `print-dev-env` (run inside the jail) reads the
# host's bind-mounted /nix config, which sets build-users-group=nixbld; nix errors out
# unless that group exists *with members*. These users only satisfy that check — actual
# builds use the shared host store. Without this, `devbox run`/`devbox shell` fail in the jail.
RUN groupadd -r nixbld && \
    for i in 1 2 3 4; do \
      useradd -r -g nixbld -G nixbld -d /var/empty -s /usr/sbin/nologin -c "Nix build user $i" "nixbld$i"; \
    done

ENV SHELL=/bin/bash

COPY tools/jail-entrypoint.sh /usr/local/bin/jail-entrypoint.sh
RUN chmod +x /usr/local/bin/jail-entrypoint.sh

# Claude Code, native build, pinned to homelab's version-set STAMP (homelab#2014 shape (a)): the
# one version the worker (agent-base) and the coordinator/reviewer images bake too, so the three
# claude images agree and the drift belt (`VersionSetMembersDisagree` / `VersionSetBehindPin`,
# homelab argocd/resources/version-sets/) stays quiet. The stamp is read at BUILD time (the ADD
# fetches master's lock; Docker re-checks it on every build), so a host rebuild IS the seat's
# deploy edge — the belt only watches it. Never "latest": that is how the seat ran 2.1.301
# against a 2.1.293 stamp. Override for a one-off: --build-arg CLAUDE_CODE_VERSION=<x.y.z>.
# The installer takes the version, verifies the binary against that release's manifest and puts
# it under ~/.local, which is not a mount, so it lives in the image; the in-container
# auto-updater is off (it would move the seat off the stamp, into a container that loses it at
# exit). The download cache under ~/.claude is dropped — that path is a bind mount at runtime.
# The /usr/local/bin link keeps `claude` reachable from shells that reset PATH (login shells, sudo).
ARG CLAUDE_CODE_VERSION=""
ADD --chmod=644 https://raw.githubusercontent.com/teststuffstash/homelab/master/version-sets/devbox.lock /opt/version-sets.lock
USER node
RUN CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-$(jq -er '.packages | to_entries[] | select(.key | startswith("claude-code@")) | .value.version' /opt/version-sets.lock)}" && \
    test -n "$CLAUDE_CODE_VERSION" && \
    echo "version set: claude-code ${CLAUDE_CODE_VERSION}" && \
    curl -fsSL -o /tmp/claude-install.sh https://claude.ai/install.sh && \
    bash /tmp/claude-install.sh "$CLAUDE_CODE_VERSION" && \
    rm -rf /tmp/claude-install.sh /home/node/.claude && \
    /home/node/.local/bin/claude --version | grep -qF "$CLAUDE_CODE_VERSION"
USER root
RUN ln -s /home/node/.local/bin/claude /usr/local/bin/claude
ENV PATH="/home/node/.local/bin:${PATH}" \
    DISABLE_AUTOUPDATER=1

USER node
WORKDIR /workspace

# tini is PID 1: reaps the backgrounded upload server and forwards signals to
# the whole group (-g) so both claude and the server stop cleanly.
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/jail-entrypoint.sh"]
CMD ["claude"]

# Codex reuses the jail toolchain, with its own entrypoint and persistent state.
FROM jail-base AS codex
USER root
# Codex, native build: the release's full `codex-package` (what the npm package installs), not
# the bare `codex-<target>` binary — Codex spawns sibling helpers (`codex-code-mode-host` runs
# every tool call, `codex-exec-server`) and uses the bundled codex-path/ (rg) and
# codex-resources/ (bwrap). The bare binary alone fails every tool call with "failed to spawn
# code-mode host". Unpacked whole under /opt/codex; bin/* linked into /usr/local/bin.
# CODEX_VERSION=latest follows the newest release at build time; a version (0.169.0) pins it.
# ripgrep stays for interactive use (Codex brings its own).
ARG CODEX_VERSION=latest
RUN apt-get update && apt-get install -y --no-install-recommends ripgrep && rm -rf /var/lib/apt/lists/* && \
    asset="codex-package-$(uname -m)-unknown-linux-musl.tar.gz" && \
    if [ "${CODEX_VERSION}" = latest ]; then url="https://github.com/openai/codex/releases/latest/download/${asset}"; \
    else url="https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/${asset}"; fi && \
    curl -fsSL -o /tmp/codex.tar.gz "${url}" && \
    mkdir -p /opt/codex && tar -xzf /tmp/codex.tar.gz -C /opt/codex --no-same-owner && \
    rm -f /tmp/codex.tar.gz && \
    for b in /opt/codex/bin/*; do ln -sf "${b}" "/usr/local/bin/$(basename "${b}")"; done && \
    codex --version && test -x /usr/local/bin/codex-code-mode-host
COPY tools/codex-entrypoint.sh /usr/local/bin/codex-entrypoint.sh
COPY tools/codex-context.py /opt/jail/codex-context.py
COPY tools/mcp-register.py /opt/jail/mcp-register.py
COPY tools/codex-transcripts-sync.sh /opt/jail/codex-transcripts-sync.sh
COPY tools/upload/upload.py /opt/jail/upload.py
RUN chmod 0755 /usr/local/bin/codex-entrypoint.sh /opt/jail/codex-transcripts-sync.sh
USER node
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/codex-entrypoint.sh"]
CMD ["codex"]

# Preserve the default image used by existing Claude compose services.
FROM jail-base AS claude
