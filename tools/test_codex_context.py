"""Fixture checks for startup instruction generation; no live checkout writes."""

import importlib.util
import subprocess
import tempfile
import unittest
import unittest.mock
from pathlib import Path

spec = importlib.util.spec_from_file_location("context", Path(__file__).with_name("codex-context.py"))
context = importlib.util.module_from_spec(spec)
spec.loader.exec_module(context)


class ContextTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.project = self.root / "project"
        self.project.mkdir()
        self.home = self.root / "codex"
        self.home.mkdir()
        subprocess.run(["git", "init", "-q", str(self.project)], check=True)
        (self.project / "CLAUDE.md").write_text("Base facts")

    def boot(self, seat=False):
        context.bootstrap(self.project, self.home, seat)

    def test_fresh_seat_refresh_and_exclusion(self):
        (self.project / "agents").mkdir()
        source = self.project / "agents/jail-seat-card.md"
        source.write_text("Current procedure")
        self.boot(True)
        generated = self.project / "AGENTS.md"
        text = generated.read_text()
        self.assertLess(text.index("Base facts"), text.index("Current procedure"))
        source.write_text("Revised procedure")
        self.boot(True)
        self.assertIn("Revised procedure", generated.read_text())
        self.assertNotIn("Current procedure", generated.read_text())
        self.assertEqual(subprocess.run(["git", "-C", str(self.project), "check-ignore", "-q", "AGENTS.md"]).returncode, 0)
        self.assertEqual((self.project / ".git/info/exclude").read_text().count("/AGENTS.md"), 1)
        self.assertIn("Codex jail environment", (self.home / "AGENTS.md").read_text())

    def test_global_card_composes_jail_card_and_runtime_file(self):
        cards = self.root / "cards"
        (cards / "jail-card.d").mkdir(parents=True)
        (cards / "jail-card.md").write_text("Shared rule\n")
        (cards / "jail-card.d" / "codex.md").write_text("Codex rule\n")
        (cards / "jail-card.d" / "claude.md").write_text("Claude rule\n")
        stack = self.root / "stack-card.md"
        stack.write_text("Stack facts\n\n---\nClaude-composed tail\n")
        saved = context.CARD_DIRS, context.STACK_CARD
        context.CARD_DIRS, context.STACK_CARD = [self.root / "absent", cards], stack
        self.addCleanup(lambda: setattr(context, "CARD_DIRS", saved[0]) or setattr(context, "STACK_CARD", saved[1]))
        with unittest.mock.patch.dict("os.environ", {"STACK_NAME": "fixture"}):
            self.boot()
        text = (self.home / "AGENTS.md").read_text()
        order = [text.index(s) for s in ("Codex jail environment", "Stack facts", "Shared rule", "Codex rule")]
        self.assertEqual(order, sorted(order))
        self.assertNotIn("Claude rule", text)
        self.assertNotIn("Claude-composed tail", text)

    def test_native_and_tracked_instructions_preserved(self):
        target = self.project / "AGENTS.md"
        target.write_text("Native rules")
        self.boot()
        self.assertEqual(target.read_text(), "Native rules")
        target.write_text(context.MARKER + "\nTracked rules")
        subprocess.run(["git", "-C", str(self.project), "add", "AGENTS.md"], check=True)
        self.boot()
        self.assertIn("Tracked rules", target.read_text())

    def test_custom_global_and_local_cards_preserved(self):
        (self.home / "AGENTS.md").write_text("Personal rules")
        (self.project / "agents").mkdir()
        (self.project / "agents/jail-seat-card.md").write_text("Source")
        local = self.project / "CLAUDE.local.md"
        local.write_text("Hand-authored local card")
        with self.assertRaises(RuntimeError):
            self.boot(True)
        self.assertEqual(local.read_text(), "Hand-authored local card")
        self.assertEqual((self.home / "AGENTS.md").read_text(), "Personal rules")

    def test_missing_seat_fails_instead_of_using_stale_card(self):
        with self.assertRaises(RuntimeError):
            self.boot(True)

    def test_removed_sources_remove_stale_generated_file(self):
        self.boot()
        (self.project / "CLAUDE.md").unlink()
        self.boot()
        self.assertFalse((self.project / "AGENTS.md").exists())


if __name__ == "__main__":
    unittest.main()
