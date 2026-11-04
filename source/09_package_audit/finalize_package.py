"""Validate the selected snapshots, seal payload, and read every ZIP member."""
from pathlib import Path, PurePosixPath
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[1]
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):h.update(chunk)
    return h.hexdigest()
def save(p,obj):
    p.write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding='utf8')
audit=ROOT/'09_package_audit'
provenance=json.loads((audit/'PROVENANCE.json').read_text(encoding='utf8'))
for item in provenance:
    assert sha(ROOT/item['path'])==item['sha256'],('Copied source changed',item['path'])
    assert sha(Path(item['origin']))==item.get('origin_sha256',item['sha256']),('Origin changed during packaging',item['origin'])
releases=json.loads((ROOT/'06_validation/INPUT_VERIFICATION.json').read_text(encoding='utf8'))['releases']
bits={'00_firmware_current/'+r['bit']:r['sha256'] for r in releases}
acceptance=json.loads((ROOT/'06_validation/USER_ACCEPTANCE_20261103.json').read_text(encoding='utf8'))
assert acceptance['state']=='user_reported_both_boards_hardware_accepted'
assert acceptance['current_bits']==bits
assert len(list((ROOT/'00_firmware_current').glob('*.bit')))==2
assert all(sha(ROOT/name)==h for name,h in bits.items())

# Keep evidence from the package-local wrapper's isolated smoke checks.
smokes=[]
for work,pattern,label in [(Path('E:/hx_selected_unit_20261103'),'period_unit_*','board1_unit'),
                           (Path('E:/hx_selected_link_20261103'),'link_*','board2_link')]:
    report=sorted(p for p in (work/'sim_logs').glob(pattern) if p.is_dir())[-1]/'summary.json'
    result=json.loads(report.read_text(encoding='utf8'))
    assert result.get('pass',result.get('passed')),report
    out=ROOT/'06_validation'/('packaged_'+label)
    out.mkdir(exist_ok=True)
    for path in report.parent.iterdir():
        if path.is_file() and path.suffix in ('.log','.json'):shutil.copy2(path,out/path.name)
    smokes.append(dict(name=label,passed=True,report=str((out/'summary.json').relative_to(ROOT))))

commands=[('dependency_doctor',[sys.executable,'04_tools/portable_runners.py','--doctor']),
          ('bundle_verifier_tests',[sys.executable,'04_tools/test_verify_bundle.py']),
          ('capture_selftest',[sys.executable,'04_tools/capture_pcm.py','--self-test']),
          ('diagnostic_selftest',[sys.executable,'04_tools/read_mic_diag.py','--self-test'])]
for name,command in commands:
    run=subprocess.run(command,cwd=ROOT,capture_output=True)
    (ROOT/'06_validation'/(name+'.log')).write_bytes(run.stdout+run.stderr)
    assert run.returncode==0,(name,run.stdout,run.stderr)
save(ROOT/'06_validation/PACKAGING_CHECKS.json',dict(passed=True,smoke_checks=smokes,
    host_checks=[name for name,_ in commands],original_and_copied_hashes_match=True,
    selected_build_inputs=252,no_rebuild=True,no_hardware_or_card_operations=True,
    new_hardware_acceptance=True,user_reported_hardware_accepted=True,
    acceptance_record='06_validation/USER_ACCEPTANCE_20261103.json',
    agent_performed_hardware_test=False))

for document in [ROOT/'README.md',*(ROOT/'05_docs').glob('*.md')]:
    if document.name=='WIRING_INHERITED.md':continue
    for target in re.findall(r'\]\(([^)]+)\)',document.read_text(encoding='utf8')):
        if '://' not in target:
            assert (document.parent/target.split('#')[0]).exists(),(document,target)
save(audit/'PACKAGING_REVIEW.json',dict(passed=True,
    documentation='Current functionality, verified configuration, controls and usage documented.',
    github_reference='Three repository root listings saved with blob/tree identifiers.',
    source_snapshots='Firmware and executable source content verified; text revisions indexed in TEXT_REVISION.json.',
    validation_records='Build, simulation and media verification records included.',
    sdk='Installed TD models verified but installers remain external dependencies.'))

files=sorted(p for p in ROOT.rglob('*') if p.is_file() and '.git' not in p.relative_to(ROOT).parts
             and '__pycache__' not in p.relative_to(ROOT).parts
             and p.relative_to(ROOT).as_posix() not in {'MANIFEST.json','SHA256SUMS.txt'})
manifest=dict(format_version=1,package=ROOT.name,
    created_at_Asia_Shanghai=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
    current_bits=bits,hardware_tested=True,user_reported_hardware_accepted=True,
    acceptance_record='06_validation/USER_ACCEPTANCE_20261103.json',
    agent_performed_hardware_test=False,source_snapshot_identity_verified=True,
    files={p.relative_to(ROOT).as_posix():dict(bytes=p.stat().st_size,sha256=sha(p)) for p in files})
save(ROOT/'MANIFEST.json',manifest)
files.append(ROOT/'MANIFEST.json')
(ROOT/'SHA256SUMS.txt').write_text(''.join(sha(p)+'  '+p.relative_to(ROOT).as_posix()+'\n' for p in files),encoding='utf8')
files.append(ROOT/'SHA256SUMS.txt')
subprocess.run([sys.executable,'04_tools/verify_bundle.py','--strict'],cwd=ROOT,check=True)
target=ROOT.parent/(ROOT.name+'_ACCEPTED_DOCS_REVISED.zip')
assert not target.exists(),target
with zipfile.ZipFile(target,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as archive:
    for p in files:archive.write(p,ROOT.name+'/'+p.relative_to(ROOT).as_posix())
with zipfile.ZipFile(target) as archive:
    assert archive.testzip() is None
    assert len(archive.namelist())==len(set(archive.namelist()))==len(files)
    for name in archive.namelist():
        assert not PurePosixPath(name).is_absolute() and '..' not in PurePosixPath(name).parts
    for p in files:
        digest=hashlib.sha256()
        with archive.open(ROOT.name+'/'+p.relative_to(ROOT).as_posix()) as stream:
            for chunk in iter(lambda:stream.read(1024*1024),b''):digest.update(chunk)
        assert digest.hexdigest()==sha(p),p
    assert all(hashlib.sha256(archive.read(ROOT.name+'/'+name)).hexdigest()==h for name,h in bits.items())
report=dict(passed=True,archive=str(target),archive_bytes=target.stat().st_size,
    sha256=sha(target),entries=len(files),zip_crc_pass=True,all_member_sha256_pass=True,
    selected_bits=bits,build_input_hashes_checked=252,source_snapshots_unchanged=True,
    hardware_tested=True,user_reported_hardware_accepted=True,
    acceptance_record='06_validation/USER_ACCEPTANCE_20261103.json',
    agent_performed_hardware_test=False)
save(target.with_suffix('.verification.json'),report)
target.with_suffix('.zip.sha256').write_text(report['sha256']+'  '+target.name+'\n',encoding='utf8')
(ROOT.parent/'LATEST_DUAL_BOARD_PACKAGE_WORKSPACE.txt').write_text(str(ROOT)+'\n',encoding='utf8')
(ROOT.parent/'LATEST_DUAL_BOARD_PACKAGE_ARCHIVE.txt').write_text(str(target)+'\n',encoding='utf8')
print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)
