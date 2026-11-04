"""Exercise delivery corruption and unexpected-file detection without hardware."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

VERIFIER = Path(__file__).with_name('verify_bundle.py')


class BundleIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root/'payload.bin').write_bytes(b'accepted baseline')
        self.manifest = {'files': {'payload.bin': {'bytes': 17,
            'sha256': hashlib.sha256(b'accepted baseline').hexdigest()}}}
        self.seal()

    def seal(self):
        manifest = self.root/'MANIFEST.json'
        manifest.write_text(json.dumps(self.manifest), encoding='utf8')
        (self.root/'SHA256SUMS.txt').write_text(
            hashlib.sha256(manifest.read_bytes()).hexdigest()+'  MANIFEST.json\n', encoding='utf8')

    def verify(self, expected, *args):
        result = subprocess.run([sys.executable, str(VERIFIER), '--root', str(self.root), *args],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stdout+result.stderr)

    def test_intact(self):
        self.verify(0, '--strict')

    def test_same_size_tampering(self):
        (self.root/'payload.bin').write_bytes(b'Xccepted baseline')
        self.verify(1)

    def test_missing_payload(self):
        (self.root/'payload.bin').unlink()
        self.verify(1)

    def test_unsealed_manifest(self):
        (self.root/'MANIFEST.json').write_text('{}', encoding='utf8')
        self.verify(1)

    def test_extra_file(self):
        (self.root/'unexpected.bit').write_bytes(b'wrong firmware')
        self.verify(0)
        self.verify(1, '--strict')

    def test_unsafe_path(self):
        self.manifest['files']['../outside.bin'] = {'bytes': 0, 'sha256': '0'*64}
        self.seal()
        self.verify(1)


if __name__ == '__main__':
    unittest.main()
