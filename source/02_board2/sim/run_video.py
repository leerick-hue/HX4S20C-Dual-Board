from pathlib import Path
import hashlib,json,os,shutil,subprocess,tempfile,time
SIM_TIMEOUT=int(os.environ.get('HX_SIM_TIMEOUT','1800'))
ASPECT=os.environ.get('HX_ASPECT_16X9','0')
R=Path(__file__).resolve().parents[1];B=Path('E:/Modelsim/modelsim_ase/win32aloem')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
files=[R/'src'/n for n in ('video_source.v','video_path.v','mjpeg_video_player.v','media_catalog.v','jpeg_sector_stream.v','sd_sector_cdc.v','rgb565_pack.v','sdram.v','frame_read_write.v','frame_fifo_read.v','frame_fifo_write.v','frame_swap_fx_cdc.v','reset_sync.v','pixel_write_fifo.v','afifo_32_16_256.v','media_viewport.v','video_timing_data.v','video_delay.v','rgb565_unpack.v','native_video_timing.v','word_replicator.v','word_upscaler.v')]
files+=list((R/'src/jpeg').glob('*.v'))+list((R/'user_source/hdl_source/include').glob('*'))+[R/'sim/sdram_retention_model.sv',R/'sim/tb_video_path.sv']
fixtures=list((R/'sim/fixtures').glob('*'))
stage=Path(tempfile.mkdtemp(prefix='hx_video_path_'));cwd=stage/'project';cwd.mkdir()
out=R/'sim_logs'/f"{time.strftime('video_%Y%m%d_%H%M%S')}_a{ASPECT}";out.mkdir(parents=True)
hashes={str(p.relative_to(R)):sha(p) for p in files+fixtures if p.is_file()}
for p in files+fixtures:
 if p.is_file():
  d=stage/p.relative_to(R);d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,d)
commands=[['vlib.exe','work'],['vlog.exe','-permissive',*[('../'+p.relative_to(R).as_posix()) for p in files if p.suffix=='.v' and p.name!='global_def.v']],['vlog.exe','-sv','-permissive',*[('../'+p.relative_to(R).as_posix()) for p in files if p.suffix=='.sv']],['vsim.exe','-c','-t','1ps','-gASPECT_16X9='+ASPECT,'-gHOLD_FREEZE='+os.environ.get('HX_HOLD_FREEZE','0'),'-onfinish','stop','work.tb_video_path','-do','run -all; quit -code 0']]
report=dict(passed=False,aspect_16x9=ASPECT,stage=str(stage),sources=hashes,scope='Actual JPEG/catalog/sector CDC/packer/SDRAM controller/FIFOs/scanout; synthetic sector byte360ns; functional retained early-return memory; ideal 100/40/50/74.25MHz clocks. Every stored word and displayed pixel is predicted from the pixel stream of the decoder itself (scaler geometry model), plus golden colour per source word. Excludes physical TF/SPI, HDMI/PLL/SDF.')
start=time.monotonic()
try:
 for i,c in enumerate(commands):
  print('RUN',i,c[0],out,flush=True)
  if i==len(commands)-1:
   # Stream the simulation transcript so a hang leaves readable progress instead
   # of a lost capture_output buffer.
   with open(out/f'{i}.log','w',encoding='utf8') as fh:
    proc=subprocess.Popen([str(B/c[0]),*c[1:]],cwd=cwd,stdout=fh,stderr=subprocess.STDOUT,text=True,errors='replace')
    deadline=time.monotonic()+SIM_TIMEOUT
    while proc.poll() is None:
     if time.monotonic()>deadline:
      proc.kill();raise RuntimeError(f'vsim timed out after {SIM_TIMEOUT}s; partial log follows\n'+open(out/f'{i}.log',encoding='utf8',errors='replace').read()[-6000:])
     time.sleep(5)
    log=open(out/f'{i}.log',encoding='utf8',errors='replace').read()
   if proc.returncode or '** Error:' in log or '** Fatal:' in log:raise RuntimeError(log[-5000:])
  else:
   run=subprocess.run([str(B/c[0]),*c[1:]],cwd=cwd,capture_output=True,timeout=1800)
   log=(run.stdout+run.stderr).decode(errors='replace');(out/f'{i}.log').write_text(log,encoding='utf8')
   if run.returncode or '** Error:' in log or '** Fatal:' in log:raise RuntimeError(log[-5000:])
 assert 'PASS video_path' in log,log[-5000:]
 assert all(sha(R/p)==h for p,h in hashes.items())
 report['passed']=True;report['results']=[s for s in log.splitlines() if any(t in s for t in ('JPEG_SWAP','JPEG_FRAME','PASS '))];print('\n'.join(report['results']),flush=True)
except Exception as e:report['error']=str(e);print(str(e),flush=True)
report['elapsed_seconds']=time.monotonic()-start;(out/'summary.json').write_text(json.dumps(report,indent=2),encoding='utf8')
raise SystemExit(0 if report['passed'] else 1)
