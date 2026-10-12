#!/usr/bin/env python3
"""Fixture tests for the native Codex transcript sync adapter."""
from __future__ import annotations

import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/codex-transcripts-sync.sh"


def write_executable(path: pathlib.Path, body: str) -> None:
    path.write_text(body)
    path.chmod(0o755)


with tempfile.TemporaryDirectory() as raw:
    tmp = pathlib.Path(raw)
    sessions = tmp / "sessions/2026/09/21"
    sessions.mkdir(parents=True)
    (sessions / "rollout-fixture.jsonl").write_text('{"type":"session_meta"}\n')
    (sessions / "ignore.txt").write_text("not a transcript\n")
    bin_dir = tmp / "bin"
    bin_dir.mkdir()
    aws_log = tmp / "aws.log"
    write_executable(
        bin_dir / "aws",
        '#!/bin/sh\nprintf "%s\\n" "$*" > "$AWS_LOG"\n'
        'printf "upload: fixture to target\\n"\n',
    )
    write_executable(bin_dir / "curl", "#!/bin/sh\nexit 0\n")
    env = dict(
        os.environ,
        PATH=f"{bin_dir}:{os.environ['PATH']}",
        AWS=str(bin_dir / "aws"),
        AWS_LOG=str(aws_log),
        AWS_ACCESS_KEY_ID="fixture-id",
        AWS_SECRET_ACCESS_KEY="fixture-secret",
        CODEX_TRANSCRIPTS_SRC=str(tmp / "sessions"),
        JAIL_NAME="homelab-codex",
        GARAGE_S3_ENDPOINT="https://fixture.invalid",
    )
    result = subprocess.run(
        ["bash", str(SCRIPT)], env=env, text=True, capture_output=True, check=True
    )
    invocation = aws_log.read_text()
    assert "s3 sync" in invocation
    assert "s3://jail-transcripts/codex/homelab-codex/sessions" in invocation
    assert "--exclude * --include *.jsonl" in invocation
    assert "done — 1 file(s) uploaded" in result.stdout

    env["JAIL_NAME"] = "../../escape"
    invalid = subprocess.run(
        ["bash", str(SCRIPT)], env=env, text=True, capture_output=True, check=True
    )
    assert "SKIPPED: invalid jail name" in invalid.stdout

print("codex transcript sync fixtures: PASS")
