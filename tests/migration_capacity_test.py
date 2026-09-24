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
    assert not (home / 'state').exists(), 'read-only inspection created migration state'
    prepared = subprocess.run(command[:-1] + ['prepare'], env=env, capture_output=True, text=True, timeout=180)
    assert prepared.returncode == 0, prepared.stderr
    journal_path = home / 'state/migration.json'
    journal = json.loads(journal_path.read_text())
    # Exercise receipt validation separately from runtime staging and file transfer.
    journal['phase'] = 'transferred'
    journal['transferredInventory'] = journal['sourceInventory']
    journal['transferredFullInventory'] = [
        {'path': 'agent', 'type': 'directory', 'mode': 448},
        {'path': 'sessions', 'type': 'directory', 'mode': 448},
        *[dict(item, path='agent/' + item['path']) for item in journal['sourceInventory']],
        *[{'path': f'sessions/existing-{index}', 'type': 'directory', 'mode': 448} for index in range(200000)],
    ]
    journal['verifiedInventory'] = journal['sourceInventory']
    journal['verifiedFullInventory'] = journal['transferredFullInventory']
    journal_path.write_text(json.dumps(journal))
    loaded = subprocess.run(command[:-1] + ['status'], env=env, capture_output=True, text=True, timeout=180)
    assert loaded.returncode == 0, loaded.stderr
    for field in ['transferredFullInventory', 'verifiedFullInventory']:
        full = journal[field]
        journal[field] = [*full, {'path': 'sessions/overflow', 'type': 'directory', 'mode': 448}]
        journal_path.write_text(json.dumps(journal))
        rejected_receipt = subprocess.run(command[:-1] + ['status'], env=env, capture_output=True, text=True, timeout=180)
        assert rejected_receipt.returncode != 0, field
        assert 'Malformed full' in rejected_receipt.stderr, rejected_receipt.stderr
        journal[field] = full
    journal_path.write_text(json.dumps(journal))
    (legacy / 'one-too-many').touch()
    rejected = subprocess.run(command, env=env, capture_output=True, text=True, timeout=180)
    assert rejected.returncode != 0
    assert f'Migration inventory exceeds {LIMIT} entries' in rejected.stderr
print('PASS source inventory limit 200000 and combined receipt limit 400002, with adjacent rejections')
