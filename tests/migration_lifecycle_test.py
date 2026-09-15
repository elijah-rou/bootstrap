#!/usr/bin/env python3
"""Synthetic legacy-to-owned migration lifecycle and recovery checks."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MigrationLifecycleTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='bootstrap-migration-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.home = self.root / 'home'
        self.legacy = self.home / '.pi/agent'
        self.agent = self.home / 'private/pi/agent'
        self.sessions = self.home / 'private/pi/sessions'
        self.state = self.home / 'state/bootstrap'
        self.home.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / '.config'),
                        XDG_DATA_HOME=str(self.home / '.data'), XDG_CACHE_HOME=str(self.home / '.cache'),
                        XDG_STATE_HOME=str(self.home / 'state-home'),
                        BOOTSTRAP_PRIVATE_ROOT=str(self.home / 'private'),
                        BOOTSTRAP_STATE_ROOT=str(self.state), DOTFILES_BARE_ROOT=str(self.home / 'tools'))

    def run_migration(self, phase, confirm=False, status=0):
        args = ['bash', str(ROOT / 'install.sh'), 'migration', phase]
        if confirm:
            args.append('--yes')
        result = subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        return result

    def seed_legacy(self):
        (self.legacy / 'sessions/nested').mkdir(parents=True)
        (self.legacy / 'skills/custom-skill').mkdir(parents=True)
        (self.legacy / 'skills/.backups/custom-old').mkdir(parents=True)
        (self.legacy / 'auth.json').write_text('{"token":"synthetic"}\n')
        (self.legacy / 'auth.json').chmod(0o600)
        (self.legacy / 'settings.json').write_text('{"theme":"custom","packages":[]}\n')
        (self.legacy / 'settings.json').chmod(0o640)
        (self.legacy / 'models.json').write_text('{"providers":{"synthetic":{}}}\n')
        (self.legacy / 'WORKTREE_STREAMS.md').write_text('personal worktree modes\n')
        (self.legacy / 'sessions/nested/session.jsonl').write_text('{"message":"fixture"}\n')
        (self.legacy / 'skills/custom-skill/SKILL.md').write_text('synthetic custom skill\n')
        (self.legacy / 'skills/.backups/custom-old/SKILL.md').write_text('synthetic backup\n')
        (self.legacy / 'links').mkdir()
        (self.legacy / 'links/session-absolute').symlink_to(self.legacy / 'sessions/nested/session.jsonl')
        (self.legacy / 'links/session-relative').symlink_to('../sessions/nested/session.jsonl')

        old = self.home / ('cache/snapshots/' + 'a' * 40)
        (old / 'pi').mkdir(parents=True)
        shutil.copy2(ROOT / 'install.sh', old / 'install.sh')
        (old / 'install.sh').chmod(0o755)
        (old / '.bootstrap-archive-sha256').write_text('b' * 64 + '\n')
        (old / 'pi/AGENTS.md').write_text('old managed source\n')
        (self.legacy / 'AGENTS.md').symlink_to(old / 'pi/AGENTS.md')

    def test_full_transfer_activation_and_retirement_preserve_personal_state(self):
        self.seed_legacy()
        inspect = self.run_migration('inspect')
        report = json.loads(inspect.stdout)
        self.assertEqual(report['schemaVersion'], 1)
        self.assertTrue(report['ready'])
        self.assertFalse(self.state.exists(), 'inspect must not create state or locks')

        self.run_migration('prepare')
        self.assertFalse((self.home / '.config/dotfiles/bare-env.sh').exists())
        self.assertTrue(self.legacy.exists())

        writer = subprocess.Popen(['bash', '-c', f'exec -a "{self.legacy}/writer" sleep 30'], env=self.env)
        self.addCleanup(lambda: writer.poll() is not None or writer.kill())
        time.sleep(0.1)
        blocked = self.run_migration('transfer', confirm=True, status=1)
        self.assertIn('active writers', blocked.stderr)
        writer.terminate()
        writer.wait(timeout=5)

        self.run_migration('transfer', confirm=True)
        self.run_migration('transfer', confirm=True)
        self.assertEqual((self.agent / 'auth.json').read_text(), '{"token":"synthetic"}\n')
        self.assertEqual((self.agent / 'auth.json').stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.agent / 'settings.json').stat().st_mode & 0o777, 0o640)
        session = self.sessions / 'nested/session.jsonl'
        self.assertEqual(session.read_text(), '{"message":"fixture"}\n')
        self.assertEqual((self.agent / 'links/session-absolute').readlink(), session)
        self.assertEqual((self.agent / 'links/session-relative').resolve(), session.resolve())
        self.assertEqual((self.agent / 'AGENTS.md').readlink(), ROOT / 'pi/AGENTS.md')
        self.assertEqual((self.agent / 'skills/.backups/custom-old/SKILL.md').read_text(), 'synthetic backup\n')

        cli = self.home / 'tools/bun/install/global/node_modules/@earendil-works/pi-coding-agent/dist/cli.js'
        cli.parent.mkdir(parents=True)
        cli.write_text('console.log(process.argv.slice(2).join("\\n"));\n')
        self.run_migration('activate', confirm=True)
        self.run_migration('activate', confirm=True)
        self.assertEqual((self.home / '.config/dotfiles/bare-env.sh').readlink(), ROOT / 'scripts/bare-env.sh')
        launched = subprocess.run([self.home / '.local/bin/pi', '--version'], env=self.env,
                                  capture_output=True, text=True, check=True).stdout.splitlines()
        self.assertEqual(launched[:2], ['--session-dir', str(self.sessions)])
        self.assertTrue(session.is_file())
        self.run_migration('verify')

        new_session = self.sessions / 'post-cutover.jsonl'
        new_session.write_text('{"new":true}\n')
        rollback = self.run_migration('rollback', confirm=True, status=1)
        self.assertIn('post-cutover additions', rollback.stderr)
        self.assertEqual(new_session.read_text(), '{"new":true}\n')
        new_session.unlink()

        settings = self.agent / 'settings.json'
        settings_original = settings.read_bytes()
        settings.write_text('{"changed":true}\n')
        changed = self.run_migration('rollback', confirm=True, status=1)
        self.assertIn('file changes', changed.stderr)
        settings.write_bytes(settings_original)
        settings.chmod(0o640)

        session_original = session.read_bytes()
        session.unlink()
        deleted = self.run_migration('rollback', confirm=True, status=1)
        self.assertIn('deletions', deleted.stderr)
        session.write_bytes(session_original)

        legacy_auth = self.legacy / 'auth.json'
        legacy_auth_original = legacy_auth.read_bytes()
        legacy_auth.write_text('{"token":"mutated"}\n')
        retirement = self.run_migration('retire', confirm=True, status=1)
        self.assertIn('Legacy source changed', retirement.stderr)
        legacy_auth.write_bytes(legacy_auth_original)
        legacy_auth.chmod(0o600)

        writer = subprocess.Popen(['bash', '-c', f'exec -a "{self.legacy}/writer" sleep 30'], env=self.env)
        self.addCleanup(lambda: writer.poll() is not None or writer.kill())
        time.sleep(0.1)
        retirement = self.run_migration('retire', confirm=True, status=1)
        self.assertIn('active writers', retirement.stderr)
        writer.terminate()
        writer.wait(timeout=5)

        self.run_migration('retire', confirm=True)
        self.assertFalse(self.legacy.exists())
        self.assertEqual(session.read_text(), '{"message":"fixture"}\n')

    def test_conflicts_are_reported_before_transfer_effects(self):
        self.seed_legacy()
        external = self.home / 'omarchy/custom.ts'
        external.parent.mkdir(parents=True)
        external.write_text('custom external target\n')
        (self.legacy / 'extensions').mkdir()
        (self.legacy / 'extensions/custom.ts').symlink_to(external)
        (self.agent).mkdir(parents=True)
        (self.agent / 'auth.json').write_text('{}\n')
        herdr = self.home / '.config/herdr'
        herdr.mkdir(parents=True)
        (herdr / 'personal.db').write_text('personal\n')

        report = json.loads(self.run_migration('inspect').stdout)
        self.assertFalse(report['ready'])
        self.assertEqual(report['unknownExternalLinks'][0]['target'], str(external))
        reasons = '\n'.join(item['reason'] for item in report['conflicts'])
        self.assertIn('nonidentical', reasons)
        self.assertIn('Herdr', reasons)
        self.assertFalse(self.state.exists())
        prepare = self.run_migration('prepare', status=1)
        self.assertIn('conflicts must be resolved', prepare.stderr)
        self.assertEqual((self.agent / 'auth.json').read_text(), '{}\n')
        self.assertTrue((self.legacy / 'auth.json').exists())
        self.assertFalse((self.state / 'migration.json').exists())

    def test_quiescent_reverification_accepts_newer_destination_writes_for_retirement(self):
        self.seed_legacy()
        for phase, confirm in [('prepare', False), ('transfer', True), ('activate', True), ('verify', False)]:
            self.run_migration(phase, confirm)
        refreshed = '{"token":"refreshed-after-cutover"}\n'
        (self.agent / 'auth.json').write_text(refreshed)
        (self.sessions / 'nested/session.jsonl').write_text('{"message":"appended-after-cutover"}\n')
        self.run_migration('verify')
        self.run_migration('retire', confirm=True)
        self.assertEqual((self.agent / 'auth.json').read_text(), refreshed)
        self.assertIn('appended-after-cutover', (self.sessions / 'nested/session.jsonl').read_text())

    def test_source_mutation_after_preparation_blocks_transfer(self):
        self.seed_legacy()
        self.run_migration('prepare')
        (self.legacy / 'auth.json').write_text('{"token":"changed-after-prepare"}\n')
        blocked = self.run_migration('transfer', confirm=True, status=1)
        self.assertIn('Legacy source changed', blocked.stderr)
        self.assertFalse((self.agent / 'auth.json').exists())

    def test_destination_directory_mode_conflict_blocks_before_copy(self):
        self.legacy.mkdir(parents=True)
        source_directory = self.legacy / 'custom'
        source_directory.mkdir(mode=0o700)
        (source_directory / 'secret').write_text('secret\n')
        destination_directory = self.agent / 'custom'
        destination_directory.mkdir(parents=True, mode=0o755)
        blocked = self.run_migration('prepare', status=1)
        self.assertIn('directory mode', blocked.stderr.lower())
        self.assertFalse((destination_directory / 'secret').exists())

    def test_destination_parent_alias_cannot_collapse_source_and_destination(self):
        self.legacy.mkdir(parents=True)
        (self.legacy / 'auth.json').write_text('{"token":"synthetic"}\n')
        private = self.home / 'private'
        private.mkdir()
        (private / 'pi').symlink_to(self.home / '.pi')
        blocked = self.run_migration('prepare', status=1)
        self.assertIn('symlink', blocked.stderr.lower())
        self.assertTrue((self.legacy / 'auth.json').exists())

    def test_tampered_embedded_traversal_cannot_delete_unrelated_file(self):
        self.seed_legacy()
        for phase, confirm in [('prepare', False), ('transfer', True), ('activate', True), ('verify', False)]:
            self.run_migration(phase, confirm)
        victim = self.home / 'victim'
        victim.write_text('unrelated\n')
        journal_path = self.state / 'migration.json'
        journal = json.loads(journal_path.read_text())
        file_index = next(index for index, item in enumerate(journal['sourceInventory']) if item['type'] == 'file')
        journal['sourceInventory'][file_index]['path'] = 'x/../../../../../victim'
        journal_path.write_text(json.dumps(journal))
        blocked = self.run_migration('rollback', confirm=True, status=1)
        self.assertIn('malformed', blocked.stderr.lower())
        self.assertEqual(victim.read_text(), 'unrelated\n')

    def test_rollback_refuses_when_legacy_source_lost_its_last_copy(self):
        self.seed_legacy()
        for phase, confirm in [('prepare', False), ('transfer', True), ('activate', True)]:
            self.run_migration(phase, confirm)
        (self.legacy / 'auth.json').unlink()
        blocked = self.run_migration('rollback', confirm=True, status=1)
        self.assertIn('legacy source changed', blocked.stderr.lower())
        self.assertTrue((self.agent / 'auth.json').exists())

    def test_retirement_retry_rechecks_destination_before_source_deletion(self):
        self.seed_legacy()
        for phase, confirm in [('prepare', False), ('transfer', True), ('activate', True), ('verify', False)]:
            self.run_migration(phase, confirm)
        fault_env = dict(self.env, BOOTSTRAP_MIGRATION_TEST_ONLY='1',
                         BOOTSTRAP_MIGRATION_TEST_HOME=str(self.home),
                         BOOTSTRAP_MIGRATION_TEST_FAULT='retire-after-intent')
        interrupted = subprocess.run(['bash', str(ROOT / 'install.sh'), 'migration', 'retire', '--yes'],
                                     env=fault_env, capture_output=True, text=True, timeout=10)
        self.assertEqual(interrupted.returncode, 86, interrupted.stdout + interrupted.stderr)
        (self.agent / 'auth.json').unlink()
        blocked = self.run_migration('retire', confirm=True, status=1)
        self.assertIn('destination', blocked.stderr.lower())
        self.assertTrue((self.legacy / 'auth.json').exists())

    def test_legacy_node_hosted_pi_blocks_transfer(self):
        self.seed_legacy()
        self.run_migration('prepare')
        runtime = self.home / '.local/share/dotfiles/bare/node/bin'
        runtime.mkdir(parents=True)
        (runtime / 'node').symlink_to(shutil.which('node'))
        cli = self.home / '.local/share/dotfiles/bare/pi-coding-agent/dist/cli.js'
        cli.parent.mkdir(parents=True)
        cli.write_text('setInterval(() => {}, 1000);\n')
        writer = subprocess.Popen([runtime / 'node', cli], env=self.env)
        self.addCleanup(lambda: writer.poll() is not None or writer.kill())
        time.sleep(0.1)
        blocked = self.run_migration('transfer', confirm=True, status=1)
        self.assertIn('active writers', blocked.stderr)
        writer.terminate()
        writer.wait(timeout=5)

    def test_interrupted_rollback_resumes_from_before_or_after_states(self):
        self.seed_legacy()
        for phase, confirm in [('prepare', False), ('transfer', True), ('activate', True), ('verify', False)]:
            self.run_migration(phase, confirm)
        fault_env = dict(self.env, BOOTSTRAP_MIGRATION_TEST_ONLY='1',
                         BOOTSTRAP_MIGRATION_TEST_HOME=str(self.home),
                         BOOTSTRAP_MIGRATION_TEST_FAULT='rollback-after-activation-5')
        interrupted = subprocess.run(['bash', str(ROOT / 'install.sh'), 'migration', 'rollback', '--yes'],
                                     env=fault_env, capture_output=True, text=True, timeout=10)
        self.assertEqual(interrupted.returncode, 86, interrupted.stdout + interrupted.stderr)
        self.run_migration('rollback', confirm=True)
        journal = json.loads((self.state / 'migration.json').read_text())
        self.assertEqual(journal['phase'], 'rolled-back')

    def test_transfer_retry_and_clean_rollback_restore_previous_selection(self):
        self.seed_legacy()
        previous = self.home / ('cache/snapshots/' + 'c' * 40)
        (previous / 'scripts').mkdir(parents=True)
        shutil.copy2(ROOT / 'install.sh', previous / 'install.sh')
        (previous / 'install.sh').chmod(0o755)
        (previous / '.bootstrap-archive-sha256').write_text('d' * 64 + '\n')
        (previous / 'scripts/bare-env.sh').write_text('# previous\n')
        marker = self.home / '.config/dotfiles/bare-env.sh'
        marker.parent.mkdir(parents=True)
        marker.symlink_to(previous / 'scripts/bare-env.sh')

        self.run_migration('prepare')
        (self.agent / 'auth.json').parent.mkdir(parents=True)
        shutil.copy2(self.legacy / 'auth.json', self.agent / 'auth.json')
        self.run_migration('transfer', confirm=True)
        self.run_migration('activate', confirm=True)
        self.run_migration('verify')
        self.run_migration('rollback', confirm=True)
        self.assertEqual(marker.readlink(), previous / 'scripts/bare-env.sh')
        self.assertTrue(self.legacy.exists())
        self.assertFalse((self.agent / 'settings.json').exists())

    def test_configuration_after_retirement_preserves_migrated_customizations(self):
        self.seed_legacy()
        for phase, confirm in [('prepare', False), ('transfer', True), ('activate', True), ('verify', False), ('retire', True)]:
            self.run_migration(phase, confirm)
        result = subprocess.run(['bash', str(ROOT / 'configure.sh'), 'pi'], env=self.env,
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.agent / 'settings.json').read_text(), '{"theme":"custom","packages":[]}\n')
        self.assertEqual((self.agent / 'models.json').read_text(), '{"providers":{"synthetic":{}}}\n')
        self.assertEqual((self.agent / 'WORKTREE_STREAMS.md').read_text(), 'personal worktree modes\n')

    def test_missing_neovim_does_not_affect_personal_state_lifecycle(self):
        self.seed_legacy()
        self.assertFalse((self.home / '.config/nvim').exists())
        for phase, confirm in [('prepare', False), ('transfer', True), ('activate', True), ('verify', False)]:
            self.run_migration(phase, confirm)
        self.assertEqual((self.agent / 'settings.json').read_text(), '{"theme":"custom","packages":[]}\n')
        self.assertFalse((self.home / '.config/nvim').exists())


if __name__ == '__main__':
    unittest.main()
