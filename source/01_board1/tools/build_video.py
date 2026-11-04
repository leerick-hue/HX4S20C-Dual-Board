"""Stage, compile and retain the unified media test; does not program a board."""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
TD = 'E:/TD/TD/bin/td_commands_prompt.exe'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def project_files(path):
    # TD's own project format uses unescaped "UsedInP&R" attribute values.
    text=path.read_text(encoding='utf-8')
    tree=ET.fromstring(re.sub(r'&(?!#?\w+;)', '&amp;', text))
    return sorted(node.attrib.get('Path','') for node in tree.iter('File'))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--gate-only', action='store_true')
    ap.add_argument('--name', default='unified640')
    ap.add_argument('--seed', type=int, help='Explicit TD placement seed override, recorded in manifest')
    ap.add_argument('--carry-min', type=int, help='Explicit TD min_ripple_len override, recorded in manifest')
    args = ap.parse_args()
    out = ROOT / 'build' / args.name
    out.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='hx4s20c_mjpeg_'))
    records = []
    for folder in ('src', 'rtl'):
        for p in sorted((ROOT / folder).rglob('*')):
            if not p.is_file() or 'build' in p.relative_to(ROOT / folder).parts:
                continue
            if p.suffix.lower() in ('.db', '.bit', '.rpt', '.log', '.area', '.timing', '.ts'):
                continue
            relative = p.relative_to(ROOT)
            dest = stage / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, dest)
            records.append({'path': relative.as_posix(), 'sha256': sha(p)})
    # Root/decoder agent owns verified overrides; integrate them in source before
    # a final build. This script never silently patches RTL in the staging tree.
    shutil.copy2(ROOT / 'build.tcl', stage / 'build.tcl')
    records.append({'path': 'build.tcl', 'sha256': sha(ROOT / 'build.tcl')})
    overrides = {}
    for argument, step, key in ((args.seed, 'place', 'seed'), (args.carry_min, 'rtl', 'min_ripple_len')):
        if argument is None: continue
        script = (stage / 'build.tcl').read_text(encoding='utf8')
        script, count = re.subn(r'(?m)^set_param '+step+' '+key+r' \d+$',
                               'set_param '+step+' '+key+' '+str(argument), script)
        assert count == 1, ('missing strategy setting', step, key)
        (stage / 'build.tcl').write_text(script, encoding='utf8')
        overrides[step+'.'+key] = argument
    project = stage / 'src/td_project/HX4S20C_Extensions.al'
    original = project.read_text(encoding='utf-8')
    project.write_text(re.sub(r'(<Project\b[^>]*\bPath=")[^"]*',
                             lambda m: m[1] + project.parent.as_posix(), original, count=1), encoding='utf-8')
    if args.gate_only:
        script = (stage / 'build.tcl').read_text(encoding='utf-8')
        script = script[:script.index('\nplace\n')] + '\nclose_project\nexit\n'
        (stage / 'build.tcl').write_text(script, encoding='utf-8')
    staged_sources = [{'path': r['path'], 'sha256': sha(stage / r['path'])} for r in records]
    project_files_before=project_files(project)
    print('TD stage', stage, 'gate_only', args.gate_only, flush=True)
    with (out / 'console.log').open('w', encoding='utf-8') as log:
        run = subprocess.run([TD, 'build.tcl'], cwd=stage, stdout=log, stderr=subprocess.STDOUT)
    changed = [r['path'] for r in records if not (ROOT / r['path']).is_file()
               or sha(ROOT / r['path']) != r['sha256']]
    changed_in_stage = [r['path'] for r in staged_sources if not (stage / r['path']).is_file()
                        or sha(stage / r['path']) != r['sha256']]
    # TD rewrites generated project metadata/AutoExcluded entries at close.
    # Require identical source list and unchanged actual HDL/IP/constraints.
    project_metadata_only=project_files(project)==project_files_before
    unexpected_stage_changes=[p for p in changed_in_stage if p!='src/td_project/HX4S20C_Extensions.al' or not project_metadata_only]
    output_folder = stage / 'build'
    bit = output_folder / 'HX4S20C_UNIFIED_TEST.bit'
    area = output_folder / 'HX4S20C_UNIFIED_gate.area'
    console = (out / 'console.log').read_text(encoding='utf-8', errors='replace')
    errors = re.findall(r'^.*(?:ERROR|Error:).*$', console, re.M)
    passed = run.returncode == 0 and area.is_file() and not errors and not changed and not unexpected_stage_changes and (args.gate_only or bit.is_file())
    for p in output_folder.glob('*'):
        if p.is_file() and p.suffix.lower() in ('.bit', '.area', '.timing', '.ts'):
            shutil.copy2(p, out / p.name)
    report = {'utc': datetime.now(timezone.utc).isoformat(), 'workspace': str(stage),
              'strategy_overrides': overrides, 'build_helper_sha256': sha(Path(__file__)),
              'gate_only': args.gate_only, 'td_exit': run.returncode, 'pass': passed,
              'bit_generated': bit.is_file(), 'errors': errors, 'changed_during_build': changed,
              'sources': records, 'staged_sources': staged_sources, 'changed_in_stage': changed_in_stage,
              'project_metadata_only':project_metadata_only,'unexpected_stage_changes':unexpected_stage_changes,
              'bit_sha256': sha(bit) if bit.is_file() else None,
              'stage_project_sha256': sha(project)}
    (out / 'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('PASS' if passed else 'FAIL', 'TD build', 'changed', changed, 'errors', errors, flush=True)
    if not passed:
        print(console[-10000:])
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
