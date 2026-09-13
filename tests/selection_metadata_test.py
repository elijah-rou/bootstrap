#!/usr/bin/env python3
"""Validate the persisted catalog-to-runtime projection without running an editor."""
import json
import os
import pathlib
import subprocess
import tempfile
import unittest

HELPER = pathlib.Path(__file__).resolve().parents[1] / 'scripts/state-helper.mjs'

class SelectionMetadataTest(unittest.TestCase):
    def test_projection_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            home = pathlib.Path(directory)
            env = dict(os.environ, HOME=directory, BOOTSTRAP_STATE_ROOT=str(home/'state'))
            def run(*args):
                return subprocess.run(['node', str(HELPER), *map(str, args)], env=env, capture_output=True, text=True)
            self.assertEqual(run('init').returncode, 0)
            self.assertEqual(run('select', 'lsp', 'fixture').returncode, 0)
            catalog, output = home/'catalog.json', home/'output.json'
            base = {'server': 'fixture', 'command': ['server'], 'filetypes': ['rust']}
            def project(extra):
                catalog.write_text(json.dumps({'schemaVersion': 1, 'lsp': {'fixture': dict(base, **extra)}}))
                return run('lsp-output', catalog, output)
            self.assertEqual(project({}).returncode, 0)
            self.assertEqual(json.loads(output.read_text())['servers']['fixture'], {'selector': 'fixture', 'cmd': ['server'], 'filetypes': ['rust']})
            for method in ['textDocument/documentSymbol', 'textDocument/diagnostic', 'workspace/symbol']:
                extra = {'root_markers': ['Cargo.toml', 'rust-project.json', '.git'], 'root_policy': 'rust-standalone', 'verification': {'method': method}}
                self.assertEqual(project(extra).returncode, 0)
                for key, value in extra.items():
                    self.assertEqual(json.loads(output.read_text())['servers']['fixture'][key], value)
            accepted = [['a'], ['a'*128], ['a']*16]
            for markers in accepted:
                self.assertEqual(project({'root_markers': markers}).returncode, 0)
            for key, values in {
                'root_markers': [None, True, 1, '', {}, [], ['a']*17, ['a'*129], [''], ['..'], ['.'], ['a/b'], ['a\n'], [None]],
                'root_policy': [None, True, 1, [], {}, '', 'unknown'],
                'verification': [None, True, 1, [], '', {}, {'method': None}, {'method': 1}, {'method': 'shutdown'}, {'method': 'workspace/executeCommand'}, {'method': 'workspace/symbol', 'params': {}}],
            }.items():
                for value in values:
                    with self.subTest(key=key, value=value):
                        self.assertNotEqual(project({key: value}).returncode, 0)

if __name__ == '__main__':
    unittest.main()
