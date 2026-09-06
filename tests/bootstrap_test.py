#!/usr/bin/env python3
"""Exercise the public downloader without network or package installation."""
import hashlib
import io
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'bootstrap.sh').read_text()
REVISION = re.search(r"^REVISION='([0-9a-f]{40})'$", SOURCE, re.M).group(1)

class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='bootstrap-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cache = self.root / 'cache with spaces'
        self.snapshot = self.cache / 'snapshots' / REVISION
        self.archive = self.root / 'source.tar.gz'
        installer = b'#!/bin/sh\nprintf "%s\\n" "$@" >> "$HOME/installed"\nexit "${INSTALL_STATUS:-0}"\n'
        with tarfile.open(self.archive, 'w:gz') as archive:
            entry = tarfile.TarInfo('bootstrap-source/install.sh')
            entry.mode, entry.size = 0o755, len(installer)
            archive.addfile(entry, io.BytesIO(installer))
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.script = self.root / 'bootstrap.sh'
        self.script.write_text(re.sub(r"^ARCHIVE_SHA256='[0-9a-f]{64}'$", f"ARCHIVE_SHA256='{digest}'", SOURCE, flags=re.M))
        binary = self.root / 'bin'; binary.mkdir()
        curl = binary / 'curl'
        curl.write_text('''#!/bin/sh
printf 'curl\\n' >> "$HOME/downloads"
[ "${CURL_STATUS:-0}" = 0 ] || exit "$CURL_STATUS"
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then shift; cp "$FIXTURE_ARCHIVE" "$1"; exit; fi
  shift
done
exit 1
''')
        curl.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.root), BOOTSTRAP_ROOT=str(self.cache),
                        PATH=f'{binary}:{os.environ["PATH"]}', FIXTURE_ARCHIVE=str(self.archive))

    def run_bootstrap(self, *args, status=0):
        result = subprocess.run(['bash', str(self.script), *args], env=self.env, text=True,
                                capture_output=True, timeout=10)
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        return result

    def test_fetch_retry_and_dispatch(self):
        result = self.run_bootstrap('fetch')
        self.assertEqual(result.stdout.strip(), str(self.snapshot))
        self.assertFalse((self.root / 'installed').exists())
        self.run_bootstrap('fetch')
        self.run_bootstrap()
        self.run_bootstrap('languages', 'c', 'cpp', 'rust', 'go', 'python', 'typescript', 'bash', 'elixir', 'zig')
        self.run_bootstrap('doctor')
        self.assertEqual((self.root / 'downloads').read_text(), 'curl\n')
        self.assertEqual((self.root / 'installed').read_text(), 'install\nlanguages\nc\ncpp\nrust\ngo\npython\ntypescript\nbash\nelixir\nzig\ndoctor\n')
        self.env['INSTALL_STATUS'] = '17'
        self.run_bootstrap(status=17)
        self.assertFalse((self.cache / 'install.lock').exists())
        self.assertFalse(list(self.cache.glob('stage.*')))

    def test_failures_preserve_state(self):
        self.env['CURL_STATUS'] = '22'
        self.run_bootstrap('fetch', status=22)
        self.assertFalse(self.snapshot.exists())
        del self.env['CURL_STATUS']
        self.archive.write_bytes(b'corrupt archive')
        result = self.run_bootstrap('fetch', status=1)
        self.assertIn('checksum mismatch', result.stderr)
        self.assertFalse(self.snapshot.exists())
        self.assertFalse((self.cache / 'install.lock').exists())
        self.assertFalse(list(self.cache.glob('stage.*')))

    def test_missing_and_unowned_cache(self):
        for command in ['doctor', 'link', 'codex-link']:
            self.run_bootstrap(command, status=1)
            self.assertFalse(self.cache.exists())
        self.snapshot.mkdir(parents=True)
        marker = self.snapshot / 'keep'; marker.write_text('personal')
        self.run_bootstrap('fetch', status=1)
        self.assertEqual(marker.read_text(), 'personal')
        self.assertFalse((self.root / 'downloads').exists())
        lock = self.cache / 'install.lock'; lock.mkdir()
        self.run_bootstrap('fetch', status=1)
        self.assertTrue(lock.is_dir())

    def test_rejects_arguments_before_writes(self):
        for args in [('unknown',), ('install', '--bad'), ('languages',), ('languages', 'rust', 'unknown')]:
            self.run_bootstrap(*args, status=2)
            self.assertFalse(self.cache.exists())
        self.run_bootstrap('--help')
        self.assertFalse(self.cache.exists())
        self.env['BOOTSTRAP_ROOT'] = 'relative'
        self.run_bootstrap('fetch', status=2)

if __name__ == '__main__':
    unittest.main()
