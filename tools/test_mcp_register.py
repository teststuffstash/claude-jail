"""Offline contract tests for tools/mcp-register.py: python3 tools/test_mcp_register.py"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest

SCRIPT = Path(__file__).with_name('mcp-register.py').resolve()
URL = 'http://jail-browser:8931/mcp'


def run(*args):
    return subprocess.run([sys.executable, str(SCRIPT), *args], text=True, capture_output=True)


class ClaudeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / '.claude.json'

    def test_registers_and_is_idempotent(self):
        self.path.write_text('{}')
        self.assertEqual(run('claude', str(self.path), 'browser', URL).returncode, 0)
        first = self.path.read_text()
        self.assertEqual(json.loads(first)['mcpServers']['browser'], {'type': 'http', 'url': URL})
        result = run('claude', str(self.path), 'browser', URL)
        self.assertEqual((result.returncode, result.stderr), (0, ''))
        self.assertEqual(self.path.read_text(), first)

    def test_preserves_other_state_and_entries(self):
        self.path.write_text(json.dumps({'hasCompletedOnboarding': True, 'projects': {'/w': {'allowedTools': []}},
                                         'mcpServers': {'other': {'type': 'stdio', 'command': 'x'}}}))
        run('claude', str(self.path), 'browser', URL)
        data = json.loads(self.path.read_text())
        self.assertTrue(data['hasCompletedOnboarding'])
        self.assertEqual(data['projects'], {'/w': {'allowedTools': []}})
        self.assertEqual(data['mcpServers']['other'], {'type': 'stdio', 'command': 'x'})
        self.assertEqual(data['mcpServers']['browser']['url'], URL)

    def test_empty_file_becomes_valid_json(self):
        self.path.write_text('')
        run('claude', str(self.path), 'browser', URL)
        self.assertEqual(json.loads(self.path.read_text())['mcpServers']['browser']['url'], URL)

    def test_invalid_json_is_left_alone(self):
        self.path.write_text('{not json')
        result = run('claude', str(self.path), 'browser', URL)
        self.assertEqual(result.returncode, 0)
        self.assertIn('NOT registered', result.stderr)
        self.assertEqual(self.path.read_text(), '{not json')

    def test_user_entry_with_other_url_is_kept(self):
        self.path.write_text(json.dumps({'mcpServers': {'browser': {'type': 'http', 'url': 'http://mine:1/mcp'}}}))
        result = run('claude', str(self.path), 'browser', URL)
        self.assertEqual(result.returncode, 0)
        self.assertIn('left as is', result.stderr)
        self.assertEqual(json.loads(self.path.read_text())['mcpServers']['browser']['url'], 'http://mine:1/mcp')

    def test_empty_url_is_a_noop(self):
        self.path.write_text('{}')
        self.assertEqual(run('claude', str(self.path), 'browser', '').returncode, 0)
        self.assertEqual(self.path.read_text(), '{}')


class CodexTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'config.toml'

    def test_appends_to_seeded_config_and_is_idempotent(self):
        seed = 'forced_login_method = "chatgpt"\ncli_auth_credentials_store = "file"\n'
        self.path.write_text(seed)
        self.assertEqual(run('codex', str(self.path), 'browser', URL).returncode, 0)
        first = self.path.read_text()
        self.assertTrue(first.startswith(seed))
        self.assertEqual(tomllib.loads(first)['mcp_servers']['browser'], {'url': URL})
        self.assertEqual(tomllib.loads(first)['forced_login_method'], 'chatgpt')
        result = run('codex', str(self.path), 'browser', URL)
        self.assertEqual((result.returncode, result.stderr), (0, ''))
        self.assertEqual(self.path.read_text(), first)

    def test_missing_file_is_created(self):
        run('codex', str(self.path), 'browser', URL)
        self.assertEqual(tomllib.loads(self.path.read_text())['mcp_servers']['browser']['url'], URL)

    def test_user_section_with_other_url_is_kept(self):
        text = '[mcp_servers.browser]\nurl = "http://mine:1/mcp"\nstartup_timeout_sec = 30\n'
        self.path.write_text(text)
        result = run('codex', str(self.path), 'browser', URL)
        self.assertEqual(result.returncode, 0)
        self.assertIn('left as is', result.stderr)
        self.assertEqual(self.path.read_text(), text)

    def test_other_sections_untouched(self):
        text = '[mcp_servers.other]\ncommand = "x"\n\n[otel]\nlog_user_prompt = false\n'
        self.path.write_text(text)
        run('codex', str(self.path), 'browser', URL)
        data = tomllib.loads(self.path.read_text())
        self.assertEqual(data['mcp_servers']['other'], {'command': 'x'})
        self.assertEqual(data['mcp_servers']['browser'], {'url': URL})
        self.assertFalse(data['otel']['log_user_prompt'])


class UsageTest(unittest.TestCase):
    def test_bad_harness(self):
        self.assertEqual(run('vim', '/dev/null', 'browser', URL).returncode, 2)


if __name__ == '__main__':
    unittest.main()
