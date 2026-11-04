"""Verify the isolated source delta, implementation, and unchanged old releases."""
from pathlib import Path
import hashlib,json,re,subprocess
R=Path(__file__).resolve().parents[1];A=R/'audit';A.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
baseline=json.loads((R/'BASELINE.json').read_text(encoding='utf8'));base=Path(baseline['source'])
allowed={
 'src/td_project/HX4S20C_Extensions.al',
 'src/user_source/constraints_source/pin.adc','src/user_source/constraints_source/timing.sdc',
 'src/user_source/hdl_source/top_tf_hdmi_audio.v','src/user_source/hdl_source/board_video_controls.v',
 'src/user_source/hdl_source/SD/sd_card_bmp.v',
 *['src/user_source/hdl_source/extensions/'+n for n in ['ir_keymap.v','board_remote_control.v','event_packet_rx.v']]
}
added={'src/user_source/hdl_source/extensions/event_packet_tx.v','src/user_source/hdl_source/extensions/uart_tx.v'}
changed=[];unchanged=[];diff=[]
for e in baseline['sources']:
 p=e['path'];assert sha(base/p)==e['sha256'],'Original baseline changed: '+p
 if sha(R/p)==e['sha256']:unchanged.append(p)
 else:
  changed.append(p);assert p in allowed,'Unexpected production edit: '+p
  q=subprocess.run(['git','diff','--no-index','--',str(base/p),str(R/p)],capture_output=True)
  assert q.returncode==1;diff.append(q.stdout.decode('utf8',errors='replace'))
assert set(changed)==allowed,(changed,allowed)
expected={e['path']for e in baseline['sources']}|added
actual={p.relative_to(R).as_posix()for d in ['src','rtl']for p in(R/d).rglob('*')if p.is_file()}|{'build.tcl'}
assert actual==expected,(actual-expected,expected-actual)
for p in added:
 q=subprocess.run(['git','diff','--no-index','--','NUL',str(R/p)],capture_output=True)
 assert q.returncode==1;diff.append(q.stdout.decode('utf8',errors='replace'))
(A/'production.diff').write_text('\n'.join(diff),encoding='utf8')
stable=R.parent/'phone_ir_fit_link_ack_20261030'
for p in ['board_video_controls.v','extensions/board_remote_control.v','extensions/event_packet_rx.v','extensions/event_packet_tx.v','extensions/uart_tx.v']:
 assert sha(R/'src/user_source/hdl_source'/p)==sha(stable/'src/user_source/hdl_source'/p),p
# Fit is the only album-controller change relative to the accepted HD source.
p='src/user_source/hdl_source/SD/sd_card_bmp.v'
assert (R/p).read_text(encoding='utf8')==(base/p).read_text(encoding='utf8').replace('.KEEP_ASPECT(0)','.KEEP_ASPECT(1)')
build=json.loads((R/'build/hd720_controls_release/manifest.json').read_text(encoding='utf8'))
assert build['pass']and build['timing_closed']and build['setup_ns']>=0 and build['hold_ns']>=0
for e in build['sources']:assert sha(R/e['path'])==e['sha256'],e['path']
area=(R/'build/hd720_controls_release/HX4S20C_UNIFIED_phy.area').read_text()
for port,direction,pad in [('link_ack_tx','OUTPUT','G11'),('link_rx','INPUT','D14'),('ir_in','INPUT','F13')]:
 assert re.search(r'\b'+port+r'\s+'+direction+r'\s+'+pad+r'\s+LVCMOS33',area),(port,pad)
old=[]
for report in [stable/'delivery_fit.json',R.parent/'phone_ir_link_ack_20261030/delivery_phone.json',Path('E:/HX4S20C_Board2/work/link_ack_20261026/build_manifest.json')]:
 d=json.loads(report.read_text(encoding='utf8'))
 if 'file'in d:p=Path(d['file']);h=d['sha256']
 else:p=Path('E:/HX4S20C_Board2/board/build/HX4S20C_Board2_VOICE_LINK_ACK.bit');h=d['bit']['sha256']
 assert sha(p)==h,'Old passed bit changed: '+str(p)
 old.append({'path':str(p),'sha256':h})
result={'pass':True,'baseline':baseline,'unchanged_production_inputs':unchanged,'changed_production_inputs':changed,'added_production_inputs':sorted(added),
 'old_releases_verified':old,'diff':str(A/'production.diff'),'diff_sha256':sha(A/'production.diff'),
 'build_manifest':str(R/'build/hd720_controls_release/manifest.json'),'setup_ns':build['setup_ns'],'hold_ns':build['hold_ns']}
(A/'source_audit.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
print('PASS source audit:',len(unchanged),'unchanged,',len(changed),'changed,',len(added),'added; old releases preserved; pins and positive timing verified.')
