#!/usr/bin/env python3
"""Exercise the migration inventory bound with real, empty cache files."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 200_000

with tempfile.TemporaryDirectory(prefix='migration-capacity-') as temporary:
    home = Path(temporary).resolve() / 'home'
    legacy = home / '.pi/agent'
    legacy.mkdir(parents=True)
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
               BOOTSTRAP_LEGACY_PI_ROOT=str(legacy), BOOTSTRAP_LEGACY_GH_ROOT=str(home / '.config/gh'),
               BOOTSTRAP_PRIVATE_ROOT=str(home / 'private'), BOOTSTRAP_STATE_ROOT=str(home / 'state'),
               DOTFILES_BARE_ROOT=str(home / 'tools'))
    for key in ['NVIM_CONFIG_CHECKOUT_DIR', 'NVIM_CONFIG_REPO_URL']:
        env.pop(key, None)
    for index in range(LIMIT):
        (legacy / f'cache-{index:06d}').touch()
    command = ['node', str(ROOT / 'scripts/migration-helper.mjs'), 'inspect']
    accepted = subprocess.run(command, env=env, capture_output=True, text=True, timeout=180)
    assert accepted.returncode == 0, accepted.stderr
    report = json.loads(accepted.stdout)
    assert report['sourceEntries'] == LIMIT
    assert report['ready'] is True, report['conflicts']
    (legacy / 'one-too-many').touch()
    rejected = subprocess.run(command, env=env, capture_output=True, text=True, timeout=180)
    assert rejected.returncode != 0
    assert f'Migration inventory exceeds {LIMIT} entries' in rejected.stderr
    assert not (home / 'state').exists(), 'read-only inspection created migration state'
print('PASS migration accepts 200000 entries and rejects 200001 without creating state')
