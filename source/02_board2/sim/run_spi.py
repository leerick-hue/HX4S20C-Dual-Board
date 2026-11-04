from pathlib import Path
import hashlib,json,shutil,subprocess,tempfile,time
R=Path(__file__).resolve().parents[1];B=Path('E:/Modelsim/modelsim_ase/win32aloem')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
files=[R/'src'/n for n in ('sd_card_top.v','sd_card_sec_read_write.v','sd_card_cmd.v','spi_master.v')]+[R/'sim/tb_spi_read.sv']
out=R/'sim_logs'/time.strftime('spi_%Y%m%d_%H%M%S');out.mkdir(parents=True)
stage=Path(tempfile.mkdtemp(prefix='hx_video_spi_'));hashes={str(p):sha(p) for p in files}
for p in files:shutil.copy2(p,stage/p.name)
commands=[['vlib.exe','work'],['vlog.exe','-sv','-permissive',*[p.name for p in files]],['vsim.exe','-c','-t','1ps','-onfinish','stop','work.tb_spi_read','-do','run -all; quit -code 0']]
report=dict(passed=False,sources=hashes,stage=str(stage),scope='Production SD initialization, command, sector and SPI RTL; digital MISO/MOSI/SCK/CS card model for SDHC/SDSC v1/v2 and missing token retry; production dividers and power-up count; token timeout accelerated to2048 cycles. Not physical-card latency/reliability proof.')
try:
 for i,c in enumerate(commands):
  run=subprocess.run([str(B/c[0]),*c[1:]],cwd=stage,capture_output=True,timeout=180)
  log=(run.stdout+run.stderr).decode(errors='replace');(out/f'{i}.log').write_text(log,encoding='utf8')
  if run.returncode or '** Error:' in log or '** Fatal:' in log:raise RuntimeError(log[-5000:])
 assert 'PASS spi_read' in log,log[-5000:]
 assert all(sha(Path(p))==h for p,h in hashes.items())
 report['passed']=True;report['results']=[s for s in log.splitlines() if 'PASS' in s];print('\n'.join(report['results']))
except Exception as e:report['error']=str(e);print(str(e))
(out/'summary.json').write_text(json.dumps(report,indent=2),encoding='utf8');raise SystemExit(0 if report['passed'] else 1)
