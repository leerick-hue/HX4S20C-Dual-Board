from pathlib import Path
import hashlib,json,shutil,subprocess,time,uuid
R=Path(__file__).resolve().parents[1];B=Path('E:/Modelsim/modelsim_ase/win32aloem')
files=[R/'src/word_replicator.v',R/'sim/tb_replicator_contract.sv']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
hashes={str(p):sha(p) for p in files}
stage=R/'sim_stages'/('replicator_'+uuid.uuid4().hex[:8]);stage.mkdir(parents=True)
out=R/'sim_logs'/('replicator_'+time.strftime('%Y%m%d_%H%M%S'));out.mkdir(parents=True)
for p in files:shutil.copy2(p,stage/p.name)
cmds=[['vlib.exe','work'],['vlog.exe','-sv',*[p.name for p in files]],
 ['vsim.exe','-c','-t','1ps','-onfinish','stop','work.tb_replicator_contract','-do','run -all; quit -code 0']]
for i,c in enumerate(cmds):
 p=subprocess.run([str(B/c[0]),*c[1:]],cwd=stage,capture_output=True,timeout=120)
 text=(p.stdout+p.stderr).decode(errors='replace');(out/f'{i}.log').write_text(text)
 if p.returncode or '** Error:' in text or '** Fatal:' in text:raise RuntimeError(text[-3000:])
assert 'PASS replicator_contract' in text
assert all(sha(Path(p))==h for p,h in hashes.items())
report=dict(passed=True,stage=str(stage),sources=hashes,results=[s for s in text.splitlines() if 'PASS' in s],
 scope='Four-word aligned output for every row/column at 3x/4x,230400 output words, random stalls and partial group cancellation. Module-only, not 16:9 system qualification.')
(out/'summary.json').write_text(json.dumps(report,indent=2));print(report['results'])
