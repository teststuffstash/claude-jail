FROM node:22-bookworm

ARG HOST_UID=1000
ARG HOST_GID=1000

RUN apt-get update && \
    apt-get install -y --no-install-recommends zsh git jq && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# Remap the existing 'node' user/group to match the host UID/GID so files
# created in mounted volumes are owned by the host user. Also switch the
# login shell to zsh.
RUN usermod -u ${HOST_UID} -s /bin/zsh node && groupmod -g ${HOST_GID} node

ENV SHELL=/bin/zsh

USER node
WORKDIR /workspace

CMD ["claude"]
