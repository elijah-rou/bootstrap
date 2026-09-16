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
        for name in ['NVIM_CONFIG_CHECKOUT_DIR', 'NVIM_CONFIG_REPO_URL', 'DOTFILES_BARE_ROOT',
                     'BOOTSTRAP_PRIVATE_ROOT', 'BOOTSTRAP_STATE_ROOT', 'PI_CODING_AGENT_DIR',
                     'PI_CODING_AGENT_SESSION_DIR', 'NVIM_APPNAME', 'BOOTSTRAP_LSP_SELECTIONS']:
            self.env.pop(name, None)
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
        agent = self.home / '.local/share/bootstrap/private/pi/agent'
        unrelated_agent = self.home / '.pi/other-profile'
        unrelated_agent.mkdir(parents=True)
        auth = unrelated_agent / 'auth.json'
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
        self.assertFalse((self.home / '.zshenv').exists())
        self.assertFalse((self.home / '.config/starship.toml').exists())
        self.assertEqual((self.home / '.config/dotfiles/bare-env.sh').resolve(), ROOT / 'scripts/bare-env.sh')
        self.assertEqual((self.home / '.local/bin/dev-shell').resolve(), ROOT / 'scripts/dev-shell')
        self.run_config(*args)
        self.assertEqual(list(self.home.rglob('*.bak.*')), [])

    def test_legacy_linked_auth_blocks_configuration_before_cutover(self):
        legacy = self.home / '.pi/agent'
        legacy.mkdir(parents=True)
        secret = self.root / 'legacy-secret'
        secret.write_text('synthetic-credential')
        auth = legacy / 'auth.json'
        auth.symlink_to(secret)
        result = self.run_config('all', ok=False)
        self.assertIn('explicit migration', result.stderr)
        self.assertEqual(auth.readlink(), secret)
        self.assertEqual(secret.read_text(), 'synthetic-credential')
        self.assertFalse((self.home / '.config/dotfiles/bare-env.sh').exists())
        self.assertFalse((self.home / '.local/bin/pi').exists())

    def test_shell_extras_require_recorded_selection_and_runtime_env_is_shared(self):
        self.run_config('terminal')
        self.assertFalse((self.home / '.zshenv').exists())
        self.assertFalse((self.home / '.config/starship.toml').exists())
        command = ['node', str(ROOT / 'scripts/state-helper.mjs'), 'select', 'tools']
        for tool in ['zsh', 'starship']:
            subprocess.run([*command, tool], env=self.env, check=True, capture_output=True, text=True)
        self.run_config('terminal')
        self.assertEqual((self.home / '.zshenv').resolve(), ROOT / 'zshenv')
        self.assertEqual((self.home / '.config/starship.toml').resolve(), ROOT / 'starship.toml')
        output = subprocess.check_output(
            ['bash', '-c', '. "$HOME/.bashrc"; printf "%s\n%s\n" "$PI_CODING_AGENT_DIR" "$NVIM_APPNAME"'],
            env=self.env, text=True).splitlines()
        self.assertEqual(output, [str(self.home / '.local/share/bootstrap/private/pi/agent'), 'bootstrap-nvim'])
        output = subprocess.check_output(
            ['zsh', '-c', 'source "$HOME/.zshenv"; printf "%s\\n%s\\n" "$PI_CODING_AGENT_DIR" "$NVIM_APPNAME"'],
            env=self.env, text=True).splitlines()
        self.assertEqual(output, [str(self.home / '.local/share/bootstrap/private/pi/agent'), 'bootstrap-nvim'])

    def test_shell_extras_require_recorded_selections(self):
        self.run_config('terminal')
        self.assertFalse((self.home / '.zshrc').exists())
        self.assertFalse((self.home / '.config/starship.toml').exists())
        for selection in ['zsh', 'starship']:
            subprocess.run(['node', str(ROOT / 'scripts/state-helper.mjs'), 'select', 'tools', selection],
                           env=self.env, check=True, capture_output=True, text=True)
        self.run_config('terminal')
        self.assertEqual((self.home / '.zshrc').resolve(), ROOT / 'zshrc')
        self.assertEqual((self.home / '.config/starship.toml').resolve(), ROOT / 'starship.toml')
        expected = f'{self.home}/.local/share/bootstrap/private/pi/agent|bootstrap-nvim'
        bash = subprocess.check_output(['bash', '-c', '. "$HOME/.bashrc"; printf "%s|%s" "$PI_CODING_AGENT_DIR" "$NVIM_APPNAME"'], env=self.env, text=True)
        zsh = subprocess.check_output(['zsh', '-c', 'printf "%s|%s" "$PI_CODING_AGENT_DIR" "$NVIM_APPNAME"'], env=self.env, text=True)
        self.assertEqual(bash, expected)
        self.assertEqual(zsh, expected)

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
        self.assertTrue((extensions / 'retired.ts').is_symlink())
        self.assertTrue((extensions / 'unmanaged.ts').is_symlink())
        self.assertTrue(interactive.is_symlink())
        self.assertTrue(bare.is_symlink())
        self.assertEqual(zshrc.read_text(), 'keep my old shell')
        backups = list(self.home.rglob('*.bak.*'))
        self.assertFalse(any(p.is_file() and p.read_text() == 'keep my old shell' for p in backups))
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
        settings = self.home / '.local/share/bootstrap/private/pi/agent/settings.json'
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

    def test_skill_aliases_converge_from_cached_snapshot_to_checkout(self):
        self.run_config('codex')
        name = (ROOT / 'codex/skills.txt').read_text().splitlines()[0]
        for cache_setting in ['default', 'DOTFILES_BOOTSTRAP_ROOT', 'BOOTSTRAP_ROOT', 'precedence']:
            with self.subTest(cache_setting=cache_setting):
                self.env.pop('DOTFILES_BOOTSTRAP_ROOT', None)
                self.env.pop('BOOTSTRAP_ROOT', None)
                cache = self.home / '.local/share/bootstrap' if cache_setting == 'default' else self.root / cache_setting
                if cache_setting == 'precedence':
                    self.env['DOTFILES_BOOTSTRAP_ROOT'] = str(cache)
                    self.env['BOOTSTRAP_ROOT'] = str(self.root / 'unselected-cache')
                elif cache_setting != 'default':
                    self.env[cache_setting] = str(cache)
                snapshot = cache / 'snapshots' / ('a' * 40)
                source = snapshot / 'pi/skills' / name
                source.mkdir(parents=True)
                (source / 'SKILL.md').write_text('old managed skill')
                (snapshot / 'install.sh').write_text('#!/bin/sh\n')
                (snapshot / 'install.sh').chmod(0o755)
                (snapshot / '.bootstrap-archive-sha256').write_text('b' * 64 + '\n')
                retired = self.home / '.pi/agent/extensions/retired.ts'
                retired.parent.mkdir(parents=True, exist_ok=True)
                retired.unlink(missing_ok=True)
                retired.symlink_to(snapshot / 'pi/extensions/retired.ts')
                pi = self.home / '.local/share/bootstrap/private/pi/agent/skills' / name
                shared = self.home / '.agents/skills' / name
                for command in ['pi', 'codex']:
                    with self.subTest(command=command):
                        for alias in [pi, shared]:
                            alias.parent.mkdir(parents=True, exist_ok=True)
                            alias.unlink(missing_ok=True)
                            alias.symlink_to(source)
                        self.run_config(command)
                        self.assertEqual(pi.resolve(), ROOT / 'pi/skills' / name)
                        self.assertEqual(shared.resolve(), pi.resolve())
                        self.assertEqual(retired.readlink(), snapshot / 'pi/extensions/retired.ts')
                        backups = sorted(str(p) for p in self.home.rglob('*.bak.*'))
                        self.run_config(command)
                        self.assertEqual(sorted(str(p) for p in self.home.rglob('*.bak.*')), backups)

    def test_pi_does_not_create_shared_skill_root(self):
        self.run_config('pi')
        self.assertFalse((self.home / '.agents').exists())

    def test_codex_does_not_create_pi_skill_root(self):
        self.run_config('codex')
        self.assertFalse((self.home / '.pi').exists())

    def test_checkout_rejects_unproven_cached_skill_ownership(self):
        name = (ROOT / 'codex/skills.txt').read_text().splitlines()[0]
        for mode in ['unmarked', 'malformed', 'extra-line', 'not-executable', 'other-cache', 'suffix-root', 'nested-asset', 'symlink-root']:
            with self.subTest(mode=mode):
                cache = self.root / mode
                self.env['DOTFILES_BOOTSTRAP_ROOT'] = str(cache)
                snapshot = cache / 'snapshots' / ('c' * 40)
                source = snapshot / 'pi/skills' / name
                source.mkdir(parents=True)
                (source / 'SKILL.md').write_text('preserve this skill')
                installer = snapshot / 'install.sh'
                installer.write_text('#!/bin/sh\n')
                installer.chmod(0o755)
                marker = snapshot / '.bootstrap-archive-sha256'
                marker.write_text('d' * 64 + '\n')
                if mode == 'unmarked':
                    marker.unlink()
                elif mode == 'malformed':
                    marker.write_text('not a checksum')
                elif mode == 'extra-line':
                    marker.write_text('d' * 64 + '\nextra\n')
                elif mode == 'not-executable':
                    installer.chmod(0o644)
                elif mode == 'other-cache':
                    self.env['DOTFILES_BOOTSTRAP_ROOT'] = str(self.root / 'selected-cache')
                elif mode == 'suffix-root':
                    renamed = snapshot.with_name(snapshot.name + '-custom')
                    snapshot.rename(renamed)
                    source = renamed / 'pi/skills' / name
                elif mode == 'nested-asset':
                    source = snapshot / 'custom/pi/skills' / name
                    source.mkdir(parents=True)
                    (source / 'SKILL.md').write_text('preserve this skill')
                elif mode == 'symlink-root':
                    renamed = snapshot.with_name('external')
                    snapshot.rename(renamed)
                    snapshot.symlink_to(renamed)
                shared = self.home / '.agents/skills' / name
                shared.parent.mkdir(parents=True, exist_ok=True)
                shared.unlink(missing_ok=True)
                shared.symlink_to(source)
                for command in ['pi', 'codex']:
                    self.run_config(command)
                    self.assertEqual(shared.readlink(), source)
                    self.assertEqual((source / 'SKILL.md').read_text(), 'preserve this skill')

    def test_unowned_shared_skill_is_preserved_during_pi_setup(self):
        name = (ROOT / 'codex/skills.txt').read_text().splitlines()[0]
        source = self.root / 'custom' / name
        source.mkdir(parents=True)
        (source / 'SKILL.md').write_text('user skill')
        shared = self.home / '.agents/skills' / name
        shared.parent.mkdir(parents=True)
        shared.symlink_to(source)
        self.run_config('pi')
        self.assertEqual(shared.readlink(), source)
        self.assertEqual((source / 'SKILL.md').read_text(), 'user skill')
        shared.unlink()
        shared.symlink_to(ROOT / 'pi/skills' / name)
        pi = self.home / '.local/share/bootstrap/private/pi/agent/skills' / name
        pi.unlink()
        pi.symlink_to(source)
        self.run_config('codex')
        self.assertEqual(pi.readlink(), source)
        self.assertEqual((source / 'SKILL.md').read_text(), 'user skill')

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

    def test_checkout_only_install_preserves_explicit_legacy_override(self):
        checkout = self.root / 'explicit-checkout'
        self.env['NVIM_CONFIG_CHECKOUT_DIR'] = str(checkout)
        self.env.pop('NVIM_CONFIG_REPO_URL', None)
        git = self.root / 'guard/git'
        git.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$HOME/git-args"\nexit 29\n')
        git.chmod(0o755)
        result = subprocess.run(['bash', str(ROOT / 'install.sh'), 'neovim'], env=self.env,
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.home / 'git-args').read_text().splitlines(),
                         ['clone', '--', 'https://github.com/elijah-rou/lazyvim-config.git', str(checkout)])
        self.assertFalse(checkout.with_name('explicit-checkout.install.lock').exists())
        self.assertFalse((self.home / '.config/bootstrap-nvim').exists())

    def test_workstation_neovim_install_command(self):
        upstream = self.root / 'upstream'
        (upstream / 'lua/config').mkdir(parents=True)
        (upstream / 'lua/plugins').mkdir(parents=True)
        (upstream / 'lua/plugins/.keep').write_text('')
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
        self.assertEqual((self.home / '.config/bootstrap-nvim').resolve(), checkout)
        self.assertEqual((checkout / 'lua/plugins/zz-bootstrap-managed.lua').resolve(), ROOT / 'neovim/bootstrap.lua')

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
        (checkout / 'lua/plugins').mkdir(parents=True)
        (checkout / 'init.lua').write_text('return {}')
        (checkout / 'lua/config/lazy.lua').write_text('return {}')
        self.env['NVIM_CONFIG_CHECKOUT_DIR'] = str(checkout)
        self.env['NVIM_CONFIG_REPO_URL'] = 'https://invalid.invalid/never-clone'
        self.run_config('neovim')
        self.assertEqual((self.home / '.config/bootstrap-nvim').resolve(), checkout)
        self.assertFalse((checkout / '.git').exists())
        plugin = checkout / 'lua/plugins/zz-bootstrap-managed.lua'
        self.assertEqual(plugin.resolve(), ROOT / 'neovim/bootstrap.lua')
        self.run_config('neovim')
        self.assertTrue(plugin.is_symlink())
        plugin.unlink()
        plugin.write_text('user managed plugin')
        self.run_config('neovim', ok=False)
        self.assertEqual(plugin.read_text(), 'user managed plugin')

    def test_external_policy_link_uninstalls_without_owning_checkout(self):
        checkout = self.root / 'external-policy'
        (checkout / 'lua/config').mkdir(parents=True)
        (checkout / 'lua/plugins').mkdir(parents=True)
        (checkout / 'init.lua').write_text('return {}')
        (checkout / 'lua/config/lazy.lua').write_text('return {}')
        sentinel = checkout / 'keep'; sentinel.write_text('external')
        self.env['NVIM_CONFIG_CHECKOUT_DIR'] = str(checkout)
        self.env['NVIM_CONFIG_REPO_URL'] = 'https://invalid.invalid/never-clone'
        self.run_config('neovim')
        plugin = checkout / 'lua/plugins/zz-bootstrap-managed.lua'
        helper = ['node']
        preview = subprocess.run([*helper, str(ROOT / 'scripts/state-helper.mjs'), 'uninstall', '--dry-run'],
                                 env=self.env, capture_output=True, text=True)
        self.assertEqual(preview.returncode, 0, preview.stdout + preview.stderr)
        self.assertIn(f'remove\t{plugin}', preview.stdout)
        result = subprocess.run([*helper, str(ROOT / 'scripts/state-helper.mjs'), 'uninstall'],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(plugin.exists())
        self.assertEqual(sentinel.read_text(), 'external')
        self.assertTrue(checkout.is_dir())
        subprocess.run([*helper, str(ROOT / 'scripts/state-helper.mjs'), 'finish-uninstall'], env=self.env, check=True)

    def test_external_policy_link_rejects_parent_and_checkout_identity_changes(self):
        checkout = self.root / 'external-identity'
        (checkout / 'lua/config').mkdir(parents=True)
        plugins = checkout / 'lua/plugins'; plugins.mkdir(parents=True)
        (checkout / 'init.lua').write_text('return {}')
        (checkout / 'lua/config/lazy.lua').write_text('return {}')
        self.env['NVIM_CONFIG_CHECKOUT_DIR'] = str(checkout)
        self.env['NVIM_CONFIG_REPO_URL'] = 'https://invalid.invalid/never-clone'
        self.run_config('neovim')
        moved_plugins = checkout / 'lua/plugins-real'
        plugins.rename(moved_plugins); plugins.symlink_to(moved_plugins)
        result = subprocess.run(['node', str(ROOT / 'scripts/state-helper.mjs'), 'uninstall', '--dry-run'],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('parent changed', result.stderr)
        plugins.unlink(); moved_plugins.rename(plugins)
        moved_checkout = checkout.with_name('external-identity-original')
        checkout.rename(moved_checkout)
        (checkout / 'lua/plugins').mkdir(parents=True)
        result = subprocess.run(['node', str(ROOT / 'scripts/state-helper.mjs'), 'uninstall', '--dry-run'],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('checkout was replaced', result.stderr)
        self.assertTrue((moved_checkout / 'lua/plugins/zz-bootstrap-managed.lua').is_symlink())

    def test_tracked_external_policy_collision_is_preserved(self):
        checkout = self.root / 'tracked-policy'
        (checkout / 'lua/config').mkdir(parents=True)
        (checkout / 'lua/plugins').mkdir(parents=True)
        (checkout / 'init.lua').write_text('return {}')
        (checkout / 'lua/config/lazy.lua').write_text('return {}')
        plugin = checkout / 'lua/plugins/zz-bootstrap-managed.lua'; plugin.write_text('tracked custom policy')
        subprocess.run(['git', '-C', str(checkout), 'init', '-q'], env=self.env, check=True)
        subprocess.run(['git', '-C', str(checkout), 'add', '.'], env=self.env, check=True)
        self.env['NVIM_CONFIG_CHECKOUT_DIR'] = str(checkout)
        self.env['NVIM_CONFIG_REPO_URL'] = 'https://invalid.invalid/never-clone'
        self.run_config('neovim', ok=False)
        self.assertEqual(plugin.read_text(), 'tracked custom policy')


if __name__ == '__main__':
    unittest.main()
