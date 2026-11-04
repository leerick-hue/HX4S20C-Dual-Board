"""Finish a routed build with TD's clock-route hold repair, retaining provenance."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, subprocess, tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    ap = argparse.ArgumentParser(__doc__)
    ap.add_argument('--parent', required=True)
    ap.add_argument('--name', default='unified640_release')
    a = ap.parse_args()
    parent = ROOT/'build'/a.parent
    original = json.loads((parent/'manifest.json').read_text(encoding='utf8'))
    assert original['pass'] and original['bit_generated']
    for r in original['sources']: assert sha(ROOT/r['path']) == r['sha256'], r['path']
    # Early guard: a parent build whose own timing report already closes
    # (SWNS and HWNS >= 0) must not be re-touched by post-route fix_hold,
    # which caused an observed hardware regression on an already-clean design.
    parent_ts = parent/'HX4S20C_UNIFIED_phy.ts'
    if parent_ts.is_file() and original.get('bit_sha256'):
        pt = parent_ts.read_text(encoding='utf8', errors='replace')
        ps = re.search(r'SWNS:\s*([-\d.]+)', pt)
        ph = re.search(r'HWNS:\s*([-\d.]+)', pt)
        if ps and ph and float(ps[1]) >= 0 and float(ph[1]) >= 0:
            skip_out = ROOT/'build'/a.name
            skip_out.mkdir(parents=True, exist_ok=True)
            for f in parent.iterdir():
                if f.is_file() and f.suffix in ('.bit', '.area', '.timing', '.ts'):
                    shutil.copy2(f, skip_out/f.name)
            copied_bit = skip_out/'HX4S20C_UNIFIED_TEST.bit'
            bit_ok = copied_bit.is_file() and sha(copied_bit) == original['bit_sha256']
            srcs_ok = all(sha(ROOT/r['path']) == r['sha256'] for r in original['sources'])
            # A failed integrity check must stop, not fall through to a new
            # physical modification of the already-closed implementation.
            assert bit_ok, 'Copied parent bit differs from its manifest'
            assert srcs_ok, 'Production source changed while copying parent build'
            if bit_ok and srcs_ok:
                result = dict(original)
                result.update(utc=datetime.now(timezone.utc).isoformat(),
                              parent_build=a.parent,
                              parent_manifest_sha256=sha(parent/'manifest.json'),
                              parent_timing_report=str(parent_ts),
                              setup_ns=float(ps[1]), hold_ns=float(ph[1]),
                              timing_closed=True, hold_repair_skipped=True,
                              reason='parent timing already passes',
                              td_exit=None, errors=[], changed_during_build=[],
                              pass_=True, bit_generated=True,
                              strategy_overrides=dict(original.get('strategy_overrides', {}),
                                                      post_route_hold='skipped_already_passed'))
                result['pass'] = result.pop('pass_')
                (skip_out/'manifest.json').write_text(json.dumps(result, indent=2), encoding='utf8')
                print('SKIP', 'hold repair not run:', skip_out,
                      'parent SWNS', ps[1], 'HWNS', ph[1],
                      'copied bit SHA and source hashes verified')
                return
    source_stage = Path(original['workspace'])
    project_stage = Path(original.get('source_project_workspace', original['workspace']))
    routed_db = Path(original.get('routed_db', source_stage/'build/HX4S20C_UNIFIED_pr.db'))
    effective_script = Path(original.get('effective_script', source_stage/'build.tcl'))
    stage = Path(tempfile.mkdtemp(prefix='td_unified_release_'))
    out = ROOT/'build'/a.name; out.mkdir(parents=True, exist_ok=True)
    script = f'''import_device eagle_s20.db -package EG4S20BG256
open_project -single_run {{{(project_stage/'src/td_project/HX4S20C_Extensions.al').as_posix()}}}
import_db {{{routed_db.as_posix()}}}
update_timing -mode final
fix_hold -clock_opt
update_timing -mode final
report_cells [get_cells {{video_pll_m0/pll_inst}}] -connection
report_cells [get_cells {{u_audio_pll/pll_inst}}] -connection
report_cells [get_cells {{sys_pll_m0/pll_inst}}] -connection
report_route_status -drc -file route_status.txt
report_area -io_info -file HX4S20C_UNIFIED_phy.area
report_timing_summary -file HX4S20C_UNIFIED_pr.timing
report_timing_status -file HX4S20C_UNIFIED_phy.ts
export_db HX4S20C_UNIFIED_pr.db
bitgen -bit HX4S20C_UNIFIED_TEST.bit
close_project
exit
'''
    (stage/'holdfix.tcl').write_text(script, encoding='utf8')
    shutil.copy2(stage/'holdfix.tcl', out/'holdfix.tcl')
    with (out/'console.log').open('w', encoding='utf8') as log:
        p = subprocess.run(['E:/TD/TD/bin/td_commands_prompt.exe', 'holdfix.tcl'],
                           cwd=stage, stdout=log, stderr=subprocess.STDOUT)
    text = (out/'console.log').read_text(encoding='utf8', errors='replace')
    errors = re.findall(r'^.*(?:ERROR|Error:|Oops!).*$', text, re.M)
    changed = [r['path'] for r in original['sources'] if sha(ROOT/r['path']) != r['sha256']]
    bit = stage/'HX4S20C_UNIFIED_TEST.bit'
    passed = p.returncode == 0 and bit.is_file() and not errors and not changed
    status_path = stage/'HX4S20C_UNIFIED_phy.ts'
    timing = status_path.read_text(encoding='utf8') if status_path.is_file() else ''
    setup_match = re.search(r'SWNS:\s*([-\d.]+)', timing)
    hold_match = re.search(r'HWNS:\s*([-\d.]+)', timing)
    setup = float(setup_match[1]) if setup_match else None
    hold = float(hold_match[1]) if hold_match else None
    for f in stage.iterdir():
        if f.is_file() and f.suffix in ('.bit', '.area', '.timing', '.ts', '.txt'):
            shutil.copy2(f, out/f.name)
    # Include parent placement evidence and effective script without changing it.
    shutil.copy2(parent/'console.log', out/'parent_console.log')
    shutil.copy2(effective_script, out/'effective_build.tcl')
    result = dict(original)
    result.update(utc=datetime.now(timezone.utc).isoformat(), parent_build=a.parent,
                  parent_manifest_sha256=sha(parent/'manifest.json'), repair_workspace=str(stage),
                  repair_script=str(out/'holdfix.tcl'), repair_script_sha256=sha(out/'holdfix.tcl'),
                  pass_=passed, td_exit=p.returncode, errors=errors, changed_during_build=changed,
                  bit_generated=bit.is_file(), bit_sha256=sha(bit) if bit.is_file() else None,
                  parent_setup_ns=original.get('setup_ns'), parent_hold_ns=original.get('hold_ns'),
                  setup_ns=setup, hold_ns=hold,
                  timing_closed=passed and setup is not None and hold is not None and setup>=0 and hold>=0)
    result['pre_hold_routed_db'] = str(routed_db)
    result['routed_db'] = str(stage/'HX4S20C_UNIFIED_pr.db')
    result['effective_script'] = str(out/'holdfix.tcl')
    result['pass'] = result.pop('pass_')
    result['strategy_overrides'] = dict(original.get('strategy_overrides', {}), post_route_hold='clock_opt')
    (out/'manifest.json').write_text(json.dumps(result, indent=2), encoding='utf8')
    print('PASS' if passed else 'FAIL', 'TD clock hold finish', out, 'errors', errors, 'changed', changed)
    if not passed: raise SystemExit(1)

if __name__ == '__main__': main()
