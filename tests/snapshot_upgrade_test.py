#!/usr/bin/env python3
"""Snapshot upgrades recognize only completed sibling snapshots and exact assets."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SnapshotUpgrade(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.snapshots = self.root / 'bootstrap/snapshots'
        self.old = self.snapshots / ('a' * 40)
        self.new = self.snapshots / ('b' * 40)
        for snapshot in [self.old, self.new]:
            shutil.copytree(ROOT, snapshot, ignore=shutil.ignore_patterns('.git', '__pycache__', 'node_modules'))
            (snapshot / '.bootstrap-archive-sha256').write_text('c' * 64 + '\n')
        (self.old / 'pi/extensions/retired.ts').write_text('old extension')
        self.skill = (ROOT / 'codex/skills.txt').read_text().splitlines()[0]

    def environment(self, name):
        home = self.root / name
        home.mkdir()
        return dict(os.environ, HOME=str(home), CODEX_HOME=str(home / '.codex'),
                    XDG_CONFIG_HOME=str(home / '.config'), XDG_STATE_HOME=str(home / '.local/state'),
                    XDG_DATA_HOME=str(home / '.local/share'), NVIM_CONFIG_CHECKOUT_DIR=str(home / 'absent-nvim'))

    def run_command(self, snapshot, env, *args):
        result = subprocess.run(['bash', str(snapshot / args[0]), *args[1:]], env=env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_bare_and_workstation_upgrades_retarget_and_retire(self):
        for profile in ['bare', 'workstation']:
            with self.subTest(profile=profile):
                env = self.environment(profile)
                home = Path(env['HOME'])
                commands = [('install.sh', 'link'), ('install.sh', 'codex-link')] if profile == 'bare' else [('configure.sh', 'all')]
                for command in commands:
                    self.run_command(self.old, env, *command)
                skill = home / '.agents/skills' / self.skill
                retired = home / '.pi/agent/extensions/retired.ts'
                self.assertEqual(skill.readlink(), self.old / 'pi/skills' / self.skill)
                self.assertEqual(retired.readlink(), self.old / 'pi/extensions/retired.ts')
                for command in commands:
                    self.run_command(self.new, env, *command)
                with self.subTest(asset='Codex skill'):
                    self.assertEqual(skill.readlink(), self.new / 'pi/skills' / self.skill)
                with self.subTest(asset='retired Pi extension'):
                    self.assertFalse(retired.is_symlink())
                self.assertTrue((self.old / 'pi/extensions/retired.ts').is_file())
                backups = sorted(home.rglob('*.bak.*'))
                for command in commands:
                    self.run_command(self.new, env, *command)
                self.assertEqual(sorted(home.rglob('*.bak.*')), backups)

    def test_unproven_and_nonmatching_links_are_preserved(self):
        for mode in ['unmarked', 'malformed', 'extra-line', 'not-executable', 'suffix-root', 'other-cache', 'suffix-asset', 'current-suffix-asset', 'unmarked-current']:
            with self.subTest(mode=mode):
                env = self.environment(mode)
                home = Path(env['HOME'])
                candidate = self.old
                marker = self.old / '.bootstrap-archive-sha256'
                marker.write_text('c' * 64 + '\n')
                (self.new / '.bootstrap-archive-sha256').write_text('c' * 64 + '\n')
                (self.old / 'install.sh').chmod(0o755)
                if mode == 'unmarked':
                    marker.unlink()
                elif mode == 'malformed':
                    marker.write_text('not-a-checksum')
                elif mode == 'extra-line':
                    marker.write_text('c' * 64 + '\nextra\n')
                elif mode == 'not-executable':
                    (self.old / 'install.sh').chmod(0o644)
                elif mode in ['suffix-root', 'other-cache']:
                    candidate = self.snapshots / ('a' * 40 + '-custom') if mode == 'suffix-root' else self.root / 'other/snapshots' / ('a' * 40)
                    shutil.copytree(self.old, candidate)
                elif mode == 'current-suffix-asset':
                    candidate = self.new
                elif mode == 'unmarked-current':
                    (self.new / '.bootstrap-archive-sha256').unlink()
                skill = home / '.agents/skills' / self.skill
                retired = home / '.pi/agent/extensions/retired.ts'
                for target in [skill, retired]:
                    target.parent.mkdir(parents=True, exist_ok=True)
                skill_source = candidate / 'pi/skills' / self.skill
                extension_source = candidate / 'pi/extensions/retired.ts'
                if mode == 'current-suffix-asset':
                    skill_source = candidate / 'pi/skills/nested' / self.skill
                    extension_source = candidate / 'pi/extensions/nested/retired.ts'
                if mode == 'suffix-asset':
                    skill_source = candidate / 'custom/pi/skills' / self.skill
                    extension_source = candidate / 'custom/pi/extensions/retired.ts'
                skill.symlink_to(skill_source)
                retired.symlink_to(extension_source)
                self.run_command(self.new, env, 'configure.sh', 'all')
                self.assertEqual(skill.readlink(), skill_source)
                self.assertEqual(retired.readlink(), extension_source)

    def test_workstation_removes_prior_snapshot_bare_activation_links(self):
        env = self.environment('transition')
        home = Path(env['HOME'])
        self.run_command(self.old, env, 'install.sh', 'link')
        bare = home / '.config/dotfiles/bare-env.sh'
        launcher = home / '.local/bin/dev-shell'
        self.assertTrue(bare.is_symlink())
        self.assertTrue(launcher.is_symlink())
        self.run_command(self.new, env, 'configure.sh', 'terminal')
        self.assertFalse(bare.is_symlink())
        self.assertFalse(launcher.is_symlink())


if __name__ == '__main__':
    unittest.main()
