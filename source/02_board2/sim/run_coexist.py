from pathlib import Path
import hashlib,json,shutil,struct,subprocess,uuid,time,re,sys,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parents[1]
B=Path('E:/Modelsim/modelsim_ase/win32aloem')
L=Path('E:/TD/TD/sim_release/eg4')
peer=Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board/phone_ir_fit_link_ack_20261030/src/user_source/hdl_source/extensions')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
link_only='--link' in sys.argv
bench='tb_link_ack' if link_only else 'tb_coexist'
tree=ET.parse(R/'project/HX4S20C_Extensions.al')
files=[(R/'project'/e.attrib['Path']).resolve() for e in tree.findall('./Source_Files/Verilog/File')]
exclude=('sd_card_top.v','sd_card_sec_read_write.v','sd_card_cmd.v','spi_master.v','sys_pll.v','video_hd_pll.v','hdmi_phy_warpper.v','lane_lvds_10_1.v')
files=[p for p in files if p.name not in exclude]
files += [R/'user_source/hdl_source/include/global_def.v']
files += [R/'sim'/n for n in ('sdram_retention_model.sv','top_storage.v','card_model.v','ideal_plls.v','phy_omitted.v',bench+'.sv')]
vendor=[p for p in L.glob('*.v') if p.name!='eg_phy_sdram_2m_32.v']
stage=R/'sim_stages'/uuid.uuid4().hex[:10];cwd=stage/'project';cwd.mkdir(parents=True)
out=R/'sim_logs'/time.strftime(('link_' if link_only else 'coexist_')+'%Y%m%d_%H%M%S');out.mkdir(parents=True)
hashes={str(p):sha(p) for p in files+vendor}
for p in files:
 d=stage/p.relative_to(R);d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,d)
 if p.name=='top_storage.v': d.write_text(p.read_text().replace('tb_motion_top','tb_coexist'))
fixture=stage/'sim/fixtures';fixture.mkdir(parents=True,exist_ok=True)
card_bytes=153088
if not link_only:
 sys.path.insert(0,str(R/'media/tools'))
 import hxjv
 framefolder=fixture/'jpegs';framefolder.mkdir()
 for i in range(3):
  p=R/'media/frames'/f'frame_{i:08d}.jpg'
  hashes[str(p)]=sha(p);shutil.copy2(p,framefolder/p.name)
 player=fixture/'short_hxjv.img';hxjv.pack_sequence(framefolder,player,fps=15)
 prefix_path=R.parent/'board2_adaptive_voice_20261101/media_bbb_20261102/DELIVERY/CARD_BBB_20s_320x240_25fps.img'
 with prefix_path.open('rb') as f:prefix=bytearray(f.read(4096))
 assert len(prefix)==4096 and prefix[:4]==b'HXAU'
 hashes[str(prefix_path)]=sha(prefix_path)
 struct.pack_into('<II',prefix,20,8,0)
 struct.pack_into('<I',prefix,28,8)
 segment=player.read_bytes();video_sectors=len(segment)//512
 struct.pack_into('<4sIII',prefix,36,b'HXUV',8,video_sectors,8+video_sectors)
 data=bytes(prefix)+segment;card_bytes=len(data)
 (fixture/'card480.img').write_bytes(data)
 (fixture/'fps30.hex').write_text(''.join(f'{v:02x}\n' for v in data))
fixtures={'conditioner.mem':Path('E:/HX4S20C_Board2/work/link_ack_20261026/data/conditioner.mem')}
if link_only:fixtures['fps30.hex']=R/'sim/fixtures/fps30_320x240.hex'
for name,p in fixtures.items():
 d=stage/'sim/fixtures'/name;d.parent.mkdir(exist_ok=True);shutil.copy2(p,d);hashes[str(p)]=sha(p)
for p in vendor:
 d=stage/'vendor'/p.name;d.parent.mkdir(exist_ok=True);shutil.copy2(p,d)
peerfiles=[peer/(n+'.v') for n in ('board_remote_control','uart_rx','event_packet_rx','event_fifo')]
for p in peerfiles:
 d=stage/'peer'/p.name;d.parent.mkdir(exist_ok=True);shutil.copy2(p,d);hashes[str(p)]=sha(p)
 # Namespace only: board one has diagnostic ports absent in board two's decoder.
 s=p.read_text()
 for n in ('uart_rx','event_packet_rx','event_fifo'):s=re.sub(r'\b'+n+r'\b','peer_'+n,s)
 d.write_text(s)
sources=['../vendor/'+p.name for p in vendor]+['../'+p.relative_to(R).as_posix() for p in files if p.name!='global_def.v']+['../peer/'+p.name for p in peerfiles]
commands=[['vlib.exe','work'],['vlog.exe','-permissive',*[s for s in sources if s.endswith('.v')]],['vlog.exe','-sv',*[s for s in sources if s.endswith('.sv')]],['vsim.exe','-c','-t','1ps',*([f'-gCARD_BYTES={card_bytes}'] if not link_only else []),'-onfinish','stop','work.glbl','work.'+bench,'-do','run -all; quit -code 0']]
report=dict(passed=False,stage=str(stage),card_bytes=card_bytes,sources=hashes,scope='Actual candidate top and peer board_remote_control: I2S input/conditioner/debug UART, key mapping, forced recognition event IDs through real UART/ACK including lost ACK, concurrent 640x480@15 JPEG decode/direct RGB565/centred native 640x480 in 720p60 AXIS frame geometry and black borders. Ideal PLL, omitted serial PHY, synthetic sector service and functional SDRAM. No new speech accuracy or hardware claim.')
if link_only:report['scope']='Candidate reliable_event_link and board-one receiver, real 50/100MHz clocks and 115200-baud UART: corruption, ACK loss, bounded retry, disconnect/reconnect, wrong sequence, ordered queue, late ACK and duplicate suppression. No video or speech recognition instantiated.'
start=time.monotonic()
try:
 for i,c in enumerate(commands):
  print('RUN',i,c[0],out,flush=True)
  with (out/f'{i}.log').open('w') as fh:
   run=subprocess.run([str(B/c[0]),*c[1:]],cwd=cwd,stdout=fh,stderr=subprocess.STDOUT,timeout=3600)
  log=(out/f'{i}.log').read_text(errors='replace')
  if run.returncode or '** Error:' in log or '** Fatal:' in log:raise RuntimeError(log[-5000:])
 assert ('PASS reliable link' if link_only else 'PASS coexist') in log,log[-5000:]
 assert all(sha(Path(p))==h for p,h in hashes.items())
 report['passed']=True;report['results']=[s for s in log.splitlines() if any(t in s for t in ('PASS','FRAME n='))]
 print('\n'.join(report['results']),flush=True)
except Exception as e:report['error']=str(e);print(e,flush=True)
report['elapsed_seconds']=time.monotonic()-start
(out/'summary.json').write_text(json.dumps(report,indent=2))
raise SystemExit(0 if report['passed'] else 1)
