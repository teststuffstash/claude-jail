"""Credential-free launcher contract tests: python3 tools/test_codex_jail.py."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class LauncherTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "tools").mkdir()
        shutil.copy(Path(__file__).with_name("codex-jail.sh"), self.root / "tools")
        self.project = self.root / "project with spaces"
        self.project.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        docker = self.bin / "docker"
        docker.write_text(
            '#!/usr/bin/env python3\nimport json,sys,os\nfrom pathlib import Path\nPath(os.environ["CAPTURE"]).write_text(json.dumps({k:v for k,v in os.environ.items() if k.startswith("JAIL_") or k == "CODEX_OTLP_BASE_ENDPOINT"}))\nprint(json.dumps(sys.argv[1:]))\n'
        )
        docker.chmod(0o755)
        self.env = dict(os.environ, CAPTURE=str(self.root / "captured.json"), PATH=f"{self.bin}:{os.environ['PATH']}")

    def run_jail(self, *args):
        return subprocess.run(
            ["bash", str(self.root / "tools/codex-jail.sh"), "--project", str(self.project), *args], env=self.env, text=True, capture_output=True
        )

    def test_resume_preserves_arguments_and_state(self):
        for _ in range(2):
            result = self.run_jail("--", "codex", "resume", "--last", "literal $(false)")
            self.assertEqual(result.returncode, 0, result.stderr)
            args = json.loads(result.stdout)
            self.assertEqual(args[-6:], ["codex", "codex", "--dangerously-bypass-approvals-and-sandbox", "resume", "--last", "literal $(false)"])
            self.assertIn("127.0.0.1:8021:8000", args)
            self.assertEqual(args[1:3], ["--env-file", "/dev/null"])
        state = self.root / ".codex-jail/main"
        self.assertEqual(state.stat().st_mode & 0o777, 0o700)

    def test_login_and_runtime_environment(self):
        runtime = self.root / "runtime.env"
        runtime.write_text("GH_TOKEN=fake-fixture\n")
        result = self.run_jail("--env-file", str(runtime), "--login")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout)
        self.assertEqual(args[-4:], ["codex", "--dangerously-bypass-approvals-and-sandbox", "login", "--device-auth"])
        self.assertIn("--env-from-file", args)
        self.assertNotIn("fake-fixture", result.stdout)

    def test_mono_mounts_and_wallet_contract(self):
        project = self.root / "homelab"
        project.mkdir()
        for file in ("homelab-keepass/homelab.kdbx", "homelab-keepass/homelab.keyx", "homelab-pve-ssh/id_ed25519"):
            target = self.root / ".claude-data" / file
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("dummy fixture")
        (self.root / ".claude-data.gitconfig").write_text("[user]\n name = Fixture\n")
        result = self.run_jail("--mono", "--project", str(project), "--homelab-wallet")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout)
        env = json.loads((self.root / "captured.json").read_text())
        self.assertEqual(env["JAIL_WORKDIR"], "/workspace/homelab")
        self.assertEqual(env["JAIL_MOUNT_SOURCE"], str(self.root))
        self.assertEqual(env["JAIL_MOUNT_TARGET"], "/workspace")
        self.assertEqual(env["JAIL_HOMELAB_SEAT"], "1")
        self.assertEqual(env["CODEX_OTLP_BASE_ENDPOINT"], "http://192.168.40.29:4318")
        self.assertIn(f"{self.root}/.claude-data/homelab-keepass:/home/node/.claude/homelab-keepass:ro", args)
        self.assertIn(f"{self.root}/.codex-jail/main/service-credentials:/home/node/.claude", args)
        (self.root / ".claude-data/homelab-keepass/homelab.keyx").unlink()
        self.assertEqual(self.run_jail("--mono", "--project", str(project), "--homelab-wallet").returncode, 2)

    def browser_script(self, exit_code):
        script = self.root / "tools/jail-browser.sh"
        script.write_text(f'#!/bin/sh\necho "jail-browser $*" >&2\nexit {exit_code}\n')
        script.chmod(0o755)

    def test_browser_url_only_when_sidecar_is_up(self):
        for exit_code, url in ((0, "http://jail-browser:8931/mcp"), (1, "")):
            self.browser_script(exit_code)
            result = self.run_jail()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("jail-browser up", result.stderr)
            env = json.loads((self.root / "captured.json").read_text())
            self.assertEqual(env["JAIL_BROWSER_MCP_URL"], url)
        self.assertIn("no browser tool", result.stderr)

    def test_no_sidecar_script_no_browser(self):
        self.assertEqual(self.run_jail().returncode, 0)
        self.assertEqual(json.loads((self.root / "captured.json").read_text())["JAIL_BROWSER_MCP_URL"], "")

    def test_rejects_bad_inputs_and_cross_project_resume(self):
        for args in [("--name", "../escape"), ("--port", "65536"), ("--port", "x"), ("--",)]:
            self.assertEqual(self.run_jail(*args).returncode, 2)
        self.assertEqual(self.run_jail().returncode, 0)
        other = self.root / "another-project"
        other.mkdir()
        self.assertEqual(self.run_jail("--project", str(other)).returncode, 2)


if __name__ == "__main__":
    unittest.main()
