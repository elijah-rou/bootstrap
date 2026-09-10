#!/usr/bin/env python3
"""Offline configuration contract, isolated from the caller's workstation."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ConfigurationContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.home = self.root / 'home'
        self.home.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), CODEX_HOME=str(self.home / '.codex'),
                        XDG_CONFIG_HOME=str(self.home / '.config'), XDG_STATE_HOME=str(self.home / '.local/state'),
                        XDG_DATA_HOME=str(self.home / '.local/share'))
        self.env.pop('NVIM_CONFIG_CHECKOUT_DIR', None)
        self.env.pop('NVIM_CONFIG_REPO_URL', None)
        guard = self.root / 'guard'
        guard.mkdir()
        for command in ['sudo', 'systemctl', 'chsh', 'curl', 'wget', 'npm', 'bun', 'pi', 'micromamba']:
            path = guard / command
            path.write_text('#!/bin/sh\necho "Unexpected external operation" >&2\nexit 99\n')
            path.chmod(0o755)
        self.env['PATH'] = str(guard) + os.pathsep + self.env['PATH']

    def run_config(self, *args, ok=True):
        result = subprocess.run(['bash', str(ROOT / 'configure.sh'), *map(str, args)],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result

    def test_input_rejections_do_not_write(self):
        for args in [(), ('unknown',), ('pi', '--unknown'), ('pi', '--overlay'),
                     ('pi', '--overlay', 'relative'), ('pi', '--overlay', self.root / 'missing'),
                     ('pi', '--legacy-root', '/'), ('pi', '--legacy-root'),
                     ('pi', '--legacy-root', 'relative'), ('pi', 'null'), ('pi', '--overlay', 'undefined'),
                     ('pi', '--legacy-root', self.root, '--legacy-root', self.root)]:
            with self.subTest(args=args):
                self.run_config(*args, ok=False)
                self.assertEqual(list(self.home.iterdir()), [])

    def test_ordered_overlays_and_auth_preservation(self):
        low, high = self.root / 'low space', self.root / "high'quote"
        for directory in [low, high]:
            directory.mkdir()
        (low / 'pi-settings.json').write_text(json.dumps({'contract': {'keep': 1, 'value': 1}, 'packages': ['low']}))
        (high / 'pi-settings.json').write_text(json.dumps({'contract': {'value': 2}, 'packages': [], 'nullable': None}))
        (low / 'pi-models.json').write_text(json.dumps({'contract': {'keep': True, 'replace': [1, 2]}}))
        (high / 'pi-models.json').write_text(json.dumps({'contract': {'replace': [3]}}))
        for directory, value in [(low, 'low'), (high, 'high')]:
            (directory / 'gitconfig').write_text(f'[contract]\n value = {value}\n')
            (directory / 'env.sh').write_text(f'export CONTRACT_ENV={value}\n')
            (directory / 'zshenv').write_text(f'export CONTRACT_ZSH={value}\n')
            (directory / 'repos.conf').write_text(value + '\n')
        agent = self.home / '.pi/agent'
        agent.mkdir(parents=True)
        auth = agent / 'auth.json'
        secret = self.root / 'secret'
        secret.write_text('private-auth')
        auth.symlink_to(secret)
        codex = self.home / '.codex'
        codex.mkdir()
        (codex / 'config.toml').write_text('local settings')
        (codex / 'hooks.json').write_text('local hooks')
        args = ('all', '--overlay', low, '--overlay', high)
        self.run_config(*args)
        self.assertEqual(json.loads((agent / 'settings.json').read_text())['contract'], {'keep': 1, 'value': 2})
        self.assertEqual(json.loads((agent / 'settings.json').read_text())['packages'], [])
        self.assertEqual(json.loads((agent / 'models.json').read_text())['contract'], {'keep': True, 'replace': [3]})
        self.assertTrue(auth.is_symlink())
        self.assertEqual(secret.read_text(), 'private-auth')
        self.assertEqual((codex / 'config.toml').read_text(), 'local settings')
        self.assertEqual((codex / 'hooks.json').read_text(), 'local hooks')
        value = subprocess.check_output(['git', 'config', '--global', '--includes', 'contract.value'], env=self.env, text=True)
        self.assertEqual(value.strip(), 'high')
        value = subprocess.check_output(['bash', '-c', '. "$HOME/.config/dotfiles/env.sh"; printf %s "$CONTRACT_ENV"'], env=self.env, text=True)
        self.assertEqual(value, 'high')
        self.assertEqual((self.home / '.config/dotfiles/repos.conf').read_text(), 'high\n')
        self.assertEqual((self.home / '.zshenv').resolve(), ROOT / 'zshenv')
        self.assertFalse((self.home / '.config/dotfiles/bare-env.sh').exists())
        self.assertFalse((self.home / '.local/bin/dev-shell').exists())
        self.run_config(*args)
        self.assertEqual(list(self.home.rglob('*.bak.*')), [])

    def test_legacy_cleanup_backups_and_retry(self):
        legacy = self.root / 'legacy'
        legacy.mkdir()
        extensions = self.home / '.pi/agent/extensions'
        extensions.mkdir(parents=True)
        (extensions / 'retired.ts').symlink_to(legacy / 'pi/extensions/retired.ts')
        (extensions / 'unmanaged.ts').symlink_to(self.root / 'unmanaged.ts')
        interactive = self.home / '.pi/agent/interactive-shell.json'
        interactive.symlink_to(self.root / 'custom.json')
        zshrc = self.home / '.zshrc'
        zshrc.write_text('keep my old shell')
        bare = self.home / '.config/dotfiles/bare-env.sh'
        bare.parent.mkdir(parents=True)
        bare.symlink_to(ROOT / 'scripts/bare-env.sh')
        self.run_config('all', '--legacy-root', legacy)
        self.assertFalse((extensions / 'retired.ts').is_symlink())
        self.assertTrue((extensions / 'unmanaged.ts').is_symlink())
        self.assertTrue(interactive.is_symlink())
        self.assertFalse(bare.is_symlink())
        backups = list(self.home.rglob('*.bak.*'))
        self.assertTrue(any(p.read_text() == 'keep my old shell' for p in backups if p.is_file()))
        self.run_config('all', '--legacy-root', legacy)
        self.assertEqual(list(self.home.rglob('*.bak.*')), backups)
        lock = self.home / '.local/state/bootstrap/configure.lock'
        lock.mkdir()
        self.run_config('pi', ok=False)
        self.assertTrue(lock.is_dir())
        lock.rmdir()
        self.run_config('pi')

    def test_invalid_json_preserves_settings_and_releases_lock(self):
        overlay = self.root / 'overlay'
        overlay.mkdir()
        self.run_config('pi')
        settings = self.home / '.pi/agent/settings.json'
        original = settings.read_bytes()
        for value in ['null', '[]', '"string"', 'true', '1', '{"value": NaN}', '{']:
            with self.subTest(value=value):
                (overlay / 'pi-settings.json').write_text(value)
                self.run_config('pi', '--overlay', overlay, ok=False)
                self.assertEqual(settings.read_bytes(), original)
                self.assertFalse((self.home / '.local/state/bootstrap/configure.lock').exists())
        (overlay / 'pi-settings.json').write_text('{"contract": true}')
        self.run_config('pi', '--overlay', overlay)
        self.assertTrue(json.loads(settings.read_text())['contract'])
        backups = list(settings.parent.glob('settings.json.bak.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), original)
        self.run_config('pi', '--overlay', overlay)
        self.assertEqual(list(settings.parent.glob('settings.json.bak.*')), backups)

    def test_codex_legacy_skill_migration_preserves_custom_skills(self):
        legacy = self.root / 'legacy'
        name = (ROOT / 'codex/skills.txt').read_text().splitlines()[0]
        source = legacy / 'pi/skills' / name
        source.mkdir(parents=True)
        (source / 'SKILL.md').write_text('old managed skill')
        shared = self.home / '.agents/skills'
        shared.mkdir(parents=True)
        (shared / name).symlink_to(source)
        (shared / 'retired').symlink_to(legacy / 'pi/skills/retired')
        (shared / 'custom').symlink_to(self.root / 'custom')
        self.run_config('codex', '--legacy-root', legacy)
        self.assertEqual((shared / name).resolve(), ROOT / 'pi/skills' / name)
        self.assertFalse((shared / 'retired').is_symlink())
        self.assertTrue((shared / 'custom').is_symlink())
        backups = list((self.home / '.codex/backups').rglob('*.bak.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].readlink(), source)
        self.run_config('codex', '--legacy-root', legacy)
        self.assertEqual(list((self.home / '.codex/backups').rglob('*.bak.*')), backups)

    def test_install_read_only_contract(self):
        result = subprocess.run(['bash', str(ROOT / 'install.sh'), 'pi-version'], env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '0.85.1\n')
        result = subprocess.run(['bash', str(ROOT / 'install.sh'), 'pi-check'], env=self.env,
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('checkout missing', result.stdout)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_workstation_neovim_install_command(self):
        upstream = self.root / 'upstream'
        (upstream / 'lua/config').mkdir(parents=True)
        (upstream / 'init.lua').write_text('return {}')
        (upstream / 'lua/config/lazy.lua').write_text('return {}')
        for args in [('init', '-q'), ('add', '.'), ('-c', 'user.name=Test', '-c',
                     'user.email=test@example.invalid', 'commit', '-qm', 'initial')]:
            subprocess.run(['git', '-C', str(upstream), *args], check=True, env=self.env,
                           capture_output=True, text=True)
        checkout = self.root / 'checkout'
        self.env['NVIM_CONFIG_CHECKOUT_DIR'] = str(checkout)
        self.env['NVIM_CONFIG_REPO_URL'] = str(upstream)
        for _ in range(2):
            result = subprocess.run(['bash', str(ROOT / 'install.sh'), 'neovim'], env=self.env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((checkout / '.git').is_dir())
        self.assertEqual((self.home / '.config/nvim').resolve(), checkout)
        self.assertFalse((checkout / 'lua/plugins/zz-bootstrap-managed.lua').exists())

    def test_package_install_command_uses_rendered_configuration(self):
        overlay = self.root / 'packages'
        overlay.mkdir()
        (overlay / 'pi-settings.json').write_text('{"packages": ["fixture:first", "fixture:second"]}')
        self.run_config('pi', '--overlay', overlay)
        stub = self.root / 'guard/pi'
        stub.write_text('#!/bin/sh\nprintf "%s %s\\n" "$1" "$2" >> "$HOME/packages.log"\n')
        result = subprocess.run(['bash', str(ROOT / 'install.sh'), 'pi-packages'], env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.home / 'packages.log').read_text(), 'install fixture:first\ninstall fixture:second\n')

    def test_neovim_relinks_without_mason_or_network(self):
        checkout = self.root / 'nvim'
        (checkout / 'lua/config').mkdir(parents=True)
        (checkout / 'init.lua').write_text('return {}')
        (checkout / 'lua/config/lazy.lua').write_text('return {}')
        self.env['NVIM_CONFIG_CHECKOUT_DIR'] = str(checkout)
        self.env['NVIM_CONFIG_REPO_URL'] = 'https://invalid.invalid/never-clone'
        self.run_config('neovim')
        self.assertEqual((self.home / '.config/nvim').resolve(), checkout)
        self.assertFalse((checkout / 'lua/plugins/zz-bootstrap-managed.lua').exists())
        self.assertFalse((checkout / '.git').exists())
        plugin = checkout / 'lua/plugins/zz-bootstrap-managed.lua'
        plugin.parent.mkdir()
        plugin.symlink_to(ROOT / 'neovim/bootstrap.lua')
        self.run_config('neovim')
        self.assertFalse(plugin.is_symlink())
        plugin.write_text('user managed plugin')
        self.run_config('neovim')
        self.assertEqual(plugin.read_text(), 'user managed plugin')


if __name__ == '__main__':
    unittest.main()
