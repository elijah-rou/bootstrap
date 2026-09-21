#!/usr/bin/env python3
"""Synthetic legacy-to-owned migration lifecycle and recovery checks."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_FIXTURE = os.environ.get('BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')


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
        if phase == 'prepare':
            args = ['node', str(ROOT / 'scripts/migration-helper.mjs'), 'prepare']
        for attempt in range(5):
            result = subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=120)
            if 'Writer disappeared during identity check' not in result.stderr:
                break
            time.sleep(0.1)
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        if phase == 'prepare' and status == 0:
            subprocess.run(['node', str(ROOT / 'scripts/state-helper.mjs'), 'init'], env=self.env, check=True)
            if RUNTIME_FIXTURE:
                self.stage_real_runtime()
        if phase == 'activate' and status == 0:
            self.assertEqual((self.home / '.local/bin/pih').readlink(), ROOT / 'scripts/pi-headroom')
        return result

    def stage_real_runtime(self):
        fixture = Path(RUNTIME_FIXTURE) / 'home'
        for source, target in [(fixture / 'tools', self.home / 'tools'),
                               (fixture / '.data/bootstrap-nvim', self.home / '.data/bootstrap-nvim'),
                               (fixture / 'private/neovim/config', self.home / 'private/neovim/config')]:
            shutil.copytree(source, target, symlinks=True, dirs_exist_ok=True)
        staging = self.home / 'private/neovim/staged-config/bootstrap-nvim'
        staging.parent.mkdir(parents=True, exist_ok=True)
        staging.symlink_to(self.home / 'private/neovim/config')
        for root in [self.home / 'tools', self.home / 'private', self.home / '.data/bootstrap-nvim']:
            subprocess.run(['node', str(ROOT / 'scripts/state-helper.mjs'), 'enroll', str(root)], env=self.env, check=True)
        verified = subprocess.run(['bash', str(ROOT / 'scripts/migration-runtime'), 'verify'],
                                  env=self.env, capture_output=True, text=True, timeout=120)
        self.assertEqual(verified.returncode, 0, verified.stdout + verified.stderr)

    def test_readiness_rejects_legacy_only_command_path(self):
        self.seed_legacy()
        self.run_migration('prepare')
        legacy = self.home / '.local/share/dotfiles/bare/bin'
        infrastructure = self.home / 'infrastructure'
        legacy.mkdir(parents=True)
        infrastructure.mkdir()
        catalog = json.loads((ROOT / 'packages/catalog.json').read_text())
        for name in {catalog['packages'][key]['executable'] for key in catalog['core']} | {'herdr'}:
            executable = shutil.which(name)
            self.assertIsNotNone(executable)
            (legacy / name).symlink_to(executable)
        for name in ['node', 'bash', 'dirname']:
            (infrastructure / name).symlink_to(shutil.which(name))
        result = subprocess.run(['/bin/bash', str(ROOT / 'scripts/migration-runtime'), 'verify'],
                                env=dict(self.env, PATH=f'{legacy}:{infrastructure}'), capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Migration runtime missing', result.stderr)
        self.assertFalse((self.home / '.config/dotfiles/bare-env.sh').exists())

    def test_restoration_interruption_keeps_active_target_and_retries(self):
        self.seed_legacy()
        login = self.home / '.bash_profile'
        login.write_text('export ORIGINAL=kept\n')
        for phase in ['prepare', 'transfer', 'activate', 'verify']:
            self.run_migration(phase, phase in ['transfer', 'activate'])
        active = login.read_bytes()
        self.env.update(BOOTSTRAP_MIGRATION_TEST_ONLY='1', BOOTSTRAP_MIGRATION_TEST_HOME=str(self.home),
                        BOOTSTRAP_MIGRATION_TEST_FAULT='restore-before-rename')
        self.run_migration('rollback', True, status=86)
        self.assertEqual(login.read_bytes(), active)
        self.env.pop('BOOTSTRAP_MIGRATION_TEST_FAULT')
        self.run_migration('rollback', True)
        self.assertEqual(login.read_text(), 'export ORIGINAL=kept\n')
        self.assertEqual(list(self.home.glob('.bootstrap-restore-*')), [])

    def test_login_profile_edits_block_uninstall_preview(self):
        self.seed_legacy()
        for phase in ['prepare', 'transfer', 'activate', 'verify']:
            self.run_migration(phase, phase in ['transfer', 'activate'])
        login = self.home / '.bash_profile'
        self.assertFalse(login.is_symlink())
        login.write_text(login.read_text() + 'export NEW_PERSONAL=value\n')
        result = subprocess.run(['node', str(ROOT / 'scripts/state-helper.mjs'), 'uninstall', '--dry-run'],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('NEW_PERSONAL=value', login.read_text())
        self.assertTrue((self.agent / 'auth.json').is_file())

    def test_rollback_retry_refuses_substituted_descendant_directory(self):
        self.seed_legacy()
        for phase in ['prepare', 'transfer', 'activate', 'verify']:
            self.run_migration(phase, phase in ['transfer', 'activate'])
        self.env.update(BOOTSTRAP_MIGRATION_TEST_ONLY='1', BOOTSTRAP_MIGRATION_TEST_HOME=str(self.home),
                        BOOTSTRAP_MIGRATION_TEST_FAULT='rollback-after-intent')
        self.run_migration('rollback', True, status=86)
        self.env.pop('BOOTSTRAP_MIGRATION_TEST_FAULT')
        source = self.agent / 'skills/custom-skill'
        outside = self.home / 'unrelated'
        shutil.copytree(source, outside)
        shutil.rmtree(source)
        source.symlink_to(outside, target_is_directory=True)
        self.run_migration('rollback', True, status=1)
        self.assertEqual((outside / 'SKILL.md').read_text(), 'synthetic custom skill\n')

    def test_rollback_retry_preserves_new_file_at_restored_target(self):
        self.seed_legacy()
        for phase in ['prepare', 'transfer', 'activate', 'verify']:
            self.run_migration(phase, phase in ['transfer', 'activate'])
        self.env.update(BOOTSTRAP_MIGRATION_TEST_ONLY='1', BOOTSTRAP_MIGRATION_TEST_HOME=str(self.home),
                        BOOTSTRAP_MIGRATION_TEST_FAULT='rollback-after-activation-0')
        self.run_migration('rollback', True, status=86)
        self.env.pop('BOOTSTRAP_MIGRATION_TEST_FAULT')
        target = self.home / '.bashrc'
        self.assertFalse(target.exists())
        target.write_text('new personal configuration\n')
        self.run_migration('rollback', True, status=1)
        self.assertEqual(target.read_text(), 'new personal configuration\n')

    def test_rollback_rejects_migration_original_target_override(self):
        self.seed_legacy()
        for phase in ['prepare', 'transfer', 'activate', 'verify']:
            self.run_migration(phase, phase in ['transfer', 'activate'])
        victim = self.home / 'unrelated-victim'
        victim.write_text('preserve\n')
        path = self.state / 'install.json'
        record = json.loads(path.read_text())
        item = next(item for item in record['resources'] if item.get('migrationBefore', {}).get('priorType') == 'absent')
        item['migrationBefore'].update(target=str(victim), **{'class': 'owned'})
        path.write_text(json.dumps(record))
        self.run_migration('rollback', True, status=1)
        self.assertEqual(victim.read_text(), 'preserve\n')

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

    @unittest.skipUnless(RUNTIME_FIXTURE, 'requires cold real BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')
    def test_full_transfer_activation_and_retirement_preserve_personal_state(self):
        self.seed_legacy()
        old_tool = self.home / '.local/share/dotfiles/bare/user-addition'
        old_tool.parent.mkdir(parents=True)
        old_tool.write_text('unrelated old tool\n')
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

        self.run_migration('activate', confirm=True)
        self.run_migration('activate', confirm=True)
        self.assertEqual((self.home / '.config/dotfiles/bare-env.sh').readlink(), ROOT / 'scripts/bare-env.sh')
        launched = subprocess.run([self.home / '.local/bin/pi', '--version'], env=self.env,
                                  capture_output=True, text=True, check=True).stdout.splitlines()
        self.assertEqual(launched, ['0.85.1'])
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
        self.assertEqual(old_tool.read_text(), 'unrelated old tool\n')

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
        self.assertIn(str(herdr), report['enrollmentOnTransfer'])
        self.assertFalse(self.state.exists())
        prepare = self.run_migration('prepare', status=1)
        self.assertIn('conflicts must be resolved', prepare.stderr)
        self.assertEqual((self.agent / 'auth.json').read_text(), '{}\n')
        self.assertTrue((self.legacy / 'auth.json').exists())
        self.assertFalse((self.state / 'migration.json').exists())

    @unittest.skipUnless(RUNTIME_FIXTURE, 'requires cold real BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')
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

    @unittest.skipUnless(RUNTIME_FIXTURE, 'requires cold real BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')
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

    @unittest.skipUnless(RUNTIME_FIXTURE, 'requires cold real BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')
    def test_rollback_refuses_when_legacy_source_lost_its_last_copy(self):
        self.seed_legacy()
        for phase, confirm in [('prepare', False), ('transfer', True), ('activate', True)]:
            self.run_migration(phase, confirm)
        (self.legacy / 'auth.json').unlink()
        blocked = self.run_migration('rollback', confirm=True, status=1)
        self.assertIn('legacy source changed', blocked.stderr.lower())
        self.assertTrue((self.agent / 'auth.json').exists())

    @unittest.skipUnless(RUNTIME_FIXTURE, 'requires cold real BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')
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

    @unittest.skipUnless(RUNTIME_FIXTURE, 'requires cold real BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')
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

    @unittest.skipUnless(RUNTIME_FIXTURE, 'requires cold real BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')
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
        (self.agent / 'auth.json').parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(self.legacy / 'auth.json', self.agent / 'auth.json')
        self.run_migration('transfer', confirm=True)
        self.run_migration('activate', confirm=True)
        self.run_migration('verify')
        self.run_migration('rollback', confirm=True)
        self.assertEqual(marker.readlink(), previous / 'scripts/bare-env.sh')
        self.assertTrue(self.legacy.exists())
        self.assertFalse((self.agent / 'settings.json').exists())

    @unittest.skipUnless(RUNTIME_FIXTURE, 'requires cold real BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')
    def test_configuration_after_retirement_preserves_migrated_customizations(self):
        self.seed_legacy()
        for phase, confirm in [('prepare', False), ('transfer', True), ('activate', True), ('verify', False), ('retire', True)]:
            self.run_migration(phase, confirm)
        result = subprocess.run(['bash', str(ROOT / 'configure.sh'), 'pi'], env=self.env,
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        updater = subprocess.run(['bash', '-c', 'source "$1/scripts/bare-env.sh"; exec node "$1/scripts/verify-pi-package-manager.mjs"', 'test', str(ROOT)],
                                 env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(updater.returncode, 0, updater.stdout + updater.stderr)
        self.assertEqual((self.agent / 'settings.json').read_text(), '{"theme":"custom","packages":[]}\n')
        self.assertEqual((self.agent / 'models.json').read_text(), '{"providers":{"synthetic":{}}}\n')
        self.assertEqual((self.agent / 'WORKTREE_STREAMS.md').read_text(), 'personal worktree modes\n')

    @unittest.skipUnless(RUNTIME_FIXTURE, 'requires cold real BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')
    def test_public_prepare_stages_real_runtime_without_switching_profiles(self):
        self.seed_legacy()
        editor = self.home / '.config/nvim'
        editor.mkdir(parents=True)
        (editor / 'init.lua').symlink_to(ROOT / 'neovim/config/init.lua')
        seeds = {}
        for name in ['lazy-lock.json', 'lazyvim.json', '.neoconf.json']:
            value = json.loads((ROOT / 'neovim/defaults' / name).read_text())
            if name != 'lazy-lock.json':
                value['personalMarker'] = 'preserved'
            seeds[name] = json.dumps(value) + '\n'
            (editor / name).write_text(seeds[name])
        self.run_migration('prepare')
        original = (self.legacy / 'settings.json').read_bytes()
        result = subprocess.run(['bash', str(ROOT / 'install.sh'), 'migration', 'prepare'],
                                env=self.env, capture_output=True, text=True, timeout=900)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        readiness = json.loads(self.run_migration('readiness').stdout)
        self.assertTrue(readiness['ready'])
        self.assertEqual(readiness['phase'], 'prepared')
        self.assertEqual(readiness['profiles']['neovim'], str(self.home / 'private/neovim/config'))
        for target in ['.config/dotfiles/bare-env.sh', '.config/bootstrap-nvim', '.local/bin/pi',
                       '.local/bin/pih', '.bashrc', '.zshenv', '.bash_profile']:
            self.assertFalse((self.home / target).exists(), target)
        self.assertEqual((self.legacy / 'settings.json').read_bytes(), original)
        for name, content in seeds.items():
            self.assertEqual((self.home / 'private/neovim/config' / name).read_text(), content)
            self.assertEqual((editor / name).read_text(), content)
        self.assertFalse((self.agent / 'settings.json').exists())
        record = json.loads((self.state / 'install.json').read_text())
        self.assertEqual(record['packages'], [], 'fixture must not install native packages on the host')

    @unittest.skipUnless(RUNTIME_FIXTURE, 'requires cold real BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')
    def test_removed_owned_cli_or_missing_actual_neovim_blocks_activation(self):
        self.seed_legacy()
        self.run_migration('prepare')
        self.run_migration('transfer', True)
        cli = self.home / 'tools/bun/install/global/node_modules/@earendil-works/pi-coding-agent/dist/cli.js'
        saved = cli.with_suffix('.saved')
        cli.rename(saved)
        blocked = self.run_migration('activate', True, status=1)
        self.assertIn('owned Pi CLI is missing', blocked.stderr)
        saved.rename(cli)
        (self.home / 'private/neovim/config/init.lua').unlink()
        blocked = self.run_migration('activate', True, status=1)
        self.assertIn('Neovim config missing', blocked.stderr)
        self.assertFalse((self.home / '.config/dotfiles/bare-env.sh').exists())
        self.assertFalse((self.home / '.local/bin/pih').exists())

    @unittest.skipUnless(RUNTIME_FIXTURE, 'requires cold real BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')
    def test_gh_continuity_and_herdr_supported_root_enrollment(self):
        self.seed_legacy()
        gh = self.home / '.config/gh'
        gh.mkdir(parents=True)
        (gh / 'hosts.yml').write_text('github.com:\n  oauth_token: synthetic\n')
        (gh / 'hosts.yml').chmod(0o600)
        herdr = self.home / '.config/herdr'
        herdr.mkdir()
        (herdr / 'personal.db').write_bytes(b'synthetic database')
        report = json.loads(self.run_migration('inspect').stdout)
        self.assertTrue(report['ready'])
        self.assertIn(str(herdr), report['enrollmentOnTransfer'])
        self.run_migration('prepare')
        self.assertFalse((self.home / 'private/gh/hosts.yml').exists())
        self.run_migration('transfer', True)
        self.run_migration('activate', True)
        migrated = self.home / 'private/gh/hosts.yml'
        self.assertEqual(migrated.read_bytes(), (gh / 'hosts.yml').read_bytes())
        self.assertEqual(migrated.stat().st_mode & 0o777, 0o600)
        self.assertEqual((herdr / 'personal.db').read_bytes(), b'synthetic database')
        record = json.loads((self.state / 'install.json').read_text())
        self.assertIn(str(herdr), record['enrolledRoots'])
        migrated.write_text('github.com:\n  oauth_token: refreshed\n')
        # An activated shell exports the destination, not the old source. The journal retains the old identity.
        self.env['GH_CONFIG_DIR'] = str(migrated.parent)
        self.run_migration('verify')
        self.run_migration('retire', True)
        self.assertIn('refreshed', migrated.read_text())
        self.assertTrue(gh.exists(), 'GH legacy retirement is separately operator-owned')

    @unittest.skipUnless(RUNTIME_FIXTURE, 'requires cold real BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE')
    def test_uninstall_restores_pre_migration_originals_after_new_writes(self):
        self.seed_legacy()
        old = self.home / ('cache/snapshots/' + 'a' * 40)
        (old / 'scripts').mkdir()
        (old / 'scripts/pi-headroom').write_text('# old launcher\n')
        (old / 'bashrc').write_text('mamba activate legacy\n')
        pih = self.home / '.local/bin/pih'
        pih.parent.mkdir(parents=True)
        pih.symlink_to(old / 'scripts/pi-headroom')
        bashrc = self.home / '.bashrc'
        bashrc.symlink_to(old / 'bashrc')
        login = self.home / '.bash_profile'
        login.write_text('export PERSONAL=value\n')
        for phase, confirm in [('prepare', False), ('transfer', True), ('activate', True)]:
            self.run_migration(phase, confirm)
        self.assertNotIn('mamba', bashrc.read_text())
        self.assertIn('PERSONAL=value', login.read_text())
        (self.agent / 'auth.json').write_text('{"token":"refreshed"}\n')
        self.run_migration('verify')
        adopted = subprocess.run(['node', str(ROOT / 'scripts/migration-helper.mjs'), 'allows-adoption'],
                                 env=self.env, capture_output=True, text=True)
        self.assertEqual(adopted.returncode, 0, adopted.stderr)
        removed = subprocess.run(['node', str(ROOT / 'scripts/state-helper.mjs'), 'uninstall'],
                                 env=self.env, capture_output=True, text=True)
        self.assertEqual(removed.returncode, 0, removed.stdout + removed.stderr)
        self.assertEqual(pih.readlink(), old / 'scripts/pi-headroom')
        self.assertEqual(bashrc.readlink(), old / 'bashrc')
        self.assertFalse(login.is_symlink())
        self.assertEqual(login.read_text(), 'export PERSONAL=value\n')
        subprocess.run(['node', str(ROOT / 'scripts/state-helper.mjs'), 'finish-uninstall'], env=self.env, check=True)
        self.assertFalse(self.state.exists())
        self.assertTrue((self.legacy / 'auth.json').exists())

    def test_unresolved_shell_and_external_neovim_block_before_preparation(self):
        self.seed_legacy()
        (self.home / '.bashrc').write_text('mamba activate personal\n')
        self.env['NVIM_CONFIG_CHECKOUT_DIR'] = str(self.home / 'custom-editor')
        report = json.loads(self.run_migration('inspect').stdout)
        self.assertFalse(report['ready'])
        reasons = '\n'.join(item['reason'] for item in report['conflicts'])
        self.assertIn('External Neovim', reasons)
        self.assertTrue(any(item['path'] == str(self.home / '.bashrc') for item in report['conflicts']))
        self.run_migration('prepare', status=1)
        self.assertFalse((self.state / 'install.json').exists())

    def test_migration_requires_operator_to_stop_herdr(self):
        self.seed_legacy()
        root = self.home / '.config/herdr'
        root.mkdir(parents=True)
        with socket.socket(socket.AF_UNIX) as server:
            previous = Path.cwd()
            try:
                os.chdir(root)
                server.bind('herdr.sock')
            finally:
                os.chdir(previous)
            blocked = self.run_migration('transfer', True, status=1)
            self.assertIn('stop Herdr explicitly', blocked.stderr)
            self.assertTrue((root / 'herdr.sock').is_socket())
            self.assertFalse((self.agent / 'auth.json').exists())

    def test_gh_conflict_blocks_before_pi_or_gh_transfer(self):
        self.seed_legacy()
        gh = self.home / '.config/gh'
        gh.mkdir(parents=True)
        (gh / 'hosts.yml').write_text('source\n')
        destination = self.home / 'private/gh'
        destination.mkdir(parents=True)
        (destination / 'hosts.yml').write_text('distinct\n')
        self.run_migration('prepare', status=1)
        self.assertEqual((destination / 'hosts.yml').read_text(), 'distinct\n')
        self.assertFalse((self.agent / 'auth.json').exists())

    def test_activation_requires_real_prepared_runtime_before_any_cutover(self):
        self.seed_legacy()
        subprocess.run(['node', str(ROOT / 'scripts/state-helper.mjs'), 'init'], env=self.env, check=True)
        for phase in ['prepare', 'transfer']:
            result = subprocess.run(['node', str(ROOT / 'scripts/migration-helper.mjs'), phase],
                                    env=self.env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        blocked = self.run_migration('activate', confirm=True, status=1)
        self.assertIn('runtime', blocked.stderr.lower())
        self.assertFalse((self.home / '.config/dotfiles/bare-env.sh').exists())
        self.assertFalse((self.home / '.local/bin/pi').exists())
        self.assertFalse((self.home / '.config/bootstrap-nvim').exists())


if __name__ == '__main__':
    unittest.main()
