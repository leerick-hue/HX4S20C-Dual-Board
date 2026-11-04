"""Retain pre-hold-repair implementation as a controlled hardware comparison."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re,shutil
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
folder=R/'build/hd720_controls_seed11';m=json.loads((folder/'manifest.json').read_text(encoding='utf8'))
post=json.loads((R/'build/hd720_controls_release/manifest.json').read_text(encoding='utf8'))
assert m['pass']and m['sources']==post['sources']
for e in m['sources']:assert sha(R/e['path'])==e['sha256']
timing=(folder/'HX4S20C_UNIFIED_pr.timing').read_text(encoding='utf8')
setup=float(re.search(r'SWNS:\s*([-\d.]+)ns',timing)[1]);hold=float(re.search(r'HWNS:\s*([-\d.]+)ns',timing)[1])
assert setup>=0 and hold>=0,(setup,hold)
src=folder/'HX4S20C_UNIFIED_TEST.bit';h=sha(src);assert h==m['bit_sha256']
reports=[]
for n in ['keymap','infrared','ack','scale','ui','album720','acr_service_top']:
 p=R/'sim_logs'/n/'summary.json';d=json.loads(p.read_text(encoding='utf8'));assert d['pass']
 for f,s in d['sources'].items():assert sha(Path(f))==s
 reports.append({'name':n,'path':str(p),'sha256':sha(p)})
accepted=Path('E:/HX4S20C_Test_20261026/HX4S20C_HD720_PHOTO_PROBE_99A489D0.bit')
assert sha(accepted)=='99a489d0428e81c2a8743799121c56b3ae898ae9418aef6a6d9c35c0bd8a1a4c'
target=R.parent/f'build/HX4S20C_HD720_LINK_ACK_ROUTE_{h[:8].upper()}.bit'
assert not target.exists();shutil.copy2(src,target);assert sha(target)==h
report={'utc':datetime.now(timezone.utc).isoformat(),'status':'Controlled pre-hold-repair comparison; not a confirmed fix',
 'file':str(target),'sha256':h,'source_manifest':str(folder/'manifest.json'),'source_manifest_sha256':sha(folder/'manifest.json'),
 'sources_identical_to_failed_candidate':True,'setup_ns':setup,'hold_ns':hold,'timing_coverage_percent':99.96,'simulations':reports,
 'only_build_flow_difference':'Use original routed bit before fix_hold -clock_opt. No source, constraint, seed, clock, pin or feature changes.',
 'hypothesis':'Post-route repair inserted buffers on HDMI reset and video-input FIFO paths. Controlled comparison tests this implementation delta; causality not established.',
 'hardware_accepted':False,'hardware_programmed_by_agent':False,
 'known_failed_bit_sha256':post['bit_sha256'],'accepted_rollback':str(accepted),'old_baseline_sha256':sha(accepted)}
(R/'delivery_route_comparison.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
print(json.dumps({'file':str(target),'sha256':h,'setup_ns':setup,'hold_ns':hold},ensure_ascii=False),flush=True)
