"""Stack launcher fixture tests; never mint real credentials or contact services."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("stack-jail.sh").resolve()


class StackTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.root = self.home / "Projects"
        (self.root / "homelab/agents").mkdir(parents=True)
        (self.root / "homelab/agents/stacks.json").write_text(json.dumps({"stacks": [{"name": "oracle", "repos": ["oracle-fleet", "oracle-iac"]}]}))
        (self.root / ".env.oracle").write_text("ORACLE_PAT=fixture\n")
        self.bin = self.home / "bin"
        self.bin.mkdir()
        for name, content in {
            "docker": "#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n",
            "devbox": '#!/bin/sh\ncase "$*" in *create*) echo a.b.c;; *server*) echo https://fixture.invalid;; *) echo Zml4dHVyZQ==;; esac\n',
        }.items():
            path = self.bin / name
            path.write_text(content)
            path.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:{os.environ['PATH']}")

    def run_stack(self, *args):
        return subprocess.run(["bash", str(SCRIPT), "oracle", *args], env=self.env, text=True, capture_output=True)

    def test_codex_mount_boundary_and_resume(self):
        result = self.run_stack("--codex", "--", "resume", "--last")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout.splitlines()[-1])
        self.assertIn("127.0.0.1:8037:8000", args)
        self.assertIn(f"{self.root}/.codex-jail/stack-oracle:/home/node/.codex", args)
        self.assertIn(f"{self.root}/teststuff:/workspace/teststuff:ro", args)
        self.assertNotIn(f"{self.root}:/workspace", args)
        self.assertNotIn(f"{self.root}/homelab:/workspace/homelab", args)
        self.assertNotIn("homelab-keepass", result.stdout)
        self.assertFalse((self.root / ".claude-data-oracle.json").exists())
        self.assertEqual(args[-4:], ["codex", "--dangerously-bypass-approvals-and-sandbox", "resume", "--last"])

    def test_codex_login_independent_of_claude_auth(self):
        result = self.run_stack("--codex", "--login")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout.splitlines()[-1])
        self.assertEqual(args[-3:], ["codex", "login", "--device-auth"])
        self.assertNotIn("54545:54545", args)

    def test_claude_still_uses_original_launch(self):
        (self.root / ".claude-data").mkdir()
        (self.root / ".claude-data/.credentials.json").write_text("{}")
        result = self.run_stack("--login")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout.splitlines()[-1])
        self.assertIn("8017:8000", args)
        self.assertIn("54545:54545", args)
        self.assertIn("exec claude --dangerously-skip-permissions", args[-1])

    def test_build_does_not_provision(self):
        result = self.run_stack("--codex", "--build")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)[-2:], ["build", "codex-stack"])
        self.assertFalse((self.root / ".codex-jail").exists())


if __name__ == "__main__":
    unittest.main()
