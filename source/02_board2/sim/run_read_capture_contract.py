"""Isolate the production capture selection under the inherited early model."""
from pathlib import Path
import hashlib,json,shutil,subprocess,time,uuid
R=Path(__file__).resolve().parents[1]
B=Path('E:/Modelsim/modelsim_ase/win32aloem')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=[R/'src/sdram.v',R/'src/frame_read_write.v',R/'sim/sdram_retention_model.sv',
       R/'sim/tb_read_capture_contract.sv',Path(__file__).resolve()]
files+=list((R/'user_source/hdl_source/include').glob('*'))
hashes={str(p):sha(p) for p in files if p.is_file()}
stage=R/'sim_stages'/('capture_'+uuid.uuid4().hex[:8])
cwd=stage/'project';cwd.mkdir(parents=True)
out=R/'sim_logs'/time.strftime('read_capture_%Y%m%d_%H%M%S');out.mkdir(parents=True)
for p in files:
 if p.is_file():
  d=stage/p.relative_to(R);d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,d)
commands=[['vlib.exe','work'],['vlog.exe','-permissive','../src/sdram.v',
 '../user_source/hdl_source/include/sdr_as_ram.enc.v',
 '../user_source/hdl_source/include/sdr_init_ref.enc.v',
 '../user_source/hdl_source/include/sdr_wrrd.enc.v'],
 ['vlog.exe','-sv','../sim/sdram_retention_model.sv','../sim/tb_read_capture_contract.sv'],
 ['vsim.exe','-c','-t','1ps','-onfinish','stop','work.tb_read_capture_contract',
  '-do','run -all; quit -code 0']]
report=dict(passed=False,stage=str(stage),sources=hashes,
 scope='Functional early-return retained memory and production previous-data selection only. 256 tagged read responses across four aligned bursts and row boundaries. Preloaded memory isolates reads, excludes writes. No silicon CAS-latency or physical-timing claim.')
try:
 for i,c in enumerate(commands):
  p=subprocess.run([str(B/c[0]),*c[1:]],cwd=cwd,capture_output=True,timeout=120)
  log=(p.stdout+p.stderr).decode(errors='replace');(out/f'{i}.log').write_text(log)
  assert p.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-4000:]
 assert 'PASS read_capture ' in log
 assert all(sha(Path(p))==h for p,h in hashes.items())
 report['passed']=True;report['results']=[s for s in log.splitlines() if 'PASS read_capture ' in s]
 print('\n'.join(report['results']))
except Exception as e:report['error']=str(e);print(e)
(out/'summary.json').write_text(json.dumps(report,indent=2))
raise SystemExit(0 if report['passed'] else 1)
