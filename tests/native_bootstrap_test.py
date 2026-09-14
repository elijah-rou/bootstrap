#!/usr/bin/env python3
import json, os, pathlib, subprocess, tempfile, time, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / 'scripts/state-helper.mjs'

class OwnershipTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        root = pathlib.Path(self.temp.name); self.home = root/'home'; self.home.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), XDG_STATE_HOME=str(self.home/'.local/state'))
        self.state = self.home/'.local/state/bootstrap'
    def execute(self,*args,ok=True):
        result=subprocess.run(['node',str(HELPER),*map(str,args)],env=self.env,text=True,capture_output=True)
        self.assertEqual(result.returncode==0,ok,result.stdout+result.stderr); return result
    def test_install_preview_uninstall_retry_and_sensitive_cleanup(self):
        unrelated=self.home/'unrelated'; unrelated.write_text('keep')
        shared=self.home/'.bashrc'; shared.write_text('original')
        self.execute('init'); self.execute('prepare',shared,'shared',str(ROOT/'bashrc'))
        shared.unlink(); shared.symlink_to(ROOT/'bashrc'); self.execute('activate',shared)
        private=self.home/'.local/share/bootstrap/private'; private.mkdir(parents=True)
        for name in ['credentials/auth.json','sessions/live.json','projects/enrolled/secret','cache/token','backups/auth.copy']:
            path=private/name; path.parent.mkdir(parents=True,exist_ok=True); path.write_text('sensitive')
        self.execute('enroll',private); self.execute('select','languages','rust'); self.execute('select','lsp','basedpyright')
        self.execute('package','apt','git','1','2.0','installed'); self.execute('package','apt','jq','0','1.0','installed'); self.execute('ready')
        preview=self.execute('uninstall','--dry-run').stdout
        self.assertIn(f'delete-owned\t{private}',preview); self.assertIn('remove-package\tapt\tjq',preview); self.assertNotIn('remove-package\tapt\tgit',preview)
        self.assertTrue(private.exists()); self.assertTrue(shared.is_symlink()); self.assertEqual(unrelated.read_text(),'keep')
        self.execute('uninstall'); self.assertFalse(private.exists()); self.assertFalse(shared.is_symlink()); self.assertEqual(shared.read_text(),'original'); self.assertEqual(unrelated.read_text(),'keep')
        self.execute('package-removed','apt','jq'); self.execute('finish-uninstall'); self.assertFalse(self.state.exists())
    def test_escape_malformed_and_conflict_are_rejected(self):
        outside=pathlib.Path(self.temp.name)/'outside'; outside.write_text('keep')
        self.execute('init'); self.execute('enroll',outside,ok=False)
        escaped=self.home/'escaped'; escaped.symlink_to(pathlib.Path(self.temp.name)); self.execute('prepare',escaped/'target','shared','x',ok=False)
        target=self.home/'.bashrc'; self.execute('prepare',target,'shared',str(ROOT/'bashrc')); target.symlink_to(ROOT/'bashrc'); self.execute('activate',target); target.unlink(); target.write_text('user edit')
        self.execute('uninstall',ok=False); self.assertEqual(target.read_text(),'user edit')
        record=json.loads((self.state/'install.json').read_text()); record['schemaVersion']=999; (self.state/'install.json').write_text(json.dumps(record)); self.execute('validate',ok=False)

    def test_package_identity_rejects_options_duplicates_and_malformed_flags(self):
        self.execute('init'); self.execute('package','apt','fixture','0','absent','installed')
        path=self.state/'install.json'; original=json.loads(path.read_text())
        for field, values in {
            'backend': [None, '', 'unknown', 1, []],
            'name': [None, '', '--nodeps', 'bad\nname', 'a'*193, 1, []],
            'preexisting': [None, 'false', 0, 1, [], {}],
            'installed': [None, 'true', 0, 1, [], {}],
            'priorVersion': [None, 1, [], {}],
        }.items():
            for value in values:
                with self.subTest(field=field,value=value):
                    record=json.loads(json.dumps(original)); record['packages'][0][field]=value; path.write_text(json.dumps(record)); self.execute('validate',ok=False)
            record=json.loads(json.dumps(original)); del record['packages'][0][field]; path.write_text(json.dumps(record)); self.execute('validate',ok=False)
        record=json.loads(json.dumps(original)); record['packages']*=2; path.write_text(json.dumps(record)); self.execute('validate',ok=False)

if __name__=='__main__': unittest.main()
