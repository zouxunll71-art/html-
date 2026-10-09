"""Synthetic temporary files only: never touch a real Workspace or project."""
import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import os
import stat
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('snapshots', ROOT / 'scripts/current_workbench_snapshot.py')
snapshots = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshots)


class SnapshotSafety(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_paths_and_symlinks_cannot_escape(self):
        file = self.root / 'data'
        file.write_bytes(b'original')
        link = self.root / 'link'
        link.symlink_to(file)
        with self.assertRaises(ValueError): snapshots.fingerprint(link)
        with self.assertRaises(ValueError): snapshots.within(self.root, '../outside')

    def test_normalization_only_removes_diagnostic_location_and_derived_hash(self):
        a = {'hash': 'old', 'pages': {'home': {'source': {'file': '/original/pages/home.html'}, 'x': 24}}, 'assets': []}
        b = {'hash': 'new', 'pages': {'home': {'source': {'file': '/copy/pages/home.html'}, 'x': 24}}, 'assets': []}
        self.assertEqual(snapshots.normalized_model(a, '/original'), snapshots.normalized_model(b, '/copy'))
        b['pages']['home']['x'] = 25
        self.assertNotEqual(snapshots.normalized_model(a, '/original'), snapshots.normalized_model(b, '/copy'))
        self.assertEqual(a['hash'], 'old')

    @unittest.skipUnless(sys.platform == 'darwin', 'APFS clonefile is a macOS staging requirement')
    def test_clone_is_a_distinct_inode_and_chmod_or_write_cannot_change_origin(self):
        original, cloned = self.root / 'original', self.root / 'copy'
        original.write_bytes(b'original-resource-bytes')
        os.chmod(original, 0o640)
        proof = snapshots.fingerprint(original)
        snapshots.clone_independent(original, cloned, proof)
        self.assertNotEqual(original.stat().st_ino, cloned.stat().st_ino)
        self.assertEqual(stat.S_IMODE(original.stat().st_mode), 0o640)
        self.assertEqual(stat.S_IMODE(cloned.stat().st_mode), 0o400)
        cloned.chmod(0o600)
        cloned.write_bytes(b'changed-fixture-only')
        self.assertEqual(snapshots.fingerprint(original)['sha256'], proof['sha256'])
        self.assertEqual(original.read_bytes(), b'original-resource-bytes')

    def test_stale_audit_stops_before_any_clone(self):
        original, cloned = self.root / 'original', self.root / 'copy'
        original.write_bytes(b'first')
        proof = snapshots.fingerprint(original)
        original.write_bytes(b'newer')
        with self.assertRaises(ValueError): snapshots.clone_independent(original, cloned, proof)
        self.assertFalse(cloned.exists())

    @unittest.skipUnless(sys.platform == 'darwin', 'APFS clonefile is a macOS staging requirement')
    def test_materialization_preserves_sessions_and_original_record_without_registration(self):
        original_root = snapshots.ROOT
        snapshots.ROOT = self.root
        self.addCleanup(setattr, snapshots, 'ROOT', original_root)
        source = self.root / 'original-source'
        source.mkdir()
        (source / 'app.json').write_text('{"synthetic":true}')
        source_file = {**snapshots.fingerprint(source / 'app.json'), 'relative': 'app.json'}
        original = {'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'source': str(source), 'model': {'hash': 'old', 'name': 'Synthetic', 'assets': [], 'pages': {'home': {'source': {'file': str(source / 'page.html')}}}}, 'sessions': {'ios': {'state': {'draft': 'preserve'}, 'stack': [{'page': 'home'}]}, 'web': {'state': {'draft': 'independent'}}}, 'overrides': {'node': {'patch': {'x': 15}}}, 'additions': {'home': [{'id': 'added'}]}, 'localNavigationReceipts': [{'eventID': 'old-identity'}]}
        file = self.root / 'original-record.json'
        raw = json.dumps(original).encode()
        file.write_bytes(raw)
        (self.root / 'artifacts').mkdir()
        project = {'id': original['id'], 'name': 'Synthetic', 'record': snapshots.fingerprint(file), 'registeredSource': str(source), 'originalProjectRoot': str(source), 'eligibleSource': str(source), 'cachedFiles': [], 'paintings': [], 'sourceCandidates': [{'path': str(source), 'inputFiles': [source_file]}]}
        audit = self.root / 'audit.json'
        audit.write_text(json.dumps({'engineRoot': str(self.root / 'engine'), 'projects': [project]}))
        dest = self.root / 'artifacts' / 'snapshot'
        with contextlib.redirect_stdout(io.StringIO()):
            snapshots.materialize(argparse.Namespace(audit=audit, name=['Synthetic'], destination=dest))
        manifest = json.loads((dest / 'fixtures.json').read_text())
        self.assertFalse(manifest['registered'])
        self.assertFalse(manifest['activated'])
        row = manifest['projects'][0]
        staged = json.loads((Path(row['workspace']) / 'record.json').read_text())
        self.assertNotEqual(staged['id'], original['id'])
        self.assertEqual(staged['sessions'], original['sessions'])
        self.assertEqual(staged['overrides'], original['overrides'])
        self.assertEqual(staged['additions'], original['additions'])
        self.assertNotIn('localNavigationReceipts', staged)
        self.assertEqual(file.read_bytes(), raw)
        self.assertEqual((Path(row['workspace']) / 'qa-provenance/original-record.json').read_bytes(), raw)
        self.assertTrue(staged['model']['pages']['home']['source']['file'].startswith(row['source']))

    def test_unverified_or_original_destination_is_rejected(self):
        report = self.root / 'audit.json'
        report.write_text(json.dumps({'projects': [{'name': 'Synthetic', 'eligibleSource': None}]}))
        with self.assertRaisesRegex(ValueError, 'Missing source'):
            snapshots.materialize(argparse.Namespace(audit=report, name=['Synthetic'], destination=self.root / 'new'))
        self.assertFalse((self.root / 'new').exists())


if __name__ == '__main__':
    unittest.main()
