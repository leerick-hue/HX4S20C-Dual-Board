"""640x480@15 full-path regression; requires completed media/RTL_SAMPLE_CHECK.json."""
from pathlib import Path
import hashlib,json,os,shutil,struct,subprocess,sys,time,uuid
from PIL import Image
RATE='--rate' in sys.argv
R=Path(__file__).resolve().parents[1]
MEDIA=R/'media'
B=Path('E:/Modelsim/modelsim_ase/win32aloem')
sys.path.insert(0,str(R.parent/'tools'))
import hxjv
hxjv.WIDTH,hxjv.HEIGHT=640,480
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
sample_path=MEDIA/'RTL_SAMPLE_CHECK.json'
sample=json.loads(sample_path.read_text());assert sample['passed'], 'RTL/C sample validation must pass first'
indices=sample['indices'];assert len(indices)>=3
indices=[indices[0],indices[(len(indices)-1)//2],indices[-1]]
assert len(set(indices))==3
rtlstage=Path(sample['stage'])
stage=R/'sim_stages'/(('rate480_' if RATE else 'video480_')+uuid.uuid4().hex[:8]);cwd=stage/'project';cwd.mkdir(parents=True)
out=R/'sim_logs'/(('rate480_' if RATE else 'video480_')+time.strftime('%Y%m%d_%H%M%S'));out.mkdir(parents=True)
fixture=stage/'sim/fixtures';frames=fixture/'jpegs';frames.mkdir(parents=True)
hashes={str(sample_path):sha(sample_path)}
for i,index in enumerate(indices):
 jpeg=MEDIA/'frames'/f'frame_{index:08d}.jpg';gold=rtlstage/f'frame{index}_rtl_0.png'
 hashes[str(jpeg)]=sha(jpeg);hashes[str(gold)]=sha(gold)
 shutil.copy2(jpeg,frames/f'{i:08d}.jpg')
 im=Image.open(gold).convert('RGB');assert im.size==(640,480)
 px=list(im.getdata());words=[]
 for j in range(0,len(px),2):
  a,b=px[j:j+2]
  a=((a[0]>>3)<<11)|((a[1]>>2)<<5)|(a[2]>>3)
  b=((b[0]>>3)<<11)|((b[1]>>2)<<5)|(b[2]>>3)
  words.append(a|(b<<16))
 (fixture/f'video{i}_640x480.hex').write_text(''.join(f'{v:08x}\n' for v in words))
player=fixture/'short_hxjv.img';hxjv.pack_sequence(frames,player,fps=15)
prefix_path=Path(os.environ.get('HX_480_PREFIX_CARD',str(R.parent/'board2_adaptive_voice_20261101/media_bbb_20261102/DELIVERY/CARD_BBB_20s_320x240_25fps.img')))
hashes[str(prefix_path)]=sha(prefix_path)
with prefix_path.open('rb') as f:prefix=bytearray(f.read(4096))
assert len(prefix)==4096 and prefix[:4]==b'HXAU'
# Preserve the parent's album prefix but advertise the shortened video at LBA8.
# The bench never requests photo/audio sectors; disable that soundtrack metadata.
struct.pack_into('<II',prefix,20,8,0)
struct.pack_into('<I',prefix,28,8)
segment=player.read_bytes();video_sectors=len(segment)//512
struct.pack_into('<4sIII',prefix,36,b'HXUV',8,video_sectors,8+video_sectors)
data=bytes(prefix)+segment
(fixture/'card480.img').write_bytes(data)
(fixture/'card480.hex').write_text(''.join(f'{v:02x}\n' for v in data))
names=('video_source.v','video_path.v','mjpeg_video_player.v','media_catalog.v','jpeg_sector_stream.v','sd_sector_cdc.v','rgb565_pack.v','sdram.v','frame_read_write.v','frame_fifo_read.v','frame_fifo_write.v','frame_swap_fx_cdc.v','reset_sync.v','pixel_write_fifo.v','afifo_32_16_256.v','media_viewport.v','video_timing_data.v','video_delay.v','rgb565_unpack.v','native_video_timing.v')
files=[R/'src'/n for n in names]+list((R/'src/jpeg').glob('*.v'))+list((R/'user_source/hdl_source/include').glob('*'))+[R/'sim/sdram_retention_model.sv',R/'sim/tb_video_path.sv']
for p in files:
 if not p.is_file():continue
 hashes[str(p)]=sha(p);dest=stage/p.relative_to(R);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
commands=[['vlib.exe','work'],['vlog.exe','-permissive',*['../'+p.relative_to(R).as_posix() for p in files if p.suffix=='.v' and p.name!='global_def.v']],['vlog.exe','-sv','../sim/sdram_retention_model.sv','../sim/tb_video_path.sv'],['vsim.exe','-c','-t','1ps',f'-gCARD_BYTES={len(data)}',f'-gRATE_TEST={int(RATE)}',f'-gSECTOR_FIXED_US={int(os.environ.get("HX_SECTOR_FIXED_US","0"))}',f'-gSECTOR_JITTER_US={int(os.environ.get("HX_SECTOR_JITTER_US","50"))}','-onfinish','stop','work.tb_video_path','-do','run -all; quit -code 0']]
report=dict(passed=False,rate_test=RATE,sector_fixed_us=int(os.environ.get("HX_SECTOR_FIXED_US","0")),sector_jitter_us=int(os.environ.get("HX_SECTOR_JITTER_US","50")),stage=str(stage),indices=indices,card_bytes=len(data),sources=hashes,scope='Actual JPEG, native RGB565 pack/unpack, sector CDC, FIFOs, encrypted controller and retained physical-pin SDRAM BL4 model. First/middle/last independently C-checked RTL sample PNGs are exact golden. Every 720p pixel including centred 640x480 window and black border, each frame address, source/App BL4 continuity, front-bank isolation, freeze/resume and loop checked. Ideal clocks; synthetic sector byte360ns without physical TF token/command latency; CL2 early-return fault-injection model with existing capture delay; excludes HDMI electrical and hardware timing proof.')
start=time.monotonic()
try:
 for i,cmd in enumerate(commands):
  print('RUN',i,'OUT',out,'STAGE',stage,flush=True)
  with (out/f'{i}.log').open('w') as log:
   proc=subprocess.run([str(B/cmd[0]),*cmd[1:]],cwd=cwd,stdout=log,stderr=subprocess.STDOUT,timeout=int(os.environ.get('HX_SIM_TIMEOUT','5400')))
  text=(out/f'{i}.log').read_text(errors='replace')
  if proc.returncode or '** Error:' in text or '** Fatal:' in text:raise RuntimeError(text[-6000:])
 assert ('PASS video_path_rate ' if RATE else 'PASS video_path ') in text,text[-6000:]
 assert all(sha(Path(p))==h for p,h in hashes.items()),'Source or golden changed during run'
 report['passed']=True;report['results']=[line for line in text.splitlines() if any(k in line for k in ('JPEG_SWAP','JPEG_FRAME','DECODE_DRAIN','DECODE_DUE','PASS '))]
 print('\n'.join(report['results']),flush=True)
except Exception as e:report['error']=str(e);print(e,flush=True)
report['elapsed_seconds']=time.monotonic()-start
(out/'summary.json').write_text(json.dumps(report,indent=2))
raise SystemExit(0 if report['passed'] else 1)
