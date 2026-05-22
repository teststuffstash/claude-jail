#!/bin/sh
# Run as PID 1 by tini. Launches the upload server in the background, then
# hands the terminal off to the main command (claude). tini reaps the
# background server and forwards signals to the whole process group on stop.
set -e

# Upload server: always binds container port 8000. The host-side port is
# decided by docker-compose (per-project, see UPLOAD_PORT in .aliases).
# UPLOAD_DIR picks the target folder for dropped files.
python3 /workspace/tools/upload/upload.py \
  --dir "${UPLOAD_DIR:-/workspace}" \
  --port 8000 \
  --host 0.0.0.0 \
  >/tmp/upload-server.log 2>&1 &

exec "$@"
