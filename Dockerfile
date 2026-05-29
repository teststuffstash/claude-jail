FROM node:22-bookworm

ARG HOST_UID=1000
ARG HOST_GID=1000

RUN apt-get update && \
    apt-get install -y --no-install-recommends zsh git jq curl gpg tini python3 sudo xz-utils && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# Remap the existing 'node' user/group to match the host UID/GID so files
# created in mounted volumes are owned by the host user. Also switch the
# login shell to zsh.
RUN usermod -u ${HOST_UID} -s /bin/zsh node && groupmod -g ${HOST_GID} node

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
ENV PATH="/nix/var/nix/profiles/default/bin:${PATH}"

ENV SHELL=/bin/zsh

COPY tools/jail-entrypoint.sh /usr/local/bin/jail-entrypoint.sh
RUN chmod +x /usr/local/bin/jail-entrypoint.sh

USER node
WORKDIR /workspace

# tini is PID 1: reaps the backgrounded upload server and forwards signals to
# the whole group (-g) so both claude and the server stop cleanly.
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/jail-entrypoint.sh"]
CMD ["claude"]
