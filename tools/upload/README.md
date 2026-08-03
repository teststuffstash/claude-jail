# upload — minimal file-drop server

Stdlib-only Python server for getting screenshots and documents from your host into the jail's filesystem. Paste from clipboard, drop files, or pick from disk.

## Run

The server **starts automatically** with every jail session — `tini` (PID 1, set in the `Dockerfile`) launches it in the background via `tools/jail-entrypoint.sh` before handing the terminal to `claude`. It serves on container port `8000`, dropping files into `$UPLOAD_DIR` — each project's gitignored `uploads/` inbox (set per project in `.aliases`). Move files out of `uploads/` to commit them. Logs go to `/tmp/upload-server.log` inside the container.

Just open the host port for your session and paste (Ctrl/Cmd+V), drop, or click:

- main (`~/Projects`) → <http://localhost:8000>
- car-fleet → <http://localhost:8001>
- homelab → <http://localhost:8002>
- life → <http://localhost:8003>

To run it manually against a different folder, note the auto-started instance already holds `8000` — give the manual one another port (only `8000` is forwarded to the host, so reach others via `docker compose port` or by adding them to `ports:`):

```bash
python3 /workspace/tools/upload/upload.py --dir /workspace/car-fleet/volvo-xc90-2006 --port 8100
```

### Ports & multiple sessions

- The container always serves on `8000`. Each alias in `.aliases` publishes its own **host** port with `-p host:8000`, so several sessions can run at once without colliding. `docker-compose.yml` declares no `ports:`.
- Only the **main** jail (run from `~/Projects`) also maps `-p 54545:54545`, so it's the only one that can complete `/login` — the callback URL is fixed to `localhost:54545`. The project jails don't publish it. Log in once via `main`; the token persists in `.claude-data/` and works in every session.
- To add or change a port, edit the `-p` flag in that alias (and re-source `.aliases`).

## What it does

- `POST /upload` with `X-Filename` header → saves raw body to `<dir>/<filename>`. Name collisions auto-rename to `name-1.ext`.
- Pasted images get auto-named `paste-YYYYMMDD-HHMMSS.png`.
- No auth, no HTTPS. Local jail tool only — do **not** expose to the internet.

## Why stdlib

The container has no pip and runs as a non-root user. `http.server` + a tiny request handler avoids the install dance entirely.
