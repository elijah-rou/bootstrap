#!/usr/bin/env python3
"""Bundled Neovim ownership, migration and writable-state contracts."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def environment(root: Path) -> tuple[Path, dict[str, str]]:
    home = root / 'home'
    home.mkdir()
    guard = root / 'guard'
    guard.mkdir()
    for name in ['git', 'curl', 'wget', 'sudo', 'systemctl', 'nvim', 'npm', 'bun']:
        path = guard / name
        _ = path.write_text('#!/bin/sh\necho forbidden >> "$HOME/forbidden"\nexit 99\n')
        path.chmod(0o755)
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
               XDG_DATA_HOME=str(home / '.local/share'), XDG_STATE_HOME=str(home / '.local/state'),
               PATH=str(guard) + os.pathsep + os.environ['PATH'])
    _ = env.pop('NVIM_CONFIG_REPO_URL', None)
    _ = env.pop('NVIM_CONFIG_CHECKOUT_DIR', None)
    return home, env


def configure(env: dict[str, str], *arguments: str, source: Path = ROOT, success: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(['bash', str(source / arguments[0]), *arguments[1:]], env=env,
                            text=True, capture_output=True, timeout=15)
    assert (result.returncode == 0) == success, result.stdout + result.stderr
    assert not (Path(env['HOME']) / 'forbidden').exists(), result.stdout + result.stderr
    return result


def test_fresh_retry_and_profile_switch() -> None:
    with tempfile.TemporaryDirectory(prefix='bundled-nvim-') as temporary:
        home, env = environment(Path(temporary).resolve())
        runtime = home / '.local/share/bootstrap/neovim'
        target = home / '.config/nvim'
        _ = configure(env, 'configure.sh', 'neovim')
        assert target.resolve() == runtime
        assert (runtime / 'init.lua').resolve() == ROOT / 'neovim/config/init.lua'
        assert json.loads((runtime / 'bootstrap-profile.json').read_text()) == {'version': 1, 'profile': 'workstation'}
        for name in ['lazy-lock.json', 'lazyvim.json', '.neoconf.json']:
            assert (runtime / name).is_file()
            assert not (runtime / name).is_symlink()
            assert (runtime / name).read_bytes() == (ROOT / 'neovim/defaults' / name).read_bytes()
        for _ in range(2):
            _ = configure(env, 'configure.sh', 'neovim')
        assert not list(home.rglob('*.bak.*'))
        _ = configure(env, 'install.sh', 'link')
        assert json.loads((runtime / 'bootstrap-profile.json').read_text())['profile'] == 'bare'
        _ = configure(env, 'install.sh', 'neovim')
        assert json.loads((runtime / 'bootstrap-profile.json').read_text())['profile'] == 'workstation'
        assert not (runtime / '.git').exists()
    return


def test_legacy_migration_and_source_upgrade_preserve_local_state() -> None:
    with tempfile.TemporaryDirectory(prefix='bundled-nvim-migrate-') as temporary:
        root = Path(temporary).resolve()
        home, env = environment(root)
        old = home / '.local/share/elijahrou/lazyvim-config'
        (old / 'lua/config').mkdir(parents=True)
        _ = (old / 'init.lua').write_text('local original = true\n')
        _ = (old / 'lua/config/custom.lua').write_text('uncommitted user code\n')
        for name in ['lazy-lock.json', 'lazyvim.json', '.neoconf.json']:
            _ = (old / name).write_text(json.dumps({'local': name}) + '\n')
        before = {p.relative_to(old): p.read_bytes() for p in old.rglob('*') if p.is_file()}
        target = home / '.config/nvim'
        target.parent.mkdir(parents=True)
        target.symlink_to(old)
        _ = configure(env, 'configure.sh', 'neovim')
        runtime = target.resolve()
        for name in ['lazy-lock.json', 'lazyvim.json', '.neoconf.json']:
            assert (runtime / name).read_bytes() == (old / name).read_bytes()
        backups = list(target.parent.glob('nvim.bak.*'))
        assert len(backups) == 1 and backups[0].readlink() == old
        assert {p.relative_to(old): p.read_bytes() for p in old.rglob('*') if p.is_file()} == before
        _ = (runtime / 'lazy-lock.json').write_text('{"updated-locally":true}\n')
        next_source = root / 'next-source'
        _ = shutil.copytree(ROOT, next_source, ignore=shutil.ignore_patterns('.git', '__pycache__', 'node_modules'))
        _ = configure(env, 'configure.sh', 'neovim', source=next_source)
        assert (runtime / 'init.lua').resolve() == next_source / 'neovim/config/init.lua'
        assert (runtime / 'lazy-lock.json').read_text() == '{"updated-locally":true}\n'
        assert {p.relative_to(old): p.read_bytes() for p in old.rglob('*') if p.is_file()} == before
        assert list(target.parent.glob('nvim.bak.*')) == backups
    return


def test_foreign_runtime_and_invalid_profiles_are_preserved() -> None:
    invalid: list[object] = [None, [], {}, {'version': True, 'profile': 'bare'}, {'version': 1.0, 'profile': 'bare'},
               {'version': 1.5, 'profile': 'bare'}, {'version': 2, 'profile': 'bare'},
               {'version': 1, 'profile': 'unknown'}, {'version': 1, 'profile': None},
               {'version': 1, 'profile': 'bare', 'extra': True}]
    with tempfile.TemporaryDirectory(prefix='bundled-nvim-invalid-') as temporary:
        home, env = environment(Path(temporary).resolve())
        runtime = home / '.local/share/bootstrap/neovim'
        runtime.mkdir(parents=True)
        keep = runtime / 'keep'
        _ = keep.write_text('unowned')
        _ = configure(env, 'configure.sh', 'neovim', success=False)
        marker = runtime / 'bootstrap-profile.json'
        env['PYTHONOPTIMIZE'] = '1'
        for value in invalid:
            _ = marker.write_text(json.dumps(value))
            _ = configure(env, 'configure.sh', 'neovim', success=False)
            assert json.loads(marker.read_text()) == value
            assert keep.read_text() == 'unowned'
            assert not (home / '.config/nvim').exists()
        marker.unlink()
        elsewhere = runtime.parent / 'elsewhere'
        _ = elsewhere.write_text('{"version":1,"profile":"bare"}')
        marker.symlink_to(elsewhere)
        _ = configure(env, 'configure.sh', 'neovim', success=False)
        assert marker.is_symlink()
    return


def test_lock_and_partial_initialization_recovery() -> None:
    with tempfile.TemporaryDirectory(prefix='bundled-nvim-lock-') as temporary:
        home, env = environment(Path(temporary).resolve())
        runtime = home / '.local/share/bootstrap/neovim'
        lock = runtime.with_name('neovim.install.lock')
        lock.mkdir(parents=True)
        _ = configure(env, 'configure.sh', 'neovim', success=False)
        assert lock.is_dir() and not runtime.exists()
        lock.rmdir()
        old = home / '.config/nvim'
        old.mkdir(parents=True)
        _ = (old / 'lazyvim.json').write_text('{invalid')
        _ = configure(env, 'configure.sh', 'neovim', success=False)
        assert not runtime.exists()
        assert not lock.exists()
        assert not list(runtime.parent.glob('.neovim-stage.*'))
        assert (old / 'lazyvim.json').read_text() == '{invalid'
        _ = (old / 'lazyvim.json').write_text('{"extras":[]}\n')
        _ = configure(env, 'configure.sh', 'neovim')
        assert old.is_symlink() and old.resolve() == runtime
        assert (runtime / 'lazyvim.json').read_text() == '{"extras":[]}\n'
        (runtime / 'lazy-lock.json').unlink()
        _ = configure(env, 'configure.sh', 'neovim')
        assert (runtime / 'lazy-lock.json').is_file()
    return


def test_failed_activation_can_retry_without_losing_legacy_state() -> None:
    with tempfile.TemporaryDirectory(prefix='bundled-nvim-activation-') as temporary:
        root = Path(temporary).resolve()
        home, env = environment(root)
        target = home / '.config/nvim'
        target.mkdir(parents=True)
        _ = (target / 'init.lua').write_text('keep original')
        _ = (target / 'lazy-lock.json').write_text('{"local-lock":true}\n')
        original_ln = shutil.which('ln')
        assert original_ln is not None
        guard_ln = root / 'guard/ln'
        _ = guard_ln.write_text('#!/bin/bash\nif [[ "${!#}" == "$HOME/.config/nvim" ]]; then exit 29; fi\nexec ' + original_ln + ' "$@"\n')
        guard_ln.chmod(0o755)
        _ = configure(env, 'configure.sh', 'neovim', success=False)
        assert (target / 'init.lua').read_text() == 'keep original'
        assert (target / 'lazy-lock.json').read_text() == '{"local-lock":true}\n'
        runtime = home / '.local/share/bootstrap/neovim'
        assert (runtime / 'bootstrap-profile.json').is_file()
        assert not runtime.with_name('neovim.install.lock').exists()
        guard_ln.unlink()
        _ = (target / 'lazy-lock.json').write_text('{"edited-after-failure":true}\n')
        _ = configure(env, 'configure.sh', 'neovim')
        assert target.resolve() == runtime
        assert (runtime / 'lazy-lock.json').read_text() == '{"edited-after-failure":true}\n'
        backups = list(target.parent.glob('nvim.bak.*'))
        assert len(backups) == 1 and (backups[0] / 'init.lua').read_text() == 'keep original'
    return


def test_bare_doctor_rejects_workstation_profile() -> None:
    with tempfile.TemporaryDirectory(prefix='bundled-nvim-doctor-') as temporary:
        home, env = environment(Path(temporary).resolve())
        _ = configure(env, 'configure.sh', 'neovim')
        activation = home / '.config/dotfiles/bare-env.sh'
        activation.parent.mkdir(parents=True)
        _ = activation.write_text('export DOTFILES_BARE_ROOT="$HOME/fake-bare"\n')
        bare = home / 'fake-bare'
        (bare / 'bin').mkdir(parents=True)
        (bare / 'env/conda-meta').mkdir(parents=True)
        _ = (bare / 'bin/micromamba').write_text('#!/bin/sh\nexit 0\n')
        (bare / 'bin/micromamba').chmod(0o755)
        probe = '''source "$1/install.sh"
for tool in git delta gh ssh zsh tmux nvim rg fzf bat eza jq node bun herdr; do
    eval "$tool() { :; }"
done
pi() { printf '%s\\n' "$PI_CLI_VERSION"; }
check_pi_subagents_revision() { :; }
bare_doctor
'''
        result = subprocess.run(['bash', '-c', probe, '_', str(ROOT)], env=env, text=True, capture_output=True)
        assert result.returncode != 0, result.stdout + result.stderr
        assert 'Bundled Neovim profile' in result.stdout + result.stderr
        switch = subprocess.run(['bash', '-c', 'source "$1/install.sh"; BOOTSTRAP_WORKSTATION=0 setup_neovim_config', '_', str(ROOT)],
                                env=env, text=True, capture_output=True)
        assert switch.returncode == 0, switch.stdout + switch.stderr
        result = subprocess.run(['bash', '-c', probe, '_', str(ROOT)], env=env, text=True, capture_output=True)
        assert result.returncode == 0, result.stdout + result.stderr
    return


if __name__ == '__main__':
    for check in [test_fresh_retry_and_profile_switch, test_legacy_migration_and_source_upgrade_preserve_local_state,
                  test_foreign_runtime_and_invalid_profiles_are_preserved, test_lock_and_partial_initialization_recovery,
                  test_failed_activation_can_retry_without_losing_legacy_state, test_bare_doctor_rejects_workstation_profile]:
        check()
        print(f'PASS {check.__name__}')
