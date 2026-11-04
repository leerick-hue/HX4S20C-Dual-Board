"""Actual period/gesture scheduler RTL with forced ideal parser/display/consumer.
No full-album, SD, SDRAM, HDMI, routed/SDF, or physical-button acceptance claim.
"""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,time,uuid
R=Path(__file__).resolve().parents[1]
B=Path('E:/Modelsim/modelsim_ase/win32aloem')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=[R/'src/user_source/hdl_source/SD/sd_card_bmp.v',R/'src/user_source/hdl_source/SD/bmp_read_scaled.v',R/'src/user_source/hdl_source/extensions/bmp24_scale_stream.v',R/'sim/tb_period_regression.sv']
stage=R/'sim_stages'/('period_unit_'+uuid.uuid4().hex[:10]);stage.mkdir(parents=True)
out=R/'sim_logs'/('period_unit_'+time.strftime('%Y%m%d_%H%M%S'));out.mkdir(parents=True)
sources={str(p):sha(p) for p in files+[Path(__file__).resolve()]}
for p in files:shutil.copy2(p,stage/p.name)
commands=[['vlib.exe','work'],['vlog.exe','-sv','-permissive',*[p.name for p in files]],['vsim.exe','-c','-t','1ps','-onfinish','stop','work.tb_period_regression','-do','run -all; quit -code 0']]
report=dict(pass_=False,stage=str(stage),sources=sources,commands=commands,scope=__doc__.strip())
report['pass']=report.pop('pass_');start=time.monotonic()
try:
 for i,cmd in enumerate(commands):
  print('RUN',i,'OUT',out,'STAGE',stage,flush=True)
  with (out/f'{i}.log').open('w') as f:
   proc=subprocess.run([str(B/cmd[0]),*cmd[1:]],cwd=stage,stdout=f,stderr=subprocess.STDOUT,timeout=int(os.environ.get('HX_SIM_TIMEOUT','300')))
  log=(out/f'{i}.log').read_text(errors='replace')
  if proc.returncode or '** Error:' in log or '** Fatal:' in log or '** Failure:' in log:raise RuntimeError(log[-7000:])
 assert 'PASS period_regression ' in log,log[-7000:]
 assert all(sha(Path(p))==h for p,h in sources.items()),'Source changed during simulation'
 report['pass']=True;report['results']=[line for line in log.splitlines() if 'PERIOD_CASE' in line or 'PASS period_regression ' in line]
 print('\n'.join(report['results']),flush=True)
except Exception as e:report['error']=str(e);print(e,flush=True)
report['wall_seconds']=time.monotonic()-start
(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
(R/'sim_logs/period_unit_latest.json').write_text(json.dumps(dict(path=str(out/'summary.json'),**report),indent=2)+'\n')
raise SystemExit(0 if report['pass'] else 1)
