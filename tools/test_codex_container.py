"""Docker smoke test; mounts only temporary fixtures, never credentials/projects.

Build codex-jail-codex first, then: python3 tools/test_codex_container.py
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile


def docker(*args, check=True):
    return subprocess.run(['docker', *args], check=check, text=True, capture_output=True)


with tempfile.TemporaryDirectory(prefix='codex-jail-smoke-') as directory:
    root = Path(directory)
    state = root / 'state'
    state.mkdir(mode=0o700)
    project = root / 'project'
    project.mkdir()
    subprocess.run(['git', 'init', '-q', str(project)], check=True)
    (project / 'CLAUDE.md').write_text('fixture repository facts')
    (project / 'agents').mkdir()
    (project / 'agents/jail-seat-card.md').write_text('fixture current seat card')
    (project / '.claude/skills/fixture').mkdir(parents=True)
    (project / '.claude/skills/fixture/SKILL.md').write_text('---\nname: fixture\ndescription: Fixture only\n---\n')
    args = ['--workdir', '/workspace/homelab', '-e', 'JAIL_HOMELAB_SEAT=1',
            '-e', 'GH_TOKEN=fixture-token-not-real', '--network', 'none', '--user', f'{os.getuid()}:{os.getgid()}',
            '-e', 'CODEX_HOME=/home/node/.codex',
            '-e', 'UPLOAD_DIR=/workspace/homelab/uploads',
            '--mount', f'type=bind,src={state},dst=/home/node/.codex',
            '--mount', f'type=bind,src={project},dst=/workspace/homelab']
    image = 'codex-jail-codex'
    print(docker('run', '--rm', *args, image, 'codex', '--version').stdout.strip())
    assert 'forced_login_method = "chatgpt"' in (state / 'config.toml').read_text()
    assert 'fixture current seat card' in (project / 'AGENTS.md').read_text()
    assert 'Codex jail environment' in (state / 'AGENTS.md').read_text()
    (project / 'agents/jail-seat-card.md').write_text('fixture refreshed seat card')
    # No real auth; this must report logged out without reaching the network.
    status = docker('run', '--rm', *args, image, 'codex', 'login', 'status', check=False)
    assert status.returncode == 1, (status.stdout, status.stderr)
    assert 'not logged in' in (status.stdout + status.stderr).lower()
    assert 'fixture refreshed seat card' in (project / 'AGENTS.md').read_text()
    (state / 'sentinel').write_text('persistent')
    container = docker('run', '-d', *args, image, 'sh', '-c',
                       'trap "exit 0" TERM; while :; do sleep 1; done').stdout.strip()
    try:
        assert docker('exec', container, 'cat', '/home/node/.codex/sentinel').stdout == 'persistent'
        assert docker('exec', container, 'readlink', '/home/node/.agents/skills').stdout.strip() == '/workspace/homelab/.claude/skills'
        # Retry only to allow the Python upload server to finish starting.
        docker('exec', container, 'python3', '-c', '''
import time, urllib.request
for attempt in range(30):
    try:
        assert urllib.request.urlopen('http://127.0.0.1:8000', timeout=1).status == 200
        break
    except OSError:
        time.sleep(.1)
else:
    raise RuntimeError('upload server did not start')
''')
        docker('stop', '-t', '5', container)
        info = json.loads(docker('inspect', container).stdout)[0]
        assert info['State']['ExitCode'] == 0, info['State']
    finally:
        docker('rm', '-f', container, check=False)
    credential_check = docker('run', '--rm', *args, image, 'python3', '-c', '''
import subprocess
r = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\\nhost=github.com\\n\\n', text=True, capture_output=True, check=True)
assert 'password=fixture-token-not-real' in r.stdout
print('Git credential fixture passed')
''')
    print(credential_check.stdout.strip())
    (project / 'AGENTS.md').write_text('native fixture instructions')
    result = docker('run', '--rm', *args, image, 'sh', '-c', 'exit 23', check=False)
    assert result.returncode == 23, result
    assert (project / 'AGENTS.md').read_text() == 'native fixture instructions'
    print('PASS: refreshed cards, native instructions, skills link, credential helper; fresh auth config, logged-out status, persistent state, upload HTTP, SIGTERM, exit status')
