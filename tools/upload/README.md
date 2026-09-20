# upload — minimal file-drop server

Stdlib-only Python server for getting screenshots and documents into the jail.
Paste from the clipboard, drop files, or pick them from disk.

## Automatic startup

Both Claude and Codex entrypoints start the server on container port `8000` before
launching the main command. Files go to `$UPLOAD_DIR`, normally the project's
`uploads/` inbox. Logs go to `/tmp/upload-server.log`. Ensure the inbox is gitignored;
move files out when they should be committed.

The host port belongs to the launcher/alias, not the server. See the complete
[port table](../../README.md#upload-inbox-and-ports) in the main README. For example,
`homelab` uses [localhost:8002](http://localhost:8002), `homelab-go` uses
[localhost:8012](http://localhost:8012), and `homelab-codex` uses
[localhost:8022](http://localhost:8022). `idp-or` publishes no upload port.

The Claude OAuth callback is separate from uploads: `main`, or a stack session
launched with `--login`, publishes `54545`. Codex uses device login without a
callback port.

## Manual operation

The auto-started instance already owns `8000`. For a second server, choose another
container port and publish it when creating the container:

```bash
python3 /workspace/tools/upload/upload.py --dir /workspace/car-fleet/volvo-xc90-2006 --port 8100
```

That workspace script exists in mono jails; the Codex image also contains
`/opt/jail/upload.py`, which works in a project-only jail. Add an explicit Docker
port mapping such as `-p 127.0.0.1:8100:8100` to reach the second server from the
host. `docker compose port` only reports an existing mapping; it does not create one.

## API and exposure

- `POST /upload` with an `X-Filename` header saves the raw body into the inbox.
- Name collisions are renamed to `name-1.ext`, and so on.
- Pasted images receive a `paste-YYYYMMDD-HHMMSS.png` filename.
- No authentication or HTTPS. Codex publishes on host loopback; existing Claude
  aliases use Docker's unspecified host binding. Do not expose the UI publicly.

The server uses Python's `http.server` and standard library only; no pip packages
are required. `tini` forwards container stop signals to the runtime and upload
server together.
