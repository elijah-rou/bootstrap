#!/usr/bin/env python3
"""Herdr command dispatch without network, service, or machine registration effects."""
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
installer_pin = re.search(r'^HERDR_INSTALLER_SHA256="([0-9a-f]{64})"$',
                          (ROOT / 'install.sh').read_text(), re.M)
assert installer_pin is not None
INSTALLER_SHA256 = installer_pin.group(1)


def executable(path: Path, content: str) -> None:
    _ = path.write_text(content)
    path.chmod(0o755)
    return


def fixture(root: Path, stage: str = 'success', custom_directory: bool = False) -> tuple[dict[str, str], Path, Path, Path]:
    home = root / 'home'
    home.mkdir()
    guard = root / 'guard'
    guard.mkdir()
    temporary = root / 'tmp'
    temporary.mkdir()
    install_directory = home / ('custom bin' if custom_directory else '.local/bin')
    env = dict(os.environ, HOME=str(home), TMPDIR=str(temporary),
               PATH=f'{install_directory}{os.pathsep}{guard}{os.pathsep}{os.environ["PATH"]}',
               TEST_ROOT=str(root), TEST_STAGE=stage, TEST_INSTALLER_SHA256=INSTALLER_SHA256)
    _ = env.pop('HERDR_INSTALL_DIR', None)
    if custom_directory:
        env['HERDR_INSTALL_DIR'] = str(install_directory)
    for name in ['pi', 'ssh', 'sshd', 'tailscale', 'systemctl', 'launchctl', 'sudo', 'pkexec', 'npm', 'bun']:
        executable(guard / name, '#!/bin/sh\necho unexpected >> "$TEST_ROOT/forbidden"\nexit 99\n')
    executable(guard / 'curl', '''#!/bin/bash
set -eu
printf 'download\\n' >> "$TEST_ROOT/calls"
[[ "$TEST_STAGE" != download ]] || exit 22
[[ " $* " == *" --proto =https "* && " $* " == *" --proto-redir =https "* ]] || exit 90
[[ "${!#}" == https://herdr.dev/install.sh ]] || exit 91
while [[ $# -gt 0 ]]; do
    if [[ "$1" == --output ]]; then cp "$TEST_ROOT/installer" "$2"; exit 0; fi
    shift
done
exit 92
''')
    executable(guard / 'sha256sum', '''#!/bin/sh
printf 'verify\\n' >> "$TEST_ROOT/calls"
if [ "$TEST_STAGE" = checksum ]; then printf 'invalid\\n'; else printf '%s  %s\\n' "$TEST_INSTALLER_SHA256" "$1"; fi
''')
    executable(root / 'installer', '''#!/bin/sh
set -eu
printf 'install\\n' >> "$TEST_ROOT/calls"
[ "$TEST_STAGE" != installer ] || exit 37
directory="${HERDR_INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$directory"
cp "$TEST_ROOT/herdr" "$directory/herdr"
''')
    executable(root / 'herdr', '''#!/bin/sh
set -eu
printf '%s\\n' "$*" >> "$TEST_ROOT/calls"
case "$*" in
    'integration install pi')
        [ "$TEST_STAGE" != integration ] || exit 38
        [ -d "$HOME/.pi/agent/extensions" ] || exit 93
        printf integration > "$HOME/.pi/agent/extensions/herdr-test"
        ;;
    'completion zsh')
        [ "$TEST_STAGE" != completion ] || exit 39
        printf '# fixture completion\\n'
        ;;
    *) printf 'unexpected herdr %s\\n' "$*" >> "$TEST_ROOT/forbidden"; exit 99 ;;
esac
''')
    return env, home, install_directory, temporary


def run(env: dict[str, str], *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(['bash', str(ROOT / 'install.sh'), *arguments], env=env,
                          text=True, capture_output=True, timeout=15)


def test_install_retry_and_user_only_effects() -> None:
    for custom in [False, True]:
        with tempfile.TemporaryDirectory(prefix='herdr-install-') as directory:
            root = Path(directory)
            env, home, installed, temporary = fixture(root, custom_directory=custom)
            for _ in range(2):
                result = run(env, 'herdr')
                assert result.returncode == 0, result.stdout + result.stderr
                assert (installed / 'herdr').is_file()
                assert (home / '.pi/agent/extensions/herdr-test').read_text() == 'integration'
                assert (home / '.zfunc/_herdr').read_text() == '# fixture completion\n'
                assert not (root / 'forbidden').exists()
                assert list(temporary.iterdir()) == []
            assert (root / 'calls').read_text().splitlines() == [
                'download', 'verify', 'install', 'integration install pi', 'completion zsh'] * 2
            assert not (home / '.config').exists()
            assert not (home / '.ssh').exists()
    return


def test_failures_stop_and_clean_temporary_files() -> None:
    stages = ['download', 'checksum', 'installer', 'integration', 'completion']
    expected = ['download', 'verify', 'install', 'integration install pi', 'completion zsh']
    for index, stage in enumerate(stages):
        with tempfile.TemporaryDirectory(prefix='herdr-failure-') as directory:
            root = Path(directory)
            env, _, _, temporary = fixture(root, stage=stage)
            result = run(env, 'herdr')
            assert result.returncode != 0, result.stdout + result.stderr
            assert (root / 'calls').read_text().splitlines() == expected[:index + 1]
            assert list(temporary.iterdir()) == []
            assert not (root / 'forbidden').exists()
    return


def test_unexpected_arguments_fail_before_installation() -> None:
    with tempfile.TemporaryDirectory(prefix='herdr-arguments-') as directory:
        root = Path(directory)
        env, home, _, _ = fixture(root)
        result = run(env, 'herdr', '--label', 'not-a-machine-registration')
        assert result.returncode == 2, result.stdout + result.stderr
        assert not (root / 'calls').exists()
        assert not (root / 'forbidden').exists()
        assert list(home.iterdir()) == []
    return


if __name__ == '__main__':
    for check in [test_install_retry_and_user_only_effects, test_failures_stop_and_clean_temporary_files,
                  test_unexpected_arguments_fail_before_installation]:
        check()
        print(f'PASS {check.__name__}')
