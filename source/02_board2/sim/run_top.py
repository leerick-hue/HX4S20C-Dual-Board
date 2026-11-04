from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,tempfile,time,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parents[1];B=Path('E:/Modelsim/modelsim_ase/win32aloem');L=Path('E:/TD/TD/sim_release/eg4')
ap=argparse.ArgumentParser();ap.add_argument('--smoke',action='store_true');args=ap.parse_args()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
tree=ET.parse(R/'project/HX4S20C_Extensions.al')
files=[(R/'project'/e.attrib['Path']).resolve() for e in tree.findall('./Source_Files/Verilog/File')]
files=[p for p in files if p.name not in ('sd_card_top.v','sd_card_sec_read_write.v','sd_card_cmd.v','spi_master.v')]
if not args.smoke:files=[p for p in files if p.name not in ('sys_pll.v','video_hd_pll.v','hdmi_phy_warpper.v','lane_lvds_10_1.v')]
files+=[R/'user_source/hdl_source/include/global_def.v']
files+=[R/'sim'/n for n in ('sdram_retention_model.sv','top_storage.v','hdmi_sequence_decoder.sv','tb_motion_top.sv','card_model.v')]
if not args.smoke:files+=[R/'sim/ideal_plls.v',R/'sim/phy_omitted.v']
vendor=[p for p in L.glob('*.v') if p.name!='eg_phy_sdram_2m_32.v']
stage=Path(tempfile.mkdtemp(prefix='hx_motion_top_'));cwd=stage/'project';cwd.mkdir()
out=R/'sim_logs'/time.strftime(('smoke_' if args.smoke else 'top_')+'%Y%m%d_%H%M%S');out.mkdir(parents=True)
hashes={str(p):sha(p) for p in files+vendor}
for p in files:
 d=stage/p.relative_to(R);d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,d)
shutil.copytree(R/'sim/fixtures',stage/'sim/fixtures')
hashes.update({str(p):sha(p) for p in (R/'sim/fixtures').glob('*') if p.is_file()})
for p in vendor:
 d=stage/'vendor'/p.name;d.parent.mkdir(exist_ok=True);shutil.copy2(p,d)
sources=['../vendor/'+p.name for p in vendor]+['../'+p.relative_to(R).as_posix() for p in files if p.name!='global_def.v']
commands=[['vlib.exe','work'],['vlog.exe','-permissive',*[s for s in sources if s.endswith('.v')]],['vlog.exe','-sv','-permissive',*[s for s in sources if s.endswith('.sv')]],['vsim.exe','-c','-t','1ps','-onfinish','stop','work.glbl','work.tb_motion_top',*(['-gSMOKE=1'] if args.smoke else []),'-do','run -all; quit -code 0']]
report=dict(passed=False,stage=str(stage),sources=hashes,smoke=args.smoke,scope='Actual full top/JPEG and encrypted HDMI/SDRAM cores, synthetic sector service replacing sd_card_top (no physical SPI), functional retained SDRAM (early-return test model), accelerated EDID wait, no responder. '+('Actual vendor PLL and PHY short binding/boot test; forced video lock.' if args.smoke else 'Ideal PLL clocks and omitted serial PHY; natural video lock, complete AXIS frames including JPEG image and decoded parallel TMDS PCM/ACR/BCH/InfoFrames.'))
start=time.monotonic()
try:
 for i,c in enumerate(commands):
  print('RUN',i,c[0],out,flush=True)
  run=subprocess.run([str(B/c[0]),*c[1:]],cwd=cwd,capture_output=True,timeout=1200)
  log=(run.stdout+run.stderr).decode(errors='replace');(out/f'{i}.log').write_text(log,encoding='utf8')
  if run.returncode or '** Error:' in log or '** Fatal:' in log:raise RuntimeError(log[-5000:])
 assert ('PASS motion_top_smoke' if args.smoke else 'PASS motion_top natural') in log,log[-5000:]
 assert all(sha(Path(p))==h for p,h in hashes.items())
 report['passed']=True;report['results']=[s for s in log.splitlines() if 'PASS ' in s or 'TOP_FRAME' in s];print('\n'.join(report['results']),flush=True)
except Exception as e:report['error']=str(e);print(str(e),flush=True)
report['elapsed_seconds']=time.monotonic()-start;(out/'summary.json').write_text(json.dumps(report,indent=2),encoding='utf8')
raise SystemExit(0 if report['passed'] else 1)
