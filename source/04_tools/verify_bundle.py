"""Verify all packaged payload SHA256 values. No third-party dependencies."""
from pathlib import Path
import argparse, hashlib, json

def sha(p):
    h = hashlib.sha256()
    with p.open('rb') as f:
        for block in iter(lambda: f.read(1024*1024), b''): h.update(block)
    return h.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--strict', action='store_true', help='Reject files absent from the manifest')
    args = parser.parse_args()
    root = args.root.resolve()
    expected = None
    for line in (root/'SHA256SUMS.txt').read_text(encoding='utf8').splitlines():
        h, name = line.split('  ', 1)
        if name == 'MANIFEST.json': expected = h
    if expected is None or sha(root/'MANIFEST.json') != expected:
        print('FAIL: MANIFEST.json checksum mismatch'); return 1
    manifest = json.loads((root/'MANIFEST.json').read_text(encoding='utf8'))
    failures = []
    for name, entry in manifest['files'].items():
        p = root/name
        if '\\' in name or ':' in name or '..' in Path(name).parts or not p.resolve().is_relative_to(root):
            failures.append(name+' unsafe path')
        elif not p.is_file() or p.stat().st_size != entry['bytes'] or sha(p) != entry['sha256']:
            failures.append(name)
    if args.strict:
        allowed = set(manifest['files']) | {'MANIFEST.json', 'SHA256SUMS.txt'}
        for p in root.rglob('*'):
            relative = p.relative_to(root)
            if '.git' in relative.parts or '__pycache__' in relative.parts:
                continue
            if p.is_file() and relative.as_posix() not in allowed:
                failures.append(relative.as_posix()+' unlisted file')
    if failures:
        print('FAIL: '+ '\n'.join(failures)); return 1
    print('PASS: %d payload files verified; selected releases: Board1 8EB7D133, Board2 6F5DD197' % len(manifest['files']))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
