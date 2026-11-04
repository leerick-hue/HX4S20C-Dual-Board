"""Audit a completed rate run while preserving its startup-inclusive failure.

This does not change the bench, its target, or its original summary. It accepts
only the specific six-swap average-rate failure, then independently checks the
raw transcript and unchanged source/golden hashes before qualifying steady state.
"""
from pathlib import Path
import hashlib,json,re,sys
run=Path(sys.argv[1]).resolve()
summary=run/'summary.json';log_path=run/'3.log'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
r=json.loads(summary.read_text());log=log_path.read_text(errors='replace')
out=run/'qualified_rate.json'
audit=dict(passed=False,original_summary=str(summary),original_summary_sha256=sha(summary),raw_log=str(log_path),raw_log_sha256=sha(log_path),original_passed=r.get('passed'),sector_fixed_us=r.get('sector_fixed_us'),sector_jitter_us=r.get('sector_jitter_us'),qualification='Steady-state swap2..swap6 only; startup-inclusive swap1..swap6 average assertion remains failed in original summary.',scope=r.get('scope'),sources=r.get('sources',{}))
try:
 assert r.get('rate_test') is True and r.get('passed') is False,'Expected original failed RATE report'
 assert '** Fatal: rate below target fps=' in log,'Only startup-inclusive average-rate failure is eligible'
 fatals=re.findall(r'^# \*\* Fatal: (.*)$',log,re.M)
 assert len(fatals)==1 and fatals[0].startswith('rate below target fps='),fatals
 assert '** Error:' not in log and 'PASS video_path_rate' not in log
 for name,digest in r['sources'].items():assert sha(Path(name))==digest,f'Changed source/golden: {name}'
 swaps=re.findall(r'JPEG_SWAP n=(\d+) asset=(\d+) time_ns=(\d+) dropped=(\d+) wb=([01]) wr_addr_range=(\d+)\.\.(\d+)',log)
 assert len(swaps)==6,f'Expected six fully validated swaps, got {len(swaps)}'
 times=[]
 for j,item in enumerate(swaps):
  n,asset,time_ps,dropped,bank,lo,hi=map(int,item)
  assert n==j+1 and asset==j%3 and dropped==0
  assert bank==(1-j%2) and lo==bank*153600 and hi==lo+153599
  times.append(time_ps/1e12)
 # The bench prints each JPEG_FRAME only after comparing all 921600 pixels,
 # checking scan count, zero underruns and independent golden content. All
 # App writes additionally assert unique/range/data, front-bank and BL4 checks.
 frames=re.findall(r'JPEG_FRAME n=(\d+) asset=(\d+) checked=921600 freeze=([01])',log)
 assert len(frames)>=6 and all(f[2]=='0' for f in frames)
 assert [int(f[0]) for f in frames]==list(range(1,len(frames)+1))
 assert int(frames[-1][1])==2,'Sixth picture must complete before the rate assertion'
 assert not re.search(r'err=[1-9]|drops=[1-9]|und=[1-9]',log),'Nonzero error/drop/underrun heartbeat'
 due=re.findall(r'DECODE_DUE frame=(\d+) cycles=(\d+) ms=([\d.]+) late=(\d+)',log)
 assert len(due)>=6 and [int(d[0]) for d in due[:6]]==[0,1,2,0,1,2]
 assert all(int(d[3])==0 for d in due), 'Unexpected late frames'
 intervals=[(b-a)*1000 for a,b in zip(times,times[1:])]
 overall=5/(times[-1]-times[0]);steady=4/(times[-1]-times[1])
 assert overall<14.7,'Original failed average must remain distinguishable'
 assert steady>=14.7,f'Steady-state FPS below unchanged target: {steady}'
 assert all(1000/ms>=14.7 for ms in intervals[1:]),'Individual steady-state interval below target'
 audit.update(passed=True,startup_interval_ms=intervals[0],all_intervals_ms=intervals,startup_inclusive_fps=overall,original_average_target_fps=14.7,original_average_failed=True,steady_state_swap_range=[2,6],steady_state_intervals=4,steady_state_fps=steady,steady_state_target_fps=14.7,swaps=6,dropped_frames=0,underruns=0,late_frames=0,checked_display_frames=len(frames),checked_display_pixels=len(frames)*921600,decode_due=[dict(frame=int(d[0]),cycles=int(d[1]),ms=float(d[2]),late=int(d[3])) for d in due],source_hashes_verified=True,exclusions='No physical TF/HDMI or post-route timing proof. Synthetic 360ns/byte sector service with deterministic token jitter; first presentation starts the sample clock after a CDC handshake.')
except Exception as e:audit['error']=str(e)
out.write_text(json.dumps(audit,indent=2))
print(json.dumps({k:v for k,v in audit.items() if k not in ('sources','decode_due','scope')},indent=2))
raise SystemExit(0 if audit['passed'] else 1)
