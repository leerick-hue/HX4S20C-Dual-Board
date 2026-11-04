"""Native photo-only source -> real pack/FIFO/DMA/swap, concurrent PCM."""
from pathlib import Path
import hashlib,json,shutil,struct,subprocess,tempfile,time
R=Path(__file__).resolve().parents[1];H=R/'src/user_source/hdl_source';E=H/'extensions'
OLD=R.parent/'media_hd_unified_20261025';B=Path('E:/Modelsim/modelsim_ase/win32aloem')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
out=R/'sim_logs/album720';out.mkdir(parents=True,exist_ok=False)
stage=Path(tempfile.mkdtemp(prefix='hx720_album_'));fixture=stage/'fixtures';fixture.mkdir()
inputs=[OLD/'sim/tb_unified_playback.sv',OLD/'sim/fixtures/combined.img',OLD/'sim/fixtures/pcm_album.hex']
image=(OLD/'sim/fixtures/combined.img').read_bytes()
(fixture/'combined.hex').write_text('\n'.join(f'{b:02x}'for b in image)+'\n')
shutil.copy2(OLD/'sim/fixtures/pcm_album.hex',fixture/'pcm_album.hex')
# Keep the dormant video reference arrays initialized; this release never selects video.
for name in ['video0.hex','video1.hex','video2.hex','pcm_video.hex']:
 shutil.copy2(OLD/'sim/fixtures'/name,fixture/name)
for n in range(2):
 p=OLD/f'sim/fixtures/photo{n}.bmp';inputs.append(p);bmp=p.read_bytes()
 off=struct.unpack_from('<I',bmp,10)[0];w,raw_h=struct.unpack_from('<ii',bmp,18);h=abs(raw_h);stride=(w*3+3)&~3
 fw,fh=1280,720
 if w*720>h*1280:fh=max(1,h*1280//w)
 elif w*720<h*1280:fw=max(1,w*720//h)
 ox,oy=(1280-fw)//2,(720-fh)//2
 def pixel(x,y):
  if not(ox<=x<ox+fw and oy<=y<oy+fh):return 0
  sx,sy=(x-ox)*w//fw,(y-oy)*h//fh
  if raw_h>0:sy=h-1-sy
  b,g,r=bmp[off+sy*stride+sx*3:off+sy*stride+sx*3+3]
  return ((r>>3)<<11)|((g>>2)<<5)|(b>>3)
 with (fixture/f'photo{n}.hex').open('w')as f:
  for y in range(720):
   for x in range(0,1280,2):f.write(f'{pixel(x,y)|(pixel(x+1,y)<<16):08x}\n')
s=(OLD/'sim/tb_unified_playback.sv').read_text()
changes=[
 ('always #20 vclk','always #6.734007 vclk'),('always #4 mclk','always #10 mclk'),
 ('#(.CLK_FREQ_HZ(4000))','#(.ENABLE_VIDEO(0),.CLK_FREQ_HZ(4000))'),
 ('active_video?2+source.video_player.frame_index:source.album.load_idx','source.album.load_idx'),
 ("active_video?32'd8+source.video_player.audio_start:32'd4","32'd4"),
 ('active_video?4800:512','512'),
 ('  // Deliberately cancel a fourth photo while both an SD sector and a partial',
 '''  @(negedge vclk);play=0;repeat(20)@(negedge vclk);dummy=playhead;
  #2000000;if(playhead!=dummy || commits!=3 || playing)$fatal(1,"photo pause changed playhead/display");
  @(negedge vclk);play=1;wait(playing);repeat(100)@(negedge vclk);
  if(photo_pcm_samples<512 || fade_completed!=2 || underruns)$fatal(1,"photo PCM/fade coverage");
  $display("PASS album720: three complete1280x720 fit photos,1382400 unique RGB565 words, manual next, auto wrap/off, both BMP orientations, bank ownership, real40/50/74.25/100MHz clocks, shared SD CDC/PCM/FIFO/DMA/swap/fade, pause/resume, zero underruns (%0d PCM)",photo_pcm_samples);
  $finish;
  // Deliberately cancel a fourth photo while both an SD sector and a partial''')]
for a,b in changes:assert a in s,a;s=s.replace(a,b)
bench=R/'sim/tb_album720.sv';bench.write_text(s,encoding='utf8')
files=[R/'rtl'/n for n in ['media_catalog.v','media_mode_reset.v','unified_media_source.v','sd_sector_cdc.v','hxjv_pcm_player.v']]
files += [H/'SD/sd_card_bmp.v',H/'SD/bmp_read_scaled.v',H/'SD/frame_fifo_write.v',H/'pixel_write_fifo.v']
files += [E/n for n in ['bmp24_scale_stream.v','sd_sector_arbiter.v','audio_pcm_fifo.v','rgb565_pack.v','reset_sync.v','frame_swap_fx_cdc.v']]
inputs+=files+[bench]
rec={'pass':False,'stage':str(stage),'sources':{str(p):sha(p)for p in inputs},'derivation_replacements':changes,
 'scope':'Actual production source/catalog/scaler/sector CDC/PCM/pack/FIFO/write DMA/swap with native720 size and actual clock rates. Synthetic SD sector bytes and memory busy/app acceptance; accelerated auto timer/vblank/reset. Excludes physical SD init, SDRAM chip/read PHY and actual HDMI/display.'}
start=time.monotonic()
commands=[['vlib.exe','work'],['vlog.exe','-sv',*map(str,files),str(bench)],['vsim.exe','-c','-t','1ps','-onfinish','stop','work.tb_unified_playback','+IMAGE=fixtures/combined.hex',f'+BYTES={len(image)}','+FIXTURE=fixtures','-do','onerror {quit -code 1}; run -all; quit -code 0']]
try:
 for i,c in enumerate(commands):
  print('album720 step',i,flush=True)
  p=subprocess.run([str(B/c[0]),*c[1:]],cwd=stage,capture_output=True,timeout=1200)
  log=(p.stdout+p.stderr).decode(errors='replace');(out/f'{i}.log').write_text(log,encoding='utf8')
  assert not p.returncode and '** Error:'not in log and '** Fatal:'not in log,log[-7000:]
 assert 'PASS album720:'in log,log[-3000:]
 assert all(sha(Path(p))==h for p,h in rec['sources'].items())
 frames=[]
 for n,asset in enumerate([0,1,0]):
  frame=stage/f'frame_{n}.hex';expected=fixture/f'photo{asset}.hex'
  assert frame.read_text().lower()==expected.read_text().lower(),f'frame {n}'
  frames.append({'commit':n,'words':460800,'sha256':sha(frame),'reference_sha256':sha(expected)})
 rec.update({'pass':True,'frames':frames,'markers':[l for l in log.splitlines()if any(v in l for v in ['METRIC','PASS '])]})
 print('\n'.join(rec['markers']),flush=True)
except Exception as e:rec['error']=str(e);print(str(e)[-7000:],flush=True)
finally:
 rec['wall_seconds']=time.monotonic()-start;(out/'summary.json').write_text(json.dumps(rec,indent=2)+'\n',encoding='utf8')
raise SystemExit(0 if rec['pass']else 1)
