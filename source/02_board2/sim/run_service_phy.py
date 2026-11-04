"""Run the actual vendor PLL + unchanged serializer RTL through three startups."""
import hashlib,json,subprocess,tempfile,time,shutil
from pathlib import Path
R=Path(__file__).resolve().parents[1]
B=Path('E:/Modelsim/modelsim_ase/win32aloem')
V=sorted(Path('E:/TD/TD/sim_release/eg4').glob('*.v'))
H=R/'src'
RTL=[H/'video_hd_pll.v',H/'hdmi_phy_warpper.v',H/'lane_lvds_10_1.v']
TB=R/'sim/tb_capture_phy.sv'
O=R/'sim_logs'/time.strftime('service_phy_%Y%m%d_%H%M%S');O.mkdir(parents=True,exist_ok=False)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
files=[*V,*RTL,TB];assert V and all(p.is_file() for p in files)
sources={str(p):sha(p) for p in files}
stage=R/'sim_stages'/('phy_'+str(time.time_ns()));stage.mkdir(parents=True);assert str(stage).isascii()
for p in files:shutil.copy2(p,stage/p.name)
for p in sorted((R/'sim/vectors').glob('tmds_*.hex')):
 sources[str(p)]=sha(p);shutil.copy2(p,stage/p.name)
assert len(list(stage.glob('tmds_*.hex')))==3
commands=[['vlib.exe','work'],['vlog.exe','-permissive',*[p.name for p in V],*[p.name for p in RTL]],
 ['vlog.exe','-sv',TB.name],['vsim.exe','-c','-t','100fs','-onfinish','stop','work.glbl','work.tb_capture_phy','-do','run -all; quit -code 0']]
s={'pass':False,'sources':sources,'commands':commands,'stage':str(stage),
 'scope':'Actual vendor PLL and modified PHY reset RTL. Three PLL startups with varied reset-release offsets; assert async serial reset and exactly3serial edges to release. Replay3x24576 captured real-core words plus training; exact3lane bit order and forwarded-clock boundaries. Short capture windows do not guarantee ACR symbols. Separate capture/replay, no live core feedback, SDF, receiver eye, actual TF/SDRAM/photo or board proof.'}
start=time.monotonic();log=''
try:
 for i,c in enumerate(commands):
  print('PHASE_PHY',i,stage,flush=True)
  p=subprocess.run([str(B/c[0]),*c[1:]],cwd=stage,capture_output=True,timeout=300)
  log=(p.stdout+p.stderr).decode(errors='replace');(O/f'{i}.log').write_text(log,encoding='utf8')
  assert p.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-4000:]
 assert 'PASS service_phy ' in log,log[-4000:]
 assert all(sha(Path(p))==h for p,h in sources.items())
 s['pass']=True;s['pass_lines']=[l for l in log.splitlines() if 'CAPTURE_OK' in l or 'PASS service_phy ' in l]
 print('\n'.join(s['pass_lines']),flush=True)
except Exception as e:
 s['error']=str(e);print('FAIL',str(e)[-4000:],flush=True)
finally:
 s['wall_seconds']=time.monotonic()-start;(O/'summary.json').write_text(json.dumps(s,indent=2)+'\n',encoding='utf8')
raise SystemExit(0 if s['pass'] else 1)
