#!/usr/bin/env python3
"""Release pin evidence comes from a full local commit and matching archive."""
import hashlib
import io
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
REVISION = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()


class ReleasePinTest(unittest.TestCase):
    def run_pin(self, revision, archive):
        return subprocess.run(['node', str(ROOT / 'scripts/release-pin.mjs'), revision, str(archive)],
                              cwd=ROOT, capture_output=True, text=True, timeout=10)

    def test_reports_digest_for_exact_full_revision_archive(self):
        with tempfile.TemporaryDirectory(prefix='release-pin-') as directory:
            archive = Path(directory) / 'source.tar.gz'
            payload = b'fixture\n'
            with tarfile.open(archive, 'w:gz') as output:
                entry = tarfile.TarInfo(f'bootstrap-{REVISION}/install.sh')
                entry.mode = 0o755
                entry.size = len(payload)
                output.addfile(entry, io.BytesIO(payload))
            result = self.run_pin(REVISION, archive)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(hashlib.sha256(archive.read_bytes()).hexdigest(), result.stdout)
            self.assertIn(REVISION, result.stdout)

    def test_rejects_short_unknown_and_mismatched_revisions(self):
        with tempfile.TemporaryDirectory(prefix='release-pin-reject-') as directory:
            archive = Path(directory) / 'source.tar.gz'
            with tarfile.open(archive, 'w:gz') as output:
                entry = tarfile.TarInfo('bootstrap-not-the-revision/install.sh')
                entry.size = 0
                output.addfile(entry, io.BytesIO())
            self.assertEqual(self.run_pin(REVISION[:12], archive).returncode, 2)
            self.assertNotEqual(self.run_pin('f' * 40, archive).returncode, 0)
            self.assertNotEqual(self.run_pin(REVISION, archive).returncode, 0)


if __name__ == '__main__':
    unittest.main()
