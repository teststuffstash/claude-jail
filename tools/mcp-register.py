#!/usr/bin/env python3
"""Register an HTTP MCP server with a harness's user config, idempotently.

    mcp-register.py claude <~/.claude.json> <name> <url>
    mcp-register.py codex  <config.toml>    <name> <url>

Called by the jail entrypoints at container start with the browser sidecar's URL
(docker-compose.yml `browser`, JAIL_BROWSER_MCP_URL). Both targets are the harness's
OWN user-scope config — a bind-mounted file the harness also writes — so the rules are:
write in place (never rename: the mount is a single file), change only the one server
entry, never clobber a file that does not parse, and do nothing when the URL is empty.
A user-edited entry under the same name with a different URL is left alone and reported.
Exit status is 0 whenever the config is left in a valid state; the caller only warns.
"""
import json
import re
import sys


def register_claude(path, name, url):
    """~/.claude.json: top-level `mcpServers` is Claude Code's user scope ({"type": "http", "url"})."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        text = ""
    if text.strip():
        try:
            data = json.loads(text)
        except ValueError as e:
            print(f"mcp-register: {path} is not valid JSON ({e}); left untouched, {name} NOT registered", file=sys.stderr)
            return 0
        if not isinstance(data, dict):
            print(f"mcp-register: {path} is not a JSON object; left untouched, {name} NOT registered", file=sys.stderr)
            return 0
    else:
        data = {}
    servers = data.get("mcpServers")
    if servers is None:
        servers = data["mcpServers"] = {}
    if not isinstance(servers, dict):
        print(f"mcp-register: {path} mcpServers is not an object; left untouched, {name} NOT registered", file=sys.stderr)
        return 0
    existing = servers.get(name)
    if isinstance(existing, dict) and existing.get("url") == url and existing.get("type") in ("http", "streamable-http"):
        return 0
    if isinstance(existing, dict) and existing.get("url") not in (None, url):
        print(f"mcp-register: {path} already has {name} -> {existing.get('url')}; left as is", file=sys.stderr)
        return 0
    entry = dict(existing) if isinstance(existing, dict) else {}
    entry["type"] = "http"
    entry["url"] = url
    servers[name] = entry
    with open(path, "w", encoding="utf-8") as f:  # in place: the mount is a single file
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"mcp-register: {name} -> {url} ({path})", file=sys.stderr)
    return 0


def register_codex(path, name, url):
    """config.toml: `[mcp_servers.<name>]` with `url = ...` is Codex's streamable-HTTP server."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        text = ""
    header = re.compile(r"^\[mcp_servers\." + re.escape(name) + r"\]\s*$", re.M)
    m = header.search(text)
    if m:
        # Our own section: the url line directly inside it. Anything else is user-owned.
        body = text[m.end():]
        nxt = re.search(r"^\[", body, re.M)
        body = body[: nxt.start()] if nxt else body
        um = re.search(r'^\s*url\s*=\s*"([^"]*)"', body, re.M)
        if um and um.group(1) == url:
            return 0
        print(f"mcp-register: {path} already has [mcp_servers.{name}] -> {um.group(1) if um else '?'}; left as is", file=sys.stderr)
        return 0
    block = f'[mcp_servers.{name}]\nurl = "{url}"\n'
    new = text if not text or text.endswith("\n") else text + "\n"
    if new:
        new += "\n"
    new += block
    try:
        import tomllib  # 3.11+
        tomllib.loads(new)
    except ImportError:
        pass
    except Exception as e:  # noqa: BLE001 — any parse failure means: do not write
        print(f"mcp-register: {path} would not parse after adding {name} ({e}); left untouched", file=sys.stderr)
        return 0
    with open(path, "w", encoding="utf-8") as f:
        f.write(new)
    print(f"mcp-register: {name} -> {url} ({path})", file=sys.stderr)
    return 0


def main(argv):
    if len(argv) != 5 or argv[1] not in ("claude", "codex"):
        print(__doc__, file=sys.stderr)
        return 2
    harness, path, name, url = argv[1:]
    if not url:
        return 0
    if harness == "claude":
        return register_claude(path, name, url)
    return register_codex(path, name, url)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
