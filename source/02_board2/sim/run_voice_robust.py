"""Fingerprint and run isolated voice regressions; never edit the parent."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,time,uuid
R=Path(__file__).resolve().parents[1];B=Path('E:/Modelsim/modelsim_ase/win32aloem')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
p=argparse.ArgumentParser();p.add_argument('bench');a=p.parse_args()
stage=R/'sim_stages'/('voice_'+uuid.uuid4().hex[:10]);stage.mkdir(parents=True)
out=R/'sim_logs'/(a.bench+'_'+time.strftime('%Y%m%d_%H%M%S'));out.mkdir(parents=True)
files=list((R/'src/voice').glob('*.v'))+[R/'src/reset_sync.v',R/'sim'/(a.bench+'.sv'),Path(__file__).resolve()]
data_names=[]
if a.bench=='tb_voice_replay':data_names=['voice_raw.hex','voice_cases.hex','voice_counts.vh','cases.json'];files+=[R/'sim/prepare_voice_cases.py']
if a.bench in ('tb_conditioner_compat','tb_frontend_compat'):data_names=['conditioner.mem','conditioner_count.vh']
files+=[R/'sim/voice_data'/n for n in data_names]
files=[f for f in files if f.is_file()];sources={str(f):sha(f) for f in files}
for f in files:
 d=stage/f.relative_to(R);d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,d)
cmds=[['vlib.exe','work'],['vlog.exe','-sv','-permissive',*[f.relative_to(R).as_posix() for f in files if f.suffix in ('.v','.sv')]],
 ['vsim.exe','-c','-t','1ps','-onfinish','stop','work.'+a.bench,'-do','run -all; quit -code 0']]
s=dict(passed=False,stage=str(stage),sources=sources,scope='Digital RTL voice regression '+a.bench+'. Sample-level synthetic and recorded-development replay, no physical distance, room acoustics or new human-accuracy claim.')
try:
 for i,c in enumerate(cmds):
  print('RUN',a.bench,i,out,flush=True)
  with (out/f'{i}.log').open('w') as log:
   q=subprocess.run([str(B/c[0]),*c[1:]],cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=1800)
  log=(out/f'{i}.log').read_text(errors='replace')
  assert q.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-5000:]
 assert 'PASS '+a.bench in log,log[-4000:]
 assert all(sha(Path(f))==h for f,h in sources.items())
 s['passed']=True;s['results']=[l for l in log.splitlines() if any(k in l for k in ('PASS ','LEVEL ','RESULT ','TRAIN '))]
 print('\n'.join(s['results']),flush=True)
except Exception as e:s['error']=str(e);print(e,flush=True)
(out/'summary.json').write_text(json.dumps(s,indent=2),encoding='utf-8')
raise SystemExit(0 if s['passed'] else 1)
