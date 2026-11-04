"""Natural encrypted-core diagnostic using already verified compiled RTL library."""
from pathlib import Path
import hashlib,json,subprocess,time
R=Path(__file__).resolve().parents[1];B=Path('E:/Modelsim/modelsim_ase/win32aloem')
previous=R/'sim_logs/acr_service_top/summary.json';p=json.loads(previous.read_text(encoding='utf8'))
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
# The cached library is accepted only with byte-identical source inputs.
for q,h in p['sources'].items():assert sha(Path(q))==h,q
stage=Path(p['stage']);cwd=stage/'src/td_project';bench=R/'sim/tb_hdmi_native_core.sv'
out=R/'sim_logs/hdmi_native_core';out.mkdir(exist_ok=False)
rec={'pass':False,'library_manifest':str(previous),'library_manifest_sha256':sha(previous),'bench':str(bench),'bench_sha256':sha(bench),'stage':str(stage),
 'scope':'Actual production native timing and RGB adapter into unchanged encrypted HDMI core, natural lock without force, fourcomplete720p frames. Ideal pixel clock, constant RGB, noEDID slave, noPHY or electrical claim.'}
cmds=[['vlog.exe','-sv',str(bench)],['vsim.exe','-c','-t','1ps','-onfinish','stop','work.glbl','work.tb_hdmi_native_core','-do','onerror {quit -code 1}; run -all; quit -code 0']]
start=time.monotonic()
try:
 for i,c in enumerate(cmds):
  print('native_core step',i,flush=True)
  with(out/f'{i}.log').open('w',encoding='utf8')as log:
   run=subprocess.Popen([str(B/c[0]),*c[1:]],cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace')
   for line in run.stdout:
    log.write(line);log.flush()
    if any(t in line for t in ['CORE_FRAME','PASS ','** Fatal','** Error']):print(line.strip(),flush=True)
   code=run.wait()
  s=(out/f'{i}.log').read_text(encoding='utf8');assert not code and '** Error:'not in s and '** Fatal:'not in s,s[-5000:]
 assert 'PASS hdmi_native_geometry'in s,s[-3000:]
 rec.update({'pass':True,'markers':[l for l in s.splitlines()if 'CORE_FRAME'in l or 'PASS 'in l]})
except Exception as e:rec['error']=str(e);print(str(e)[-5000:],flush=True)
finally:
 rec['wall_seconds']=time.monotonic()-start;(out/'summary.json').write_text(json.dumps(rec,indent=2)+'\n',encoding='utf8')
raise SystemExit(0 if rec['pass']else 1)
