#!/usr/bin/env bash
# jail-browser — host-side verbs for the browser sidecar every jail on this host shares
# (docker-compose.yml service `browser`: headless Chromium + Playwright MCP, reachable only on
# the `jail-browser` docker network as http://jail-browser:8931/mcp).
#
#   tools/jail-browser.sh up       ensure the network exists, start (or update) the sidecar
#   tools/jail-browser.sh down     stop + remove the sidecar (the network stays)
#   tools/jail-browser.sh status   is it running, since when, healthy?
#   tools/jail-browser.sh logs     the MCP server's log (`logs -f` follows)
#   tools/jail-browser.sh pull     prefetch the pinned image (first launch otherwise pulls)
#
# `up` is what a launcher calls before starting a jail; the Claude compose services also
# `depends_on: browser`, so the aliases get it for free once the network exists (setup-env.sh
# creates it). The network is EXTERNAL to every compose project on purpose: both the Claude
# project (this file's directory) and a separately named Codex project can join it, which a
# project-owned network's labels would forbid.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
NET=jail-browser
CONTAINER=jail-browser
compose=(docker compose -f "$ROOT/docker-compose.yml")

ensure_net() {
  docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
}

case "${1:-}" in
  up)
    ensure_net
    "${compose[@]}" up -d --quiet-pull browser
    ;;
  down)
    "${compose[@]}" rm -sf browser
    ;;
  status)
    docker ps -a --filter "name=^${CONTAINER}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
    ;;
  logs)
    shift
    docker logs "$@" "$CONTAINER"
    ;;
  pull)
    "${compose[@]}" pull browser
    ;;
  *)
    sed -n '2,12p' "$0" >&2
    exit 2
    ;;
esac
