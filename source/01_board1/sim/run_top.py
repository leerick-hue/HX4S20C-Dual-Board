"""Actual RTL-top quiet/reset integration, bounded; no routed/SDF/photo claim."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,tempfile,time
R=Path(__file__).resolve().parents[1];B=Path('E:/Modelsim/modelsim_ase/win32aloem');L=Path('E:/TD/TD/sim_release/eg4')
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--name',default='acr_service_top');args=parser.parse_args()
out=R/'sim_logs'/args.name;out.mkdir(parents=True,exist_ok=False)
stage=Path(tempfile.mkdtemp(prefix='hx_quiet_top_'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
sources={}
for folder in ('src','rtl'):
 for p in (R/folder).rglob('*'):
  if p.is_file():
   d=stage/p.relative_to(R);d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,d);sources[str(p)]=sha(p)
project=stage/'src/td_project/HX4S20C_Extensions.al'
paths=re.findall(r'<File\s+Path="([^"]+)"',project.read_text(encoding='utf8'))
vfiles=[(project.parent/p).resolve() for p in paths if Path(p).suffix.lower()=='.v']
svfiles=[(project.parent/p).resolve() for p in paths if Path(p).suffix.lower()=='.sv']
# The .ipc project entries generate HDL; include their existing simulation wrappers.
registered={str(p).lower() for p in vfiles}
for p in (stage/'src/td_project/al_ip').glob('*.v'):
 if str(p.resolve()).lower() not in registered:vfiles.append(p.resolve())
# These two generated .ipc sources are existing production Verilog wrappers.
# Do not include IP/sdram.v: it is a different module with the same name.
for rel in ('IP/sys_pll.v','IP/afifo_32_16_256.v'):
 p=(stage/'src/user_source/hdl_source'/rel).resolve()
 if p not in vfiles:vfiles.append(p)
vendor=stage/'vendor';vendor.mkdir()
for p in L.glob('*.v'):
 shutil.copy2(p,vendor/p.name);sources[str(p)]=sha(p)
tb=R/'sim/tb_acr_service_top.sv';shutil.copy2(tb,stage/tb.name);sources[str(tb)]=sha(tb)
plain_v=[p for p in vfiles if p.name.endswith('.enc.v') or re.search(r'\.\s*do\s*\(',p.read_text(encoding='utf8',errors='replace'))]
svfiles += [p for p in vfiles if p not in plain_v]
commands=[['vlib.exe','work'],['vlog.exe','-permissive',*[p.as_posix() for p in vendor.glob('*.v')],*[p.as_posix() for p in plain_v]],['vlog.exe','-sv','-permissive',*[p.as_posix() for p in svfiles],(stage/tb.name).as_posix()],['vsim.exe','-c','-t','1ps','-onfinish','stop','work.glbl','work.tb_acr_service_top','-do','run -all; quit -code 0']]
result={'pass':False,'stage':str(stage),'sources':sources,'commands':commands,'runner_sha256':sha(Path(__file__)),'scope':'Actual full RTL top and installed vendor PLL/core/PHY models. Deliberately forced core lock, post-volume PCM/ACR and own parser-ack endpoint stimuli verify lock gating,64stereo samples,4ACR updates,parameter hold,pending buffer,no media/video reset,normal control defaults and diagnostic CDC. No keys pressed or debounce acceleration. Testbench pulses tied-low systemPLL reset once to model configuration startup, then uses real model clocks/locks. HardSDRAM model empty. Not natural HDMI lock,actual PCM packet decoding,actual power-on/TF/photo/full-frame/routed/SDF/electrical proof; actual-core packets checked separately.'}
start=time.monotonic()
try:
 for i,c in enumerate(commands):
  print('ModelSim quiet_top step',i,flush=True)
  run=subprocess.run([str(B/c[0]),*c[1:]],cwd=project.parent,capture_output=True,timeout=180)
  log=(run.stdout+run.stderr).decode(errors='replace');(out/f'{i}.log').write_text(log,encoding='utf8')
  if run.returncode or '** Error:' in log or '** Fatal:' in log:raise RuntimeError(log[-5000:])
 assert 'PASS acr_service_top ' in log,log[-4000:]
 assert all(sha(Path(p))==h for p,h in sources.items())
 result['pass_lines']=[s for s in log.splitlines() if 'PASS acr_service_top ' in s]
 result['pass']=True;print('\n'.join(result['pass_lines']),flush=True)
except subprocess.TimeoutExpired as e:
 (out/'timeout_partial.log').write_bytes(e.stdout or b'');result['error']=str(e);print('FAIL quiet_top timeout',flush=True)
except Exception as e:result['error']=str(e);print(str(e)[-5000:],flush=True)
finally:
 result['wall_seconds']=time.monotonic()-start;(out/'summary.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
raise SystemExit(0 if result['pass'] else 1)

