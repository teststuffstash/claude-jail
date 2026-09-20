"""Offline stack initialization acceptance with fake credentials and a fixture clone."""
import os
from pathlib import Path
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix='codex-stack-smoke-') as temp:
    root = Path(temp)
    project = root / 'oracle-fleet'
    project.mkdir()
    subprocess.run(['git', 'init', '-q', str(project)], check=True)
    (project / 'CLAUDE.md').write_text('Oracle fixture facts')
    clone = root / 'homelab'
    clone.mkdir()
    (clone / 'CLAUDE.md').write_text('Public fixture context only')
    state = root / 'state'
    state.mkdir()
    verify = '''
import os, pathlib, subprocess
assert os.getcwd() == '/workspace/oracle-fleet'
card = pathlib.Path(os.environ['CODEX_HOME'], 'AGENTS.md').read_text()
assert 'oracle stack jail' in card and 'oracle-fleet oracle-iac' in card
assert 'fixture-pat' not in card and 'a.b.c' not in card
assert 'Oracle fixture facts' in pathlib.Path('AGENTS.md').read_text()
assert not pathlib.Path('/workspace/homelab/CLAUDE.local.md').exists()
assert not pathlib.Path('/home/node/.agents/skills').exists()
assert 'namespace: oracle-fleet' in pathlib.Path('/home/node/.kube/config').read_text()
assert os.environ['GH_TOKEN'] == 'fixture-pat'
assert 'STACK_PAT' not in os.environ and 'STACK_KUBE_TOKEN' not in os.environ
for repo, expected in [('oracle-fleet', 'fixture-pat'), ('homelab', 'fixture-homelab')]:
    result = subprocess.run(['git','credential','fill'], input=f'protocol=https\\nhost=github.com\\npath=teststuffstash/{repo}\\n\\n', text=True, capture_output=True, check=True)
    assert f'password={expected}' in result.stdout
result = subprocess.run(['git','credential','fill'], input='protocol=https\\nhost=github.com\\npath=teststuffstash/unrelated\\n\\n', env=dict(os.environ, GIT_TERMINAL_PROMPT='0'), text=True, capture_output=True)
assert result.returncode != 0
print('PASS: stack cwd, cards, secret-free context, scoped Git, kube config, no seat/skills leakage')
'''
    args = ['docker', 'run', '--rm', '--network', 'none', '--user', f'{os.getuid()}:{os.getgid()}']
    for source, target, readonly in [(project, '/workspace/oracle-fleet', False), (clone, '/workspace/homelab', True), (state, '/home/node/.codex', False), (Path(__file__).resolve().parent, '/workspace/tools', True)]:
        args += ['--mount', f'type=bind,source={source},target={target}' + (',readonly' if readonly else '')]
    for key, value in {'STACK_NAME':'oracle', 'STACK_MAIN_DIR':'/workspace/oracle-fleet', 'STACK_REPOS':'oracle-fleet oracle-iac', 'STACK_PAT':'fixture-pat', 'STACK_HOMELAB_TOKEN':'fixture-homelab', 'STACK_KUBE_TOKEN':'a.b.c', 'STACK_KUBE_SERVER':'https://fixture.invalid', 'STACK_KUBE_CA':'Zml4dHVyZQ==', 'STACK_KUBE_NS':'oracle-fleet', 'UPLOAD_DIR':'/workspace/oracle-fleet/uploads'}.items():
        args += ['-e', f'{key}={value}']
    subprocess.run([*args, 'codex-jail-codex', 'python3', '-c', verify], check=True)
