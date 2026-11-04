"""Full natural-colour regression; exact candidate sources, physical SDRAM model."""
from pathlib import Path
import hashlib,json,struct,subprocess,sys,shutil,uuid,time
from PIL import Image
R=Path(__file__).resolve().parents[1]
MEDIA=R.parent/'board2_adaptive_voice_20261101/media_bbb_20261102'
TOOLS=MEDIA/'tools';sys.path.insert(0,str(TOOLS));import hxjv
hxjv.WIDTH,hxjv.HEIGHT=320,240
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
fixture=R/'sim/natural_fixture';fixture.mkdir(exist_ok=True)
frame_dir=fixture/'jpegs';frame_dir.mkdir(exist_ok=True)
sample=json.loads((MEDIA/'RTL_SAMPLE_CHECK.json').read_text());assert sample['passed']
rtlstage=Path(sample['stage'])
for i,index in enumerate((0,249,499)):
 shutil.copy2(MEDIA/'frames'/f'frame_{index:08d}.jpg',frame_dir/f'{i}.jpg')
 # This golden is the exact candidate JPEG output, independently checked to
 # within two channel levels of the C decoder. Here we test storage/scaling.
 im=Image.open(rtlstage/f'frame{index}_rtl_0.png').convert('RGB')
 px=list(im.getdata());words=[]
 for j in range(0,len(px),2):
  a,b=px[j:j+2];a=((a[0]>>3)<<11)|((a[1]>>2)<<5)|(a[2]>>3)
  b=((b[0]>>3)<<11)|((b[1]>>2)<<5)|(b[2]>>3)
  words.append(a|(b<<16))
 (fixture/f'video{i}_320x240.hex').write_text(''.join(f'{n:08x}\n' for n in words))
player=fixture/'natural.img';hxjv.pack_sequence(frame_dir,player,fps=25)
data=player.read_bytes()
(fixture/'fps30_320x240.hex').write_text(''.join(f'{b:02x}\n' for b in data))
stage=R/'sim_stages'/('natural_'+uuid.uuid4().hex[:8]);cwd=stage/'project';cwd.mkdir(parents=True)
out=R/'sim_logs'/('natural_'+time.strftime('%Y%m%d_%H%M%S'));out.mkdir(parents=True)
names=('video_source.v','video_path.v','mjpeg_video_player.v','media_catalog.v','jpeg_sector_stream.v','sd_sector_cdc.v',
 'rgb565_pack.v','sdram.v','frame_read_write.v','frame_fifo_read.v','frame_fifo_write.v','frame_swap_fx_cdc.v',
 'reset_sync.v','pixel_write_fifo.v','afifo_32_16_256.v','media_viewport.v','video_timing_data.v','video_delay.v',
 'rgb565_unpack.v','native_video_timing.v','word_replicator.v','word_upscaler.v')
files=[R/'src'/n for n in names]+list((R/'src/jpeg').glob('*.v'))+list((R/'user_source/hdl_source/include').glob('*'))
files+=[R/'sim/sdram_retention_model.sv',R/'sim/tb_video_path.sv']
hashes={str(p):sha(p) for p in files if p.is_file()}
for p in files:
 if not p.is_file():continue
 dest=stage/p.relative_to(R);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
bench=stage/'sim/tb_video_path.sv'
s=bench.read_text()
s=s.replace('reg[7:0]image[0:153087];',f'reg[7:0]image[0:{len(data)-1}];')
s=s.replace('addr*512+511>=153088',f'addr*512+511>={len(data)}')
# Explicitly verify the physical-controller contract on all source handshakes
# and App writes; no hardware logic is replaced.
checks='''
 integer collected=0; reg[8:0]row_check,col_check;
 integer app_beat=0; reg[20:0]app_base;
 always @(posedge decode_clk)if(!rst && dut.source.pack_valid && dut.source.pack_ready)begin
  if(collected==0)begin
   if(dut.source.word_col[1:0]!=0)$fatal(1,"unaligned JPEG group");
   row_check=dut.source.word_row;col_check=dut.source.word_col;
  end else if(dut.source.word_row!=row_check || dut.source.word_col!=col_check+collected)
   $fatal(1,"noncontiguous JPEG input group");
  collected=(collected+1)%4;
 end
 always @(posedge mem_clk)if(!rst && dut.app_wr)begin
  if(app_beat==0)begin app_base=dut.wr_addr;if(app_base[1:0]!=0)$fatal(1,"unaligned BL4");end
  else if(dut.wr_addr!=app_base+app_beat)$fatal(1,"noncontiguous BL4 App address");
  app_beat=(app_beat+1)%4;
 end
'''
s=s.replace(' integer rd_req=0,rd_ret=0,wr_app=0;',checks+'\n integer rd_req=0,rd_ret=0,wr_app=0;')
bench.write_text(s)
dest=stage/'sim/fixtures';dest.mkdir(exist_ok=True)
for p in fixture.glob('*.hex'):shutil.copy2(p,dest/p.name);hashes[str(p)]=sha(p)
hashes[str(MEDIA/'RTL_SAMPLE_CHECK.json')]=sha(MEDIA/'RTL_SAMPLE_CHECK.json')
B=Path('E:/Modelsim/modelsim_ase/win32aloem')
commands=[['vlib.exe','work'],['vlog.exe','-permissive',*['../'+p.relative_to(R).as_posix() for p in files if p.suffix=='.v' and p.name!='global_def.v']],
 ['vlog.exe','-sv','../sim/sdram_retention_model.sv','../sim/tb_video_path.sv'],
 ['vsim.exe','-c','-t','1ps','-onfinish','stop','work.tb_video_path','-do','run -all; quit -code 0']]
report=dict(passed=False,stage=str(stage),sources=hashes,staged_bench_sha256=sha(bench),
 scope='Natural-colour first/middle/last BBB frames. Actual JPEG, scaler, FIFOs, encrypted SDRAM controller and physical-pin retained BL4 model; full displayed pixels equal decoded source geometry; independent JPEG C comparison inherited by exact asset identity. Input four-word alignment and physical-controller App BL4 contract assertions. Functional CL2 early-return model paired with existing read_capture_delay=1. No board/HDMI electrical proof.')
start=time.monotonic()
try:
 for i,cmd in enumerate(commands):
  print('RUN',i,out,flush=True)
  with (out/f'{i}.log').open('w') as log:
   p=subprocess.run([str(B/cmd[0]),*cmd[1:]],cwd=cwd,stdout=log,stderr=subprocess.STDOUT,timeout=3600)
  text=(out/f'{i}.log').read_text(errors='replace')
  if p.returncode or '** Error:' in text or '** Fatal:' in text:raise RuntimeError(text[-5000:])
 assert 'PASS video_path ' in text
 assert all(sha(Path(p))==h for p,h in hashes.items())
 report['passed']=True;report['results']=[s for s in text.splitlines() if any(k in s for k in ('JPEG_SWAP','JPEG_FRAME','PASS '))]
 print('\n'.join(report['results']),flush=True)
except Exception as e:report['error']=str(e);print(e,flush=True)
report['elapsed_seconds']=time.monotonic()-start
(out/'summary.json').write_text(json.dumps(report,indent=2))
raise SystemExit(0 if report['passed'] else 1)
