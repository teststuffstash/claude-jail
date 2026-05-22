#!/usr/bin/env python3
"""Minimal upload server. Stdlib only. Paste from clipboard, drag-drop, or pick files.

Usage:
    python3 upload.py --dir /path/to/target [--port 8000] [--host 0.0.0.0]
"""
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Upload — {dir_html}</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ font: 14px/1.4 system-ui, sans-serif; margin: 2rem auto; max-width: 760px; padding: 0 1rem; }}
  h1 {{ font-size: 1.1rem; margin: 0 0 .5rem; }}
  .dir {{ font-family: ui-monospace, monospace; color: #888; word-break: break-all; }}
  #drop {{ border: 2px dashed #888; border-radius: 8px; padding: 3rem 1rem; text-align: center; margin: 1.5rem 0; cursor: pointer; }}
  #drop.over {{ border-color: #2a7; background: rgba(42,170,68,.08); }}
  #drop p {{ margin: .25rem 0; }}
  #drop input {{ display: none; }}
  #log {{ margin: 0; padding: 0; list-style: none; font-family: ui-monospace, monospace; font-size: 12px; }}
  #log li {{ padding: .25rem .5rem; border-bottom: 1px solid #4443; display: flex; gap: 1rem; }}
  #log li.err {{ color: #c33; }}
  #log .name {{ flex: 1; word-break: break-all; }}
  #log .size {{ color: #888; }}
  kbd {{ background: #8884; padding: .1em .3em; border-radius: 3px; font-family: ui-monospace, monospace; }}
</style>
</head>
<body>
<h1>Upload to <span class="dir">{dir_html}</span></h1>
<div id="drop" tabindex="0">
  <p><strong>Paste</strong> (<kbd>Ctrl/Cmd+V</kbd>), <strong>drop files</strong>, or <strong>click to pick</strong>.</p>
  <p style="color:#888;font-size:12px">Images from clipboard saved as <code>paste-YYYYMMDD-HHMMSS.png</code></p>
  <input id="pick" type="file" multiple>
</div>
<h2 style="font-size:.9rem;margin:1.5rem 0 .5rem;color:#888">Uploaded this session</h2>
<ul id="log"></ul>
<script>
const drop = document.getElementById('drop');
const pick = document.getElementById('pick');
const log  = document.getElementById('log');

function ts() {{
  const d = new Date();
  const p = n => String(n).padStart(2,'0');
  return `${{d.getFullYear()}}${{p(d.getMonth()+1)}}${{p(d.getDate())}}-${{p(d.getHours())}}${{p(d.getMinutes())}}${{p(d.getSeconds())}}`;
}}

function fmtSize(b) {{
  if (b < 1024) return b + ' B';
  if (b < 1024*1024) return (b/1024).toFixed(1) + ' KB';
  return (b/1024/1024).toFixed(2) + ' MB';
}}

async function upload(blob, name) {{
  const li = document.createElement('li');
  li.innerHTML = `<span class="name">${{name}}</span><span class="size">…</span>`;
  log.prepend(li);
  try {{
    const r = await fetch('/upload', {{
      method: 'POST',
      headers: {{ 'X-Filename': encodeURIComponent(name) }},
      body: blob,
    }});
    const j = await r.json();
    if (!j.ok) throw new Error(j.error || 'upload failed');
    li.querySelector('.name').textContent = j.name;
    li.querySelector('.size').textContent = fmtSize(j.size);
  }} catch (e) {{
    li.classList.add('err');
    li.querySelector('.size').textContent = e.message;
  }}
}}

drop.addEventListener('click', () => pick.click());
drop.addEventListener('keydown', e => {{ if (e.key === 'Enter' || e.key === ' ') pick.click(); }});
pick.addEventListener('change', () => {{
  for (const f of pick.files) upload(f, f.name);
  pick.value = '';
}});

['dragenter','dragover'].forEach(ev => drop.addEventListener(ev, e => {{ e.preventDefault(); drop.classList.add('over'); }}));
['dragleave','drop'].forEach(ev => drop.addEventListener(ev, e => {{ e.preventDefault(); drop.classList.remove('over'); }}));
drop.addEventListener('drop', e => {{
  for (const f of e.dataTransfer.files) upload(f, f.name);
}});

document.addEventListener('paste', e => {{
  let handled = false;
  for (const item of e.clipboardData.items) {{
    if (item.kind === 'file') {{
      const blob = item.getAsFile();
      if (!blob) continue;
      const ext = (blob.type.split('/')[1] || 'bin').replace(/[^a-z0-9]/gi,'');
      const name = blob.name && blob.name !== 'image.png' ? blob.name : `paste-${{ts()}}.${{ext}}`;
      upload(blob, name);
      handled = true;
    }}
  }}
  if (handled) e.preventDefault();
}});
</script>
</body>
</html>
"""


def safe_name(name: str) -> str:
    name = name.strip().replace("\\", "/").split("/")[-1]
    name = re.sub(r"[^\w.\- ]+", "_", name)
    return name or "upload.bin"


def unique_path(target: Path) -> Path:
    if not target.exists():
        return target
    stem, suffix, i = target.stem, target.suffix, 1
    while True:
        candidate = target.with_name(f"{stem}-{i}{suffix}")
        if not candidate.exists():
            return candidate
        i += 1


def make_handler(target_dir: Path):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            sys.stderr.write(f"{self.address_string()} - {fmt % args}\n")

        def _json(self, status: int, body: dict) -> None:
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):  # noqa: N802
            if self.path == "/" or self.path == "/index.html":
                body = PAGE.format(dir_html=html.escape(str(target_dir))).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            self.send_error(404)

        def do_POST(self):  # noqa: N802
            if self.path != "/upload":
                self.send_error(404)
                return
            raw_name = self.headers.get("X-Filename", "")
            try:
                from urllib.parse import unquote
                raw_name = unquote(raw_name)
            except Exception:
                pass
            name = safe_name(raw_name) if raw_name else f"upload-{dt.datetime.now():%Y%m%d-%H%M%S}.bin"
            target = unique_path(target_dir / name)
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0:
                self._json(400, {"ok": False, "error": "empty body"})
                return
            try:
                with open(target, "wb") as f:
                    remaining = length
                    while remaining > 0:
                        chunk = self.rfile.read(min(65536, remaining))
                        if not chunk:
                            break
                        f.write(chunk)
                        remaining -= len(chunk)
            except OSError as e:
                self._json(500, {"ok": False, "error": str(e)})
                return
            self._json(200, {"ok": True, "name": target.name, "path": str(target), "size": length})

    return Handler


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", required=True, type=Path, help="Target directory for uploads")
    ap.add_argument("--port", type=int, default=8000, help="Port (default: 8000)")
    ap.add_argument("--host", default="0.0.0.0", help="Bind host (default: 0.0.0.0)")
    args = ap.parse_args()

    target_dir = args.dir.resolve()
    target_dir.mkdir(parents=True, exist_ok=True)

    httpd = ThreadingHTTPServer((args.host, args.port), make_handler(target_dir))
    print(f"Upload server: http://localhost:{args.port}  →  {target_dir}", file=sys.stderr)
    print("Ctrl-C to stop.", file=sys.stderr)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
