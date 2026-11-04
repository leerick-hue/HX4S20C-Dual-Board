from pathlib import Path
import hashlib,json,shutil,subprocess,tempfile,time
R=Path(__file__).resolve().parents[1];B=Path('E:/Modelsim/modelsim_ase/win32aloem')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
names=['sd_card_top.v','sd_card_sec_read_write.v','sd_card_cmd.v','spi_master.v',
       'video_source.v','sd_sector_cdc.v','reset_sync.v','media_catalog.v','mjpeg_video_player.v','jpeg_sector_stream.v','rgb565_pack.v']
files=[R/'src'/n for n in names]+sorted((R/'src/jpeg').glob('*.v'))+[R/'sim/tb_card_boundary.sv']
fixtures=[R/'sim/fixtures/card_boot.hex',R/'sim/fixtures/card_boot.json']
out=R/'sim_logs'/time.strftime('boundary_%Y%m%d_%H%M%S');out.mkdir(parents=True)
stage=Path(tempfile.mkdtemp(prefix='hx_video_boundary_'));hashes={str(p):sha(p) for p in files+fixtures}
for p in files+fixtures:shutil.copy2(p,stage/p.name)
commands=[['vlib.exe','work'],['vlog.exe','-sv','-permissive',*[p.name for p in files]],['vsim.exe','-c','-t','1ps','-onfinish','stop','work.tb_card_boundary','-do','run -all; quit -code 0']]
report=dict(passed=False,sources=hashes,stage=str(stage),scope='Actual SPI pins -> production SD controller -> 100/40MHz sector CDC -> media catalog -> JPEG player header/index/stream -> first complete RGB565 frame. Exact sectors from local production image. Checks all 153600 word addresses exactly once, known data and swap readiness; synthetic memory completion. Digital SDHC model, no physical card or SDRAM/HDMI.')
try:
 for i,c in enumerate(commands):
  run=subprocess.run([str(B/c[0]),*c[1:]],cwd=stage,capture_output=True,timeout=180)
  log=(run.stdout+run.stderr).decode(errors='replace');(out/f'{i}.log').write_text(log,encoding='utf8')
  if run.returncode or '** Error:' in log or '** Fatal:' in log:raise RuntimeError(log[-5000:])
 assert 'PASS card_boundary' in log,log[-5000:]
 assert all(sha(Path(p))==h for p,h in hashes.items())
 report['passed']=True;report['results']=[s for s in log.splitlines() if 'PASS' in s or 'CARD_CMD17' in s];print('\n'.join(report['results']))
except Exception as e:report['error']=str(e);print(str(e))
(out/'summary.json').write_text(json.dumps(report,indent=2),encoding='utf8');raise SystemExit(0 if report['passed'] else 1)
